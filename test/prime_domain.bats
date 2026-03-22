#!/usr/bin/env bats
# Tests for domain (tag-based) grouping in hivemem prime output.

load helpers.bash

setup() {
  local r1 r2 r3 r4 r5
  r1=$(make_record convention foundational "Use ESM imports" hm-c1 "" '["frontend", "js"]' "2026-01-01T00:00:00Z")
  r2=$(make_record pattern tactical "Repository pattern" hm-p1 "" '["backend", "arch"]' "2026-01-02T00:00:00Z")
  r3=$(make_record decision foundational "Chose Postgres" hm-d1 "" '["backend", "db"]' "2026-01-03T00:00:00Z")
  r4=$(make_record convention tactical "Always lint" hm-c2 "" '["frontend"]' "2026-01-04T00:00:00Z")
  r5=$(make_record reference tactical "API docs" hm-r1 "" '[]' "2026-01-05T00:00:00Z")

  MOCK_RECORDS="[$r1, $r2, $r3, $r4, $r5]"
  MOCK_RESPONSE=$(make_search_response "$MOCK_RECORDS")
}

@test "full markdown: records grouped by first tag as domain" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "## frontend"
  echo "$output" | grep -q "## backend"
}

@test "full markdown: tagless records appear under General" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "## General"
}

@test "full markdown: domain sections contain their records" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  # "Use ESM imports" has tag frontend, should appear after frontend header
  local frontend_line esm_line
  frontend_line=$(echo "$output" | grep -n "## frontend" | head -1 | cut -d: -f1)
  esm_line=$(echo "$output" | grep -n "Use ESM imports" | head -1 | cut -d: -f1)
  [ "$esm_line" -gt "$frontend_line" ]
}

@test "compact markdown: records show domain tag inline" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact 0
  [ "$status" -eq 0 ]
  # Records should have their type shown
  echo "$output" | grep -q "\[convention\].*Use ESM"
}

@test "plain full: domain sections with type sub-grouping" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj plain full 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "frontend"
  echo "$output" | grep -q "backend"
}

@test "xml: records retain tags attribute" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj xml compact 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'tags="frontend js"'
  echo "$output" | grep -q 'tags="backend arch"'
}
