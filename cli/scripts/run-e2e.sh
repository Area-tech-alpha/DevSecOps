#!/usr/bin/env bash
# Alpha CI — E2E Runner (alpha-e2e.yml replica)
set -euo pipefail
cd "$WORKSPACE"

if [ -z "$E2E_FRAMEWORK" ] || [ "$E2E_FRAMEWORK" = "" ]; then
  echo -e "${DIM}ℹ️  Nenhum framework E2E (Playwright/Cypress) detectado. Pulando.${NC}"
  exit 0
fi

# Instalar dependências do projeto
if [ ! -d node_modules ]; then
  echo -e "${CYAN}📦 Instalando dependências...${NC}"
  if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile 2>/dev/null || pnpm install
  elif [ -f yarn.lock ]; then yarn install --frozen-lockfile 2>/dev/null || yarn install
  elif [ -f package-lock.json ]; then npm ci --legacy-peer-deps 2>/dev/null || npm install --legacy-peer-deps
  else npm install --legacy-peer-deps; fi
fi

# Build (necessário para webserver local nos E2E)
if node -e "process.exit(require('./package.json').scripts?.['build'] ? 0 : 1)" 2>/dev/null; then
  echo -e "${CYAN}🏗 Building project (necessário para E2E)...${NC}"
  npm run build
fi

# ── Playwright ──
if [ "$E2E_FRAMEWORK" = "playwright" ]; then
  echo -e "\n${CYAN}🎭 Configurando Playwright...${NC}"

  # Instalar browsers
  if npm run 2>/dev/null | grep -q "test:e2e:install"; then
    npm run test:e2e:install -- chromium
  else
    ./node_modules/.bin/playwright install chromium
  fi
  ./node_modules/.bin/playwright install-deps chromium

  # Executar
  echo -e "\n${CYAN}🧪 Executando testes E2E (Playwright)...${NC}"
  set +e
  if node -e "process.exit(require('./package.json').scripts?.['test:e2e'] ? 0 : 1)" 2>/dev/null; then
    CI=true npm run test:e2e
  else
    CI=true ./node_modules/.bin/playwright test
  fi
  E2E_EXIT=$?
  set -e

# ── Cypress ──
elif [ "$E2E_FRAMEWORK" = "cypress" ]; then
  echo -e "\n${CYAN}🌲 Executando testes E2E (Cypress)...${NC}"
  set +e
  if node -e "process.exit(require('./package.json').scripts?.['test:e2e'] ? 0 : 1)" 2>/dev/null; then
    CI=true npm run test:e2e
  else
    CI=true ./node_modules/.bin/cypress run
  fi
  E2E_EXIT=$?
  set -e
fi

if [ ${E2E_EXIT:-0} -ne 0 ]; then
  echo -e "  ${RED}❌ E2E Tests falharam${NC}"
  exit 1
else
  echo -e "  ${GREEN}✅ E2E Tests: Todos passaram${NC}"
  exit 0
fi
