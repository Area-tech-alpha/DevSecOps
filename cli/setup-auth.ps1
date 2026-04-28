# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Full Setup (Windows/PowerShell)                  ║
# ║  Configura npm (.npmrc) + Docker (GHCR) automaticamente      ║
# ║                                                              ║
# ║  Uso:                                                        ║
# ║  irm https://raw.githubusercontent.com/Area-tech-alpha/      ║
# ║    DevSecOps/main/cli/setup-auth.ps1 | iex                  ║
# ╚══════════════════════════════════════════════════════════════╝

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║     🛡️  Alpha CI — Setup                      ║" -ForegroundColor Magenta
Write-Host "  ║     Area Tech Alpha · DevSecOps               ║" -ForegroundColor Magenta
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# ══════════════════════════════════════════════════
#  STEP 1: Coletar credenciais
# ══════════════════════════════════════════════════

Write-Host "  ── Step 1/3: Credenciais ──" -ForegroundColor Cyan
Write-Host ""

$ghUsername = $null
$ghToken = $null

# ── Detectar .npmrc GLOBAL primeiro (evita conflitos com .npmrc local) ──
$npmrcGlobal = (npm config get userconfig 2>$null)
if (-not $npmrcGlobal) { $npmrcGlobal = Join-Path $env:USERPROFILE ".npmrc" }

# Garante que o npm sempre use o .npmrc global
$env:NPM_CONFIG_USERCONFIG = $npmrcGlobal

Write-Host "  📂 .npmrc global: $npmrcGlobal" -ForegroundColor DarkGray

# ── Strategy 1: gh CLI (zero-friction) ──
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ GitHub CLI detectado" -ForegroundColor Green
    try {
        $null = gh auth status 2>&1
        $ghToken = (gh auth token 2>$null)
        if ($ghToken) { $ghToken = $ghToken.Trim() }

        # Extrai username do gh
        $ghUsername = (gh api user --jq .login 2>$null)
        if ($ghUsername) { $ghUsername = $ghUsername.Trim() }

        if ($ghToken -and $ghUsername) {
            Write-Host "  ✓ Token e username extraídos via GitHub CLI" -ForegroundColor Green
            Write-Host "    Usuário: $ghUsername" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  ⚠ GitHub CLI não autenticado. Execute: gh auth login" -ForegroundColor Yellow
    }
}

# ── Strategy 2: Environment variables ──
if (-not $ghToken) {
    $ghToken = $env:GITHUB_TOKEN
    if (-not $ghToken) { $ghToken = $env:NODE_AUTH_TOKEN }
    if ($ghToken) {
        Write-Host "  ✓ Token encontrado via variável de ambiente" -ForegroundColor Green
    }
}

# ── Strategy 3: .npmrc global existente ──
if (-not $ghToken -and (Test-Path $npmrcGlobal)) {
    $match = Select-String -Path $npmrcGlobal -Pattern '//npm\.pkg\.github\.com/:_authToken=(.+)' -ErrorAction SilentlyContinue
    if ($match) {
        $ghToken = $match.Matches[0].Groups[1].Value.Trim()
        Write-Host "  ✓ Token encontrado no .npmrc global" -ForegroundColor Green
    }
}

# ── Strategy 4: Interactive prompt ──
if (-not $ghToken) {
    Write-Host "  ⚠ Nenhum token detectado automaticamente." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Crie um Personal Access Token (classic):" -ForegroundColor White
    Write-Host "  → https://github.com/settings/tokens/new" -ForegroundColor Cyan
    Write-Host "    ☑ read:packages   (obrigatório)" -ForegroundColor DarkGray
    Write-Host "    ☑ write:packages  (se for publicar)" -ForegroundColor DarkGray
    Write-Host ""
    $ghToken = Read-Host "  Cole o token aqui (ghp_...)"

    if (-not $ghToken) {
        Write-Host "`n  ❌ Nenhum token fornecido. Abortando." -ForegroundColor Red
        exit 1
    }
}

# ── Sempre pedir username se não foi detectado ──
if (-not $ghUsername) {
    Write-Host ""
    $ghUsername = Read-Host "  Digite seu usuário do GitHub"

    if (-not $ghUsername) {
        Write-Host "`n  ❌ Nenhum usuário fornecido. Abortando." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ══════════════════════════════════════════════════
#  STEP 2: Configurar npm (.npmrc global)
# ══════════════════════════════════════════════════

Write-Host "  ── Step 2/3: Configurando npm ──" -ForegroundColor Cyan
Write-Host ""

# Remove .npmrc local do diretório atual se existir (evita conflitos)
$npmrcLocal = Join-Path (Get-Location) ".npmrc"
if ((Test-Path $npmrcLocal) -and ($npmrcLocal -ne $npmrcGlobal)) {
    $localContent = Get-Content $npmrcLocal -Raw -ErrorAction SilentlyContinue
    if ($localContent -match 'area-tech-alpha') {
        Write-Host "  ⚠ .npmrc local detectado com config @area-tech-alpha" -ForegroundColor Yellow
        Write-Host "    O .npmrc GLOBAL tem prioridade. O local pode causar conflitos." -ForegroundColor DarkGray
    }
}

# Configura via npm config (grava no .npmrc global automaticamente)
npm config set @area-tech-alpha:registry https://npm.pkg.github.com 2>$null
npm config set //npm.pkg.github.com/:_authToken $ghToken 2>$null
npm config set always-auth true 2>$null

Write-Host "  ✓ Registry @area-tech-alpha → npm.pkg.github.com" -ForegroundColor Green
Write-Host "  ✓ Auth token configurado no .npmrc global" -ForegroundColor Green
Write-Host "  ✓ always-auth = true (para evitar 403 intermitentes)" -ForegroundColor Green

# Verifica se funcionou
Write-Host ""
Write-Host "  🔍 Validando acesso ao package..." -ForegroundColor Cyan
try {
    $viewResult = npm view @area-tech-alpha/alpha-ci version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Acesso validado! Versão disponível: $viewResult" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Não foi possível validar o acesso. Verifique o token." -ForegroundColor Yellow
        Write-Host "    Se o erro for 403 (Forbidden), você DEVE autorizar o token para SSO:" -ForegroundColor DarkGray
        Write-Host "    → https://github.com/settings/tokens" -ForegroundColor Cyan
        Write-Host "    → Clique no seu token → 'Configure SSO' (ao lado de 'Area-tech-alpha')" -ForegroundColor DarkGray
        Write-Host "    → Clique em 'Authorize'" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ⚠ Validação ignorada (npm não respondeu)" -ForegroundColor Yellow
}

Write-Host ""

# ══════════════════════════════════════════════════
#  STEP 3: Configurar Docker (GHCR)
# ══════════════════════════════════════════════════

Write-Host "  ── Step 3/3: Configurando Docker (GHCR) ──" -ForegroundColor Cyan
Write-Host ""

if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ Docker detectado" -ForegroundColor Green

    # Login no GHCR usando o token que já temos
    Write-Host "  🔑 Fazendo login no GitHub Container Registry..." -ForegroundColor Cyan
    $ghToken | docker login ghcr.io -u $ghUsername --password-stdin 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Docker autenticado no ghcr.io como $ghUsername" -ForegroundColor Green

        # Tenta puxar a imagem para validar
        Write-Host "  📦 Puxando imagem alpha-ci..." -ForegroundColor Cyan
        $pullResult = docker pull ghcr.io/area-tech-alpha/alpha-ci:latest 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Imagem alpha-ci:latest baixada com sucesso" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Não foi possível puxar a imagem. Ela será baixada na primeira execução." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ⚠ Falha no login Docker. Verifique se o token tem scope 'read:packages'." -ForegroundColor Yellow
    }
} else {
    Write-Host "  ⚠ Docker não encontrado. Instale em: https://docs.docker.com/get-docker/" -ForegroundColor Yellow
    Write-Host "    Você ainda pode usar: alpha-ci lint --no-docker" -ForegroundColor DarkGray
}

# ══════════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════════

Write-Host ""
Write-Host "  ══════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ Setup concluído com sucesso!" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Agora você pode usar:" -ForegroundColor White
Write-Host "    npx @area-tech-alpha/alpha-ci all        # Pipeline completo" -ForegroundColor Cyan
Write-Host "    npx @area-tech-alpha/alpha-ci security   # Scan de segurança" -ForegroundColor Cyan
Write-Host "    npx @area-tech-alpha/alpha-ci lint       # Linting" -ForegroundColor Cyan
Write-Host "    npx @area-tech-alpha/alpha-ci lint --fix # Auto-fix" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Ou instalar globalmente:" -ForegroundColor DarkGray
Write-Host "    npm install -g @area-tech-alpha/alpha-ci" -ForegroundColor Cyan
Write-Host "    alpha-ci all" -ForegroundColor Cyan
Write-Host ""
