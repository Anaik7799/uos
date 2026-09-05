(* Per-module AGENTS.md, DERIVED from the dune graph.

   Fifteen hand-written module guides agree with the tree on the day they
   are written and drift by the next. Everything here is read from the
   dune files and the filesystem, so a module that gains a dependency
   gains it in its guide too, and a guide can never name a library that
   no longer exists.

   What is NOT derived is the part a machine cannot know: the boundary
   and ownership notes, which are declared below and stated per module
   because getting them wrong has already cost this repository a breached
   ratchet and a commit of another actor's files. *)

let ( / ) = Filename.concat

let read_file path =
  try
    let ic = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr ic)
      (fun () -> Some (really_input_string ic (in_channel_length ic)))
  with _ -> None

let write_atomic path content =
  let tmp = path ^ ".tmp" in
  let oc = open_out_bin tmp in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc content);
  Sys.rename tmp path

(* every dune file under a module, and the stanzas we can read from it *)
let rec dune_files dir acc =
  if not (Sys.file_exists dir) || not (Sys.is_directory dir) then acc
  else
    Sys.readdir dir |> Array.to_list
    |> List.fold_left
         (fun acc e ->
           if e = "_build" || e = ".git" then acc
           else
             let p = dir / e in
             match Sys.is_directory p with
             | true -> dune_files p acc
             | false -> if e = "dune" then p :: acc else acc
             | exception Sys_error _ -> acc)
         acc

let words s =
  String.split_on_char '\n' s
  |> List.concat_map (String.split_on_char ' ')
  |> List.concat_map (String.split_on_char '\t')
  |> List.map (fun w -> String.concat "" (String.split_on_char '(' w))
  |> List.map (fun w -> String.concat "" (String.split_on_char ')' w))
  |> List.filter (fun w -> w <> "")

let libraries_of body =
  (* every `(libraries ...)` in the file, flattened and deduped *)
  let parts = String.split_on_char '\n' body in
  parts
  |> List.filter (fun l ->
         let t = String.trim l in
         String.length t > 0
         && (String.length t >= 10 && String.sub t 0 10 = "(libraries"
            || (String.length t >= 3 && String.sub t 0 3 = "   ")))
  |> String.concat " " |> words
  |> List.filter (fun w -> w <> "libraries")
  |> List.sort_uniq compare

(* `(library` and `(name x)` sit on different lines, so this walks the
   token stream rather than filtering lines — the per-line version
   reported zero declarations for a module with five, which is the kind
   of confident wrong number a generated guide must never carry. *)
let names_of body =
  let ws = words body in
  let rec go acc = function
    | "name" :: n :: rest -> go (n :: acc) rest
    | _ :: rest -> go acc rest
    | [] -> List.rev acc
  in
  go [] ws |> List.sort_uniq compare

let sources dir suffix =
  if not (Sys.file_exists dir) then []
  else
    Sys.readdir dir |> Array.to_list
    |> List.filter (fun f -> Filename.check_suffix f suffix)
    |> List.sort compare

(* the boundary notes a machine cannot derive *)
let ownership = function
  | "swarm" ->
      Some
        "**Owned by a parallel Claude session.** Do not edit files here without \
         an operator grant; extend `modules/hermes_ops` instead. Known defects \
         from the dossier §8: `Obj.magic` in `swarm_algebra.merge_crdt`, and \
         fabricated `[PASS]` output in `swarm_cli` — both OPEN. The third, \
         `test_sop_execution_stress` failing and absent from any `runtest` \
         alias, is CLOSED on 2026-08-12: its line-167 assertion demanded an \
         exception escape `execute_sop_workflow`, which the engine stopped \
         allowing when it began capturing join exceptions — the engine \
         implements the total-at-the-edges law this guide states, and the test \
         asserted its violation. The stale test was fixed, its byte-identical \
         twin `test_challenger_m3_stress` deleted (a suite counted twice \
         inflates the denominator with zero information), and the suite is now \
         in the alias. A defect note that outlives its defect trains readers to \
         discount the list."
  | "hermes_wiki" ->
      Some
        "The engine's dune carries a **guard law**: no `hermes_harness_*` \
         dependency. `test_hermes_wiki` reads these dune files and refuses \
         one. Code needing the harness belongs in `modules/hermes_ops`."
  | "hermes_ops" ->
      Some
        "The offload layer (R22). Everything here is an **operator tool**: \
         R19 applies in full — refuse unknown flags, write atomically, \
         capture the real exit code, fail closed. Never report a \
         measurement nothing measured."
  | _ -> None

let render ~name ~libs ~exes ~tests ~ml ~mli ~dunes =
  let b = Buffer.create 4096 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  p "<!-- GENERATED by `ops agents`. Do not edit: edit the dune files or\n\
     \     the ownership notes in ops_agents.ml and regenerate, or this\n\
     \     guide and the tree disagree and the guide is the one nobody\n\
     \     believes. -->\n\n";
  p "# `modules/%s` — agent guide\n\n" name;
  p "Read `AGENTS.md` at the repository root first; it governs. This file \
     records what is true of **this module** and nothing else.\n\n";
  (match ownership name with Some note -> p "> %s\n\n" note | None -> ());
  p "## Shape\n\n";
  p "| | |\n|---|---:|\n";
  p "| libraries / executables declared | %d |\n" (List.length exes);
  p "| implementation files (`.ml`) | %d |\n" ml;
  p "| interfaces (`.mli`) | %d |\n" mli;
  p "| test executables | %d |\n" (List.length tests);
  p "| dune files | %d |\n\n" dunes;
  if exes <> [] then p "**Declared:** %s\n\n" (String.concat ", " (List.map (Printf.sprintf "`%s`") exes));
  if tests <> [] then
    p "**Suites:** %s\n\n" (String.concat ", " (List.map (Printf.sprintf "`%s`") tests));
  if libs <> [] then begin
    p "## Depends on\n\n";
    List.iter (fun l -> p "- `%s`\n" l) libs;
    p "\nA dependency added to a dune file appears here on the next \
       regeneration. If it does not, the guide was not regenerated — that \
       is the only way these two can disagree.\n\n";
    p "**The dependency unit is the LIBRARY, not this directory.** A module \
       directory may declare libraries at several depths, so two directories \
       can each depend on the other while the library graph stays a DAG — \
       dune proves that, since it rejects a library cycle at build time and \
       the workspace builds. `modules/hermes_ops` and \
       `modules/hermes_ops_dashboard` are the worked example: the aggregate \
       `hermes_ops` depends on the dashboard, while the dashboard depends on \
       the leaves `hermes_ops_capability`, `hermes_ops_governance` and \
       `hermes_ops_topology`, which the aggregate re-exports so consumers \
       keep the same unwrapped module names. Read the list above as \
       libraries; a directory-level reading of it reports cycles that do not \
       exist.\n\n"
  end;
  p "## What binds work here\n\n";
  p "- **Interfaces first.** Write the `.mli` with each law in prose — what \
     is true and *why it must be* — then the `.ml`. Never ship an `.mli` \
     stating a law the `.ml` does not enforce.\n";
  p "- **Total at the edges.** Malformed input clamps to a defined value or \
     returns a named error; it never raises and never silently drops an \
     author's text.\n";
  p "- **A skip is disclosed and counted** (R2). Missing evidence is \
     unavailable, never passing.\n";
  p "- **Verify with the offload layer**, not a loop: `dune exec \
     modules/hermes_ops/ops_main.exe -- verify` (R22).\n";
  p "- **Mutation-test with `ops mutate`.** A survivor is a finding, not a \
     failure; a void run is not a result.\n";
  if name = "hermes_wiki" then
    p "- **A register row flips only by a live probe.** \
       `stale_declarations` catches a declaration its probe contradicts.\n";
  p "\n## Verify\n\n```\neval $(opam env --switch=/home/an/dev/ver/zigvm --set-switch)\n\
     dune build\ndune exec modules/hermes_ops/ops_main.exe -- verify\n```\n";
  Buffer.contents b

let module_dirs () =
  Sys.readdir "modules" |> Array.to_list
  |> List.filter (fun d -> Sys.is_directory ("modules" / d))
  |> List.sort compare

let generate ~write =
  let results =
    module_dirs ()
    |> List.map (fun name ->
           let root = "modules" / name in
           let dunes = dune_files root [] in
           let bodies = List.filter_map read_file dunes in
           let joined = String.concat "\n" bodies in
           let libs =
             libraries_of joined
             |> List.filter (fun l -> not (String.length l > 0 && l.[0] = '('))
           in
           let exes = names_of joined in
           let all_ml = List.concat_map (fun d -> sources d ".ml") [ root ] in
           let tests =
             List.filter
               (fun f -> String.length f > 5 && String.sub f 0 5 = "test_")
               all_ml
             |> List.map Filename.remove_extension
           in
           let doc =
             render ~name ~libs ~exes:(List.sort_uniq compare exes) ~tests
               ~ml:(List.length all_ml)
               ~mli:(List.length (sources root ".mli"))
               ~dunes:(List.length dunes)
           in
           let path = root / "AGENTS.md" in
           let changed = read_file path <> Some doc in
           if write && changed then write_atomic path doc;
           (name, changed))
  in
  results
