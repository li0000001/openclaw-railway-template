FROM node:24-bookworm

ENV FORCE_REBUILD=20260602-openclaw-dcdeploy-1

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    tini \
    build-essential \
    zip \
    unzip \
    jq \
    file \
    tar \
    gzip \
    xz-utils \
    openssh-client \
    bash \
    fonts-wqy-microhei \
    libjpeg-dev \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir python-pptx requests --break-system-packages

RUN npm install -g openclaw@2026.5.27 --unsafe-perm \
  && npm install -g clawhub@latest --unsafe-perm \
  && npm install -g pptxgenjs axios --unsafe-perm \
  && npm cache clean --force

# 修复 OpenClaw 入口文件兼容问题
RUN set -eux; \
    OPENCLAW_DIR="/usr/local/lib/node_modules/openclaw"; \
    DIST_DIR="${OPENCLAW_DIR}/dist"; \
    echo "OpenClaw directory:"; \
    ls -la "${OPENCLAW_DIR}" || true; \
    echo "OpenClaw dist directory:"; \
    ls -la "${DIST_DIR}" || true; \
    if [ ! -f "${DIST_DIR}/entry.js" ]; then \
      if [ -f "${DIST_DIR}/index.mjs" ]; then \
        echo "Creating compatibility entry.js from index.mjs"; \
        printf '%s\n' \
          '#!/usr/bin/env node' \
          'import("./index.mjs").catch((error) => {' \
          '  console.error(error);' \
          '  process.exit(1);' \
          '});' \
          > "${DIST_DIR}/entry.js"; \
        chmod +x "${DIST_DIR}/entry.js"; \
      else \
        echo "ERROR: OpenClaw entry.js not found, and dist/index.mjs not found either."; \
        find "${OPENCLAW_DIR}" -maxdepth 4 -type f | sort; \
        exit 1; \
      fi; \
    fi; \
    test -f "${DIST_DIR}/entry.js"; \
    node "${DIST_DIR}/entry.js" --version || true; \
    openclaw --version || true

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN corepack enable \
  && pnpm install --frozen-lockfile --prod

COPY src ./src
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

RUN useradd -m -s /bin/bash openclaw \
  && mkdir -p /data \
  && mkdir -p /data/.npm \
  && mkdir -p /data/.openclaw \
  && mkdir -p /data/workspace \
  && mkdir -p /home/linuxbrew/.linuxbrew \
  && chown -R openclaw:openclaw /app \
  && chown -R openclaw:openclaw /data \
  && chown -R openclaw:openclaw /home/linuxbrew \
  && chown -R openclaw:openclaw /usr/local/lib/node_modules

USER openclaw

RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV ENABLE_WEB_TUI=true
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV NPM_CONFIG_CACHE=/data/.npm
ENV HOME=/home/openclaw

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root

ENTRYPOINT ["tini", "--", "./entrypoint.sh"]
