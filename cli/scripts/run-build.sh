#!/usr/bin/env bash
# Alpha CI — Build Runner (alpha-build.yml replica)
set -euo pipefail
cd "$WORKSPACE"

BUILD_RAN=false
OVERALL_EXIT=0

if [ "$IS_NODE" = "true" ]; then
  if ! jq . package.json >/dev/null 2>&1; then
    echo -e "${RED}❌ package.json inválido${NC}"; exit 1
  fi

  if [ ! -d node_modules ]; then
    echo -e "${CYAN}📦 Instalando dependências...${NC}"
    if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile 2>/dev/null || pnpm install
    elif [ -f yarn.lock ]; then yarn install --frozen-lockfile 2>/dev/null || yarn install
    elif [ -f package-lock.json ]; then npm ci --legacy-peer-deps 2>/dev/null || npm install --legacy-peer-deps
    else npm install --legacy-peer-deps; fi
  fi

  if [ -f prisma/schema.prisma ]; then
    echo -e "${CYAN}⚡ Generating Prisma Client...${NC}"
    # Workaround for Windows/Docker EPERM on copyfile: delete old client first
    rm -rf node_modules/.prisma 2>/dev/null || true
    set +e
    DATABASE_URL="${DATABASE_URL:-postgresql://ci:ci@localhost:5432/ci_dummy}" npx prisma generate
    PRISMA_EXIT=$?
    set -e
    if [ $PRISMA_EXIT -ne 0 ]; then
      echo -e "${YELLOW}⚠ Falha no Prisma local (provável erro de cross-platform). Tentando npx -y prisma@latest...${NC}"
      DATABASE_URL="${DATABASE_URL:-postgresql://ci:ci@localhost:5432/ci_dummy}" npx -y prisma@latest generate
    fi
  fi

  if node -e "process.exit(require('./package.json').scripts?.build ? 0 : 1)" 2>/dev/null; then
    BUILD_RAN=true
    echo -e "\n${CYAN}🏗 Running build...${NC}"
    set +e
    DATABASE_URL="${DATABASE_URL:-postgresql://ci:ci@localhost:5432/ci_dummy}" \
    NEXT_TELEMETRY_DISABLED=1 CI=true npm run build
    BUILD_EXIT=$?
    set -e
    if [ $BUILD_EXIT -ne 0 ]; then echo -e "  ${RED}❌ Build falhou${NC}"; OVERALL_EXIT=1
    else echo -e "  ${GREEN}✅ Build: Sucesso${NC}"; fi
  elif [ "${IS_SWC:-false}" = "true" ]; then
    BUILD_RAN=true
    echo -e "\n${CYAN}⚡ Running SWC build...${NC}"

    SWC_SCRIPT=""
    if SWC_SCRIPT=$(node -e "
      const scripts = require('./package.json').scripts || {};
      for (const name of ['build:swc', 'swc']) {
        if (scripts[name]) {
          console.log(name);
          process.exit(0);
        }
      }
      process.exit(1);
    " 2>/dev/null); then
      set +e
      npm run "$SWC_SCRIPT"
      SWC_EXIT=$?
      set -e
      if [ $SWC_EXIT -ne 0 ]; then echo -e "  ${RED}❌ SWC script '$SWC_SCRIPT' falhou${NC}"; OVERALL_EXIT=1
      else echo -e "  ${GREEN}✅ SWC script '$SWC_SCRIPT': Sucesso${NC}"; fi
    elif [ -d src ]; then
      SWC_BIN=""
      if [ -x "./node_modules/.bin/swc" ]; then
        SWC_BIN="./node_modules/.bin/swc"
      elif command -v swc >/dev/null 2>&1; then
        SWC_BIN="swc"
      fi

      if [ -z "$SWC_BIN" ]; then
        echo -e "  ${YELLOW}⚠ SWC detectado, mas @swc/cli não está disponível. Pulando build SWC implícito.${NC}"
      else
        set +e
        "$SWC_BIN" src -d dist
        SWC_EXIT=$?
        set -e
        if [ $SWC_EXIT -ne 0 ]; then echo -e "  ${RED}❌ SWC build falhou${NC}"; OVERALL_EXIT=1
        else echo -e "  ${GREEN}✅ SWC Build: Sucesso${NC}"; fi
      fi
    else
      echo -e "  ${YELLOW}⚠ SWC detectado, mas não há script build/build:swc/swc nem diretório src. Pulando build SWC implícito.${NC}"
    fi
  fi

  if [ "$IS_TYPESCRIPT" = "true" ]; then
    BUILD_RAN=true
    echo -e "\n${CYAN}🔎 TypeScript type check...${NC}"
    set +e
    DATABASE_URL="${DATABASE_URL:-postgresql://ci:ci@localhost:5432/ci_dummy}" npx tsc --noEmit
    TSC_EXIT=$?
    set -e
    if [ $TSC_EXIT -ne 0 ]; then echo -e "  ${RED}❌ Type check falhou${NC}"; OVERALL_EXIT=1
    else echo -e "  ${GREEN}✅ TypeScript: OK${NC}"; fi
  fi
fi

if [ "$IS_PYTHON" = "true" ]; then
  BUILD_RAN=true
  echo -e "\n${CYAN}🐍 Instalando deps Python...${NC}"
  if [ -f requirements.txt ]; then pip install --break-system-packages -q -r requirements.txt
  elif [ -f pyproject.toml ]; then pip install --break-system-packages -q .; fi
  echo -e "  ${GREEN}✅ Python: OK${NC}"
fi

[ "$BUILD_RAN" = "false" ] && echo -e "${DIM}ℹ️  Nenhum build detectado.${NC}"
exit $OVERALL_EXIT
