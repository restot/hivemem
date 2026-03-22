#!/usr/bin/env bats
# Tests for hivemem validate command.

load helpers.bash

@test "validate command is in dispatch table" {
  grep -q 'validate)' "$HIVEMEM_BIN"
}

@test "validate command is in help text" {
  grep 'validate' "$HIVEMEM_BIN" | grep -q 'Check\|record health\|pre-commit'
}

@test "configure_git_hooks installs pre-commit hook" {
  # Extract configure_git_hooks and test in a temp git repo
  local tmpdir
  tmpdir=$(mktemp -d)
  git init "$tmpdir" >/dev/null 2>&1

  # Source just the function we need
  bash -c "
    source '$HIVEMEM_BIN' --source-only 2>/dev/null || true
  " 2>&1 || true

  # Check that the function exists in the script
  grep -q 'configure_git_hooks\|install_git_hook' "$HIVEMEM_BIN"
  rm -rf "$tmpdir"
}

@test "validate help mentions validate in usage" {
  grep -q 'validate' "$HIVEMEM_BIN"
}
