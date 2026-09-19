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
  "Dart-Code.flutter"
  "Dart-Code.dart-code"
  "cweijan.vscode-database-client2"
  "esbenp.prettier-vscode"
  "formulahendry.auto-rename-tag"
  "christian-kohler.path-intellisense"
  "davidanson.vscode-markdownlint"
  "oderwat.indent-rainbow"
  "usernamehw.errorlens"
  "google.google-antigravity"
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

# --- 9. START SUPABASE LOOPBACK PROXY (IF ACTIVE) ---
if [ -x "/usr/local/bin/supabase-proxy" ]; then
    /usr/local/bin/supabase-proxy start >/dev/null 2>&1 || true
fi

echo "🎯 Spliqo Dev Workspace Setup Complete!"

