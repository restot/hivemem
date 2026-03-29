---
name: hm-read
description: Read a full hivemem knowledge record by shortlink. Use when the user wants to view a specific record, says "hm-read", or references a shortlink like "hm-abc1234".
---

Read a full hivemem knowledge record.

Arguments: $ARGUMENTS (shortlink, e.g. hm-abc1234)

Steps:
1. Take the argument as the shortlink identifier.
2. Run the hivemem CLI to fetch the record:
   ```bash
   hivemem read <shortlink>
   ```
3. Parse the JSON output and display all fields in a readable format:

   **Title**: ...
   **Shortlink**: ...
   **Project**: ...
   **Type**: ...
   **Classification**: ...
   **Tags**: ...
   **Created**: ...
   **Updated**: ...

   **Summary**:
   (summary text)

   **Content**:
   (full content text)

4. If the record is not found, say so and suggest using `/hm-search` to find the correct shortlink.

Example:
- `/hm-read hm-abc1234`
