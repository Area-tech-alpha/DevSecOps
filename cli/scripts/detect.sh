#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Project Detection                                ║
# ║  Detecta tipo de projeto, frameworks e runners de teste      ║
# ║  Lógica unificada extraída dos workflows do GitHub Actions   ║
# ╚══════════════════════════════════════════════════════════════╝

# Exporta variáveis globais de detecção
IS_NODE=false
IS_REACT=false
IS_TYPESCRIPT=false
IS_PYTHON=false
IS_GO=false
IS_DOCKER=false
IS_MONOREPO=false
IS_SWC=false
MONOREPO_DIRS=""
NODE_RUNNER=""
HAS_NODE_TEST=false
HAS_PYTHON_TEST=false
HAS_GO_TEST=false
E2E_FRAMEWORK=""

detect_project() {
  echo -e "${CYAN}🔍 Detectando tipo de projeto...${NC}"

  cd "$WORKSPACE" 2>/dev/null || true

  # ── Node.js ──
  if [ -s package.json ] && jq -e . package.json >/dev/null 2>&1; then
    IS_NODE=true
    echo -e "  ${GREEN}✓${NC} Node.js detectado (package.json)"

    # React?
    if jq -e '.dependencies.react or .devDependencies.react' package.json >/dev/null 2>&1; then
      IS_REACT=true
      echo -e "  ${GREEN}✓${NC} React detectado"
    fi

    # TypeScript?
    if [ -f tsconfig.json ]; then
      IS_TYPESCRIPT=true
      echo -e "  ${GREEN}✓${NC} TypeScript detectado"
    fi

    # SWC?
    if [ -f .swcrc ] || grep -q '"@swc/cli"' package.json 2>/dev/null || grep -q '"@swc/core"' package.json 2>/dev/null; then
      IS_SWC=true
      echo -e "  ${GREEN}✓${NC} SWC detectado"
    fi

    # ── Monorepo Detection ──
    # pnpm workspaces
    if [ -f pnpm-workspace.yaml ]; then
      IS_MONOREPO=true
      echo -e "  ${GREEN}✓${NC} Monorepo detectado (pnpm-workspace.yaml)"
      # Extrai workspace dirs do pnpm-workspace.yaml
      MONOREPO_DIRS=$(grep -E '^\s*-\s+' pnpm-workspace.yaml 2>/dev/null \
        | sed "s/^[[:space:]]*-[[:space:]]*//" \
        | sed "s/['\"]//g" \
        | tr '\n' ' ')
    fi

    # npm/yarn workspaces
    if jq -e '.workspaces' package.json >/dev/null 2>&1; then
      IS_MONOREPO=true
      echo -e "  ${GREEN}✓${NC} Monorepo detectado (workspaces em package.json)"
      MONOREPO_DIRS=$(jq -r '.workspaces | if type == "array" then .[] else .packages[]? end' package.json 2>/dev/null | tr '\n' ' ')
    fi

    # lerna
    if [ -f lerna.json ]; then
      IS_MONOREPO=true
      echo -e "  ${GREEN}✓${NC} Monorepo detectado (lerna.json)"
      if [ -z "$MONOREPO_DIRS" ]; then
        MONOREPO_DIRS=$(jq -r '.packages[]?' lerna.json 2>/dev/null | tr '\n' ' ')
      fi
    fi

    # nx
    if [ -f nx.json ]; then
      IS_MONOREPO=true
      echo -e "  ${GREEN}✓${NC} Monorepo detectado (nx.json)"
    fi

    # turborepo
    if [ -f turbo.json ]; then
      IS_MONOREPO=true
      echo -e "  ${GREEN}✓${NC} Monorepo detectado (turbo.json)"
    fi

    if [ "$IS_MONOREPO" = "true" ] && [ -n "$MONOREPO_DIRS" ]; then
      echo -e "  ${DIM}  Workspaces: ${MONOREPO_DIRS}${NC}"
    fi

    # Test runner: Jest ou Vitest
    if grep -q '"jest"' package.json 2>/dev/null; then
      NODE_RUNNER="jest"
      echo -e "  ${GREEN}✓${NC} Jest detectado como test runner"
    elif grep -q '"vitest"' package.json 2>/dev/null; then
      NODE_RUNNER="vitest"
      echo -e "  ${GREEN}✓${NC} Vitest detectado como test runner"
    fi

    # Verifica se existe script de test
    if node -e "
      const pkg = require('./package.json');
      const scripts = pkg.scripts || {};
      if (scripts['test:unit'] || scripts['test']) process.exit(0);
      process.exit(1);
    " 2>/dev/null; then
      HAS_NODE_TEST=true
      echo -e "  ${GREEN}✓${NC} Script de teste Node encontrado"
    fi

    # E2E Framework
    if ls playwright.config.* 1>/dev/null 2>&1; then
      E2E_FRAMEWORK="playwright"
      echo -e "  ${GREEN}✓${NC} Playwright detectado (E2E)"
    elif ls cypress.config.* 1>/dev/null 2>&1; then
      E2E_FRAMEWORK="cypress"
      echo -e "  ${GREEN}✓${NC} Cypress detectado (E2E)"
    fi
  fi

  # ── Python ──
  if [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f setup.py ]; then
    IS_PYTHON=true
    echo -e "  ${GREEN}✓${NC} Python detectado"

    if [ -d tests ] || [ -d test ]; then
      HAS_PYTHON_TEST=true
      echo -e "  ${GREEN}✓${NC} Diretório de testes Python encontrado"
    fi
  fi

  # ── Go ──
  if [ -f go.mod ]; then
    IS_GO=true
    echo -e "  ${GREEN}✓${NC} Go detectado"

    if find . -name '*_test.go' -not -path './vendor/*' -not -path './node_modules/*' | grep -q .; then
      HAS_GO_TEST=true
      echo -e "  ${GREEN}✓${NC} Arquivos _test.go encontrados"
    fi
  fi

  # ── Docker ──
  if [ -f Dockerfile ]; then
    IS_DOCKER=true
    echo -e "  ${GREEN}✓${NC} Dockerfile detectado"
  fi

  # Export all vars
  export IS_NODE IS_REACT IS_TYPESCRIPT IS_PYTHON IS_GO IS_DOCKER IS_MONOREPO MONOREPO_DIRS IS_SWC
  export NODE_RUNNER HAS_NODE_TEST HAS_PYTHON_TEST HAS_GO_TEST E2E_FRAMEWORK

  echo ""
}
