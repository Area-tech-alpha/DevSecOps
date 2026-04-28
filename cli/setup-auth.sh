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

# ── Validação Ativa do Token ──
echo -e "  ${CYAN}🔍 Validando token contra a API do GitHub...${NC}"

# Silenciosamente tenta pegar info do usuário e escopos
API_RESPONSE=$(curl -s -I -H "Authorization: token $GH_TOKEN" https://api.github.com/user)
HTTP_STATUS=$(echo "$API_RESPONSE" | grep "HTTP/" | awk '{print $2}' | head -n 1)

if [ "$HTTP_STATUS" != "200" ]; then
  echo -e "  ${RED}❌ Token inválido ou expirado (HTTP $HTTP_STATUS).${NC}"
  echo -e "     Verifique em: https://github.com/settings/tokens"
  exit 1
fi

# Extrair escopos do header X-OAuth-Scopes
SCOPES=$(echo "$API_RESPONSE" | grep -i "x-oauth-scopes:" | cut -d':' -f2 | tr -d ' \r\n')
echo -e "  ${GREEN}✓${NC} Token válido. Scopes: ${DIM}${SCOPES:-none (fine-grained?)}${NC}"

# Se tiver admin, repo ou write:packages, ele já tem permissão de leitura
if [[ ! "$SCOPES" =~ "read:packages" ]] && [[ ! "$SCOPES" =~ "write:packages" ]] && [[ ! "$SCOPES" =~ "repo" ]] && [[ ! "$SCOPES" =~ "admin" ]]; then
  # Se o token for fine-grained (github_pat_), o header de scopes pode vir vazio, então não bloqueamos
  if [[ ! "$GH_TOKEN" =~ ^github_pat_ ]]; then
    echo -e "  ${YELLOW}⚠️  Aviso: O token pode não ter o escopo 'read:packages'.${NC}"
    echo -e "     Se falhar com 403, revise os escopos em: https://github.com/settings/tokens"
  fi
fi

# Extrair username automaticamente se ainda não tivermos
if [ -z "$GH_USERNAME" ]; then
  GH_USERNAME=$(curl -s -H "Authorization: token $GH_TOKEN" https://api.github.com/user | grep -oP '"login":\s*"\K[^"]+')
  echo -e "  ${GREEN}✓${NC} Usuário detectado: ${BOLD}$GH_USERNAME${NC}"
fi

# Verificar se pertence à Area-tech-alpha e se precisa de SSO
ORG_CHECK=$(curl -s -I -H "Authorization: token $GH_TOKEN" https://api.github.com/orgs/Area-tech-alpha)
ORG_STATUS=$(echo "$ORG_CHECK" | grep "HTTP/" | awk '{print $2}' | head -n 1)

if [ "$ORG_STATUS" = "403" ] || [ "$ORG_STATUS" = "404" ]; then
  echo -e ""
  echo -e "  ${YELLOW}⚠️  Possível problema de SSO ou Acesso à Org.${NC}"
  echo -e "     Você deve autorizar este token para a organização 'Area-tech-alpha':"
  echo -e "     ${CYAN}→ https://github.com/settings/tokens${NC}"
  echo -e "     ${DIM}→ Clique no seu token → 'Configure SSO' ao lado de 'Area-tech-alpha'${NC}"
  echo -e "     ${DIM}→ Clique em 'Authorize'${NC}"
  echo ""
  read -p "  Pressione ENTER após autorizar para continuar ou CTRL+C para sair..."
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

# Higieniza o .npmrc (remove entradas conflitantes ou malformadas)
if [ -f "$NPMRC_GLOBAL" ]; then
  # Remove linhas antigas (usa || true para não quebrar o script se o sed falhar)
  sed -i '/area-tech-alpha:registry/d' "$NPMRC_GLOBAL" || true
  sed -i '/npm.pkg.github.com\/:_authToken/d' "$NPMRC_GLOBAL" || true
  sed -i '/npm.pkg.github.com\/always-auth/d' "$NPMRC_GLOBAL" || true
fi

# Configura via npm config (grava no .npmrc global automaticamente)
echo -e "  ${CYAN}⚙️  Configurando registry e token...${NC}"

# Tenta configurar e mostra o erro real se falhar
npm config set @area-tech-alpha:registry https://npm.pkg.github.com
npm config set "//npm.pkg.github.com/:_authToken" "$GH_TOKEN"

# Injeta always-auth diretamente no arquivo (evita erro no npm v9+)
echo "always-auth=true" >> "$NPMRC_GLOBAL"

echo -e "  ${GREEN}✓${NC} Registry @area-tech-alpha configurado"
echo -e "  ${GREEN}✓${NC} Auth token injetado e higienizado"
echo -e "  ${GREEN}✓${NC} always-auth = true (enforced)"

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

# ══════════════════════════════════════════════════
#  STEP 4: Instalação Global
# ══════════════════════════════════════════════════

echo -e "  ${CYAN}── Step 4/4: Instalando Alpha CI globalmente ──${NC}"
echo ""

if npm install -g @area-tech-alpha/alpha-ci; then
  echo -e "  ${GREEN}✓${NC} Alpha CI instalado com sucesso!"
else
  echo -e "  ${YELLOW}⚠${NC} Falha na instalação global. Tente rodar manually:${NC}"
  echo -e "    ${CYAN}sudo npm install -g @area-tech-alpha/alpha-ci${NC}"
fi

echo ""

# ══════════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════════

echo -e "  ${GREEN}══════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}✅ Setup concluído com sucesso!${NC}"
echo -e "  ${GREEN}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Agora você pode usar em qualquer projeto:${NC}"
echo -e "    ${CYAN}alpha-ci all${NC}"
echo ""
