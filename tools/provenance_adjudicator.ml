(* tools/provenance_adjudicator.ml
   OI01 EV94..109 provenance adjudicator CLI. REPORT_ONLY; EV94..109 stay
   NOT_ADMITTED, ceiling 93. Exit 0 means only that a well-formed report was
   produced from caller assertions; it is not verification, admission, or task
   completion.

   Run from the workspace root with the pinned toplevel:
     /home/an/NAS-setup/uos/toolchains/opam-ocaml/bin/ocaml tools/provenance_adjudicator.ml [--stdin] < report.json

   Default input: stdin only, at most 262144 bytes (one extra sentinel byte is read to
   refuse oversize input). No file paths are read. Arguments: none or --stdin;
   anything else is a typed HOLD with exit 2, before stdin is touched.
   Malformed, nonstandard or oversize input is a typed HOLD with exit 2.
   --scan instead collects bounded read-only observations from the current
   standalone JJ workspace. It observes candidate bytes and ancestry itself;
   caller-supplied candidates/locators are not accepted in this mode. Its
   report remains HOLD/NOT_ADMITTED with no two-key or sovereign authority.
   --validate-observed checks bounded stdin against the strict observed-artifact
   schema. Its success authenticates neither local observations nor signatures.
   Exit zero means a report was produced, never admission or whole-task success.
   Unexpected faults are not masked by a blanket handler. *)

#use "topfind";;
#require "bos.setup,yojson,cryptokit,unix,str,mtime.clock.os";;
#mod_use "km_provenance/km_adjudication.ml";;
open Km_adjudication;;
#mod_use "km_provenance/km_forensic_scan.ml";;
#mod_use "km_provenance/km_forensic_schema.ml";;

let max_input = 262144
let chunk_size = 4096

(* Reads at most max_input + 1 bytes; the extra byte is the oversize sentinel. *)
let read_bounded_stdin () : (string, string) result =
  set_binary_mode_in stdin true;
  let buf = Buffer.create chunk_size in
  let chunk = Bytes.create chunk_size in
  let rec fill () =
    let want = min chunk_size (max_input + 1 - Buffer.length buf) in
    if want > 0 then
      match input stdin chunk 0 want with
      | 0 -> ()
      | n -> Buffer.add_subbytes buf chunk 0 n; fill ()
  in
  match fill () with
  | () ->
      if Buffer.length buf > max_input then Error "input exceeds 262144 bytes"
      else Ok (Buffer.contents buf)
  | exception Sys_error m -> Error ("stdin read failed: " ^ m)

let hold_json (msg : string) : Yojson.Safe.t =
  `Assoc [
    ("status", `String "HOLD");
    ("authority", `String "NONE");
    ("detail", `String msg);
    ("admitted_ev_ceiling", `Int 93);
    ("application_admitted", `Bool false);
    ("system_admitted", `Bool false);
    ("readback_verified", `Bool false);
  ]

let print_json (j : Yojson.Safe.t) : unit =
  print_endline (Yojson.Safe.to_string j)

let hold msg = print_json (hold_json msg); exit 2

let () =
  match List.tl (Array.to_list Sys.argv) with
  | ["--scan"] ->
      let report = Km_forensic_scan.scan ~root:(Sys.getcwd ()) in
      let json = Km_forensic_scan.to_json report in
      (match Km_forensic_schema.validate (Yojson.Safe.to_string json) with
       | Error msg -> hold ("generated observed schema: " ^ msg)
       | Ok _ -> print_json json);
      (match report.candidate with None -> exit 2 | Some _ -> exit 0)
  | ["--validate-observed"] ->
      (match read_bounded_stdin () with
       | Error msg -> hold msg
       | Ok input ->
           match Km_forensic_schema.validate input with
           | Error msg -> hold msg
           | Ok summary -> print_json (Km_forensic_schema.summary_to_json summary); exit 0)
  | [] | ["--stdin"] ->
      (match read_bounded_stdin () with
       | Error msg -> hold msg
       | Ok input ->
           (match Adjudicator.adjudicate input with
            | Ok report -> print_json report; exit 0
            | Error msg -> hold msg))
  | _ -> hold "unknown arguments"
