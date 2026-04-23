# ╔══════════════════════════════════════════════════════════════╗
# ║  Alpha CI — Docker Image                                    ║
# ║  Replica o ambiente ubuntu-latest do GitHub Actions          ║
# ║  com todas as ferramentas de DevSecOps pré-instaladas        ║
# ╚══════════════════════════════════════════════════════════════╝

# ────────────────────────────────────────────────────────
# Stage 1: Builder — Baixa binários das security tools
# ────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tools

# Gitleaks — latest release
RUN URL=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
      | jq -r '.assets[] | select(.name | contains("linux_x64.tar.gz")) | .browser_download_url' \
      | head -n1) \
    && curl -L "$URL" -o gitleaks.tar.gz \
    && tar -xzf gitleaks.tar.gz gitleaks \
    && chmod +x gitleaks

# OSV-Scanner — latest release
RUN URL=$(curl -s https://api.github.com/repos/google/osv-scanner/releases/latest \
      | jq -r '.assets[] | select(.name | contains("linux_amd64") and (contains("exe") | not) and (contains("SHA256") | not)) | .browser_download_url' \
      | head -n1) \
    && curl -L "$URL" -o osv-scanner \
    && chmod +x osv-scanner

# golangci-lint — latest release
RUN URL=$(curl -s https://api.github.com/repos/golangci/golangci-lint/releases/latest \
      | jq -r '.assets[] | select(.name | contains("linux-amd64.tar.gz")) | .browser_download_url' \
      | head -n1) \
    && curl -L "$URL" -o golangci-lint.tar.gz \
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

# ── Node.js 20 LTS ──
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm \
    && rm -rf /var/lib/apt/lists/*

# ── Go (latest stable) ──
RUN GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -1) \
    && curl -L "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" -o go.tar.gz \
    && tar -C /usr/local -xzf go.tar.gz \
    && rm go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# ── Python tools (Semgrep + Ruff) ──
RUN pip install --break-system-packages --no-cache-dir \
    semgrep \
    ruff

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

WORKDIR /workspace

ENTRYPOINT ["/opt/alpha-ci/scripts/entrypoint.sh"]
CMD ["all"]
