#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Installer                                        ║
# ║  Instalação segura: Baixe o script, revise, e execute.       ║
# ║  bash <(curl -fsSL https://raw.githubusercontent.com/        ║
# ║    Area-tech-alpha/DevSecOps/main/cli/install.sh)            ║
# ╚══════════════════════════════════════════════════════════════╝

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo -e "${MAGENTA}${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║     🛡️  Alpha CI — Installer                  ║"
echo "  ║     Area Tech Alpha · DevSecOps               ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Check Docker ──
if ! command -v docker &>/dev/null; then
  echo -e "${RED}❌ Docker não encontrado.${NC}"
  echo -e "   Instale em: https://docs.docker.com/get-docker/"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Docker disponível"

# ── Check Node (para o wrapper npm) ──
if ! command -v node &>/dev/null; then
  echo -e "${RED}❌ Node.js não encontrado.${NC}"
  echo -e "   Instale Node.js 18+: https://nodejs.org/"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Node.js $(node -v)"

# ── Pull Docker Image ──
echo ""
echo -e "${CYAN}📦 Puxando imagem Docker do GHCR...${NC}"
IMAGE="ghcr.io/area-tech-alpha/alpha-ci:latest"

if docker pull "$IMAGE" 2>/dev/null; then
  echo -e "  ${GREEN}✓${NC} Imagem baixada: $IMAGE"

  # Verify the image has the expected entrypoint
  ENTRYPOINT=$(docker inspect --format='{{json .Config.Entrypoint}}' "$IMAGE" 2>/dev/null || echo "")
  if echo "$ENTRYPOINT" | grep -q "entrypoint.sh"; then
    echo -e "  ${GREEN}✓${NC} Entrypoint verificado"
  else
    echo -e "  ${DIM}⚠ Não foi possível verificar entrypoint da imagem${NC}"
  fi
else
  echo -e "  ${DIM}GHCR indisponível. Tentando build local...${NC}"

  TMPDIR=$(mktemp -d)
  # SECURITY: Ensure cleanup on exit
  trap 'rm -rf "$TMPDIR"' EXIT

  echo -e "${CYAN}📥 Clonando DevSecOps...${NC}"
  git clone --depth 1 https://github.com/Area-tech-alpha/DevSecOps.git "$TMPDIR/DevSecOps" 2>/dev/null

  # SECURITY: Verify expected files exist before building
  if [ ! -f "$TMPDIR/DevSecOps/cli/Dockerfile" ]; then
    echo -e "${RED}❌ Dockerfile não encontrado no repositório clonado.${NC}"
    exit 1
  fi

  echo -e "${CYAN}🏗 Construindo imagem...${NC}"
  docker build -t alpha-ci:latest -f "$TMPDIR/DevSecOps/cli/Dockerfile" "$TMPDIR/DevSecOps"
  echo -e "  ${GREEN}✓${NC} Imagem construída: alpha-ci:latest"
fi

# ── Setup .npmrc para GitHub Packages ──
echo ""
echo -e "${CYAN}🔑 Configurando acesso ao GitHub Packages...${NC}"

NPMRC_FILE="$HOME/.npmrc"
GH_TOKEN="${GITHUB_TOKEN:-${NODE_AUTH_TOKEN:-}}"

# Se não tem token no env, tenta ler do .npmrc existente
if [ -z "$GH_TOKEN" ] && [ -f "$NPMRC_FILE" ]; then
  GH_TOKEN=$(grep -oP '//npm.pkg.github.com/:_authToken=\K.*' "$NPMRC_FILE" 2>/dev/null || echo "")
fi

if [ -z "$GH_TOKEN" ]; then
  echo -e "  ${RED}⚠️  GITHUB_TOKEN não encontrado.${NC}"
  echo -e "  ${DIM}GitHub Packages requer autenticação para instalar packages.${NC}"
  echo -e ""
  echo -e "  ${BOLD}Opção 1: Crie um PAT (Personal Access Token)${NC}"
  echo -e "  ${DIM}→ https://github.com/settings/tokens/new${NC}"
  echo -e "  ${DIM}  Scopes necessários: read:packages${NC}"
  echo -e ""
  echo -e "  ${BOLD}Opção 2: Use o GitHub CLI${NC}"
  echo -e "  ${CYAN}gh auth login${NC}"
  echo -e "  ${CYAN}export GITHUB_TOKEN=\$(gh auth token)${NC}"
  echo -e ""
  echo -e "  ${BOLD}Depois rode novamente:${NC}"
  echo -e "  ${CYAN}GITHUB_TOKEN=ghp_xxx bash install.sh${NC}"
  exit 1
fi

# Configura o .npmrc (preserva entradas existentes de outros registries)
if ! grep -q '@area-tech-alpha:registry=https://npm.pkg.github.com' "$NPMRC_FILE" 2>/dev/null; then
  echo '@area-tech-alpha:registry=https://npm.pkg.github.com' >> "$NPMRC_FILE"
fi
if ! grep -q '//npm.pkg.github.com/:_authToken=' "$NPMRC_FILE" 2>/dev/null; then
  echo "//npm.pkg.github.com/:_authToken=$GH_TOKEN" >> "$NPMRC_FILE"
else
  # Atualiza token existente
  sed -i "s|//npm.pkg.github.com/:_authToken=.*|//npm.pkg.github.com/:_authToken=$GH_TOKEN|" "$NPMRC_FILE"
fi

echo -e "  ${GREEN}✓${NC} .npmrc configurado para @area-tech-alpha"

# ── Install NPM package ──
echo ""
echo -e "${CYAN}📦 Instalando CLI via npm...${NC}"

if npm install -g @area-tech-alpha/alpha-ci 2>/dev/null; then
  echo -e "  ${GREEN}✓${NC} CLI instalada globalmente"
else
  echo -e "  ${DIM}Instalação global falhou. Tente com npx:${NC}"
  echo -e "  ${CYAN}npx @area-tech-alpha/alpha-ci <command>${NC}"
fi

# ── Done ──
echo ""
echo -e "${GREEN}${BOLD}🎉 Alpha CI instalado com sucesso!${NC}"
echo ""
echo -e "${BOLD}Quick Start:${NC}"
echo -e "  ${CYAN}cd seu-projeto${NC}"
echo -e "  ${CYAN}alpha-ci security${NC}    # Scan de segurança"
echo -e "  ${CYAN}alpha-ci lint${NC}        # Linting"
echo -e "  ${CYAN}alpha-ci all${NC}         # Pipeline completo"
echo ""
echo -e "${BOLD}⚠️  Segurança:${NC}"
echo -e "  ${DIM}Tokens devem ser configurados via variáveis de ambiente:${NC}"
echo -e "  ${CYAN}export GITHUB_TOKEN=ghp_xxx${NC}"
echo -e "  ${CYAN}export SEMGREP_APP_TOKEN=xxx${NC}"
echo ""
echo -e "${DIM}Docs: https://github.com/Area-tech-alpha/DevSecOps/tree/main/cli${NC}"
