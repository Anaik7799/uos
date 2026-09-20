#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,yojson,digestif.ocaml";;
(* @agent_intent: preserve numbered, UTC-timestamped Medical-Nordics workbook
   snapshots and checksums before changing the canonical workbook.
   @laws: archived bytes are never replaced; parent mismatch fails closed;
   repeat publication is idempotent; version history is not financial validation. *)
let root = "/home/an/dev/ver/c3i/sub-projects/work/gdrive/4-Temp/1-Bountytek"
let current = root ^ "/Medical-Nordics-1.xlsx"
let history = root ^ "/versions/Medical-Nordics-1"
let manifest = history ^ "/manifest.json"
let get = function Ok x -> x | Error (`Msg m) -> failwith m
let hash s = Digestif.SHA256.(to_hex (digest_string s))
let stable p =
 let rec read n =
  let a=Unix.stat p in
  if a.Unix.st_size > 100_000_000 then failwith "file exceeds 100 MB limit";
  if (Unix.lstat p).Unix.st_kind<>Unix.S_REG then failwith("not a regular file: " ^ p);
  let x=get(Bos.OS.File.read(Fpath.v p)) and y=get(Bos.OS.File.read(Fpath.v p)) in
  let b=Unix.stat p in
  if x=y && String.length x=b.Unix.st_size && a.Unix.st_size=b.Unix.st_size && a.Unix.st_mtime=b.Unix.st_mtime then x
  else if n=0 then failwith("unstable read: " ^ p) else (Unix.sleepf 0.2;read(n-1)) in read 4
let utc t = let d=Unix.gmtime t in Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (1900+d.Unix.tm_year)(d.Unix.tm_mon+1)d.Unix.tm_mday d.Unix.tm_hour d.Unix.tm_min d.Unix.tm_sec
let valid_time s =
 String.length s=20 && s.[4]='-' && s.[7]='-' && s.[10]='T' && s.[13]=':' && s.[16]=':' && s.[19]='Z' &&
 (String.to_seqi s |> Seq.for_all(fun(i,c)->List.mem i [4;7;10;13;16;19] || (c>='0'&&c<='9'))) &&
 (let num i n=int_of_string(String.sub s i n) in
 let y=num 0 4 and m=num 5 2 and d=num 8 2 in
 let leap=y mod 400=0 || (y mod 4=0 && y mod 100<>0) in
 let days=match m with 2->if leap then 29 else 28 | 4|6|9|11->30 | _->31 in
 y>=1970 && m>=1 && m<=12 && d>=1 && d<=days && num 11 2<24 && num 14 2<60 && num 17 2<60)
let compact s = if not(valid_time s)then failwith "timestamp must be YYYY-MM-DDTHH:MM:SSZ" else String.to_seq s |> Seq.filter(fun c->c<>'-'&&c<>':') |> String.of_seq
let string j k = Yojson.Safe.Util.(j |> member k |> to_string)
let integer j k = Yojson.Safe.Util.(j |> member k |> to_int)
let members = function `Assoc xs->xs | _->failwith "JSON object required"
let entries j = Yojson.Safe.Util.(j |> member "versions" |> to_list)
let mkdir p = ignore(get(Bos.OS.Dir.create(Fpath.v p)))
let immutable p contents =
 if Sys.file_exists p then (if stable p<>contents then failwith("refusing to replace archive: " ^ p))
 else begin get(Bos.OS.File.write(Fpath.v p)contents);if stable p<>contents then failwith("write mismatch: " ^ p)end
let atomic p contents =
 let tmp=p ^ ".pending" in immutable tmp contents; Unix.rename tmp p;
 if stable p<>contents then failwith("published readback mismatch: " ^ p)
let encode j = Yojson.Safe.pretty_to_string j ^ "\n"
let bundle vs = `Assoc["schema_version",`Int 1;"workbook",`String "Medical-Nordics-1.xlsx";"time_zone",`String "UTC";"latest_version",`Int(integer(List.hd(List.rev vs))"version");"versions",`List vs]
let filename version time = Printf.sprintf "Medical-Nordics-1_v%04d_%s.xlsx" version (compact time)
let check_entries vs =
 List.iteri(fun i e->
  if integer e "version"<>i then failwith "non-sequential version history";
  let name=string e "snapshot" in
  if Filename.basename name<>name || not(Filename.check_suffix name ".xlsx") then failwith "unsafe snapshot path";
  if hash(stable(history ^ "/" ^ name))<>string e "sha256" then failwith("archive checksum mismatch: " ^ name);
  if i>0 && string e "previous_sha256"<>string(List.nth vs(i-1))"sha256" then failwith "broken version parent chain"
 )vs
let check ?(canonical=current) () =
 let vs=entries(Yojson.Safe.from_string(stable manifest)) in check_entries vs;
 if hash(stable canonical)<>string(List.hd(List.rev vs))"sha256" then failwith "canonical workbook differs from latest registered version (for a mounted Google export collision, check the Drive XLSX download by file ID with --check-against)";
 Printf.printf "VERSION_CHECK_PASS snapshots=%d; checked workbook and all archived checksums match.\n"(List.length vs)
let self_test () =
 List.iter(fun(s,want)->if valid_time s<>want then failwith("timestamp test failed: " ^ s))[
 "2026-09-28T09:21:36Z",true;"2024-02-29T23:59:59Z",true;
 "2026-02-29T00:00:00Z",false;"2026-13-01T00:00:00Z",false;
 "2026-01-01T24:00:00Z",false;"TTTT-09-28T09:21:36Z",false;
 "2026-09-28 09:21:36Z",false;"../2026-09-28T09:21Z",false];
 let p=Filename.temp_file "medical-version-test-" ".bin" in
 Fun.protect ~finally:(fun()->Unix.unlink p)(fun()->
  immutable p "";
  let rejected=try immutable p "replacement";false with Failure _->true in
  if not rejected || stable p<>"" then failwith "archive replacement was not rejected");
 print_endline "VERSION_SELF_TEST_PASS timestamp boundaries=8; archive idempotence and replacement rejection checked."
let publish ?(already_uploaded=false) candidate metadata =
 let bytes=stable candidate in
 if String.length bytes<4 || String.sub bytes 0 4<>"PK\003\004" then failwith "candidate must be a nonempty XLSX ZIP; validate spreadsheet content before publication";
 let meta=Yojson.Safe.from_string(stable metadata) in
 let n=integer meta "version" and time=string meta "recorded_at_utc" and parent=string meta "previous_sha256" in
 if n<1 || n>9999 then failwith "version outside 1..9999";
 ignore(compact time);ignore(string meta "change");
 let candidate_hash=hash bytes in
 let original=if already_uploaded && Sys.file_exists manifest then
   let previous=List.hd(List.rev(entries(Yojson.Safe.from_string(stable manifest)))) in
   stable(history ^ "/" ^ string previous "snapshot") else stable current in
 let vs = if Sys.file_exists manifest then entries(Yojson.Safe.from_string(stable manifest)) else begin
   if n<>1 || hash original<>parent then failwith "initial version or previous workbook checksum mismatch";
   let name=filename 0 time in immutable(history ^ "/" ^ name)original;
   let e=`Assoc["version",`Int 0;"recorded_at_utc",`String time;"original_modified_at_utc",`String(utc(Unix.stat current).Unix.st_mtime);"snapshot",`String name;"sha256",`String(hash original);"bytes",`Int(String.length original);"change",`String "Captured existing workbook before first managed update; a zero-byte file is an empty placeholder, not a valid workbook."] in
   let initial=[e]in atomic manifest (encode(bundle initial));initial
 end in
 check_entries vs;
 let last=List.hd(List.rev vs) in
 if integer last "version"=n && string last "sha256"=candidate_hash then begin check ~canonical:(if already_uploaded then candidate else current)();print_endline "Already published; no new version created." end
 else begin
  if integer last "version"+1<>n || string last "sha256"<>parent then failwith "version must increment by one and match the previous checksum";
  if time<string last "recorded_at_utc" then failwith "version timestamp precedes prior version";
  let before=hash original in
  if before<>parent && before<>candidate_hash then failwith "canonical workbook changed since review";
  let manifest_before=stable manifest in
  let name=filename n time in immutable(history ^ "/" ^ name)bytes;
  immutable(history ^ "/" ^ Printf.sprintf "release-v%04d.json" n)(encode meta);
  if (not already_uploaded && hash(stable current)<>before) || stable manifest<>manifest_before then failwith "concurrent workbook or manifest modification";
  if not already_uploaded && before<>candidate_hash then atomic current bytes;
  let e=`Assoc((List.filter(fun(k,_)->not(List.mem k ["snapshot";"sha256";"bytes"]))(members meta)) @ ["snapshot",`String name;"sha256",`String candidate_hash;"bytes",`Int(String.length bytes)]) in
  atomic manifest (encode(bundle(vs@[e])));check ~canonical:(if already_uploaded then candidate else current)();
  Printf.printf "Recorded version %04d at %s; snapshot=%s\n" n time name
 end
let () = try
 if Sys.getcwd()<>root then failwith("run from " ^ root);
 match Array.to_list Sys.argv with
 | [_;"--self-test"] -> self_test()
 | [_;"--check"] -> check()
 | [_;"--check-against";download] -> check ~canonical:download()
 | [_;("--publish"|"--record-published"|"--record-local" as operation);candidate;metadata] ->
   mkdir history;
   let lock=history ^ "/.publication.lock" in
   let fd=Unix.openfile lock [Unix.O_WRONLY;Unix.O_CREAT;Unix.O_EXCL] 0o600 in
   Fun.protect ~finally:(fun()->Unix.close fd;Unix.unlink lock)(fun()->publish ~already_uploaded:(operation<>"--publish") candidate metadata)
 | _ -> failwith "usage: ocaml version_medical_nordics.ml --self-test | --check | --check-against WORKBOOK.xlsx | --publish CANDIDATE.xlsx RELEASE.json | --record-published VERIFIED_DOWNLOAD.xlsx RELEASE.json | --record-local VALIDATED_WORKBOOK.xlsx RELEASE.json (archive only; does not update Drive binary)"
 with Failure m -> prerr_endline m;exit 1 | Unix.Unix_error(e,f,p)->Printf.eprintf "%s: %s (%s)\n" f (Unix.error_message e) p;exit 1
