#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Entrypoint                                       ║
# ║  Recebe o comando da CLI e despacha para o runner correto    ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/alpha-ci/scripts}"
CONFIG_DIR="${CONFIG_DIR:-/opt/alpha-ci/config}"
WORKSPACE="${WORKSPACE:-/workspace}"

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
export SCRIPTS_DIR CONFIG_DIR

# ── Workspace Isolation (Cross-platform safe) ──
# Se o projeto foi montado em /host_workspace, copiamos para /workspace
# ignorando node_modules. Isso previne que binários nativos do Windows/Mac
# quebrem o ambiente Linux do container.
if [ -d "/host_workspace" ]; then
  echo -e "  ${DIM}ℹ️  Isolando workspace (evitando conflitos de SO Windows -> Linux)...${NC}"
  mkdir -p /workspace
  tar --exclude='node_modules' --exclude='.next' --exclude='dist' --exclude='build' --exclude='venv' --exclude='.venv' -cf - -C /host_workspace . | tar -xf - -C /workspace
  WORKSPACE="/workspace"
else
  WORKSPACE="${WORKSPACE:-/workspace}"
fi
export WORKSPACE

cd "$WORKSPACE"

# ── Proteção Extrema: Forçar .npmrc global e aniquilar o local ──
# Se o projeto tiver um .npmrc local, ele pode gerar erros de EACCES
# ou conflitos de registry. Como estamos em um workspace isolado (/workspace),
# podemos apagar o .npmrc local sem afetar o host!
if [ -f "$WORKSPACE/.npmrc" ]; then
  echo -e "  ${DIM}ℹ️  Apagando .npmrc local do workspace isolado para evitar conflitos de permissão...${NC}"
  rm -f "$WORKSPACE/.npmrc"
fi

# O host's global .npmrc já foi montado como read-only em /home/alpha-ci/.npmrc
export NPM_CONFIG_USERCONFIG=/home/alpha-ci/.npmrc

banner() {
  echo ""
  echo -e "${MAGENTA}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════╗"
  echo "  ║     🛡️  Alpha CI — DevSecOps Pipeline         ║"
  echo "  ║     Area Tech Alpha · Local Runner            ║"
  echo "  ╚═══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

usage() {
  banner
  echo -e "${BOLD}Usage:${NC} alpha-ci <command> [options]"
  echo ""
  echo -e "${BOLD}Commands:${NC}"
  echo -e "  ${CYAN}all${NC}         Pipeline completo (security → lint → test → build)"
  echo -e "  ${CYAN}security${NC}    Scanners de segurança (Gitleaks + OSV + Semgrep)"
  echo -e "  ${CYAN}lint${NC}        Linting (ESLint / Ruff / golangci-lint)"
  echo -e "  ${CYAN}test${NC}        Testes unitários (Jest/Vitest/pytest/go test)"
  echo -e "  ${CYAN}build${NC}       Build do projeto"
  echo -e "  ${CYAN}e2e${NC}         Testes E2E (Playwright / Cypress)"
  echo -e "  ${CYAN}shell${NC}       Shell interativo no container"
  echo -e "  ${CYAN}detect${NC}      Apenas detecta o tipo de projeto"
  echo ""
  echo -e "${BOLD}Options:${NC}"
  echo -e "  ${YELLOW}-v, --verbose${NC}              Output detalhado"
  echo -e "  ${YELLOW}--fix${NC}                      Auto-fix problemas de lint"
  echo -e "  ${YELLOW}--format <json|sarif|text>${NC} Formato do relatório"
  echo -e "  ${YELLOW}--output <file>${NC}            Salva relatório em arquivo"
  echo -e "  ${YELLOW}--help${NC}                     Mostra esta mensagem"
  echo ""
}

# ── Parse args ──
COMMAND="${1:-help}"
shift 2>/dev/null || true

VERBOSE="${VERBOSE:-false}"
AUTO_FIX="${AUTO_FIX:-false}"
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

# ── Fix git ownership warning (container UID != host UID) ──
# SECURITY: Only mark the specific workspace as safe (not '*' wildcard)
# This prevents malicious git hooks from being trusted in arbitrary directories
git config --global --add safe.directory "$WORKSPACE" 2>/dev/null || true

# ── Sync configs from DevSecOps repo ──
DEVSECOPS_RAW="https://raw.githubusercontent.com/Area-tech-alpha/DevSecOps/main"
CONFIG_CACHE_FILE="/tmp/.alpha-ci-config-synced"
CONFIG_CACHE_TTL=3600  # 1 hour

# SECURITY: Validate downloaded config files are not malicious
validate_config_file() {
  local file="$1"
  local ext="${file##*.}"
  
  # Block executable content in non-JS config files
  if [ "$ext" = "toml" ]; then
    # TOML files should not contain shell commands or JS
    if grep -qE '(exec|spawn|child_process|require\(|import |\$\(|`.*`)' "$file" 2>/dev/null; then
      echo -e "  ${RED}🚨 Config rejeitado: conteúdo suspeito em $file${NC}"
      rm -f "$file"
      return 1
    fi
  fi
  return 0
}

sync_configs() {
  # Skip if recently synced (cache TTL)
  if [ -f "$CONFIG_CACHE_FILE" ]; then
    local last_sync=$(cat "$CONFIG_CACHE_FILE" 2>/dev/null || echo 0)
    local now=$(date +%s)
    if (( now - last_sync < CONFIG_CACHE_TTL )); then
      [ "$VERBOSE" = "true" ] && echo -e "  ${DIM}⏩ Configs sincronizados recentemente, usando cache${NC}"
      return 0
    fi
  fi

  echo -e "${CYAN}🔄 Sincronizando configs do DevSecOps...${NC}"

  local sync_ok=true

  # Security configs
  mkdir -p "$CONFIG_DIR/security" 2>/dev/null || true
  curl -fsSL --max-time 10 "$DEVSECOPS_RAW/security/gitleaks.toml" -o "$CONFIG_DIR/security/gitleaks.toml.tmp" 2>/dev/null \
    && validate_config_file "$CONFIG_DIR/security/gitleaks.toml.tmp" \
    && mv "$CONFIG_DIR/security/gitleaks.toml.tmp" "$CONFIG_DIR/security/gitleaks.toml" \
    && echo -e "  ${GREEN}✓${NC} gitleaks.toml atualizado" \
    || { echo -e "  ${DIM}⚠ gitleaks.toml — usando versão embarcada${NC}"; sync_ok=false; }

  curl -fsSL --max-time 10 "$DEVSECOPS_RAW/security/osv-scanner.toml" -o "$CONFIG_DIR/security/osv-scanner.toml.tmp" 2>/dev/null \
    && validate_config_file "$CONFIG_DIR/security/osv-scanner.toml.tmp" \
    && mv "$CONFIG_DIR/security/osv-scanner.toml.tmp" "$CONFIG_DIR/security/osv-scanner.toml" \
    && echo -e "  ${GREEN}✓${NC} osv-scanner.toml atualizado" \
    || { echo -e "  ${DIM}⚠ osv-scanner.toml — usando versão embarcada${NC}"; sync_ok=false; }

  # Lint configs
  mkdir -p "$CONFIG_DIR/lint" 2>/dev/null || true
  # SECURITY: eslint.config.mjs is executable JS — only sync if content looks safe
  curl -fsSL --max-time 10 "$DEVSECOPS_RAW/lint/eslint.config.mjs" -o "$CONFIG_DIR/lint/eslint.config.mjs.tmp" 2>/dev/null \
    && if grep -qE '(child_process|execSync|spawnSync|\bexec\b|\bspawn\b|require\(.fs.)' "$CONFIG_DIR/lint/eslint.config.mjs.tmp" 2>/dev/null; then
         echo -e "  ${RED}🚨 eslint.config.mjs rejeitado: imports perigosos detectados${NC}"
         rm -f "$CONFIG_DIR/lint/eslint.config.mjs.tmp"
         sync_ok=false
       else
         mv "$CONFIG_DIR/lint/eslint.config.mjs.tmp" "$CONFIG_DIR/lint/eslint.config.mjs"
         echo -e "  ${GREEN}✓${NC} eslint.config.mjs atualizado"
       fi \
    || { echo -e "  ${DIM}⚠ eslint.config.mjs — usando versão embarcada${NC}"; sync_ok=false; }

  # NOTE: .eslintignore removido — ESLint 9 Flat Config ignora esse arquivo.
  # Os padrões de ignore estão definidos no campo `ignores` do eslint.config.mjs.

  curl -fsSL --max-time 10 "$DEVSECOPS_RAW/lint/.editorconfig" -o "$CONFIG_DIR/lint/.editorconfig.tmp" 2>/dev/null \
    && mv "$CONFIG_DIR/lint/.editorconfig.tmp" "$CONFIG_DIR/lint/.editorconfig" \
    && echo -e "  ${GREEN}✓${NC} .editorconfig atualizado" \
    || { echo -e "  ${DIM}⚠ .editorconfig — usando versão embarcada${NC}"; sync_ok=false; }

  # Marca timestamp do sync
  date +%s > "$CONFIG_CACHE_FILE"

  if [ "$sync_ok" = "true" ]; then
    echo -e "  ${GREEN}✅ Todos os configs sincronizados com DevSecOps/main${NC}"
  else
    echo -e "  ${YELLOW}⚠️ Alguns configs não puderam ser atualizados (offline?)${NC}"
  fi
  echo ""
}

sync_configs


# ── Source detection ──
source "$SCRIPTS_DIR/detect.sh"

# ── Timer ──
TIMER_START=$(date +%s)

run_stage() {
  local name="$1"
  local script="$2"
  local emoji="$3"

  echo ""
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  ${emoji}  ${name}${NC}"
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"
  echo ""

  local stage_start=$(date +%s)

  set +e
  bash "$SCRIPTS_DIR/$script"
  local exit_code=$?
  set -e

  local stage_end=$(date +%s)
  local stage_dur=$((stage_end - stage_start))

  if [ $exit_code -eq 0 ]; then
    echo -e "\n  ${GREEN}✅ ${name} — PASSED${NC} ${DIM}(${stage_dur}s)${NC}"
  else
    echo -e "\n  ${RED}❌ ${name} — FAILED (exit $exit_code)${NC} ${DIM}(${stage_dur}s)${NC}"
  fi

  return $exit_code
}

summary() {
  local overall_exit=$1
  shift
  local results=("$@")

  local TIMER_END=$(date +%s)
  local DURATION=$((TIMER_END - TIMER_START))

  echo ""
  echo -e "${BOLD}${MAGENTA}══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  📊  Alpha CI — Pipeline Summary${NC}"
  echo -e "${BOLD}${MAGENTA}══════════════════════════════════════════════════${NC}"
  echo ""

  for result in "${results[@]}"; do
    local stage_name="${result%%:*}"
    local stage_status="${result##*:}"
    if [ "$stage_status" = "0" ]; then
      echo -e "  ${GREEN}✅${NC} ${stage_name}"
    elif [ "$stage_status" = "skip" ]; then
      echo -e "  ${DIM}⏩${NC} ${stage_name} ${DIM}(skipped)${NC}"
    else
      echo -e "  ${RED}❌${NC} ${stage_name}"
    fi
  done

  echo ""
  echo -e "  ${DIM}⏱  Duration: ${DURATION}s${NC}"

  if [ "$overall_exit" -eq 0 ]; then
    echo ""
    echo -e "  ${GREEN}${BOLD}🎉 All checks passed!${NC}"
  else
    echo ""
    echo -e "  ${RED}${BOLD}💀 Pipeline failed. Fix the issues above.${NC}"
  fi
  echo ""

  # ── Generate consolidated report if requested ──
  if [ -n "$REPORT_OUTPUT" ] && [ "$REPORT_FORMAT" != "text" ]; then
    generate_report "$overall_exit" "$DURATION" "${results[@]}"
  fi

  return "$overall_exit"
}

generate_report() {
  local exit_code="$1"
  local duration="$2"
  shift 2
  local results=("$@")

  echo -e "${CYAN}📄 Gerando relatório ($REPORT_FORMAT)...${NC}"

  local status="passed"
  [ "$exit_code" -ne 0 ] && status="failed"

  local stages_json="[]"
  for result in "${results[@]}"; do
    local stage_name="${result%%:*}"
    local stage_status="${result##*:}"
    local s_status="passed"
    [ "$stage_status" != "0" ] && s_status="failed"
    [ "$stage_status" = "skip" ] && s_status="skipped"
    stages_json=$(echo "$stages_json" | jq --arg name "$stage_name" --arg st "$s_status" '. + [{"name": $name, "status": $st}]')
  done

  # Collect tool outputs if available
  local gitleaks_json="{}"
  local osv_json="{}"
  local semgrep_json="{}"

  [ -f /tmp/gitleaks-report.json ] && gitleaks_json=$(cat /tmp/gitleaks-report.json 2>/dev/null || echo "{}")
  [ -f /tmp/osv-results.json ] && osv_json=$(cat /tmp/osv-results.json 2>/dev/null || echo "{}")
  [ -f /tmp/semgrep-report.json ] && semgrep_json=$(cat /tmp/semgrep-report.json 2>/dev/null || echo "{}")

  if [ "$REPORT_FORMAT" = "json" ]; then
    jq -n \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg status "$status" \
      --argjson duration "$duration" \
      --argjson stages "$stages_json" \
      --argjson gitleaks "$gitleaks_json" \
      --argjson osv "$osv_json" \
      --argjson semgrep "$semgrep_json" \
      '{
        "alpha_ci_report": {
          "version": "1.0.0",
          "timestamp": $ts,
          "status": $status,
          "duration_seconds": $duration,
          "stages": $stages,
          "security_details": {
            "gitleaks": $gitleaks,
            "osv_scanner": $osv,
            "semgrep": $semgrep
          }
        }
      }' > "$REPORT_OUTPUT"

    echo -e "  ${GREEN}✅ Relatório salvo: $REPORT_OUTPUT${NC}"

  elif [ "$REPORT_FORMAT" = "sarif" ]; then
    # SARIF 2.1.0 format for GitHub Security tab integration
    jq -n \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson semgrep "$semgrep_json" \
      '{
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [
          {
            "tool": {
              "driver": {
                "name": "Alpha CI",
                "version": "1.0.0",
                "informationUri": "https://github.com/Area-tech-alpha/DevSecOps"
              }
            },
            "results": [],
            "invocations": [
              {
                "executionSuccessful": true,
                "endTimeUtc": $ts
              }
            ]
          }
        ]
      }' > "$REPORT_OUTPUT"

    echo -e "  ${GREEN}✅ SARIF salvo: $REPORT_OUTPUT${NC}"
  fi
}

sync_back_to_host() {
  if [ -d "/host_workspace" ]; then
    echo -e "\n  ${DIM}ℹ️  Sincronizando arquivos de volta para o host...${NC}"
    
    # Redireciona os erros do tar para um arquivo para podermos analisá-los
    set +e
    tar --exclude='node_modules' --exclude='.git' -cf - -C /workspace . | tar --no-same-owner --no-same-permissions -xf - -C /host_workspace 2> /tmp/sync-errors.log
    local tar_exit_code=$?
    set -e

    if [ -s /tmp/sync-errors.log ] || [ $tar_exit_code -ne 0 ]; then
      echo -e "  ${YELLOW}⚠️  Aviso: Alguns arquivos não puderam ser sincronizados de volta para o host.${NC}"
      
      # Verifica se é erro de permissão negada (comum quando há arquivos do root de execuções antigas)
      if grep -qi "permission denied" /tmp/sync-errors.log || grep -qi "operation not permitted" /tmp/sync-errors.log; then
        echo -e "  ${DIM}Isso geralmente ocorre por dois motivos:${NC}"
        echo -e "  ${DIM}1. Arquivos criados por versões antigas (root) bloqueando a sobrescrita.${NC}"
        echo -e "  ${DIM}2. Restrições de permissão do Docker no Windows/Mac.${NC}"
        echo -e "  ${CYAN}💡 Solução (no Linux/Mac): Rode 'sudo chown -R $(id -u):$(id -g) .' na pasta do projeto.${NC}"
      else
        # Mostra as primeiras 3 linhas do erro para debug
        head -n 3 /tmp/sync-errors.log | while read -r line; do
          echo -e "  ${DIM}> $line${NC}"
        done
      fi
    fi
  fi
}

# ── Dispatch ──
case "$COMMAND" in
  all)
    banner
    detect_project

    OVERALL=0
    RESULTS=()

    # Security
    if run_stage "Security Scan" "run-security.sh" "🔐"; then
      RESULTS+=("🔐 Security:0")
    else
      RESULTS+=("🔐 Security:1")
      OVERALL=1
    fi

    # Lint
    if run_stage "Lint" "run-lint.sh" "🔍"; then
      RESULTS+=("🔍 Lint:0")
    else
      RESULTS+=("🔍 Lint:1")
      OVERALL=1
    fi

    # Test
    if run_stage "Unit Tests" "run-test.sh" "🧪"; then
      RESULTS+=("🧪 Unit Tests:0")
    else
      RESULTS+=("🧪 Unit Tests:1")
      OVERALL=1
    fi

    # Build
    if run_stage "Build" "run-build.sh" "🏗"; then
      RESULTS+=("🏗  Build:0")
    else
      RESULTS+=("🏗  Build:1")
      OVERALL=1
    fi

    summary "$OVERALL" "${RESULTS[@]}"
    sync_back_to_host
    ;;

  security)
    banner
    detect_project
    run_stage "Security Scan" "run-security.sh" "🔐"
    sync_back_to_host
    ;;

  lint)
    banner
    detect_project
    run_stage "Lint" "run-lint.sh" "🔍"
    sync_back_to_host
    ;;

  test)
    banner
    detect_project
    run_stage "Unit Tests" "run-test.sh" "🧪"
    sync_back_to_host
    ;;

  build)
    banner
    detect_project
    run_stage "Build" "run-build.sh" "🏗"
    sync_back_to_host
    ;;

  e2e)
    banner
    detect_project
    run_stage "E2E Tests" "run-e2e.sh" "🧪"
    ;;

  detect)
    banner
    detect_project
    echo -e "\n${BOLD}Detected features:${NC}"
    [ "$IS_NODE" = "true" ] && echo -e "  ${GREEN}✅${NC} Node.js"
    [ "$IS_REACT" = "true" ] && echo -e "  ${GREEN}✅${NC} React"
    [ "$IS_TYPESCRIPT" = "true" ] && echo -e "  ${GREEN}✅${NC} TypeScript"
    [ "$IS_PYTHON" = "true" ] && echo -e "  ${GREEN}✅${NC} Python"
    [ "$IS_GO" = "true" ] && echo -e "  ${GREEN}✅${NC} Go"
    [ "$IS_DOCKER" = "true" ] && echo -e "  ${GREEN}✅${NC} Docker"
    [ "$IS_MONOREPO" = "true" ] && echo -e "  ${GREEN}✅${NC} Monorepo"
    [ -n "$NODE_RUNNER" ] && echo -e "  ${CYAN}🧪${NC} Test runner: $NODE_RUNNER"
    [ "$HAS_NODE_TEST" = "true" ] && echo -e "  ${CYAN}🧪${NC} Node tests found"
    [ "$HAS_PYTHON_TEST" = "true" ] && echo -e "  ${CYAN}🧪${NC} Python tests found"
    [ "$HAS_GO_TEST" = "true" ] && echo -e "  ${CYAN}🧪${NC} Go tests found"
    [ -n "$E2E_FRAMEWORK" ] && echo -e "  ${CYAN}🧪${NC} E2E framework: $E2E_FRAMEWORK"
    [ "$IS_MONOREPO" = "true" ] && [ -n "$MONOREPO_DIRS" ] && echo -e "  ${CYAN}📦${NC} Workspaces: $(echo "$MONOREPO_DIRS" | wc -w)"
    echo ""
    ;;

  shell)
    banner
    detect_project
    echo -e "${YELLOW}Entering interactive shell...${NC}"
    echo -e "${DIM}DevSecOps configs at: /opt/alpha-ci/config/${NC}"
    echo -e "${DIM}Workspace at: /workspace/${NC}"
    echo ""
    exec /bin/bash
    ;;

  help|--help|-h)
    usage
    exit 0
    ;;

  *)
    echo -e "${RED}❌ Unknown command: ${COMMAND}${NC}"
    usage
    exit 1
    ;;
esac
