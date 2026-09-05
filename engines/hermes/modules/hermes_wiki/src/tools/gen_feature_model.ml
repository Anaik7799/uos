(* Emit the MBSE surfaces of the feature register — SysML v2, OML/TTL and
   the OpenMBEE MMS payload — into generated/mbse/.

   This is the SDLC integration point: the surfaces are BUILD OUTPUTS, so
   a model change shows up as a reviewable diff in the same commit as the
   code change that caused it. A model maintained beside the code drifts
   from it within a week; a model regenerated from the code cannot.

   R19 operator discipline: unknown flags are refused, writes are atomic
   (temp + rename, so an interrupted run never leaves a half-written
   model that the next reader treats as truth), every path is measured
   from the repo root, and the exit code is honest — a --check run that
   finds drift exits 1 and says which surface drifted. *)

let out_dir = "generated/mbse"

let surfaces () =
  [ ("features.sysml", Feature_model.sysml_v2 ());
    ("features.ttl", Feature_model.oml_ttl ());
    ("features.mms.json", Feature_model.mms_json ()) ]

let read_file path =
  if not (Sys.file_exists path) then None
  else
    try
      let ic = open_in_bin path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr ic)
        (fun () -> Some (really_input_string ic (in_channel_length ic)))
    with _ -> None

let rec mkdir_p path =
  if path <> "" && path <> "." && path <> "/" && not (Sys.file_exists path) then begin
    mkdir_p (Filename.dirname path);
    try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

(* Atomic: a reader either sees the previous model or the new one, never
   a truncated file. A generator that writes in place and is interrupted
   leaves something that parses and is wrong, which is worse than nothing. *)
let write_atomic path content =
  mkdir_p (Filename.dirname path);
  let tmp = path ^ ".tmp" in
  let oc = open_out_bin tmp in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc content);
  Sys.rename tmp path

let usage () =
  prerr_endline
    "usage: gen_feature_model [--check]\n\
    \  (no flag)  regenerate generated/mbse/ from the feature register\n\
    \  --check    verify the committed surfaces match the register; exit 1 on drift";
  exit 2

let () =
  let check =
    match List.tl (Array.to_list Sys.argv) with
    | [] -> false
    | [ "--check" ] -> true
    | _ -> usage ()
  in
  let ss = surfaces () in
  (* A model with no elements is not a model, and emitting one would
     silently replace a real committed model with an empty one — the same
     class of failure as a baseline generator truncating its baseline. *)
  let elements = List.length (Feature_model.elements ()) in
  if elements < 100 then begin
    Printf.eprintf
      "refusing to emit: the register yielded %d elements, which cannot be right.\n\
       The model is not written rather than written empty.\n"
      elements;
    exit 1
  end;
  if check then begin
    let drifted =
      List.filter
        (fun (name, content) ->
          match read_file (Filename.concat out_dir name) with
          | Some existing -> existing <> content
          | None -> true)
        ss
    in
    List.iter
      (fun (name, _) ->
        Printf.eprintf "model surface DRIFTED from the register: %s\n" (Filename.concat out_dir name))
      drifted;
    if drifted <> [] then begin
      Printf.eprintf
        "\n%d of %d surfaces are stale. Run gen_feature_model to regenerate,\n\
         and commit the result with the change that caused it.\n"
        (List.length drifted) (List.length ss);
      exit 1
    end;
    Printf.printf "model surfaces match the register (%d elements, %d surfaces)\n" elements
      (List.length ss)
  end
  else begin
    List.iter (fun (name, content) -> write_atomic (Filename.concat out_dir name) content) ss;
    let cov = Feature_model.coverage () in
    Printf.printf "wrote %d surfaces to %s/\n" (List.length ss) out_dir;
    List.iter
      (fun (name, content) ->
        Printf.printf "  %-20s %7d bytes\n" name (String.length content))
      ss;
    Printf.printf "model: %d elements · %d probe-verified · %d built-but-declared (gaps)\n"
      cov.Feature_model.total cov.Feature_model.verified cov.Feature_model.declared_only
  end
