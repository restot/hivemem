# =========================================================================
# help
# =========================================================================
cmd_help() {
  cat <<'EOF'
hivemem — Portable CLI for hivemem knowledge store

Usage: hivemem <command> [args]

Commands:
  setup [--hostname NAME]         Bootstrap local server (TLS, auth, config)
  init [OPTIONS]                  Install skills, hooks, configure settings (global by default)
    --local                         Install to project instead of global
    --server URL                    Server URL (default: https://localhost:3055)
  search [QUERY] [OPTIONS]        Search knowledge records
    --project/-p NAME               Filter by project
    --type/-t TYPE                  Filter by knowledge type
    --tag TAG                       Filter by tag (repeatable)
    --limit/-l N                    Max results (default: 25)
  read <SHORTLINK>                Read a full record by shortlink
  write [OPTIONS]                 Create a knowledge record
    --project/-p NAME               Project name (default: cwd basename)
    --type/-t TYPE                  Knowledge type (required)
    --title TEXT                    Record title (required)
    --content TEXT                  Record content (default: title)
    --summary TEXT                  Brief summary for search results
    --classification CLASS          foundational|tactical|observational (default: tactical)
    --tag TAG                       Tag (repeatable)
    --evidence-commit SHA           Git commit SHA as evidence
  delete <SHORTLINK>              Delete a record by shortlink
  prime [PROJECT] [OPTIONS]       Output project knowledge (auto-runs via hooks)
    --compact                       One-line per record (default)
    --full                          Grouped by type with headers
    --format <markdown|xml|plain|json>  Output format (default: markdown)
    --context                       Filter to records relevant to git changes
    --files <paths...>              Filter to records relevant to specific files
    --domain <domains...>           Include only these domains (by first tag)
    --exclude-domain <domains...>   Exclude these domains
    --budget <tokens>               Token budget (default: 4000, 0 = no limit)
    --no-limit                      Alias for --budget 0
  migrate [PATH] [--dry-run]      Migrate mulch records into hivemem
  validate [--quiet]              Check record health (pre-commit hook)
  status                          Check server health and config
  version                         Show version, check for updates
  update                          Self-update from GitHub releases
  help                            Show this help

Config Precedence:
  Project .hivemem/config takes precedence over global ~/.hivemem/config.
  Default server: https://localhost:3055

Environment:
  HIVEMEM_URL              Server URL (overrides config files)
  HIVEMEM_AUTH_TOKEN       Auth token (overrides config files)
  HIVEMEM_PROJECT_ROOT     Server project root (auto-detected)

Install:
  gh release download --repo restot/hivemem --pattern hivemem --dir ~/.local/bin \
    && chmod +x ~/.local/bin/hivemem

Migration:
  Users upgrading from v0.3.x: run 'hivemem init' to migrate from
  .mcp.json to .hivemem/config. Legacy .mcp.json configs are read as
  fallback and migrated automatically during init.

Quick start:
  # Server setup (one-time)
  cd ~/path/to/hivemem && hivemem setup && docker compose up -d

  # Install globally (default — works for all projects)
  hivemem init

  # Or install for a specific project only
  hivemem init --local
EOF
}
