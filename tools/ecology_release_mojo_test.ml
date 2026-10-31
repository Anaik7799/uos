#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos,yojson";;

(* @agent_intent: Exercise only the Mojo argv/exec shim using an inert OCaml
   backend in a private fixture. No release, config, service or grant operations.
   @laws: 2/3/4 argv reach the backend exactly; invalid arity/oversize refuse;
   shell metacharacters remain literal. This is not core deployment parity. *)
let need b why = if not b then failwith why
let get = function Ok x -> x | Error (`Msg m) -> failwith m
let () = need (Array.length Sys.argv = 3)
  "usage: ecology_release_mojo_test.ml <canonical-root> <mojo-source>"
let root = Unix.realpath Sys.argv.(1)
let source = Unix.realpath Sys.argv.(2)
let () = need ((Unix.lstat source).Unix.st_kind = Unix.S_REG) "regular Mojo source required"
let parent = Unix.realpath (Filename.get_temp_dir_name ())
let fixture = Filename.temp_file ~temp_dir:parent "uos-mojo-argv-" ""
let () = Unix.unlink fixture; Unix.mkdir fixture 0o700
let mkdir p = ignore (get (Bos.OS.Dir.create ~mode:0o700 ~path:true (Fpath.v p)))
let write p body =
  let fd = Unix.openfile p [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC] 0o600 in
  let oc = Unix.out_channel_of_descr fd in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc body; flush oc; Unix.fsync fd)
let () = mkdir (fixture ^ "/tools"); mkdir (fixture ^ "/toolchains/opam-ocaml/bin")
let () = Unix.symlink (root ^ "/toolchains/opam-ocaml/bin/ocaml") (fixture ^ "/toolchains/opam-ocaml/bin/ocaml")
let () = write (fixture ^ "/tools/ecology_release.mojo") (get (Bos.OS.File.read (Fpath.v source)))
let backend = {|if Array.length Sys.argv < 2 || Sys.argv.(1) = "__invalid_cli__" then exit 2;
let args = Array.to_list Sys.argv |> List.tl |> List.map (Printf.sprintf "%S") in
print_endline ("[" ^ String.concat "," args ^ "]")
|}
let () = write (fixture ^ "/tools/ecology_release.ml") backend
let ocaml = root ^ "/toolchains/opam-ocaml/bin/ocaml"
let pixi = root ^ "/toolchains/pixi/bin/pixi"
let environment = get (Bos.OS.Env.current ())
  |> Astring.String.Map.add "OCAMLLIB" (root ^ "/toolchains/opam-ocaml/lib/ocaml")
let checks = ref 0
let run number args =
  let out = fixture ^ "/output-" ^ string_of_int number in
  let command = Bos.Cmd.of_list ([ocaml; "-I"; "+unix"; root ^ "/tools/ecology_process.ml";
    "30000"; "65536"; "merged"; pixi; "run"; "--no-install"; "--frozen"; "--offline";
    "--no-config"; "--manifest-path"; root ^ "/services/inference/max/pixi.toml";
    "--executable"; "mojo"; "run"; fixture ^ "/tools/ecology_release.mojo"] @ args) in
  let result = get (Bos.OS.Cmd.run_out ~env:environment command |> Bos.OS.Cmd.out_string) in
  let text, (_, status) = result in
  write out text;
  status, text
let check number args expected =
  let status, text = run number args in
  need (status = `Exited 0) ("shim execution failed; private output " ^ fixture ^ "/output-" ^ string_of_int number);
  need (Yojson.Safe.from_string text = `List (List.map (fun s -> `String s) expected)) "argv changed";
  incr checks
let () =
  check 0 ["selftest"] ["selftest"];
  check 1 ["verify"; "/fixture/capsule"] ["verify"; "/fixture/capsule"];
  check 2 ["cutover"; "/fixture/repository"; "/fixture/capsule"] ["cutover"; "/fixture/repository"; "/fixture/capsule"];
  let literal = "literal $(touch SHOULD_NOT_EXIST) `touch ALSO_NOT` ; spaces\nline" in
  check 3 ["cutover"; literal; "/fixture/capsule"] ["cutover"; literal; "/fixture/capsule"];
  check 4 ["verify"; String.make 4096 'a'] ["verify"; String.make 4096 'a'];
  List.iteri (fun i args -> let status, _ = run (i + 5) args in
    need (status = `Exited 2) "invalid CLI was not refused"; incr checks)
    [[]; ["a";"b";"c";"d"]; ["verify"; String.make 4097 'a']; ["cutover"; "/fixture"; String.make 4097 'a']];
  need (not (Sys.file_exists "SHOULD_NOT_EXIST") && not (Sys.file_exists "ALSO_NOT")) "shell interpolation occurred";
  print_endline (Yojson.Safe.to_string (`Assoc ["status", `String "PASS"; "checks", `Int !checks;
    "scope", `String "Mojo argv shim with inert private backend; no deployment-core parity or authority"]));
  ignore (get (Bos.OS.Dir.delete ~recurse:true (Fpath.v fixture)))
