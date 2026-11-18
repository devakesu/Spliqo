#!/usr/bin/env bash
set -e

echo "🚀 Running Spliqo Dev Workspace Initialization..."

# --- 0. SILENCE SUDO HINT & RESOLVE UNNAMED GROUP IDS ---
touch "$HOME/.sudo_as_admin_successful" "$HOME/.hushlogin" 2>/dev/null || true
for gid in $(id -G 2>/dev/null); do
    if ! getent group "$gid" >/dev/null 2>&1; then
        sudo groupadd -g "$gid" "host-group-$gid" 2>/dev/null || true
    fi
done

# --- 1. RESOLVE WORKSPACE & ENSURE VOLUME OWNERSHIP ---
TARGET_DIR="${WORKSPACE_DIR:-${containerWorkspaceFolder:-/workspaces/Spliqo}}"
if [ ! -d "$TARGET_DIR" ]; then
    if [ -d "/workspaces/Spliqo" ]; then
        TARGET_DIR="/workspaces/Spliqo"
    elif [ -d "/spliqo" ]; then
        TARGET_DIR="/spliqo"
    else
        TARGET_DIR="$PWD"
    fi
fi

echo "🔐 Verifying cache and workspace permissions..."
TARGET_VOLUME_DIRS=(
    "/home/vscode/.pub-cache"
    "/home/vscode/.gradle"
    "/home/vscode/.npm"
    "/home/vscode/.cache"
    "$TARGET_DIR/spliqo_client/.dart_tool"
    "$TARGET_DIR/spliqo_client/build"
    "/workspaces/Spliqo/spliqo_client/.dart_tool"
    "/workspaces/Spliqo/spliqo_client/build"
)

for vdir in "${TARGET_VOLUME_DIRS[@]}"; do
    if [ ! -d "$vdir" ]; then
        sudo mkdir -p "$vdir" 2>/dev/null || true
    fi
    if [ -d "$vdir" ] && [ "$(stat -c '%u' "$vdir" 2>/dev/null)" != "$(id -u)" ]; then
        sudo chown -R vscode:vscode "$vdir" 2>/dev/null || true
        sudo chmod -R 775 "$vdir" 2>/dev/null || true
    fi
done

# Ensure workspace and spliqo_client directory roots have correct vscode ownership
for pdir in "$TARGET_DIR" "$TARGET_DIR/spliqo_client" "/workspaces/Spliqo/spliqo_client"; do
    if [ -d "$pdir" ] && [ "$(stat -c '%u' "$pdir" 2>/dev/null)" != "$(id -u)" ]; then
        sudo chown vscode:vscode "$pdir" 2>/dev/null || true
        sudo chmod 775 "$pdir" 2>/dev/null || true
    fi
done

# --- 2. GIT CONFIG DIVERSION ---
if [ ! -L "/home/vscode/.gitconfig" ]; then
    if [ -f "/home/vscode/.gitconfig" ]; then
        mv /home/vscode/.gitconfig /home/vscode/.gitconfig_local
    else
        touch /home/vscode/.gitconfig_local
    fi
    ln -sf /home/vscode/.gitconfig_local /home/vscode/.gitconfig
fi
chmod 644 /home/vscode/.gitconfig_local 2>/dev/null || true

# --- 3. GIT IDENTITY AUTO-CONFIGURATION ---
CURRENT_NAME=$(git config --global user.name 2>/dev/null || true)
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || true)

if [ -z "$CURRENT_NAME" ] || [ -z "$CURRENT_EMAIL" ]; then
    if [ -t 0 ]; then
        echo "👤 Setting up Git identity..."
        [ -z "$CURRENT_NAME" ] && read -rp "Enter Git Name: " CURRENT_NAME && git config --global user.name "$CURRENT_NAME"
        [ -z "$CURRENT_EMAIL" ] && read -rp "Enter Git Email: " CURRENT_EMAIL && git config --global user.email "$CURRENT_EMAIL"
    else
        AUTO_EMAIL=$(ssh-add -L 2>/dev/null | awk '{print $3}' | grep "@" | head -n 1 || true)
        [ -z "$CURRENT_NAME" ] && git config --global user.name "${GIT_NAME:-User}"
        [ -z "$CURRENT_EMAIL" ] && git config --global user.email "${GIT_EMAIL:-${AUTO_EMAIL:-dev@example.com}}"
        echo "ℹ️ Auto-configured Git identity: $(git config --global user.name) <$(git config --global user.email)>"
    fi
fi

# --- 4. SSH AGENT & SIGNING SETUP ---
echo "🔑 Checking SSH Agent Forwarding..."
HAS_SSH_KEY=false
if [ -S "${SSH_AUTH_SOCK:-}" ] && ssh-add -L >/dev/null 2>&1; then
    CLEAN_KEY=$(ssh-add -L 2>/dev/null | tr -d '\r' | head -n 1)
    if [ -n "$CLEAN_KEY" ]; then
        HAS_SSH_KEY=true
        git config --global user.signingkey "$CLEAN_KEY"
        git config --global gpg.format ssh
        git config --global commit.gpgsign true
        
        ALLOWED_FILE="/home/vscode/.ssh/allowed_signers"
        mkdir -p /home/vscode/.ssh && chmod 700 /home/vscode/.ssh
        EMAIL=$(git config --global user.email 2>/dev/null || echo "*")
        echo "${EMAIL:-*} ${CLEAN_KEY}" > "$ALLOWED_FILE"
        chmod 600 "$ALLOWED_FILE"
        git config --global gpg.ssh.allowedSignersFile "$ALLOWED_FILE"
        echo "✅ SSH commit signing active."
    fi
else
    echo "ℹ️ SSH Agent is not active or has no keys loaded."
fi

# --- 5. GIT SAFE DIRECTORY ---
git config --global --add safe.directory "$TARGET_DIR"
git config --global --add safe.directory /workspaces/Spliqo 2>/dev/null || true
git config --global --add safe.directory /spliqo 2>/dev/null || true

# --- 6. PYTHON / FASTAPI ENVIRONMENT SYNCHRONIZATION ---
VENV_DIR="$TARGET_DIR/.venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "🐍 Initializing Python virtual environment at $VENV_DIR..."
    if command -v uv >/dev/null 2>&1; then
        uv venv "$VENV_DIR" --python python3
    else
        python3 -m venv "$VENV_DIR"
    fi
fi

# Locate requirements file if present
REQ_FILE=""
if [ -f "$TARGET_DIR/requirements.txt" ]; then
    REQ_FILE="$TARGET_DIR/requirements.txt"
elif [ -f "$TARGET_DIR/backend/requirements.txt" ]; then
    REQ_FILE="$TARGET_DIR/backend/requirements.txt"
elif [ -f "$TARGET_DIR/api/requirements.txt" ]; then
    REQ_FILE="$TARGET_DIR/api/requirements.txt"
fi

if [ -n "$REQ_FILE" ] && [ -x "$VENV_DIR/bin/pip" ]; then
    echo "📦 Synchronizing Python dependencies from $REQ_FILE..."
    if grep -q "--hash=" "$REQ_FILE" 2>/dev/null; then
        echo "🔒 Installing dependencies with strict hash verification..."
        "$VENV_DIR/bin/pip" install --require-hashes -r "$REQ_FILE"
    elif command -v uv >/dev/null 2>&1; then
        VIRTUAL_ENV="$VENV_DIR" uv pip install -r "$REQ_FILE"
    else
        "$VENV_DIR/bin/pip" install -r "$REQ_FILE"
    fi
elif [ -f "$TARGET_DIR/pyproject.toml" ] && command -v uv >/dev/null 2>&1; then
    echo "📦 Synchronizing pyproject.toml dependencies..."
    VIRTUAL_ENV="$VENV_DIR" uv pip install -e "$TARGET_DIR" 2>/dev/null || true
fi

# Ensure pip-tools is installed in the virtual environment and system toolchain
if [ -x "$VENV_DIR/bin/pip" ]; then
    if command -v uv >/dev/null 2>&1; then
        VIRTUAL_ENV="$VENV_DIR" uv pip install pip-tools >/dev/null 2>&1 || true
    else
        "$VENV_DIR/bin/pip" install pip-tools >/dev/null 2>&1 || true
    fi
fi
if ! command -v pip-compile >/dev/null 2>&1 && command -v uv >/dev/null 2>&1; then
    sudo env UV_TOOL_DIR="/usr/local/share/uv-tools" UV_TOOL_BIN_DIR="/usr/local/bin" uv tool install --force pip-tools >/dev/null 2>&1 || true
fi

BASHRC="/home/vscode/.bashrc"
if ! grep -qF "$VENV_DIR/bin/activate" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "# Auto-activate Spliqo Python virtual environment" >> "$BASHRC"
    echo "if [ -f $VENV_DIR/bin/activate ]; then source $VENV_DIR/bin/activate; fi" >> "$BASHRC"
fi

# --- 7. FLUTTER CLIENT DEPENDENCIES SYNCHRONIZATION ---
if command -v flutter >/dev/null 2>&1; then 
    FLUTTER_SYNCED=false
    for app_dir in "$TARGET_DIR/spliqo_client" "$TARGET_DIR"; do
        if [ -f "$app_dir/pubspec.yaml" ]; then
            rel_name=$(basename "$app_dir")
            echo "🐦 Synchronizing Flutter packages ($rel_name)..."
            (cd "$app_dir" && flutter pub get) || echo "⚠️ Failed to synchronize Flutter packages in $rel_name"
            FLUTTER_SYNCED=true
        fi
    done
    if [ "$FLUTTER_SYNCED" = false ]; then
        echo "ℹ️ No Flutter project (pubspec.yaml) found. Skipping Flutter package sync."
    fi
fi

# Optional NPM sync (if package.json present)
if [ -f "$TARGET_DIR/package.json" ]; then 
    echo "📦 Synchronizing NPM packages..."
    (cd "$TARGET_DIR" && npm install --legacy-peer-deps)
fi

# --- 8. EXTENSION SYNC ACROSS ALL IDES ---
EXTENSIONS=(
  "ms-python.python"
  "ms-pyright.pyright"
  "ms-python.debugpy"
  "charliermarsh.ruff"
  "tamasfe.even-better-toml"
  "Dart-Code.flutter"
  "Dart-Code.dart-code"
  "cweijan.vscode-database-client2"
  "esbenp.prettier-vscode"
  "formulahendry.auto-rename-tag"
  "christian-kohler.path-intellisense"
  "davidanson.vscode-markdownlint"
  "oderwat.indent-rainbow"
  "usernamehw.errorlens"
  "swiftlang.swift-vscode"
  "meezilla.json"
  "timonwong.shellcheck"
  "redhat.vscode-yaml"
  "vscjava.vscode-gradle"
  "github.vscode-github-actions"
  "google.google-antigravity"
  "ms-vscode.cmake-tools"
  "openai.chatgpt"
  "mkhl.direnv"
  "Anthropic.claude-code"
)

PRIMARY_CLI=""
if command -v code >/dev/null 2>&1; then
    PRIMARY_CLI="code"
elif command -v antigravity >/dev/null 2>&1; then
    PRIMARY_CLI="antigravity"
elif command -v cursor >/dev/null 2>&1; then
    PRIMARY_CLI="cursor"
else
    while IFS= read -r binary_path; do
        if [ -n "$binary_path" ] && "$binary_path" --version >/dev/null 2>&1; then
            PRIMARY_CLI="$binary_path"
            break
        fi
    done < <(find ~/.vscode-server ~/.antigravity-server ~/.antigravity-ide-server ~/.cursor-server -type f -executable \( -name "code-server" -o -name "antigravity-server" -o -name "antigravity-ide-server" -o -name "cursor-server" \) 2>/dev/null || true)
fi

if [ -n "$PRIMARY_CLI" ]; then
    echo "🔧 Synchronizing extensions via: $PRIMARY_CLI"
    INSTALLED_EXTS=$("$PRIMARY_CLI" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
    for ext in "${EXTENSIONS[@]}"; do
        EXT_LOWER=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
        if ! echo "$INSTALLED_EXTS" | grep -q "^${EXT_LOWER}$"; then
            echo "  ⬇️ Installing extension: $ext"
            "$PRIMARY_CLI" --install-extension "$ext" --force >/dev/null 2>&1 || true
        fi
    done
fi

# --- 9. UI/UX SKILLS & IMPECCABLE INITIALIZATION ---
echo "🎨 Initializing UI/UX skills & Impeccable..."
if ! command -v uipro >/dev/null 2>&1; then
    sudo npm install -g ui-ux-pro-max-cli >/dev/null 2>&1 || npm install -g ui-ux-pro-max-cli >/dev/null 2>&1 || true
fi

(
    cd "$TARGET_DIR"
    if command -v uipro >/dev/null 2>&1; then
        uipro init --ai claude >/dev/null 2>&1 || true
        uipro init --ai cursor >/dev/null 2>&1 || true
        uipro init --ai antigravity >/dev/null 2>&1 || true
        uipro init --ai codex >/dev/null 2>&1 || true
        uipro init --ai gemini >/dev/null 2>&1 || true
        uipro init --ai opencode >/dev/null 2>&1 || true
    fi

    npx --yes impeccable install -y 2>/dev/null || true
)

# --- 10. DIRENV & INFISICAL AUTH SETUP ---
echo "⚡ Configuring direnv & Infisical auto-auth..."
if ! grep -q 'direnv hook bash' "$HOME/.bashrc" 2>/dev/null; then
    cat << 'EOF' >> "$HOME/.bashrc"

# Direnv shell hook & initial environment export
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)"
    eval "$(direnv export bash 2>/dev/null)"
fi
EOF
fi

if ! grep -q 'infisical_auth()' "$HOME/.bashrc" 2>/dev/null; then
    cat << 'EOF' >> "$HOME/.bashrc"

# Infisical Universal Auth Helper
infisical_auth() {
  local client_id="${1:-${INFISICAL_SECRETS_UNIVERSAL_AUTH_CLIENT_ID:-}}"
  local client_secret="${2:-${INFISICAL_SECRETS_UNIVERSAL_AUTH_CLIENT_SECRET:-}}"

  if [ -z "$client_id" ] || [ -z "$client_secret" ] || \
     [ "$client_id" = "<YOUR_CLIENT_ID>" ] || [ "$client_secret" = "<YOUR_CLIENT_SECRET>" ]; then
    return 0
  fi

  if command -v infisical >/dev/null 2>&1; then
    local token
    token=$(infisical login --method=universal-auth \
      --client-id="$client_id" \
      --client-secret="$client_secret" \
      --plain --silent 2>/dev/null)
    if [ -n "$token" ]; then
      export INFISICAL_TOKEN="$token"
      echo "🔐 Infisical authenticated (INFISICAL_TOKEN exported)."
    fi
  fi
}
EOF
fi

if [ -f "$TARGET_DIR/.envrc" ]; then
    echo "  🔓 Authorizing direnv in $TARGET_DIR..."
    (cd "$TARGET_DIR" && direnv allow .) 2>/dev/null || true
fi

# --- 11. ADB PORT FORWARD BRIDGE DAEMON ---
echo "📱 Checking ADB Port Forward Bridge..."
ADB_BRIDGE_SCRIPT="$TARGET_DIR/scripts/adb_forward_bridge.py"
if [ ! -f "$ADB_BRIDGE_SCRIPT" ] && [ -f "/workspaces/Spliqo/scripts/adb_forward_bridge.py" ]; then
    ADB_BRIDGE_SCRIPT="/workspaces/Spliqo/scripts/adb_forward_bridge.py"
fi

if ! grep -q 'adb_forward_bridge.py' "$HOME/.bashrc" 2>/dev/null; then
    cat << EOF >> "$HOME/.bashrc"

# Ensure ADB Port Forward Bridge is running for DevContainer Flutter debugging
if [[ -n "\$ADB_SERVER_SOCKET" ]] && ! pgrep -f "adb_forward_bridge.py" >/dev/null 2>&1; then
  nohup python3 "$ADB_BRIDGE_SCRIPT" >/tmp/adb_forward_bridge.log 2>&1 &
fi
EOF
fi

if [[ -n "$ADB_SERVER_SOCKET" ]] && [ -f "$ADB_BRIDGE_SCRIPT" ] && ! pgrep -f "adb_forward_bridge.py" >/dev/null 2>&1; then
    nohup python3 "$ADB_BRIDGE_SCRIPT" >/tmp/adb_forward_bridge.log 2>&1 &
    echo "  ✅ ADB Port Forward Bridge started in background."
fi

# --- 12. MCP SERVERS & SKILLS SETUP ---
echo "🤖 Ensuring MCP servers and AI developer skills are configured..."
if ! command -v sentry >/dev/null 2>&1; then
    curl -fsSL https://cli.sentry.dev/install | bash 2>/dev/null || true
fi

if ! docker mcp --version >/dev/null 2>&1; then
    ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
    case "${ARCH}" in
      amd64) DOCKER_MCP_ARCH="linux-amd64";;
      arm64) DOCKER_MCP_ARCH="linux-arm64";;
      *) DOCKER_MCP_ARCH="linux-amd64";;
    esac
    sudo mkdir -p /usr/libexec/docker/cli-plugins 2>/dev/null || true
    curl -fsSL "https://github.com/docker/mcp-gateway/releases/download/v0.44.3/docker-mcp-${DOCKER_MCP_ARCH}.tar.gz" 2>/dev/null | sudo tar -xz -C /usr/libexec/docker/cli-plugins 2>/dev/null || true
    sudo chmod 755 /usr/libexec/docker/cli-plugins/docker-mcp 2>/dev/null || true
fi

# Ensure github-mcp-server launcher with automatic token resolution
if [ ! -f "/usr/local/bin/github-mcp-server" ] || [ ! -x "/usr/local/bin/github-mcp-server" ]; then
    sudo tee /usr/local/bin/github-mcp-server > /dev/null << 'EOF'
#!/usr/bin/env bash
if [ -z "$GITHUB_PERSONAL_ACCESS_TOKEN" ]; then
    if [ -n "$GITHUB_TOKEN" ]; then
        export GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_TOKEN"
    elif [ -n "$GH_TOKEN" ]; then
        export GITHUB_PERSONAL_ACCESS_TOKEN="$GH_TOKEN"
    elif command -v gh >/dev/null 2>&1; then
        GH_TOKEN_VAL=$(gh auth token 2>/dev/null || true)
        if [ -n "$GH_TOKEN_VAL" ]; then
            export GITHUB_PERSONAL_ACCESS_TOKEN="$GH_TOKEN_VAL"
        fi
    fi
fi
if [ -x "/usr/local/bin/github-mcp-server-bin" ]; then
    exec /usr/local/bin/github-mcp-server-bin "$@"
elif command -v npx >/dev/null 2>&1; then
    exec npx -y @modelcontextprotocol/server-github "$@"
fi
EOF
    sudo chmod 755 /usr/local/bin/github-mcp-server 2>/dev/null || true
fi

mkdir -p "$HOME/.gemini/config" "$HOME/.gemini/antigravity" "$HOME/.config/Claude" "$HOME/.cursor"
MCP_CONFIG_FILES=(
    "$HOME/.gemini/config/mcp_config.json"
    "$HOME/.gemini/antigravity/mcp_config.json"
    "$HOME/.config/Claude/claude_desktop_config.json"
    "$HOME/.cursor/mcp.json"
)

for cfg in "${MCP_CONFIG_FILES[@]}"; do
    if [ ! -f "$cfg" ]; then
        echo '{"mcpServers":{}}' > "$cfg"
    fi
    python3 -c '
import json, sys
cfg_path = sys.argv[1]
try:
    with open(cfg_path, "r") as f:
        data = json.load(f)
except Exception:
    data = {}
servers = data.setdefault("mcpServers", {})
if "dart" not in servers:
    servers["dart"] = {
        "command": "dart",
        "args": ["mcp-server"]
    }
if "github" not in servers:
    servers["github"] = {
        "command": "github-mcp-server",
        "args": ["stdio"]
    }
if "MCP_DOCKER" not in servers:
    servers["MCP_DOCKER"] = {
        "command": "docker",
        "args": ["mcp", "gateway", "run"]
    }
servers["context7"] = {
    "type": "http",
    "url": "https://mcp.context7.com/mcp",
    "serverUrl": "https://mcp.context7.com/mcp"
}
if "sentry" not in servers:
    servers["sentry"] = {
        "command": "sentry",
        "args": ["mcp"]
    }
if "redis" not in servers:
    servers["redis"] = {
        "command": "redis-mcp-server",
        "args": ["--url", "redis://localhost:6379/0"]
    }
servers["cloudflare"] = {
    "type": "http",
    "url": "https://mcp.cloudflare.com/mcp",
    "serverUrl": "https://mcp.cloudflare.com/mcp"
}
with open(cfg_path, "w") as f:
    json.dump(data, f, indent=2)
' "$cfg" 2>/dev/null || true
done

# Ensure official Flutter and Dart skills exist in workspace
if [ -d "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR/.agents/skills/flutter-apply-architecture-best-practices" ]; then
    (
        cd "$TARGET_DIR"
        npx skills add flutter/agent-plugins --skill '*' --agent universal --yes 2>/dev/null || true
        npx skills add dart-lang/skills --skill '*' --agent universal --yes 2>/dev/null || true
    )
fi

# Ensure Cloudflare skills exist in workspace
if [ -d "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR/.agents/skills/cloudflare" ]; then
    (
        cd "$TARGET_DIR"
        npx skills add cloudflare/skills --skill '*' --agent universal --yes 2>/dev/null || true
    )
fi

# --- 13. START SUPABASE LOOPBACK PROXY (IF ACTIVE) ---
if [ -x "/usr/local/bin/supabase-proxy" ]; then
    /usr/local/bin/supabase-proxy start >/dev/null 2>&1 || true
fi

echo "🎯 Spliqo Dev Workspace Setup Complete!"
