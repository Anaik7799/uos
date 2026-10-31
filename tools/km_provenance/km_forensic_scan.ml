(* OI01A, Codex relay implementation; report-only local observations.
   Signature/effect laws: scan reads a fixed allowlist; it never mutates source,
   VCS, status or admission. Exactly sixteen EV/ADR pairs are emitted. A binding
   requires byte equality with the observed JJ parent, not a caller assertion.
   Sorting observations makes the map hash independent of enumeration order.
   Missing, unsafe, changed or unverifiable evidence is a typed gap, never proof.
   Quarantine is directory metadata ONLY: its payloads are never opened/hashed.
   Descriptor/path identity checks detect changes but do not provide openat-style
   hostile-directory isolation; a quiesced/frozen root remains a release premise.
   Sanitized receipt namespace: governance/provenance/receipts/
   YYYYMMDD-HHSS-ev-NNN-KIND.receipt.json, KIND runtime or formal. Schema below.
   No cryptographic reviewer verifier is present: even bound receipts stay
   UNVERIFIED_SIGNATURE and cannot establish a fresh two-key observation. *)

type gap = Missing | Unsafe | Changed | Too_large | Ambiguous | Unbound
         | Unrun | Invalid_receipt | Unverified_signature | Process_failure
type binding = Candidate_bound | Dirty_binding
type source = { path : string; sha256 : string; binding : binding }
type claim = { ev : int; adr : int; document : source option;
               code : source list; receipts : source list;
               recommendation : string option; gaps : (string * gap) list }
type origin = Local_observation | Synthetic_fixture
type report = { origin : origin; candidate : string option; ancestry : string list;
                sources : source list; source_map_sha256 : string;
                claims : claim list; quarantine_presence : string list;
                gaps : (string * gap) list }
type command = Ancestry | Candidate_bytes of string * string
type runner = command -> (string, gap) result

let max_file = 65536
let max_receipt = 16384
let max_entries = 4096
let max_refs = 8
let max_process_calls = 180
let jj = "/home/an/NAS-setup/uos/toolchains/nix-profile/bin/jj"
let receipt_dir = "governance/provenance/receipts"
let quarantine_dir = "var/coordination/tri-agent/events-quarantine"
let hash s = Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) s
             |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())
let hex n s = String.length s = n && String.for_all (function
  | '0'..'9' | 'a'..'f' -> true | _ -> false) s
let prefix = String.starts_with
let suffix = String.ends_with
let sorted xs = List.sort_uniq String.compare xs
let gap_name = function Missing -> "MISSING" | Unsafe -> "UNSAFE" | Changed -> "CHANGED"
  | Too_large -> "BOUND_EXCEEDED" | Ambiguous -> "AMBIGUOUS" | Unbound -> "DIRTY_BINDING"
  | Unrun -> "UNRUN" | Invalid_receipt -> "INVALID_RECEIPT"
  | Unverified_signature -> "UNVERIFIED_SIGNATURE" | Process_failure -> "PROCESS_FAILURE"
let valid_relative s =
  String.length s > 0 && String.length s <= 512 && s.[0] <> '/' &&
  String.for_all (function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'|'/' -> true | _ -> false) s &&
  List.for_all (fun p -> p <> "" && p <> "." && p <> "..") (String.split_on_char '/' s)
let allowed_code s = valid_relative s && prefix ~prefix:"apps/" s &&
  (suffix ~suffix:".gleam" s || suffix ~suffix:".erl" s) &&
  List.mem "src" (String.split_on_char '/' s)
let same_stat a b = a.Unix.st_dev = b.Unix.st_dev && a.st_ino = b.st_ino &&
  a.st_size = b.st_size && a.st_mtime = b.st_mtime && a.st_ctime = b.st_ctime &&
  a.st_kind = b.st_kind && a.st_nlink = b.st_nlink
exception Refuse of gap
let protect f = try Ok (f ()) with Refuse g -> Error g | Unix.Unix_error _ -> Error Unsafe
  | Sys_error _ -> Error Unsafe | Invalid_argument _ -> Error Unsafe
let check_root root =
  if not (Filename.is_relative root) && not (prefix ~prefix:"/proc" root ||
      prefix ~prefix:"/sys" root || prefix ~prefix:"/dev" root) &&
      Unix.realpath root = root && (Unix.lstat root).st_kind = Unix.S_DIR then ()
  else raise (Refuse Unsafe)
let checked_path root rel ~directory =
  if not (valid_relative rel) then raise (Refuse Unsafe);
  check_root root;
  let parts = String.split_on_char '/' rel in
  let rec walk p = function
    | [] -> p
    | x :: xs ->
      let p = Filename.concat p x in
      let st = try Unix.lstat p with Unix.Unix_error (Unix.ENOENT,_,_) -> raise (Refuse Missing) in
      if st.st_kind = Unix.S_LNK then raise (Refuse Unsafe);
      if xs <> [] || directory then
        (if st.st_kind <> Unix.S_DIR then raise (Refuse Unsafe))
      else if st.st_kind <> Unix.S_REG || st.st_nlink <> 1 then raise (Refuse Unsafe);
      walk p xs
  in walk root parts
let list_dir root rel = protect (fun () ->
  let p = checked_path root rel ~directory:true in
  let before = Unix.lstat p in
  let d = Unix.opendir p in
  let entries = Fun.protect ~finally:(fun () -> Unix.closedir d) (fun () ->
    let rec loop n acc =
      let next = try Some (Unix.readdir d) with End_of_file -> None in
      match next with None -> sorted acc | Some ("."|"..") -> loop n acc
      | Some x -> if n = max_entries then raise (Refuse Too_large) else loop (n+1) (x::acc)
    in loop 0 []) in
  if not (same_stat before (Unix.lstat p)) then raise (Refuse Changed);
  entries)
let read_file root rel limit = protect (fun () ->
  let p = checked_path root rel ~directory:false in
  let initial = Unix.lstat p in
  if initial.st_size > limit then raise (Refuse Too_large);
  let fd = Unix.openfile p [Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC] 0 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    let before = Unix.fstat fd in
    if not (same_stat initial before) || before.st_kind <> Unix.S_REG || before.st_nlink <> 1
      then raise (Refuse Changed);
    let buf = Bytes.create 4096 and out = Buffer.create (min before.st_size limit) in
    let rec loop () = let n = Unix.read fd buf 0 (min 4096 (limit - Buffer.length out + 1)) in
      if n <> 0 then (if Buffer.length out + n > limit then raise (Refuse Too_large);
        Buffer.add_subbytes out buf 0 n; loop ()) in
    loop ();
    let final_path = checked_path root rel ~directory:false in
    if not (same_stat before (Unix.fstat fd)) || not (same_stat before (Unix.lstat final_path))
      then raise (Refuse Changed);
    Buffer.contents out))

(* Strict argv, no shell, process group kill/reap, monotonic deadline and bounded
   stdout. Stderr is discarded to avoid leaking diagnostics or document bytes. *)
let bounded_command ~root args limit = protect (fun () ->
  check_root root;
  let argv = Bos.Cmd.(v jj % "--ignore-working-copy" % "--repository" % root %% of_list args)
             |> Bos.Cmd.to_list |> Array.of_list in
  let rd, wr = Unix.pipe ~cloexec:true () in
  let pid = try Unix.fork () with e -> Unix.close rd; Unix.close wr; raise e in
  if pid = 0 then (try
    ignore (Unix.setsid ()); Unix.chdir root; Unix.close rd;
    let null = Unix.openfile "/dev/null" [Unix.O_RDWR] 0 in
    Unix.dup2 null Unix.stdin; Unix.dup2 wr Unix.stdout; Unix.dup2 null Unix.stderr;
    Unix.close wr; Unix.close null; Unix.execv jj argv
    with _ -> Unix._exit 127);
  Unix.close wr; Unix.set_nonblock rd;
  let reaped = ref false in
  let reap () =
    (try ignore (Unix.kill (-pid) Sys.sigkill) with Unix.Unix_error _ -> ());
    if not !reaped then (try ignore (Unix.kill pid Sys.sigkill) with Unix.Unix_error _ -> ());
    if not !reaped then (let rec wait () = try ignore (Unix.waitpid [] pid)
      with Unix.Unix_error (Unix.EINTR,_,_) -> wait () in wait (); reaped := true) in
  Fun.protect ~finally:(fun () -> Unix.close rd; reap ()) (fun () ->
    let start = Mtime_clock.now () and out = Buffer.create 256 and buf = Bytes.create 4096 in
    let elapsed () = Mtime.Span.to_float_ns (Mtime.span start (Mtime_clock.now ())) /. 1e9 in
    let rec pump eof status =
      if elapsed () > 2.0 then raise (Refuse Process_failure);
      let status = match status with Some _ -> status | None ->
        let p,s = Unix.waitpid [Unix.WNOHANG] pid in
        if p = 0 then None else (reaped := true; Some s) in
      if eof && status <> None then match status with
        | Some (Unix.WEXITED 0) -> Buffer.contents out | _ -> raise (Refuse Process_failure)
      else (
        let ready,_,_ = Unix.select (if eof then [] else [rd]) [] [] 0.01 in
        let eof = if ready = [] then eof else
          try let n = Unix.read rd buf 0 4096 in
            if n = 0 then true else (if Buffer.length out + n > limit then raise (Refuse Too_large);
              Buffer.add_subbytes out buf 0 n; false)
          with Unix.Unix_error ((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_) -> false in
        pump eof status)
    in pump false None))
let operational_runner root = function
  | Ancestry -> bounded_command ~root ["log"; "-r"; "@ | ancestors(@-,6)"; "--limit"; "7";
      "--no-graph"; "-T"; "if(self.contained_in(\"@\"), \"H\" ++ parents.len(), if(self.contained_in(\"@-\"), \"P\", \"A\") ++ commit_id) ++ \"\\n\""] 512
  | Candidate_bytes (rev,path) ->
      if not (hex 40 rev && valid_relative path) then Error Unsafe else
      bounded_command ~root ["file"; "show"; "-r"; rev; path] max_file

let canonical_sources sources =
  List.sort_uniq (fun a b -> String.compare a.path b.path) sources
let source_map_hash ?candidate sources = canonical_sources sources |> List.map (fun s ->
  s.path ^ "\000" ^ s.sha256 ^ "\000" ^
  (match s.binding with Candidate_bound -> "BOUND" | Dirty_binding -> "DIRTY"))
  |> String.concat "\n" |> fun entries -> hash ((Option.value ~default:"UNKNOWN" candidate) ^ "\n" ^ entries)
let source_tokens bytes =
  let token_char = function 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'-'|'.'|'/' -> true | _ -> false in
  let n = String.length bytes in
  let rec loop i acc = if i >= n then sorted acc else if not (token_char bytes.[i]) then loop (i+1) acc
    else let j = ref i in while !j < n && token_char bytes.[!j] do incr j done;
      let token = String.sub bytes i (!j-i) in
      loop !j (token::acc) in loop 0 []
let code_references bytes = List.filter allowed_code (source_tokens bytes)
let unsafe_code_reference bytes = List.exists (fun p -> prefix ~prefix:"apps/" p &&
  (suffix ~suffix:".gleam" p || suffix ~suffix:".erl" p) && not (allowed_code p)) (source_tokens bytes)
let exact_keys keys fields =
  let ks = List.map fst fields in List.length ks = List.length (sorted ks) && sorted ks = sorted keys
let shallow_json bytes =
  let depth = ref 0 and quoted = ref false and escape = ref false and ok = ref true in
  String.iter (fun c -> if !quoted then
    (if !escape then escape := false else if c = '\\' then escape := true else if c = '"' then quoted := false)
    else if c = '"' then quoted := true else if c = '{' || c = '[' then
      (incr depth; if !depth > 16 then ok := false)
    else if c = '}' || c = ']' then decr depth) bytes;
  !ok
let rec unique_json = function
  | `Assoc fields -> let ks = List.map fst fields in List.length ks = List.length (sorted ks) &&
      List.for_all (fun (_,v) -> unique_json v) fields
  | `List xs -> List.for_all unique_json xs | _ -> true
let receipt_valid ?expected_kind ~candidate ~sources bytes =
  try if not (shallow_json bytes) then false else
    let j = Yojson.Safe.from_string bytes in
    if not (unique_json j) then false else match j with
    | `Assoc f when exact_keys ["schema";"kind";"candidate_commit";"source_path";
        "source_sha256";"reviewer";"signature"] f ->
      let s k = match List.assoc k f with `String s -> s | _ -> "" in
      s "schema" = "uos-forensic-receipt-v1" &&
      List.mem (s "kind") ["runtime";"formal"] && List.mem (s "reviewer") ["codex";"agy"] &&
      (match expected_kind with None -> true | Some k -> s "kind"=k) &&
      Some (s "candidate_commit") = candidate && hex 64 (s "source_sha256") &&
      String.length (s "signature") >= 1 && String.length (s "signature") <= 256 &&
      List.exists (fun x -> x.path = s "source_path" && x.sha256 = s "source_sha256" &&
        x.binding = Candidate_bound) sources
    | _ -> false
  with _ -> false
let timestamp_prefix name =
  String.length name >= 14 && name.[8]='-' && name.[13]='-' &&
  String.for_all (function '0'..'9' -> true | _ -> false) (String.sub name 0 8) &&
  String.for_all (function '0'..'9' -> true | _ -> false) (String.sub name 9 4)
let adr_filename adr name =
  String.length name <= 256 && suffix ~suffix:".md" name && timestamp_prefix name &&
  prefix ~prefix:(Printf.sprintf "adr-%03d-" adr) (String.sub name 14 (String.length name-14)) &&
  valid_relative name && not (String.contains name '/')
let receipt_filename ev name =
  String.length name <= 100 && timestamp_prefix name &&
  List.exists (fun kind -> String.sub name 14 (String.length name-14) =
    Printf.sprintf "ev-%03d-%s.receipt.json" ev kind) ["runtime";"formal"]

(* The injected interpreter is explicitly fixture-only. Production callers use
   scan, which fixes the process interpreter and labels real local observations. *)
let scan_interpreted ~origin ~root ~run =
  let global = ref [] and observed = ref [] and rereads = ref [] in
  let add p g = global := (p,g)::!global in
  let calls = ref 0 in
  let run c = incr calls; if !calls > max_process_calls then Error Too_large else run c in
  let ancestry = match run Ancestry with
    | Ok bytes -> let all_rows = String.split_on_char '\n' bytes |> List.filter ((<>) "") in
        let header_valid,rows = match all_rows with "H1"::xs -> true,xs | _ -> false,[] in
        let valid s = String.length s=41 && (s.[0]='P' || s.[0]='A') && hex 40 (String.sub s 1 40) in
        let parents = List.filter (fun s -> String.length s>0 && s.[0]='P') rows in
        if not header_valid || rows = [] || List.length rows > 6 || not (List.for_all valid rows) ||
           List.length parents <> 1 || List.length rows <> List.length (sorted rows) ||
           List.hd rows <> List.hd parents ||
           List.length rows <> List.length (sorted (List.map (fun s -> if String.length s=41 then String.sub s 1 40 else "") rows))
          then (add "jj:ancestry" Process_failure; [])
        else List.map (fun s -> String.sub s 1 40) rows
    | Error g -> add "jj:ancestry" g; [] in
  let candidate = match ancestry with x::_ -> Some x | [] -> None in
  let observe path limit = match read_file root path limit with
    | Error g -> Error g
    | Ok bytes ->
      let digest = hash bytes in
      let binding = match candidate with Some c -> (match run (Candidate_bytes(c,path)) with
        | Ok snapshot when String.equal snapshot bytes -> Candidate_bound | _ -> Dirty_binding)
        | None -> Dirty_binding in
      let src = {path; sha256=digest; binding} in
      observed := src::!observed; rereads := (path,limit,digest)::!rereads;
      Ok (src,bytes) in
  let docs = match list_dir root "docs/zk" with Ok xs -> xs | Error g -> add "docs/zk" g; [] in
  let receipt_names = match list_dir root receipt_dir with Ok xs -> xs
    | Error Missing -> add receipt_dir Unrun; [] | Error g -> add receipt_dir g; [] in
  let quarantine_presence = match list_dir root quarantine_dir with
    | Error g -> add quarantine_dir g; []
    | Ok names ->
      let allowed name = String.length name <= 180 && String.length name >= 10 &&
        String.for_all (function '0'..'9' -> true | _ -> false) (String.sub name 0 10) &&
        valid_relative name && not (String.contains name '/') &&
        (suffix ~suffix:".json" name || suffix ~suffix:".txt" name) in
      List.filter_map (fun name -> if not (allowed name) then None else
        let rel = quarantine_dir ^ "/" ^ name in
        (* lstat only: FIFOs and regular payloads are equally presence-only. *)
        try let st = Unix.lstat (Filename.concat root rel) in
          if st.st_kind = Unix.S_LNK || st.st_nlink <> 1 then (add rel Unsafe; None) else Some rel
        with Unix.Unix_error _ -> add rel Changed; None) names in
  if quarantine_presence = [] then add quarantine_dir Missing;
  let claims = List.init 16 (fun i ->
    let ev = 94+i and adr = 71+i and gaps = ref [] in
    let gap p g = gaps := (p,g)::!gaps in
    let candidates = List.filter (adr_filename adr) docs in
    let document,code = match candidates with
      | [name] -> let path = "docs/zk/" ^ name in
        (match observe path max_file with
         | Error g -> gap path g; None,[]
         | Ok (src,bytes) ->
           if src.binding = Dirty_binding then gap path Unbound;
           if unsafe_code_reference bytes then gap path Unsafe;
           let refs = code_references bytes in
           let refs = if List.length refs > max_refs then (gap path Too_large; []) else refs in
           let code = List.filter_map (fun path -> match observe path max_file with
             | Error g -> gap path g; None | Ok (s,_) ->
               if s.binding = Dirty_binding then gap path Unbound; Some s) refs in
           if code = [] then gap path Unrun;
           Some src,code)
      | [] -> gap (Printf.sprintf "docs/zk/ADR-%03d" adr) Missing; None,[]
      | _ -> gap (Printf.sprintf "docs/zk/ADR-%03d" adr) Ambiguous; None,[] in
    let names = List.filter (receipt_filename ev) receipt_names in
    let names = if List.length names > 2 then
      (gap (Printf.sprintf "%s/EV-%03d" receipt_dir ev) Ambiguous; []) else names in
    if names = [] then gap (Printf.sprintf "%s/EV-%03d" receipt_dir ev) Unrun;
    List.iter (fun kind -> if not (List.exists (suffix ~suffix:("-" ^ kind ^ ".receipt.json")) names)
      then gap (Printf.sprintf "%s/EV-%03d/%s" receipt_dir ev kind) Unrun) ["runtime";"formal"];
    let bound_sources = (match document with None -> code | Some d -> d::code) in
    let receipts = List.filter_map (fun name -> let path = receipt_dir ^ "/" ^ name in
      match observe path max_receipt with Error g -> gap path g; None
      | Ok (s,bytes) ->
        if s.binding = Dirty_binding then gap path Unbound;
        let expected_kind = if suffix ~suffix:"-runtime.receipt.json" name then "runtime" else "formal" in
        gap path (if receipt_valid ~expected_kind ~candidate ~sources:bound_sources bytes
                  then Unverified_signature else Invalid_receipt); Some s) names in
    {ev;adr;document;code;receipts;recommendation=(if code=[] then None else
      Some "CODE_PRESENT_REQUIRES_FRESH_TWO_KEY_REBIND");gaps=List.sort_uniq compare !gaps}) in
  List.iter (fun (path,limit,digest) -> match read_file root path limit with
    | Ok bytes when hash bytes = digest -> () | Ok _ -> add path Changed | Error g -> add path g) !rereads;
  (* Re-observe ancestry to reject a changed JJ parent during the scan. *)
  (match run Ancestry with Ok b when
      String.split_on_char '\n' b |> List.filter ((<>) "") =
        "H1" :: List.mapi (fun i c -> (if i=0 then "P" else "A") ^ c) ancestry -> ()
    | _ -> add "jj:ancestry" Changed);
  List.iter (fun x -> if List.exists (fun y -> x.path = y.path && x.sha256 <> y.sha256) !observed
    then add x.path Changed) !observed;
  let sources = canonical_sources !observed in
  {origin;candidate;ancestry;sources;source_map_sha256=source_map_hash ?candidate sources;claims;
   quarantine_presence;gaps=List.sort_uniq compare !global}
let scan ~root = scan_interpreted ~origin:Local_observation ~root ~run:(operational_runner root)
let scan_fixture ~root ~run = scan_interpreted ~origin:Synthetic_fixture ~root ~run
let to_json (r:report) =
  let s x = `String x and list f xs = `List (List.map f xs) in
  let gaps xs = list (fun (path,g) -> `Assoc ["locator",s path;"status",s (gap_name g)]) xs in
  let source x = `Assoc ["path",s x.path;"sha256",s x.sha256;"binding",s
    (match x.binding with Candidate_bound -> "CANDIDATE_BOUND" | Dirty_binding -> "DIRTY_BINDING")] in
  `Assoc ["schema",s "uos-forensic-scan-v1";"status",s "HOLD";
    "authority",s "NONE";"historical_status",s "NOT_ADMITTED";"two_key_verified",`Bool false;
    "admitted_ev_ceiling",`Int 93;"application_admitted",`Bool false;
    "system_admitted",`Bool false;"readback_verified",`Bool false;
    "origin",s (match r.origin with Local_observation -> "LOCAL_OBSERVATION" | Synthetic_fixture -> "SYNTHETIC_FIXTURE");
    "ancestry_scope",s "ONE_DIRECT_PARENT_AND_AT_MOST_SIX_ANCESTORS";
    "receipt_namespace",s receipt_dir;"trusted_receipt_verifier",s "UNAVAILABLE";
    "candidate_commit",(match r.candidate with None -> `Null | Some c -> s c);
    "ancestry",list s r.ancestry;"source_map_sha256",s r.source_map_sha256;
    "sources",list source r.sources;"quarantine_presence",list s r.quarantine_presence;
    "gaps",gaps r.gaps;"claims",list (fun c -> `Assoc ["ev",`Int c.ev;"adr",`Int c.adr;
      "historical_status",s "NOT_ADMITTED";"document",(match c.document with None -> `Null | Some x -> source x);
      "code",list source c.code;"receipts",list source c.receipts;
      "recommendation",(match c.recommendation with None -> `Null | Some x -> s x);"gaps",gaps c.gaps]) r.claims]
