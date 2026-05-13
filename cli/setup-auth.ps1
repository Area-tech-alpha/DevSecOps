# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Full Setup (Windows/PowerShell)                  ║
# ║  Configura npm (.npmrc) + Docker (GHCR) automaticamente      ║
# ║                                                              ║
# ║  Uso:                                                        ║
# ║  irm https://raw.githubusercontent.com/Area-tech-alpha/      ║
# ║    DevSecOps/main/cli/setup-auth.ps1 | iex                   ║
# ║                                                              ║
# ║  Flags:                                                      ║
# ║    -SkipDocker     Pula configuração do Docker/GHCR          ║
# ║    -SkipInstall    Pula instalação global do alpha-ci        ║
# ╚══════════════════════════════════════════════════════════════╝

param(
    [switch]$SkipDocker,
    [switch]$SkipInstall,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ── Timer ──
$setupStart = Get-Date

# ── Summary tracking ──
$summaryItems = [System.Collections.ArrayList]::new()
function Add-Summary($msg) { [void]$summaryItems.Add($msg) }

if ($Help) {
    Write-Host "Usage: setup-auth.ps1 [-SkipDocker] [-SkipInstall]"
    Write-Host ""
    Write-Host "  -SkipDocker    Pula configuração do Docker/GHCR (Step 3)"
    Write-Host "  -SkipInstall   Pula instalação global do alpha-ci (Step 4)"
    exit 0
}

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║     🛡️  Alpha CI — Setup                      ║" -ForegroundColor Magenta
Write-Host "  ║     Area Tech Alpha · DevSecOps               ║" -ForegroundColor Magenta
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

# ══════════════════════════════════════════════════
#  PRE-FLIGHT: Verificações rápidas
# ══════════════════════════════════════════════════

Write-Host "  ── Pre-flight checks ──" -ForegroundColor DarkGray

# Verificar se npm está instalado
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "  ❌ npm não encontrado." -ForegroundColor Red
    Write-Host "     Instale Node.js 18+: https://nodejs.org/"
    exit 1
}
$npmVersion = (npm -v 2>$null)
Write-Host "  ✓ npm $npmVersion disponível" -ForegroundColor Green

# Verificar Node >= 18
$nodeVersionRaw = (node -v 2>$null)
if ($nodeVersionRaw) {
    $nodeMajor = [int]($nodeVersionRaw -replace '^v','').Split('.')[0]
    if ($nodeMajor -lt 18) {
        Write-Host "  ❌ Node.js v$nodeMajor detectado. Alpha CI requer Node >= 18." -ForegroundColor Red
        Write-Host "     Atualize: https://nodejs.org/"
        exit 1
    }
    Write-Host "  ✓ Node.js $nodeVersionRaw" -ForegroundColor Green
}
Write-Host ""

# ══════════════════════════════════════════════════
#  STEP 1: Coletar credenciais
# ══════════════════════════════════════════════════

Write-Host "  ── Step 1/4: Credenciais ──" -ForegroundColor Cyan
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
        # Limpeza nuclear: remove TUDO que não for alfanumérico ou os separadores permitidos
        $ghToken = $match.Matches[0].Groups[1].Value -replace '[^a-zA-Z0-9_.-]', ''
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
    $ghToken = $ghToken -replace '[^a-zA-Z0-9_.-]', ''
}

# ── Validação Ativa do Token (com retry) ──
Write-Host "  🔍 Validando token contra a API do GitHub..." -ForegroundColor Cyan

$maxRetries = 3
$retryDelay = 2
$httpStatus = $null
$response = $null

for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    try {
        $headers = @{ "Authorization" = "token $ghToken" }
        $response = Invoke-WebRequest -Uri "https://api.github.com/user" -Headers $headers -Method Get -TimeoutSec 10
        $httpStatus = $response.StatusCode
        break
    } catch {
        if ($attempt -lt $maxRetries) {
            Write-Host "  ⏳ Tentativa $attempt/$maxRetries falhou. Retentando em ${retryDelay}s..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $retryDelay
        } else {
            # Check if it's a 401/403 from the API vs network error
            if ($_.Exception.Response) {
                $httpStatus = [int]$_.Exception.Response.StatusCode
            } else {
                Write-Host "  ❌ Não foi possível conectar à API do GitHub após $maxRetries tentativas." -ForegroundColor Red
                Write-Host "     Verifique sua conexão com a internet." -ForegroundColor DarkGray
                exit 1
            }
        }
    }
}

if ($httpStatus -ne 200) {
    Write-Host "  ❌ Token inválido ou expirado (HTTP $httpStatus)." -ForegroundColor Red
    Write-Host "     Verifique em: https://github.com/settings/tokens" -ForegroundColor DarkGray
    exit 1
}

# Extrair escopos
$scopes = $null
if ($response.Headers.ContainsKey("X-OAuth-Scopes")) {
    $scopes = $response.Headers["X-OAuth-Scopes"]
}
$displayScopes = if ($null -eq $scopes -or $scopes -eq "") { "none (fine-grained?)" } else { $scopes }
Write-Host "  ✓ Token válido. Scopes: $displayScopes" -ForegroundColor Green
Add-Summary "Token GitHub validado (scopes: $displayScopes)"

# Se tiver admin, repo ou write:packages, ele já tem permissão de leitura
if (($scopes -notmatch "read:packages") -and ($scopes -notmatch "write:packages") -and ($scopes -notmatch "repo") -and ($scopes -notmatch "admin")) {
    # Se o token for fine-grained (github_pat_), não bloqueamos por falta de header
    if ($ghToken -notmatch "^github_pat_") {
        Write-Host "  ⚠️  Aviso: O token pode não ter o escopo 'read:packages'." -ForegroundColor Yellow
        Write-Host "     Se falhar com 403, revise os escopos em: https://github.com/settings/tokens" -ForegroundColor DarkGray
    }
}

# Extrair username automaticamente se não tivermos
if (-not $ghUsername) {
    $userJson = $response.Content | ConvertFrom-Json
    $ghUsername = $userJson.login
    Write-Host "  ✓ Usuário detectado: $ghUsername" -ForegroundColor Green
}
Add-Summary "Usuário: $ghUsername"

# Verificar acesso à Org e SSO
try {
    $orgResponse = Invoke-WebRequest -Uri "https://api.github.com/orgs/Area-tech-alpha" -Headers $headers -Method Get -TimeoutSec 10
} catch {
    Write-Host "" -ForegroundColor Red
    Write-Host "  ⚠️  Possível problema de SSO ou Acesso à Org." -ForegroundColor Yellow
    Write-Host "     Você deve autorizar este token para a organização 'Area-tech-alpha':" -ForegroundColor White
    Write-Host "     → https://github.com/settings/tokens" -ForegroundColor Cyan
    Write-Host "     Clique no seu token → 'Configure SSO' ao lado de 'Area-tech-alpha' → 'Authorize'" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Pressione ENTER após autorizar para continuar ou CTRL+C para sair..."
}

Write-Host ""

# ══════════════════════════════════════════════════
#  STEP 2: Configurar npm (.npmrc global)
# ══════════════════════════════════════════════════

Write-Host "  ── Step 2/4: Configurando npm ──" -ForegroundColor Cyan
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

# Higieniza o .npmrc (remove entradas conflitantes ou malformadas no Windows)
try {
    if (Test-Path $npmrcGlobal) {
        $content = Get-Content $npmrcGlobal -ErrorAction SilentlyContinue
        if ($content) {
            $newContent = $content | Where-Object {
                $_ -notmatch 'area-tech-alpha:registry' -and
                $_ -notmatch 'npm\.pkg\.github\.com/:_authToken' -and
                $_ -notmatch 'npm\.pkg\.github\.com/always-auth' -and
                $_ -notmatch '^always-auth=true$'
            }
            Set-Content -Path $npmrcGlobal -Value $newContent -ErrorAction SilentlyContinue
        }
    }
} catch {
    # Ignora falhas de limpeza (ex: arquivo travado)
}

# Configura via npm config (grava no .npmrc global automaticamente)
Write-Host "  ⚙️  Configurando registry e token..." -ForegroundColor Cyan
npm config set @area-tech-alpha:registry https://npm.pkg.github.com
npm config set //npm.pkg.github.com/:_authToken $ghToken

# Injeta always-auth apenas se não existir (evita duplicatas em execuções repetidas)
$currentContent = Get-Content $npmrcGlobal -ErrorAction SilentlyContinue
if (-not ($currentContent -match '^always-auth=true$')) {
    Add-Content -Path $npmrcGlobal -Value "always-auth=true"
}

Write-Host "  ✓ Registry @area-tech-alpha configurado" -ForegroundColor Green
Write-Host "  ✓ Auth token injetado e higienizado" -ForegroundColor Green
Write-Host "  ✓ always-auth = true (enforced)" -ForegroundColor Green
Add-Summary "npm registry @area-tech-alpha configurado"

# Verifica se funcionou
Write-Host ""
Write-Host "  🔍 Validando acesso ao package..." -ForegroundColor Cyan
try {
    $viewResult = npm view @area-tech-alpha/alpha-ci version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Acesso validado! Versão disponível: $viewResult" -ForegroundColor Green
        Add-Summary "Acesso ao GitHub Packages validado (v$viewResult)"
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

Write-Host "  ── Step 3/4: Configurando Docker (GHCR) ──" -ForegroundColor Cyan
Write-Host ""

if ($SkipDocker) {
    Write-Host "  ⏩ Pulando configuração Docker (-SkipDocker)" -ForegroundColor DarkGray
    Add-Summary "Docker: pulado (-SkipDocker)"
} elseif (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ Docker detectado" -ForegroundColor Green

    # Tenta verificar se o daemon está rodando
    try {
        $null = docker info 2>$null
    } catch {
        # Docker não está respondendo, tenta iniciar no Windows
        $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerPath) {
            Write-Host "  🐳 Docker não está rodando. Tentando iniciar Docker Desktop..." -ForegroundColor Cyan
            Start-Process $dockerPath
            Write-Host "    Aguarde o Docker inicializar e rode o script novamente." -ForegroundColor DarkGray
        }
    }

    # Login no GHCR usando o token que já temos
    Write-Host "  🔑 Fazendo login no GitHub Container Registry..." -ForegroundColor Cyan
    $ghToken | docker login ghcr.io -u $ghUsername --password-stdin 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Docker autenticado no ghcr.io como $ghUsername" -ForegroundColor Green
        Add-Summary "Docker autenticado no ghcr.io"

        # Tenta puxar a imagem para validar
        Write-Host "  📦 Puxando imagem alpha-ci..." -ForegroundColor Cyan
        $pullResult = docker pull ghcr.io/area-tech-alpha/alpha-ci:latest 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Imagem alpha-ci:latest baixada com sucesso" -ForegroundColor Green
            Add-Summary "Imagem Docker alpha-ci:latest baixada"
        } else {
            Write-Host "  ⚠ Não foi possível puxar a imagem. Ela será baixada na primeira execução." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ⚠ Falha no login Docker. Verifique se o token tem scope 'read:packages'." -ForegroundColor Yellow
    }
} else {
    Write-Host "  ⚠ Docker não encontrado. Instale em: https://docs.docker.com/get-docker/" -ForegroundColor Yellow
    Write-Host "    Você ainda pode usar: alpha-ci lint --no-docker" -ForegroundColor DarkGray
    Add-Summary "Docker: não encontrado (use --no-docker)"
}

Write-Host ""

# ══════════════════════════════════════════════════
#  STEP 4: Instalação Global
# ══════════════════════════════════════════════════

Write-Host "  ── Step 4/4: Instalando Alpha CI globalmente ──" -ForegroundColor Cyan
Write-Host ""

if ($SkipInstall) {
    Write-Host "  ⏩ Pulando instalação global (-SkipInstall)" -ForegroundColor DarkGray
    Add-Summary "Instalação global: pulada (-SkipInstall)"
} else {
    npm install -g @area-tech-alpha/alpha-ci

    if ($LASTEXITCODE -eq 0) {
        # Usa npm list ao invés de alpha-ci --version para não disparar o Docker container
        $installedVersion = (npm list -g @area-tech-alpha/alpha-ci --depth=0 2>$null) -match '@(\d+\.\d+\.\d+)'
        if ($Matches) { $installedVersion = "v$($Matches[1])" } else { $installedVersion = "?" }
        Write-Host "  ✓ Alpha CI instalado com sucesso! $installedVersion" -ForegroundColor Green
        Add-Summary "Alpha CI instalado globalmente ($installedVersion)"
    } else {
        Write-Host "  ⚠ Falha na instalação global. Tente rodar manualmente:" -ForegroundColor Yellow
        Write-Host "    npm install -g @area-tech-alpha/alpha-ci" -ForegroundColor Cyan
        Add-Summary "Instalação global: falhou (tente manualmente)"
    }
}

Write-Host ""

# ══════════════════════════════════════════════════
#  DONE: Resumo final
# ══════════════════════════════════════════════════

$setupEnd = Get-Date
$setupDuration = [math]::Round(($setupEnd - $setupStart).TotalSeconds)

Write-Host ""
Write-Host "  ══════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ Setup concluído com sucesso!" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  📋 Resumo:" -ForegroundColor White
foreach ($item in $summaryItems) {
    Write-Host "    ✓ $item" -ForegroundColor Green
}
Write-Host "    ⏱  Tempo total: ${setupDuration}s" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Agora você pode usar em qualquer projeto:" -ForegroundColor White
Write-Host "    alpha-ci all        " -NoNewline -ForegroundColor Cyan
Write-Host "# Pipeline completo" -ForegroundColor DarkGray
Write-Host "    alpha-ci security   " -NoNewline -ForegroundColor Cyan
Write-Host "# Scan de segurança" -ForegroundColor DarkGray
Write-Host "    alpha-ci lint --fix " -NoNewline -ForegroundColor Cyan
Write-Host "# Lint com auto-fix" -ForegroundColor DarkGray
Write-Host ""
