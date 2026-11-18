#!/usr/bin/env bash
# ==============================================================================
# GitHub MCP Server Wrapper with Automatic Token Resolution
# ==============================================================================
set -e

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
else
    echo "Error: Neither github-mcp-server-bin nor npx is available." >&2
    exit 1
fi
