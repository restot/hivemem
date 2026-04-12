#!/usr/bin/env bash
# Hivemem conversation capture — Stop hook
# Parses current session via agent-watch, filters tool outputs,
# ingests new turns as conversation records. Runs in background.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || exit 0
[ -z "$CWD" ] && exit 0

# Background the heavy work
(
  set -euo pipefail

  AGENT_WATCH="$HOME/.claude/bin/agent-watch"
  STATE_DIR="$HOME/.hivemem/state"
  PROJECT=$(basename "$CWD")

  # Get active session ID
  SESSION_ID=$("$AGENT_WATCH" list-sessions --no-color 1 2>/dev/null \
    | grep '●' | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9a-f]{8}$/) print $i}')
  [ -z "$SESSION_ID" ] && exit 0

  # Check last processed turn
  mkdir -p "$STATE_DIR"
  LAST_TURN=$(cat "$STATE_DIR/$SESSION_ID" 2>/dev/null || echo 0)

  # Get transcript, parse into turns, filter
  TRANSCRIPT=$("$AGENT_WATCH" session "$SESSION_ID" --no-color --limit 50000 2>/dev/null)

  # Git context
  BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  COMMIT=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null || true)

  # Parse and ingest — awk does the heavy lifting
  echo "$TRANSCRIPT" | awk -v last_turn="$LAST_TURN" \
    -v project="$PROJECT" -v session_id="$SESSION_ID" \
    -v branch="$BRANCH" -v commit="$COMMIT" '
  BEGIN {
    tag = ""; content = ""; turn = 0
    user_text = ""; asst_text = ""; tool_lines = ""
    files_read = ""; files_edited = ""; commands = ""
  }

  function is_real_user(text) {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", text)
    if (text == "") return 0
    if (text ~ /^<system-reminder>/) return 0
    if (text ~ /^<command-message>/) return 0
    if (text ~ /^<command-name>/) return 0
    if (text ~ /^<local-command-/) return 0
    return 1
  }

  function extract_json_field(json, field,    pat, val) {
    pat = "\"" field "\"[[:space:]]*:[[:space:]]*\""
    if (match(json, pat)) {
      val = substr(json, RSTART + RLENGTH)
      sub(/".*/, "", val)
      gsub(/\\\"/, "\"", val)
      return val
    }
    return ""
  }

  function filter_tool(line,    name, rest, fp, cmd) {
    name = line
    sub(/[[:space:]].*/, "", name)
    rest = line
    sub(/^[^[:space:]]+[[:space:]]*/, "", rest)

    if (name == "Read") { fp = extract_json_field(rest, "file_path"); return "Read: " fp }
    if (name == "Edit") { fp = extract_json_field(rest, "file_path"); return "Edit: " fp }
    if (name == "Write") { fp = extract_json_field(rest, "file_path"); return "Write: " fp }
    if (name == "Bash") { cmd = extract_json_field(rest, "command"); return "Bash: " cmd }
    if (name == "Grep") return "Grep: " extract_json_field(rest, "pattern")
    if (name == "Glob") return "Glob: " extract_json_field(rest, "pattern")
    if (name == "Agent") return "Task: " extract_json_field(rest, "description")
    if (name == "WebFetch") return "Fetch: " extract_json_field(rest, "url")
    if (name == "ToolSearch") return "ToolSearch: " extract_json_field(rest, "query")
    if (name == "Skill") return "Skill: " extract_json_field(rest, "skill")
    if (name == "LSP") return "LSP"
    if (name == "SendMessage") return "SendMessage: " extract_json_field(rest, "to")
    if (name ~ /^(TodoWrite|TaskCreate|TaskUpdate|TaskGet|TaskList)$/) return ""
    return name
  }

  function flush_turn() {
    if (turn <= last_turn) return
    if (user_text == "") return

    # Title: first line, max 120 chars
    title = user_text
    sub(/\n.*/, "", title)
    if (length(title) > 120) title = substr(title, 1, 117) "..."

    # Build content
    body = "User: " user_text "\n"
    if (asst_text != "") body = body "\nAgent: " asst_text "\n"
    if (tool_lines != "") body = body "\n" tool_lines

    # Escape for JSON
    gsub(/\\/, "\\\\", title); gsub(/"/, "\\\"", title); gsub(/\t/, "\\t", title); gsub(/\n/, " ", title)
    gsub(/\\/, "\\\\", body); gsub(/"/, "\\\"", body); gsub(/\t/, "\\t", body); gsub(/\n/, "\\n", body)

    # Build metadata
    meta = "{\"session_id\":\"" session_id "\",\"turn_number\":" turn
    if (branch != "") meta = meta ",\"branch\":\"" branch "\""
    if (commit != "") meta = meta ",\"commit\":\"" commit "\""
    meta = meta "}"

    # Output as tab-separated: title \t content \t metadata
    print title "\t" body "\t" meta
  }

  /^\[(USER|ASST|TOOL|HOOK|SYSTEM)\]/ {
    new_tag = $0
    sub(/\].*/, "", new_tag)
    sub(/\[/, "", new_tag)
    line_content = $0
    sub(/^\[[A-Z]+\][[:space:]]?/, "", line_content)

    if (new_tag == "USER" && is_real_user(line_content)) {
      flush_turn()
      turn++
      user_text = line_content
      asst_text = ""
      tool_lines = ""
    } else if (new_tag == "ASST" && turn > 0) {
      if (asst_text != "") asst_text = asst_text "\n"
      asst_text = asst_text line_content
    } else if (new_tag == "TOOL" && turn > 0) {
      filtered = filter_tool(line_content)
      if (filtered != "") {
        if (tool_lines != "") tool_lines = tool_lines "\n"
        tool_lines = tool_lines filtered
      }
    }
    tag = new_tag
    next
  }

  # Continuation lines
  tag == "USER" && turn > 0 { user_text = user_text "\n" $0 }
  tag == "ASST" && turn > 0 { asst_text = asst_text "\n" $0 }

  END { flush_turn() }
  ' | while IFS=$'\t' read -r title content metadata; do
    [ -z "$title" ] && continue
    hivemem write \
      --type conversation \
      --project "$PROJECT" \
      --title "$title" \
      --content "$content" \
      --classification observational \
      --metadata "$metadata" >/dev/null 2>&1 || true
  done

  # Update state with total turn count
  TOTAL_TURNS=$(echo "$TRANSCRIPT" | awk '
    /^\[USER\]/ {
      line = $0; sub(/^\[USER\][[:space:]]?/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "" && line !~ /^<system-reminder>/ && line !~ /^<command-/ && line !~ /^<local-command-/) turn++
    }
    END { print turn+0 }
  ')
  echo "$TOTAL_TURNS" > "$STATE_DIR/$SESSION_ID"
) >/dev/null 2>&1 &

exit 0
