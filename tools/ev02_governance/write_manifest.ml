#use "topfind";;
#require "yojson,cryptokit";;
let root = "/home/an/NAS-setup/uos/.uos-workspaces/ev98-health-formal-20260909/"
let files = [
  "tools/ev02_governance/policy_surface_gate.ml";
  "tools/ev02_governance/run_checks.ml";
  "tools/ev02_governance/write_manifest.ml";
  "docs/reviews/20260909-1725-ev02-governance-risk.json";
  "docs/reviews/20260909-1716-ev02-governance-checks.json";
  "docs/reviews/20260909-1716-ev02-policy-selftest.out";
  "docs/reviews/20260909-1716-ev02-policy-observation.out";
  "docs/reviews/20260909-1716-ev02-km-gate.out";
  "docs/reviews/20260909-1716-ev02-km-ev-selftest.out";
  "docs/journal/20260909-1720-ev02-governance-dossier.md" ]
let sha path = let c=open_in_bin (root^path) in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->Cryptokit.hash_channel (Cryptokit.Hash.sha256()) c |> Cryptokit.transform_string (Cryptokit.Hexa.encode()))
let () =
  let entries = List.map (fun path -> `Assoc ["path", `String path; "sha256", `String (sha path)]) files in
  let output = root ^ "docs/reviews/20260909-1721-ev02-governance-manifest.json" in
  let c = open_out_bin output in Fun.protect ~finally:(fun()->close_out_noerr c) (fun () -> output_string c (Yojson.Safe.pretty_to_string (`Assoc ["schema",`String "uos.ev02-governance-manifest/v1";"authority",`String "REPORT_ONLY";"admission",`String "NOT_GRANTED";"base_commit",`String "8152a497929d68f830385a1a887570f94ccebd77";"files",`List entries]) ^ "\n"))
