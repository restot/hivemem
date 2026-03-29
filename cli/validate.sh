# =========================================================================
# validate — Check record health (usable as pre-commit hook)
# =========================================================================
cmd_validate() {
  local quiet=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet|-q) quiet=true; shift ;;
      *) shift ;;
    esac
  done

  local project
  project="$(basename "$(pwd)")"

  # Resolve server
  resolve_server
  local health_url="${SERVER_URL}/health"
  local mcp_url="${SERVER_URL}/mcp"
  local token="$AUTH_TOKEN"

  # Check server reachability
  local health_status
  health_status="$(curl -sk -o /dev/null -w '%{http_code}' "$health_url" 2>/dev/null || echo "000")"

  if [[ "$health_status" != "200" ]]; then
    echo "FAIL: hivemem server unreachable at $SERVER_URL"
    return 1
  fi

  $quiet || echo "hivemem validate: $project"

  local payload auth_header response
  payload=$(HIVEMEM_P="$project" python3 -c "
import json, os
print(json.dumps({
    'jsonrpc': '2.0', 'id': 1,
    'method': 'tools/call',
    'params': {'name': 'hivemem_search_tool', 'arguments': {'project': os.environ['HIVEMEM_P'], 'limit': 100}}
}))
")

  auth_header=""
  [[ -n "$token" ]] && auth_header="Authorization: Bearer $token"

  response="$(echo "$payload" | curl -sk -X POST "$mcp_url" \
    -H "Content-Type: application/json" \
    ${auth_header:+-H "$auth_header"} \
    -d @- 2>/dev/null || true)"

  if [[ -z "$response" ]]; then
    echo "FAIL: could not fetch records"
    return 1
  fi

  # Validate records
  local result
  result=$(HIVEMEM_RESPONSE="$response" python3 -c "
import json, os, sys
raw = os.environ.get('HIVEMEM_RESPONSE', '')
try:
    data = json.loads(json.loads(raw)['result']['content'][0]['text'])
except:
    print('FAIL:0:parse error')
    sys.exit(0)

records = data.get('results', [])
total = data.get('total', 0)
issues = []

if total == 0:
    issues.append('no records found')

for r in records:
    sl = r.get('shortlink', '?')
    if not r.get('title'):
        issues.append(f'{sl}: missing title')
    if not r.get('knowledge_type'):
        issues.append(f'{sl}: missing knowledge_type')
    if not r.get('classification'):
        issues.append(f'{sl}: missing classification')

if issues:
    print(f'FAIL:{total}:' + ';'.join(issues))
else:
    print(f'OK:{total}')
")

  local exit_code=0
  if [[ "$result" == OK:* ]]; then
    local count="${result#OK:}"
    $quiet || ok "All $count records valid"
  else
    local count issues
    count="$(echo "$result" | cut -d: -f2)"
    issues="$(echo "$result" | cut -d: -f3-)"
    echo "FAIL: $issues"
    exit_code=1
  fi
  return $exit_code
}
