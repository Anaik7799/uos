#use "topfind";;
#require "yojson,cryptokit";;
let root = "/home/an/NAS-setup/uos/.uos-workspaces/ev98-health-formal-20260909/"
let sha path = let c=open_in_bin (root^path) in Fun.protect ~finally:(fun()->close_in_noerr c)(fun()->Cryptokit.hash_channel (Cryptokit.Hash.sha256()) c |> Cryptokit.transform_string (Cryptokit.Hexa.encode()))
let () =
 let output = root ^ "docs/reviews/20260909-1723-ev02-governance-evidence-binding.json" in
 let json = `Assoc [
  "schema",`String "uos.ev02-governance-evidence-binding/v1";
  "authority",`String "REPORT_ONLY";"admission",`String "NOT_GRANTED";
  "source_commit",`String "c9fcf183a6a322c044443dea66fc0f03ab58234d";
  "source_change_id",`String "nxuymvnlmrtulquvqxxlxntosumloyyn";
  "base_commit",`String "8152a497929d68f830385a1a887570f94ccebd77";
  "manifest",`Assoc ["path",`String "docs/reviews/20260909-1721-ev02-governance-manifest.json";"sha256",`String(sha "docs/reviews/20260909-1721-ev02-governance-manifest.json")];
  "risk",`Assoc ["path",`String "docs/reviews/20260909-1725-ev02-governance-risk.json";"sha256",`String(sha "docs/reviews/20260909-1725-ev02-governance-risk.json");"active_receipt",`String "/tmp/ev02-governance-active-final-attempt1-20260909-1722.json";"assessment_sha256",`String "d8b8fef9c4241f48ceeb3c128411e8d092a7335e827a07ce572f9a2adfb172d0"];
  "executions",`List [`String "docs/reviews/20260909-1716-ev02-governance-checks.json";`String "/tmp/ev02-governance-preflight-pass-20260909-1728.json";`String "/tmp/ev02-governance-claim-20260909-1728.json"];
  "holds",`List [`String "No immutable 38-family source/adaptation manifest";`String "Current policy surface observation: 33 union names, 32/32/32/33 per surface";`String "Current KM gate entropy HOLD";`String "No EV02 candidate-bound runtime/formal keys or authenticated independent review"]]
 in let c=open_out_bin output in Fun.protect ~finally:(fun()->close_out_noerr c)(fun()->output_string c (Yojson.Safe.pretty_to_string json^"\n"))
