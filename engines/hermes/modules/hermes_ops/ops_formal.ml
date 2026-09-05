(* Formal service gates — see ops_formal.mli for the laws. *)

type verdict = Discharged | Refuted of string | Unavailable of string

type service = { sname : string; tool : string; extension : string; roots : string list }

type check = { service : string; artifact : string; verdict : verdict; duration_ms : float }

type report = { checks : check list; discharged : int; refuted : int; unavailable : int }

let string_of_verdict = function
  | Discharged -> "DISCHARGED"
  | Refuted _ -> "REFUTED"
  | Unavailable why -> "UNAVAILABLE (" ^ why ^ ")"

(* The declared services. `z3` is checked through the in-repo
   `z3_topology_check` executable rather than by feeding z3 a `.smt2`
   directly, because the topology constraints are GENERATED — checking a
   hand-written file would verify a transcription rather than the model. *)
let services =
  [ { sname = "gospel"; tool = "gospel"; extension = ".gospel"; roots = [ "modules" ] };
    (* only .mli files that CARRY a specification: running `gospel check`
       on an interface with no spec verifies nothing, so counting it would
       inflate the denominator with questions nobody asked. *)
    { sname = "gospel-spec"; tool = "gospel"; extension = ".gospel-spec"; roots = [ "modules" ] };
    { sname = "rocq"; tool = "coqc"; extension = ".v"; roots = [ "modules" ] };
    { sname = "quint"; tool = "quint"; extension = ".qnt"; roots = [ "modules" ] };
    { sname = "lean"; tool = "lean"; extension = ".lean"; roots = [ "modules" ] };
    { sname = "governance-z3"; tool = "z3"; extension = ".generated-smt2";
      roots = [] } ]

let rec walk dir acc =
  if not (Sys.file_exists dir) then acc
  else if not (Sys.is_directory dir) then acc
  else
    Sys.readdir dir |> Array.to_list
    |> List.fold_left
         (fun acc entry ->
           if entry = "_build" || entry = ".git" || entry = "node_modules" then acc
           else
             let p = Filename.concat dir entry in
             match Sys.is_directory p with
             | true -> walk p acc
             | false -> p :: acc
             | exception Sys_error _ -> acc)
         acc

let artifacts_of s =
  let carries_spec p =
    match open_in_bin p with
    | exception _ -> false
    | ic ->
        Fun.protect
          ~finally:(fun () -> close_in_noerr ic)
          (fun () ->
            let n = in_channel_length ic in
            let body = really_input_string ic n in
            let k = String.length body in
            let rec go i = i + 3 <= k && (String.sub body i 3 = "(*@" || go (i + 1)) in
            go 0)
  in
  let want p =
    if s.extension = ".gospel-spec" then Filename.check_suffix p ".mli" && carries_spec p
    else Filename.check_suffix p s.extension
  in
  List.concat_map (fun r -> walk r []) s.roots |> List.filter want |> List.sort compare

let run_capture cmd =
  match Unix.open_process_full cmd (Unix.environment ()) with
  | exception e -> (127, "could not start: " ^ Printexc.to_string e)
  | (out_c, in_c, err_c) as chans ->
      let buf = Buffer.create 2048 in
      let drain ic =
        try while true do Buffer.add_channel buf ic 1 done
        with End_of_file | Sys_error _ -> ()
      in
      Fun.protect
        ~finally:(fun () -> try close_out in_c with Sys_error _ -> ())
        (fun () -> drain out_c; drain err_c);
      let st = try Unix.close_process_full chans with Unix.Unix_error _ -> Unix.WEXITED 127 in
      ((match st with Unix.WEXITED n -> n | Unix.WSIGNALED n | Unix.WSTOPPED n -> 128 + n),
       Buffer.contents buf)

let tool_available s =
  let code, _ = run_capture ("command -v " ^ Filename.quote s.tool ^ " >/dev/null 2>&1") in
  code = 0

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Sys.readdir path
      |> Array.iter (fun name -> remove_tree (Filename.concat path name));
      Unix.rmdir path
    end
    else Sys.remove path

let temp_directory () =
  let path = Filename.temp_file "hermes-ops-formal-" "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let copy_file source target =
  In_channel.with_open_bin source (fun input ->
      Out_channel.with_open_bin target (fun output ->
          let buffer = Bytes.create 8192 in
          let rec loop () =
            match In_channel.input input buffer 0 (Bytes.length buffer) with
            | 0 -> ()
            | count -> Out_channel.output output buffer 0 count; loop ()
          in
          loop ()))

(* Gospel 0.3.1 writes a compiled [.gospel] sidecar beside an [.mli] input.
   The formal gate therefore mirrors every Gospel input into a private stage.
   Load paths point at the source module and the intentionally weak harness
   stubs, but the checker never receives an in-tree file as its output target. *)
let run_gospel_safely artifact =
  let stage = temp_directory () in
  Fun.protect
    ~finally:(fun () -> remove_tree stage)
    (fun () ->
      let staged = Filename.concat stage (Filename.basename artifact) in
      copy_file artifact staged;
      let load_paths =
        [ Filename.dirname artifact;
          "modules/hermes_harness";
          "modules/hermes_harness/gospel_stubs" ]
        |> List.sort_uniq compare
      in
      let load_arguments =
        load_paths
        |> List.concat_map (fun directory -> [ "-L"; Filename.quote directory ])
        |> String.concat " "
      in
      run_capture
        (Printf.sprintf "timeout 60 gospel check %s %s 2>&1" load_arguments
           (Filename.quote staged)))

let run_staged s artifact =
  let stage = temp_directory () in
  Fun.protect
    ~finally:(fun () -> remove_tree stage)
    (fun () ->
      let basename = Filename.basename artifact in
      let staged = Filename.concat stage basename in
      copy_file artifact staged;
      let stage_q = Filename.quote stage in
      let source_directory = Filename.dirname artifact |> Unix.realpath |> Filename.quote in
      let artifact_q = Filename.quote basename in
      let invocation =
        match s.sname with
        | "rocq" ->
            Printf.sprintf "timeout 180 coqc -q -Q %s '' %s 2>&1"
              source_directory artifact_q
        | "quint" -> Printf.sprintf "timeout 120 quint typecheck %s 2>&1" artifact_q
        | "lean" -> Printf.sprintf "timeout 180 lean %s 2>&1" artifact_q
        | _ -> Printf.sprintf "timeout 60 false %s 2>&1" artifact_q
      in
      (* Run from the private stage as well as reading a staged input: Rocq
         extraction paths and Lean object paths are relative to cwd, not only
         to the input filename. *)
      run_capture (Printf.sprintf "cd %s && %s" stage_q invocation))

(* The checker ran but could not resolve the world it was given — a
   missing sibling module or library. Distinguished from a real
   refutation because the two demand opposite responses: fix the
   invocation, versus fix the specification. *)
let unresolved_environment out =
  let has needle =
    let n = String.length out and k = String.length needle in
    let rec go i = i + k <= n && (String.sub out i k = needle || go (i + 1)) in
    k > 0 && go 0
  in
  has "No module with name" || has "Unbound module" || has "unknown option"
  || has "Cannot find a physical path bound to logical path"

let trim_output out =
  let t = String.trim out in
  if String.length t <= 600 then t else String.sub t 0 600 ^ " …"

let check_one s artifact =
  let started = Unix.gettimeofday () in
  let code, out =
    if not (tool_available s) then (127, "checker not on PATH: " ^ s.tool)
    else if s.sname = "gospel" || s.sname = "gospel-spec" then
      run_gospel_safely artifact
    else run_staged s artifact
  in
  let duration_ms = (Unix.gettimeofday () -. started) *. 1000.0 in
  let verdict =
    if code = 0 then Discharged
    else if code = 124 then Unavailable "checker timed out"
    else if code = 127 then Unavailable "checker could not be started"
    else if unresolved_environment out then
      (* THE CHECKER DID NOT VERIFY. An unresolved module reference means
         the oracle could not be given the environment it needs, so
         nothing was proved — and nothing was disproved either. Reporting
         it as Refuted would manufacture a finding against a file that may
         be perfectly well specified; reporting it as Discharged would be
         the R2 violation. Unavailable is the only honest verdict. *)
      Unavailable ("environment unresolved: " ^ trim_output out)
    else Refuted (trim_output out)
  in
  { service = s.sname; artifact; verdict; duration_ms }

let check_artifact = check_one

let run ?only () =
  let wanted = match only with None -> services | Some n -> List.filter (fun s -> s.sname = n) services in
  let checks =
    List.concat_map
      (fun s ->
        if s.sname = "governance-z3" then
          let started = Unix.gettimeofday () in
          let verdict =
            match Ops_governance_formal.run () with
            | Ops_governance_formal.Proved -> Discharged
            | Ops_governance_formal.Refuted detail -> Refuted detail
            | Ops_governance_formal.Unavailable detail -> Unavailable detail
          in
          [ { service = s.sname; artifact = "Ops_governance_model.formal_smt2";
              verdict; duration_ms = (Unix.gettimeofday () -. started) *. 1000.0 } ]
        else if not (tool_available s) then
          (* R2: the oracle is absent, so nothing is proved. Never green. *)
          [ { service = s.sname; artifact = "(all)";
              verdict = Unavailable ("checker not on PATH: " ^ s.tool); duration_ms = 0.0 } ]
        else
          match artifacts_of s with
          (* NOT vacuously discharged: zero artifacts means the question
             was never asked, and "not asked" is not "answered yes". *)
          | [] ->
              [ { service = s.sname; artifact = "(none)";
                  verdict = Unavailable ("no " ^ s.extension ^ " artifacts found");
                  duration_ms = 0.0 } ]
          | fs -> List.map (check_one s) fs)
      wanted
  in
  let count f = List.length (List.filter f checks) in
  { checks;
    discharged = count (fun c -> c.verdict = Discharged);
    refuted = count (fun c -> match c.verdict with Refuted _ -> true | _ -> false);
    unavailable = count (fun c -> match c.verdict with Unavailable _ -> true | _ -> false) }

let render r =
  let b = Buffer.create 4096 in
  (* refutations FIRST and in the checker's own words — paraphrasing a
     prover is how a real refutation becomes a warning nobody acts on *)
  List.iter
    (fun c ->
      match c.verdict with
      | Refuted out ->
          Buffer.add_string b
            (Printf.sprintf "\n===== REFUTED: %s — %s =====\n%s\n" c.service c.artifact out)
      | Discharged | Unavailable _ -> ())
    r.checks;
  List.iter
    (fun c ->
      match c.verdict with
      | Unavailable why ->
          Buffer.add_string b
            (Printf.sprintf "UNAVAILABLE (disclosed): %s — %s\n" c.service why)
      | Discharged | Refuted _ -> ())
    r.checks;
  List.iter
    (fun s ->
      let mine = List.filter (fun c -> c.service = s.sname) r.checks in
      let ok = List.length (List.filter (fun c -> c.verdict = Discharged) mine) in
      if mine <> [] then
        Buffer.add_string b (Printf.sprintf "  %-12s %d/%d discharged\n" s.sname ok (List.length mine)))
    services;
  Buffer.add_string b
    (Printf.sprintf "formal: %d discharged, %d refuted, %d unavailable\n" r.discharged r.refuted
       r.unavailable);
  (* unavailable is non-zero too: an ungated formal artifact is exactly
     the state this module exists to end, so it may not read as success *)
  (Buffer.contents b, if r.refuted > 0 || r.unavailable > 0 then 1 else 0)
