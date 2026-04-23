#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Installer                                        ║
# ║  curl -fsSL https://raw.githubusercontent.com/               ║
# ║    Area-tech-alpha/DevSecOps/main/cli/install.sh | bash      ║
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
else
  echo -e "  ${DIM}GHCR indisponível. Tentando build local...${NC}"

  TMPDIR=$(mktemp -d)
  echo -e "${CYAN}📥 Clonando DevSecOps...${NC}"
  git clone --depth 1 https://github.com/Area-tech-alpha/DevSecOps.git "$TMPDIR/DevSecOps" 2>/dev/null

  echo -e "${CYAN}🏗 Construindo imagem...${NC}"
  docker build -t alpha-ci:latest -f "$TMPDIR/DevSecOps/cli/Dockerfile" "$TMPDIR/DevSecOps"
  rm -rf "$TMPDIR"
  echo -e "  ${GREEN}✓${NC} Imagem construída: alpha-ci:latest"
fi

# ── Install NPM package ──
echo ""
echo -e "${CYAN}📦 Instalando CLI via npm...${NC}"

if npm install -g @area-tech-alpha/alpha-ci 2>/dev/null; then
  echo -e "  ${GREEN}✓${NC} CLI instalada globalmente"
else
  echo -e "  ${DIM}GPR indisponível. Instalando via npx...${NC}"
  echo -e "  ${DIM}Use: npx @area-tech-alpha/alpha-ci <command>${NC}"
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
echo -e "${DIM}Docs: https://github.com/Area-tech-alpha/DevSecOps/tree/main/cli${NC}"
