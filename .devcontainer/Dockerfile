# syntax=docker/dockerfile:1.4
FROM mcr.microsoft.com/devcontainers/base:3.0.12-ubuntu24.04

ARG TARGETARCH
USER root

# ==============================================================================
# 0. Toolchain & Dependency Versions (Target: Android & iOS Flutter + Python Backend)
# ==============================================================================
ARG NODE_MAJOR="26"
ARG FLUTTER_CHANNEL="stable"
ARG ANDROID_CMDTOOLS_VERSION="16111833"
ARG SUPABASE_VERSION="2.101.0"
ARG DOCKER_MCP_VERSION="0.44.3"

# ==============================================================================
# 1. Native Dependencies & Toolchains (Single-Pass Repository & Package Setup)
# ==============================================================================
RUN install -m 0755 -d /etc/apt/keyrings \
    # NodeSource Repo (Node 26 LTS)
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && chmod 644 /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    # GitHub CLI Repo
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod 644 /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    # Docker CE CLI Repo
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod 644 /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
    # Single unified APT update & install
    && apt-get update && apt-get install -y --no-install-recommends \
    acl \
    adb \
    build-essential \
    ca-certificates \
    clang \
    cmake \
    direnv \
    docker-buildx-plugin \
    docker-ce-cli \
    docker-compose-plugin \
    fd-find \
    ffmpeg \
    gh \
    git \
    gnome-keyring \
    gnupg \
    iproute2 \
    iputils-ping \
    jq \
    lcov \
    libgl1 \
    libglib2.0-0 \
    libleptonica-dev \
    libtesseract-dev \
    net-tools \
    ninja-build \
    nodejs \
    openjdk-21-jdk-headless \
    pkg-config \
    poppler-utils \
    postgresql-client \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    redis-tools \
    ripgrep \
    shellcheck \
    socat \
    tesseract-ocr \
    tesseract-ocr-eng \
    unzip \
    wget \
    zlib1g \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Symlink python3 to python/pip
RUN ln -sf /usr/bin/python3 /usr/local/bin/python \
    && ln -sf /usr/bin/pip3 /usr/local/bin/pip

# Install Astral uv for ultra-fast, modern Python package & environment management
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh

# Install Global CLI tools via npm
RUN npm install -g firebase-tools @infisical/cli ui-ux-pro-max-cli

# Install Sentry CLI, docker-mcp CLI plugin & Redis MCP server via uv
RUN ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && case "${ARCH}" in \
      amd64) DOCKER_MCP_ARCH="linux-amd64";; \
      arm64) DOCKER_MCP_ARCH="linux-arm64";; \
      *) DOCKER_MCP_ARCH="linux-amd64";; \
    esac \
    && mkdir -p /usr/libexec/docker/cli-plugins \
    && curl -fsSL "https://github.com/docker/mcp-gateway/releases/download/v${DOCKER_MCP_VERSION}/docker-mcp-${DOCKER_MCP_ARCH}.tar.gz" | tar -xz -C /usr/libexec/docker/cli-plugins \
    && chmod 755 /usr/libexec/docker/cli-plugins/docker-mcp \
    && curl -fsSL https://cli.sentry.dev/install | bash \
    && env UV_TOOL_DIR="/usr/local/share/uv-tools" UV_TOOL_BIN_DIR="/usr/local/bin" uv tool install --force redis-mcp-server

# ==============================================================================
# 2. Multi-Arch Precompiled Binaries: Supabase CLI & GitHub MCP Server
# ==============================================================================
RUN ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && case "${ARCH}" in \
      amd64) SUPA_ARCH="linux_amd64"; GITHUB_MCP_ARCH="Linux_x86_64";; \
      arm64) SUPA_ARCH="linux_arm64"; GITHUB_MCP_ARCH="Linux_arm64";; \
      *) echo "Unsupported target architecture: ${ARCH}" && exit 1;; \
    esac \
    # Supabase CLI (dynamic latest release with pinned fallback)
    && SUPABASE_URL=$(curl -fsSL https://api.github.com/repos/supabase/cli/releases/latest 2>/dev/null | jq -r --arg arch "${SUPA_ARCH}.tar.gz" '.assets[] | select(.name | contains($arch)) | .browser_download_url' | head -n 1) \
    && if [ -z "$SUPABASE_URL" ] || [ "$SUPABASE_URL" = "null" ]; then \
         SUPABASE_URL="https://github.com/supabase/cli/releases/download/v${SUPABASE_VERSION}/supabase_${SUPA_ARCH}.tar.gz"; \
       fi \
    && curl -fSL "${SUPABASE_URL}" -o /tmp/supabase.tar.gz \
    && tar -xzf /tmp/supabase.tar.gz -C /usr/local/bin supabase && rm -f /tmp/supabase.tar.gz && chmod 755 /usr/local/bin/supabase \
    # Precompiled github-mcp-server binary (no Go SDK required)
    && GITHUB_MCP_URL=$(curl -fsSL https://api.github.com/repos/github/github-mcp-server/releases/latest 2>/dev/null | jq -r --arg arch "${GITHUB_MCP_ARCH}.tar.gz" '.assets[] | select(.name | contains($arch)) | .browser_download_url' | head -n 1) \
    && if [ -n "$GITHUB_MCP_URL" ] && [ "$GITHUB_MCP_URL" != "null" ]; then \
         curl -fSL "${GITHUB_MCP_URL}" -o /tmp/github-mcp.tar.gz \
         && tar -xzf /tmp/github-mcp.tar.gz -C /usr/local/bin github-mcp-server 2>/dev/null || true \
         && if [ -f /usr/local/bin/github-mcp-server ]; then mv /usr/local/bin/github-mcp-server /usr/local/bin/github-mcp-server-bin; fi \
         && rm -f /tmp/github-mcp.tar.gz; \
       fi

# ==============================================================================
# 3. Directories Pre-Creation & Environment
# ==============================================================================
ENV ANDROID_HOME="/opt/android-sdk"
ENV FLUTTER_HOME="/opt/flutter"
ENV HOME="/home/vscode"
ENV PUB_CACHE="$HOME/.pub-cache"
ENV NODE_OPTIONS="--max-old-space-size=9216"
ENV SUPABASE_SERVICES_HOSTNAME="host.docker.internal"
ENV PYTHONUNBUFFERED="1"
ENV PYTHONDONTWRITEBYTECODE="1"
ENV UV_LINK_MODE="copy"
ENV PATH="$PATH:${FLUTTER_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PUB_CACHE}/bin:$HOME/.local/bin"

# Pre-create SDK and volume target dirs with vscode ownership ONCE
RUN mkdir -p ${ANDROID_HOME} \
             ${FLUTTER_HOME} \
             /home/vscode/.pub-cache \
             /home/vscode/.gradle \
             /home/vscode/.npm \
             /home/vscode/.cache \
             /home/vscode/.ssh \
             /workspaces/Spliqo/spliqo_client/.dart_tool \
             /workspaces/Spliqo/spliqo_client/build \
    && touch /home/vscode/.sudo_as_admin_successful /home/vscode/.hushlogin \
    && (groupadd -g 992 host-docker-992 2>/dev/null || true) \
    && chown -R vscode:vscode ${ANDROID_HOME} ${FLUTTER_HOME} /home/vscode /workspaces \
    && chmod -R 775 /workspaces/Spliqo \
    && ln -sf /workspaces/Spliqo /spliqo

# ==============================================================================
# 4. Non-Root Toolchain Setup (Target: Android & iOS Flutter)
# ==============================================================================
USER vscode

# Android SDK Tools (Android 36 + 35 + 34, BuildTools 36.1.0, 36.0.0, 35.0.0, 34.0.0, 28.0.3)
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && wget -q "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDTOOLS_VERSION}_latest.zip" -O /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp \
    && mv /tmp/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm -f /tmp/cmdline-tools.zip \
    && yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 || true \
    && ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager \
        "platform-tools" \
        "platforms;android-36" \
        "platforms;android-35" \
        "platforms;android-34" \
        "build-tools;36.1.0" \
        "build-tools;36.0.0" \
        "build-tools;35.0.0" \
        "build-tools;34.0.0" \
        "build-tools;28.0.3" >/dev/null \
    && yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 || true

# Flutter SDK (Configured specifically for Mobile: Android & iOS)
RUN git config --global --add safe.directory ${FLUTTER_HOME} \
    && git clone --depth 1 -b ${FLUTTER_CHANNEL} https://github.com/flutter/flutter.git ${FLUTTER_HOME} \
    && flutter config --no-analytics >/dev/null 2>&1 \
    && flutter config --no-enable-linux-desktop >/dev/null 2>&1 \
    && flutter config --no-enable-macos-desktop >/dev/null 2>&1 \
    && flutter config --no-enable-windows-desktop >/dev/null 2>&1 \
    && flutter config --no-enable-web >/dev/null 2>&1 \
    && flutter config --android-sdk "${ANDROID_HOME}" >/dev/null 2>&1 \
    && flutter precache --android >/dev/null 2>&1 || true \
    && yes | flutter doctor --android-licenses >/dev/null 2>&1 || true

# ==============================================================================
# 5. Multi-IDE Machine Settings & Extension Symlinks
# ==============================================================================
RUN for dir in .antigravity-server .antigravity-ide-server .vscode-server .cursor-server; do \
      mkdir -p "$HOME/$dir/data/Machine"; \
    done \
    && ln -sf $HOME/.vscode-server/extensions $HOME/.antigravity-server/extensions \
    && ln -sf $HOME/.vscode-server/extensions $HOME/.antigravity-ide-server/extensions \
    && ln -sf $HOME/.vscode-server/extensions $HOME/.cursor-server/extensions \
    && SETTINGS='{ \
        "remote.forwardAgent": true, \
        "python.defaultInterpreterPath": "/workspaces/Spliqo/.venv/bin/python", \
        "python.analysis.diagnosticMode": "workspace", \
        "python.analysis.typeCheckingMode": "strict", \
        "python.analysis.inlayHints.variableTypes": true, \
        "python.analysis.inlayHints.functionReturnTypes": true, \
        "python.analysis.diagnosticSeverityOverrides": { \
            "reportMissingTypeStubs": "none", \
            "reportUnknownMemberType": "none", \
            "reportUnknownVariableType": "none", \
            "reportUnknownArgumentType": "none", \
            "reportUnknownReturnType": "none", \
            "reportUnusedImport": "error", \
            "reportUnusedVariable": "error", \
            "reportDuplicateImport": "error", \
            "reportPrivateUsage": "none" \
        }, \
        "ruff.enable": true, \
        "ruff.organizeImports": true, \
        "ruff.fixAll": true, \
        "dart.flutterSdkPath": "/opt/flutter", \
        "editor.formatOnSave": true, \
        "editor.defaultFormatter": "esbenp.prettier-vscode", \
        "[python]": { \
            "editor.defaultFormatter": "charliermarsh.ruff", \
            "editor.formatOnSave": true, \
            "editor.codeActionsOnSave": { \
                "source.fixAll": "explicit", \
                "source.organizeImports": "explicit" \
            } \
        }, \
        "[dart]": { \
            "editor.defaultFormatter": "Dart-Code.dart-code", \
            "editor.formatOnSave": true, \
            "editor.codeActionsOnSave": { \
                "source.fixAll": "explicit", \
                "source.organizeImports": "explicit" \
            } \
        }, \
        "[json]": { \
            "editor.defaultFormatter": "esbenp.prettier-vscode" \
        }, \
        "[jsonc]": { \
            "editor.defaultFormatter": "esbenp.prettier-vscode" \
        }, \
        "[markdown]": { \
            "editor.defaultFormatter": "esbenp.prettier-vscode" \
        }, \
        "[yaml]": { \
            "editor.defaultFormatter": "esbenp.prettier-vscode" \
        }, \
        "[toml]": { \
            "editor.defaultFormatter": "tamasfe.even-better-toml" \
        } \
    }' \
    && echo "$SETTINGS" > $HOME/.antigravity-server/data/Machine/settings.json \
    && echo "$SETTINGS" > $HOME/.antigravity-ide-server/data/Machine/settings.json \
    && echo "$SETTINGS" > $HOME/.vscode-server/data/Machine/settings.json \
    && echo "$SETTINGS" > $HOME/.cursor-server/data/Machine/settings.json \
    && mkdir -p $HOME/.gemini/config $HOME/.gemini/antigravity $HOME/.config/Claude $HOME/.cursor \
    && MCP_CONFIG='{ \
        "mcpServers": { \
            "dart": { \
                "command": "dart", \
                "args": ["mcp-server"] \
            }, \
            "github": { \
                "command": "github-mcp-server", \
                "args": ["stdio"] \
            }, \
            "MCP_DOCKER": { \
                "command": "docker", \
                "args": ["mcp", "gateway", "run"] \
            }, \
            "context7": { \
                "type": "http", \
                "url": "https://mcp.context7.com/mcp", \
                "serverUrl": "https://mcp.context7.com/mcp" \
            }, \
            "sentry": { \
                "command": "sentry", \
                "args": ["mcp"] \
            }, \
            "redis": { \
                "command": "redis-mcp-server", \
                "args": ["--url", "redis://localhost:6379/0"] \
            }, \
            "cloudflare": { \
                "type": "http", \
                "url": "https://mcp.cloudflare.com/mcp", \
                "serverUrl": "https://mcp.cloudflare.com/mcp" \
            } \
        } \
    }' \
    && echo "$MCP_CONFIG" > $HOME/.gemini/config/mcp_config.json \
    && echo "$MCP_CONFIG" > $HOME/.gemini/antigravity/mcp_config.json \
    && echo "$MCP_CONFIG" > $HOME/.config/Claude/claude_desktop_config.json \
    && echo "$MCP_CONFIG" > $HOME/.cursor/mcp.json

# ==============================================================================
# 6. Companion Scripts & Launchers Installation
# ==============================================================================
USER root
COPY --chown=vscode:vscode --chmod=755 .devcontainer/init_workspace.sh /home/vscode/init_workspace.sh
COPY --chown=root:root --chmod=755 .devcontainer/supabase-proxy.sh /usr/local/bin/supabase-proxy
COPY --chown=root:root --chmod=755 .devcontainer/github-mcp-server.sh /usr/local/bin/github-mcp-server
RUN sed -i 's/\r$//' /home/vscode/init_workspace.sh /usr/local/bin/supabase-proxy /usr/local/bin/github-mcp-server

# ==============================================================================
# 7. Runtime Defaults & Entrypoint (Android & iOS Flutter + FastAPI Ports)
# ==============================================================================
USER vscode
WORKDIR /workspaces/Spliqo
EXPOSE 8000 8181
CMD ["sleep", "infinity"]
