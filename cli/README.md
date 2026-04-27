# 🛡️ Alpha CI — DevSecOps Pipeline Runner

> Rode o pipeline completo do GitHub Actions **localmente** em qualquer repositório da organização, dentro de um container Docker que replica o ambiente de CI.

---

## ⚡ Quick Start

### Pré-requisito: Configurar acesso ao GitHub Packages (uma única vez)

> GitHub Packages **exige autenticação** mesmo para leitura. Execute o setup abaixo **uma vez** na sua máquina:

**Linux / Mac:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Area-tech-alpha/DevSecOps/main/cli/setup-auth.sh)
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/Area-tech-alpha/DevSecOps/main/cli/setup-auth.ps1 | iex
```

> O script detecta automaticamente o token do GitHub CLI (`gh auth token`), variáveis de ambiente, ou pede interativamente.

---

### Opção 1: Instalação Global (Recomendado)

Evita o erro `403 Forbidden` do `npx` quando o projeto possui um `.npmrc` local.

```bash
npm install -g @area-tech-alpha/alpha-ci

# Scan de segurança no repo atual:
alpha-ci security

# Pipeline completo:
alpha-ci all

# Em outro repositório:
alpha-ci all --path ../meu-projeto
```

### Opção 2: NPX (Requer token exportado)

Se usar `npx` dentro de um repositório que tenha `.npmrc` com `_authToken=${NODE_AUTH_TOKEN}`, você obrigatoriamente precisa ter a variável exportada no terminal, senão o `npx` retornará 403 antes mesmo de executar.

```bash
export NODE_AUTH_TOKEN=$(gh auth token)
npx @area-tech-alpha/alpha-ci all
```

### Opção 3: One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/Area-tech-alpha/DevSecOps/main/cli/install.sh | bash
```

### Opção 4: Docker direto

```bash
docker pull ghcr.io/area-tech-alpha/alpha-ci:latest
docker run --rm -v $(pwd):/workspace ghcr.io/area-tech-alpha/alpha-ci security
```

### Opção 5: Docker Compose

```bash
cd cli/
TARGET_REPO=/path/to/repo docker compose run security
```

### Opção 6: Sem Docker (--no-docker)

```bash
# Requer as tools instaladas localmente (gitleaks, semgrep, eslint, etc.)
alpha-ci security --no-docker
alpha-ci lint --no-docker --fix
```

---

## 📋 Comandos

| Comando | Descrição | Equivalente no CI |
|---------|-----------|-------------------|
| `all` | Pipeline completo | `alpha-ci.yml` |
| `security` | Gitleaks + OSV + Semgrep | `alpha-security.yaml` |
| `lint` | ESLint / Ruff / golangci-lint | `alpha-lint.yml` |
| `test` | Jest/Vitest/pytest/go test | `alpha-test.yml` |
| `build` | npm build + tsc | `alpha-build.yml` |
| `e2e` | Playwright / Cypress | `alpha-e2e.yml` |
| `shell` | Shell interativo no container | — |
| `detect` | Mostra tipo do projeto | — |

---

## 🔧 Opções

```
-p, --path <dir>              Repositório alvo (default: diretório atual)
-v, --verbose                 Output detalhado
--no-docker                   Roda sem Docker (requer tools instaladas)
--fix                         Auto-fix problemas de lint (ESLint + Ruff + golangci-lint)
--format <json|sarif|text>    Formato do relatório (default: text)
--output <file>               Salva relatório em arquivo
--rebuild                     Força rebuild da imagem Docker
--version                     Mostra a versão
```

> ⚠️ Tokens (`GITHUB_TOKEN`, `SEMGREP_APP_TOKEN`) devem ser passados **exclusivamente via variáveis de ambiente** por segurança. Flags `--semgrep-token` e `--github-token` foram removidos.

---

## 🔐 Autenticação

Para repositórios com packages privados do GitHub Package Registry:

```bash
export GITHUB_TOKEN="ghp_xxxxx"
alpha-ci all
```

Para Semgrep com regras customizadas:

```bash
export SEMGREP_APP_TOKEN="xxxxx"
alpha-ci security
```

---

## 🔧 Auto-Fix

Corrige automaticamente problemas de lint sem sair do terminal:

```bash
# Fix via Docker
alpha-ci lint --fix

# Fix sem Docker
alpha-ci lint --fix --no-docker

# Via Docker Compose
AUTO_FIX=true TARGET_REPO=/path/to/repo docker compose run lint
# Ou use o service dedicado:
TARGET_REPO=/path/to/repo docker compose run lint-fix
```

Ferramentas que suportam auto-fix:
- **ESLint**: `--fix` (formatting, import order, etc.)
- **Ruff**: `--fix` (Python formatting, imports)
- **golangci-lint**: `--fix` (Go formatting)

---

## 📊 Relatórios

Gere relatórios estruturados para integração com CI/CD:

```bash
# JSON report
alpha-ci security --format json --output security-report.json

# SARIF (GitHub Security tab)
alpha-ci security --format sarif --output results.sarif

# Pipeline completo com report
alpha-ci all --format json --output pipeline-report.json
```

O relatório JSON consolidado inclui:
- Resultados do Gitleaks (secrets)
- Resultados do OSV-Scanner (vulnerabilidades)
- Resultados do Semgrep (SAST)
- Status de cada stage do pipeline
- Timestamp e duração

---

## 📦 Monorepo Support

A CLI detecta automaticamente monorepos e roda lint/test em todos os workspaces:

```bash
# Detecta e lista workspaces
alpha-ci detect

# Roda lint em todos os packages do monorepo
alpha-ci lint
```

Formatos suportados:
- `pnpm-workspace.yaml`
- `package.json` → `workspaces`
- `lerna.json`
- `nx.json`
- `turbo.json`

---

## 🏗 Arquitetura

```
┌──────────────────────────────────────────┐
│  alpha-ci (npm package / CLI wrapper)    │
│  Orquestra o Docker container            │
│  --no-docker → roda direto no host       │
└───────────────┬──────────────────────────┘
                │ docker run -v repo:/workspace
┌───────────────▼──────────────────────────┐
│  Docker Container (ubuntu:24.04)         │
│  ┌─────────────────────────────────────┐ │
│  │ Tools: Gitleaks, OSV, Semgrep,      │ │
│  │ Node 20, Python 3, Go, ESLint 9,   │ │
│  │ Ruff, golangci-lint, pnpm          │ │
│  └─────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐ │
│  │ Configs embutidos:                  │ │
│  │ - security/gitleaks.toml            │ │
│  │ - security/osv-scanner.toml         │ │
│  │ - lint/eslint.config.mjs            │ │
│  └─────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐ │
│  │ Cache volumes (persistent):         │ │
│  │ - npm-cache, pip-cache, pnpm-cache  │ │
│  └─────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐ │
│  │ Runners: entrypoint.sh → run-*.sh   │ │
│  └─────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

---

## 🔗 Git Hook (opcional)

Para rodar automaticamente antes de cada push:

```bash
# .git/hooks/pre-push
#!/bin/sh
alpha-ci security lint
```

Instalar automaticamente o hook no seu repositório (ex.: na raiz do seu projeto):

```bash
# A partir do repositório DevSecOps:
bash cli/hooks/install-hook.sh /path/to/your/repo

# Ou, para instalar no repositório atual (execute dentro do projeto):
bash /path/to/DevSecOps/cli/hooks/install-hook.sh
```

Observações:
- O hook tenta usar `./node_modules/.bin/alpha-ci` ou `alpha-ci` global se disponível.
- Se não encontrar, ele executa `npm install --no-save @area-tech-alpha/alpha-ci` automaticamente na primeira execução para facilitar a configuração.
- Se o pipeline falhar, o push é abortado.

---

## 🐛 Troubleshooting

| Problema | Solução |
|----------|---------|
| `E401 Unauthorized` (npx) | Rode o setup: `bash <(curl -fsSL .../setup-auth.sh)` |
| `Docker not found` | Instale Docker ou use `--no-docker` |
| `Permission denied` | Rode `chmod +x` no script ou use `sudo` |
| `Image pull failed` | Faça login: `docker login ghcr.io -u USERNAME` |
| `npm packages 403` | Configure `GITHUB_TOKEN` com scope `read:packages` |
| `Semgrep timeout` | Semgrep pode demorar na primeira execução (baixa regras) |
| `golangci-lint not found` | Instale: https://golangci-lint.run/usage/install/ |
| `Tool not found (--no-docker)` | Instale as tools manualmente ou use Docker |

---

## 📦 Distribuição

| Canal | Comando |
|-------|---------|
| **NPM (GPR)** | `npx @area-tech-alpha/alpha-ci` |
| **Docker (GHCR)** | `docker pull ghcr.io/area-tech-alpha/alpha-ci:latest` |
| **Installer** | `curl -fsSL .../install.sh \| bash` |

A imagem Docker e o pacote npm são publicados automaticamente via GitHub Actions quando há alterações em `cli/`, `security/` ou `lint/`. A versão é incrementada automaticamente (patch bump) a cada push.

---

## 🗂 Estrutura de Arquivos

```
cli/
├── bin/
│   └── alpha-ci.mjs          # CLI wrapper (Node.js → Docker)
├── scripts/
│   ├── entrypoint.sh          # Dispatcher principal
│   ├── detect.sh              # Detecção de projeto + monorepo
│   ├── run-local.sh           # Runner --no-docker
│   ├── run-security.sh        # Gitleaks + OSV + Semgrep
│   ├── run-lint.sh            # ESLint + Ruff + golangci-lint
│   ├── run-test.sh            # Jest/Vitest/pytest/go test
│   ├── run-build.sh           # npm build + tsc
│   └── run-e2e.sh             # Playwright / Cypress
├── Dockerfile                 # Multi-stage (builder + runtime)
├── docker-compose.yml         # Services com cache volumes
├── install.sh                 # Installer completo (Docker + npm)
├── setup-auth.sh              # Setup .npmrc (Linux/Mac)
├── setup-auth.ps1             # Setup .npmrc (Windows/PowerShell)
├── package.json               # NPM package config
└── README.md                  # Esta documentação
```
