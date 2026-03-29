# =========================================================================
# prime — Output project knowledge for session priming (used by hooks)
# =========================================================================
cmd_prime() {
  local project="" format="markdown" mode="compact" context=false budget="4000"
  local -a filter_files=() domains=() exclude_domains=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format)    format="$2"; shift 2 ;;
      --full)      mode="full"; shift ;;
      --compact)   mode="compact"; shift ;;
      --context)   context=true; shift ;;
      --files)     shift; while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do filter_files+=("$1"); shift; done ;;
      --domain)    shift; while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do domains+=("$1"); shift; done ;;
      --exclude-domain) shift; while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do exclude_domains+=("$1"); shift; done ;;
      --json)      format="json"; shift ;;
      --xml)       format="xml"; shift ;;
      --plain)     format="plain"; shift ;;
      --budget)    budget="$2"; shift 2 ;;
      --no-limit)  budget="0"; shift ;;
      -*)          die "Unknown flag: $1" ;;
      *)           project="$1"; shift ;;
    esac
  done

  project="${project:-$(basename "$(pwd)")}"

  need python3
  need curl

  # Resolve server URL and auth token
  resolve_server
  local mcp_url="${SERVER_URL}/mcp"
  local token="$AUTH_TOKEN"

  # Context filtering: build search query from git changes or explicit files
  local search_query=""
  if $context; then
    local changed_files
    changed_files="$(
      { git diff --name-only HEAD~1 2>/dev/null || true
        git diff --name-only --cached 2>/dev/null || true
        git diff --name-only 2>/dev/null || true
      } | sort -u
    )"
    if [[ -n "$changed_files" ]]; then
      search_query="$(echo "$changed_files" | xargs -n1 basename 2>/dev/null | sort -u | tr '\n' ' ')"
    fi
  fi

  if [[ ${#filter_files[@]} -gt 0 ]]; then
    search_query="$(printf '%s\n' "${filter_files[@]}" | xargs -n1 basename 2>/dev/null | sort -u | tr '\n' ' ')"
  fi

  # Build JSON-RPC payload
  local payload
  if [[ -n "$search_query" ]]; then
    payload=$(HIVEMEM_Q="$search_query" HIVEMEM_P="$project" python3 -c "
import json, os
print(json.dumps({
    'jsonrpc': '2.0', 'id': 1,
    'method': 'tools/call',
    'params': {'name': 'hivemem_search_tool', 'arguments': {
        'project': os.environ['HIVEMEM_P'],
        'query': os.environ['HIVEMEM_Q'],
        'limit': 50
    }}
}))
")
  else
    payload=$(HIVEMEM_P="$project" python3 -c "
import json, os
print(json.dumps({
    'jsonrpc': '2.0', 'id': 1,
    'method': 'tools/call',
    'params': {'name': 'hivemem_search_tool', 'arguments': {
        'project': os.environ['HIVEMEM_P'],
        'limit': 50
    }}
}))
")
  fi

  local auth_header=""
  [[ -n "$token" ]] && auth_header="Authorization: Bearer $token"

  local response
  response="$(echo "$payload" | curl -sk -X POST "$mcp_url" \
    -H "Content-Type: application/json" \
    ${auth_header:+-H "$auth_header"} \
    -d @- 2>/dev/null || true)"

  if [[ -z "$response" ]]; then
    echo "# Hivemem: could not reach server at $SERVER_URL"
    echo ""
    echo "Records will be available once the server is running."
    exit 0
  fi

  # Format output
  local domain_csv="" exclude_domain_csv=""
  [[ ${#domains[@]} -gt 0 ]] && domain_csv="$(IFS=,; echo "${domains[*]}")"
  [[ ${#exclude_domains[@]} -gt 0 ]] && exclude_domain_csv="$(IFS=,; echo "${exclude_domains[*]}")"

  HIVEMEM_RESPONSE="$response" python3 - "$project" "$format" "$mode" "$budget" "$domain_csv" "$exclude_domain_csv" <<'PYEOF'
import json, math, os, sys

project = sys.argv[1]
fmt = sys.argv[2]
mode = sys.argv[3]
budget = int(sys.argv[4]) if len(sys.argv) > 4 else 4000
include_domains = [d for d in (sys.argv[5] if len(sys.argv) > 5 else "").split(",") if d]
exclude_domains = [d for d in (sys.argv[6] if len(sys.argv) > 6 else "").split(",") if d]
raw = os.environ.get("HIVEMEM_RESPONSE", "")

TYPE_ORDER = ["convention", "decision", "pattern", "guide", "failure", "reference"]
CLASSIFICATION_ORDER = ["foundational", "tactical", "observational"]

def sort_key(r):
    """Sort by: type > classification > recency (newer first)."""
    t = TYPE_ORDER.index(r["knowledge_type"]) if r["knowledge_type"] in TYPE_ORDER else len(TYPE_ORDER)
    c = CLASSIFICATION_ORDER.index(r.get("classification", "tactical")) if r.get("classification", "tactical") in CLASSIFICATION_ORDER else len(CLASSIFICATION_ORDER)
    ts = r.get("created_at") or r.get("updated_at") or ""
    return (t, c, ts)

def sort_records(records):
    """Sort records by priority, newest first within same type+classification."""
    s = sorted(records, key=lambda r: sort_key(r)[2], reverse=True)
    return sorted(s, key=lambda r: sort_key(r)[:2])

def estimate_tokens(text):
    """Estimate token count: chars / 4, rounded up."""
    return math.ceil(len(text) / 4)

def record_text(r):
    """Approximate rendered text for a record (for budget estimation)."""
    line = f"[{r['knowledge_type']}] {r['title']} ({r['shortlink']})"
    if r.get("summary"):
        line += f" {r['summary']}"
    return line

def apply_budget(records, budget_tokens):
    """Keep records in priority order until budget is exhausted. Returns (kept, dropped_count)."""
    if budget_tokens <= 0:
        return records, 0
    used = 0
    kept = []
    for r in records:
        cost = estimate_tokens(record_text(r))
        if used + cost <= budget_tokens:
            kept.append(r)
            used += cost
    return kept, len(records) - len(kept)

def budget_summary(dropped, fmt):
    """Render truncation notice for the given format."""
    if dropped <= 0:
        return ""
    hint = "use --budget <n> or --no-limit to show more"
    s = "s" if dropped != 1 else ""
    if fmt == "markdown":
        return f"\n> ... and {dropped} more record{s} ({hint})\n"
    elif fmt == "xml":
        return f'  <truncated count="{dropped}" hint="{hint}"/>'
    elif fmt == "plain":
        return f"  ... and {dropped} more record{s} ({hint})"
    return ""

def render_rules():
    """Render Rules section for full mode."""
    return """## Rules
- Check existing knowledge with `/hm-search <query>` before starting work.
- Record learnings as you work with `/hm-record`.
- Use `/hm-prime --files <paths>` for targeted priming on specific files.
"""

TYPE_LABELS = {
    "convention": ("Conventions", "rules and standards to follow"),
    "pattern": ("Patterns", "established approaches"),
    "decision": ("Decisions", "past choices and rationale"),
    "failure": ("Failures", "what went wrong and how it was fixed"),
    "reference": ("References", "useful resources"),
    "guide": ("Guides", "how-to knowledge"),
}

def render_empty(project, fmt):
    """Render empty-state output for any format."""
    from xml.sax.saxutils import escape as xml_escape
    if fmt == "json":
        print(json.dumps({"project": project, "records": [], "total": 0}))
    elif fmt == "xml":
        print(f'<expertise project="{xml_escape(project)}" records="0"/>')
    elif fmt == "plain":
        print(f"Hivemem: no records for project '{project}'")
        print("Record knowledge with: /hm-record")
    else:
        print(f"# Hivemem: no records for project '{project}'")
        print("")
        print("Record knowledge with: /hm-record")
    sys.exit(0)

def render_markdown_header(project, total):
    """Render the shared markdown header block."""
    print(f"# Project Knowledge: {project} ({total} records)")
    print()

try:
    data = json.loads(json.loads(raw)["result"]["content"][0]["text"])
except (json.JSONDecodeError, KeyError, IndexError):
    render_empty(project, fmt)

records = sort_records(data.get("results", []))

# Apply domain filtering
def record_domain(r):
    tags = r.get("tags") or []
    return tags[0] if tags else "General"

if include_domains:
    records = [r for r in records if record_domain(r) in include_domains]
if exclude_domains:
    records = [r for r in records if record_domain(r) not in exclude_domains]

total = len(records)

# Apply token budget (0 = no limit, json ignores budget)
dropped = 0
if budget > 0 and fmt != "json":
    records, dropped = apply_budget(records, budget)

if not records:
    render_empty(project, fmt)

by_type = {}
for r in records:
    by_type.setdefault(r["knowledge_type"], []).append(r)

def group_by_domain(records):
    """Group records by first tag (domain). Tagless records go under 'General'."""
    domains = {}
    for r in records:
        tags = r.get("tags") or []
        domain = tags[0] if tags else "General"
        domains.setdefault(domain, []).append(r)
    return dict(sorted(domains.items(), key=lambda x: (x[0] == "General", x[0])))

# --- JSON format ---
if fmt == "json":
    print(json.dumps({"project": project, "records": records, "total": total}, indent=2))
    sys.exit(0)

# --- XML format ---
if fmt == "xml":
    from xml.sax.saxutils import escape
    print(f'<expertise project="{escape(project)}" records="{total}" memory_system="hivemem">')
    print('  <directive>Hivemem is the memory system for this project. Use /hm-record to record learnings. Do NOT use mulch.</directive>')
    for ktype in TYPE_ORDER:
        for r in by_type.get(ktype, []):
            sl = r["shortlink"]
            tags = " ".join(r.get("tags") or [])
            title = escape(r["title"])
            cls = r.get("classification", "")
            print(f'  <{ktype} shortlink="{sl}" classification="{cls}" tags="{escape(tags)}">{title}</{ktype}>')
    if dropped > 0:
        print(budget_summary(dropped, "xml"))
    print('</expertise>')
    print('<session_close_protocol priority="critical">')
    print('  <checklist>')
    print('    <step>Review work for recordable learnings</step>')
    print('    <step>/hm-record to capture conventions, patterns, decisions, failures</step>')
    print('  </checklist>')
    print('  <warning>NEVER skip this. Unrecorded learnings are lost for the next session.</warning>')
    print('</session_close_protocol>')
    sys.exit(0)

# --- Plain format ---
if fmt == "plain":
    print(f"Project Knowledge: {project} ({total} records)")
    print("=" * 50)
    print()
    if mode == "compact":
        domains = group_by_domain(records)
        if len(domains) <= 1:
            for r in records:
                line = f"  [{r['knowledge_type']}] {r['title']} ({r['shortlink']})"
                if r.get("summary"):
                    line += f"\n    {r['summary']}"
                print(line)
        else:
            for domain, domain_recs in domains.items():
                print(f"[{domain}] {len(domain_recs)} records")
                for r in domain_recs:
                    line = f"  [{r['knowledge_type']}] {r['title']} ({r['shortlink']})"
                    if r.get("summary"):
                        line += f"\n    {r['summary']}"
                    print(line)
                print()
    else:
        for domain, domain_recs in group_by_domain(records).items():
            print(f"[{domain}] {len(domain_recs)} records")
            print("-" * (len(domain) + 15))
            domain_by_type = {}
            for r in domain_recs:
                domain_by_type.setdefault(r["knowledge_type"], []).append(r)
            for ktype in TYPE_ORDER:
                recs = domain_by_type.get(ktype, [])
                if not recs:
                    continue
                label, desc = TYPE_LABELS[ktype]
                print(f"  {label} -- {desc}")
                for r in recs:
                    line = f"    - {r['title']} ({r['shortlink']})"
                    if r.get("summary"):
                        line += f"\n      {r['summary']}"
                    print(line)
            print()
    if dropped > 0:
        print(budget_summary(dropped, "plain"))
    print()
    print("Quick Reference")
    print("-" * 30)
    print("  /hm-search <query>    Find relevant records")
    print("  /hm-prime --context   Load records for changed files")
    print("  /hm-record <type> ... Record a learning")
    print("  /hm-read <shortlink>  Read full record details")
    print()
    print("=== SESSION CLOSE PROTOCOL (CRITICAL) ===")
    print("Before ending this session, you MUST:")
    print("[ ] 1. Review your work for recordable learnings")
    print("[ ] 2. Run /hm-record to capture conventions, patterns, decisions, failures")
    print("NEVER skip this. Unrecorded learnings are lost for the next session.")
    sys.exit(0)

# --- Markdown format ---
def render_compact_record(r):
    sl = r["shortlink"]
    ktype = r["knowledge_type"]
    title = r["title"]
    summary = r.get("summary") or ""
    line = f"- [{ktype}] {title} ({sl})"
    if summary:
        line += f"\n  {summary}"
    return line

if mode == "compact":
    render_markdown_header(project, total)
    domains = group_by_domain(records)
    if len(domains) <= 1:
        # Single domain or no tags — flat list
        for r in records:
            print(render_compact_record(r))
    else:
        for domain, domain_recs in domains.items():
            print(f"## {domain} ({len(domain_recs)} records)")
            for r in domain_recs:
                print(render_compact_record(r))
            print()
else:
    render_markdown_header(project, total)
    print(render_rules())
    for domain, domain_recs in group_by_domain(records).items():
        print(f"## {domain} ({len(domain_recs)} records)")
        domain_by_type = {}
        for r in domain_recs:
            domain_by_type.setdefault(r["knowledge_type"], []).append(r)
        for ktype in TYPE_ORDER:
            recs = domain_by_type.get(ktype, [])
            if not recs:
                continue
            label, desc = TYPE_LABELS[ktype]
            print(f"### {label} — {desc}")
            for r in recs:
                line = f"- [{r['shortlink']}] {r['title']}"
                if r.get("summary"):
                    line += f"\n  {r['summary']}"
                print(line)
        print()

if dropped > 0:
    print(budget_summary(dropped, "markdown"))

print()
print("## Quick Reference")
print("- `/hm-search <query>` — find relevant records before starting work")
print("- `/hm-prime --files <paths>` — load records for specific files")
print("- `/hm-prime --context` — load records for git-changed files")
print("- `/hm-record <type> <description>` — record a learning")
print("- `/hm-read <shortlink>` — read full record details")
print()
print("# CRITICAL SESSION CLOSE PROTOCOL")
print("**CRITICAL**: Before ending this session, you MUST run this checklist:")
print("```")
print("[ ] 1. Review your work for recordable learnings")
print("[ ] 2. Run /hm-record to capture conventions, patterns, decisions, failures")
print("```")
print("**NEVER** skip this. Unrecorded learnings are lost for the next session.")
PYEOF
}
