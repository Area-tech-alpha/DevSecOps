#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Full Setup (Linux / macOS)                       ║
# ║  Configura npm (.npmrc) + Docker (GHCR) automaticamente      ║
# ║                                                              ║
# ║  Uso:                                                        ║
# ║  bash <(curl -fsSL https://raw.githubusercontent.com/        ║
# ║    Area-tech-alpha/DevSecOps/main/cli/setup-auth.sh)         ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo -e ""
echo -e "${MAGENTA}${BOLD}  ╔═══════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}${BOLD}  ║     🛡️  Alpha CI — Setup                      ║${NC}"
echo -e "${MAGENTA}${BOLD}  ║     Area Tech Alpha · DevSecOps               ║${NC}"
echo -e "${MAGENTA}${BOLD}  ╚═══════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════
#  STEP 1: Coletar credenciais
# ══════════════════════════════════════════════════

echo -e "  ${CYAN}── Step 1/3: Credenciais ──${NC}"
echo ""

GH_USERNAME=""
GH_TOKEN=""

# ── Detectar .npmrc GLOBAL primeiro (evita conflitos com .npmrc local) ──
NPMRC_GLOBAL=$(npm config get userconfig 2>/dev/null || echo "$HOME/.npmrc")
if [ -z "$NPMRC_GLOBAL" ] || [ "$NPMRC_GLOBAL" = "undefined" ]; then
  NPMRC_GLOBAL="$HOME/.npmrc"
fi

# Garante que o npm sempre use o .npmrc global
export NPM_CONFIG_USERCONFIG="$NPMRC_GLOBAL"

echo -e "  ${DIM}📂 .npmrc global: $NPMRC_GLOBAL${NC}"

# ── Strategy 1: gh CLI (zero-friction) ──
if command -v gh &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} GitHub CLI detectado"

  if gh auth status &>/dev/null 2>&1; then
    GH_TOKEN=$(gh auth token 2>/dev/null || echo "")
    GH_USERNAME=$(gh api user --jq .login 2>/dev/null || echo "")

    if [ -n "$GH_TOKEN" ] && [ -n "$GH_USERNAME" ]; then
      echo -e "  ${GREEN}✓${NC} Token e username extraídos via GitHub CLI"
      echo -e "    ${DIM}Usuário: $GH_USERNAME${NC}"
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} GitHub CLI não autenticado"
    echo -e "  ${DIM}Execute: gh auth login${NC}"
  fi
fi

# ── Strategy 2: Environment variables ──
if [ -z "$GH_TOKEN" ]; then
  GH_TOKEN="${GITHUB_TOKEN:-${NODE_AUTH_TOKEN:-}}"
  if [ -n "$GH_TOKEN" ]; then
    echo -e "  ${GREEN}✓${NC} Token encontrado via variável de ambiente"
  fi
fi

# ── Strategy 3: .npmrc global existente ──
if [ -z "$GH_TOKEN" ] && [ -f "$NPMRC_GLOBAL" ]; then
  GH_TOKEN=$(grep -oP '//npm.pkg.github.com/:_authToken=\K.*' "$NPMRC_GLOBAL" 2>/dev/null || echo "")
  if [ -n "$GH_TOKEN" ]; then
    echo -e "  ${GREEN}✓${NC} Token encontrado no .npmrc global"
  fi
fi

# ── Strategy 4: Interactive prompt ──
if [ -z "$GH_TOKEN" ]; then
  echo -e "  ${YELLOW}⚠ Nenhum token detectado automaticamente.${NC}"
  echo ""
  echo -e "  ${BOLD}Crie um Personal Access Token (classic):${NC}"
  echo -e "  ${CYAN}→ https://github.com/settings/tokens/new${NC}"
  echo -e "  ${DIM}  ☑ read:packages   (obrigatório)${NC}"
  echo -e "  ${DIM}  ☑ write:packages  (se for publicar)${NC}"
  echo ""
  read -rp "  Cole o token aqui (ghp_...): " GH_TOKEN

  if [ -z "$GH_TOKEN" ]; then
    echo -e "\n  ${RED}❌ Nenhum token fornecido. Abortando.${NC}"
    exit 1
  fi
fi

# ── Sempre pedir username se não foi detectado ──
if [ -z "$GH_USERNAME" ]; then
  echo ""
  read -rp "  Digite seu usuário do GitHub: " GH_USERNAME

  if [ -z "$GH_USERNAME" ]; then
    echo -e "\n  ${RED}❌ Nenhum usuário fornecido. Abortando.${NC}"
    exit 1
  fi
fi

echo ""

# ══════════════════════════════════════════════════
#  STEP 2: Configurar npm (.npmrc global)
# ══════════════════════════════════════════════════

echo -e "  ${CYAN}── Step 2/3: Configurando npm ──${NC}"
echo ""

# Alerta se houver .npmrc local conflitante
NPMRC_LOCAL="$(pwd)/.npmrc"
if [ -f "$NPMRC_LOCAL" ] && [ "$NPMRC_LOCAL" != "$NPMRC_GLOBAL" ]; then
  if grep -q 'area-tech-alpha' "$NPMRC_LOCAL" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠${NC} .npmrc local detectado com config @area-tech-alpha"
    echo -e "    ${DIM}O .npmrc GLOBAL tem prioridade. O local pode causar conflitos.${NC}"
  fi
fi

# Configura via npm config (grava no .npmrc global automaticamente)
npm config set @area-tech-alpha:registry https://npm.pkg.github.com 2>/dev/null
npm config set "//npm.pkg.github.com/:_authToken" "$GH_TOKEN" 2>/dev/null
npm config set always-auth true 2>/dev/null

echo -e "  ${GREEN}✓${NC} Registry @area-tech-alpha → npm.pkg.github.com"
echo -e "  ${GREEN}✓${NC} Auth token configurado no .npmrc global"
echo -e "  ${GREEN}✓${NC} always-auth = true (para evitar 403 intermitentes)"

# Valida acesso
echo ""
echo -e "  ${CYAN}🔍 Validando acesso ao package...${NC}"
set +e
VIEW_RESULT=$(npm view @area-tech-alpha/alpha-ci version 2>&1)
VIEW_EXIT=$?
set -e

if [ $VIEW_EXIT -eq 0 ]; then
  echo -e "  ${GREEN}✓${NC} Acesso validado! Versão disponível: ${BOLD}$VIEW_RESULT${NC}"
else
  echo -e "  ${YELLOW}⚠${NC} Não foi possível validar o acesso. Verifique o token."
  echo -e "    ${DIM}Se o erro for 403 (Forbidden), você DEVE autorizar o token para SSO:${NC}"
  echo -e "    ${CYAN}→ https://github.com/settings/tokens${NC}"
  echo -e "    ${DIM}→ Clique no seu token → 'Configure SSO' (ao lado de 'Area-tech-alpha')${NC}"
  echo -e "    ${DIM}→ Clique em 'Authorize'${NC}"
fi

echo ""

# ══════════════════════════════════════════════════
#  STEP 3: Configurar Docker (GHCR)
# ══════════════════════════════════════════════════

echo -e "  ${CYAN}── Step 3/3: Configurando Docker (GHCR) ──${NC}"
echo ""

if command -v docker &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Docker detectado"

  # Login no GHCR usando o token que já temos
  echo -e "  ${CYAN}🔑 Fazendo login no GitHub Container Registry...${NC}"
  set +e
  echo "$GH_TOKEN" | docker login ghcr.io -u "$GH_USERNAME" --password-stdin 2>/dev/null
  DOCKER_EXIT=$?
  set -e

  if [ $DOCKER_EXIT -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} Docker autenticado no ghcr.io como ${BOLD}$GH_USERNAME${NC}"

    # Tenta puxar a imagem para validar
    echo -e "  ${CYAN}📦 Puxando imagem alpha-ci...${NC}"
    set +e
    docker pull ghcr.io/area-tech-alpha/alpha-ci:latest 2>/dev/null
    PULL_EXIT=$?
    set -e

    if [ $PULL_EXIT -eq 0 ]; then
      echo -e "  ${GREEN}✓${NC} Imagem alpha-ci:latest baixada com sucesso"
    else
      echo -e "  ${YELLOW}⚠${NC} Não foi possível puxar a imagem. Será baixada na primeira execução."
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} Falha no login Docker. Verifique se o token tem scope 'read:packages'."
  fi
else
  echo -e "  ${YELLOW}⚠${NC} Docker não encontrado. Instale em: https://docs.docker.com/get-docker/"
  echo -e "    ${DIM}Você ainda pode usar: alpha-ci lint --no-docker${NC}"
fi

# ══════════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════════

echo ""
echo -e "  ${GREEN}══════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}✅ Setup concluído com sucesso!${NC}"
echo -e "  ${GREEN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Agora você pode usar:${NC}"
echo -e "    ${CYAN}npx @area-tech-alpha/alpha-ci all${NC}        # Pipeline completo"
echo -e "    ${CYAN}npx @area-tech-alpha/alpha-ci security${NC}   # Scan de segurança"
echo -e "    ${CYAN}npx @area-tech-alpha/alpha-ci lint${NC}       # Linting"
echo -e "    ${CYAN}npx @area-tech-alpha/alpha-ci lint --fix${NC} # Auto-fix"
echo ""
echo -e "  ${DIM}Ou instalar globalmente:${NC}"
echo -e "    ${CYAN}npm install -g @area-tech-alpha/alpha-ci${NC}"
echo -e "    ${CYAN}alpha-ci all${NC}"
echo ""
