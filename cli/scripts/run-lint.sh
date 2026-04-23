#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Lint Runner                                      ║
# ║  Replica alpha-lint.yml do GitHub Actions                    ║
# ║  ESLint (Node/TS) + Ruff (Python) + golangci-lint (Go)       ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail
cd "$WORKSPACE"

CONFIG_LINT="/opt/alpha-ci/config/lint"
LINT_RAN=false
OVERALL_EXIT=0

# ── Auto-fix mode ──
FIX_FLAG=""
RUFF_FIX_FLAG=""
GOLANGCI_FIX_FLAG=""

if [ "${AUTO_FIX:-false}" = "true" ]; then
  FIX_FLAG="--fix"
  RUFF_FIX_FLAG="--fix"
  GOLANGCI_FIX_FLAG="--fix"
  echo -e "${YELLOW}🔧 Modo auto-fix ativado${NC}"
  echo ""
fi

# ══════════════════════════════════════════
# 📦 NODE / TYPESCRIPT LINTING
# ══════════════════════════════════════════

if [ "$IS_NODE" = "true" ]; then
  LINT_RAN=true
  echo -e "${CYAN}📦 Instalando dependências do projeto...${NC}"

  # Instalar dependências do projeto (necessário para ESLint resolver imports)
  if [ ! -d node_modules ]; then
    if [ -f pnpm-lock.yaml ]; then
      pnpm install --frozen-lockfile 2>/dev/null || pnpm install
    elif [ -f yarn.lock ]; then
      yarn install --frozen-lockfile 2>/dev/null || yarn install
    elif [ -f package-lock.json ]; then
      npm ci --legacy-peer-deps 2>/dev/null || npm install --legacy-peer-deps
    else
      npm install --legacy-peer-deps
    fi
  else
    echo -e "  ${DIM}node_modules já existe, pulando install${NC}"
  fi

  # ── Monorepo: install em cada workspace ──
  if [ "${IS_MONOREPO:-false}" = "true" ] && [ -n "${MONOREPO_DIRS:-}" ]; then
    echo -e "${CYAN}📦 Monorepo detectado — instalando deps dos workspaces...${NC}"
    for ws_pattern in $MONOREPO_DIRS; do
      # Expande globs como "packages/*"
      for ws_dir in $ws_pattern; do
        if [ -d "$ws_dir" ] && [ -f "$ws_dir/package.json" ]; then
          echo -e "  ${DIM}→ $ws_dir${NC}"
          (cd "$ws_dir" && [ ! -d node_modules ] && npm install --legacy-peer-deps 2>/dev/null) || true
        fi
      done
    done
  fi

  echo -e "\n${CYAN}🔍 Rodando ESLint (config centralizado)...${NC}"

  export ESLINT_USE_FLAT_CONFIG=true
  export DATABASE_URL="${DATABASE_URL:-postgresql://ci:ci@localhost:5432/ci_dummy}"

  # Determine ESLint binary and config path
  ESLINT_BIN="$CONFIG_LINT/node_modules/.bin/eslint"
  ESLINT_CONFIG="$CONFIG_LINT/eslint.config.mjs"

  # Fallback: se config centralizado não existe (--no-docker mode)
  if [ ! -f "$ESLINT_BIN" ]; then
    if [ -f "./node_modules/.bin/eslint" ]; then
      ESLINT_BIN="./node_modules/.bin/eslint"
      echo -e "  ${DIM}Usando ESLint local do projeto${NC}"
    elif command -v eslint &>/dev/null; then
      ESLINT_BIN="eslint"
      echo -e "  ${DIM}Usando ESLint global${NC}"
    else
      echo -e "  ${YELLOW}⚠️ ESLint não encontrado — pulando lint Node${NC}"
      ESLINT_BIN=""
    fi
  fi

  if [ ! -f "$ESLINT_CONFIG" ]; then
    # Tenta usar config do projeto
    if [ -f "eslint.config.mjs" ] || [ -f "eslint.config.js" ] || [ -f ".eslintrc.json" ] || [ -f ".eslintrc.js" ]; then
      ESLINT_CONFIG=""
      echo -e "  ${DIM}Usando config ESLint do projeto${NC}"
    fi
  fi

  if [ -n "$ESLINT_BIN" ]; then
    set +e

    # SECURITY: Use bash array for arguments (prevents word splitting / injection)
    ESLINT_ARGS=(".")
    [ -n "$ESLINT_CONFIG" ] && ESLINT_ARGS+=("--config" "$ESLINT_CONFIG")
    ESLINT_ARGS+=("--no-error-on-unmatched-pattern")
    [ -n "$FIX_FLAG" ] && ESLINT_ARGS+=("$FIX_FLAG")

    # Mute warnings to prevent output pollution unless VERBOSE is true
    if [ "${VERBOSE:-false}" != "true" ]; then
      ESLINT_ARGS+=("--quiet")
    fi

    # Run ESLint and capture output
    "$ESLINT_BIN" "${ESLINT_ARGS[@]}" > /tmp/eslint-output.log 2>&1
    ESLINT_EXIT=$?
    set -e

    if [ $ESLINT_EXIT -ne 0 ]; then
      echo -e "  ${RED}❌ ESLint encontrou problemas:${NC}"
      
      # Exibir apenas as primeiras linhas se for muito longo
      TOTAL_LINES=$(wc -l < /tmp/eslint-output.log)
      if [ "$TOTAL_LINES" -gt 30 ] && [ "${VERBOSE:-false}" != "true" ]; then
        head -n 25 /tmp/eslint-output.log
        echo -e "\n  ${DIM}... ($((TOTAL_LINES - 25)) linhas ocultadas. Use --verbose para ver tudo) ...${NC}\n"
        tail -n 3 /tmp/eslint-output.log
      else
        cat /tmp/eslint-output.log
      fi
      
      OVERALL_EXIT=1
    else
      echo -e "  ${GREEN}✅ ESLint: Sem problemas${NC}"
    fi
  fi
fi

# ══════════════════════════════════════════
# 🐍 PYTHON LINTING
# ══════════════════════════════════════════

if [ "$IS_PYTHON" = "true" ]; then
  LINT_RAN=true

  if command -v ruff &>/dev/null; then
    echo -e "\n${CYAN}🐍 Rodando Ruff (Python Linter)...${NC}"

    # SECURITY: Use bash array for arguments
    RUFF_ARGS=("check" ".")
    [ -n "$RUFF_FIX_FLAG" ] && RUFF_ARGS+=("$RUFF_FIX_FLAG")

    set +e
    ruff "${RUFF_ARGS[@]}"
    RUFF_EXIT=$?
    set -e

    if [ $RUFF_EXIT -ne 0 ]; then
      echo -e "  ${RED}❌ Ruff encontrou problemas${NC}"
      OVERALL_EXIT=1
    else
      echo -e "  ${GREEN}✅ Ruff: Sem problemas${NC}"
    fi
  else
    echo -e "\n${YELLOW}⚠️ Ruff não encontrado — pulando lint Python${NC}"
  fi
fi

# ══════════════════════════════════════════
# 🐹 GO LINTING
# ══════════════════════════════════════════

if [ "$IS_GO" = "true" ]; then
  LINT_RAN=true

  if command -v golangci-lint &>/dev/null; then
    echo -e "\n${CYAN}🐹 Rodando golangci-lint (Go Linter)...${NC}"

    # SECURITY: Use bash array for arguments
    GOLANGCI_ARGS=("run" "./...")
    [ -n "$GOLANGCI_FIX_FLAG" ] && GOLANGCI_ARGS+=("$GOLANGCI_FIX_FLAG")

    set +e
    golangci-lint "${GOLANGCI_ARGS[@]}"
    GOLANGCI_EXIT=$?
    set -e

    if [ $GOLANGCI_EXIT -ne 0 ]; then
      echo -e "  ${RED}❌ golangci-lint encontrou problemas${NC}"
      OVERALL_EXIT=1
    else
      echo -e "  ${GREEN}✅ golangci-lint: Sem problemas${NC}"
    fi
  else
    echo -e "\n${YELLOW}⚠️ golangci-lint não encontrado — pulando lint Go${NC}"
    echo -e "  ${DIM}Instale: https://golangci-lint.run/usage/install/${NC}"
  fi
fi

# ══════════════════════════════════════════

if [ "$LINT_RAN" = "false" ]; then
  echo -e "${DIM}ℹ️  Nenhum framework de lint aplicável detectado.${NC}"
fi

exit $OVERALL_EXIT
