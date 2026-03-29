# =========================================================================
# API wrapper commands — thin CLI interface over the hivemem server
# These replace direct MCP tool access. Skills call these via bash.
# =========================================================================

# Internal: make a JSON-RPC call to the hivemem server
# Usage: _api_call <tool_name> <arguments_json>
# Outputs the parsed result text (or error message)
_api_call() {
  local tool_name="$1"
  local args_json="$2"

  resolve_server
  local mcp_url="${SERVER_URL}/mcp"

  local payload
  payload="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool_name\",\"arguments\":$args_json}}"

  local auth_header=""
  [[ -n "$AUTH_TOKEN" ]] && auth_header="Authorization: Bearer $AUTH_TOKEN"

  local response
  response="$(echo "$payload" | curl -sk -X POST "$mcp_url" \
    -H "Content-Type: application/json" \
    ${auth_header:+-H "$auth_header"} \
    -d @- 2>/dev/null || true)"

  if [[ -z "$response" ]]; then
    die "Could not reach hivemem server at $SERVER_URL"
  fi

  # Extract result text or error
  echo "$response" | python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
    if 'error' in data:
        print(json.dumps({'error': data['error'].get('message', str(data['error']))}, indent=2))
        sys.exit(1)
    text = data['result']['content'][0]['text']
    # Try to parse as JSON for pretty output
    try:
        parsed = json.loads(text)
        print(json.dumps(parsed, indent=2))
    except:
        print(text)
except (json.JSONDecodeError, KeyError, IndexError) as e:
    print(f'Error parsing response: {e}', file=sys.stderr)
    print(raw)
    sys.exit(1)
"
}

# =========================================================================
# search — Search knowledge records
# Usage: hivemem search [query] [--project P] [--type T] [--tag TAG] [--limit N]
# =========================================================================
cmd_search() {
  local query="" project="" knowledge_type="" limit="25"
  local -a tags=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project|-p) project="$2"; shift 2 ;;
      --type|-t)    knowledge_type="$2"; shift 2 ;;
      --tag)        tags+=("$2"); shift 2 ;;
      --limit|-l)   limit="$2"; shift 2 ;;
      -*)           die "search: unknown option $1" ;;
      *)            query="${query:+$query }$1"; shift ;;
    esac
  done

  need python3
  need curl

  local args_json
  args_json="$(HIVEMEM_Q="$query" HIVEMEM_P="$project" HIVEMEM_T="$knowledge_type" HIVEMEM_L="$limit" \
    HIVEMEM_TAGS="$(printf '%s\n' "${tags[@]}" 2>/dev/null || true)" python3 -c "
import json, os
args = {'limit': int(os.environ['HIVEMEM_L'])}
q = os.environ['HIVEMEM_Q']
p = os.environ['HIVEMEM_P']
t = os.environ['HIVEMEM_T']
tags_raw = os.environ.get('HIVEMEM_TAGS', '').strip()
if q: args['query'] = q
if p: args['project'] = p
if t: args['knowledge_type'] = t
if tags_raw:
    tags = [t for t in tags_raw.split('\n') if t]
    if tags: args['tags'] = tags
print(json.dumps(args))
")"

  _api_call "hivemem_search_tool" "$args_json"
}

# =========================================================================
# read — Read a full record by shortlink
# Usage: hivemem read <shortlink>
# =========================================================================
cmd_read() {
  local shortlink="${1:-}"
  [[ -n "$shortlink" ]] || die "Usage: hivemem read <shortlink>"

  need python3
  need curl

  local args_json
  args_json="$(HIVEMEM_SL="$shortlink" python3 -c "import json,os; print(json.dumps({'shortlink': os.environ['HIVEMEM_SL']}))")"
  _api_call "hivemem_read_tool" "$args_json"
}

# =========================================================================
# write — Create a knowledge record
# Usage: hivemem write --project P --type T --title "..." --content "..." [options]
# =========================================================================
cmd_write() {
  local project="" knowledge_type="" title="" content="" summary=""
  local classification="tactical"
  local -a tags=()
  local evidence_json="{}" metadata_json="{}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project|-p)        project="$2"; shift 2 ;;
      --type|-t)           knowledge_type="$2"; shift 2 ;;
      --title)             title="$2"; shift 2 ;;
      --content)           content="$2"; shift 2 ;;
      --summary)           summary="$2"; shift 2 ;;
      --classification)    classification="$2"; shift 2 ;;
      --tag)               tags+=("$2"); shift 2 ;;
      --evidence-commit)   evidence_json="{\"commit\":\"$2\"}"; shift 2 ;;
      --evidence)          evidence_json="$2"; shift 2 ;;
      --metadata)          metadata_json="$2"; shift 2 ;;
      -*)                  die "write: unknown option $1" ;;
      *)                   # Positional: type then rest as title
                           if [[ -z "$knowledge_type" ]]; then
                             knowledge_type="$1"
                           elif [[ -z "$title" ]]; then
                             title="$1"
                           else
                             title="$title $1"
                           fi
                           shift ;;
    esac
  done

  [[ -n "$knowledge_type" ]] || die "write: --type is required"
  [[ -n "$title" ]]          || die "write: --title is required"

  # Default project to cwd basename
  project="${project:-$(basename "$(pwd)")}"
  # Default content to title if not provided
  content="${content:-$title}"

  need python3
  need curl

  local args_json
  args_json="$(HIVEMEM_P="$project" HIVEMEM_T="$knowledge_type" HIVEMEM_TITLE="$title" \
    HIVEMEM_CONTENT="$content" HIVEMEM_SUMMARY="$summary" HIVEMEM_CLASS="$classification" \
    HIVEMEM_TAGS="$(printf '%s\n' "${tags[@]}" 2>/dev/null || true)" \
    HIVEMEM_EVIDENCE="$evidence_json" HIVEMEM_META="$metadata_json" python3 -c "
import json, os
args = {
    'project': os.environ['HIVEMEM_P'],
    'knowledge_type': os.environ['HIVEMEM_T'],
    'title': os.environ['HIVEMEM_TITLE'],
    'content': os.environ['HIVEMEM_CONTENT'],
    'classification': os.environ['HIVEMEM_CLASS'],
}
summary = os.environ.get('HIVEMEM_SUMMARY', '')
if summary: args['summary'] = summary
tags_raw = os.environ.get('HIVEMEM_TAGS', '').strip()
if tags_raw:
    tags = [t for t in tags_raw.split('\n') if t]
    if tags: args['tags'] = tags
evidence = json.loads(os.environ.get('HIVEMEM_EVIDENCE', '{}'))
if evidence: args['evidence'] = evidence
metadata = json.loads(os.environ.get('HIVEMEM_META', '{}'))
if metadata: args['metadata'] = metadata
print(json.dumps(args))
")"

  _api_call "hivemem_write_tool" "$args_json"
}

# =========================================================================
# delete — Delete a record by shortlink
# Usage: hivemem delete <shortlink>
# =========================================================================
cmd_delete() {
  local shortlink="${1:-}"
  [[ -n "$shortlink" ]] || die "Usage: hivemem delete <shortlink>"

  need python3
  need curl

  local args_json
  args_json="$(HIVEMEM_SL="$shortlink" python3 -c "import json,os; print(json.dumps({'shortlink': os.environ['HIVEMEM_SL']}))")"
  _api_call "hivemem_delete_tool" "$args_json"
}
