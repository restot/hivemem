---
name: hm-prime
description: Prime the current session with hivemem knowledge. Use when starting a session, needing project context, or when the user says "prime", "load knowledge", or "hm-prime".
---

Prime the current session with relevant hivemem knowledge.

Arguments: $ARGUMENTS (project name, "all" for cross-project, or "full" for grouped-by-type view)

Steps:
1. Parse arguments. If no argument given, use current project directory name (basename of cwd). If "full" is anywhere in args, use full mode.
2. Run the hivemem CLI to fetch and format knowledge:

   **Default (compact mode):**
   ```bash
   hivemem prime <project>
   ```

   **Full mode (grouped by type):**
   ```bash
   hivemem prime <project> --full
   ```

   **Cross-project (all projects):**
   ```bash
   hivemem prime --no-limit
   ```

3. The CLI outputs formatted knowledge directly. Display its output to the user.
4. If the CLI is not available, fall back to:
   ```bash
   hivemem search --project <project> --limit 50
   ```
   and format the JSON results manually.

Examples:
- `/hm-prime` — prime with current project knowledge (compact)
- `/hm-prime hivemem` — prime with hivemem project knowledge
- `/hm-prime full` — prime with grouped-by-type view
- `/hm-prime all` — prime with all cross-project knowledge
