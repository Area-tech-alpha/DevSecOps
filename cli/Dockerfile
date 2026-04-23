# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Docker Image                                    ║
# ║  Replica o ambiente ubuntu-latest do GitHub Actions          ║
# ║  com todas as ferramentas de DevSecOps pré-instaladas        ║
# ╚══════════════════════════════════════════════════════════════╝

# ────────────────────────────────────────────────────────
# Stage 1: Builder — Baixa binários das security tools
# SECURITY: Versões pinadas com SHA256 verification
# ────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tools

# ── Pinned versions ──
ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG OSV_SCANNER_VERSION=2.3.5
ARG OSV_SCANNER_SHA256=bb30c580afe5e757d3e959f4afd08a4795ea505ef84c46962b9a738aa573b41b
ARG GOLANGCI_LINT_VERSION=2.11.4
ARG GOLANGCI_LINT_SHA256=200c5b7503f67b59a6743ccf32133026c174e272b930ee79aa2aa6f37aca7ef1
ARG GO_VERSION=1.24.2

# Gitleaks — pinned version + SHA256 verification
RUN curl -L "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
      -o gitleaks.tar.gz \
    && echo "${GITLEAKS_SHA256}  gitleaks.tar.gz" | sha256sum -c - \
    && tar -xzf gitleaks.tar.gz gitleaks \
    && chmod +x gitleaks \
    && rm gitleaks.tar.gz

# OSV-Scanner — pinned version + SHA256 verification
RUN curl -L "https://github.com/google/osv-scanner/releases/download/v${OSV_SCANNER_VERSION}/osv-scanner_linux_amd64" \
      -o osv-scanner \
    && echo "${OSV_SCANNER_SHA256}  osv-scanner" | sha256sum -c - \
    && chmod +x osv-scanner

# golangci-lint — pinned version + SHA256 verification
RUN curl -L "https://github.com/golangci/golangci-lint/releases/download/v${GOLANGCI_LINT_VERSION}/golangci-lint-${GOLANGCI_LINT_VERSION}-linux-amd64.tar.gz" \
      -o golangci-lint.tar.gz \
    && echo "${GOLANGCI_LINT_SHA256}  golangci-lint.tar.gz" | sha256sum -c - \
    && mkdir golangci-lint-extract \
    && tar -xzf golangci-lint.tar.gz -C golangci-lint-extract --strip-components=1 \
    && mv golangci-lint-extract/golangci-lint . \
    && chmod +x golangci-lint \
    && rm -rf golangci-lint-extract golangci-lint.tar.gz


# ────────────────────────────────────────────────────────
# Stage 2: Runtime — Imagem final com tudo
# ────────────────────────────────────────────────────────
FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/Area-tech-alpha/DevSecOps"
LABEL org.opencontainers.image.description="Alpha CI — DevSecOps pipeline runner"
LABEL org.opencontainers.image.title="alpha-ci"

# Evita prompts interativos
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# ── System packages ──
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    jq \
    ca-certificates \
    gnupg \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 LTS (pinned via APT, no curl|bash) ──
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && npm install -g pnpm \
    && rm -rf /var/lib/apt/lists/*

# ── Go (pinned version) ──
ARG GO_VERSION=1.24.2
RUN curl -L "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o go.tar.gz \
    && tar -C /usr/local -xzf go.tar.gz \
    && rm go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# ── Python tools (Semgrep + Ruff) with pinned versions ──
RUN pip install --break-system-packages --no-cache-dir \
    'semgrep>=1.60,<2.0' \
    'ruff>=0.4,<1.0'

# ── Copy security tool binaries from builder ──
COPY --from=builder /tools/gitleaks /usr/local/bin/gitleaks
COPY --from=builder /tools/osv-scanner /usr/local/bin/osv-scanner
COPY --from=builder /tools/golangci-lint /usr/local/bin/golangci-lint

# ── Embed DevSecOps configs ──
# Build context = repo root (docker build -f cli/Dockerfile .)
COPY security/gitleaks.toml     /opt/alpha-ci/config/security/gitleaks.toml
COPY security/osv-scanner.toml  /opt/alpha-ci/config/security/osv-scanner.toml
COPY lint/eslint.config.mjs     /opt/alpha-ci/config/lint/eslint.config.mjs
COPY lint/.eslintignore         /opt/alpha-ci/config/lint/.eslintignore
COPY lint/.editorconfig         /opt/alpha-ci/config/lint/.editorconfig

# ── Install isolated ESLint 9 toolchain ──
RUN mkdir -p /opt/alpha-ci/config/lint \
    && cd /opt/alpha-ci/config/lint \
    && npm init -y \
    && npm install --no-save --legacy-peer-deps \
       eslint@9 \
       @eslint/js \
       typescript \
       typescript-eslint \
       eslint-config-prettier \
       globals \
    && npm cache clean --force

# ── Copy runner scripts ──
COPY cli/scripts/ /opt/alpha-ci/scripts/
RUN chmod +x /opt/alpha-ci/scripts/*.sh

# ── Security: Create non-root user ──
RUN useradd -m -s /bin/bash alpha-ci \
    && mkdir -p /home/alpha-ci/.npm /home/alpha-ci/.cache/pip /home/alpha-ci/.local/share/pnpm/store \
    && chown -R alpha-ci:alpha-ci /home/alpha-ci \
    && chown -R alpha-ci:alpha-ci /opt/alpha-ci \
    && chmod -R 755 /opt/alpha-ci/scripts

# ── Security: /workspace needs to be writable by the user ──
RUN mkdir -p /workspace && chown alpha-ci:alpha-ci /workspace

# ── Health check ──
HEALTHCHECK --interval=30s --timeout=5s --retries=1 \
  CMD gitleaks version || exit 1

USER alpha-ci
WORKDIR /workspace

ENTRYPOINT ["/opt/alpha-ci/scripts/entrypoint.sh"]
CMD ["all"]
