#!/usr/bin/env bats
# Tests for token budget in hivemem prime output.
# Default 4k, --budget overrides, --no-limit disables, chars/4 counting.

load helpers.bash

setup() {
  # Build 10 records with long titles to consume token budget
  local records=()
  local types=(convention convention decision pattern guide failure reference convention pattern decision)
  local classes=(foundational tactical foundational tactical tactical foundational tactical observational observational observational)
  for i in $(seq 0 9); do
    local title="Record number $i with a reasonably long title to consume some tokens for budget testing purposes here"
    records+=("$(make_record "${types[$i]}" "${classes[$i]}" "$title" "hm-rec$i" "Summary for record $i that adds more tokens" '["test"]' "2026-01-$(printf '%02d' $((i+1)))T00:00:00Z")")
  done

  local joined
  joined=$(IFS=','; echo "${records[*]}")
  MOCK_RECORDS="[$joined]"
  MOCK_RESPONSE=$(make_search_response "$MOCK_RECORDS")
}

@test "default budget is 4000 tokens" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact
  [ "$status" -eq 0 ]
  # Output should be within 4000 tokens (~16000 chars)
  local char_count=${#output}
  [ "$char_count" -le 16000 ]
}

@test "--budget 100 truncates output significantly" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact 100
  [ "$status" -eq 0 ]
  # With budget=100 (~400 chars), most records should be dropped
  # Should contain a truncation message
  echo "$output" | grep -q "more record"
}

@test "--no-limit shows all records" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact 0
  [ "$status" -eq 0 ]
  # Budget=0 means no limit; all 10 records should appear
  local record_count
  record_count=$(echo "$output" | grep -c '^\- \[')
  [ "$record_count" -eq 10 ]
}

@test "truncation message shows dropped count" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact 100
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "[0-9]+ more record"
}

@test "budget keeps high-priority records (conventions first)" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact 200
  [ "$status" -eq 0 ]
  # Conventions should survive since they have highest priority
  echo "$output" | grep -q "\[convention\]"
}

@test "budget drops low-priority records first (references)" {
  # With a tight budget, references should be first to go
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact 300
  [ "$status" -eq 0 ]
  # If any records are dropped, references go first
  if echo "$output" | grep -q "more record"; then
    # References should NOT appear if budget is tight
    ! echo "$output" | grep -q "\[reference\]"
  fi
}

@test "json format ignores budget" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj json compact 100
  [ "$status" -eq 0 ]
  # JSON should contain all 10 records regardless of budget
  local record_count
  record_count=$(echo "$output" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["records"]))')
  [ "$record_count" -eq 10 ]
}

@test "budget uses chars/4 estimation" {
  # Create a single record with a known-length title (100 chars = 25 tokens)
  local title
  title=$(printf 'x%.0s' $(seq 1 100))
  local rec
  rec=$(make_record convention foundational "$title" hm-exact "" '[]' "2026-01-01T00:00:00Z")
  local response
  response=$(make_search_response "[$rec]")

  # With budget of 1 token, the record itself won't fit but header will partially render
  run run_prime_formatter "$response" testproj markdown compact 1
  [ "$status" -eq 0 ]
  # The record should be dropped due to tiny budget
  echo "$output" | grep -q "more record" || ! echo "$output" | grep -q "$title"
}

@test "plain format respects budget" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj plain compact 200
  [ "$status" -eq 0 ]
  local char_count=${#output}
  # Should be reasonably small given 200 token budget
  [ "$char_count" -le 2000 ]
}

@test "xml format respects budget" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj xml compact 200
  [ "$status" -eq 0 ]
  # Should still be valid XML (has closing tag or self-closing)
  echo "$output" | grep -q "</expertise>" || echo "$output" | grep -q "/>"
}
