# Hivemem

Persistent knowledge store for AI coding agents.

Coding agents start every session with no memory of the last one. Hivemem gives them a
searchable store of conventions, decisions, patterns and past failures, plus an automatic
record of the conversations that produced them — injected into context at session start,
so you stop re-explaining the same project to the same agent.

Mulch-compatible record schema. BM25 full-text search out of the box, with optional
semantic and hybrid search when a local inference host is available.

---

## Contents

- [How it works](#how-it-works)
- [Install](#install)
- [Quick start](#quick-start)
- [Search modes](#search-modes)
- [CLI reference](#cli-reference)
- [Skills](#skills)
- [Hooks](#hooks)
- [Conversation indexing](#conversation-indexing)
- [Record schema](#record-schema)
- [Optional: semantic and hybrid search](#optional-semantic-and-hybrid-search)
- [Configuration](#configuration)
- [Server API](#server-api)
- [Admin UI](#admin-ui)
- [Deployment](#deployment)
- [Development](#development)
- [Migrating from mulch](#migrating-from-mulch)

---

## How it works

```
┌──────────────────┐
│   Claude Code    │
│                  │
│  skills  hooks   │
└────────┬─────────┘
         │  shell out
         ▼
┌──────────────────┐   MCP JSON-RPC    ┌──────────────┐
│  hivemem CLI     │ ────────────────► │  Rails API   │
│  (bash, single   │   POST /mcp       │  port 3055   │
│   file)          │   Bearer token    │  (TLS)       │
└──────────────────┘                   └──────┬───────┘
                                              │
                                       ┌──────▼───────┐
                                       │   ParadeDB   │
                                       │  PG + BM25   │
                                       │  + pgvector  │
                                       └──────────────┘
```

Claude Code never talks to the server directly. Skills and hooks shell out to the
`hivemem` CLI, which is a single self-contained bash script that speaks MCP JSON-RPC to
the Rails server. There is no `.mcp.json` registration and no MCP client configuration in
Claude Code — that was removed in v0.5.0. The server still exposes a standard MCP
endpoint, so other MCP clients can use it directly if you want.

- **Rails 8.1 API** (Ruby 3.4.4) — MCP streamable HTTP transport, bearer-token auth
- **ParadeDB** — PostgreSQL with the `pg_search` extension for BM25, plus `pgvector`
- **5 MCP tools** — search, read, write, update, delete

---

## Install

### CLI

```bash
gh release download --repo restot/hivemem --pattern hivemem --dir ~/.local/bin \
  && chmod +x ~/.local/bin/hivemem
```

Requires `bash`, `curl`, `python3`, and `jq`. `gh` is needed only for `version` and
`update`.

### Server

Clone the repo — the server runs from it, and `hivemem setup` writes TLS certs and the
auth token into the working copy.

```bash
git clone https://github.com/restot/hivemem.git
cd hivemem
```

---

## Quick start

```bash
# 1. Bootstrap the server: TLS certs, auth token, global config
hivemem setup

# 2. Start it
docker compose up -d
docker compose exec web bin/rails db:migrate

# 3. Verify
hivemem status

# 4. Wire up Claude Code (installs skills + hooks globally)
hivemem init
```

`hivemem init` is global by default and applies to every project. Use `--local` from
inside a project to scope hooks and config to that project instead.

> `hivemem onboard` still exists as a legacy alias for `init`. It does **not** take a
> path argument — `hivemem onboard .` will fail. Use `hivemem init` (or `cd` into the
> project and run `hivemem init --local`).

---

## Search modes

Three tiers. Only the first is enabled by default; the other two need an inference host
(see [Optional: semantic and hybrid search](#optional-semantic-and-hybrid-search)).

| Mode | Flag | Requires | What it does |
|---|---|---|---|
| BM25 | *(default)* | nothing | ParadeDB full-text ranking. Fast, exact-term. |
| Vector | `--vector` | embeddings endpoint | pgvector cosine similarity over embedded chunks. Finds semantic matches that share no keywords. |
| Hybrid | `--query` | embeddings endpoint | Query expansion → BM25 + vector → Reciprocal Rank Fusion → LLM reranking. |

```bash
hivemem search "auth token rotation"            # BM25
hivemem search "auth token rotation" --vector   # semantic
hivemem search "auth token rotation" --query    # hybrid
```

**Graceful degradation.** Hybrid search runs whatever stages are available. If the
inference host is missing or fails, it falls back to BM25 and reports which stages were
skipped in a `degraded` field:

```json
{"results":[...],"total":30,"mode":"query","degraded":["expansion","vector","rerank"]}
```

A BM25-only result set is therefore never silently mistaken for a full hybrid one.
`--vector` has nothing to fall back to, so it fails loudly instead.

---

## CLI reference

Run `hivemem help` for the built-in version.

### Server lifecycle

| Command | Description |
|---|---|
| `hivemem setup [--hostname NAME]` | Generate TLS CA + server certs into `certs/`, write `HIVEMEM_AUTH_TOKEN` to `.env`, write `~/.hivemem/config`, trust the CA (macOS keychain). Idempotent. `--hostname` adds an extra SAN. |
| `hivemem status` | Server health, installed skill count, which config file is in effect. |
| `hivemem version` | Print version, check GitHub for a newer release. Needs `gh`. |
| `hivemem update` | Self-update from GitHub releases, then refresh skills and hooks. Needs `gh`. |
| `hivemem help` | Built-in help. |

### Claude Code integration

| Command | Description |
|---|---|
| `hivemem init [--global\|--local] [--server URL]` | Install skills, hook scripts, config, and register hooks in `settings.json`. `--global` (default) targets `~/.claude/`; `--local` targets the current project. |
| `hivemem onboard` | Legacy alias for `init`. Takes no path argument. |

### Records

| Command | Description |
|---|---|
| `hivemem search [QUERY] [OPTIONS]` | Search records. Bare words become the query. |
| `hivemem read <SHORTLINK>` | Print a full record as JSON. |
| `hivemem write [OPTIONS]` | Create a record. |
| `hivemem delete <SHORTLINK>` | Delete a record. |

**`search` options**

| Flag | Default | Description |
|---|---|---|
| `--project`, `-p NAME` | *(all)* | Filter by project |
| `--type`, `-t TYPE` | *(all)* | Filter by knowledge type |
| `--tag TAG` | — | Filter by tag; repeatable, AND logic |
| `--limit`, `-l N` | `25` | Max results |
| `--vector` | — | Semantic vector search |
| `--query` | — | Hybrid BM25 + vector + rerank |

**`write` options**

| Flag | Default | Description |
|---|---|---|
| `--project`, `-p NAME` | cwd basename | Project identifier |
| `--type`, `-t TYPE` | *(required)* | Knowledge type |
| `--title TEXT` | *(required)* | Record title |
| `--content TEXT` | title | Record body |
| `--summary TEXT` | — | 1–3 sentence summary shown in search results |
| `--classification CLASS` | `tactical` | `foundational`, `tactical`, or `observational` |
| `--tag TAG` | — | Tag; repeatable |
| `--evidence-commit SHA` | — | Shorthand for `--evidence '{"commit":"SHA"}'` |
| `--evidence JSON` | — | Raw evidence object |
| `--metadata JSON` | — | Type-specific metadata object |

### Context priming

`hivemem prime [PROJECT] [OPTIONS]` — output project knowledge, formatted for injection
into an agent's context. Runs automatically via the `SessionStart` and `PreCompact`
hooks. `PROJECT` defaults to the cwd basename.

| Flag | Default | Description |
|---|---|---|
| `--compact` | default | One line per record |
| `--full` | — | Grouped by type with headers |
| `--format FMT` | `markdown` | `markdown`, `xml`, `plain`, or `json` |
| `--json` / `--xml` / `--plain` | — | Shorthand for `--format` |
| `--context` | — | Filter to records relevant to current git changes |
| `--files <paths...>` | — | Filter to records relevant to specific files |
| `--domain <names...>` | — | Include only these domains (matched on first tag) |
| `--exclude-domain <names...>` | — | Exclude these domains |
| `--budget <tokens>` | `4000` | Token budget; `0` means unlimited |
| `--no-limit` | — | Alias for `--budget 0` |

### Maintenance

| Command | Description |
|---|---|
| `hivemem migrate [PATH] [--dry-run]` | Import mulch records from `<PATH>/.mulch/expertise/*.jsonl`. |
| `hivemem validate [--quiet\|-q]` | Check record health for the current project. Non-zero exit on failure — usable as a pre-commit hook. |

---

## Skills

Installed by `hivemem init` to `~/.claude/skills/<name>/SKILL.md`. Skills are **always
global**, even with `--local` — only hooks and config are scoped.

| Skill | Description |
|---|---|
| `/hm-prime` | Load project knowledge into the session |
| `/hm-record` | Create a record; with no arguments, scans the session for learnings and records all of them |
| `/hm-search` | Search, parsing `project:`, `type:` and `#tag` filters out of the query |
| `/hm-read` | Read a record by shortlink |
| `/hm-status` | Store statistics — counts by project, type, and top tags |

Each skill shells out to the CLI. `init` also removes the pre-v0.5.0 flat-file commands
at `~/.claude/commands/hm-*.md`.

---

## Hooks

`hivemem init` writes two scripts to `~/.hivemem/hooks/` (or `<project>/.hivemem/hooks/`
with `--local`) and registers them in the corresponding `settings.json`. Registration
merges into any existing hooks and strips stale hivemem entries.

| Event | Script | Timeout | Purpose |
|---|---|---|---|
| `SessionStart` | `pre-init.sh` | 15s | Runs `hivemem prime` and injects project knowledge into the new session |
| `PreCompact` | `pre-init.sh` | 15s | Re-injects knowledge before context compaction |
| `Stop` | `stop.sh` | 5s | Captures the conversation (see below) |

`stop.sh` backgrounds itself immediately and exits 0, so it never delays the Stop event.

---

## Conversation indexing

The `Stop` hook records each completed exchange as a `conversation` record, building a
searchable history of what was discussed and decided — the reason you can ask an agent
about a past decision instead of re-explaining it.

**What gets captured**, per turn: the user prompt, the agent's full text response, and a
one-line summary of each tool call.

**What gets filtered out:**

- System reminders, `<command-message>` / `<command-name>` scaffolding, and other
  hook-injected text — these aren't real user turns
- All tool *output*. Only the call is summarized: `Read: <path>`, `Edit: <path>`,
  `Bash: <command>`, `Grep: <pattern>`, `Task: <description>`, etc.
- `TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskGet`, `TaskList` — dropped entirely

**How it's stored:** `knowledge_type: conversation`, `classification: observational`,
title = first line of the user prompt truncated to 120 chars, and metadata carrying
`{session_id, turn_number, branch, commit}`.

**Deduplication** is client-side. A high-water mark of the last indexed turn is kept in
`~/.hivemem/state/<session_id>`, so re-running the hook won't re-index earlier turns.
This is per-machine: if that state directory is lost, or two machines index the same
session against one server, turns can be duplicated.

Requires `agent-watch` at `~/.claude/bin/agent-watch` to read the transcript. Without it
the hook exits quietly and nothing is captured.

---

## Record schema

Mulch-compatible. All record types share one schema.

| Field | Type | Required | Description |
|---|---|---|---|
| `shortlink` | string | auto | Unique ID, e.g. `hm-abc1234` |
| `title` | string | yes | Short descriptive title |
| `content` | text | yes | Full record body |
| `knowledge_type` | enum | yes | `convention`, `pattern`, `decision`, `failure`, `reference`, `guide`, `conversation` |
| `classification` | enum | yes | `foundational` (permanent), `tactical` (default), `observational` (short-term) |
| `project` | string | yes | Project identifier |
| `summary` | text | no | 1–3 sentence summary for search results |
| `tags` | string[] | no | Free-form tags |
| `evidence` | jsonb | no | `{commit, date, issue, file, bead}` |
| `relates_to` | string[] | no | Shortlinks of related records |
| `supersedes` | string[] | no | Shortlinks this record replaces |
| `outcomes` | jsonb[] | no | `[{status, duration, test_results, agent, notes, recorded_at}]` |
| `metadata` | jsonb | no | Type-specific: `resolution` (failure), `rationale` (decision), `files` (pattern/reference) |
| `created_by` | string | no | Actor identifier |
| `created_at` | datetime | auto | |
| `updated_at` | datetime | auto | |

`observational` is a labelling convention describing intent — there is no automatic
expiry or pruning.

---

## Optional: semantic and hybrid search

Everything below is opt-in. Hivemem runs BM25-only by default and needs no inference
host.

### How it works

Records are chunked and embedded on write (`after_save`, wrapped so a failure never
blocks the write). Curated records get one chunk from title + summary + content;
conversations get one chunk per turn. Embeddings are stored in `record_embeddings` with a
`model_id` tag so stale vectors can be found after a model change.

Hybrid search (`--query`) then runs: query expansion into 3–5 alternate phrasings → BM25
and vector search across every variant (original weighted 2×) → Reciprocal Rank Fusion
(`k=60`) → LLM reranking of the top 30 candidates.

### Option A — Docker Model Runner

Requires **Docker Desktop 4.40+**. Not available on OrbStack, Colima, or plain Docker
Engine, which have no `docker model` plugin.

```bash
docker compose -f docker-compose.yml -f docker-compose.models.yml up -d
```

This provisions three models and injects their endpoints automatically:

| Role | Model |
|---|---|
| Embeddings | `ai/embeddinggemma` (300M, 768-dim) |
| Reranker | `ai/qwen3-reranker:0.6B-Q4_K_M` |
| Query expander | `ai/qwen3:0.6B-Q4_K_M` |

### Option B — any OpenAI-compatible endpoint

Works on any runtime. Point hivemem at Ollama, llama.cpp, vLLM, or a remote host by
creating a `docker-compose.override.yml` (compose merges it automatically):

```yaml
services:
  web:
    environment:
      EMBEDDINGS_URL: http://host.docker.internal:11434/v1
      EMBEDDINGS_MODEL: embeddinggemma
      RERANKER_URL: http://host.docker.internal:11434/v1
      RERANKER_MODEL: qwen3
      EXPANDER_URL: http://host.docker.internal:11434/v1
      EXPANDER_MODEL: qwen3
```

The embedding column is fixed at 768 dimensions. A model with a different dimension
requires changing the migration.

### Verifying

```bash
docker compose exec web bin/rails runner 'puts EmbeddingClient.available?'
```

`false` means no endpoint is configured — searches will run BM25-only and report
`degraded`. Each client has a circuit breaker that opens after 3 consecutive failures
and retries after 60s, so an inference host that goes down degrades search rather than
stalling it.

### Backfilling

Embeddings are generated on write, so records created before you enabled inference have
none. There is no backfill command yet; re-saving is the current workaround:

```bash
docker compose exec web bin/rails runner \
  'KnowledgeRecord.needs_embedding.find_each(&:save!)'
```

---

## Configuration

### CLI

Resolution order: environment → project `.hivemem/config` → global `~/.hivemem/config` →
legacy `.mcp.json` → `.env`.

| Variable | Default | Description |
|---|---|---|
| `HIVEMEM_URL` | `https://localhost:3055` | Server base URL. The CLI appends `/mcp` itself — don't include it. |
| `HIVEMEM_AUTH_TOKEN` | from config/`.env` | Bearer token |
| `HIVEMEM_PROJECT_ROOT` | auto-detected | Path to the server working copy |

### Server

| Variable | Default | Description |
|---|---|---|
| `HIVEMEM_AUTH_TOKEN` | random, logged at boot | Bearer token. **If unset, the admin UI has no authentication.** |
| `PORT` | `3055` | Listen port |
| `RAILS_ENV` | `development` | Rails environment |
| `SECRET_KEY_BASE` | dev fallback | Required in production |
| `DB_HOST` | `db` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `hivemem` | Database user |
| `DB_PASSWORD` | `hivemem_dev` (dev) | Database password. No default in production. |
| `DB_NAME` | `hivemem_development` | Database name |
| `RAILS_MAX_THREADS` | `3` | Puma threads |
| `SSL_CERT_FILE` | `/rails/certs/server.pem` | TLS certificate |
| `SSL_KEY_FILE` | `/rails/certs/server-key.pem` | TLS private key |
| `EMBEDDING_MODEL_ID` | `embeddinggemma-300m-v1` | Version tag written to stored embeddings |
| `EMBEDDINGS_URL` | *(unset)* | Embeddings endpoint. Unset disables vector search. |
| `EMBEDDINGS_MODEL` | `ai/embeddinggemma` | Embedding model name |
| `RERANKER_URL` | *(unset)* | Reranker endpoint |
| `RERANKER_MODEL` | `ai/qwen3-reranker` | Reranker model name |
| `EXPANDER_URL` | *(unset)* | Query expander endpoint |
| `EXPANDER_MODEL` | `ai/qwen3` | Expander model name |

### TLS

`hivemem setup` generates a local CA and a `localhost` server certificate into `certs/`,
then trusts the CA in the macOS system keychain. Puma serves HTTPS whenever
`SSL_CERT_FILE` and `SSL_KEY_FILE` point at an existing file.

If `certs/` is empty, **Puma silently falls back to plain HTTP on the same port** — so a
server that appears to work may not be encrypted. Run `hivemem setup` before first start.

---

## Server API

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/mcp` | Bearer | MCP JSON-RPC endpoint. Also accepts `GET` and `DELETE` per the transport spec. |
| `GET` | `/health` | none | `{"status":"ok"}`, or `503` with `{"status":"error","message":"..."}` if the database is unreachable |
| `GET` | `/up` | none | Rails process-liveness check |

There is no REST CRUD API for records — the MCP tools are the interface.

### MCP tools

| Tool | Arguments |
|---|---|
| `hivemem_search_tool` | `query`, `mode` (`search`\|`vsearch`\|`query`), `project`, `knowledge_type`, `tags`, `classification`, `limit`, `offset`. Omitting `query` browses by `updated_at`. |
| `hivemem_read_tool` | `shortlink` |
| `hivemem_write_tool` | `title`, `content`, `knowledge_type`, `project` required; plus the optional schema fields |
| `hivemem_update_tool` | `shortlink` plus any field. Supports `add_tags`/`remove_tags`, `add_relates_to`, `add_supersedes`, and appending an `outcome`. Shallow-merges `metadata`. |
| `hivemem_delete_tool` | `shortlink` |

`hivemem_update_tool` has no CLI equivalent — reach it through an MCP client or a direct
JSON-RPC call.

Auth is a single shared bearer token compared in constant time. If `HIVEMEM_AUTH_TOKEN`
is unset the server generates a random one at boot and logs it to stderr.

---

## Admin UI

A read-mostly HTML dashboard at `/admin`:

- `/admin` — totals, breakdowns by project / type / classification, recent and stalest records, database size
- `/admin/records` — searchable and filterable list, 50 per page
- `/admin/records/:id` — full record detail, with delete

Authenticates via bearer header, a `?token=` parameter, or a session cookie set after the
first successful auth. **If `HIVEMEM_AUTH_TOKEN` is unset, the admin UI is completely
open** — always set it on any non-local deployment.

---

## Deployment

`docker-compose.prod.yml` pulls the prebuilt image instead of building locally:

```bash
docker compose -f docker-compose.prod.yml up -d
```

Images are published to `ghcr.io/restot/hivemem` (tagged `latest` and by commit SHA) by
the `Build and push` GitHub Actions workflow on every push to `main`. Prefix a commit
message with `[no-build]` to skip it.

Production differences: `RAILS_ENV=production`, the database port is not published, and
`SECRET_KEY_BASE` / `DB_PASSWORD` / `HIVEMEM_AUTH_TOKEN` have **no defaults**. Compose
substitutes an empty string for missing variables rather than failing, so verify `.env`
before deploying.

`bin/watchtower` is an optional host-side poller that redeploys when a new image digest
appears on GHCR and can post deploy notifications to Telegram.

> The CLI binary is **not** released by CI. Publish it manually:
> `./build.sh && gh release create v0.5.1 bin/hivemem --repo restot/hivemem`
> Bump `VERSION` in `cli/header.sh` first.

---

## Development

```bash
docker compose up -d
docker compose exec web bin/rails db:migrate
curl -sk https://localhost:3055/health
```

The CLI is assembled from `cli/*.sh` into a single distributable script:

```bash
./build.sh          # concatenates cli/*.sh -> bin/hivemem, syntax-checks it
```

Edit the modules in `cli/`, never `bin/hivemem` directly — it's a build artifact.

**The compose file does not bind-mount application code.** Only `certs/` is mounted, so
Ruby changes require a rebuild:

```bash
docker compose up -d --build web
```

**OrbStack** publishes each container at `<service>.<project>.orb.local` — for this repo,
`https://web.hivemem.orb.local:3055`. That hostname is allowed in development via a
regexp in `config/environments/development.rb`; the `config.hosts << ".orb.local"`
shorthand does **not** work, because Rails only matches one label deep and the OrbStack
name is two levels.

The `Dockerfile` is production-shaped: it bundles with `RAILS_ENV=production` and
`BUNDLE_WITHOUT=development`, so dev gems (`debug`, `brakeman`, `bundler-audit`,
`rubocop`) are not present in the image regardless of the runtime `RAILS_ENV`.

There is currently no Ruby test suite. `test/` holds `bats` tests covering CLI behavior.

---

## Migrating from mulch

Hivemem uses the same record types and classification levels as mulch. `hivemem migrate`
reads `.mulch/expertise/*.jsonl` and imports with full field mapping.

```bash
hivemem migrate . --dry-run   # preview
hivemem migrate .             # execute
```

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

### Upgrading from v0.3.x

Run `hivemem init`. It migrates `.mcp.json` to `.hivemem/config`, removes the hivemem
entry from `.mcp.json`, and warns about leftover `<!-- hivemem:start -->` blocks in
`CLAUDE.md` and a stale `NODE_EXTRA_CA_CERTS` setting. Legacy `.mcp.json` files are still
read as a fallback.
