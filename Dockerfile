FROM node:24-bookworm

ENV FORCE_REBUILD=20260602-dcdeploy-linux-full-1

# 1. 基础 Linux 系统环境
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    gosu \
    sudo \
    procps \
    psmisc \
    tini \
    bash \
    zsh \
    nano \
    vim-tiny \
    jq \
    file \
    tar \
    gzip \
    xz-utils \
    zip \
    unzip \
    openssh-client \
    build-essential \
    pkg-config \
    make \
    g++ \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    fonts-wqy-microhei \
    fonts-liberation \
    libjpeg-dev \
    zlib1g-dev \
    libpng-dev \
    libnss3 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libxss1 \
    libasound2 \
    libgbm1 \
    chromium \
  && rm -rf /var/lib/apt/lists/*

# 2. Python 常用依赖
RUN pip3 install --no-cache-dir --break-system-packages \
    requests \
    python-pptx \
    pillow \
    pandas \
    openpyxl

# 3. 全局 npm 环境
ENV NPM_CONFIG_PREFIX=/usr/local
ENV NPM_CONFIG_CACHE=/data/.npm
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/bin

# 4. 安装 OpenClaw / ClawHub / PPT 依赖
RUN npm install -g openclaw@2026.5.27 --unsafe-perm \
  && npm install -g clawhub@latest --unsafe-perm \
  && npm install -g pptxgenjs axios playwright --unsafe-perm \
  && npm cache clean --force

# 5. 修复 OpenClaw 某些版本缺少 dist/entry.js 的问题
RUN set -eux; \
    OPENCLAW_DIR="/usr/local/lib/node_modules/openclaw"; \
    DIST_DIR="${OPENCLAW_DIR}/dist"; \
    mkdir -p "${DIST_DIR}"; \
    echo "OpenClaw package files:"; \
    find "${OPENCLAW_DIR}" -maxdepth 3 -type f | sort || true; \
    if [ ! -f "${DIST_DIR}/entry.js" ]; then \
      if [ -f "${DIST_DIR}/index.mjs" ]; then \
        echo "Creating compatibility entry.js -> index.mjs"; \
        printf '%s\n' \
          '#!/usr/bin/env node' \
          'import("./index.mjs").catch((error) => {' \
          '  console.error(error);' \
          '  process.exit(1);' \
          '});' \
          > "${DIST_DIR}/entry.js"; \
      elif [ -f "${OPENCLAW_DIR}/openclaw.mjs" ]; then \
        echo "Creating compatibility entry.js -> openclaw.mjs"; \
        printf '%s\n' \
          '#!/usr/bin/env node' \
          'import("../openclaw.mjs").catch((error) => {' \
          '  console.error(error);' \
          '  process.exit(1);' \
          '});' \
          > "${DIST_DIR}/entry.js"; \
      else \
        echo "ERROR: Cannot find a usable OpenClaw entry file."; \
        find "${OPENCLAW_DIR}" -maxdepth 5 -type f | sort; \
        exit 1; \
      fi; \
    fi; \
    chmod +x "${DIST_DIR}/entry.js"; \
    test -f "${DIST_DIR}/entry.js"; \
    node "${DIST_DIR}/entry.js" --version || true; \
    openclaw --version || true

WORKDIR /app

# 6. 安装 openclaw-railway-template 自身依赖
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

RUN corepack enable \
  && pnpm install --frozen-lockfile --prod

# 7. 复制模板源码
COPY src ./src
COPY --chmod=755 entrypoint.sh ./entrypoint.sh

# 8. 创建运行用户和目录
RUN useradd -m -s /bin/bash openclaw \
  && mkdir -p /data \
  && mkdir -p /data/.npm \
  && mkdir -p /data/.openclaw \
  && mkdir -p /data/workspace \
  && mkdir -p /home/openclaw \
  && mkdir -p /home/linuxbrew/.linuxbrew \
  && chown -R openclaw:openclaw /app \
  && chown -R openclaw:openclaw /data \
  && chown -R openclaw:openclaw /home/openclaw \
  && chown -R openclaw:openclaw /home/linuxbrew \
  && chown -R openclaw:openclaw /usr/local/lib/node_modules \
  && chmod -R u+rwX,g+rwX /data /home/openclaw

# 9. 安装 Linuxbrew
# 如果 DCDeploy 构建阶段访问 GitHub raw 失败，这一步不阻断构建。
USER openclaw

RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true

# 10. 运行环境变量
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
ENV ENABLE_WEB_TUI=true
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js
ENV OPENCLAW_STATE_DIR=/data/.openclaw
ENV OPENCLAW_WORKSPACE_DIR=/data/workspace
ENV HOME=/home/openclaw

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

USER root

ENTRYPOINT ["tini", "--", "./entrypoint.sh"]
