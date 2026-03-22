#!/usr/bin/env bats
# Tests for priority ranking in hivemem prime output.
# Records should be sorted: type > classification > recency.

load helpers.bash

setup() {
  # Build records in deliberately wrong order (should be re-sorted)
  local ref guide conv decision pattern failure

  ref=$(make_record reference tactical "API docs link" hm-ref1 "" '["api"]' "2026-01-05T00:00:00Z")
  guide=$(make_record guide tactical "How to deploy" hm-guide1 "" '["ops"]' "2026-01-04T00:00:00Z")
  failure=$(make_record failure foundational "DB migration broke" hm-fail1 "" '["db"]' "2026-01-03T00:00:00Z")
  decision=$(make_record decision foundational "Chose Postgres" hm-dec1 "" '["db"]' "2026-01-02T00:00:00Z")
  pattern=$(make_record pattern tactical "Repository pattern" hm-pat1 "" '["arch"]' "2026-01-01T00:00:00Z")
  conv=$(make_record convention foundational "Always use ESM" hm-conv1 "" '["js"]' "2026-01-06T00:00:00Z")

  # Feed them in wrong order: ref, guide, failure, decision, pattern, conv
  MOCK_RECORDS="[$ref, $guide, $failure, $decision, $pattern, $conv]"
  MOCK_RESPONSE=$(make_search_response "$MOCK_RECORDS")
}

@test "compact markdown: conventions appear before decisions" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact
  [ "$status" -eq 0 ]
  # Find line numbers of convention and decision
  local conv_line dec_line
  conv_line=$(echo "$output" | grep -n "\[convention\]" | head -1 | cut -d: -f1)
  dec_line=$(echo "$output" | grep -n "\[decision\]" | head -1 | cut -d: -f1)
  [ "$conv_line" -lt "$dec_line" ]
}

@test "compact markdown: decisions appear before patterns" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact
  [ "$status" -eq 0 ]
  local dec_line pat_line
  dec_line=$(echo "$output" | grep -n "\[decision\]" | head -1 | cut -d: -f1)
  pat_line=$(echo "$output" | grep -n "\[pattern\]" | head -1 | cut -d: -f1)
  [ "$dec_line" -lt "$pat_line" ]
}

@test "compact markdown: references appear last" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact
  [ "$status" -eq 0 ]
  local ref_line guide_line
  ref_line=$(echo "$output" | grep -n "\[reference\]" | head -1 | cut -d: -f1)
  guide_line=$(echo "$output" | grep -n "\[guide\]" | head -1 | cut -d: -f1)
  [ "$ref_line" -gt "$guide_line" ]
}

@test "type priority: convention > decision > pattern > guide > failure > reference" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj markdown compact
  [ "$status" -eq 0 ]

  local conv_line dec_line pat_line guide_line fail_line ref_line
  conv_line=$(echo "$output" | grep -n "\[convention\]" | head -1 | cut -d: -f1)
  dec_line=$(echo "$output" | grep -n "\[decision\]" | head -1 | cut -d: -f1)
  pat_line=$(echo "$output" | grep -n "\[pattern\]" | head -1 | cut -d: -f1)
  guide_line=$(echo "$output" | grep -n "\[guide\]" | head -1 | cut -d: -f1)
  fail_line=$(echo "$output" | grep -n "\[failure\]" | head -1 | cut -d: -f1)
  ref_line=$(echo "$output" | grep -n "\[reference\]" | head -1 | cut -d: -f1)

  [ "$conv_line" -lt "$dec_line" ]
  [ "$dec_line" -lt "$pat_line" ]
  [ "$pat_line" -lt "$guide_line" ]
  [ "$guide_line" -lt "$fail_line" ]
  [ "$fail_line" -lt "$ref_line" ]
}

@test "classification: foundational before tactical within same type" {
  local conv_found conv_tact
  conv_found=$(make_record convention foundational "Foundational conv" hm-cf1 "" '[]' "2026-01-01T00:00:00Z")
  conv_tact=$(make_record convention tactical "Tactical conv" hm-ct1 "" '[]' "2026-01-02T00:00:00Z")

  # Feed tactical first — should be reordered
  local records="[$conv_tact, $conv_found]"
  local response
  response=$(make_search_response "$records")

  run run_prime_formatter "$response" testproj markdown compact
  [ "$status" -eq 0 ]

  local found_line tact_line
  found_line=$(echo "$output" | grep -n "Foundational conv" | head -1 | cut -d: -f1)
  tact_line=$(echo "$output" | grep -n "Tactical conv" | head -1 | cut -d: -f1)
  [ "$found_line" -lt "$tact_line" ]
}

@test "classification: tactical before observational within same type" {
  local conv_tact conv_obs
  conv_tact=$(make_record convention tactical "Tactical conv" hm-ct1 "" '[]' "2026-01-01T00:00:00Z")
  conv_obs=$(make_record convention observational "Observational conv" hm-co1 "" '[]' "2026-01-02T00:00:00Z")

  local records="[$conv_obs, $conv_tact]"
  local response
  response=$(make_search_response "$records")

  run run_prime_formatter "$response" testproj markdown compact
  [ "$status" -eq 0 ]

  local tact_line obs_line
  tact_line=$(echo "$output" | grep -n "Tactical conv" | head -1 | cut -d: -f1)
  obs_line=$(echo "$output" | grep -n "Observational conv" | head -1 | cut -d: -f1)
  [ "$tact_line" -lt "$obs_line" ]
}

@test "recency: newer records first within same type+classification" {
  local old_rec new_rec
  old_rec=$(make_record convention foundational "Old convention" hm-old "" '[]' "2025-01-01T00:00:00Z")
  new_rec=$(make_record convention foundational "New convention" hm-new "" '[]' "2026-06-01T00:00:00Z")

  local records="[$old_rec, $new_rec]"
  local response
  response=$(make_search_response "$records")

  run run_prime_formatter "$response" testproj markdown compact
  [ "$status" -eq 0 ]

  local old_line new_line
  old_line=$(echo "$output" | grep -n "Old convention" | head -1 | cut -d: -f1)
  new_line=$(echo "$output" | grep -n "New convention" | head -1 | cut -d: -f1)
  [ "$new_line" -lt "$old_line" ]
}

@test "full mode: type subsections follow priority order within domain" {
  # All records share the same domain tag so they group together
  local conv dec pat
  conv=$(make_record convention foundational "Use ESM" hm-c1 "" '["core"]' "2026-01-01T00:00:00Z")
  dec=$(make_record decision foundational "Chose PG" hm-d1 "" '["core"]' "2026-01-02T00:00:00Z")
  pat=$(make_record pattern tactical "Repo pattern" hm-p1 "" '["core"]' "2026-01-03T00:00:00Z")
  local records="[$pat, $dec, $conv]"
  local response
  response=$(make_search_response "$records")

  run run_prime_formatter "$response" testproj markdown full 0
  [ "$status" -eq 0 ]

  local conv_line dec_line pat_line
  conv_line=$(echo "$output" | grep -n "### Conventions" | head -1 | cut -d: -f1)
  dec_line=$(echo "$output" | grep -n "### Decisions" | head -1 | cut -d: -f1)
  pat_line=$(echo "$output" | grep -n "### Patterns" | head -1 | cut -d: -f1)
  [ "$conv_line" -lt "$dec_line" ]
  [ "$dec_line" -lt "$pat_line" ]
}

@test "plain format: records sorted by priority" {
  run run_prime_formatter "$MOCK_RESPONSE" testproj plain compact
  [ "$status" -eq 0 ]

  local conv_line ref_line
  conv_line=$(echo "$output" | grep -n "\[convention\]" | head -1 | cut -d: -f1)
  ref_line=$(echo "$output" | grep -n "\[reference\]" | head -1 | cut -d: -f1)
  [ "$conv_line" -lt "$ref_line" ]
}
