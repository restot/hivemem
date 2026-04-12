# Proposal: Conversation Indexing for Hivemem

## Problem

Agents start every session cold. Knowledge from previous conversations — architecture decisions, failed approaches, debugging context, conventions discussed but never recorded — is lost. hivemem's manual recording captures maybe 10-20% of useful context, biased toward what the agent deemed important, not what you'll need three weeks later in a different project.

## Solution

Ingest Claude Code session transcripts into hivemem as searchable, BM25-indexed records. Each user prompt → agent response turn becomes one record. Tool outputs are stripped to keep tokens low while preserving intent and actions. Data flows live via hooks during the session, with backfill via `agent-watch` for historical sessions.

## Data Model

New `knowledge_type: "conversation"` in the existing `knowledge_records` table. Requires adding the value to the `KNOWLEDGE_TYPES` whitelist in `knowledge_record.rb` and updating tool descriptions that enumerate valid types.

```
title:          First line of user prompt (truncated to 120 chars)
content:        Filtered turn content (see Content Filtering below)
knowledge_type: "conversation"
classification: "observational" (auto-expires after 30 days)
project:        Detected from session's working directory
tags:           Auto-extracted (file extensions touched, commands used, error types)
metadata: {
  session_id:   "abc123",
  turn_number:  3,
  timestamp:    "2026-04-08T14:30:00Z",
  branch:       "feature/auth-fix",
  commit:       "a1b2c3d",
  files_read:   ["app/models/user.rb", "config/routes.rb"],
  files_edited: ["app/controllers/auth_controller.rb"],
  commands_run: ["bundle exec rspec spec/auth_spec.rb"],
  tasks_spawned: 2
}
```

### Deduplication

By `session_id` in metadata. Shortlinks remain random (existing behavior). Dedup query: check if any record exists with `metadata->>'session_id' = X AND metadata->>'turn_number' = Y` before inserting.

### Scoping & Ranking

Conversation records are ranked by date (most recent = most relevant), then scoped by:
- **Project** — default scope, matches session's working directory
- **Branch** — narrows to feature-branch context
- **Worktree** — for multi-worktree setups

This differs from curated records (ranked by BM25 relevance). Conversations are temporal context; curated records are durable knowledge. Both participate in search but serve different retrieval patterns.

### Classification Strategy

- Default: `observational` (expires 30 days) — most conversations are tactical
- `hivemem promote <shortlink>` — upgrade to `tactical` or `foundational` if it turns out to be important
- Bulk cleanup via existing `hivemem prune`

## Content Filtering

Each turn is filtered to preserve intent while minimizing tokens. Thinking blocks are dropped entirely.

| Tool | Keep | Drop |
|------|------|------|
| User prompt | Full text | — |
| Agent text | Full text (reasoning, explanations, decisions) | — |
| Thinking | — | Entire block |
| Read | `Read: <file_path>` | File contents |
| Edit | `Edit: <file_path>` | Old/new strings |
| Write | `Write: <file_path>` | File contents |
| Bash | `Bash: <command>` | Command output |
| Grep/Glob | `Search: <pattern> in <path>` | Results |
| Agent/Task | `Task: <description>` | Sub-agent transcript |
| WebFetch | `Fetch: <url>` | Page content |
| ToolSearch | `ToolSearch: <query>` | Tool definitions |
| Skill | `Skill: <name>` | Skill output |
| LSP | `LSP: <method>` | Response |
| system-reminder | — | Entire block (hook output, not user intent) |
| queue-operation | — | Skip entirely |

**Note:** Bash commands are kept verbatim including any secrets/tokens in them. This is intentional — they're valuable for finding credentials later.

Filtering rules will be refined by examining real transcript data before implementation.

### Example filtered turn

Raw session: ~15,000 tokens. Filtered:

```
User: fix the auth bug in login.rb where tokens aren't being compared securely

Agent: The token comparison on line 42 uses `==` which is vulnerable to timing
attacks. Changing to `secure_compare` and adding a test.

Read: app/controllers/sessions_controller.rb
Read: test/controllers/sessions_test.rb
Edit: app/controllers/sessions_controller.rb
Bash: bundle exec ruby -Itest test/controllers/sessions_test.rb
Edit: app/controllers/sessions_controller.rb
Bash: bundle exec ruby -Itest test/controllers/sessions_test.rb
```

~200 tokens. BM25 still catches "auth bug", "timing attack", "secure_compare", "sessions_controller".

## Ingestion

### Live ingestion (primary)

Data flows via Claude Code hooks during the session. A `PostToolUse` or `SessionEnd` hook collects the current turn's filtered content and POSTs it to hivemem.

### Backfill (historical)

For existing sessions, `agent-watch` provides parsed transcript data. The CLI reads from agent-watch output rather than parsing JSONL directly — agent-watch already handles the complex message reconstruction (parentUuid chains, split messages, thinking blocks).

```bash
# Backfill a specific session
hivemem ingest <session-id>

# Backfill recent sessions
hivemem ingest --recent [N]

# Backfill all sessions for a project
hivemem ingest --project <name>

# Preview
hivemem ingest <session-id> --dry-run

# Re-ingest (overwrite)
hivemem ingest <session-id> --force
```

## Retrieval

### Search (existing, works unchanged)

```bash
hivemem search "timing attack auth"
```

BM25 finds conversation turns alongside curated records.

### Conversation browser (new)

```bash
# List ingested sessions
hivemem sessions [--project <name>] [--limit N]

# View filtered turns for a session
hivemem session <session-id>

# View a specific turn
hivemem turn <shortlink>
```

### Prime integration

`hivemem prime` shows a "Recent Conversations" section, ranked by date within project/branch scope:

```
## Recent Conversations
- [hm-x1y2z3] fix auth timing attack in sessions_controller (3 days ago)
- [hm-a4b5c6] debug TLS cert trust on macOS (5 days ago)
```

## Server-Side Changes

### Model

Add `"conversation"` to `KNOWLEDGE_TYPES` in `knowledge_record.rb`.

### Scopes

Add scopes for conversation retrieval:

```ruby
scope :conversations, -> { where(knowledge_type: "conversation") }
scope :for_session, ->(sid) { conversations.where("metadata->>'session_id' = ?", sid) }
scope :recent_conversations, ->(project:, limit: 20) {
  conversations.where(project: project).order(created_at: :desc).limit(limit)
}
```

### API

Extend existing search/write endpoints. One new grouped endpoint for session browser:

```
GET /api/sessions?project=myproject&limit=20
```

### MCP tools

Update `hivemem_search_tool.rb` and `hivemem_write_tool.rb` descriptions to include `"conversation"` in valid types. No new tools needed.

## Implementation Plan

### Phase 1: Core (MVP)
1. Add `"conversation"` to model whitelist + update tool descriptions
2. Content filtering logic (turn → filtered text)
3. `ingest` CLI command using agent-watch for transcript parsing
4. Dedup by session_id + turn_number in metadata
5. `--dry-run` flag

### Phase 2: Live + Retrieval
6. SessionEnd hook for live ingestion
7. `sessions` / `session` / `turn` browser commands
8. Update `prime` to include recent conversations section
9. Date-based ranking for conversation records in prime

### Phase 3: Polish
10. `promote` command (change classification)
11. Branch/worktree scoping in search and prime
12. Auto-tag extraction from filtered content
