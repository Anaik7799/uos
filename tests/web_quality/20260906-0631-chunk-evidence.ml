#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;
(* @agent_intent Preserve complete review datasets in bounded Jujutsu-trackable
   parts. This transforms only newly generated audit artifacts, not source trees.
   @laws Reassembled JSON records and CSV bytes must match the original dataset. *)
open Bos
open Yojson.Basic.Util
let get=function Ok x->x |Error(`Msg s)->failwith s
let read p=get(OS.File.read(Fpath.v p))
let write p s=get(OS.File.write(Fpath.v p)s)
let root="/home/an/NAS-setup/uos"
let prefix="20260906-0631-"
let base=root^"/docs/design/"^prefix
let dir=base^"test-data"
let sha source_path=get(OS.Cmd.(run_out Cmd.(v "sha256sum" % "--" % source_path)|>out_string|>success))|>fun s->String.sub s 0 64
let s x=`String x
let groups encode xs =
  let rec loop done_ current bytes=function
    |[]->List.rev(if current=[] then done_ else List.rev current::done_)
    |x::rest->let n=String.length(encode x)+2 in
      if n>800000 then failwith "Single record exceeds safe part bound";
      if bytes+n>800000 && current<>[] then loop(List.rev current::done_)[x]n rest
      else loop done_(x::current)(bytes+n)rest in loop [] [] 0 xs
let json stem =
  let path=base^stem^".json" in
  let source=read path in
  let document=Yojson.Basic.from_string source in
  let records=member "records" document|>to_list in
  write("/tmp/"^prefix^stem^"-full.json")source;
  let parts=groups Yojson.Basic.to_string records|>List.mapi(fun i rs->
    let name=Printf.sprintf "%s%s-%04d.json"prefix stem(i+1) in
    let path=dir^"/"^name in
    write path(Yojson.Basic.to_string(`Assoc["records",`List rs])^"\n");
    `Assoc["path",s("docs/design/"^prefix^"test-data/"^name);"records",`Int(List.length rs);"bytes",`Int(String.length(read path));"sha256",s(sha path)]) in
  let rebuilt=List.concat_map(fun p->read(root^"/"^(member "path" p|>to_string))|>Yojson.Basic.from_string|>member "records"|>to_list)parts in
  if rebuilt<>records then failwith "JSON reassembly mismatch";
  write path(Yojson.Basic.pretty_to_string(`Assoc[
    "schema",s "uos.chunked-review-dataset.v1";"original_metadata",`Assoc(List.filter(fun(k,_)->k<>"records")(to_assoc document));
    "record_count",`Int(List.length records);"reassembly_verified",`Bool true;
    "reassembly",s "Concatenate each part.records in listed order; restore original_metadata fields.";"parts",`List parts])^"\n");
  Printf.printf "%s: %d records, %d parts\n%!"stem(List.length records)(List.length parts)
let csv () =
  let stem="cross-project-test-cases" in
  let path=base^stem^".csv" in
  let source=read path in
  let lines=String.split_on_char '\n' source in
  let header=List.hd lines in
  let lines=List.tl lines|>List.filter(fun l->l<>"") in
  let parts=groups Fun.id lines|>List.mapi(fun i rows->
    let name=Printf.sprintf "%s%s-%04d.csv"prefix stem(i+1) in
    let p=dir^"/"^name in
    write p(header^"\n"^String.concat "\n" rows^"\n");
    name,List.length rows,sha p) in
  let rebuilt=header^"\n"^String.concat "\n"(List.concat_map(fun(name,_,_)->read(dir^"/"^name)|>String.split_on_char '\n'|>List.tl|>List.filter(fun l->l<>""))parts)^"\n" in
  if rebuilt<>source then failwith "CSV reassembly mismatch";
  let backup="/tmp/"^prefix^stem^"-full.csv" in
  write backup source;
  (* Replace the large working artifact with an explicit CSV part index. *)
  write path("part_path,data_rows,sha256\n"^String.concat "\n"(List.map(fun(name,n,digest)->"docs/design/"^prefix^"test-data/"^name^","^string_of_int n^","^digest)parts)^"\n");
  Printf.printf "CSV: %d rows, %d parts; root CSV is now the explicit part index.\n%!"(List.length lines)(List.length parts)
let () =
  ignore(get(OS.Dir.create ~path:true(Fpath.v dir)));
  json "source-corpus-index";json "cross-project-test-catalogue";csv()
