Show hivemem knowledge store statistics.

Steps:
1. Call `hivemem_search_tool` with no query and no filters, setting `limit` to 1000.
2. From the returned records, compute and display:

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

3. If there are more than 1000 records, note that the counts are approximate and only reflect the first 1000 results.
