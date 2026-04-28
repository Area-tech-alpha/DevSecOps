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
        $ghToken = $match.Matches[0].Groups[1].Value.Trim() -replace '[\r\n\s\t]', ''
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
    $ghToken = $ghToken.Trim() -replace '[\r\n\s\t]', ''
}

# ── Validação Ativa do Token ──
Write-Host "  🔍 Validando token contra a API do GitHub..." -ForegroundColor Cyan

try {
    $headers = @{ "Authorization" = "token $ghToken" }
    $response = Invoke-WebRequest -Uri "https://api.github.com/user" -Headers $headers -Method Get
    $httpStatus = $response.StatusCode

    if ($httpStatus -ne 200) {
        Write-Host "  ❌ Token inválido ou expirado (HTTP $httpStatus)." -ForegroundColor Red
        exit 1
    }

    # Extrair escopos
    $scopes = $response.Headers["X-OAuth-Scopes"]
    $displayScopes = if ($null -eq $scopes) { "none (fine-grained?)" } else { $scopes }
    Write-Host "  ✓ Token válido. Scopes: $displayScopes" -ForegroundColor Green

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

    # Verificar acesso à Org e SSO
    try {
        $orgResponse = Invoke-WebRequest -Uri "https://api.github.com/orgs/Area-tech-alpha" -Headers $headers -Method Get
    } catch {
        Write-Host "" -ForegroundColor Red
        Write-Host "  ⚠️  Possível problema de SSO ou Acesso à Org." -ForegroundColor Yellow
        Write-Host "     Você deve autorizar este token para a organização 'Area-tech-alpha':" -ForegroundColor White
        Write-Host "     → https://github.com/settings/tokens" -ForegroundColor Cyan
        Write-Host "     Clique no seu token → 'Configure SSO' ao lado de 'Area-tech-alpha' → 'Authorize'" -ForegroundColor DarkGray
        Write-Host ""
        Read-Host "  Pressione ENTER após autorizar para continuar ou CTRL+C para sair..."
    }

} catch {
    Write-Host "  ❌ Falha crítica na validação do token: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "     Verifique sua conexão e o token em: https://github.com/settings/tokens" -ForegroundColor DarkGray
    exit 1
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

# Higieniza o .npmrc (remove entradas conflitantes ou malformadas no Windows)
try {
    if (Test-Path $npmrcGlobal) {
        $content = Get-Content $npmrcGlobal -ErrorAction SilentlyContinue
        if ($content) {
            $newContent = $content | Where-Object { 
                $_ -notmatch 'area-tech-alpha:registry' -and 
                $_ -notmatch 'npm\.pkg\.github\.com/:_authToken' -and
                $_ -notmatch 'npm\.pkg\.github\.com/always-auth'
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

# Injeta always-auth diretamente no arquivo (evita erro no npm v9+)
Add-Content -Path $npmrcGlobal -Value "always-auth=true"

Write-Host "  ✓ Registry @area-tech-alpha configurado" -ForegroundColor Green
Write-Host "  ✓ Auth token injetado e higienizado" -ForegroundColor Green
Write-Host "  ✓ always-auth = true (enforced)" -ForegroundColor Green

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

# ══════════════════════════════════════════════════
#  STEP 4: Instalação Global
# ══════════════════════════════════════════════════

Write-Host "  ── Step 4/4: Instalando Alpha CI globalmente ──" -ForegroundColor Cyan
Write-Host ""

npm install -g @area-tech-alpha/alpha-ci

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Alpha CI instalado com sucesso!" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Falha na instalação global. Tente rodar manually:" -ForegroundColor Yellow
    Write-Host "    npm install -g @area-tech-alpha/alpha-ci" -ForegroundColor Cyan
}

Write-Host ""

# ══════════════════════════════════════════════════
#  DONE
# ══════════════════════════════════════════════════

Write-Host ""
Write-Host "  ══════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ Setup concluído com sucesso!" -ForegroundColor Green
Write-Host "  ══════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Agora você pode usar em qualquer projeto:" -ForegroundColor White
Write-Host "    alpha-ci all" -ForegroundColor Cyan
Write-Host ""
