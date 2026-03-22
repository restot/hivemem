#!/usr/bin/env bats
# Tests for Rules and Recording Examples sections in full mode output.

load helpers.bash

setup() {
  local r1
  r1=$(make_record convention foundational "Use ESM imports" hm-c1 "" '["core"]' "2026-01-01T00:00:00Z")
  MOCK_RECORDS="[$r1]"
  MOCK_RESPONSE=$(make_search_response "$MOCK_RECORDS")
}

@test "full markdown: includes Rules section" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "## Rules"
}

@test "full markdown: rules mention /hm-record" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "/hm-record"
}

@test "full markdown: includes Recording Examples section" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Recording"
}

@test "full markdown: recording examples cover all 6 types" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "convention"
  echo "$output" | grep -q "pattern"
  echo "$output" | grep -q "decision"
  echo "$output" | grep -q "failure"
  echo "$output" | grep -q "reference"
  echo "$output" | grep -q "guide"
}

@test "full markdown: includes required fields table" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  # Should have a table with type and required fields
  echo "$output" | grep -q "description"
  echo "$output" | grep -q "rationale"
}

@test "compact markdown: omits Rules and Recording sections" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact 0
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "## Rules"
  ! echo "$output" | grep -q "Recording"
}

@test "full markdown: references hivemem commands not mulch" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "mulch record"
  ! echo "$output" | grep -q "mulch prime"
  echo "$output" | grep -q "/hm-record"
}

@test "full markdown: includes session close checklist" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown full 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "SESSION CLOSE"
}

@test "compact markdown: still has quick reference" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact 0
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Quick Reference"
}
