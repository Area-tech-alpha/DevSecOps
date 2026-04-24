#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Test Runner                                      ║
# ║  Replica alpha-test.yml do GitHub Actions                    ║
# ║  Jest/Vitest (Node) + pytest (Python) + go test (Go)         ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail
cd "$WORKSPACE"

TESTS_RAN=false
OVERALL_EXIT=0

# ══════════════════════════════════════════
# 📦 NODE.JS — Unit Tests
# ══════════════════════════════════════════

if [ "$HAS_NODE_TEST" = "true" ]; then
  TESTS_RAN=true

  # Instalar dependências se necessário
  if [ ! -d node_modules ]; then
    echo -e "${CYAN}📦 Instalando dependências Node...${NC}"
    if [ -f pnpm-lock.yaml ]; then
      pnpm install --frozen-lockfile 2>/dev/null || pnpm install
    elif [ -f yarn.lock ]; then
      yarn install --frozen-lockfile 2>/dev/null || yarn install
    elif [ -f package-lock.json ]; then
      npm ci --legacy-peer-deps 2>/dev/null || npm install --legacy-peer-deps
    else
      npm install --legacy-peer-deps
    fi
  fi

  # Prisma generate (se necessário)
  if [ -f prisma/schema.prisma ]; then
    echo -e "${CYAN}⚡ Generating Prisma Client...${NC}"
    # Workaround for Windows/Docker EPERM on copyfile: delete old client first
    rm -rf node_modules/.prisma 2>/dev/null || true
    DATABASE_URL="${DATABASE_URL:-postgresql://ci:ci@localhost:5432/ci_dummy}" npx prisma generate
  fi

  # Determina flags baseado no runner
  TEST_FLAGS=""
  if [ "$NODE_RUNNER" = "jest" ]; then
    TEST_FLAGS="-- --forceExit --detectOpenHandles --passWithNoTests"
  elif [ "$NODE_RUNNER" = "vitest" ]; then
    TEST_FLAGS="-- --passWithNoTests"
  fi

  # Prefere test:unit se existir
  set +e
  if node -e "process.exit(require('./package.json').scripts?.['test:unit'] ? 0 : 1)" 2>/dev/null; then
    echo -e "\n${CYAN}🧪 Executando: npm run test:unit $TEST_FLAGS${NC}"
    CI=true NODE_ENV=test DATABASE_URL="${DATABASE_URL:-postgresql://ci:ci@localhost:5432/ci_dummy}" \
      npm run test:unit $TEST_FLAGS
    NODE_EXIT=$?
  else
    echo -e "\n${CYAN}🧪 Executando: npm test $TEST_FLAGS${NC}"
    CI=true NODE_ENV=test DATABASE_URL="${DATABASE_URL:-postgresql://ci:ci@localhost:5432/ci_dummy}" \
      npm test $TEST_FLAGS
    NODE_EXIT=$?
  fi
  set -e

  if [ $NODE_EXIT -ne 0 ]; then
    echo -e "  ${RED}❌ Testes Node falharam${NC}"
    OVERALL_EXIT=1
  else
    echo -e "  ${GREEN}✅ Testes Node: Todos passaram${NC}"
  fi
fi

# ══════════════════════════════════════════
# 🐍 PYTHON — Unit Tests
# ══════════════════════════════════════════

if [ "$HAS_PYTHON_TEST" = "true" ]; then
  TESTS_RAN=true

  echo -e "\n${CYAN}🐍 Instalando dependências Python...${NC}"
  pip install --break-system-packages -q pytest pytest-cov 2>/dev/null || true

  if [ -f requirements.txt ]; then
    pip install --break-system-packages -q -r requirements.txt 2>/dev/null || true
  elif [ -f pyproject.toml ]; then
    pip install --break-system-packages -q . 2>/dev/null || true
  fi

  echo -e "\n${CYAN}🧪 Executando testes Python com pytest${NC}"
  set +e
  CI=true pytest -q --tb=short
  PY_EXIT=$?
  set -e

  if [ $PY_EXIT -ne 0 ]; then
    echo -e "  ${RED}❌ Testes Python falharam${NC}"
    OVERALL_EXIT=1
  else
    echo -e "  ${GREEN}✅ Testes Python: Todos passaram${NC}"
  fi
fi

# ══════════════════════════════════════════
# 🐹 GO — Unit Tests
# ══════════════════════════════════════════

if [ "$HAS_GO_TEST" = "true" ]; then
  TESTS_RAN=true

  echo -e "\n${CYAN}🐹 Executando testes Go${NC}"
  set +e
  CI=true go test ./... -v -count=1
  GO_EXIT=$?
  set -e

  if [ $GO_EXIT -ne 0 ]; then
    echo -e "  ${RED}❌ Testes Go falharam${NC}"
    OVERALL_EXIT=1
  else
    echo -e "  ${GREEN}✅ Testes Go: Todos passaram${NC}"
  fi
fi

# ══════════════════════════════════════════

if [ "$TESTS_RAN" = "false" ]; then
  echo -e "${DIM}ℹ️  Nenhum framework de teste detectado. Job pulado.${NC}"
fi

exit $OVERALL_EXIT
