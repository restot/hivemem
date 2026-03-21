## Context

Agents (Telegram bot, Claude Code sessions, sub-agents) currently use mulch — a flat-file per-project knowledge store. Each project has its own `.mulch/` directory with YAML records. This creates knowledge silos: an agent working in project A cannot access lessons learned in project B. There is no full-text search, no cross-project querying, and no way to run pipelines (e.g. summarization) over accumulated knowledge. Hivemem replaces this with a centralized PostgreSQL-backed store accessible from all clients via MCP.

## Goals / Non-Goals

**Goals:**
- Centralized knowledge store accessible from all agent clients via MCP
- BM25 full-text search with pre-filtering by project, type, and tags
- Agent-optimized search UX: results return (shortlink, summary, tags) so agents triage without fetching full content
- Rich metadata: project association, knowledge types (convention, pattern, decision, failure, reference, guide), free-form + structured tags
- Shortlinks for cross-referencing between hivemem records and beads (e.g. hm-abc123 ↔ bd-xyz)
- Docker-based on-prem deployment

**Non-Goals:**
- Real-time sync or CRDT-based collaboration between agents
- Semantic/vector search (BM25 is sufficient for keyword-oriented agent queries)
- Web UI or dashboard (agents are the primary consumers)
- Replacing beads (bd) — hivemem complements it as the knowledge layer
- Mulch data migration tooling (future scope, not blocking v1)

## Decisions

### 1. PostgreSQL + pg_search over Elasticsearch or SQLite FTS

**Choice**: PostgreSQL with ParadeDB pg_search extension

**Rationale**: Single database for both structured data and full-text search. pg_search provides Elasticsearch-quality BM25 ranking inside Postgres — no separate search cluster. SQLite FTS5 lacks concurrent write support needed for multi-client access. Elasticsearch adds operational complexity (separate JVM process, cluster management) for what is fundamentally a single-node workload.

**Alternatives considered**:
- Elasticsearch: Better scaling but massive operational overhead for a single-user system
- SQLite FTS5: Simpler but no concurrent multi-client writes, no MCP-friendly server model
- Typesense: Good search but another service to manage, and we need relational data alongside search

### 2. Rails MCP server over raw HTTP API or embedded library

**Choice**: Rails app serving MCP protocol

**Rationale**: MCP is the standard protocol for agent-tool communication. Claude Code, the Telegram bot, and future agents all speak MCP natively. Rails provides ActiveRecord for clean PG interaction, background jobs for future summarization pipelines, and fast development. A raw HTTP API would require each client to implement its own adapter.

**Alternatives considered**:
- Raw HTTP/JSON API: Simpler but every client needs a custom adapter
- Embedded Ruby gem: No network access, can't serve multiple clients
- Python FastAPI: Viable but Rails has better ORM and background job ecosystem for this use case

### 3. Shortlink system for cross-referencing

**Choice**: `hm-<base62>` shortlinks, stored as a column on each record

**Rationale**: Agents need terse, unique identifiers to reference knowledge records in conversation and in beads. Base62 (alphanumeric) keeps links short. The `hm-` prefix distinguishes hivemem links from bead links (`bd-`). Shortlinks are generated at record creation and are immutable.

### 4. Tag-first search UX

**Choice**: Pre-filter by (project, type, tags) before BM25 ranking

**Rationale**: Agents scanning search results need to quickly assess relevance. Filtering narrows the candidate set before expensive BM25 scoring. Tags surface in results alongside the summary, letting agents pick the right record without reading full content. This is the core UX improvement over mulch's filename-only discovery.

### 5. Docker Compose for provisioning

**Choice**: Single `docker-compose.yml` with PostgreSQL (ParadeDB image) and Rails app as services

**Rationale**: On-prem, single-machine deployment. Docker Compose is the simplest orchestration for two services. ParadeDB publishes official Docker images with pg_search pre-installed. No Kubernetes needed for a single-user system. The Rails app exposes an HTTP port for MCP clients to connect to.

### 6. HTTPS-only transport with bearer token auth

**Choice**: Streamable HTTP transport only, with bearer token authentication

**Rationale**: All clients (Claude Code, Telegram bot, agents) connect over HTTP. Stdio is incompatible with the Docker deployment model (Rails runs in a container, can't be spawned as a subprocess). Bearer token auth is simple, sufficient for single-user on-prem, and supported by MCP spec. Token stored as env var on server, configured in each client's MCP config.

**Alternatives considered**:
- stdio: Incompatible with Docker — the MCP server runs in a container, not as a local subprocess
- mTLS: Overkill for single-user on-prem deployment
- OAuth: Unnecessary complexity for a system with one user

### 7. MCP Ruby library

**Choice**: Official `mcp` gem from modelcontextprotocol/ruby-sdk

**Rationale**: Maintained by the MCP org, supports streamable HTTP transport, safest long-term bet.

**Alternatives considered**:
- fast-mcp: Deeper Rails integration but third-party maintained
- model-context-protocol-rb: Less adoption and community support

## Risks / Trade-offs

- **[pg_search maturity]** → ParadeDB is relatively young. Mitigation: pg_search is a Postgres extension, so worst case we fall back to native `tsvector` GIN indexes with minor ranking quality loss.
- **[Single point of failure]** → One PG instance, no replication. Mitigation: Acceptable for single-user on-prem. Docker volume backups. Can add streaming replication later if needed.
- **[MCP protocol evolution]** → MCP spec is still evolving. Mitigation: Rails server wraps MCP in a thin transport layer; internal API is stable regardless of MCP wire format changes.
- **[Schema migrations under load]** → Agents may be writing while we deploy schema changes. Mitigation: Use PG advisory locks and online DDL (no table locks for additive changes). Rail zero-downtime migration patterns.

## Open Questions

- Record size limits: should we cap content length or let agents store arbitrarily large session transcripts?
- Summarization pipeline: scheduled cron job or triggered on write? Deferred to post-v1 but affects schema (need a `summarized_at` column).
