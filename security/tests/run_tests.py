#!/usr/bin/env python3
"""
Testes de regressão das regras de segurança (Semgrep + Gitleaks + deps diretas).

Garante que as regras em security/ não geram falsos positivos (FP) nem falsos
negativos (FN). Como essas regras rodam em TODOS os repos da org (Required
Workflow), qualquer mudança nelas precisa passar aqui antes do merge na main.

Como funciona
-------------
1. Os arquivos em security/tests/cases/ formam um "repo falso": o caminho
   dentro de cases/ é o caminho no repo (ex.: cases/src/__tests__/a.test.ts).
2. Cada linha que deve (ou não) ser detectada é precedida por uma anotação:

       // ruleid: <regra>[, <regra>...]     -> DEVE ser detectada
       // ok: <regra>[, <regra>...]         -> NÃO pode ser detectada
       // todoruleid: <regra>               -> gap conhecido (FN aceito por enquanto)
       // todook: <regra>                   -> FP conhecido (aceito por enquanto)

   O prefixo do comentário pode ser #, //, <!--, /*, -- ou *.
   Regras que começam com "devsecops." são do Semgrep; as demais, do Gitleaks.
   Qualquer achado numa linha sem "ruleid"/"todook" para aquela regra é FP.

3. Segredos de teste NÃO são commitados: use {{rand:N}} (alfanumérico),
   {{upper:N}} (A-Z0-9), {{lower:N}} (a-z0-9) ou {{hex:N}}. O valor é gerado
   de forma determinística na hora do teste, sem palavras que as regras
   ignoram (test, fake, example...).
4. Um arquivo pode declarar outro caminho de destino na 1ª linha com
   "# path: src/.env" (útil para nomes que não queremos commitar).
5. O scan roda com os mesmos argumentos do workflow de produção
   (.github/workflows/alpha-security.yaml), num repositório git temporário,
   com as configs em devsecops/security/ como no CI.

Uso
---
    python3 security/tests/run_tests.py            # tudo
    python3 security/tests/run_tests.py semgrep    # só uma suíte (semgrep|gitleaks|deps)
    python3 security/tests/run_tests.py -v         # mostra também os gaps conhecidos

Requer: semgrep, gitleaks, git, jq (para a suíte deps) e bash.
"""
from __future__ import annotations

import json
import os
import random
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SECURITY = ROOT / "security"
CASES = SECURITY / "tests" / "cases"
DEPS_CASES = SECURITY / "tests" / "deps"
WORKFLOW = ROOT / ".github" / "workflows" / "alpha-security.yaml"

GH = os.environ.get("GITHUB_ACTIONS") == "true"

ANNOTATION_RE = re.compile(
    r"^\s*(?:#|//|<!--|/\*|--|\*)\s*(ruleid|ok|todoruleid|todook)\s*:\s*(.+?)\s*(?:-->|\*/)?\s*$"
)
PATH_RE = re.compile(r"^\s*(?:#|//|<!--|/\*|--)\s*path\s*:\s*(\S+)")
PLACEHOLDER_RE = re.compile(r"\{\{(rand|upper|lower|hex):(\d+)\}\}")
# Palavras que fazem as regras ignorarem o valor — não podem aparecer no aleatório.
SKIPWORDS_RE = re.compile(
    r"(?i)(example|placeholder|dummy|changeme|test|fake|sample|xxxx|todo|fixme|replace|your|0{16}|1{16}|a{16})"
)
ALPHABETS = {
    "rand": "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
    "upper": "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    "lower": "abcdefghijklmnopqrstuvwxyz0123456789",
    "hex": "0123456789abcdef",
}


# ─────────────────────────────────────────────────────────────
# Saída
# ─────────────────────────────────────────────────────────────
def c(code: str, text: str) -> str:
    if GH or sys.stdout.isatty():
        return f"\033[{code}m{text}\033[0m"
    return text


RED, GREEN, YELLOW, DIM, BOLD = "0;31", "0;32", "1;33", "2", "1"


@dataclass
class Problem:
    kind: str  # FP | FN | PROMOTE | ERROR
    suite: str
    file: str  # caminho no repo DevSecOps (para anotação)
    line: int
    rule: str
    detail: str


@dataclass
class Report:
    problems: list[Problem] = field(default_factory=list)
    gaps: list[Problem] = field(default_factory=list)  # todoruleid/todook ainda válidos
    checked: dict[str, int] = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)


# ─────────────────────────────────────────────────────────────
# Casos (Semgrep + Gitleaks)
# ─────────────────────────────────────────────────────────────
@dataclass
class Expectation:
    kind: str  # ruleid | ok | todoruleid | todook
    rule: str
    src: Path  # arquivo em cases/
    src_line: int  # linha da anotação em cases/ (para apontar o erro)


def tool_of(rule: str) -> str:
    return "semgrep" if rule.startswith("devsecops.") else "gitleaks"


def group_of(rule: str) -> str:
    """O Gitleaks deduplica achados das regras 'generic-*' que pegam o mesmo segredo,
    então qual delas aparece varia. Para a comparação, elas contam como uma só."""
    if tool_of(rule) == "gitleaks" and rule.startswith("generic-"):
        return "gitleaks:generic-*"
    return rule


def expand_placeholders(text: str, seed: str) -> str:
    def repl(m: re.Match) -> str:
        kind, n = m.group(1), int(m.group(2))
        alphabet = ALPHABETS[kind]
        rng = random.Random(f"{seed}:{m.start()}")
        while True:
            value = "".join(rng.choice(alphabet) for _ in range(n))
            if not SKIPWORDS_RE.search(value):
                return value

    return PLACEHOLDER_RE.sub(repl, text)


def load_rule_ids() -> dict[str, set[str]]:
    sem = set(re.findall(r"^\s*-\s*id:\s*(\S+)", (SECURITY / "semgrep.yml").read_text(), re.M))
    gl = set(re.findall(r'^\s*id\s*=\s*"([^"]+)"', (SECURITY / "gitleaks.toml").read_text(), re.M))
    return {"semgrep": sem, "gitleaks": gl}


def prod_semgrep_excludes() -> list[str]:
    """Lê os --exclude do comando semgrep do workflow de produção (evita divergência)."""
    text = WORKFLOW.read_text()
    m = re.search(r"semgrep scan \\\n(.*?)&\n", text, re.S)
    if not m:
        raise SystemExit(f"Não achei o comando 'semgrep scan' em {WORKFLOW}")
    excludes = []
    for line in m.group(1).splitlines():
        parts = shlex.split(line.strip().rstrip("\\"))
        for i, p in enumerate(parts):
            if p == "--exclude" and i + 1 < len(parts):
                excludes.append(parts[i + 1])
    return excludes


def build_fake_repo(tmp: Path, known: dict[str, set[str]], report: Report):
    """Copia os casos para tmp (repo falso) e devolve {(dest, linha): [Expectation]}."""
    expectations: dict[tuple[str, int], list[Expectation]] = {}
    dest_to_src: dict[str, Path] = {}

    for src in sorted(p for p in CASES.rglob("*") if p.is_file()):
        rel = src.relative_to(CASES).as_posix()
        text = src.read_text()
        lines = text.splitlines()
        if lines and (m := PATH_RE.match(lines[0])):
            rel = m.group(1)
        dest_to_src[rel] = src

        pending: list[Expectation] = []
        for idx, line in enumerate(lines, start=1):
            m = ANNOTATION_RE.match(line)
            if m:
                kind, rules = m.group(1), m.group(2)
                for rule in (r.strip() for r in rules.split(",") if r.strip()):
                    if rule not in known[tool_of(rule)]:
                        report.problems.append(Problem(
                            "ERROR", tool_of(rule), str(src.relative_to(ROOT)), idx, rule,
                            "regra inexistente na anotação (erro de digitação ou regra removida?)"))
                        continue
                    pending.append(Expectation(kind, rule, src, idx))
                continue
            if pending and line.strip():
                expectations.setdefault((rel, idx), []).extend(pending)
                pending = []

        out = tmp / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(expand_placeholders(text, rel))

    # Configs no mesmo lugar em que o workflow as coloca.
    cfg = tmp / "devsecops" / "security"
    cfg.mkdir(parents=True)
    for name in ("semgrep.yml", "gitleaks.toml"):
        shutil.copy(SECURITY / name, cfg / name)

    git = ["git", "-c", "user.name=ci", "-c", "user.email=ci@localhost", "-c", "commit.gpgsign=false"]
    subprocess.run(git + ["init", "-q"], cwd=tmp, check=True)
    subprocess.run(git + ["add", "-A", "-f"], cwd=tmp, check=True)
    subprocess.run(git + ["commit", "-q", "-m", "cases"], cwd=tmp, check=True)
    return expectations, dest_to_src


def run_semgrep(tmp: Path) -> tuple[list[tuple[str, str, int, str]], list[str]]:
    cmd = ["semgrep", "scan", "--config=devsecops/security/semgrep.yml", "--json",
           "--metrics=off", "--disable-version-check", "--quiet"]
    for ex in prod_semgrep_excludes():
        cmd += ["--exclude", ex]
    # Sem --severity ERROR: testamos também as regras WARNING (o relatório avisa
    # quais não bloqueiam em produção).
    proc = subprocess.run(cmd, cwd=tmp, capture_output=True, text=True)
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        raise SystemExit(f"Semgrep não gerou JSON (exit {proc.returncode}):\n{proc.stderr[-3000:]}")
    errors = [f"{e.get('type')}: {e.get('message', '')[:300]}" for e in data.get("errors", [])]
    findings = []
    for r in data.get("results", []):
        cid = r["check_id"]
        # O Semgrep prefixa o id com o caminho do config (devsecops/security/ -> devsecops.security.)
        rule = cid[len("devsecops.security."):] if cid.startswith("devsecops.security.devsecops.") else cid
        findings.append((rule, r["path"], r["start"]["line"], r["extra"]["severity"]))
    return findings, errors


def run_gitleaks(tmp: Path) -> list[tuple[str, str, int, str]]:
    report = tmp.parent / "gitleaks.json"
    cmd = ["gitleaks", "detect", "--source=.", "--config=devsecops/security/gitleaks.toml",
           "--report-format=json", f"--report-path={report}", "--no-banner",
           "--exit-code=0", "--log-level=error"]
    proc = subprocess.run(cmd, cwd=tmp, capture_output=True, text=True)
    if proc.returncode != 0 or not report.exists():
        raise SystemExit(f"Gitleaks falhou (exit {proc.returncode}):\n{proc.stderr[-3000:]}")
    return [(f["RuleID"], f["File"], f["StartLine"], "") for f in json.loads(report.read_text() or "[]")]


def compare(suite: str, findings, expectations, dest_to_src, report: Report):
    found = {}
    for rule, path, line, sev in findings:
        found.setdefault((group_of(rule), path, line), (rule, sev))

    def src_of(path: str, line: int) -> tuple[str, int]:
        src = dest_to_src.get(path)
        return (str(src.relative_to(ROOT)) if src else path, line)

    # Achados não esperados -> FP
    for (grp, path, line), (rule, _sev) in found.items():
        exp = [e for e in expectations.get((path, line), []) if group_of(e.rule) == grp]
        kinds = {e.kind for e in exp}
        if "ruleid" in kinds:
            continue
        f, l = src_of(path, line)
        if "todook" in kinds:
            report.gaps.append(Problem("FP conhecido", suite, f, l, rule, "ainda detectado (todook)"))
            continue
        why = "linha marcada como ok" if "ok" in kinds else "linha sem anotação"
        report.problems.append(Problem("FP", suite, f, l, rule, f"detectado, mas não deveria ({why})"))

    # Esperados não encontrados -> FN
    count = 0
    for (path, line), exps in expectations.items():
        for e in exps:
            if tool_of(e.rule) != suite:
                continue
            count += 1
            hit = (group_of(e.rule), path, line) in found
            f, l = src_of(path, line)
            if e.kind == "ruleid" and not hit:
                report.problems.append(Problem("FN", suite, f, l, e.rule, "deveria ser detectado e não foi"))
            elif e.kind == "todoruleid":
                if hit:
                    report.problems.append(Problem("PROMOTE", suite, f, l, e.rule,
                        "gap corrigido: agora detecta — troque 'todoruleid' por 'ruleid'"))
                else:
                    report.gaps.append(Problem("FN conhecido", suite, f, l, e.rule, "ainda não detecta (todoruleid)"))
            elif e.kind == "todook" and not hit:
                report.problems.append(Problem("PROMOTE", suite, f, l, e.rule,
                    "FP corrigido: não detecta mais — troque 'todook' por 'ok'"))
    report.checked[suite] = count


# ─────────────────────────────────────────────────────────────
# Suíte deps (security/extract-direct-deps.sh)
# ─────────────────────────────────────────────────────────────
def run_deps(report: Report):
    script = SECURITY / "extract-direct-deps.sh"
    count = 0
    for case in sorted(p for p in DEPS_CASES.iterdir() if p.is_dir()):
        count += 1
        expected = json.loads((case / "expected.json").read_text())
        gap_file = case / "KNOWN_GAP"
        with tempfile.TemporaryDirectory() as td:
            for f in case.rglob("*"):
                if f.is_file() and f.name not in ("expected.json", "KNOWN_GAP"):
                    dest = Path(td) / f.relative_to(case)
                    dest = dest.with_name(dest.name.removesuffix(".fixture"))
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy(f, dest)
            proc = subprocess.run(["bash", str(script), td], capture_output=True, text=True)
        rel = str((case / "expected.json").relative_to(ROOT))
        if proc.returncode != 0:
            report.problems.append(Problem("ERROR", "deps", rel, 1, case.name,
                                           f"script falhou (exit {proc.returncode}): {proc.stderr.strip()[:300]}"))
            continue
        got = json.loads(proc.stdout)
        ok = sorted(got) == sorted(expected)
        if gap_file.exists():
            if ok:
                report.problems.append(Problem("PROMOTE", "deps", rel, 1, case.name,
                                               "gap corrigido: resultado bate — apague KNOWN_GAP"))
            else:
                report.gaps.append(Problem("gap conhecido", "deps", rel, 1, case.name,
                                           f"{gap_file.read_text().strip()} (atual: {sorted(got)})"))
            continue
        if not ok:
            missing = sorted(set(expected) - set(got))
            extra = sorted(set(got) - set(expected))
            detail = []
            if missing:
                detail.append(f"faltando (dep direta tratada como transitiva → não bloqueia): {missing}")
            if extra:
                detail.append(f"sobrando (tratada como direta → pode bloquear indevidamente): {extra}")
            report.problems.append(Problem("FN" if missing else "FP", "deps", rel, 1, case.name, "; ".join(detail)))
    report.checked["deps"] = count


# ─────────────────────────────────────────────────────────────
def print_report(report: Report, verbose: bool) -> int:
    labels = {"FP": "falso positivo", "FN": "falso negativo", "PROMOTE": "anotação desatualizada",
              "ERROR": "erro"}
    print()
    if report.problems:
        print(c(RED + ";1", f"❌ {len(report.problems)} problema(s) nas regras de segurança:\n"))
        for p in sorted(report.problems, key=lambda p: (p.kind, p.file, p.line)):
            print(f"  {c(RED, p.kind):<10} {p.file}:{p.line}  {c(BOLD, p.rule)}")
            print(f"             {p.detail}")
            if GH:
                title = f"{labels.get(p.kind, p.kind)} ({p.suite}): {p.rule}"
                print(f"::error file={p.file},line={p.line},title={title}::{p.detail}")
        print()

    if report.gaps:
        print(c(YELLOW, f"⚠️  {len(report.gaps)} gap(s) conhecido(s) (não falham o teste):"))
        if verbose:
            for g in sorted(report.gaps, key=lambda g: (g.file, g.line)):
                print(f"  {g.kind:<14} {g.file}:{g.line}  {g.rule} — {g.detail}")
        else:
            print(c(DIM, "  (use -v para listar)"))
        print()

    for n in report.notes:
        print(c(DIM, f"ℹ️  {n}"))

    total = ", ".join(f"{k}: {v} verificações" for k, v in report.checked.items())
    status = c(GREEN + ";1", "✅ PASSOU") if not report.problems else c(RED + ";1", "❌ FALHOU")
    print(f"\n{status}  ({total})")

    if GH and (summary := os.environ.get("GITHUB_STEP_SUMMARY")):
        with open(summary, "a") as fh:
            fh.write(f"## {'✅' if not report.problems else '❌'} Testes das regras de segurança\n\n")
            fh.write(f"{total}\n\n")
            if report.problems:
                fh.write("| Tipo | Regra | Caso | Detalhe |\n|---|---|---|---|\n")
                for p in report.problems:
                    fh.write(f"| {labels.get(p.kind, p.kind)} | `{p.rule}` | `{p.file}:{p.line}` | {p.detail} |\n")
                fh.write("\n")
            if report.gaps:
                fh.write(f"<details><summary>⚠️ {len(report.gaps)} gap(s) conhecido(s)</summary>\n\n")
                for g in report.gaps:
                    fh.write(f"- `{g.rule}` — `{g.file}:{g.line}` — {g.detail}\n")
                fh.write("\n</details>\n")
    return 1 if report.problems else 0


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    verbose = "-v" in sys.argv[1:]
    suites = args or ["semgrep", "gitleaks", "deps"]
    report = Report()

    if {"semgrep", "gitleaks"} & set(suites):
        known = load_rule_ids()
        with tempfile.TemporaryDirectory(prefix="alpha-rules-") as td:
            tmp = Path(td) / "repo"
            tmp.mkdir()
            expectations, dest_to_src = build_fake_repo(tmp, known, report)
            if "semgrep" in suites:
                findings, errors = run_semgrep(tmp)
                for e in errors:
                    report.problems.append(Problem("ERROR", "semgrep", "security/semgrep.yml", 1, "semgrep", e))
                compare("semgrep", findings, expectations, dest_to_src, report)
                warn_rules = sorted({r for r, *_, sev in findings if sev != "ERROR"})
                if warn_rules:
                    report.notes.append(
                        "Regras com severity != ERROR não rodam no CI (--severity ERROR): " + ", ".join(warn_rules))
            if "gitleaks" in suites:
                compare("gitleaks", run_gitleaks(tmp), expectations, dest_to_src, report)

    if "deps" in suites:
        run_deps(report)

    return print_report(report, verbose)


if __name__ == "__main__":
    sys.exit(main())
