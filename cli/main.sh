# =========================================================================
# Main dispatch
# =========================================================================
cmd="${1:-help}"
shift || true

case "$cmd" in
  setup)    cmd_setup "$@" ;;
  init)     cmd_init "$@" ;;
  search)   cmd_search "$@" ;;
  read)     cmd_read "$@" ;;
  write)    cmd_write "$@" ;;
  delete)   cmd_delete "$@" ;;
  prime)    cmd_prime "$@" ;;
  migrate)  cmd_migrate "$@" ;;
  validate) cmd_validate "$@" ;;
  status)   cmd_status "$@" ;;
  version)  cmd_version "$@" ;;
  update)   cmd_update "$@" ;;
  help|-h|--help) cmd_help ;;
  # Legacy alias
  onboard)  cmd_init "$@" ;;
  *) die "Unknown command: $cmd (run 'hivemem help')" ;;
esac
