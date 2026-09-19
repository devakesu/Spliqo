# syntax=docker/dockerfile:1.4
FROM mcr.microsoft.com/devcontainers/base:2.1.7-ubuntu24.04

ARG TARGETARCH
USER root

# ==============================================================================
# 0. Pinned Toolchain & Dependency Versions
# ==============================================================================
ARG NODE_MAJOR="24"
ARG FIREBASE_TOOLS_VERSION="15.26.0"
ARG INFISICAL_CLI_VERSION="0.43.128"
ARG SUPABASE_VERSION="2.101.0"
ARG FLUTTER_VERSION="3.47.4"
ARG ANDROID_CMDTOOLS_VERSION="11076708"
ARG UV_VERSION="0.6.5"

# ==============================================================================
# 1. Native Dependencies & Toolchains (Single-Pass Repository & Package Setup)
# ==============================================================================
RUN install -m 0755 -d /etc/apt/keyrings \
    # NodeSource Repo (Node 24 LTS)
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
    curl \
    docker-buildx-plugin \
    docker-ce-cli \
    docker-compose-plugin \
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
RUN curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | env UV_INSTALL_DIR="/usr/local/bin" sh

# Install Pinned Global CLI tools via npm
RUN npm install -g "firebase-tools@${FIREBASE_TOOLS_VERSION}" "@infisical/cli@${INFISICAL_CLI_VERSION}"

# ==============================================================================
# 2. Multi-Arch Pinned Supabase CLI Installation
# ==============================================================================
RUN case "${TARGETARCH}" in \
      amd64) SUPA_ARCH="linux_amd64";; \
      arm64) SUPA_ARCH="linux_arm64";; \
      *) echo "Unsupported target architecture: ${TARGETARCH}" && exit 1;; \
    esac \
    && curl -fsSL "https://github.com/supabase/cli/releases/download/v${SUPABASE_VERSION}/supabase_${SUPA_ARCH}.tar.gz" -o /tmp/supabase.tar.gz \
    && tar -xzf /tmp/supabase.tar.gz -C /usr/local/bin supabase \
    && rm -f /tmp/supabase.tar.gz \
    && chmod 755 /usr/local/bin/supabase

# ==============================================================================
# 3. Directories Pre-Creation & Environment
# ==============================================================================
ENV ANDROID_HOME="/opt/android-sdk"
ENV FLUTTER_HOME="/opt/flutter"
ENV HOME="/home/vscode"
ENV PUB_CACHE="$HOME/.pub-cache"
ENV SUPABASE_SERVICES_HOSTNAME="host.docker.internal"
ENV PATH="$PATH:${FLUTTER_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PUB_CACHE}/bin:$HOME/.local/bin"

# Pre-create SDK and volume target dirs with vscode ownership ONCE.
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
# 4. Non-Root Toolchain Setup (Headless Android & Flutter for Android/iOS)
# ==============================================================================
USER vscode

# Android SDK Tools (Pinned Android Commandline Tools, SDK 34 & 36, BuildTools 34.0.0 & 36.0.0)
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && wget -q "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDTOOLS_VERSION}_latest.zip" -O /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp \
    && mv /tmp/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm -f /tmp/cmdline-tools.zip \
    && yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 || true \
    && ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager \
        "platform-tools" \
        "platforms;android-36" \
        "platforms;android-34" \
        "build-tools;36.0.0" \
        "build-tools;34.0.0" >/dev/null \
    && yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 || true

# Flutter SDK (Pinned release tag directly as user vscode - Android precache only, no Linux desktop)
RUN git config --global --add safe.directory ${FLUTTER_HOME} \
    && git clone --depth 1 -b ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_HOME} \
    && flutter config --no-analytics >/dev/null 2>&1 \
    && flutter config --android-sdk "${ANDROID_HOME}" >/dev/null 2>&1 \
    && flutter precache --android >/dev/null 2>&1 || true

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
            "editor.formatOnSave": true, \
            "editor.codeActionsOnSave": { \
                "source.fixAll": "explicit", \
                "source.organizeImports": "explicit" \
            } \
        }, \
        "[dart]": { \
            "editor.defaultFormatter": "Dart-Code.dart-code", \
            "editor.formatOnSave": true \
        } \
    }' \
    && echo "$SETTINGS" > $HOME/.antigravity-server/data/Machine/settings.json \
    && echo "$SETTINGS" > $HOME/.antigravity-ide-server/data/Machine/settings.json \
    && echo "$SETTINGS" > $HOME/.vscode-server/data/Machine/settings.json \
    && echo "$SETTINGS" > $HOME/.cursor-server/data/Machine/settings.json

# ==============================================================================
# 6. Companion Scripts Installation
# ==============================================================================
USER root
COPY --chown=vscode:vscode --chmod=755 .devcontainer/init_workspace.sh /home/vscode/init_workspace.sh
COPY --chown=root:root --chmod=755 .devcontainer/supabase-proxy.sh /usr/local/bin/supabase-proxy
RUN sed -i 's/\r$//' /home/vscode/init_workspace.sh /usr/local/bin/supabase-proxy

# ==============================================================================
# 7. Runtime Defaults & Entrypoint
# ==============================================================================
USER vscode
WORKDIR /workspaces/Spliqo
EXPOSE 8000 8181
CMD ["sleep", "infinity"]

