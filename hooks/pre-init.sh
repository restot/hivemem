#!/usr/bin/env bash
set -euo pipefail

# hivemem SessionStart/PreCompact hook
# Outputs project knowledge to stdout — Claude Code injects it as context.

# Derive project name from git or directory
PROJECT_NAME=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PROJECT_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")"
fi
PROJECT_NAME="${PROJECT_NAME:-$(basename "$(pwd)")}"

# Output hivemem knowledge (captured by Claude Code as additional context)
if command -v hivemem >/dev/null 2>&1; then
  hivemem prime "$PROJECT_NAME" 2>/dev/null || echo "# Hivemem: no data for $PROJECT_NAME"
else
  echo "# Hivemem: CLI not found"
  echo ""
  echo "Install: gh release download --repo restot/hivemem --pattern hivemem --dir ~/.local/bin && chmod +x ~/.local/bin/hivemem"
fi
