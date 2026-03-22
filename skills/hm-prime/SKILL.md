---
name: hm-prime
description: Prime the current session with hivemem knowledge. Use when starting a session, needing project context, or when the user says "prime", "load knowledge", or "hm-prime".
---

Prime the current session with relevant hivemem knowledge.

Arguments: $ARGUMENTS (project name, "all" for cross-project, or "full" for grouped-by-type view)

Steps:
1. Parse arguments. If no argument given, use current project directory name (basename of cwd). If "all", omit the project filter. If "full" is anywhere in args, use full mode.
2. Call `hivemem_search_tool` with:
   - `project`: the project name (omit if "all")
   - `limit`: 50
   - No query text (browse mode)
3. Display records in **compact mode** (default) — one line per record:
   ```
   # Project Knowledge: <project> (<N> records)

   - [convention] MCP config goes in .mcp.json (hm-nEEsMbi)
   - [pattern] trust_server_cert extracts CA root (hm-RB3OKl8)
   - [failure] NODE_EXTRA_CA_CERTS needs CA cert → use CA root (hm-Wl9TxIR)
   ...
   ```

   Or in **full mode** (if "full" in args) — grouped by type:
   ```
   # Project Knowledge: <project> (<N> records)

   ## Conventions — rules and standards to follow
   - [hm-nEEsMbi] MCP config goes in .mcp.json, not settings.json
   ...

   ## Patterns — established approaches
   ...
   ```

   Type order: convention, pattern, decision, failure, reference, guide.
   Only include type sections that have records.

4. Always append Quick Reference and Session Close Protocol:
   ```
   ## Quick Reference
   - `/hm-record` — record knowledge from this session
   - `/hm-search <query>` — search knowledge records
   - `/hm-prime` — reload project knowledge
   - `/hm-read <shortlink>` — read full record details

   ---

   # CRITICAL SESSION CLOSE PROTOCOL
   **CRITICAL**: Before ending this session, you MUST run this checklist:
   ```
   [ ] 1. Review your work for recordable learnings
   [ ] 2. Run /hm-record to capture conventions, patterns, decisions, failures
   ```
   **NEVER** skip this. Unrecorded learnings are lost for the next session.
   ```

Examples:
- `/hm-prime` — prime with current project knowledge (compact)
- `/hm-prime hivemem` — prime with hivemem project knowledge
- `/hm-prime full` — prime with grouped-by-type view
- `/hm-prime all` — prime with all cross-project knowledge
