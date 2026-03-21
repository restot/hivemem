## 1. Provisioning

- [x] 1.1 Create `docker-compose.yml` with ParadeDB PostgreSQL service (volume-mounted data dir, env vars for credentials)
- [x] 1.2 Add Rails app service to `docker-compose.yml` (depends_on postgres, env vars for DB connection and secret key)
- [x] 1.3 Verify `docker compose up` starts both services and pg_search extension is available

## 2. Rails App Bootstrap

- [x] 2.1 Generate new Rails app (API-only, PostgreSQL adapter)
- [x] 2.2 Configure `database.yml` to read from environment variables with Docker Compose defaults
- [x] 2.3 Evaluate and add MCP Ruby gem dependency (official `mcp` gem from modelcontextprotocol/ruby-sdk)
- [x] 2.4 Create Dockerfile for the Rails app

## 3. Knowledge Store Schema

- [x] 3.1 Create migration for `knowledge_records` table (id UUID, shortlink, title, summary, content, knowledge_type, project, tags array, created_by, timestamps)
- [x] 3.2 Add unique index on `shortlink`, indexes on `project`, `knowledge_type`
- [x] 3.3 Create migration to enable pg_search extension and create BM25 index over title, summary, content, tags
- [x] 3.4 Implement `KnowledgeRecord` model with shortlink generation (hm-<base62>), validations

## 4. Knowledge Store Operations

- [x] 4.1 Implement create operation: generate shortlink, validate required fields, persist record
- [x] 4.2 Implement read operation: fetch by shortlink
- [x] 4.3 Implement update operation: update mutable fields by shortlink, bump updated_at
- [x] 4.4 Implement hard-delete operation: destroy record by shortlink
- [x] 4.5 Implement tag management: add/remove tags atomically on a record

## 5. Search

- [x] 5.1 Implement BM25 search query using pg_search: full-text search over title, summary, content, tags
- [x] 5.2 Implement pre-filters: project, knowledge_type, tags (AND logic) applied before BM25 ranking
- [x] 5.3 Implement search result formatting: return (shortlink, title, summary, tags, knowledge_type, project, score) — no content
- [x] 5.4 Implement browse/list operation: list records without a query (filter-only by project, knowledge_type, tags), sorted by updated_at
- [x] 5.5 Implement pagination (limit/offset, default limit=20)

## 6. MCP Server

- [x] 6.1 Add MCP protocol gem/library dependency to Rails app
- [x] 6.2 Implement `hivemem_search` tool: accepts query + optional filters, returns ranked results
- [x] 6.3 Implement `hivemem_read` tool: accepts shortlink, returns full record
- [x] 6.4 Implement `hivemem_write` tool: accepts record fields, creates and returns record with shortlink
- [x] 6.5 Implement `hivemem_update` tool: accepts shortlink + fields (including tag add/remove), returns updated record
- [x] 6.6 Implement `hivemem_delete` tool: accepts shortlink, hard-deletes record
- [x] 6.7 Implement MCP tool registration (expose all five tools with input schemas)
- [x] 6.8 Add streamable HTTP transport support (for remote clients like Telegram bot)
- [x] 6.9 Implement bearer token authentication for MCP server endpoints
- [x] 6.10 Implement health check endpoint
- [x] 6.11 Create `.env.example` with required environment variables
- [x] 6.12 Implement structured MCP error responses for invalid input, not-found, and server errors

## 7. Integration Testing

- [x] 7.1 Test full lifecycle: docker compose up → create record → search → read → update → delete
- [x] 7.2 Test BM25 search relevance: create multiple records, verify ranking matches expected order
- [x] 7.3 Test pre-filter + search combinations: project filter, type filter, tag filter, combined filters
- [x] 7.4 Test MCP tool discovery: connect client, verify all five tools listed with correct schemas
- [x] 7.5 Test HTTP transport MCP connection
