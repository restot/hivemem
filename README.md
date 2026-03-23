# Hivemem

Persistent knowledge store for AI coding agents. Mulch-compatible schema, exposed via MCP.

## Install CLI

```bash
gh release download --repo restot/hivemem --pattern hivemem --dir ~/.local/bin && chmod +x ~/.local/bin/hivemem
```

## Quick Start

```bash
# 1. Bootstrap server (TLS, auth, MCP config)
hivemem setup

# 2. Start services
docker compose up -d

# 3. Onboard a project
cd ~/my-project
hivemem onboard .

# 4. (Optional) Migrate from mulch
hivemem migrate . --dry-run   # preview
hivemem migrate .             # execute
```

## Architecture

```
┌─────────────────┐     MCP/HTTP      ┌──────────────┐
│  Claude Code    │ ◄──────────────► │  Rails API   │
│  (skills/tools) │    JSON-RPC       │  port 3000   │
└─────────────────┘                   └──────┬───────┘
                                             │
                                      ┌──────▼───────┐
                                      │  ParadeDB    │
                                      │  (PG + BM25) │
                                      └──────────────┘
```

- **Rails 8.1 API** — MCP streamable HTTP transport, bearer token auth
- **ParadeDB** — PostgreSQL with `pg_search` extension for BM25 full-text search
- **5 MCP tools** — search, read, write, update, delete

## Record Schema

Mulch-compatible. All record types share a common schema.

| Field | Type | Required | Description |
|---|---|---|---|
| `shortlink` | string | auto | Unique ID (e.g. `hm-abc1234`) |
| `title` | string | yes | Short descriptive title |
| `content` | text | yes | Full record body |
| `knowledge_type` | enum | yes | `convention`, `pattern`, `decision`, `failure`, `reference`, `guide` |
| `classification` | enum | yes | `foundational` (permanent), `tactical` (default), `observational` (short-term) |
| `project` | string | yes | Project identifier |
| `summary` | text | no | 1-3 sentence summary for search results |
| `tags` | string[] | no | Free-form tags |
| `evidence` | jsonb | no | `{commit, date, issue, file, bead}` |
| `relates_to` | string[] | no | Shortlinks of related records |
| `supersedes` | string[] | no | Shortlinks of records this replaces |
| `outcomes` | jsonb[] | no | `[{status, duration, test_results, agent, notes, recorded_at}]` |
| `metadata` | jsonb | no | Type-specific: `resolution` (failure), `rationale` (decision), `files` (pattern/reference) |
| `created_by` | string | no | Actor identifier |
| `created_at` | datetime | auto | |
| `updated_at` | datetime | auto | |

## CLI Commands

| Command | Description |
|---|---|
| `hivemem setup` | Bootstrap server (TLS certs, auth token, MCP config) |
| `hivemem onboard [PATH]` | Onboard a project (install skills + CLAUDE.md) |
| `hivemem init` | Install skills, configure MCP, set up hooks |
| `hivemem prime [PROJECT]` | Output project knowledge (auto-runs via hooks) |
| `hivemem migrate [PATH]` | Import mulch records into hivemem |
| `hivemem validate` | Check record health (pre-commit hook) |
| `hivemem status` | Check server health |
| `hivemem update` | Self-update from GitHub releases |

## Skills

Installed to `~/.claude/skills/` by `hivemem init`:

| Skill | Description |
|---|---|
| `/hm-prime` | Load project knowledge into session context |
| `/hm-record` | Create a new knowledge record |
| `/hm-search` | Search with BM25 + filters |
| `/hm-read` | Read a record by shortlink |
| `/hm-status` | Show store statistics |

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `HIVEMEM_URL` | `https://localhost:3000/mcp` | MCP endpoint |
| `HIVEMEM_AUTH_TOKEN` | (from `.env`) | Bearer token |
| `HIVEMEM_PROJECT_ROOT` | (auto-detected) | Server project root |
| `DB_HOST` | `db` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `hivemem` | Database user |
| `DB_PASSWORD` | `hivemem` | Database password |
| `DB_NAME` | `hivemem_development` | Database name |

## Development

```bash
docker compose up -d
docker compose exec web bin/rails db:migrate
curl -s http://localhost:3000/health
```

## Mulch Migration

Hivemem uses the same record types and classification levels as mulch.
The `hivemem migrate` command reads `.mulch/expertise/*.jsonl` and imports records
with full field mapping:

| Mulch | Hivemem |
|---|---|
| `type` | `knowledge_type` |
| `content` / `description` | `content` |
| `name` | `title` |
| `classification` | `classification` |
| `tags` | `tags` |
| `evidence` | `evidence` |
| `relates_to` | `relates_to` |
| `supersedes` | `supersedes` |
| `files` | `metadata.files` |
| `resolution` (failure) | `metadata.resolution` |
| `rationale` (decision) | `metadata.rationale` |
| `date` (decision) | `metadata.date` |
