(* Hard control: the harness toolchain is OCaml, end to end.

   Python may be *referenced* here — it is the language of the frozen reference
   we are proving parity against — but it may never *implement* any part of the
   harness. The distinction this guard enforces:

     allowed   frozen reference source, fixture data that stands in for it, and
               probing for the reference interpreter
     forbidden a .py file in the workspace, a python shebang, or a build or
               shell surface that shells out to python to do work

   Everything outside the allowed data roots must be declared in
   [declared_exceptions] with a reason, so an exception is auditable rather
   than invisible. The guard fails closed: an undeclared match is a violation
   even if it is harmless, because the point is that nobody adds Python tooling
   without saying so out loud. *)

type violation = { path : string; reason : string }

(* Roots holding Python as *data* rather than as our tooling: the frozen
   reference, fixtures that stand in for it in tests, and the vendored trees the
   root dune already declares `data_only_dirs`. The rule is about what we write,
   not about what we vendor or measure. *)
let data_roots =
  [ "external"; "modules/hermes_harness/fixtures"; "third_party"; "vendor";
    (* Vendored third-party sources of the embedded Rust engine: data we pin,
       not tooling we write. The crate we DO write (src/lib.rs) is Rust by
       explicit user direction and carries no harness judgement. *)
    "rust/drift_engine/vendor" ]

(* Directories with no source of ours in them. `venv` sits beside `.venv`
   because BOTH exist at the root and they are the same kind of thing: a
   provisioned Python virtualenv, vendored runtime, no authorship of ours.
   Listing only the dotted one was an oversight, and it made the guard
   report several hundred site-packages files as R1 violations — noise
   that buried the eight authored files that are the real finding. This
   exempts a vendored directory, never an authored one. *)
let ignored_directories =
  [ ".git"; "_build"; "state"; "node_modules"; ".venv"; "venv"; "generated" ]

(* Declared, reasoned exceptions. Anything here is allowed to mention python. *)
let declared_exceptions =
  [ ( "modules/hermes_harness/bootstrap.ml",
      "probes for the python3 interpreter as a bootstrap readiness check; the \
       frozen reference needs it to run, and no harness logic is written in it" );
    ( "modules/hermes_harness/ocaml_only_guard.ml",
      "this guard names what it forbids" );
    ( "modules/hermes_harness/test_ocaml_only_guard.ml",
      "exercises this guard, including its negative cases" );
    ( "modules/hermes_harness/reference_adapter/build_kwargs_adapter.py",
      "the thinnest possible driver for the measured system. The frozen \
       reference is Python and its request shaping lives on a method that must \
       be instantiated, so no OCaml can execute it. The adapter makes no \
       decisions and knows nothing about the candidate: it reads a scenario on \
       stdin and writes the reference result on stdout. Normalization, \
       comparison, digesting and storage all happen in OCaml, so this cannot \
       become the place where parity is decided. Committed rather than run ad \
       hoc so the capture is reviewable and reproducible" );
    ( "modules/hermes_harness/reference_adapter/normalize_response_adapter.py",
      "the decode counterpart of build_kwargs_adapter, on identical terms: a \
       dumb driver that presents a provider response to the reference decoder \
       via attribute access and serializes the result. Makes no parity \
       decision; normalization, comparison and storage stay in OCaml" );
    ( "modules/hermes_harness/reference_adapter/iteration_budget_adapter.py",
      "the interrupt-control counterpart, on identical terms: a dumb driver \
       that replays a consume/refund sequence against the frozen \
       IterationBudget and serializes the observed state. Makes no parity \
       decision; comparison and storage stay in OCaml" );
    ( "modules/hermes_harness/reference_adapter/trace_execution_adapter.py",
      "the runtime-coverage counterpart, on identical terms: a dumb driver that \
       runs build_kwargs under sys.settrace and serializes the executed \
       frozen-relative files. Makes no parity decision; the executed-to-anchor \
       mapping and coverage report stay in OCaml (Runtime_coverage)" );
    ( "modules/hermes_harness/reference_adapter/path_security_adapter.py",
      "the path-safety counterpart, on identical terms: a dumb driver that runs \
       the frozen has_traversal_component over a list of paths and serializes \
       the path->bool map. Makes no parity decision; comparison stays in OCaml" );
    ( "modules/hermes_harness/reference_adapter/retry_after_adapter.py",
      "the rate-and-retry counterpart, on identical terms: a dumb driver that \
       runs the frozen parse_retry_after_seconds over a value list and \
       serializes the results positionally. Makes no parity decision; \
       comparison stays in OCaml" );
    ( "modules/hermes_harness/reference_adapter/route_resolution_adapter.py",
      "the route-resolution counterpart, on identical terms: a dumb driver that \
       runs the frozen get_fallback_chain over a list of configs and serializes \
       the resolved chains positionally. Makes no parity decision; comparison \
       stays in OCaml" );
    ( "modules/hermes_harness/reference_adapter/anthropic_adapter_adapter.py",
      "the anthropic-adapter counterpart, on identical terms: a dumb driver that \
       dispatches a list of calls to the frozen convert_tools_to_anthropic / \
       normalize_model_name / _sanitize_tool_id and serializes the results \
       positionally. Makes no parity decision; comparison stays in OCaml" );
    ( "modules/hermes_harness/reference_adapter/codex_message_shapes_adapter.py",
      "the codex-runtime counterpart, on identical terms: a dumb driver that \
       dispatches a list of ops to the frozen _chat_content_to_responses_parts / \
       _normalize_responses_message_status / _summarize_user_message_for_log and \
       serializes the results positionally. Makes no parity decision" );
    ( "modules/hermes_harness/reference_adapter/gemini_schema_adapter.py",
      "the gemini-adapter counterpart (first cut), on identical terms: a dumb \
       driver that runs the frozen sanitize_gemini_tool_parameters over a list \
       of schemas and serializes the results positionally. Makes no parity \
       decision; comparison stays in OCaml" );
    ( "modules/hermes_harness/reference_adapter/bedrock_converse_adapter.py",
      "the cloud-vendor-adapters counterpart, on identical terms: a dumb driver \
       that runs the frozen build_converse_kwargs over a list of cases and \
       serializes the results positionally (HERMES_DISABLE_LAZY_INSTALLS=1 set \
       before import to bar any network install). Makes no parity decision" );
    ( "modules/hermes_harness/reference_adapter/message_hygiene_adapter.py",
      "the message-hygiene counterpart, on identical terms: a dumb driver that \
       runs the frozen strict-strip method, sanitize_api_messages, or \
       _sanitize_surrogates (dispatched by the scenario's declared unit) over \
       labeled cases. Both file descriptors are muffled because the frozen \
       module prints at import and the capture merges child stderr into the \
       trace channel. Makes no parity decision" );
    ( "modules/hermes_harness/reference_adapter/conversation_loop_adapter.py",
      "the conversation-loop counterpart, on identical terms: a dumb driver \
       that runs the frozen _canonicalize_api_tool_calls or \
       _get_continuation_prompt over labeled cases, with the same fd-level \
       output discipline. Makes no parity decision" );
    ( "modules/hermes_harness/reference_adapter/agent_loop_units_adapter.py",
      "the four remaining agent_loop slices' counterpart, on identical terms: \
       a dumb driver dispatching per declared unit to the frozen \
       prompt_builder, context_references, context_compressor and \
       turn_finalizer/turn_summary units over labeled cases, with the same \
       fd-level output discipline. Makes no parity decision" );
    ( "modules/hermes_harness/reference_capture.ml",
      "names the adapters it drives" ) ]

(* External tools the harness may invoke.

   The rule is about what the harness is *written in*, not about refusing to
   call anything outside OCaml. A solver or a checker invoked as a subprocess is
   an oracle: it answers a question and the harness decides what the answer
   means. That is categorically different from implementing harness logic in
   another language, where the logic itself escapes review and testing.

   The test for whether an external tool is acceptable: could it silently change
   a verdict? A tool is fine when the harness validates its output, classifies
   its failures, and treats absence as "nothing proved" rather than "passed".
   All three below meet that bar and each has tests for the absent case.

     gospel   L3 contract checking; absent => unavailable, never checked
     z3       proves the dependency graph admits a build order; absent =>
              Solver_missing, never mistaken for a proof
     python3  runs the frozen reference during capture only, via the declared
              adapter above; absent => Interpreter_missing, never a trace *)
let permitted_external_tools =
  [ ("gospel", "L3 contract checking; a missing binary yields Unavailable");
    ("z3", "dependency-graph ordering proof and critical-component specs; a missing solver yields Solver_missing");
    ("python3", "runs the frozen reference during capture; absent yields Interpreter_missing");
    ("df", "free-space oracle for the resource-envelope preflight; its output is parsed and validated, and any failure to read a positive figure is Unknown, never treated as available");
    ("quint", "bounded state-machine checker for the .qnt specs; its verdict is differentially compared against the OCaml transition system, and an absent binary skips the differential with disclosure, never a verdict") ]

(* Build and shell surfaces: where tooling would actually be invoked. Doc files
   are excluded deliberately -- prose about the Python reference is expected,
   and policing it would train people to avoid saying the word. *)
let tooling_extensions = [ ".sh"; ".bash"; ".mk"; ".yml"; ".yaml" ]
let tooling_filenames = [ "dune"; "dune-project"; "Makefile" ]

let has_prefix ~prefix value =
  String.length value >= String.length prefix
  && String.sub value 0 (String.length prefix) = prefix

let has_suffix ~suffix value =
  String.length value >= String.length suffix
  && String.sub value
       (String.length value - String.length suffix)
       (String.length suffix)
     = suffix

(** Plain substring containment, deliberately not word-bounded: an interpreter
    appears as [python], [python3] and [python3.11], and a word-bounded match
    for "python" misses every one of the suffixed forms. Over-matching here is
    the safe direction — a false positive is resolved by declaring it. *)
let contains text needle =
  let length = String.length text and needle_length = String.length needle in
  let rec loop index =
    if index + needle_length > length then false
    else if String.sub text index needle_length = needle then true
    else loop (index + 1)
  in
  needle_length > 0 && loop 0

let in_data_root path = List.exists (fun root -> has_prefix ~prefix:root path) data_roots
let declared path = List.mem_assoc path declared_exceptions

let read_file path =
  try
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () -> Some (really_input_string channel (in_channel_length channel)))
  with Sys_error _ | End_of_file -> None

let is_tooling_file path =
  let base = Filename.basename path in
  List.mem base tooling_filenames
  || List.exists (fun extension -> has_suffix ~suffix:extension path) tooling_extensions

module For_test = struct
  let before_classify = ref (fun (_ : string) -> ())

  let with_before_classify hook body =
    let previous = !before_classify in
    before_classify := hook;
    Fun.protect ~finally:(fun () -> before_classify := previous) body
end

let first_line text =
  match String.index_opt text '\n' with
  | None -> text
  | Some index -> String.sub text 0 index

let rec walk ~root relative accumulator =
  let absolute = if relative = "" then root else Filename.concat root relative in
  match Sys.readdir absolute with
  | exception Sys_error _ -> accumulator
  | entries ->
      Array.sort String.compare entries;
      Array.fold_left
        (fun accumulator name ->
          let child = if relative = "" then name else relative ^ "/" ^ name in
          let child_absolute = Filename.concat root child in
          (!For_test.before_classify) child_absolute;
          match Sys.is_directory child_absolute with
          | true ->
              if List.mem name ignored_directories then accumulator
              else walk ~root child accumulator
          | false -> inspect ~root child accumulator
          | exception Sys_error _ -> accumulator)
        accumulator entries

and inspect ~root path accumulator =
  if in_data_root path || declared path then accumulator
  else
    let base = Filename.basename path in
    if base = "requirements.txt" then
      { path; reason = "Forbidden Python requirements manifest" } :: accumulator
    else if base = "package.json" then
      { path; reason = "Forbidden Node package manifest" } :: accumulator
    else if has_suffix ~suffix:".py" path then
      { path; reason = "Python source file in the harness workspace" } :: accumulator
    else
      match read_file (Filename.concat root path) with
      | None -> accumulator
      | Some contents ->
          let shebang = first_line contents in
          if has_prefix ~prefix:"#!" shebang && contains shebang "python" then
            { path; reason = "python shebang" } :: accumulator
          else if is_tooling_file path && contains contents "python" then
            { path; reason = "build or shell surface invoking python" } :: accumulator
          else accumulator

let scan ~root =
  let opam = Filename.concat root "hermes_workspace.opam" in
  let locked = Filename.concat root "hermes_workspace.opam.locked" in
  let initial = ref [] in
  if not (Sys.file_exists opam) then
    initial := { path = "hermes_workspace.opam"; reason = "Missing root opam manifest" } :: !initial;
  if not (Sys.file_exists locked) then
    initial := { path = "hermes_workspace.opam.locked"; reason = "Missing root opam lockfile" } :: !initial;
  let accumulated = walk ~root "" !initial in
  List.rev accumulated

let render violation =
  Printf.sprintf "%s: %s" violation.path violation.reason
