#!/usr/bin/env bash
set -euo pipefail

portfolio=${1:?usage: refresh-risk-portfolio.sh OLD_PORTFOLIO SNAPSHOT OUTPUT}
snapshot=${2:?usage: refresh-risk-portfolio.sh OLD_PORTFOLIO SNAPSHOT OUTPUT}
output=${3:?usage: refresh-risk-portfolio.sh OLD_PORTFOLIO SNAPSHOT OUTPUT}

[[ -f "$portfolio" && -f "$snapshot" ]] || {
  printf 'risk portfolio or snapshot not found\n' >&2
  exit 2
}

observed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
valid_until=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
evidence_map=$(mktemp)
trap 'rm -f -- "$evidence_map"' EXIT

jq -r '.[] | .snapshot.evidence[]?.path, .evidence[]?.path' "$portfolio" \
  | awk 'NF && !seen[$0]++' \
  | while IFS= read -r path; do
      if [[ -f "$path" ]]; then
        printf '%s\t%s\n' "$path" "$(sha256sum -- "$path" | awk '{print $1}')"
      fi
    done > "$evidence_map"

jq --arg observed_at "$observed_at" \
   --arg valid_until "$valid_until" \
   --rawfile evidence_map "$evidence_map" \
   --slurpfile snapshot "$snapshot" '
  def current_digest($path):
    (($evidence_map | split("\n") | map(select(length > 0) | split("\t"))
      | map(select(.[0] == $path) | .[1]) | .[0]) // "MISSING");
  def current_state($task):
    (($snapshot[0].tasks // []) | map(select(.id == $task) | .state) | .[0]) // "UNKNOWN";
  def current_dependencies($task):
    (($snapshot[0].tasks // []) | map(select(.id == $task) | (.dependencies // [])) | .[0]) // [];
  def current_worker($task):
    (($snapshot[0].tasks // []) | map(select(.id == $task) | (.worker // "")) | .[0]) // "";
  def refresh_evidence:
    map(if .path then .sha256 = current_digest(.path) | .observed_at = $observed_at else . end);
  (map(
    .assessment_id = (.assessment_id + "-refresh-" + ($observed_at | gsub("[^0-9]"; "")))
    | .observed_at = $observed_at
    | .valid_until = $valid_until
    | .task_state = current_state(.task_id)
    | .dependencies = current_dependencies(.task_id)
    | if current_worker(.task_id) != "" then .actor = current_worker(.task_id) else . end
    | if .snapshot.evidence then .snapshot.evidence |= refresh_evidence else . end
    | if .evidence then .evidence |= refresh_evidence else . end
    | .snapshot.reference = ((.snapshot.reference // "") + "; refreshed from canonical Sa-plan snapshot and current source bytes")
  )) as $refreshed
  | (($snapshot[0].tasks // []) | map(.id) - ($refreshed | map(.task_id))) as $missing
  | $refreshed + [
      $missing[] as $task
      | ($refreshed[0]
        | .assessment_id = ("successor-" + $task + "-" + ($observed_at | gsub("[^0-9]"; "")))
        | .task_id = $task
        | .task_state = current_state($task)
        | .dependencies = current_dependencies($task)
        | if current_worker($task) != "" then .actor = current_worker($task) else . end
        | .ready_since = $observed_at
        | .scope = "Successor portfolio placeholder; task-specific evidence requires independent re-observation."
        | .snapshot.reference = "Generated to conserve the canonical Sa-plan task set; not completion evidence."
      )
    ]
' "$portfolio" > "$output"

jq empty "$output"
printf 'refreshed=%s observed_at=%s\n' "$output" "$observed_at"
