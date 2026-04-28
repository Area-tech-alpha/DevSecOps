#!/usr/bin/env node
// ╔══════════════════════════════════════════════════════════════╗
// ║  Alpha CI — NPM CLI Wrapper                                  ║
// ║  Wrapper Node.js que orquestra o Docker container             ║
// ║  Permite: npx @area-tech-alpha/alpha-ci security             ║
// ╚══════════════════════════════════════════════════════════════╝

import { execFileSync, spawn } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, unlinkSync, realpathSync, copyFileSync, mkdirSync, chmodSync } from 'node:fs';
import { resolve, basename, dirname } from 'node:path';
import { tmpdir } from 'node:os';

const IMAGE = 'ghcr.io/area-tech-alpha/alpha-ci:latest';
const IMAGE_LOCAL = 'alpha-ci:latest';
const VERSION = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf-8')).version;

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
  bold: '\x1b[1m', dim: '\x1b[2m', reset: '\x1b[0m',
};

/* eslint-disable no-console -- CLI tool: console is the primary output interface */
const log = (msg) => console.log(msg);
const error = (msg) => console.error(`${c.red}${msg}${c.reset}`);
const info = (msg) => console.log(`${c.cyan}${msg}${c.reset}`);
/* eslint-enable no-console */

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
${c.magenta}${c.bold}  ╔═══════════════════════════════════════════════╗
  ║     🛡️  Alpha CI — DevSecOps Pipeline         ║
  ║     Area Tech Alpha · Local Runner            ║
  ╚═══════════════════════════════════════════════╝${c.reset}

  ${c.dim}v${VERSION}${c.reset}

${c.bold}Usage:${c.reset} alpha-ci <command> [options]

${c.bold}Commands:${c.reset}
  ${c.cyan}all${c.reset}         Pipeline completo (security → lint → test → build)
  ${c.cyan}security${c.reset}    Scanners de segurança (Gitleaks + OSV + Semgrep)
  ${c.cyan}lint${c.reset}        Linting (ESLint / Ruff / golangci-lint)
  ${c.cyan}test${c.reset}        Testes unitários (Jest/Vitest/pytest/go test)
  ${c.cyan}build${c.reset}       Build do projeto
  ${c.cyan}e2e${c.reset}         Testes E2E (Playwright / Cypress)
  ${c.cyan}shell${c.reset}       Shell interativo no container
  ${c.cyan}detect${c.reset}      Apenas detecta o tipo de projeto

${c.bold}Options:${c.reset}
  ${c.yellow}-p, --path <dir>${c.reset}          Repositório alvo (default: pwd)
  ${c.yellow}-v, --verbose${c.reset}             Output detalhado
  ${c.yellow}--no-docker${c.reset}               Roda sem Docker (requer tools instaladas)
  ${c.yellow}--fix${c.reset}                     Auto-fix problemas de lint
  ${c.yellow}--format <json|sarif|text>${c.reset} Formato do output (default: text)
  ${c.yellow}--output <file>${c.reset}            Salva relatório em arquivo
  ${c.yellow}--rebuild${c.reset}                 Força rebuild da imagem Docker
  ${c.yellow}--version${c.reset}                 Mostra a versão

${c.bold}Examples:${c.reset}
  ${c.dim}# Scan de segurança no repo atual${c.reset}
  alpha-ci security

  ${c.dim}# Pipeline completo em outro repo${c.reset}
  alpha-ci all --path ../meu-projeto

  ${c.dim}# Lint com auto-fix${c.reset}
  alpha-ci lint --fix

  ${c.dim}# Security scan com output JSON${c.reset}
  alpha-ci security --format json --output report.json

  ${c.dim}# Rodar sem Docker${c.reset}
  alpha-ci security --no-docker

  ${c.dim}# Shell interativo para debug${c.reset}
  alpha-ci shell

${c.bold}Environment:${c.reset}
  ${c.dim}GITHUB_TOKEN${c.reset}        GitHub PAT para packages privados
  ${c.dim}SEMGREP_APP_TOKEN${c.reset}   Token do Semgrep para regras custom
  ${c.dim}NODE_AUTH_TOKEN${c.reset}      Alias para GITHUB_TOKEN
`);
  process.exit(0);
}

// ── Validate target path ──
if (!existsSync(targetPath)) {
  error(`❌ Diretório não encontrado: ${targetPath}`);
  process.exit(1);
}

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
(function installHookOnHost() {
  try {
    const auto = process.env.ALPHA_CI_AUTO_INSTALL_HOOK;
    if (auto === 'false' || auto === '0') return;

    const hostGitDir = existsSync(resolve(targetPath, '.git')) ? resolve(targetPath, '.git') : null;
    if (!hostGitDir) return;

    const tpl = resolve(import.meta.dirname, '../hooks/pre-push-template');
    const fallbackTpl = resolve(process.cwd(), 'cli/hooks/pre-push-template');

    let src = null;
    if (existsSync(tpl)) src = tpl;
    else if (existsSync(fallbackTpl)) src = fallbackTpl;
    else return;

    const hooksDir = resolve(hostGitDir, 'hooks');
    if (!existsSync(hooksDir)) mkdirSync(hooksDir, { recursive: true });

    const dest = resolve(hooksDir, 'pre-push');

    if (existsSync(dest)) {
      const content = readFileSync(dest, 'utf-8');
      // If our marker is there AND shebang is at line 1, we are good.
      if (content.includes('ALPHA-CI-HOOK') && content.startsWith('#!')) return;
      try { copyFileSync(dest, `${dest}.alpha-ci.bak`); } catch (e) {}
    }

    copyFileSync(src, dest);
    const marker = '# ALPHA-CI-HOOK: installed by alpha-ci\n';
    let content = readFileSync(dest, 'utf-8');
    if (content.startsWith('#!')) {
      const lines = content.split('\n');
      lines.splice(1, 0, marker.trim());
      content = lines.join('\n');
    } else {
      content = marker + content;
    }
    writeFileSync(dest, content, { mode: 0o755 });
    chmodSync(dest, 0o755);
    info(`🔧 Installed pre-push hook at ${dest}`);
  } catch (e) {
    // Silent fail unless verbose (validation path might be sensitive)
  }
})();

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
  } catch { return false; }
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
    resolve(import.meta.dirname, '..'),
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

// ── No-Docker Mode ──
function runNoDocker() {
  const cliDir = findCliDir();
  const scriptsDir = cliDir ? resolve(cliDir, 'scripts') : null;

  // Try to find run-local.sh
  let localRunner = null;
  const candidates = [
    scriptsDir ? resolve(scriptsDir, 'run-local.sh') : null,
    resolve(import.meta.dirname, '..', 'scripts', 'run-local.sh'),
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
  info(`🎯 Target: ${repoName} (${targetPath})`);
  info(`🚀 Command: ${command} (no-docker)`);
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

  child.on('close', (code) => process.exit(code || 0));
  child.on('error', (err) => {
    error(`❌ Erro ao executar: ${err.message}`);
    process.exit(1);
  });
}

// ── Check for NPM Updates ──
async function checkForUpdates() {
  try {
    // Silent check: get latest version from registry
    const latest = execFileSync('npm', ['view', '@area-tech-alpha/alpha-ci', 'version'], { 
      encoding: 'utf-8', 
      timeout: 2000,
      env: { ...process.env, NPM_CONFIG_USERCONFIG: GLOBAL_NPMRC }
    }).trim();

    if (latest && latest !== VERSION) {
      log(`${c.yellow}${c.bold}🔔 Nova versão disponível: ${latest} (atual: ${VERSION})${c.reset}`);
      log(`${c.dim}   Execute: npm install -g @area-tech-alpha/alpha-ci${c.reset}\n`);
    }
  } catch (e) {
    // Ignore update check failures (offline/timeout)
  }
}

// ── Run ──
async function run() {
  // Check for updates in the background (don't block start)
  if (!args.includes('--version')) {
    checkForUpdates();
  }

  // --no-docker mode
  if (noDocker) {
    return runNoDocker();
  }

  if (!dockerAvailable()) {
    error('❌ Docker não está disponível.');
    error('   Instale: https://docs.docker.com/get-docker/');
    error('   Ou use: alpha-ci --no-docker <command>');
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
      try {
        log(`${c.dim}ℹ️  Verificando atualizações da imagem Docker...${c.reset}`);
        execFileSync('docker', ['pull', IMAGE], { stdio: 'ignore', timeout: 15000 });
      } catch (e) {
        // Ignora erro (offline, timeout ou interrupção) e usa cache
      }
    }
  }

  const repoName = basename(targetPath);
  info(`🎯 Target: ${repoName} (${targetPath})`);
  info(`🐳 Image: ${image}`);
  info(`🚀 Command: ${command}`);
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

  child.on('close', (code) => {
    cleanupEnvFile(envFile);
    process.exit(code || 0);
  });

  child.on('error', (err) => {
    cleanupEnvFile(envFile);
    error(`❌ Erro ao executar Docker: ${err.message}`);
    process.exit(1);
  });

  // Cleanup on unexpected exit
  process.on('SIGINT', () => cleanupEnvFile(envFile));
  process.on('SIGTERM', () => cleanupEnvFile(envFile));
}

run();
