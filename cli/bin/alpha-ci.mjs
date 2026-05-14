#!/usr/bin/env node
// ╔══════════════════════════════════════════════════════════════╗
// ║  Alpha CI — NPM CLI Wrapper                                  ║
// ║  Wrapper Node.js que orquestra o Docker container             ║
// ║  Permite: npx @area-tech-alpha/alpha-ci security             ║
// ╚══════════════════════════════════════════════════════════════╝

import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, unlinkSync, realpathSync, copyFileSync, mkdirSync, chmodSync, statSync } from 'node:fs';
import { resolve, basename, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const IMAGE = 'ghcr.io/area-tech-alpha/alpha-ci:latest';
const IMAGE_LOCAL = 'alpha-ci:latest';
const VERSION = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf-8')).version;
const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Resolve global .npmrc path (never use local .npmrc from consumer projects) ──
import { homedir } from 'node:os';
function getGlobalNpmrc() {
  try {
    return execFileSync('npm', ['config', 'get', 'userconfig'], { encoding: 'utf-8' }).trim();
  } catch {
    return resolve(homedir(), '.npmrc');
  }
}
const GLOBAL_NPMRC = getGlobalNpmrc();

// ── Colors ──
const c = {
  red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m',
  blue: '\x1b[34m', cyan: '\x1b[36m', magenta: '\x1b[35m',
  white: '\x1b[37m', gray: '\x1b[90m',
  bold: '\x1b[1m', dim: '\x1b[2m', underline: '\x1b[4m',
  reset: '\x1b[0m',
  // Background colors for status badges
  bgGreen: '\x1b[42m', bgRed: '\x1b[41m', bgYellow: '\x1b[43m',
  bgMagenta: '\x1b[45m', bgCyan: '\x1b[46m',
  black: '\x1b[30m',
};

/* eslint-disable no-console -- CLI tool: console is the primary output interface */
const log = (msg) => console.log(msg);
const error = (msg) => console.error(`${c.red}${msg}${c.reset}`);
const info = (msg) => console.log(`${c.cyan}${msg}${c.reset}`);
const success = (msg) => console.log(`${c.green}${msg}${c.reset}`);
const badge = (bg, text) => `${bg}${c.black}${c.bold} ${text} ${c.reset}`;
/* eslint-enable no-console */

// ── Timer ──
const startTime = Date.now();

function ensureHookMarker(content) {
  const marker = '# ALPHA-CI-HOOK: installed by alpha-ci\n';
  if (content.includes('ALPHA-CI-HOOK')) return content;

  if (content.startsWith('#!')) {
    const firstLineEnd = content.indexOf('\n');
    if (firstLineEnd !== -1) {
      return content.slice(0, firstLineEnd + 1) + marker + content.slice(firstLineEnd + 1);
    }
  }

  return marker + content;
}

// ── Allowed commands (whitelist) ──
const ALLOWED_COMMANDS = new Set([
  'all', 'security', 'lint', 'test', 'build', 'e2e', 'shell', 'detect', 'help',
]);

// ── Parse args ──
const args = process.argv.slice(2);
const command = args[0] || 'help';

// Validate command against whitelist
if (!ALLOWED_COMMANDS.has(command) && command !== '--help' && command !== '-h' && command !== '--version') {
  error(`❌ Comando desconhecido: ${command}`);
  process.exit(1);
}

// Extract options — tokens ONLY from env vars (never CLI args)
let targetPath = process.cwd();
let verbose = false;
let rebuild = false;
let noDocker = false;
let autoFix = false;
let reportFormat = 'text';
let reportOutput = '';

// Security: Tokens are sourced ONLY from environment variables or global .npmrc.
const semgrepToken = process.env.SEMGREP_APP_TOKEN || '';
let githubToken = process.env.GITHUB_TOKEN || process.env.NODE_AUTH_TOKEN || '';

// Fallback: If token not in env, try to extract from global .npmrc
if (!githubToken && existsSync(GLOBAL_NPMRC)) {
  try {
    const npmrcContent = readFileSync(GLOBAL_NPMRC, 'utf-8');
    // Match //npm.pkg.github.com/:_authToken=TOKEN
    const match = npmrcContent.match(/\/\/npm\.pkg\.github\.com\/:_authToken=(.+)/);
    if (match) {
      githubToken = match[1].trim();
    }
  } catch (e) {
    // Ignore read errors
  }
}

// ── Allowed report formats (whitelist) ──
const ALLOWED_FORMATS = new Set(['text', 'json', 'sarif']);

for (let i = 1; i < args.length; i++) {
  switch (args[i]) {
    case '-p': case '--path':
      targetPath = resolve(args[++i] || '.');
      break;
    case '-v': case '--verbose':
      verbose = true;
      break;
    case '--rebuild':
      rebuild = true;
      break;
    case '--no-docker':
      noDocker = true;
      break;
    case '--fix':
      autoFix = true;
      break;
    case '--format': {
      const fmt = args[++i] || 'text';
      if (!ALLOWED_FORMATS.has(fmt)) {
        error(`❌ Formato inválido: ${fmt}. Use: text, json, sarif`);
        process.exit(1);
      }
      reportFormat = fmt;
      break;
    }
    case '--output':
      reportOutput = args[++i] || '';
      break;
    case '--semgrep-token':
    case '--github-token':
      error(`⚠️  --${args[i].replace('--', '')} foi removido por segurança.`);
      error(`   Use a variável de ambiente correspondente:`);
      error(`   export SEMGREP_APP_TOKEN=<token>`);
      error(`   export GITHUB_TOKEN=<token>`);
      i++; // skip the value
      process.exit(1);
      break; // eslint: no-fallthrough (process.exit never returns, but ESLint can't infer that)
    case '--version':
      log(`alpha-ci v${VERSION}`);
      process.exit(0);
      break;
  }
}

if (command === 'help' || command === '--help' || command === '-h') {
  log(`
${c.magenta}${c.bold}  ╔═══════════════════════════════════════════════════════╗
  ║                                                       ║
  ║   🛡️  ${c.white}Alpha CI${c.magenta} — DevSecOps Pipeline                  ║
  ║   ${c.dim}Area Tech Alpha · Local Runner${c.reset}${c.magenta}${c.bold}                       ║
  ║                                                       ║
  ╚═══════════════════════════════════════════════════════╝${c.reset}
  ${c.gray}v${VERSION}${c.reset}

  ${c.bold}${c.underline}USAGE${c.reset}

    ${c.white}$${c.reset} ${c.cyan}alpha-ci${c.reset} ${c.yellow}<command>${c.reset} ${c.dim}[options]${c.reset}

  ${c.bold}${c.underline}COMMANDS${c.reset}

    ${c.cyan}all${c.reset}        ${c.dim}│${c.reset} Pipeline completo ${c.dim}(security → lint → test → build)${c.reset}
    ${c.cyan}security${c.reset}   ${c.dim}│${c.reset} Scanners de segurança ${c.dim}(Gitleaks + OSV + Semgrep)${c.reset}
    ${c.cyan}lint${c.reset}       ${c.dim}│${c.reset} Linting ${c.dim}(ESLint / Ruff / golangci-lint)${c.reset}
    ${c.cyan}test${c.reset}       ${c.dim}│${c.reset} Testes unitários ${c.dim}(Jest / Vitest / pytest / go test)${c.reset}
    ${c.cyan}build${c.reset}      ${c.dim}│${c.reset} Build do projeto
    ${c.cyan}e2e${c.reset}        ${c.dim}│${c.reset} Testes E2E ${c.dim}(Playwright / Cypress)${c.reset}
    ${c.cyan}shell${c.reset}      ${c.dim}│${c.reset} Shell interativo no container
    ${c.cyan}detect${c.reset}     ${c.dim}│${c.reset} Detecta tipo do projeto

  ${c.bold}${c.underline}OPTIONS${c.reset}

    ${c.yellow}-p, --path ${c.dim}<dir>${c.reset}          Repositório alvo ${c.dim}(default: pwd)${c.reset}
    ${c.yellow}-v, --verbose${c.reset}              Output detalhado
    ${c.yellow}--no-docker${c.reset}                Roda sem Docker ${c.dim}(requer tools locais)${c.reset}
    ${c.yellow}--fix${c.reset}                      Auto-fix problemas de lint
    ${c.yellow}--format ${c.dim}<json|sarif|text>${c.reset} Formato do output ${c.dim}(default: text)${c.reset}
    ${c.yellow}--output ${c.dim}<file>${c.reset}            Salva relatório em arquivo
    ${c.yellow}--rebuild${c.reset}                  Força rebuild da imagem Docker
    ${c.yellow}--version${c.reset}                  Mostra a versão

  ${c.bold}${c.underline}EXAMPLES${c.reset}

    ${c.dim}# Scan de segurança no repo atual${c.reset}
    ${c.white}$${c.reset} ${c.cyan}alpha-ci security${c.reset}

    ${c.dim}# Pipeline completo em outro diretório${c.reset}
    ${c.white}$${c.reset} ${c.cyan}alpha-ci all --path ../meu-projeto${c.reset}

    ${c.dim}# Lint com auto-fix + report JSON${c.reset}
    ${c.white}$${c.reset} ${c.cyan}alpha-ci lint --fix --format json --output report.json${c.reset}

    ${c.dim}# Rodar sem Docker (tools locais)${c.reset}
    ${c.white}$${c.reset} ${c.cyan}alpha-ci security --no-docker${c.reset}

  ${c.bold}${c.underline}ENVIRONMENT${c.reset}

    ${c.green}GITHUB_TOKEN${c.reset}         ${c.dim}│${c.reset} GitHub PAT para packages privados
    ${c.green}SEMGREP_APP_TOKEN${c.reset}    ${c.dim}│${c.reset} Token do Semgrep para regras custom
    ${c.green}NODE_AUTH_TOKEN${c.reset}      ${c.dim}│${c.reset} Alias para GITHUB_TOKEN

  ${c.bold}${c.underline}SETUP${c.reset} ${c.dim}(execute uma única vez)${c.reset}

    ${c.white}$${c.reset} ${c.cyan}bash <(curl -fsSL https://raw.githubusercontent.com/\n      Area-tech-alpha/DevSecOps/main/cli/setup-auth.sh)${c.reset}

  ${c.dim}─────────────────────────────────────────────────${c.reset}
  ${c.dim}💡 Dica: Use ${c.white}alpha-ci all${c.dim} antes de cada push.${c.reset}
  ${c.dim}   O pre-push hook é instalado automaticamente.${c.reset}
`);
  process.exit(0);
}

// ── Validate target path ──

if (!existsSync(targetPath)) {
  error(`❌ Diretório não encontrado: ${targetPath}`);
  process.exit(1);
}
try {
  if (!statSync(targetPath).isDirectory()) {
    error(`❌ O caminho informado não é um diretório: ${targetPath}`);
    error(`   Use -p/--path para apontar para a raiz do repositório.`);
    process.exit(1);
  }
} catch { /* statSync error already handled above */ }

// ── Security: Validate target path against path traversal ──
function validateTargetPath(p) {
  let realPath;
  try {
    realPath = realpathSync(p);
  } catch {
    error(`❌ Não foi possível resolver o caminho: ${p}`);
    process.exit(1);
  }

  // Block mounting sensitive system directories
  const BLOCKED_PATHS = [
    '/etc', '/var', '/usr', '/bin', '/sbin', '/boot', '/dev',
    '/proc', '/sys', '/root', '/run', '/lib', '/lib64',
  ];

  for (const blocked of BLOCKED_PATHS) {
    if (realPath === blocked || realPath.startsWith(blocked + '/')) {
      error(`❌ Acesso bloqueado: ${realPath}`);
      error(`   O Alpha CI não pode montar diretórios do sistema.`);
      error(`   Use um diretório de projeto válido.`);
      process.exit(1);
    }
  }

  // Warn if mounting home root
  const homeDir = process.env.HOME || '';
  if (realPath === homeDir) {
    error(`⚠️  Montar o diretório HOME inteiro não é recomendado.`);
    error(`   Aponte para o repositório específico.`);
    process.exit(1);
  }

  return realPath;
}

targetPath = validateTargetPath(targetPath);

// ── Persistence: Auto-install pre-push hook on first run in a project ──
/* (function installHookOnHost() {
  try {
    const auto = process.env.ALPHA_CI_AUTO_INSTALL_HOOK;
    if (auto === 'false' || auto === '0') return;

    // Proteção: não tenta atualizar o hook se ele já estiver rodando (evita race condition)
    if (process.env.GIT_REFLOG_ACTION || process.env.GIT_DIR) return;

    const hostGitDir = existsSync(resolve(targetPath, '.git')) ? resolve(targetPath, '.git') : null;
    if (!hostGitDir) return;

    const tpl = resolve(__dirname, '../hooks/pre-push-template');
    const fallbackTpl = resolve(process.cwd(), 'cli/hooks/pre-push-template');

    let src = null;
    if (existsSync(tpl)) src = tpl;
    else if (existsSync(fallbackTpl)) src = fallbackTpl;
    else return;

    const hooksDir = resolve(hostGitDir, 'hooks');
    if (!existsSync(hooksDir)) mkdirSync(hooksDir, { recursive: true });

    const dest = resolve(hooksDir, 'pre-push');

    if (existsSync(dest)) {
      const existingContent = readFileSync(dest, 'utf-8');

      // If our marker is there AND shebang is at line 1
      if (existingContent.includes('ALPHA-CI-HOOK') && existingContent.startsWith('#!')) {
        // Optimization: check if the template core is actually different
        const templateContent = ensureHookMarker(readFileSync(src, 'utf-8'));
        if (existingContent === templateContent) return; // Already up to date
      }

      try { copyFileSync(dest, `${dest}.alpha-ci.bak`); } catch (e) {}
    }

    copyFileSync(src, dest);
    const content = readFileSync(dest, 'utf-8');
    writeFileSync(dest, ensureHookMarker(content), { mode: 0o755 });
    chmodSync(dest, 0o755);
    info(`🔧 Installed pre-push hook at ${dest}`);
  } catch (e) {
    // Silent fail unless verbose (validation path might be sensitive)
  }
})(); */

// ── Security: Validate report output path ──
function validateOutputPath(output, target) {
  if (!output) return '';

  const resolvedOutput = resolve(target, output);
  let outputDir;
  try {
    // dirname may not exist yet, check parent
    outputDir = realpathSync(dirname(resolvedOutput));
  } catch {
    outputDir = dirname(resolvedOutput);
  }

  const realTarget = realpathSync(target);
  if (!outputDir.startsWith(realTarget)) {
    error(`❌ O caminho de output deve estar dentro do diretório alvo.`);
    error(`   Target: ${realTarget}`);
    error(`   Output: ${resolvedOutput}`);
    process.exit(1);
  }

  return resolvedOutput;
}

if (reportOutput) {
  reportOutput = validateOutputPath(reportOutput, targetPath);
}

// ── Check Docker (using execFileSync — no shell interpolation) ──
function dockerAvailable() {
  try {
    execFileSync('docker', ['info'], { stdio: 'ignore' });
    return true;
  } catch (e) {
    // No Windows, tenta iniciar o Docker Desktop automaticamente
    if (process.platform === 'win32') {
      const dockerPath = 'C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe';
      if (existsSync(dockerPath)) {
        info('🐳 Docker não está rodando. Tentando iniciar Docker Desktop...');
        try {
          spawn(dockerPath, [], { detached: true, stdio: 'ignore' }).unref();
        } catch (err) {}
      }
    }
    return false;
  }
}

function imageExists(img) {
  try {
    execFileSync('docker', ['image', 'inspect', img], { stdio: 'ignore' });
    return true;
  } catch { return false; }
}

function pullOrBuild() {
  // Try pulling from GHCR first
  info('📦 Puxando imagem Docker...');
  try {
    execFileSync('docker', ['pull', IMAGE], { stdio: 'inherit' });
    return IMAGE;
  } catch {
    log(`${c.dim}  GHCR indisponível, tentando build local...${c.reset}`);
  }

  // Fallback: build local if Dockerfile exists in DevSecOps repo
  const cliDir = findCliDir();
  if (cliDir && existsSync(`${cliDir}/Dockerfile`)) {
    info('🏗 Construindo imagem local...');
    execFileSync('docker', [
      'build', '-t', IMAGE_LOCAL,
      '-f', `${cliDir}/Dockerfile`,
      `${cliDir}/..`,
    ], { stdio: 'inherit' });
    return IMAGE_LOCAL;
  }

  error('❌ Não foi possível obter a imagem Docker.');
  error('   Opções:');
  error('   1. docker pull ghcr.io/area-tech-alpha/alpha-ci:latest');
  error('   2. Clone o DevSecOps e rode: docker build -t alpha-ci cli/');
  process.exit(1);
}

function findCliDir() {
  // Check if we're inside the DevSecOps repo
  const candidates = [
    resolve(__dirname, '..'),
    resolve(process.env.HOME || '', 'DevSecOps/cli'),
    '/opt/alpha-ci',
  ];
  for (const dir of candidates) {
    if (existsSync(`${dir}/Dockerfile`)) return dir;
  }
  return null;
}

// ── Create secure env file for Docker (avoids token leakage via ps/inspect) ──
function createEnvFile() {
  const envFilePath = resolve(tmpdir(), `.alpha-ci-env-${process.pid}-${Date.now()}`);
  const envContent = [
    `SEMGREP_APP_TOKEN=${semgrepToken}`,
    `GITHUB_TOKEN=${githubToken}`,
    `NODE_AUTH_TOKEN=${githubToken}`,
    `AUTO_FIX=${autoFix ? 'true' : 'false'}`,
    `REPORT_FORMAT=${reportFormat}`,
    `REPORT_OUTPUT=${reportOutput ? `/output/${basename(reportOutput)}` : ''}`,
    `VERBOSE=${verbose ? 'true' : 'false'}`,
  ].join('\n') + '\n';

  writeFileSync(envFilePath, envContent, { mode: 0o600 });
  return envFilePath;
}

function cleanupEnvFile(envFilePath) {
  try {
    unlinkSync(envFilePath);
  } catch {
    // Best effort cleanup
  }
}

function exitCodeFromSignal(signal) {
  if (signal === 'SIGINT') return 130;
  if (signal === 'SIGTERM') return 143;
  return 1;
}

function exitCodeFromChildClose(code, signal) {
  if (typeof code === 'number') return code;
  if (signal) return exitCodeFromSignal(signal);
  return 1;
}

// ── No-Docker Mode ──
function runNoDocker() {
  const cliDir = findCliDir();
  const scriptsDir = cliDir ? resolve(cliDir, 'scripts') : null;

  // Try to find run-local.sh
  let localRunner = null;
  const candidates = [
    scriptsDir ? resolve(scriptsDir, 'run-local.sh') : null,
    resolve(__dirname, '..', 'scripts', 'run-local.sh'),
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      localRunner = candidate;
      break;
    }
  }

  if (!localRunner) {
    // Fallback: run entrypoint.sh directly
    const entrypoint = scriptsDir ? resolve(scriptsDir, 'entrypoint.sh') : null;
    if (entrypoint && existsSync(entrypoint)) {
      localRunner = entrypoint;
    } else {
      error('❌ Scripts do Alpha CI não encontrados.');
      error('   Clone o repositório DevSecOps ou use Docker.');
      process.exit(1);
    }
  }

  const repoName = basename(targetPath);
  log('');
  log(`  ${c.magenta}${c.bold}🛡️  Alpha CI${c.reset} ${c.gray}v${VERSION}${c.reset}  ${badge(c.bgYellow, 'NO-DOCKER')}`);
  log(`  ${c.gray}${'─'.repeat(48)}${c.reset}`);
  log(`  ${c.white}📂 Projeto${c.reset}  ${c.bold}${repoName}${c.reset} ${c.dim}(${targetPath})${c.reset}`);
  log(`  ${c.white}⚡ Comando${c.reset}  ${c.cyan}${c.bold}${command}${c.reset}`);
  if (autoFix) log(`  ${c.white}🔧 Fix${c.reset}     ${c.green}enabled${c.reset}`);
  if (verbose) log(`  ${c.white}📢 Verbose${c.reset} ${c.green}enabled${c.reset}`);
  log(`  ${c.gray}${'─'.repeat(48)}${c.reset}`);
  log('');

  const env = {
    ...process.env,
    TARGET_PATH: targetPath,
    WORKSPACE: targetPath,
    SEMGREP_APP_TOKEN: semgrepToken,
    GITHUB_TOKEN: githubToken,
    NODE_AUTH_TOKEN: githubToken,
    VERBOSE: verbose ? 'true' : 'false',
    AUTO_FIX: autoFix ? 'true' : 'false',
    REPORT_FORMAT: reportFormat,
    REPORT_OUTPUT: reportOutput,
    NPM_CONFIG_USERCONFIG: GLOBAL_NPMRC,
  };

  const child = spawn('bash', [localRunner, command], {
    stdio: 'inherit',
    cwd: targetPath,
    env,
  });

  child.on('close', (code, signal) => {
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    const exitCode = exitCodeFromChildClose(code, signal);
    log('');
    log(`  ${c.gray}${'\u2500'.repeat(48)}${c.reset}`);
    if (exitCode === 0) {
      log(`  ${badge(c.bgGreen, '\u2713 PASSED')}  ${c.green}${c.bold}Pipeline conclu\u00eddo${c.reset}  ${c.gray}\u23f1 ${elapsed}s${c.reset}`);
    } else {
      log(`  ${badge(c.bgRed, '\u2717 FAILED')}  ${c.red}${c.bold}Pipeline falhou${c.reset} ${c.dim}(exit ${exitCode})${c.reset}  ${c.gray}\u23f1 ${elapsed}s${c.reset}`);
    }
    log(`  ${c.gray}${'\u2500'.repeat(48)}${c.reset}`);
    log('');
    process.exit(exitCode);
  });
  child.on('error', (err) => {
    if (err.code === 'ENOENT') {
      error(`❌ bash não encontrado. Verifique sua instalação.`);
    } else {
      error(`❌ Erro ao executar: ${err.message}`);
    }
    process.exit(1);
  });
}

// ── Check and optionally update the global NPM package ──
async function checkForUpdates() {
  try {
    const autoUpdate = process.env.ALPHA_CI_AUTO_UPDATE === 'true';

    // Short, best-effort check. Never install into the target project.
    const latest = execFileSync('npm', ['view', '@area-tech-alpha/alpha-ci', 'version'], {
      encoding: 'utf-8',
      timeout: 1500,
      env: { ...process.env, NPM_CONFIG_USERCONFIG: GLOBAL_NPMRC }
    }).trim();

    if (latest && latest !== VERSION) {
      if (autoUpdate) {
        log(`${c.cyan}🔄 Atualizando alpha-ci para a versão ${latest}...${c.reset}`);
        try {
          // Detect if installed globally or locally (use spawnSync to check exit code)
          const isGlobal = spawnSync('npm', ['list', '-g', '@area-tech-alpha/alpha-ci'], {
            stdio: 'ignore',
            env: { ...process.env, NPM_CONFIG_USERCONFIG: GLOBAL_NPMRC }
          }).status === 0;

          if (!isGlobal) {
            log(`${c.yellow}⚠️  Auto-update local desativado para não modificar o projeto alvo.${c.reset}`);
            log(`${c.dim}   Execute: npm install -g @area-tech-alpha/alpha-ci${c.reset}\n`);
            return;
          }

          spawn('npm', ['install', '-g', '@area-tech-alpha/alpha-ci@latest'], {
            detached: true,
            stdio: 'ignore',
            env: { ...process.env, NPM_CONFIG_USERCONFIG: GLOBAL_NPMRC }
          }).unref();

          log(`${c.green}✅ Atualização iniciada em segundo plano. Será aplicada na próxima execução.${c.reset}\n`);
        } catch (e) {
          log(`${c.yellow}⚠️  Não foi possível auto-atualizar. Execute manualmente: npm install -g @area-tech-alpha/alpha-ci${c.reset}\n`);
        }
      } else {
        log(`${c.yellow}${c.bold}🔔 Nova versão disponível: ${latest} (atual: ${VERSION})${c.reset}`);
        log(`${c.dim}   Execute: npm install -g @area-tech-alpha/alpha-ci${c.reset}\n`);
      }
    }
  } catch (e) {
    // Ignore update check failures
  }
}

// ── Run ──
async function run() {
  // Check for updates only when enabled; the check can touch the network.
  if ((process.env.ALPHA_CI_CHECK_UPDATES === 'true' || process.env.ALPHA_CI_AUTO_UPDATE === 'true') && !args.includes('--version')) {
    checkForUpdates();
  }

  // --no-docker mode
  if (noDocker) {
    return runNoDocker();
  }

  if (!dockerAvailable()) {
    error('❌ Docker não está disponível.');
    if (process.platform === 'darwin') {
      error('   Instale: brew install --cask docker');
    } else if (process.platform === 'win32') {
      error('   Instale: https://docs.docker.com/desktop/install/windows-install/');
    } else {
      error('   Instale: https://docs.docker.com/engine/install/');
    }
    error(`   Ou use: ${c.cyan}alpha-ci --no-docker ${command}${c.reset}`);
    process.exit(1);
  }

  // Resolve image
  let image;
  if (rebuild || (!imageExists(IMAGE) && !imageExists(IMAGE_LOCAL))) {
    image = pullOrBuild();
  } else {
    image = imageExists(IMAGE) ? IMAGE : IMAGE_LOCAL;
    // Tenta atualizar a imagem silenciosamente se for a oficial
    if (image === IMAGE && !rebuild) {
      const pullTimeout = parseInt(process.env.ALPHA_CI_DOCKER_PULL_TIMEOUT, 10) || 15000;
      try {
        log(`${c.dim}ℹ️  Verificando atualizações da imagem Docker...${c.reset}`);
        execFileSync('docker', ['pull', IMAGE], { stdio: 'ignore', timeout: pullTimeout });
      } catch (e) {
        // Ignora erro (offline, timeout ou interrupção) e usa cache
      }
    }
  }

  const repoName = basename(targetPath);
  log('');
  log(`  ${c.magenta}${c.bold}🛡️  Alpha CI${c.reset} ${c.gray}v${VERSION}${c.reset}  ${badge(c.bgCyan, 'DOCKER')}`);
  log(`  ${c.gray}${'─'.repeat(48)}${c.reset}`);
  log(`  ${c.white}📂 Projeto${c.reset}  ${c.bold}${repoName}${c.reset} ${c.dim}(${targetPath})${c.reset}`);
  log(`  ${c.white}🐳 Imagem${c.reset}   ${c.dim}${image}${c.reset}`);
  log(`  ${c.white}⚡ Comando${c.reset}  ${c.cyan}${c.bold}${command}${c.reset}`);
  if (autoFix) log(`  ${c.white}🔧 Fix${c.reset}     ${c.green}enabled${c.reset}`);
  if (verbose) log(`  ${c.white}📢 Verbose${c.reset} ${c.green}enabled${c.reset}`);
  if (reportOutput) log(`  ${c.white}📄 Report${c.reset}  ${c.yellow}${reportFormat}${c.reset} ${c.dim}→${c.reset} ${reportOutput}`);
  log(`  ${c.gray}${'─'.repeat(48)}${c.reset}`);
  log('');

  // Create secure env file (prevents token leakage via ps/docker inspect)
  const envFile = createEnvFile();

  // No Windows, NÃO substituímos as barras (\\ por /) porque o docker.exe
  // entende C:\ perfeitamente. Manter \ evita que o Git Bash confunda
  // o argumento de volume com uma lista de caminhos POSIX.
  const mountPath = targetPath;

  // Build docker run args with security hardening
  const dockerArgs = [
    'run', '--rm',
    // Security: drop all capabilities, prevent privilege escalation
    '--cap-drop=ALL',
    '--security-opt', 'no-new-privileges',
    // Volumes (mounts to /host_workspace to allow isolation from host OS node_modules)
    '-v', `${mountPath}:/host_workspace`,
    // Cache volumes (persist between runs, bumped to v2 to fix root ownership from older versions)
    '-v', 'alpha-ci-npm-cache-v2:/home/alpha-ci/.npm',
    '-v', 'alpha-ci-pip-cache-v2:/home/alpha-ci/.cache/pip',
    '-v', 'alpha-ci-pnpm-cache-v2:/home/alpha-ci/.local/share/pnpm/store',
    // Environment from secure file (tokens not visible in ps/inspect)
    '--env-file', envFile,
  ];

  // Mount global .npmrc if it exists so container has host's auth
  if (existsSync(GLOBAL_NPMRC)) {
    dockerArgs.push('-v', `${GLOBAL_NPMRC}:/home/alpha-ci/.npmrc:ro`);
  }

  // Interactive mode for shell
  if (command === 'shell') {
    dockerArgs.push('-it');
  }

  // Report output: mount the output dir so the file is accessible from host
  if (reportOutput) {
    const outputDir = dirname(reportOutput);
    dockerArgs.push('-v', `${outputDir}:/output`);
  }

  dockerArgs.push(image, command);

  // Spawn docker
  const child = spawn('docker', dockerArgs, {
    stdio: 'inherit',
    env: { 
      ...process.env, 
      NPM_CONFIG_USERCONFIG: GLOBAL_NPMRC,
      MSYS_NO_PATHCONV: '1',   // Evita que o Git Bash corrompa paths Unix-like como /host_workspace
      MSYS2_ARG_CONV_EXCL: '*' // Proteção extra para MSYS2
    },
  });

  let terminating = false;
  let forceExitTimer = null;

  function terminateFromSignal(signal) {
    if (terminating) return;
    terminating = true;

    const exitCode = exitCodeFromSignal(signal);
    cleanupEnvFile(envFile);

    try {
      if (!child.killed) child.kill(signal);
    } catch {
      // Best effort signal forwarding.
    }

    forceExitTimer = setTimeout(() => {
      error(`❌ Docker não encerrou após ${signal}; finalizando alpha-ci.`);
      process.exit(exitCode);
    }, 5000);
  }

  child.on('close', (code, signal) => {
    if (forceExitTimer) clearTimeout(forceExitTimer);
    cleanupEnvFile(envFile);
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    const exitCode = exitCodeFromChildClose(code, signal);
    log('');
    log(`  ${c.gray}${'─'.repeat(48)}${c.reset}`);
    if (exitCode === 0) {
      log(`  ${badge(c.bgGreen, '✓ PASSED')}  ${c.green}${c.bold}Pipeline concluído${c.reset}  ${c.gray}⏱ ${elapsed}s${c.reset}`);
    } else {
      log(`  ${badge(c.bgRed, '✗ FAILED')}  ${c.red}${c.bold}Pipeline falhou${c.reset} ${c.dim}(exit ${exitCode})${c.reset}  ${c.gray}⏱ ${elapsed}s${c.reset}`);
    }
    log(`  ${c.gray}${'─'.repeat(48)}${c.reset}`);
    log('');
    process.exit(exitCode);
  });

  child.on('error', (err) => {
    if (forceExitTimer) clearTimeout(forceExitTimer);
    cleanupEnvFile(envFile);
    if (err.code === 'ENOENT') {
      error('❌ Docker não encontrado no PATH.');
      error(`   Ou use: ${c.cyan}alpha-ci --no-docker ${command}${c.reset}`);
    } else {
      error(`❌ Erro ao executar Docker: ${err.message}`);
    }
    process.exit(1);
  });

  process.once('SIGINT', () => terminateFromSignal('SIGINT'));
  process.once('SIGTERM', () => terminateFromSignal('SIGTERM'));
}

run();
