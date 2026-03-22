---
name: hm-record
description: Record a knowledge entry in hivemem. Use when the user wants to save a convention, pattern, decision, failure, reference, or guide. Trigger on "record", "save knowledge", "hm-record", or "remember this".
---

Record knowledge into hivemem. Works like mulch — absorbs context automatically.

Arguments: $ARGUMENTS (flexible — see parsing below)

Parsing rules (flexible, forgiving):
1. **No arguments**: Review the current session's work. Identify all recordable learnings — conventions discovered, patterns applied, decisions made, failures encountered, references found, guides written. Record ALL of them automatically. Use cwd basename as project.
2. **Just a description**: Auto-detect project from cwd basename. Auto-infer knowledge_type from content (e.g., "always do X" → convention, "X failed because Y" → failure, "chose X over Y" → decision, "how to X" → guide, "X works by Y" → pattern, "X is at Y" → reference). Record it.
3. **type + description**: e.g., `convention always use shortlinks`. Auto-detect project from cwd basename.
4. **project + type + description**: e.g., `hivemem convention always use shortlinks`. Fully explicit.

Valid knowledge types: convention, pattern, decision, failure, reference, guide

Steps:
1. Parse arguments using the flexible rules above.
2. If no arguments: scan the session for learnings. For each one, generate title + content + type + tags and record via `hivemem_write_tool`. Report what was recorded.
3. If arguments provided:
   a. Generate a concise title (under 80 chars) from the description.
   b. Expand the description into useful content — don't just echo the input, add context from the session if relevant.
   c. Auto-generate 2-5 lowercase hyphenated tags from the content.
   d. Auto-infer classification: "always"/"never"/"must" → foundational, specific fix/workaround → observational, default → tactical.
   e. Call `hivemem_write_tool` with: title, content, project, knowledge_type, tags, classification.
   f. Print shortlink and brief confirmation.

Examples:
- `/hm-record` — scan session, record all learnings automatically
- `/hm-record always use http type for MCP servers` — auto-detect project + type
- `/hm-record convention always use shortlinks as primary identifier`
- `/hm-record hivemem decision chose ParadeDB for BM25 search`
