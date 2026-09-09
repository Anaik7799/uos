#use "topfind";;
#require "unix,bos,cryptokit";;
(* Bootstrap only trusted repository evaluator modules into an isolated cache.
   This script never consumes model answers and performs no package resolution. *)
let root="/home/an/NAS-setup/uos"
let files=["openrouter_eval_expr.mli";"openrouter_eval_expr.ml";"openrouter_eval_catalog.ml";"openrouter_eval_validate.ml";"openrouter_eval_native.ml";"openrouter_eval_test.ml";"openrouter_eval_cli.ml"]
let read p=match Bos.OS.File.read(Fpath.v p)with Ok s->s|Error _->failwith("cannot read "^p)
let () =
 let source_dir=root^"/tools/validation" in
 let material=String.concat "\000" (List.map(fun file->file^"\000"^read(source_dir^"/"^file))files @ ["guardian\000"^read(root^"/tools/ecology_process.ml");"builder\000"^read(source_dir^"/openrouter_eval_build.ml")]) in
 let hash=Cryptokit.hash_string(Cryptokit.Hash.sha256())material |> Cryptokit.transform_string(Cryptokit.Hexa.encode()) in
 let scratch="/tmp/uos-openrouter-eval-"^hash in
 if not(Sys.file_exists scratch)then Unix.mkdir scratch 0o700;
 let stat=Unix.lstat scratch in
 if stat.Unix.st_kind<>Unix.S_DIR || stat.st_uid<>Unix.getuid() || stat.st_perm land 0o077<>0 then failwith "unsafe evaluator build directory";
 let executable=scratch^"/openrouter_eval" in
 let tool=root^"/toolchains/opam-ocaml/bin/ocamlfind" in
 let run args=
  let pid=Unix.create_process tool(Array.of_list(tool::args))Unix.stdin Unix.stdout Unix.stderr in
  match snd(Unix.waitpid[]pid)with Unix.WEXITED 0->()|_->failwith "evaluator compilation failed" in
 if not(Sys.file_exists executable)then (
  let build_id=scratch^"/openrouter_eval_build_id.ml" in
  let out=open_out build_id in output_string out("let expected_suite_sha = \""^hash^"\"\n");close_out out;
  run["ocamlopt";"-c";"-o";scratch^"/openrouter_eval_build_id.cmx";build_id];
  List.iter(fun file->let stem=Filename.chop_extension file in
   let suffix=if Filename.check_suffix file ".mli"then".cmi"else".cmx" in
   run["ocamlopt";"-w";"+8";"-warn-error";"+8";"-package";"unix,yojson,cryptokit,mtime.clock";"-I";scratch;"-c";"-o";scratch^"/"^stem^suffix;source_dir^"/"^file])files;
  let objects=List.filter_map(fun file->if Filename.check_suffix file ".ml"then Some(scratch^"/"^Filename.chop_extension file^".cmx")else None)files in
  run(["ocamlopt";"-package";"unix,yojson,cryptokit,mtime.clock";"-linkpkg";"-I";scratch;"-o";executable;scratch^"/openrouter_eval_build_id.cmx"]@objects));
 print_endline executable
