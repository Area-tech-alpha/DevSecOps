# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Auth Setup (Windows/PowerShell)                  ║
# ║  Configura .npmrc para GitHub Packages automaticamente       ║
# ║                                                              ║
# ║  Uso:                                                        ║
# ║  irm https://raw.githubusercontent.com/Area-tech-alpha/      ║
# ║    DevSecOps/main/cli/setup-auth.ps1 | iex                  ║
# ╚══════════════════════════════════════════════════════════════╝

$ErrorActionPreference = "Stop"

Write-Host "`n🔑 Alpha CI — Configurando acesso ao GitHub Packages`n" -ForegroundColor Cyan

$npmrcFile = Join-Path $env:USERPROFILE ".npmrc"
$ghToken = $null

# ── Strategy 1: gh CLI ──
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ GitHub CLI detectado" -ForegroundColor Green
    try {
        $null = gh auth status 2>&1
        $ghToken = (gh auth token 2>$null).Trim()
        if ($ghToken) {
            Write-Host "  ✓ Token extraído via gh auth token" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ⚠ GitHub CLI não autenticado. Execute: gh auth login" -ForegroundColor Yellow
    }
}

# ── Strategy 2: Environment variable ──
if (-not $ghToken) {
    $ghToken = $env:GITHUB_TOKEN
    if (-not $ghToken) { $ghToken = $env:NODE_AUTH_TOKEN }
    if ($ghToken) {
        Write-Host "  ✓ Token encontrado via variável de ambiente" -ForegroundColor Green
    }
}

# ── Strategy 3: Existing .npmrc ──
if (-not $ghToken -and (Test-Path $npmrcFile)) {
    $match = Select-String -Path $npmrcFile -Pattern '//npm\.pkg\.github\.com/:_authToken=(.+)' -ErrorAction SilentlyContinue
    if ($match) {
        $ghToken = $match.Matches[0].Groups[1].Value
        Write-Host "  ✓ Token encontrado no .npmrc existente" -ForegroundColor Green
    }
}

# ── Strategy 4: Interactive prompt ──
if (-not $ghToken) {
    Write-Host "  ⚠ Nenhum token detectado automaticamente." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Crie um Personal Access Token (classic):" -ForegroundColor White
    Write-Host "  → https://github.com/settings/tokens/new" -ForegroundColor Cyan
    Write-Host "    ☑ read:packages (único scope necessário)" -ForegroundColor DarkGray
    Write-Host ""
    $ghToken = Read-Host "  Cole o token aqui (ghp_...)"

    if (-not $ghToken) {
        Write-Host "`n  ❌ Nenhum token fornecido. Abortando." -ForegroundColor Red
        exit 1
    }
}

# ── Configure .npmrc ──
if (-not (Test-Path $npmrcFile)) { New-Item -Path $npmrcFile -ItemType File | Out-Null }

$npmrcContent = Get-Content $npmrcFile -Raw -ErrorAction SilentlyContinue
if (-not $npmrcContent) { $npmrcContent = "" }

# Registry scope
if ($npmrcContent -notmatch '@area-tech-alpha:registry=https://npm.pkg.github.com') {
    Add-Content -Path $npmrcFile -Value '@area-tech-alpha:registry=https://npm.pkg.github.com'
}

# Auth token
if ($npmrcContent -match '//npm\.pkg\.github\.com/:_authToken=') {
    (Get-Content $npmrcFile) -replace '//npm\.pkg\.github\.com/:_authToken=.*', "//npm.pkg.github.com/:_authToken=$ghToken" |
        Set-Content $npmrcFile
} else {
    Add-Content -Path $npmrcFile -Value "//npm.pkg.github.com/:_authToken=$ghToken"
}

Write-Host ""
Write-Host "  ✅ .npmrc configurado com sucesso!" -ForegroundColor Green
Write-Host ""
Write-Host "  Agora você pode usar:" -ForegroundColor White
Write-Host "  npx @area-tech-alpha/alpha-ci all" -ForegroundColor Cyan
Write-Host "  npx @area-tech-alpha/alpha-ci security" -ForegroundColor Cyan
Write-Host "  npx @area-tech-alpha/alpha-ci lint" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Ou instalar globalmente:" -ForegroundColor DarkGray
Write-Host "  npm install -g @area-tech-alpha/alpha-ci" -ForegroundColor Cyan
Write-Host ""
