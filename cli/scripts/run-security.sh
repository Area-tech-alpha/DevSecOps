#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Security Scanner                                 ║
# ║  Replica alpha-security.yaml do GitHub Actions               ║
# ║  Gitleaks + OSV-Scanner + Semgrep (paralelo)                 ║
# ╚══════════════════════════════════════════════════════════════╝

set -uo pipefail
cd "$WORKSPACE"

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

  # Report output if requested
  if [ "${REPORT_FORMAT:-text}" != "text" ]; then
    GITLEAKS_ARGS+=("--report-format" "json" "--report-path" "/tmp/gitleaks-report.json")
  fi

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
    CMD_ARGS=("scan" "--format" "json")
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

  # SECURITY: Use bash array for arguments
  SEMGREP_ARGS=("scan" "--config=p/security-audit")
  if [ "$IS_REACT" = "true" ]; then
    SEMGREP_ARGS+=("--config=p/react")
  fi

  if [ -n "$CONFIG_SEC" ] && [ -f "$CONFIG_SEC/semgrep.yml" ]; then
    SEMGREP_ARGS+=("--config=$CONFIG_SEC/semgrep.yml")
  fi

  # Report output
  if [ "${REPORT_FORMAT:-text}" != "text" ]; then
    SEMGREP_ARGS+=("--json" "--output" "/tmp/semgrep-report.json")
  else
    SEMGREP_ARGS+=("--quiet")
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
echo -e "${DIM}EXIT_GIT=$EXIT_GIT | EXIT_OSV=$EXIT_OSV | EXIT_SEM=$EXIT_SEM${NC}"

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

# Semgrep
if [ "$SKIP_SEMGREP" = "true" ]; then
  echo -e "  ${DIM}⏩ Semgrep: Pulado (não instalado)${NC}"
elif [ $EXIT_SEM -ne 0 ]; then
  echo -e "  ${RED}❌ Semgrep: Vulnerabilidades de código detectadas!${NC}"
  OVERALL_EXIT=1
else
  echo -e "  ${GREEN}✅ Semgrep: Nenhuma vulnerabilidade de código${NC}"
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

  # Extrair dependências diretas do package.json
  if [ -f package.json ]; then
    jq -r '[
      (.dependencies // {} | keys[]),
      (.devDependencies // {} | keys[])
    ] | unique | .[]' package.json > /tmp/direct-deps-raw.txt

    DIRECT_COUNT=$(wc -l < /tmp/direct-deps-raw.txt | tr -d ' ')
    echo -e "  ${DIM}📦 Dependências diretas encontradas: $DIRECT_COUNT${NC}"

    jq -R -s 'split("\n") | map(select(length > 0))' /tmp/direct-deps-raw.txt > /tmp/direct-deps.json
  else
    echo -e "  ${YELLOW}⚠️ Sem package.json — todas as deps serão tratadas como diretas${NC}"
    echo '[]' > /tmp/direct-deps.json
  fi

  # Severity filter
  SEVERITY_FILTER='(
    (.vuln.database_specific.cvssScore // 0) >= 7
    or ((.vuln.database_specific.severity // "") | ascii_upcase | test("HIGH|CRITICAL"))
    or ((.vuln.severity[]?.score | tonumber? // 0) >= 7)
  )'

  DIRECT_LIST_EMPTY=$(jq 'length == 0' /tmp/direct-deps.json)

  # Layer 1: Diretas
  DIRECT_VULNS=$(jq --slurpfile direct /tmp/direct-deps.json "
    [
      .results[]?
      | (.packages[]? | . as \$pkg | .vulnerabilities[]? | {vuln: ., name: \$pkg.package.name, ver: \$pkg.package.version})
      | select(
          ( (\$direct[0] | length) == 0 or (.name as \$n | \$direct[0] | index(\$n) != null) )
          and ${SEVERITY_FILTER}
        )
    ] | length
  " /tmp/osv-results.json)

  # Layer 2: Transitivas
  TRANSITIVE_VULNS=0
  if [ "$DIRECT_LIST_EMPTY" == "false" ]; then
    TRANSITIVE_VULNS=$(jq --slurpfile direct /tmp/direct-deps.json "
      [
        .results[]?
        | (.packages[]? | . as \$pkg | .vulnerabilities[]? | {vuln: ., name: \$pkg.package.name, ver: \$pkg.package.version})
        | select(
            (.name as \$n | \$direct[0] | index(\$n) == null)
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
          (.name as $n | $direct[0] | index($n) == null)
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
    echo -e "${RED}❌ ══ DIRETAS COM VULNERABILIDADES (BLOCKING) ══${NC}"
    jq -r --slurpfile direct /tmp/direct-deps.json '
      .results[]?
      | (.packages[]? | . as $pkg | .vulnerabilities[]? | {vuln: ., name: $pkg.package.name, ver: $pkg.package.version})
      | select(
          ( ($direct[0] | length) == 0 or (.name as $n | $direct[0] | index($n) != null) )
          and (
            (.vuln.database_specific.cvssScore // 0) >= 7
            or ((.vuln.database_specific.severity // "") | ascii_upcase | test("HIGH|CRITICAL"))
            or ((.vuln.severity[]?.score | tonumber? // 0) >= 7)
          )
        )
      | ([ .vuln.affected[]? | .ranges[]?.events[]?.fixed | select(type=="string") ] | .[0]) as $fixed
      | "• \(.vuln.id // "N/A") 🎯 Alvo: \(.name // "Desconhecido")@\(.ver // "?")\n  🚨 Ameaça: \(.vuln.summary // "Exploit Desconhecido")\n  💉 Fix: \(if $fixed != null then "Migre para v\($fixed)+ (`npm install \(.name)@^\($fixed)`)" else "Patch fix desconhecido. Force update do pacote \(.name)." end)\n"
    ' /tmp/osv-results.json

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
echo -e "${DIM}══════════════════════════════════════════${NC}"
echo -e "${DIM}🔐 Security Gate Strategy:${NC}"
echo -e "${DIM}  🔴 BLOCK  → Deps diretas com HIGH/CRITICAL${NC}"
echo -e "${DIM}  🟡 WARN   → Deps transitivas com HIGH/CRITICAL${NC}"
echo -e "${DIM}  🟢 PASS   → Sem vulnerabilidades críticas diretas${NC}"
echo -e "${DIM}══════════════════════════════════════════${NC}"

exit $OVERALL_EXIT
