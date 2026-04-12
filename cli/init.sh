# ---------------------------------------------------------------------------
# resolve_source_dir — Find repo source for skills and hooks
# ---------------------------------------------------------------------------
resolve_source_dir() {
  if [[ -d "$REPO_ROOT/skills" && -d "$REPO_ROOT/hooks" ]]; then
    echo "$REPO_ROOT"
    return
  fi

  need git

  local tmpdir clone_url
  tmpdir="$(mktemp -d)"
  clone_url="$GITHUB_URL.git"

  git clone --depth 1 --branch main --filter=blob:none --sparse \
    "$clone_url" "$tmpdir" 2>/dev/null
  (cd "$tmpdir" && git sparse-checkout set skills hooks 2>/dev/null)

  echo "$tmpdir"
}

# ---------------------------------------------------------------------------
# install_skills — Install/update skill files from repo
# ---------------------------------------------------------------------------
install_skills() {
  local src_dir="$1/skills"

  if [[ ! -d "$src_dir" ]]; then
    warn "No skills source directory found at $src_dir"
    return 1
  fi

  mkdir -p "$SKILLS_DST"

  local installed=0
  for skill_dir in "$src_dir"/hm-*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name
    skill_name="$(basename "$skill_dir")"
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue

    local dst_dir="$SKILLS_DST/$skill_name"
    local dst_file="$dst_dir/SKILL.md"
    mkdir -p "$dst_dir"

    if [[ -f "$dst_file" ]] && cmp -s "$skill_file" "$dst_file"; then
      skip "$skill_name"
    else
      cp "$skill_file" "$dst_file"
      ok "$skill_name -> ~/.claude/skills/$skill_name/SKILL.md"
      installed=$((installed + 1))
    fi
  done

  # Clean up old commands format
  local cleaned=0
  for old_cmd in "$OLD_COMMANDS_DST"/hm-*.md; do
    [[ -f "$old_cmd" ]] || continue
    rm -f "$old_cmd"
    ok "Removed old command: $(basename "$old_cmd")"
    cleaned=$((cleaned + 1))
  done

  if [[ $installed -eq 0 ]]; then
    echo "  All skills up to date."
  else
    echo "  Installed/updated $installed skill(s)."
  fi
  [[ $cleaned -gt 0 ]] && echo "  Cleaned up $cleaned old command(s)." || true
}

# ---------------------------------------------------------------------------
# install_hooks — Copy hook scripts to .hivemem/hooks/
# ---------------------------------------------------------------------------
install_hooks() {
  local src_dir="$1/hooks"
  local dst_dir="$2"

  if [[ ! -d "$src_dir" ]]; then
    warn "No hooks source directory found at $src_dir"
    return 1
  fi

  mkdir -p "$dst_dir/hooks"

  local installed=0
  for hook_file in "$src_dir"/*.sh; do
    [[ -f "$hook_file" ]] || continue
    local name
    name="$(basename "$hook_file")"
    local dst_file="$dst_dir/hooks/$name"

    if [[ -f "$dst_file" ]] && cmp -s "$hook_file" "$dst_file"; then
      skip "hooks/$name"
    else
      cp "$hook_file" "$dst_file"
      chmod +x "$dst_file"
      ok "hooks/$name -> $dst_dir/hooks/$name"
      installed=$((installed + 1))
    fi
  done

  if [[ $installed -eq 0 ]]; then
    echo "  All hooks up to date."
  else
    echo "  Installed/updated $installed hook(s)."
  fi
}

# ---------------------------------------------------------------------------
# write_config — Create/update .hivemem/config
# ---------------------------------------------------------------------------
write_config() {
  local hivemem_dir="$1"
  local server_url="$2"
  local token="${3:-}"
  local config_file="$hivemem_dir/config"

  mkdir -p "$hivemem_dir"

  local new_content
  new_content="$(printf 'server_url=%s\n' "$server_url")"
  [[ -n "$token" ]] && new_content="${new_content}$(printf 'auth_token=%s\n' "$token")"

  if [[ -f "$config_file" ]] && [[ "$(cat "$config_file")" == "$new_content" ]]; then
    skip "config (unchanged)"
  else
    printf '%s' "$new_content" > "$config_file"
    ok "config -> $config_file (server: $server_url)"
  fi
}

# ---------------------------------------------------------------------------
# configure_settings_hooks — Add hivemem hooks to Claude settings JSON
# Merges with existing hooks, does not overwrite.
# ---------------------------------------------------------------------------
configure_settings_hooks() {
  local settings_file="$1"
  local hivemem_dir="$2"

  need python3

  mkdir -p "$(dirname "$settings_file")"

  python3 - "$settings_file" "$hivemem_dir" <<'PYEOF'
import json, sys, os

settings_file = sys.argv[1]
hivemem_dir = sys.argv[2]

# Define the hivemem hooks
hivemem_hooks = {
    "SessionStart": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hivemem_dir}/hooks/pre-init.sh",
                    "timeout": 15
                }
            ]
        }
    ],
    "PreCompact": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hivemem_dir}/hooks/pre-init.sh",
                    "timeout": 15
                }
            ]
        }
    ],
    "Stop": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{hivemem_dir}/hooks/stop.sh",
                    "timeout": 5
                }
            ]
        }
    ]
}

# Load existing settings
try:
    with open(settings_file, "r") as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings.setdefault("hooks", {})

changed = False

# Collect all hivemem hook commands we're installing
all_hm_commands = set()
for groups in hivemem_hooks.values():
    for g in groups:
        for h in g.get("hooks", []):
            all_hm_commands.add(h["command"])

# Clean up stale hivemem hooks and legacy "hivemem prime" hooks from ALL events
for event in list(settings["hooks"].keys()):
    existing = settings["hooks"][event]
    filtered = []
    for eg in existing:
        eg_commands = {h.get("command", "") for h in eg.get("hooks", [])}
        is_stale_hm = any("/.hivemem/hooks/" in c for c in eg_commands) and not (eg_commands & all_hm_commands)
        is_legacy = any(c == "hivemem prime" for c in eg_commands)
        if not is_stale_hm and not is_legacy:
            filtered.append(eg)
    if filtered != existing:
        settings["hooks"][event] = filtered
        changed = True
    if not settings["hooks"][event]:
        del settings["hooks"][event]
        changed = True

for event, groups in hivemem_hooks.items():
    existing = settings["hooks"].get(event, [])

    # Remove any existing hivemem hook groups (to allow updating)
    filtered = []
    for eg in existing:
        eg_commands = {h.get("command", "") for h in eg.get("hooks", [])}
        is_hm = any("/.hivemem/hooks/" in c for c in eg_commands)
        is_legacy = any(c == "hivemem prime" for c in eg_commands)
        if not is_hm and not is_legacy:
            filtered.append(eg)

    new_list = filtered + groups

    if new_list != existing:
        settings["hooks"][event] = new_list
        changed = True

if changed:
    with open(settings_file, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print("UPDATED")
else:
    print("UNCHANGED")
PYEOF
}

# ---------------------------------------------------------------------------
# migrate_legacy_config — Migrate from .mcp.json to .hivemem/config
# Cleans up old .mcp.json hivemem entries and warns about CLAUDE.md blocks.
# ---------------------------------------------------------------------------
migrate_legacy_config() {
  local hivemem_dir="$1"
  local migrated=false

  for mcp_file in ".mcp.json" "$HOME/.mcp.json"; do
    [[ -f "$mcp_file" ]] || continue

    local legacy_url legacy_token
    legacy_url="$(_read_legacy_mcp "$mcp_file" "url" || true)"
    legacy_token="$(_read_legacy_mcp "$mcp_file" "token" || true)"

    [[ -n "$legacy_url" ]] || continue

    echo ""
    info "Legacy migration"

    # Write to new config if not already configured
    if [[ ! -f "$hivemem_dir/config" ]]; then
      write_config "$hivemem_dir" "$legacy_url" "$legacy_token"
      ok "Migrated config from $mcp_file -> $hivemem_dir/config"
      migrated=true
    else
      skip "Config already exists at $hivemem_dir/config"
    fi

    # Remove hivemem entry from .mcp.json
    python3 - "$mcp_file" <<'PYEOF' 2>/dev/null || true
import json, sys, os
mcp_file = sys.argv[1]
with open(mcp_file) as f:
    cfg = json.load(f)
if "hivemem" not in cfg.get("mcpServers", {}):
    sys.exit(0)
del cfg["mcpServers"]["hivemem"]
if not cfg["mcpServers"]:
    del cfg["mcpServers"]
if cfg:
    with open(mcp_file, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print(f"  Cleaned hivemem entry from {mcp_file}")
else:
    os.remove(mcp_file)
    print(f"  Removed empty {mcp_file}")
PYEOF

    break  # Only migrate from first found
  done

  # Warn about legacy CLAUDE.md blocks
  local check_dirs=(".")
  [[ -n "${2:-}" ]] && check_dirs+=("$2")
  for d in "${check_dirs[@]}"; do
    if [[ -f "$d/CLAUDE.md" ]] && grep -q '<!-- hivemem:start -->' "$d/CLAUDE.md" 2>/dev/null; then
      echo ""
      warn "Legacy hivemem block found in $d/CLAUDE.md"
      echo "    Context is now injected via pre-init hook. You can safely remove the"
      echo "    <!-- hivemem:start --> ... <!-- hivemem:end --> block."
    fi
  done

  # Warn about legacy NODE_EXTRA_CA_CERTS in settings.json
  if [[ -f "$HOME/.claude/settings.json" ]]; then
    local has_node_ca
    has_node_ca="$(python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
if 'NODE_EXTRA_CA_CERTS' in s.get('env', {}):
    print('yes')
" 2>/dev/null || true)"
    if [[ "$has_node_ca" == "yes" ]]; then
      echo ""
      warn "Legacy NODE_EXTRA_CA_CERTS found in ~/.claude/settings.json"
      echo "    This was needed for MCP client TLS. It's no longer required"
      echo "    since hivemem now uses CLI instead of MCP integration."
    fi
  fi
}

# =========================================================================
# init — Install skills, hooks, configure settings
# Default: global (~/.hivemem, ~/.claude/settings.json)
# --local: project-specific (.hivemem/ in project root)
# =========================================================================
cmd_init() {
  local use_global=true
  local server_url="${HIVEMEM_URL:-$DEFAULT_SERVER_URL}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --global) use_global=true; shift ;;
      --local)  use_global=false; shift ;;
      --server) server_url="$2"; shift 2 ;;
      *) die "init: unknown option $1" ;;
    esac
  done

  # Resolve source files (repo checkout or sparse clone)
  local source_dir
  source_dir="$(resolve_source_dir)"
  local cleanup_source=false
  if [[ "$source_dir" != "$REPO_ROOT" ]]; then
    cleanup_source=true
  fi

  # Determine target paths
  local hivemem_dir settings_file

  if $use_global; then
    hivemem_dir="$HOME/.hivemem"
    settings_file="$HOME/.claude/settings.json"
  else
    local project_root
    project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    hivemem_dir="$project_root/.hivemem"
    settings_file="$project_root/.claude/settings.json"
  fi

  # Resolve to absolute path
  local hivemem_dir_abs
  mkdir -p "$hivemem_dir"
  hivemem_dir_abs="$(cd "$hivemem_dir" && pwd)"

  # --- 1. Skills ---
  info "Skills"
  install_skills "$source_dir"

  # --- 2. Hook scripts ---
  echo ""
  info "Hook scripts"
  install_hooks "$source_dir" "$hivemem_dir_abs"

  # --- 3. Config ---
  echo ""
  info "Config"
  local token
  token="${HIVEMEM_AUTH_TOKEN:-$(_read_config "$HOME/.hivemem/config" "auth_token" 2>/dev/null || true)}"
  write_config "$hivemem_dir_abs" "$server_url" "$token"

  # --- 4. Claude settings hooks ---
  echo ""
  info "Claude settings hooks"
  local hook_result
  hook_result="$(configure_settings_hooks "$settings_file" "$hivemem_dir_abs")"
  if [[ "$hook_result" == "UPDATED" ]]; then
    ok "Hooks configured in $settings_file"
  else
    skip "Hooks already configured in $settings_file"
  fi

  # --- 5. TLS cert trust ---
  local server_host
  server_host="$(echo "$server_url" | sed -E 's|https?://([^/]+).*|\1|')"
  if [[ "$server_host" != *:* ]]; then
    if [[ "$server_url" == https://* ]]; then
      server_host="$server_host:443"
    else
      server_host="$server_host:80"
    fi
  fi

  echo ""
  trust_server_cert "$server_host" || true

  # --- 6. Legacy migration ---
  migrate_legacy_config "$hivemem_dir_abs"

  # Clean up temp source dir
  if $cleanup_source; then
    rm -rf "$source_dir"
  fi

  echo ""
  info "Hivemem initialized"
  echo ""
  echo "  Server:    $server_url"
  echo "  Skills:    $SKILLS_DST/hm-*/"
  echo "  Hooks:     $hivemem_dir_abs/hooks/"
  echo "  Config:    $hivemem_dir_abs/config"
  echo "  Settings:  $settings_file"
  echo ""
  if $use_global; then
    echo "  Global install (default). Use --local for project-specific config."
  else
    echo "  Project-local install. Global config takes effect everywhere else."
  fi
  echo ""
}
