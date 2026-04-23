#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Local Runner (--no-docker)                       ║
# ║  Executa o pipeline diretamente no host sem Docker           ║
# ║  Requer as tools instaladas localmente                       ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── Resolve paths ──
# When running without Docker, scripts and configs come from the DevSecOps repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

export SCRIPTS_DIR="$SCRIPT_DIR"
export CONFIG_DIR="$REPO_ROOT/config"
export WORKSPACE="${TARGET_PATH:-.}"

# Fallback: se config não existe no repo root, tenta o path do Docker
if [ ! -d "$CONFIG_DIR" ]; then
  # Monta config dir a partir dos dirs do repo
  CONFIG_DIR="$REPO_ROOT"
  export CONFIG_DIR
fi

# ── Cores ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

export RED GREEN YELLOW BLUE CYAN MAGENTA BOLD DIM NC

# ── Tool Check ──
check_tool() {
  local tool="$1"
  local required="${2:-false}"

  if command -v "$tool" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} $tool $(command -v "$tool")"
    return 0
  else
    if [ "$required" = "true" ]; then
      echo -e "  ${RED}✗${NC} $tool — ${RED}REQUIRED${NC}"
      return 1
    else
      echo -e "  ${YELLOW}⚠${NC} $tool — não encontrado (será pulado)"
      return 1
    fi
  fi
}

preflight() {
  echo -e "\n${BOLD}${CYAN}🔍 Verificando ferramentas instaladas...${NC}\n"

  local missing_critical=false

  # Core tools (sempre necessárias)
  check_tool "git" true || missing_critical=true
  check_tool "jq" true || missing_critical=true

  # Security tools
  HAS_GITLEAKS=false; check_tool "gitleaks" && HAS_GITLEAKS=true
  HAS_OSV=false; check_tool "osv-scanner" && HAS_OSV=true
  HAS_SEMGREP=false; check_tool "semgrep" && HAS_SEMGREP=true

  # Lint tools
  HAS_ESLINT=false
  if [ -f "$WORKSPACE/node_modules/.bin/eslint" ]; then
    echo -e "  ${GREEN}✓${NC} eslint (local node_modules)"
    HAS_ESLINT=true
  else
    check_tool "eslint" && HAS_ESLINT=true
  fi
  HAS_RUFF=false; check_tool "ruff" && HAS_RUFF=true
  HAS_GOLANGCI=false; check_tool "golangci-lint" && HAS_GOLANGCI=true

  # Runtime tools
  HAS_NODE=false; check_tool "node" && HAS_NODE=true
  HAS_PYTHON=false; check_tool "python3" && HAS_PYTHON=true
  HAS_GO=false; check_tool "go" && HAS_GO=true

  export HAS_GITLEAKS HAS_OSV HAS_SEMGREP HAS_ESLINT HAS_RUFF HAS_GOLANGCI
  export HAS_NODE HAS_PYTHON HAS_GO

  echo ""

  if [ "$missing_critical" = "true" ]; then
    echo -e "${RED}❌ Ferramentas críticas faltando. Instale git e jq.${NC}"
    exit 1
  fi
}

# ── Banner ──
banner() {
  echo ""
  echo -e "${MAGENTA}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════╗"
  echo "  ║     🛡️  Alpha CI — DevSecOps Pipeline         ║"
  echo "  ║     Area Tech Alpha · Local Runner (no-docker)║"
  echo "  ╚═══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ── Parse args ──
COMMAND="${1:-help}"
shift 2>/dev/null || true

VERBOSE=false
AUTO_FIX=false
REPORT_FORMAT="${REPORT_FORMAT:-text}"
REPORT_OUTPUT="${REPORT_OUTPUT:-}"

for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=true ;;
    --fix) AUTO_FIX=true ;;
    --format=*) REPORT_FORMAT="${arg#*=}" ;;
    --output=*) REPORT_OUTPUT="${arg#*=}" ;;
  esac
done

export VERBOSE AUTO_FIX REPORT_FORMAT REPORT_OUTPUT

# ── Execute ──
banner
preflight

# Go to workspace
cd "$WORKSPACE" 2>/dev/null || { echo -e "${RED}❌ Workspace não encontrado: $WORKSPACE${NC}"; exit 1; }

# Fix git ownership
git config --global --add safe.directory "$WORKSPACE" 2>/dev/null || true

# Source detection
source "$SCRIPTS_DIR/detect.sh"
detect_project

# Dispatch
case "$COMMAND" in
  all|security|lint|test|build|e2e|detect)
    # Reutiliza os mesmos scripts do Docker (eles usam as env vars exportadas)
    source "$SCRIPTS_DIR/entrypoint.sh" "$COMMAND" "$@" 2>/dev/null || {
      # Se source falhar (entrypoint é pra Docker), executa direto
      bash "$SCRIPTS_DIR/entrypoint.sh" "$COMMAND" "$@"
    }
    ;;
  help|--help|-h)
    echo -e "${BOLD}Usage:${NC} alpha-ci --no-docker <command> [options]"
    echo ""
    echo -e "${BOLD}Commands:${NC} all, security, lint, test, build, e2e, detect"
    echo -e "${BOLD}Options:${NC}  -v, --verbose, --fix, --format=json, --output=file"
    exit 0
    ;;
  *)
    echo -e "${RED}❌ Unknown command: ${COMMAND}${NC}"
    exit 1
    ;;
esac
