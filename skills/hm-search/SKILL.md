---
name: hm-search
description: Search the hivemem knowledge store. Use when the user wants to find knowledge records, look up past decisions, search conventions, or says "hm-search" or "search knowledge".
---

Search the hivemem knowledge store.

Arguments: $ARGUMENTS (search query, optionally with filters)

Parse filters from the arguments before searching:
- `project:<name>` — extract as the `--project` filter (remove from query text)
- `type:<type>` — extract as the `--type` filter (remove from query text)
- `#tag` — extract as a `--tag` filter (remove from query text; multiple allowed)
- Everything remaining after extracting filters is the search query text.

Steps:
1. Parse all filters and the remaining query from the arguments.
2. Run the hivemem CLI to search:
   ```bash
   hivemem search <query> --project <project> --type <type> --tag <tag> --limit 25
   ```
   Omit flags that weren't specified.
3. Parse the JSON output and display results as a formatted table with columns: shortlink | title | tags | type | project
4. Show the total count of matching records.
5. If no results, suggest broadening the query or adjusting filters.

Examples:
- `/hm-search error handling` — full-text search
- `/hm-search project:hivemem type:convention` — browse conventions for hivemem
- `/hm-search project:myapp #api-design` — filter by project and tag
- `/hm-search type:failure database` — search failures mentioning "database"
