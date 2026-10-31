open Km_forensic_scan

let checks = ref 0
let check name b = incr checks; if not b then failwith name
let rec mkdir p = if not (Sys.file_exists p) then (mkdir (Filename.dirname p); Unix.mkdir p 0o700)
let write root rel bytes = let p = Filename.concat root rel in mkdir (Filename.dirname p);
  let oc = open_out_bin p in Fun.protect ~finally:(fun () -> close_out oc) (fun () -> output_string oc bytes)
let remove root rel = Unix.unlink (Filename.concat root rel)
let candidate = String.make 40 'a'
let code_path = "apps/fixture/src/fixture.gleam"
let doc_path adr = Printf.sprintf "docs/zk/20261031-1500-adr-%03d-fixture.md" adr
let with_fixture f =
  let root = Filename.temp_file "uos-oi01a-" "" in Unix.unlink root; Unix.mkdir root 0o700;
  let tree = Hashtbl.create 32 in
  let put rel bytes = write root rel bytes; Hashtbl.replace tree rel bytes in
  let run = function
    | Ancestry -> Ok ("H1\nP" ^ candidate ^ "\nA" ^ String.make 40 'b' ^ "\n")
    | Candidate_bytes (rev,path) -> if rev <> candidate then Error Unbound else
        (match Hashtbl.find_opt tree path with Some b -> Ok b | None -> Error Missing) in
  Fun.protect ~finally:(fun () -> ignore (Bos.OS.Dir.delete ~recurse:true (Fpath.v root))) (fun () ->
    mkdir (Filename.concat root receipt_dir);
    mkdir (Filename.concat root quarantine_dir);
    Unix.mkfifo (Filename.concat root (quarantine_dir ^ "/0000000422-fixture.json")) 0o600;
    put code_path "pub fn main() { Nil }\n";
    for adr = 71 to 86 do put (doc_path adr) ("Historical record `" ^ code_path ^ "`\n") done;
    f root put run)
let first r = List.hd r.claims
let has_gap (c:claim) g = List.exists (fun (_,x) -> x=g) c.gaps
let receipt bytes_digest = Yojson.Safe.to_string (`Assoc [
  "schema",`String "uos-forensic-receipt-v1";"kind",`String "runtime";
  "candidate_commit",`String candidate;"source_path",`String code_path;
  "source_sha256",`String bytes_digest;"reviewer",`String "codex";"signature",`String "unsigned-fixture"])
let receipt_path = receipt_dir ^ "/20261031-1500-ev-094-runtime.receipt.json"
let () =
  with_fixture (fun root _ run ->
    let r = scan_fixture ~root ~run in
    check "exact sixteen partition" (List.map (fun c -> c.ev,c.adr) r.claims = List.init 16 (fun i -> 94+i,71+i));
    check "observed candidate" (r.candidate = Some candidate);
    check "all files bound" (List.for_all (fun s -> s.binding=Candidate_bound) r.sources);
    check "actual source presence recommendation" ((first r).recommendation = Some "CODE_PRESENT_REQUIRES_FRESH_TWO_KEY_REBIND");
    check "missing receipt is unrun" (has_gap (first r) Unrun);
    check "quarantine fifo observed without blocking read" (List.length r.quarantine_presence=1);
    check "stable complete snapshot" (r.source_map_sha256=(scan_fixture ~root ~run).source_map_sha256);
    let rendered = Yojson.Safe.to_string (to_json r) in
    check "no raw document bytes" (not (try ignore (Str.search_forward (Str.regexp_string "Historical record") rendered 0); true with Not_found -> false));
    check "report never admits" (Yojson.Safe.Util.member "two_key_verified" (to_json r) = `Bool false);
    List.iter (fun key -> check ("closed flag "^key)
      (Yojson.Safe.Util.member key (to_json r)=`Bool false))
      ["application_admitted";"system_admitted";"readback_verified"];
    check "ceiling remains93" (Yojson.Safe.Util.member "admitted_ev_ceiling" (to_json r)=`Int 93);
    check "fixture visibly labelled" (r.origin=Synthetic_fixture));
  with_fixture (fun root _ run ->
    write root code_path "pub fn main() { 9 }\n";
    let r = scan_fixture ~root ~run in
    check "dirty byte guard" (has_gap (first r) Unbound);
    check "dirty source cannot bind" ((List.hd (first r).code).binding=Dirty_binding));
  with_fixture (fun root _ run ->
    remove root code_path; Unix.symlink "/etc/passwd" (Filename.concat root code_path);
    check "symlink refused" (has_gap (first (scan_fixture ~root ~run)) Unsafe));
  with_fixture (fun root _ run ->
    let alias = "apps/fixture/src/hard.erl" in Unix.link (Filename.concat root code_path) (Filename.concat root alias);
    check "hardlink refused" (has_gap (first (scan_fixture ~root ~run)) Unsafe));
  with_fixture (fun root put run ->
    put "docs/zk/20261031-1501-adr-071-second.md" "duplicate";
    check "duplicate ADR ambiguous" (has_gap (first (scan_fixture ~root ~run)) Ambiguous));
  with_fixture (fun root _ run ->
    remove root (doc_path 71);
    check "missing ADR gap" (has_gap (first (scan_fixture ~root ~run)) Missing));
  with_fixture (fun root put run ->
    put receipt_path (receipt (hash "pub fn main() { Nil }\n"));
    let c = first (scan_fixture ~root ~run) in
    check "bound unsigned receipt never authority" (has_gap c Unverified_signature);
    check "receipt candidate bound byte observation" ((List.hd c.receipts).binding=Candidate_bound));
  with_fixture (fun root put run ->
    put receipt_path (receipt (String.make 64 '0'));
    check "mismatched receipt digest" (has_gap (first (scan_fixture ~root ~run)) Invalid_receipt));
  with_fixture (fun root put run ->
    put receipt_path "{\"schema\":\"x\",\"schema\":\"x\"}";
    check "duplicate receipt fields" (has_gap (first (scan_fixture ~root ~run)) Invalid_receipt));
  with_fixture (fun root put run ->
    put (doc_path 71) ("`apps/fixture/src/../../secret.gleam` `var/private.erl` `" ^ code_path ^ "`");
    let c=first (scan_fixture ~root ~run) in
    check "traversal refs not opened" (List.map (fun s -> s.path) c.code=[code_path]);
    check "traversal gets typed unsafe gap" (has_gap c Unsafe));
  with_fixture (fun root put run ->
    put code_path (String.make (max_file+1) 'x');
    check "file bound before full read" (has_gap (first (scan_fixture ~root ~run)) Too_large));
  with_fixture (fun root _ run ->
    let count=ref 0 in
    let changed = function Ancestry -> incr count; if !count>1 then Ok (String.make 40 'c' ^ "\n") else run Ancestry
      | x -> run x in
    check "JJ parent changes rejected" (List.mem ("jj:ancestry",Changed) (scan_fixture ~root ~run:changed).gaps));
  with_fixture (fun root _ run ->
    let changed = function Candidate_bytes (_,p) as c ->
      let out=run c in if p=code_path then write root code_path "changed during observation"; out
      | x -> run x in
    check "midscan source change detected" (List.mem (code_path,Changed) (scan_fixture ~root ~run:changed).gaps));
  check "root proc refused" (match read_file "/proc" "version" 4096 with Error Unsafe -> true | _ -> false);
  check "relative traversal refused" (not (valid_relative "a/../b"));
  check "receipt deep input refused" (not (receipt_valid ~candidate:(Some candidate) ~sources:[] (String.make 30 '[')));
  with_fixture (fun root _ run ->
    let bad = function Ancestry -> Ok ("H2\nP" ^ candidate ^ "\nP" ^ String.make 40 'b' ^ "\n") | x -> run x in
    check "merge parent cannot silently select one" ((scan_fixture ~root ~run:bad).candidate=None));
  with_fixture (fun root _ run ->
    let bad = function Ancestry -> Ok ("H1\nP" ^ candidate ^ "\nA" ^ candidate ^ "\n") | x -> run x in
    check "duplicate ancestry commit refused" ((scan_fixture ~root ~run:bad).candidate=None));
  with_fixture (fun root put run ->
    put (receipt_dir ^ "/20261031-1501-ev-094-runtime.receipt.json") (receipt (hash "pub fn main() { Nil }\n"));
    let c=first (scan_fixture ~root ~run) in
    check "formal receipt missing explicitly unrun" (List.mem (receipt_dir ^ "/EV-094/formal",Unrun) c.gaps));
  with_fixture (fun root put run ->
    put (receipt_dir ^ "/20261031-1501-ev-094-formal.receipt.json") (receipt (hash "pub fn main() { Nil }\n"));
    check "receipt kind must match filename" (has_gap (first (scan_fixture ~root ~run)) Invalid_receipt));
  with_fixture (fun root put run ->
    List.iter (fun stamp -> put (receipt_dir ^ "/20261031-" ^ stamp ^ "-ev-094-runtime.receipt.json") "do-not-parse") ["1501";"1502";"1503"];
    let c=first (scan_fixture ~root ~run) in
    check "too many receipts ambiguous without reading" (has_gap c Ambiguous && c.receipts=[]));
  (* Twin seeds: independent reference interpretation fixes the source map's
     mathematical order, then arbitrary enumeration must preserve it. *)
  List.iter (fun seed ->
    let st = Random.State.make [|seed|] in
    for n=1 to 40 do
      let xs=List.init n (fun i -> {path=Printf.sprintf "apps/x/src/%03d.gleam" i;
        sha256=hash (string_of_int (Random.State.int st 9999)); binding=Candidate_bound}) in
      let oracle = List.sort (fun a b -> compare a.path b.path) xs |> List.map (fun x ->
        x.path ^ "\000" ^ x.sha256 ^ "\000BOUND") |> String.concat "\n" |> fun s -> hash (candidate ^ "\n" ^ s) in
      let shuffled = List.map (fun x -> Random.State.bits st,x) xs |> List.sort compare |> List.map snd in
      check "twin seed reference map" (source_map_hash ~candidate shuffled=oracle)
    done) [71;109];
  check "candidate belongs to map hash" (source_map_hash ~candidate [] <> source_map_hash ~candidate:(String.make 40 'b') []);
  Printf.printf "km_forensic_scan: %d checks passed; fixture observations only\n" !checks
