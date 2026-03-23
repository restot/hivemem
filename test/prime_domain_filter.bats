#!/usr/bin/env bats
# Tests for --domain / --exclude-domain filtering in hivemem prime.

load helpers.bash

setup() {
  cli=$(make_record convention foundational "Use JSON" hm-c1 "Always use JSON" '["api"]')
  mcp=$(make_record pattern tactical "MCP config pattern" hm-p1 "Use .mcp.json" '["mcp"]')
  tls=$(make_record failure tactical "TLS cert issue" hm-f1 "SAN mismatch" '["tls"]')
  general=$(make_record reference tactical "General ref" hm-r1 "No tags" '[]')
  response=$(make_search_response "[$cli, $mcp, $tls, $general]")
}

@test "no filter: all records shown" {
  run run_prime_formatter "$response" "test" "markdown" "compact" "0"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"hm-c1"* ]]
  [[ "$output" == *"hm-p1"* ]]
  [[ "$output" == *"hm-f1"* ]]
  [[ "$output" == *"hm-r1"* ]]
}

@test "--domain api: only api records" {
  run run_prime_formatter "$response" "test" "markdown" "compact" "0" "api" ""
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"hm-c1"* ]]
  [[ "$output" != *"hm-p1"* ]]
  [[ "$output" != *"hm-f1"* ]]
  [[ "$output" != *"hm-r1"* ]]
}

@test "--domain multiple: api,tls shows both" {
  run run_prime_formatter "$response" "test" "markdown" "compact" "0" "api,tls" ""
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"hm-c1"* ]]
  [[ "$output" != *"hm-p1"* ]]
  [[ "$output" == *"hm-f1"* ]]
  [[ "$output" != *"hm-r1"* ]]
}

@test "--exclude-domain tls: all except tls" {
  run run_prime_formatter "$response" "test" "markdown" "compact" "0" "" "tls"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"hm-c1"* ]]
  [[ "$output" == *"hm-p1"* ]]
  [[ "$output" != *"hm-f1"* ]]
  [[ "$output" == *"hm-r1"* ]]
}

@test "--exclude-domain multiple: api,mcp excludes both" {
  run run_prime_formatter "$response" "test" "markdown" "compact" "0" "" "api,mcp"
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"hm-c1"* ]]
  [[ "$output" != *"hm-p1"* ]]
  [[ "$output" == *"hm-f1"* ]]
  [[ "$output" == *"hm-r1"* ]]
}

@test "--domain General: matches tagless records" {
  run run_prime_formatter "$response" "test" "markdown" "compact" "0" "General" ""
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"hm-c1"* ]]
  [[ "$output" == *"hm-r1"* ]]
}

@test "domain filter updates record count in header" {
  run run_prime_formatter "$response" "test" "markdown" "compact" "0" "api" ""
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"1 record"* ]]
}

@test "full mode: domain filter limits domain sections" {
  run run_prime_formatter "$response" "test" "markdown" "full" "0" "api" ""
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"api"* ]]
  [[ "$output" != *"## mcp"* ]]
  [[ "$output" != *"## tls"* ]]
}
