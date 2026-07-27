# Proposal: Hybrid Search with Vector Embeddings, Reranking, and Query Expansion

## Problem

Hivemem's BM25-only search works well for curated records where the author controls vocabulary. With conversation indexing, the corpus grows to include raw agent transcripts — messy natural language where terminology is unpredictable. Searching "unbound variable" won't find a conversation that said "the array blows up when empty." BM25 can't bridge vocabulary mismatch.

## Solution

Add vector search, LLM reranking, and query expansion alongside existing BM25. Three search tiers:

| Tier | Method | Use Case |
|------|--------|----------|
| `search` | BM25 only | Fast exact-term lookup (existing behavior) |
| `vsearch` | Vector only | Semantic similarity when you don't know the terms |
| `query` | BM25 + vector + query expansion + reranking | Best quality, highest latency |

Default behavior: `search` stays BM25 for backward compatibility. `query` is the new premium tier, recommended for conversation-heavy searches.

## Architecture

```
Docker Compose
├── app (Rails + Puma :3055)
│   ├── BM25 search (ParadeDB @@@ operator)
│   ├── Vector search (pgvector cosine distance)
│   ├── RRF fusion (merge BM25 + vector ranked lists)
│   └── Reranker client (HTTP → DMR chat completions)
│
├── db (ParadeDB — BM25 + pgvector)
│
└── Docker Model Runner (llama.cpp backend, Metal)
    ├── ai/embeddinggemma (300M, ~300MB) — embeddings
    ├── ai/qwen3:0.6B — reranking (generative, via chat completions)
    └── ai/qwen3:0.6B — query expansion (via chat completions)
```

All models run through DMR with Metal GPU acceleration. No sidecar containers. Qwen3-Reranker-0.6B is a generative reranker — it outputs "yes"/"no" tokens. We load it in DMR as a regular chat model and score documents by extracting the "yes" logprob from the response. This keeps the entire inference stack on Metal.

### Model Stack (matching QMD)

| Role | Model | Format | Size | Source |
|------|-------|--------|------|--------|
| Embeddings | embeddinggemma-300M | GGUF | ~300MB | `docker model pull ai/embeddinggemma` |
| Reranker | Qwen3-Reranker-0.6B | GGUF Q4_K_M | ~395MB | `docker model pull ai/qwen3-reranker` |
| Query expansion | Qwen3-0.6B | GGUF | ~395MB | `docker model pull ai/qwen3` |

Total model footprint: ~1.1GB (reranker and expander share the Qwen3 architecture). All local, all Metal-accelerated, no API keys, no CPU-only sidecar containers.

## Data Model Changes

### New table: `record_embeddings`

Curated records (convention, pattern, decision, etc.) are short — a single embedding per record suffices. Conversations are long and variable — they need chunked embeddings so semantic search can match specific parts of a transcript.

```ruby
# Migration
enable_extension "vector"

create_table :record_embeddings, id: :uuid do |t|
  t.references :knowledge_record, type: :uuid, null: false, foreign_key: true, index: true
  t.vector :embedding, limit: 768          # embeddinggemma dims
  t.integer :chunk_index, null: false       # 0 for single-chunk records
  t.text :chunk_text, null: false           # the text that was embedded
  t.string :model_id, null: false           # e.g. "embeddinggemma-300m-v1"
  t.timestamps
end

add_index :record_embeddings, :embedding, using: :hnsw, opclass: :vector_cosine_ops
add_index :record_embeddings, :model_id
```

**HNSW over IVFFlat:** IVFFlat trains on existing data at index creation — useless on an empty table. HNSW works immediately on insert, no training step.

**`model_id` column:** Tracks which model generated each embedding. When the embedding model changes, stale vectors are identifiable and can be re-embedded incrementally. Query: `WHERE model_id != current_model_id` to find records needing re-embedding.

### Chunking Strategy

| Record type | Strategy |
|-------------|----------|
| Curated (convention, pattern, etc.) | Single chunk: `title + summary + content` |
| Conversation | Split by turn boundaries (user prompt → agent response = one chunk). Each chunk gets its own embedding row. |

Conversation turns are natural semantic boundaries — each is a self-contained question+answer. A 20-turn conversation produces 20 embedding rows, each searchable independently. Search hits a chunk, returns the parent `knowledge_record`.

Chunk text is capped at embeddinggemma's context window (~2048 tokens). Individual turns rarely exceed this. If one does, split at paragraph boundaries.

### Embedding generation (eager, on write)

```ruby
# In KnowledgeRecord model
after_save :generate_embeddings, if: -> {
  saved_change_to_title? || saved_change_to_summary? || saved_change_to_content?
}

def generate_embeddings
  chunks = EmbeddingChunker.chunk(self)
  record_embeddings.destroy_all

  chunks.each_with_index do |chunk_text, i|
    vector = EmbeddingClient.embed(chunk_text)
    record_embeddings.create!(
      embedding: vector,
      chunk_index: i,
      chunk_text: chunk_text,
      model_id: EmbeddingClient.current_model_id
    )
  end
rescue StandardError => e
  Rails.logger.error("Embedding generation failed for #{shortlink}: #{e.message}")
  # Never let embedding failures break writes
end
```

Uses `saved_change_to_*?` (not `content_changed?` which resets after save). Wrapped in rescue — embedding failures log but never block record creation.

### Model Warmup

DMR loads models into GPU memory on first request after restart (~2-5s for 300MB model). To avoid blocking the first write:

```ruby
# config/initializers/embedding_warmup.rb
Rails.application.config.after_initialize do
  next unless ENV["EMBEDDINGS_URL"].present?

  Thread.new do
    sleep 2 # wait for DMR to be ready
    EmbeddingClient.embed("warmup")
    Rails.logger.info("Embedding model warmed up")
  rescue => e
    Rails.logger.warn("Embedding warmup failed: #{e.message}")
  end
end
```

`EmbeddingClient` calls DMR at `http://model-runner.docker.internal:12434/engines/v1/embeddings`.

## Search Flow

### Tier 1: `search` (BM25 only, existing)

No change. Uses ParadeDB `@@@` operator with `paradedb.score(id)`.

### Tier 2: `vsearch` (vector only)

```sql
SELECT kr.*, 1 - (re.embedding <=> query_embedding) AS vector_score
FROM record_embeddings re
JOIN knowledge_records kr ON kr.id = re.knowledge_record_id
WHERE kr.project = ?
  AND re.model_id = 'embeddinggemma-300m-v1'
ORDER BY re.embedding <=> query_embedding
LIMIT 20
```

`<=>` is pgvector's cosine distance operator. Score is `1 - distance` so higher = better. Filters by `model_id` to ensure only current-model embeddings are searched. Chunks from the same record are deduplicated — best-scoring chunk wins.

### Tier 3: `query` (hybrid + reranking)

Full pipeline:

```
1. Query expansion
   Input:  "tags unbound variable"
   Output: ["bash array empty error", "set -u unset parameter", "shell parameter expansion"]
   Model:  Qwen3-0.6B via DMR chat completions
   Weight: original query 2x, expansions 1x

2. BM25 search (all query variants)
   → ranked list A (scored by paradedb.score)

3. Vector search (all query variants)
   → ranked list B (scored by cosine similarity)

4. Reciprocal Rank Fusion (RRF)
   score(d) = sum( 1 / (k + rank_in_list) ) for each list containing d
   k = 60 (standard RRF constant)
   → merged ranked list C, top 30 candidates

5. Reranker (generative, via DMR chat completions)
   For each of the top 30 candidates, call Qwen3-Reranker-0.6B with:
     system: "Judge whether the document is relevant to the query. Reply yes or no."
     user: "Query: {query}\nDocument: {document_text}"
   Extract logprob of "yes" token → relevance score 0-1
   Model: Qwen3-Reranker-0.6B via DMR (Metal-accelerated, no CPU sidecar)
   → reranker scores replace RRF scores for final ordering
```

Reranker scores are the final ranking signal — they replace, not blend with, retrieval scores. Cross-encoders exist specifically because retrieval scores are unreliable for fine-grained ordering.

## Docker Compose Changes

```yaml
models:
  embeddings:
    model: ai/embeddinggemma
    context_size: 512
    runtime_flags:
      - "--embeddings"

  reranker:
    model: ai/qwen3-reranker:0.6B-Q4_K_M
    context_size: 2048

  expander:
    model: ai/qwen3:0.6B-Q4_K_M
    context_size: 2048

services:
  app:
    # ... existing config ...
    models:
      - embeddings
      - reranker
      - expander
    environment:
      - EMBEDDING_MODEL_ID=embeddinggemma-300m-v1
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy

  db:
    image: paradedb/paradedb:latest
    restart: unless-stopped
    # ... existing config ...
```

No sidecar containers. All three models run through DMR with Metal. Docker Compose `models:` key auto-injects `EMBEDDINGS_URL`, `RERANKER_URL`, `EXPANDER_URL` environment variables into the app container.

**Note:** The `models:` top-level key in Compose is beta (Docker Desktop 4.40+). If it breaks across versions, fall back to `extra_hosts: ["model-runner.docker.internal:host-gateway"]` and configure URLs manually.

## Query Expansion Prompt

```
You are a search query expander. Given a search query, generate 3-5 alternative
phrasings that capture the same intent using different terminology.

Rules:
- Each variant should use different words than the original
- Include both technical and colloquial phrasings
- Keep each variant under 10 words
- Return one variant per line, nothing else

Query: {original_query}
```

To prevent expansion from diluting exact matches, the original query's ranked list is included twice in the RRF sum (counted 2x), giving it double the rank-based contribution of any single expansion variant.

## Server-Side Changes

### New files

```
app/models/record_embedding.rb      # RecordEmbedding model (belongs_to :knowledge_record)
app/services/embedding_client.rb    # HTTP client for DMR embeddings endpoint
app/services/embedding_chunker.rb   # Chunking logic (single vs conversation turns)
app/services/reranker_client.rb     # HTTP client for DMR chat completions (reranking)
app/services/query_expander.rb      # HTTP client for DMR chat completions (expansion)
app/services/hybrid_search.rb       # RRF fusion + reranking orchestration
config/initializers/embedding_warmup.rb  # Model warmup on app boot
```

### Modified files

```
app/models/knowledge_record.rb      # Add has_many :record_embeddings, embedding callback
app/mcp_tools/hivemem_search_tool.rb # Add mode param (search/vsearch/query)
docker-compose.yml                   # Add DMR models config
docker-compose.prod.yml              # Same
Gemfile                              # Add neighbor gem (pgvector Rails integration)
```

### Migration

```
db/migrate/XXXX_add_vector_search.rb
  - enable_extension "vector"
  - create_table :record_embeddings (embedding, chunk_index, chunk_text, model_id)
  - add_index :record_embeddings, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  - add_index :record_embeddings, :model_id
```

### MCP Tool Changes

Add `mode` parameter to `HivememSearchTool`:

```ruby
properties: {
  # ... existing params ...
  mode: {
    type: "string",
    description: "Search mode: search (BM25), vsearch (vector), query (hybrid+reranking). Default: search",
    enum: ["search", "vsearch", "query"]
  }
}
```

## CLI Changes

```bash
# Existing (unchanged)
hivemem search "timing attack"              # BM25

# New modes
hivemem search --vector "timing attack"     # vector only
hivemem search --query "timing attack"      # hybrid + reranking

# Backfill embeddings for existing records
hivemem embeddings backfill [--batch 50]

# Check model status
hivemem models status
```

## Embedding Versioning

When the embedding model changes (e.g., embeddinggemma → nomic-embed-text), all existing vectors become incompatible with new query embeddings. The `model_id` column on `record_embeddings` handles this:

- `EmbeddingClient.current_model_id` returns the active model identifier (e.g., `"embeddinggemma-300m-v1"`)
- Vector search filters by `WHERE model_id = current_model_id` — stale embeddings are excluded automatically
- Re-embedding is incremental: `hivemem embeddings backfill` finds records where `model_id != current` and regenerates
- Old embeddings are kept until re-embedding completes — no search downtime during migration

```bash
# After changing embedding model
hivemem embeddings backfill --batch 50    # re-embed stale records
hivemem embeddings cleanup                 # drop old-model embeddings
hivemem embeddings status                  # show counts by model_id
```

## Graceful Degradation

Embedding failures must never break writes. The system degrades gracefully:

| DMR Status | Search Behavior |
|------------|----------------|
| All models up | Full hybrid pipeline |
| Embedding model down | BM25 only (writes succeed without embedding, backfill later) |
| Reranker model down | BM25 + vector, skip reranking step |
| Expander model down | BM25 + vector + reranking, skip query expansion |
| DMR completely down | BM25 only (existing behavior) |

Health checks run on app boot and periodically. Each service client (`EmbeddingClient`, `RerankerClient`, `QueryExpander`) has a circuit breaker — after 3 consecutive failures, skip that step for 60 seconds before retrying.

## Implementation Plan

### Phase 1: Vector Infrastructure
1. Update Compose with DMR `models:` config — DMR must be running before anything else works
2. Add pgvector extension migration + `record_embeddings` table (HNSW index)
3. Add `neighbor` gem to Gemfile
4. Build `RecordEmbedding` model
5. Build `EmbeddingClient` service (DMR HTTP client) with circuit breaker
6. Build `EmbeddingChunker` service (single chunk for curated, turn-level for conversations)
7. Add `after_save` embedding callback to `KnowledgeRecord` (with rescue, never blocks writes)
8. Add model warmup initializer
9. Backfill command with batch support (`hivemem embeddings backfill --batch 50`)
10. Add vector search scope to model

### Phase 2: Hybrid Search
11. Build `HybridSearch` service (RRF fusion, k=60)
12. Add `mode` parameter to MCP search tool
13. Add `--vector` and `--query` CLI flags
14. Test hybrid vs BM25-only relevance on conversation corpus

### Phase 3: Reranking
15. Build `RerankerClient` service (DMR chat completions, extract "yes" logprob)
16. Integrate reranking into hybrid search pipeline (reranker scores replace RRF scores)
17. Add circuit breaker — fall back to RRF-only when reranker unavailable

### Phase 4: Query Expansion
18. Build `QueryExpander` service (DMR chat completions, structured output)
19. Integrate expansion into hybrid search pipeline
20. Original query ranked list counted 2x in RRF sum
21. Test expansion quality on conversation corpus

### Phase 5: Polish
22. `hivemem models status` command (model health, embedding counts by model_id)
23. `hivemem embeddings status` / `backfill` / `cleanup` commands
24. Embedding dimension validation at migration time
25. Memory budget documentation (minimum 16GB recommended)
