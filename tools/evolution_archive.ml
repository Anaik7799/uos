#use "evolution_cycles.ml";;
(* Retain exact local evidence, never executable caches or native binaries. *)
let ()=try
 require(Array.length Sys.argv=3)"usage: SOURCE_CYCLE_DIRECTORY NEW_ARCHIVE";
 let source=realpath Sys.argv.(1)and dest=Sys.argv.(2)in
 require(not(Filename.is_relative dest)&&not(Sys.file_exists dest))"new absolute archive required";
 verify50 ~quiet:true source;
 let paths=files source ""in
 require(List.length paths=252&&List.for_all(fun p->Filename.check_suffix p".json"&&not(String.contains p '/'))paths)"unexpected cycle artifact set";
 require(List.fold_left(fun n p->n+(lstat(source^"/"^p)).st_size)0 paths<=16777216)"archive size bound";
 mkdir dest 0o700;List.iter(fun p->copy(source^"/"^p)(dest^"/"^p))paths;
 verify50 ~quiet:true dest;
 let manifest=jobj["schema",jstr"uos.local-evidence-archive.v1";"authority",jstr"NONE";"files",jobj(List.map(fun p->p,jstr(sha(dest^"/"^p)))paths)]in
 write_new(dest^"/archive-manifest.json")(json manifest);
 emit"fifty-archive""PASS"["files",jint(List.length paths);"path",jstr dest]
 with e->emit"fifty-archive""FAIL"["error",jstr(Printexc.to_string e)];exit 1;;
