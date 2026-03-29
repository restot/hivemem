# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
skip()  { printf '\033[1;33m  –\033[0m %s (skipped)\n' "$*"; }
warn()  { printf '\033[1;33m  ⚠\033[0m %s\n' "$*"; }
die()   { printf '\033[0;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Required: $1"
}

# Read a key from a hivemem config file
# Usage: _read_config <file> <key>
_read_config() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2-
}

# Read URL or token from a legacy .mcp.json file
# Usage: _read_legacy_mcp <file> <field>  (field: url or token)
_read_legacy_mcp() {
  local file="$1" field="$2"
  [[ -f "$file" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$file" "$field" <<'PYEOF' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    hm = cfg.get("mcpServers", {}).get("hivemem", {})
    if sys.argv[2] == "url":
        url = hm.get("url", "")
        url = url.removesuffix("/mcp").rstrip("/")
        print(url)
    elif sys.argv[2] == "token":
        auth = hm.get("headers", {}).get("Authorization", "")
        print(auth.removeprefix("Bearer "))
except Exception:
    pass
PYEOF
}

# Resolve the hivemem server URL and auth token
# Sets: SERVER_URL, AUTH_TOKEN
# Precedence: env > project .hivemem/config > global ~/.hivemem/config
#             > legacy .mcp.json > legacy ~/.mcp.json > defaults
resolve_server() {
  # Server URL
  SERVER_URL="${HIVEMEM_URL:-}"
  if [[ -z "$SERVER_URL" ]]; then
    SERVER_URL="$(_read_config ".hivemem/config" "server_url" 2>/dev/null || true)"
  fi
  if [[ -z "$SERVER_URL" ]]; then
    SERVER_URL="$(_read_config "$HOME/.hivemem/config" "server_url" 2>/dev/null || true)"
  fi
  # Legacy .mcp.json fallback
  if [[ -z "$SERVER_URL" ]]; then
    SERVER_URL="$(_read_legacy_mcp ".mcp.json" "url" 2>/dev/null || true)"
  fi
  if [[ -z "$SERVER_URL" ]]; then
    SERVER_URL="$(_read_legacy_mcp "$HOME/.mcp.json" "url" 2>/dev/null || true)"
  fi
  SERVER_URL="${SERVER_URL:-$DEFAULT_SERVER_URL}"
  # Strip trailing /mcp if present (legacy URLs)
  SERVER_URL="${SERVER_URL%/mcp}"
  SERVER_URL="${SERVER_URL%/}"

  # Auth token
  AUTH_TOKEN="${HIVEMEM_AUTH_TOKEN:-}"
  if [[ -z "$AUTH_TOKEN" ]]; then
    AUTH_TOKEN="$(_read_config ".hivemem/config" "auth_token" 2>/dev/null || true)"
  fi
  if [[ -z "$AUTH_TOKEN" ]]; then
    AUTH_TOKEN="$(_read_config "$HOME/.hivemem/config" "auth_token" 2>/dev/null || true)"
  fi
  # Legacy .mcp.json fallback
  if [[ -z "$AUTH_TOKEN" ]]; then
    AUTH_TOKEN="$(_read_legacy_mcp ".mcp.json" "token" 2>/dev/null || true)"
  fi
  if [[ -z "$AUTH_TOKEN" ]]; then
    AUTH_TOKEN="$(_read_legacy_mcp "$HOME/.mcp.json" "token" 2>/dev/null || true)"
  fi
  if [[ -z "$AUTH_TOKEN" ]]; then
    AUTH_TOKEN="$(resolve_token 2>/dev/null || true)"
  fi
}

# Read the auth token from .env (legacy fallback)
resolve_token() {
  local env_file=""
  if [[ -n "${HIVEMEM_PROJECT_ROOT:-}" && -f "$HIVEMEM_PROJECT_ROOT/.env" ]]; then
    env_file="$HIVEMEM_PROJECT_ROOT/.env"
  elif [[ -f "$HOME/.hivemem/.env" ]]; then
    env_file="$HOME/.hivemem/.env"
  else
    local root
    root="$(find_project_root 2>/dev/null || true)"
    if [[ -n "$root" && -f "$root/.env" ]]; then
      env_file="$root/.env"
    fi
  fi
  if [[ -n "$env_file" ]]; then
    grep -E '^HIVEMEM_AUTH_TOKEN=' "$env_file" 2>/dev/null | cut -d= -f2- || true
  fi
}

# Locate the hivemem project root (where docker-compose.yml lives)
find_project_root() {
  if [[ -n "${HIVEMEM_PROJECT_ROOT:-}" ]]; then
    echo "$HIVEMEM_PROJECT_ROOT"
    return
  fi
  local candidates=(
    "$HOME/Documents/projects/hivemem"
    "$HOME/projects/hivemem"
    "$HOME/hivemem"
  )
  for d in "${candidates[@]}"; do
    if [[ -f "$d/docker-compose.yml" ]]; then
      echo "$d"
      return
    fi
  done
  if [[ -f "./docker-compose.yml" ]] && grep -q hivemem "./docker-compose.yml" 2>/dev/null; then
    pwd
    return
  fi
  die "Cannot find hivemem project root. Set HIVEMEM_PROJECT_ROOT or run from the hivemem directory."
}
