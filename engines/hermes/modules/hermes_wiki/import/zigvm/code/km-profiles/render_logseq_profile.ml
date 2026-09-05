open Bos

module L = Logseq_profile_core.Logseq_profile

let () =
  let output = ref "" in
  Arg.parse
    [ "--output", Arg.Set_string output, "Generated Logseq OCaml profile JSON" ]
    (fun unexpected -> raise (Arg.Bad ("unexpected argument: " ^ unexpected)))
    "render_logseq_profile --output PATH";
  if String.equal !output "" then begin
    Printf.eprintf "--output is required\n%!";
    exit 2
  end;
  match L.catalog_violations L.catalog with
  | _ :: _ as violations ->
      List.iter (Printf.eprintf "profile violation: %s\n%!") violations;
      exit 1
  | [] ->
      let content =
        L.catalog_to_yojson L.catalog |> Yojson.Safe.pretty_to_string
        |> fun text -> text ^ "\n"
      in
      let path = Fpath.v !output in
      let temporary = Fpath.v (!output ^ ".tmp") in
      (match OS.Dir.create (Fpath.parent path) with
       | Error (`Msg message) ->
           Printf.eprintf "render_logseq_profile: %s\n%!" message;
           exit 1
       | Ok _ ->
           match OS.File.write temporary content with
           | Error (`Msg message) ->
               Printf.eprintf "render_logseq_profile: %s\n%!" message;
               exit 1
           | Ok () ->
               match OS.Path.move ~force:true temporary path with
               | Error (`Msg message) ->
                   Printf.eprintf "render_logseq_profile: %s\n%!" message;
                   exit 1
               | Ok () ->
                   Printf.printf "rendered %d Logseq capabilities to %s\n%!"
                     (List.length L.catalog) !output)
