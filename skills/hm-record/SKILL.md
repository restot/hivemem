---
name: hm-record
description: Record a knowledge entry in hivemem. Use when the user wants to save a convention, pattern, decision, failure, reference, or guide. Trigger on "record", "save knowledge", "hm-record", or "remember this".
---

Record a knowledge entry in hivemem.

Arguments: $ARGUMENTS (format: "<domain> <type> <description>" or just a description)

Parse the arguments:
- Split on whitespace. If 3+ parts: first word is the `project`, second is the `knowledge_type`, and the rest is the description.
- If fewer than 3 parts, ask the user for the missing `project` and/or `knowledge_type` before proceeding.

Valid knowledge types: convention, pattern, decision, failure, reference, guide

Steps:
1. Parse arguments as described above.
2. Validate that `knowledge_type` is one of the valid types. If not, tell the user and ask for correction.
3. Generate a concise title (under 80 chars) from the description.
4. Generate 2-5 relevant tags automatically based on the content. Use lowercase, hyphenated tags (e.g. "error-handling", "api-design").
5. Use the `hivemem_write_tool` to create the record with these fields:
   - `title`: the generated title
   - `content`: the full description text
   - `project`: parsed project name
   - `knowledge_type`: parsed type
   - `tags`: the auto-generated tags array
6. Print the shortlink from the response and a brief confirmation.

Example usage:
- `/hm-record hivemem convention Always use shortlinks as the primary identifier for records`
- `/hm-record myproject decision Chose PostgreSQL over SQLite for concurrent write support`
