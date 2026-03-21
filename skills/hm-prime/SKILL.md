---
name: hm-prime
description: Prime the current session with hivemem knowledge. Use when starting a session, needing project context, or when the user says "prime", "load knowledge", or "hm-prime".
---

Prime the current session with relevant hivemem knowledge.

Arguments: $ARGUMENTS (project name, or "all" for cross-project knowledge)

Steps:
1. Parse the argument as the project name. If "all", omit the project filter.
2. Call `hivemem_search_tool` with:
   - `project`: the project name (omit if "all")
   - `limit`: 50
   - No query text (browse mode)
3. For each record returned, display a one-line summary:
   `[shortlink] title (type) — first ~100 chars of content`

4. After listing all records, produce a structured summary organized by type:

   **Conventions** — rules and standards to follow:
   - (list each convention as a bullet)

   **Patterns** — established approaches:
   - (list each pattern as a bullet)

   **Decisions** — past choices and their rationale:
   - (list each decision as a bullet)

   **Failures** — things that went wrong and how they were fixed:
   - (list each failure as a bullet)

   **References** — useful resources and links:
   - (list each reference as a bullet)

   **Guides** — how-to knowledge:
   - (list each guide as a bullet)

   Only include sections that have records. This summary should inform the rest of the current session.

Examples:
- `/hm-prime hivemem` — prime with hivemem project knowledge
- `/hm-prime all` — prime with all cross-project knowledge
