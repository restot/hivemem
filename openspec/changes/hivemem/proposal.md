## Why

Mulch stores agent knowledge as flat files per-project. This means knowledge is siloed — agents in one client (Telegram bot, Claude Code, other agents) can't access what another learned. There's no search beyond filename, no cross-project querying, and no way to summarize or pipeline over accumulated knowledge. We need a centralized, searchable knowledge store accessible from all clients via MCP.

## What Changes

- Stand up a PostgreSQL instance with ParadeDB `pg_search` extension for full-text BM25 search
- Build a Rails MCP server exposing the knowledge store over Model Context Protocol
- Implement a knowledge record schema with rich metadata: project association, knowledge types (convention, pattern, decision, failure, reference, guide), free-form + structured tags, shortlinks for cross-referencing with beads
- Agent-optimized search UX: pre-filter by project/type/tags, BM25 rank, return (shortlink, summary, tags) — agents scan results without fetching full content
- All clients (bot, claude-code, agents) read/write through MCP tools over HTTPS transport (no stdio)

## Capabilities

### New Capabilities

- `knowledge-store`: PostgreSQL schema for knowledge records with metadata, tags, shortlinks, and BM25 indexing
- `mcp-server`: Rails MCP server exposing search, read, write, and tag operations to all clients
- `search`: BM25 full-text search with pre-filtering by project, type, and tags; returns (shortlink, summary, tags) per result
- `provisioning`: Docker-based PostgreSQL + pg_search setup for on-prem deployment

### Modified Capabilities

(none — greenfield project)

## Impact

- **Infrastructure**: New Docker container running PostgreSQL + pg_search, new Rails app for MCP server
- **Dependencies**: ParadeDB pg_search extension, Rails, MCP protocol libraries
- **Clients**: Telegram bot, Claude Code, and any future agents gain shared memory via MCP tool registration over HTTPS transport with auth (no stdio)
- **Data**: Replaces mulch flat-file approach — existing mulch data will need a migration path
- **APIs**: New MCP tool surface: search, record, tag, fetch operations
