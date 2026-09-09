#use "topfind";;
#require "unix,yojson,cryptokit";;
let root = "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang"
let sha path =
  let st = Unix.lstat path in
  if st.Unix.st_kind <> Unix.S_REG || st.Unix.st_size > 16_777_216 then failwith ("invalid artifact " ^ path);
  let h = Cryptokit.Hash.sha256 () and bytes = Bytes.create 65536 in
  let ic = open_in_bin path in Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
    let rec read () = let n = input ic bytes 0 (Bytes.length bytes) in
      if n > 0 then (h#add_substring bytes 0 n; read ()) in read ();
    Cryptokit.transform_string (Cryptokit.Hexa.encode ()) h#result)
let paths () = Sys.readdir root |> Array.to_list |> List.sort String.compare
  |> List.filter (fun name -> name <> "cepaf_gleam" && name <> "uos_swarm")
  |> List.concat_map (fun name -> let ebin = root ^ "/" ^ name ^ "/ebin" in
    if not (Sys.file_exists ebin) then [] else Sys.readdir ebin |> Array.to_list
      |> List.sort String.compare |> List.map (fun entry -> ebin ^ "/" ^ entry))
let inventory () =
  let paths = paths () in
  if List.length paths > 5000 then failwith "artifact count bound";
  let total = List.fold_left (fun n p -> n + (Unix.lstat p).Unix.st_size) 0 paths in
  if total > 268_435_456 then failwith "artifact byte bound";
  `List (List.map (fun path -> `Assoc ["path", `String path; "sha256", `String (sha path)]) paths)
let () = match Array.to_list Sys.argv with
  | [_; "snapshot"; path] ->
    let entries = inventory () in
    let json = `Assoc ["schema", `String "uos.reused-gleam-artifacts.v1";
      "observed_utc_seconds", `Float (Unix.gettimeofday ()); "authority", `String "NONE";
      "scope", `String "Existing dependency ebin bytes; no source-build provenance or ABI conformance implied";
      "files", entries] in
    let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL] 0o600 in
    let oc = Unix.out_channel_of_descr fd in
    Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () ->
      output_string oc (Yojson.Safe.pretty_to_string json ^ "\n"));
    Printf.printf "Captured %d dependency artifacts\n" (List.length (Yojson.Safe.Util.to_list entries))
  | [_; "check"; path] ->
    let expected = Yojson.Safe.Util.member "files" (Yojson.Safe.from_file path) in
    if inventory () <> expected then failwith "dependency artifact bytes changed during verification";
    Printf.printf "Verified %d dependency artifacts unchanged\n"
      (List.length (Yojson.Safe.Util.to_list expected))
  | _ -> failwith "snapshot|check FILE required"
