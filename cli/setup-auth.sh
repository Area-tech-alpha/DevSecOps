#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Auth Setup (One-liner)                           ║
# ║  Configura .npmrc para GitHub Packages automaticamente       ║
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
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}🔑 Alpha CI — Configurando acesso ao GitHub Packages${NC}"
echo ""

NPMRC_FILE="$HOME/.npmrc"
GH_TOKEN=""

# ── Strategy 1: gh CLI (zero-friction) ──
if command -v gh &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} GitHub CLI detectado"

  # Verifica se está autenticado
  if gh auth status &>/dev/null 2>&1; then
    GH_TOKEN=$(gh auth token 2>/dev/null || echo "")
    if [ -n "$GH_TOKEN" ]; then
      echo -e "  ${GREEN}✓${NC} Token extraído via ${BOLD}gh auth token${NC}"
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} GitHub CLI não autenticado"
    echo -e "  ${DIM}Execute: gh auth login${NC}"
  fi
fi

# ── Strategy 2: Environment variable ──
if [ -z "$GH_TOKEN" ]; then
  GH_TOKEN="${GITHUB_TOKEN:-${NODE_AUTH_TOKEN:-${GH_TOKEN:-}}}"
  if [ -n "$GH_TOKEN" ]; then
    echo -e "  ${GREEN}✓${NC} Token encontrado via variável de ambiente"
  fi
fi

# ── Strategy 3: Existing .npmrc ──
if [ -z "$GH_TOKEN" ] && [ -f "$NPMRC_FILE" ]; then
  GH_TOKEN=$(grep -oP '//npm.pkg.github.com/:_authToken=\K.*' "$NPMRC_FILE" 2>/dev/null || echo "")
  if [ -n "$GH_TOKEN" ]; then
    echo -e "  ${GREEN}✓${NC} Token encontrado no .npmrc existente"
  fi
fi

# ── Strategy 4: Interactive prompt ──
if [ -z "$GH_TOKEN" ]; then
  echo -e "  ${YELLOW}⚠ Nenhum token detectado automaticamente.${NC}"
  echo ""
  echo -e "  ${BOLD}Crie um Personal Access Token (classic):${NC}"
  echo -e "  ${CYAN}→ https://github.com/settings/tokens/new${NC}"
  echo -e "  ${DIM}  ☑ read:packages (único scope necessário)${NC}"
  echo ""
  read -rp "  Cole o token aqui (ghp_...): " GH_TOKEN

  if [ -z "$GH_TOKEN" ]; then
    echo -e "\n  ${RED}❌ Nenhum token fornecido. Abortando.${NC}"
    exit 1
  fi
fi

# ── Validate token format ──
if [[ ! "$GH_TOKEN" =~ ^(ghp_|gho_|github_pat_) ]]; then
  echo -e "  ${YELLOW}⚠ Token não parece ser um GitHub PAT (esperado ghp_/gho_/github_pat_)${NC}"
  echo -e "  ${DIM}Continuando mesmo assim...${NC}"
fi

# ── Configure .npmrc ──
echo -e "  ${CYAN}Atualizando configurações do npm...${NC}"
npm config set @area-tech-alpha:registry https://npm.pkg.github.com
npm config set //npm.pkg.github.com/:_authToken "$GH_TOKEN"

echo ""
echo -e "  ${GREEN}✅ .npmrc configurado com sucesso!${NC}"
echo ""
echo -e "  ${BOLD}Agora você pode usar:${NC}"
echo -e "  ${CYAN}npx @area-tech-alpha/alpha-ci all${NC}"
echo -e "  ${CYAN}npx @area-tech-alpha/alpha-ci security${NC}"
echo -e "  ${CYAN}npx @area-tech-alpha/alpha-ci lint${NC}"
echo ""
echo -e "  ${DIM}Ou instalar globalmente:${NC}"
echo -e "  ${CYAN}npm install -g @area-tech-alpha/alpha-ci${NC}"
echo ""
