#!/usr/bin/env bash
# Test helpers for hivemem prime formatting
# Extracts the Python heredoc from bin/hivemem and runs it with controlled input.

HIVEMEM_BIN="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/bin/hivemem"

# Extract the Python formatter heredoc from bin/hivemem into a standalone script.
# Finds the HIVEMEM_RESPONSE line and extracts everything between it and the next bare PYEOF.
extract_prime_formatter() {
  local outfile="${BATS_TMPDIR}/prime_formatter.py"
  awk '/HIVEMEM_RESPONSE.*PYEOF/{found=1; next} found && /^PYEOF$/{exit} found{print}' \
    "$HIVEMEM_BIN" > "$outfile"
  echo "$outfile"
}

# Run the extracted Python formatter with crafted input.
# Usage: run_prime_formatter "$json_response" "$project" "$format" "$mode" [extra_args...]
# Output is captured in $output, exit code in $status (via bats `run`).
run_prime_formatter() {
  local response="$1" project="$2" format="$3" mode="$4"
  shift 4
  local formatter
  formatter="$(extract_prime_formatter)"
  HIVEMEM_RESPONSE="$response" python3 "$formatter" "$project" "$format" "$mode" "$@"
}

# Build a single record dict as JSON.
# Usage: make_record <type> <classification> <title> <shortlink> [summary] [tags_json] [created_at] [score]
make_record() {
  local ktype="$1" classification="$2" title="$3" shortlink="$4"
  local summary="${5:-}" tags="${6:-[]}" created_at="${7:-2026-01-01T00:00:00Z}" score="${8:-1.0}"
  cat <<EOF
{
  "knowledge_type": "$ktype",
  "classification": "$classification",
  "title": "$title",
  "shortlink": "$shortlink",
  "summary": "$summary",
  "tags": $tags,
  "created_at": "$created_at",
  "updated_at": "$created_at",
  "score": $score
}
EOF
}

# Build a mock MCP server response wrapping an array of records.
# Usage: make_search_response "$records_json_array" [total]
# records_json_array should be a JSON array string.
make_search_response() {
  local records_json="$1"
  local total="${2:-}"
  if [[ -z "$total" ]]; then
    total="$(echo "$records_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
  fi
  cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [{
      "type": "text",
      "text": $(echo "{\"results\": $records_json, \"total\": $total}" | python3 -c 'import json,sys; print(json.dumps(json.dumps(json.load(sys.stdin))))')
    }]
  }
}
EOF
}
