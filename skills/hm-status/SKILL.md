---
name: hm-status
description: Show hivemem knowledge store statistics. Use when the user wants an overview of stored knowledge, record counts, or says "hm-status" or "knowledge status".
---

Show hivemem knowledge store statistics.

Steps:
1. Run the hivemem CLI to check server health:
   ```bash
   hivemem status
   ```
2. Run a broad search to get record counts:
   ```bash
   hivemem search --limit 1000
   ```
3. From the JSON results, compute and display:

   **Server**: (healthy/unhealthy from status output)
   **Total Records**: N

   **Records by Project**:
   | Project | Count |
   |---------|-------|
   | ...     | ...   |

   **Records by Type**:
   | Type | Count |
   |------|-------|
   | ...  | ...   |

   **Top 10 Tags**:
   | Tag | Count |
   |-----|-------|
   | ... | ...   |

4. If there are more than 1000 records, note that the counts are approximate.
