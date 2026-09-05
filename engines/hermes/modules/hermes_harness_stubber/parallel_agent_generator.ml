(* Candidate stubs are machine-emitted output, so they belong in the
   `generated/` stratum — not production `modules/`, which promises built,
   register-rowed code, and not `../hermes_%s`, which from the repository
   root (where `dune exec` runs) resolved OUTSIDE the workspace and left 17
   untracked sibling directories on 2026-08-09. A slice leaves here for
   `modules/hermes_harness/` when it stops being a stub. *)
let stub_root = "generated/stubs"

(* Paths are workspace-root-relative; refuse rather than scatter directories
   from whatever cwd we inherit. *)
let require_workspace_root () =
  if not (Sys.file_exists "dune-project" && Sys.file_exists "generated") then begin
    prerr_endline
      "parallel_agent_generator: no ./dune-project and ./generated here — run \
       from the workspace root. Refusing to write stubs relative to this cwd.";
    exit 1
  end

(* Domains share the stub root, so tolerate the create-create race. *)
let rec mkdir_p path =
  if not (Sys.file_exists path) then begin
    let parent = Filename.dirname path in
    if parent <> path then mkdir_p parent;
    try Sys.mkdir path 0o755 with Sys_error _ when Sys.file_exists path -> ()
  end

let create_module family_id capability_id =
  let dir = Filename.concat stub_root (Printf.sprintf "hermes_%s" family_id) in
  mkdir_p dir;
  let ml_path = Printf.sprintf "%s/%s.ml" dir capability_id in
  let mli_path = Printf.sprintf "%s/%s.mli" dir capability_id in
  let oc_ml = open_out ml_path in
  Printf.fprintf oc_ml "(* Auto-generated Candidate Implementation for %s.%s *)\n\n" family_id capability_id;
  Printf.fprintf oc_ml "type t = { id : string; status : string }\n\n";
  Printf.fprintf oc_ml "let create () = { id = \"%s\"; status = \"stub\" }\n" capability_id;
  close_out oc_ml;
  let oc_mli = open_out mli_path in
  Printf.fprintf oc_mli "(* Interface for %s.%s *)\n\n" family_id capability_id;
  Printf.fprintf oc_mli "type t = { id : string; status : string }\n\n";
  Printf.fprintf oc_mli "val create : unit -> t\n";
  close_out oc_mli

let () =
  require_workspace_root ();
  let existing_families = [ "model_routing" ] in
  let missing =
    List.filter (fun (f : Capability_catalog.capability) ->
      not (List.mem f.family_id existing_families)
    ) Capability_catalog.all
  in
  let families = Hashtbl.create 10 in
  List.iter (fun (f : Capability_catalog.capability) ->
    let current = try Hashtbl.find families f.family_id with Not_found -> [] in
    Hashtbl.replace families f.family_id (f :: current)
  ) missing;

  Printf.printf "Starting parallel generation across %d families...\n%!" (Hashtbl.length families);

  let domains =
    Hashtbl.fold (fun family_id caps acc ->
      let d = Domain.spawn (fun () ->
        Printf.printf "[Thread %s] Generating %d capabilities...\n%!" family_id (List.length caps);
        List.iter (fun (f : Capability_catalog.capability) ->
          create_module f.family_id f.id
        ) caps;
        Printf.printf "[Thread %s] Done.\n%!" family_id
      ) in
      d :: acc
    ) families []
  in
  List.iter Domain.join domains;
  Printf.printf "Parallel generation complete.\n%!"
