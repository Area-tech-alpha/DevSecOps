#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Local Runner (--no-docker)                       ║
# ║  Executa o pipeline diretamente no host sem Docker           ║
# ║  Requer as tools instaladas localmente                       ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── Resolve paths ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export SCRIPTS_DIR="$SCRIPT_DIR"
export WORKSPACE="${TARGET_PATH:-$(pwd)}"

# Config: tenta achar os configs do DevSecOps repo
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)" || REPO_ROOT=""
if [ -d "$REPO_ROOT/security" ] && [ -d "$REPO_ROOT/lint" ]; then
  export CONFIG_DIR="$REPO_ROOT"
else
  export CONFIG_DIR="/opt/alpha-ci/config"
fi

# ── Cores ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Tool Check ──
echo -e "\n${BOLD}${CYAN}🔍 Verificando ferramentas no host...${NC}\n"

check_tool() {
  if command -v "$1" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $1"
    return 0
  else
    echo -e "  ${YELLOW}⚠${NC} $1 — não encontrado"
    return 1
  fi
}

check_tool "git" || { echo -e "${RED}❌ git é obrigatório${NC}"; exit 1; }
check_tool "jq" || { echo -e "${RED}❌ jq é obrigatório${NC}"; exit 1; }
check_tool "gitleaks" || true
check_tool "osv-scanner" || true
check_tool "semgrep" || true
check_tool "node" || true
check_tool "eslint" || true
check_tool "ruff" || true
check_tool "golangci-lint" || true
check_tool "go" || true
check_tool "python3" || true

echo ""

# ── Delega para o entrypoint com todas as env vars ──
exec bash "$SCRIPTS_DIR/entrypoint.sh" "$@"
