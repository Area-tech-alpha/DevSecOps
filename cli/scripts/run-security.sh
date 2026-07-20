#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Security Scanner                                 ║
# ║  Replica alpha-security.yaml do GitHub Actions               ║
# ║  Gitleaks + OSV-Scanner + Semgrep (paralelo)                 ║
# ╚══════════════════════════════════════════════════════════════╝

set -uo pipefail

# Fallback for WORKSPACE if not defined
WORKSPACE="${WORKSPACE:-$(pwd)}"
cd "$WORKSPACE"

# Define colors if not defined
RED="${RED:-'\033[0;31m'}"
GREEN="${GREEN:-'\033[0;32m'}"
YELLOW="${YELLOW:-'\033[1;33m'}"
CYAN="${CYAN:-'\033[0;36m'}"
DIM="${DIM:-'\033[2m'}"
BOLD="${BOLD:-'\033[1m'}"
NC="${NC:-'\033[0m'}"
# Garante que git confia no workspace (container UID ≠ host UID)
# SECURITY: Only trust the specific workspace, not wildcard '*'
git config --global --add safe.directory "$WORKSPACE" 2>/dev/null || true

CONFIG_SEC="/opt/alpha-ci/config/security"

# Fallback config path for --no-docker mode
if [ ! -d "$CONFIG_SEC" ]; then
  # Try relative to scripts dir
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CONFIG_SEC="$(cd "$SCRIPT_DIR/../../security" 2>/dev/null && pwd)" || CONFIG_SEC=""
fi

# ══════════════════════════════════════════
# 🔐 Gitleaks — Secret Detection
# ══════════════════════════════════════════

SKIP_GITLEAKS=false
if ! command -v gitleaks &>/dev/null; then
  echo -e "${YELLOW}⚠️ Gitleaks não encontrado — pulando${NC}"
  SKIP_GITLEAKS=true
fi

if [ "$SKIP_GITLEAKS" = "false" ]; then
  echo -e "${CYAN}🔐 Rodando Gitleaks...${NC}"

  # SECURITY: Use bash arrays to prevent word splitting / injection
  GITLEAKS_ARGS=("detect" "--source=." "--redact" "-v")
  if [ ! -d ".git" ]; then
    echo -e "  ${DIM}ℹ️  Diretório .git não encontrado, executando gitleaks com --no-git${NC}"
    GITLEAKS_ARGS+=("--no-git")
  fi

  if [ -n "$CONFIG_SEC" ] && [ -f "$CONFIG_SEC/gitleaks.toml" ]; then
    GITLEAKS_ARGS+=("--config=$CONFIG_SEC/gitleaks.toml")
  fi

  # Always generate JSON report for programmatic validation
  GITLEAKS_ARGS+=("--report-format" "json" "--report-path" "/tmp/gitleaks-report.json")

  gitleaks "${GITLEAKS_ARGS[@]}" &
  PID_GIT=$!
fi

# ══════════════════════════════════════════
# 📦 OSV-Scanner — Dependency Vulnerabilities
# ══════════════════════════════════════════

SKIP_OSV=false
if ! command -v osv-scanner &>/dev/null; then
  echo -e "${YELLOW}⚠️ OSV-Scanner não encontrado — pulando${NC}"
  SKIP_OSV=true
fi

if [ "$SKIP_OSV" = "false" ]; then
  echo -e "${CYAN}🔍 Detectando lockfiles para OSV...${NC}"
  LOCKFILES=$(find . -type d \( -name 'node_modules' -o -name 'venv' -o -name '.venv' -o -name '.git' \) -prune -o -type f \( \
    -name "package-lock.json" \
    -o -name "yarn.lock" \
    -o -name "pnpm-lock.yaml" \
    -o -name "go.mod" \
    -o -name "requirements.txt" \
    -o -name "poetry.lock" \
  \) -print)

  if [ -z "$LOCKFILES" ]; then
    echo -e "  ${YELLOW}⚠️ Nenhum lockfile encontrado — pulando OSV${NC}"
    SKIP_OSV=true
  else
    echo -e "${CYAN}📦 Rodando OSV Scanner...${NC}"
    echo "$LOCKFILES"

    # SECURITY: Use bash array for arguments
    CMD_ARGS=("scan" "--format" "json" "--offline-vulnerabilities")

    # Wire config file if available
    if [ -n "$CONFIG_SEC" ] && [ -f "$CONFIG_SEC/osv-scanner.toml" ]; then
      CMD_ARGS+=("--config=$CONFIG_SEC/osv-scanner.toml")
    fi

    while IFS= read -r LF; do
      [ -n "$LF" ] && CMD_ARGS+=("-L" "$LF")
    done <<< "$LOCKFILES"

    osv-scanner "${CMD_ARGS[@]}" > /tmp/osv-results.json 2>/tmp/osv-errors.log &
    PID_OSV=$!
  fi
fi

# ══════════════════════════════════════════
# 🛡️ Semgrep — SAST
# ══════════════════════════════════════════

SKIP_SEMGREP=false
if ! command -v semgrep &>/dev/null; then
  echo -e "${YELLOW}⚠️ Semgrep não encontrado — pulando${NC}"
  SKIP_SEMGREP=true
fi

if [ "$SKIP_SEMGREP" = "false" ]; then
  echo -e "${CYAN}🛡️ Rodando Semgrep...${NC}"

  SEMGREP_ARGS=("scan" "--quiet" "--error" "--severity" "ERROR")
  SEMGREP_ARGS+=("--json" "--output" "/tmp/semgrep-results.json")
  SEMGREP_ARGS+=(
    "--exclude" "devsecops"
    "--exclude" "node_modules"
    "--exclude" "dist"
    "--exclude" "build"
    "--exclude" ".next"
    "--exclude" "coverage"
    "--exclude" "**/*.min.js"
    "--exclude" "osv-results.json"
    "--exclude" "osv-errors.log"
    "--exclude" "semgrep-results.json"
    "--exclude" "direct-deps.json"
  )

  if [ -n "$CONFIG_SEC" ] && [ -f "$CONFIG_SEC/semgrep.yml" ]; then
    SEMGREP_ARGS+=("--config=$CONFIG_SEC/semgrep.yml")
  else
    echo -e "${YELLOW}⚠️ semgrep.yml não encontrado — pulando Semgrep${NC}"
    SKIP_SEMGREP=true
  fi

  semgrep "${SEMGREP_ARGS[@]}" &
  PID_SEM=$!
fi

# ══════════════════════════════════════════
# ⏳ Aguarda resultados paralelos
# ══════════════════════════════════════════

set +e

EXIT_GIT=0
if [ "$SKIP_GITLEAKS" = "false" ]; then
  wait $PID_GIT; EXIT_GIT=$?
fi

EXIT_OSV=0
if [ "$SKIP_OSV" != "true" ]; then
  wait $PID_OSV; EXIT_OSV=$?
fi

EXIT_SEM=0
if [ "$SKIP_SEMGREP" = "false" ]; then
  wait $PID_SEM; EXIT_SEM=$?
fi

set -e

echo ""
echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
echo -e "${DIM}Processamento paralelo concluído:${NC}"
echo -e "${DIM}EXIT_GIT=$EXIT_GIT | EXIT_OSV=$EXIT_OSV | EXIT_SEM=$EXIT_SEM${NC}"
echo -e "${CYAN}──────────────────────────────────────────────────${NC}"
echo ""

# ══════════════════════════════════════════
# 🚨 Evaluate Results
# ══════════════════════════════════════════

OVERALL_EXIT=0

# Gitleaks
if [ "$SKIP_GITLEAKS" = "true" ]; then
  echo -e "  ${DIM}⏩ Gitleaks: Pulado (não instalado)${NC}"
elif [ $EXIT_GIT -ne 0 ]; then
  echo -e "\n${RED}❌ Gitleaks: Segredos detectados no repositório!${NC}"
  OVERALL_EXIT=1
else
  echo -e "  ${GREEN}✅ Gitleaks: Nenhum segredo detectado${NC}"
fi

# Semgrep — defense-in-depth: validate JSON output regardless of exit code
SEMGREP_BLOCKING=0
if [ "$SKIP_SEMGREP" = "false" ] && [ -f /tmp/semgrep-results.json ]; then
  SEMGREP_BLOCKING=$(jq '[.results[] | select(.extra.severity == "ERROR" and (.check_id | contains("devsecops.")))] | length' /tmp/semgrep-results.json 2>/dev/null || echo 0)
fi

if [ "$SKIP_SEMGREP" = "true" ]; then
  echo -e "  ${DIM}⏩ Semgrep: Pulado (não instalado)${NC}"
elif [ $EXIT_SEM -ne 0 ] || [ "$SEMGREP_BLOCKING" -gt 0 ]; then
  echo -e "  ${RED}${BOLD}❌ SEMGREP: $SEMGREP_BLOCKING VULNERABILIDADE(S) ENCONTRADA(S)${NC}"
  if [ -f /tmp/semgrep-results.json ] && [ "$SEMGREP_BLOCKING" -gt 0 ]; then
    echo -e "  ${DIM}──────────────────────────────────────────────────${NC}"
    jq -r '.results[] | select(.extra.severity == "ERROR" and (.check_id | contains("devsecops."))) | "  🚨 \(.path):\(.start.line)\n     \(.extra.message) [\(.check_id)]\n"' /tmp/semgrep-results.json
    
    # GitHub Actions annotations
    if [ "${GITHUB_ACTIONS:-}" == "true" ]; then
      jq -r '.results[] | select(.extra.severity == "ERROR" and (.check_id | contains("devsecops."))) | "::error file=\(.path),line=\(.start.line),title=Vulnerabilidade SAST (\(.check_id))::\(.extra.message)"' /tmp/semgrep-results.json
    fi
  fi
  OVERALL_EXIT=1
else
  echo -e "  ${GREEN}✅ Semgrep: Nenhuma vulnerabilidade blocking${NC}"
fi

# ══════════════════════════════════════════
# 🔍 OSV Validation + Security Gate
# ══════════════════════════════════════════

if [ "$SKIP_OSV" = "true" ]; then
  echo -e "  ${DIM}⏩ OSV: Pulado (nenhum lockfile ou não instalado)${NC}"
elif [ ! -f /tmp/osv-results.json ]; then
  echo -e "  ${YELLOW}⚠️ OSV: Nenhum resultado gerado${NC}"
elif ! jq -e . /tmp/osv-results.json >/dev/null 2>&1; then
  echo -e "  ${RED}❌ OSV: JSON de resultados inválido${NC}"
  cat /tmp/osv-results.json 2>/dev/null || true
  OVERALL_EXIT=1
else
  # ── Security Gate: Two-Layer (Direct BLOCK / Transitive WARN) ──

  RESULTS_COUNT=$(jq '.results | length' /tmp/osv-results.json 2>/dev/null || echo 0)
  echo -e "  ${DIM}📊 OSV Results count: $RESULTS_COUNT${NC}"

  if [ -s /tmp/osv-errors.log ]; then
    echo -e "  ${YELLOW}⚠️ OSV warnings:${NC}"
    cat /tmp/osv-errors.log
  fi

  EXTRACT_SCRIPT=""
  if [ -n "$CONFIG_SEC" ] && [ -f "$CONFIG_SEC/extract-direct-deps.sh" ]; then
    EXTRACT_SCRIPT="$CONFIG_SEC/extract-direct-deps.sh"
  elif [ -f "$(dirname "${BASH_SOURCE[0]}")/../../security/extract-direct-deps.sh" ]; then
    EXTRACT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../security" && pwd)/extract-direct-deps.sh"
  fi

  if [ -n "$EXTRACT_SCRIPT" ]; then
    chmod +x "$EXTRACT_SCRIPT"
    "$EXTRACT_SCRIPT" . > /tmp/direct-deps.json
    DIRECT_COUNT=$(jq 'length' /tmp/direct-deps.json)
    echo -e "  ${DIM}📦 Dependências diretas de produção: $DIRECT_COUNT${NC}"
    if [ "$DIRECT_COUNT" -eq 0 ]; then
      echo -e "  ${DIM}ℹ️  Sem mapeamento de deps diretas — OSV não bloqueará${NC}"
    fi
  else
    echo '[]' > /tmp/direct-deps.json
  fi

  # Severity filter
  SEVERITY_FILTER='(
    (.vuln.database_specific.cvssScore // 0) >= 7
    or ((.vuln.database_specific.severity // "") | ascii_upcase | test("HIGH|CRITICAL"))
    or ((.vuln.severity[]?.score | tonumber? // 0) >= 7)
  )'

  DIRECT_LIST_EMPTY=$(jq 'length == 0' /tmp/direct-deps.json)

  DIRECT_VULNS=0
  if [ "$DIRECT_LIST_EMPTY" == "false" ]; then
    DIRECT_VULNS=$(jq --slurpfile direct /tmp/direct-deps.json "
      [
        .results[]?
        | (.packages[]? | . as \$pkg | .vulnerabilities[]? | {vuln: ., name: \$pkg.package.name, ver: \$pkg.package.version})
        | select(
            ((.name | ascii_downcase) as \$n | \$direct[0] | index(\$n) != null)
            and ${SEVERITY_FILTER}
          )
      ] | length
    " /tmp/osv-results.json)
  fi

  # Layer 2: Transitivas
  TRANSITIVE_VULNS=0
  if [ "$DIRECT_LIST_EMPTY" == "false" ]; then
    TRANSITIVE_VULNS=$(jq --slurpfile direct /tmp/direct-deps.json "
      [
        .results[]?
        | (.packages[]? | . as \$pkg | .vulnerabilities[]? | {vuln: ., name: \$pkg.package.name, ver: \$pkg.package.version})
        | select(
            ((.name | ascii_downcase) as \$n | \$direct[0] | index(\$n) == null)
            and ${SEVERITY_FILTER}
          )
      ] | length
    " /tmp/osv-results.json)
  fi

  echo ""
  echo -e "${BOLD}════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}🔢 DIRETAS    HIGH/CRITICAL: ${DIRECT_VULNS}${NC}"
  echo -e "${BOLD}🔢 TRANSITIVAS HIGH/CRITICAL: ${TRANSITIVE_VULNS}${NC}"
  echo -e "${BOLD}════════════════════════════════════════════════${NC}"

  # Transitivas — WARNING (não bloqueiam)
  if (( TRANSITIVE_VULNS > 0 )); then
    echo ""
    echo -e "${YELLOW}⚠️  ══ TRANSITIVAS COM VULNERABILIDADES (WARNING — não bloqueia) ══${NC}"
    jq -r --slurpfile direct /tmp/direct-deps.json '
      .results[]?
      | (.packages[]? | . as $pkg | .vulnerabilities[]? | {vuln: ., name: $pkg.package.name, ver: $pkg.package.version})
      | select(
          ((.name | ascii_downcase) as $n | $direct[0] | index($n) == null)
          and (
            (.vuln.database_specific.cvssScore // 0) >= 7
            or ((.vuln.database_specific.severity // "") | ascii_upcase | test("HIGH|CRITICAL"))
            or ((.vuln.severity[]?.score | tonumber? // 0) >= 7)
          )
        )
      | ([ .vuln.affected[]? | .ranges[]?.events[]?.fixed | select(type=="string") ] | .[0]) as $fixed
      | "  ⚠️  \(.vuln.id // "N/A") → \(.name)@\(.ver)\n     \(.vuln.summary // "Sem descrição")\n     Fix: \(if $fixed != null then "v\($fixed)+" else "Desconhecido" end)\n"
    ' /tmp/osv-results.json
    echo ""
    echo -e "${DIM}ℹ️  Transitivas não bloqueiam o pipeline. Corrija via overrides no package.json.${NC}"
    echo -e "${DIM}   Consulte: https://docs.npmjs.com/cli/v10/configuring-npm/package-json#overrides${NC}"
  fi

  # Diretas — BLOCK (bloqueiam o pipeline)
  if (( DIRECT_VULNS > 0 )); then
    echo ""
    echo -e "${RED}${BOLD}❌ ══ DIRETAS COM VULNERABILIDADES (BLOCKING) ══${NC}"
    echo -e "${DIM}──────────────────────────────────────────────────${NC}"
    jq -r --slurpfile direct /tmp/direct-deps.json '
      .results[]?
      | (.packages[]? | . as $pkg | .vulnerabilities[]? | {vuln: ., name: $pkg.package.name, ver: $pkg.package.version})
      | select(
          ((.name | ascii_downcase) as $n | $direct[0] | index($n) != null)
          and (
            (.vuln.database_specific.cvssScore // 0) >= 7
            or ((.vuln.database_specific.severity // "") | ascii_upcase | test("HIGH|CRITICAL"))
            or ((.vuln.severity[]?.score | tonumber? // 0) >= 7)
          )
        )
      | ([ .vuln.affected[]? | .ranges[]?.events[]?.fixed | select(type=="string") ] | .[0]) as $fixed
      | "  • \(.vuln.id // "N/A") 🎯 Alvo: \(.name // "Desconhecido")@\(.ver // "?")\n    🚨 Ameaça: \(.vuln.summary // "Exploit Desconhecido")\n    💉 Fix: \(if $fixed != null then "Migre para v\($fixed)+ (`npm install \(.name)@^\($fixed)`)" else "Patch fix desconhecido. Force update do pacote \(.name)." end)\n"
    ' /tmp/osv-results.json

    if [ "${GITHUB_ACTIONS:-}" == "true" ]; then
      jq -r --slurpfile direct /tmp/direct-deps.json '
        .results[]?
        | (.packages[]? | . as $pkg | .vulnerabilities[]? | {vuln: ., name: $pkg.package.name, ver: $pkg.package.version})
        | select(
            ((.name | ascii_downcase) as $n | $direct[0] | index($n) != null)
            and (
              (.vuln.database_specific.cvssScore // 0) >= 7
              or ((.vuln.database_specific.severity // "") | ascii_upcase | test("HIGH|CRITICAL"))
              or ((.vuln.severity[]?.score | tonumber? // 0) >= 7)
            )
          )
        | ([ .vuln.affected[]? | .ranges[]?.events[]?.fixed | select(type=="string") ] | .[0]) as $fixed
        | "::error title=\(.vuln.id // "Vulnerabilidade") em dependência direta (\(.name))::\(.vuln.summary // "Exploit Desconhecido"). Fix: \(if $fixed != null then "v\($fixed)+" else "Desconhecido" end)"
      ' /tmp/osv-results.json
    fi

    OVERALL_EXIT=1
  fi

  if (( DIRECT_VULNS == 0 )); then
    echo -e "  ${GREEN}✅ OSV: Nenhuma vulnerabilidade crítica em dependências diretas${NC}"
  fi
fi

# ══════════════════════════════════════════
# 📊 Security Summary
# ══════════════════════════════════════════

echo ""
echo -e "${BOLD}═════════════════════════════════════════════════════════${NC}"
if [ $OVERALL_EXIT -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  🎉 SUCESSO: Nenhum problema crítico de segurança!${NC}"
else
  echo -e "${RED}${BOLD}  ❌ FALHA: Problemas críticos de segurança detectados.${NC}"
  echo -e "${RED}            Corrija os erros acima para seguir com o CI.${NC}"
fi
echo -e "${BOLD}═════════════════════════════════════════════════════════${NC}"

exit $OVERALL_EXIT
