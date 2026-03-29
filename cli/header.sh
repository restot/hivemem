#!/usr/bin/env bash
# hivemem — Portable CLI for hivemem knowledge store
# Usage: hivemem <command> [args]
#
# Commands:
#   setup              Bootstrap the hivemem server (TLS, auth)
#   init [OPTIONS]     Install skills, hooks, configure settings
#   prime [PROJECT]    Output project knowledge for session priming
#   migrate [PATH]     Migrate mulch records into hivemem
#   validate           Check record health (pre-commit hook)
#   status             Check hivemem server health
#   version            Show version and check for updates
#   update             Self-update to the latest release
#   help               Show this help

set -euo pipefail

VERSION="0.5.1"
GITHUB_REPO="restot/hivemem"
GITHUB_URL="https://github.com/$GITHUB_REPO"

DEFAULT_SERVER_URL="https://localhost:3055"
SKILLS_DST="$HOME/.claude/skills"
OLD_COMMANDS_DST="$HOME/.claude/commands"

# Source repo paths (relative to this script when run from repo checkout)
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_PATH")"
