#!/usr/bin/env node
// ╔══════════════════════════════════════════════════════════════╗
// ║  Alpha CI — NPM CLI Wrapper                                  ║
// ║  Wrapper Node.js que orquestra o Docker container             ║
// ║  Permite: npx @area-tech-alpha/alpha-ci security             ║
// ╚══════════════════════════════════════════════════════════════╝

import { execSync, spawn } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve, basename } from 'node:path';

const IMAGE = 'ghcr.io/area-tech-alpha/alpha-ci:latest';
const IMAGE_LOCAL = 'alpha-ci:latest';
const VERSION = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf-8')).version;

// ── Colors ──
const c = {
  red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m',
  blue: '\x1b[34m', cyan: '\x1b[36m', magenta: '\x1b[35m',
  bold: '\x1b[1m', dim: '\x1b[2m', reset: '\x1b[0m',
};

const log = (msg) => console.log(msg);
const error = (msg) => console.error(`${c.red}${msg}${c.reset}`);
const info = (msg) => console.log(`${c.cyan}${msg}${c.reset}`);

// ── Parse args ──
const args = process.argv.slice(2);
const command = args[0] || 'help';

// Extract options
let targetPath = process.cwd();
let verbose = false;
let rebuild = false;
let noDocker = false;
let autoFix = false;
let reportFormat = 'text';
let reportOutput = '';
let semgrepToken = process.env.SEMGREP_APP_TOKEN || '';
let githubToken = process.env.GITHUB_TOKEN || process.env.NODE_AUTH_TOKEN || '';

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
    case '--format':
      reportFormat = args[++i] || 'text';
      break;
    case '--output':
      reportOutput = args[++i] || '';
      break;
    case '--semgrep-token':
      semgrepToken = args[++i] || '';
      break;
    case '--github-token':
      githubToken = args[++i] || '';
      break;
    case '--version':
      log(`alpha-ci v${VERSION}`);
      process.exit(0);
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
  ${c.yellow}--semgrep-token <token>${c.reset}   Token do Semgrep (opcional)
  ${c.yellow}--github-token <token>${c.reset}    GitHub PAT (para packages privados)
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

// ── Check Docker ──
function dockerAvailable() {
  try {
    execSync('docker info', { stdio: 'ignore' });
    return true;
  } catch { return false; }
}

function imageExists(img) {
  try {
    execSync(`docker image inspect ${img}`, { stdio: 'ignore' });
    return true;
  } catch { return false; }
}

function pullOrBuild() {
  // Try pulling from GHCR first
  info('📦 Puxando imagem Docker...');
  try {
    execSync(`docker pull ${IMAGE}`, { stdio: 'inherit' });
    return IMAGE;
  } catch {
    log(`${c.dim}  GHCR indisponível, tentando build local...${c.reset}`);
  }

  // Fallback: build local if Dockerfile exists in DevSecOps repo
  const cliDir = findCliDir();
  if (cliDir && existsSync(`${cliDir}/Dockerfile`)) {
    info('🏗 Construindo imagem local...');
    execSync(`docker build -t ${IMAGE_LOCAL} -f ${cliDir}/Dockerfile ${cliDir}/..`, {
      stdio: 'inherit',
    });
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

// ── Run ──
async function run() {
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
  }

  const repoName = basename(targetPath);
  info(`🎯 Target: ${repoName} (${targetPath})`);
  info(`🐳 Image: ${image}`);
  info(`🚀 Command: ${command}`);
  log('');

  // Build docker run args
  const dockerArgs = [
    'run', '--rm',
    '-v', `${targetPath}:/workspace`,
    // Cache volumes (persist between runs)
    '-v', 'alpha-ci-npm-cache:/root/.npm',
    '-v', 'alpha-ci-pip-cache:/root/.cache/pip',
    '-v', 'alpha-ci-pnpm-cache:/root/.local/share/pnpm/store',
    // Environment
    '-e', `SEMGREP_APP_TOKEN=${semgrepToken}`,
    '-e', `GITHUB_TOKEN=${githubToken}`,
    '-e', `NODE_AUTH_TOKEN=${githubToken}`,
    '-e', `AUTO_FIX=${autoFix ? 'true' : 'false'}`,
    '-e', `REPORT_FORMAT=${reportFormat}`,
    '-e', `REPORT_OUTPUT=${reportOutput}`,
  ];

  // Interactive mode for shell
  if (command === 'shell') {
    dockerArgs.push('-it');
  }

  // Verbose
  if (verbose) {
    dockerArgs.push('-e', 'VERBOSE=true');
  }

  // Report output: mount the output dir so the file is accessible from host
  if (reportOutput) {
    const outputDir = resolve(targetPath, reportOutput, '..');
    dockerArgs.push('-v', `${outputDir}:/output`);
    dockerArgs.push('-e', `REPORT_OUTPUT=/output/${basename(reportOutput)}`);
  }

  dockerArgs.push(image, command);

  // Spawn docker
  const child = spawn('docker', dockerArgs, {
    stdio: 'inherit',
    env: { ...process.env },
  });

  child.on('close', (code) => {
    process.exit(code || 0);
  });

  child.on('error', (err) => {
    error(`❌ Erro ao executar Docker: ${err.message}`);
    process.exit(1);
  });
}

run();
