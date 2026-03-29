# =========================================================================
# migrate — Import mulch records into hivemem
# =========================================================================
cmd_migrate() {
  local mulch_root="."
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      -*) die "migrate: unknown option $1" ;;
      *) mulch_root="$1"; shift ;;
    esac
  done

  mulch_root="$(cd "$mulch_root" 2>/dev/null && pwd)" || die "Directory not found: $mulch_root"

  need python3
  need curl

  local mulch_dir="$mulch_root/.mulch/expertise"
  if [[ ! -d "$mulch_dir" ]]; then
    die "No .mulch/expertise/ found at $mulch_root"
  fi

  # Resolve server
  resolve_server
  local mcp_url="${SERVER_URL}/mcp"
  local token="$AUTH_TOKEN"

  if [[ -z "$token" ]] && ! $dry_run; then
    die "No auth token found. Set HIVEMEM_AUTH_TOKEN or run 'hivemem setup' first."
  fi

  info "Mulch migration: $mulch_root"

  local total_migrated=0
  local total_domains=0

  for jsonl_file in "$mulch_dir"/*.jsonl; do
    [[ -f "$jsonl_file" ]] || continue
    local domain
    domain="$(basename "$jsonl_file" .jsonl)"
    local record_count
    record_count="$(wc -l < "$jsonl_file" | tr -d ' ')"
    total_domains=$((total_domains + 1))

    info "Domain: $domain ($record_count records)"

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue

      local result
      result="$(echo "$line" | python3 -c "
import json, os, sys

record = json.loads(sys.stdin.readline())
domain = '$domain'

knowledge_type = record.get('type', 'convention')
content = record.get('content', record.get('description', ''))
title = record.get('name', '')
if not title:
    title = content.split(chr(10))[0][:100] if content else 'Untitled'

classification = record.get('classification', 'tactical')

tags = list(record.get('tags', []))
evidence = record.get('evidence', {})
relates_to = record.get('relates_to', [])
supersedes = record.get('supersedes', [])

metadata = {}
files = record.get('files', [])
if isinstance(files, list) and files:
    metadata['files'] = files
resolution = record.get('resolution', '')
if resolution:
    metadata['resolution'] = resolution
rationale = record.get('rationale', '')
if rationale:
    metadata['rationale'] = rationale
rec_date = record.get('date', '')
if rec_date:
    metadata['date'] = rec_date

payload = {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {
        'name': 'hivemem_write_tool',
        'arguments': {
            'project': domain,
            'knowledge_type': knowledge_type,
            'title': title,
            'content': content,
            'classification': classification,
            'tags': tags,
            'evidence': evidence,
            'relates_to': relates_to,
            'supersedes': supersedes,
            'metadata': metadata
        }
    }
}

print(f'{knowledge_type}: {title[:60]}')
print(json.dumps(payload))
")"

      local summary payload
      summary="$(echo "$result" | head -1)"
      payload="$(echo "$result" | tail -n +2)"

      if $dry_run; then
        echo "  [dry-run] $summary"
      else
        echo "$payload" | curl -sk -X POST "$mcp_url" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $token" \
          -d @- > /dev/null 2>&1
        ok "$summary"
      fi

      total_migrated=$((total_migrated + 1))
    done < "$jsonl_file"
  done

  echo ""
  if $dry_run; then
    info "Dry run: would migrate $total_migrated records from $total_domains domains"
  else
    ok "Migrated $total_migrated records from $total_domains domains"
  fi
}
