<!-- ast:start -->
## Code Intelligence (ast-index)
<!-- ast-onboard-v:1 -->

This project is indexed by [ast-index](https://github.com/restot/ast-index) for code intelligence via MCP.

**Available MCP tools** (provided by the ast-index server):
- `search_symbols` — BM25 search across all indexed symbols
- `search_text` — full-text search in source files
- `get_file_outline` — list symbols in a file
- `get_file_tree` — browse the file tree at a commit
- `get_symbol` — get symbol details (signature, docstring, location)
- `get_file_content` — read file content at a commit
- `find_importers` — find files that import a given module
- `find_references` — find references to a symbol
- `code_review` — blast radius analysis for changed files

All tools accept a `commit` parameter (SHA). Use `git rev-parse HEAD` to get the current commit.
<!-- ast:end -->
