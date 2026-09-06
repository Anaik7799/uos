#!/usr/bin/env -S opam exec -- ocaml
#use "topfind";;
#require "bos.setup";;
#require "yojson";;
(* @agent_intent Repair only AGY rule metadata and its documented hook output
   schema; preserve rule bodies and leave Codex's distinct hook schema alone.
   @laws Stage and back up exact inputs; reject concurrent edits; record hashes. *)
open Bos
open Yojson.Basic.Util
let get = function Ok v->v | Error(`Msg s)->failwith s
let root="/home/an/NAS-setup/uos"
let read p=get(OS.File.read(Fpath.v p))
let write p v=get(OS.File.write(Fpath.v p)v)
let run args=get(OS.Cmd.(run_out(Cmd.of_list args)|>out_string|>success))|>String.trim
let sha p=String.sub(run["sha256sum";"--";p])0 64
let s x=`String x
let field r k=member k r|>to_string
let () =
  if Array.length Sys.argv=2 && Sys.argv.(1)="--stage" then (
    let stamp=run["date";"-u";"+%Y%m%d-%H%S"] in
    let dir=root^"/governance/agents/repairs/"^stamp^"-agy-config" in
    ignore(get(OS.Dir.create ~path:true(Fpath.v dir)));
    let records=List.concat_map(fun agent->
      let hooks=agent^"/hooks.json" in
      let rules=Array.to_list(Sys.readdir(root^"/"^agent^"/rules"))|>List.sort String.compare
        |>List.filter(fun n->Filename.check_suffix n ".md")|>List.map(fun n->agent^"/rules/"^n) in
      List.filter_map(fun path->
        let before=read(root^"/"^path) in
        let after=if path=hooks then (
          let doc=Yojson.Basic.from_string before in
          let rec rewrite = function
            | `Assoc pairs -> `Assoc(List.map(fun(k,v)->if k="command" then
                 k,s "test -d /home/an/NAS-setup/uos/.jj && printf '%s\\n' '{\"injectSteps\":[{\"ephemeralMessage\":\"UOS uses standalone Jujutsu. Consult AGENTS.md for Zero-Muda, OTP and evidence requirements.\"}]}'"
               else k,rewrite v)pairs)
            | `List xs->`List(List.map rewrite xs) | other->other in
          Yojson.Basic.pretty_to_string(rewrite doc)^"\n")
        else if String.starts_with ~prefix:"---\n" before then before
        else "---\ntrigger: always_on\n---\n\n"^before in
        if before=after then None else (
          let name=String.map(fun c->if c='/' then '_' else c)path in
          let backup=dir^"/"^stamp^"-"^name^".before" and staged=dir^"/"^stamp^"-"^name^".after" in
          write backup before;write staged after;
          Some(`Assoc["path",s path;"before_sha256",s(sha backup);"after_sha256",s(sha staged);"backup",s backup;"staged",s staged])))(hooks::rules)) [".agents";".gemini"] in
    let manifest=dir^"/"^stamp^"-repair.json" in
    write manifest (Yojson.Basic.pretty_to_string(`Assoc["schema",s "uos.agy-config-repair.v1";"status",s "STAGED";"records",`List records])^"\n");
    write "/tmp/uos-agy-config-repair-manifest.path" manifest;
    Printf.printf "Staged %d repairs: %s\n%!"(List.length records)manifest
  ) else if Array.length Sys.argv=2 && Sys.argv.(1)="--apply" then (
    let manifest=read "/tmp/uos-agy-config-repair-manifest.path"|>String.trim in
    let doc=Yojson.Basic.from_string(read manifest) in
    let records=doc|>member "records"|>to_list in
    List.iter(fun r->let path=field r "path" in
      if not(String.starts_with ~prefix:".agents/" path || String.starts_with ~prefix:".gemini/" path) then failwith "Invalid repair target";
      if sha(root^"/"^path)<>field r "before_sha256" || sha(field r "staged")<>field r "after_sha256" then failwith("Concurrent edit: "^path))records;
    List.iter(fun r->write(root^"/"^field r "path")(read(field r "staged"));
      if sha(root^"/"^field r "path")<>field r "after_sha256" then failwith "Write verification failed")records;
    write manifest (Yojson.Basic.pretty_to_string(`Assoc(List.map(fun(k,v)->if k="status" then k,s "APPLIED_HASH_VERIFIED" else k,v)(to_assoc doc)))^"\n");
    Printf.printf "Applied and hash-verified %d repairs.\n%!"(List.length records)
  ) else failwith "usage: --stage | --apply"
