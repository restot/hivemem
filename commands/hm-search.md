Search the hivemem knowledge store.

Arguments: $ARGUMENTS (search query, optionally with filters)

Parse filters from the arguments before searching:
- `project:<name>` — extract as the `project` filter (remove from query text)
- `type:<type>` — extract as the `knowledge_type` filter (remove from query text)
- `#tag` — extract as a `tag` filter (remove from query text; multiple allowed)
- Everything remaining after extracting filters is the BM25 search query text.

Steps:
1. Parse all filters and the remaining query from the arguments.
2. Call `hivemem_search_tool` with:
   - `query`: the remaining text (may be empty if only filters were given)
   - `project`: extracted project filter, if any
   - `knowledge_type`: extracted type filter, if any
   - `tags`: extracted tags array, if any
   - `limit`: 25
3. Display results as a formatted table with columns: shortlink | title | tags | type | project
4. Show the total count of matching records.
5. If no results, suggest broadening the query or adjusting filters.

Examples:
- `/hm-search error handling` — full-text search
- `/hm-search project:hivemem type:convention` — browse conventions for hivemem
- `/hm-search project:myapp #api-design` — filter by project and tag
- `/hm-search type:failure database` — search failures mentioning "database"
