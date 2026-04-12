# =========================================================================
# status — Check server health
# =========================================================================
cmd_status() {
  resolve_server
  local health_url="${SERVER_URL}/health"

  printf "  Server:  %s\n" "$SERVER_URL"

  local http_code
  http_code="$(curl -sk -o /dev/null -w '%{http_code}' "$health_url" 2>/dev/null || echo "000")"

  if [[ "$http_code" == "200" ]]; then
    ok "Healthy (HTTP $http_code)"
  elif [[ "$http_code" == "000" ]]; then
    warn "Unreachable (is the server running?)"
  else
    warn "Unhealthy (HTTP $http_code)"
  fi

  # Check skills
  local skill_count=0
  for d in "$SKILLS_DST"/hm-*/; do
    [[ -f "$d/SKILL.md" ]] && skill_count=$((skill_count + 1))
  done
  printf "  Skills:  %d installed in %s\n" "$skill_count" "$SKILLS_DST"

  # Check config
  local config_found=false
  if [[ -f ".hivemem/config" ]]; then
    local project_url
    project_url="$(_read_config ".hivemem/config" "server_url" 2>/dev/null || true)"
    ok "Project config (.hivemem/config) -> ${project_url:-$DEFAULT_SERVER_URL}"
    config_found=true
  fi
  if [[ -f "$HOME/.hivemem/config" ]]; then
    local global_url
    global_url="$(_read_config "$HOME/.hivemem/config" "server_url" 2>/dev/null || true)"
    ok "Global config (~/.hivemem/config) -> ${global_url:-$DEFAULT_SERVER_URL}"
    config_found=true
  fi
  # Check legacy .mcp.json
  if ! $config_found; then
    local legacy_found=false
    for mcp_file in ".mcp.json" "$HOME/.mcp.json"; do
      if [[ -f "$mcp_file" ]]; then
        local legacy_url
        legacy_url="$(_read_legacy_mcp "$mcp_file" "url" 2>/dev/null || true)"
        if [[ -n "$legacy_url" ]]; then
          warn "Legacy config ($mcp_file) -> $legacy_url (run 'hivemem init' to migrate)"
          legacy_found=true
        fi
      fi
    done
    if ! $legacy_found; then
      warn "No config found (run 'hivemem init')"
    fi
  fi
}

# =========================================================================
# version — Show version, check for updates
# =========================================================================
cmd_version() {
  echo "hivemem v$VERSION"

  need gh

  local latest
  latest="$(gh release view --repo "$GITHUB_REPO" --json tagName -q .tagName 2>/dev/null || true)"

  if [[ -z "$latest" ]]; then
    echo "  (no releases published yet)"
  elif [[ "$latest" == "v$VERSION" ]]; then
    echo "  (up to date)"
  else
    echo "  Update available: $latest (run 'hivemem update')"
  fi
}

# =========================================================================
# update — Self-update from GitHub releases
# =========================================================================
cmd_update() {
  need gh

  local self
  self="$(command -v hivemem 2>/dev/null || echo "$0")"

  local latest
  latest="$(gh release view --repo "$GITHUB_REPO" --json tagName -q .tagName 2>/dev/null || true)"

  [[ -z "$latest" ]] && die "No releases found. Publish one first: gh release create v$VERSION bin/hivemem --repo $GITHUB_REPO"

  if [[ "$latest" == "v$VERSION" ]]; then
    echo "Already up to date (v$VERSION)"
    exit 0
  fi

  echo "Updating: v$VERSION -> $latest"
  local tmpdir
  tmpdir="$(mktemp -d)" || die "Could not create temp dir"

  gh release download "$latest" --repo "$GITHUB_REPO" \
    --pattern "hivemem" --dir "$tmpdir" \
    || { rm -rf "$tmpdir"; die "Download failed"; }

  chmod +x "$tmpdir/hivemem"
  mv -f "$tmpdir/hivemem" "$self"
  rm -rf "$tmpdir"
  echo "Updated to $latest"

  # Resolve source and re-install skills + hooks
  echo ""
  local source_dir
  source_dir="$(resolve_source_dir)"
  local cleanup_source=false
  [[ "$source_dir" != "$REPO_ROOT" ]] && cleanup_source=true

  install_skills "$source_dir"

  # Update global hooks
  if [[ -d "$HOME/.hivemem/hooks" ]]; then
    echo ""
    info "Updating global hooks"
    install_hooks "$source_dir" "$HOME/.hivemem"
  fi

  # Update project hooks if configured
  if [[ -d ".hivemem/hooks" ]]; then
    echo ""
    info "Updating project hooks"
    install_hooks "$source_dir" "$(pwd)/.hivemem"
  fi

  # Update Claude settings hooks
  if [[ -f "$HOME/.claude/settings.json" ]]; then
    echo ""
    info "Claude settings hooks"
    local hook_result
    hook_result="$(configure_settings_hooks "$HOME/.claude/settings.json" "$HOME/.hivemem")"
    if [[ "$hook_result" == "UPDATED" ]]; then
      ok "Hooks configured in ~/.claude/settings.json"
    else
      skip "Hooks already configured"
    fi
  fi

  $cleanup_source && rm -rf "$source_dir" || true
}
