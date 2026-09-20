#!/usr/bin/env bash
set -euo pipefail

base="governance/capability-inventory/20260921-0706-source-universe-ledger.json"
overlay="governance/capability-inventory/20260921-1312-source-universe-correction-overlay.json"
out="governance/capability-inventory/20260921-1316-source-universe-successor-ledger.json"

manifest_hash() {
  local path="$1"
  find "$path" -type f -not -path '*/build/*' -not -name '*.beam' -not -name '*.cache*' -print0 \
    | sort -z \
    | while IFS= read -r -d '' file; do sha256sum "$file"; done \
    | sha256sum | awk '{print $1}'
}

test_hash="$(manifest_hash apps/cepaf_gleam/test)"
swarm_hash="$(manifest_hash apps/uos_swarm/test)"
hermes_hash="$(manifest_hash engines/hermes/modules/sa_plan/test)"
rules_hash="$(manifest_hash contracts/rules)"

jq --arg test_hash "$test_hash" \
   --arg swarm_hash "$swarm_hash" \
   --arg hermes_hash "$hermes_hash" \
   --arg rules_hash "$rules_hash" \
   --slurpfile overlay "$overlay" '
  . as $base
  | ($overlay[0]) as $o
  | ($o.wrapper_repairs | map({key:.id,value:.source_sha256}) | from_entries) as $pins
  | ($o.edge_repairs | group_by(.from) | map({key:.[0].from,value:(map(.to))}) | from_entries) as $edges
  | .records = ([ $base.records[]
      | .source_sha256 = ($pins[.id] // .source_sha256)
      | .edges = ($edges[.id] // [])
    ] + [
      {id:"test.cepaf_gleam",kind:"test",path:"apps/cepaf_gleam/test",source_sha256:$test_hash,status:"DECLARED_TEST_SET",edges:[],mcp:{server:null,capability:null,availability:"UNKNOWN"}},
      {id:"test.uos_swarm",kind:"test",path:"apps/uos_swarm/test",source_sha256:$swarm_hash,status:"DECLARED_TEST_SET",edges:[],mcp:{server:null,capability:null,availability:"UNKNOWN"}},
      {id:"test.hermes_sa_plan",kind:"test",path:"engines/hermes/modules/sa_plan/test",source_sha256:$hermes_hash,status:"DECLARED_TEST_SET",edges:[],mcp:{server:null,capability:null,availability:"UNKNOWN"}},
      {id:"reference.uos_rules",kind:"reference_only",path:"contracts/rules",source_sha256:$rules_hash,status:"REFERENCE_ONLY",edges:[],mcp:{server:null,capability:null,availability:"UNKNOWN"}}
    ])
  | .schema = "uos.source-universe-ledger.v2"
  | .created_at = "2026-09-21T13:16:00Z"
  | .successor_of = "governance/capability-inventory/20260921-0706-source-universe-ledger.json"
  | .reconciliation = {overlay:"governance/capability-inventory/20260921-1312-source-universe-correction-overlay.json",historical_preserved:true,typed_edges:true,source_manifest_excludes:["build artifacts","beam artifacts","cache artifacts"]}
  | .scope.directory_observation = "bounded source manifest with explicit build/cache exclusions; external trees excluded"
' "$base" > "$out"

jq empty "$out"
printf 'successor=%s\n' "$out"
