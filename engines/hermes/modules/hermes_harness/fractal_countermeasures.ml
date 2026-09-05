(* Fractal countermeasures: the response to a detected hazard.

   A hazard analysis that names failures but never says what to do about them is
   half an analysis. This table pairs each hazard the harness can act on with a
   countermeasure, and draws the one distinction that matters operationally:
   whether the response is SAFE TO APPLY AUTOMATICALLY, or needs human judgement
   and is therefore advice, not action.

   The rule is conservative by construction. Automatic is reserved for responses
   that cannot themselves cause harm -- relocating scratch space, say. Anything
   that deletes, fetches over the network, or changes permissions is Manual,
   because an automatic response that destroys evidence or reaches outside the
   checkout is a worse failure than the one it answers. Completeness is enforced
   by the test: every hazard that realises H-1, and every resource hazard, has
   an entry here, and each entry names a hazard that really exists. *)

type action =
  | Automatic of { command : string; rationale : string }
      (** Safe to apply without judgement: it cannot destroy evidence, reach the
          network, or change trust. *)
  | Manual of string
      (** Requires judgement; the string is the advice and the reason it is not
          automated. *)

type countermeasure = { hazard : string; detect : string; action : action }

let countermeasures =
  [ (* Resource shortfalls. Only relocating scratch is safe to automate; freeing
       space, provisioning tools, changing permissions and fetching a reference
       all require judgement and could do harm, so they are advice. *)
    { hazard = "HZ-RES-TEMP";
      detect = "the temp-space preflight reports insufficient space or falls below the floor";
      action =
        Automatic
          { command = "TMPDIR=$PWD/state/tmp <re-run>";
            rationale =
              "the project disk has room and only scratch is relocated; this was the safe \
               manual workaround this session and it destroys nothing" } };
    { hazard = "HZ-RES-DISK";
      detect = "the project-disk preflight reports insufficient space";
      action =
        Manual
          "free space on the project disk by deciding what to remove; the harness must never \
           delete files automatically, because it cannot know which are evidence" };
    { hazard = "HZ-RES-BIN";
      detect = "a required oracle is not resolvable on PATH";
      action =
        Manual
          "provision the missing binary deliberately (the reference interpreter via \
           state/reference_env, or gospel/z3 via the pinned switch); auto-installing tools \
           is not safe" };
    { hazard = "HZ-RES-KERNEL";
      detect =
        "the kernel-capability preflight cannot confirm /proc/self/fd, RLIMIT_AS, or process-group signalling";
      action =
        Manual
          "run the supervised worker on a platform whose kernel provides the declared isolation \
           facilities, or keep the operation unavailable; never mutate host limits, permissions, \
           or kernel configuration automatically" };
    { hazard = "HZ-RES-DB";
      detect = "the evidence-store path is not writable";
      action =
        Manual
          "make state/ (or the sqlite path) writable, or relocate it; changing permissions \
           automatically could expose or clobber the store" };
    { hazard = "HZ-RES-REF";
      detect = "the frozen reference is absent or empty";
      action =
        Manual
          "restore external/hermes_source at the pinned snapshot; never auto-fetch a \
           reference, since the fetched tree is exactly what must be trusted" };
    (* The H-1 hazards. Each is an evidence- or specification-integrity failure,
       where the wrong automatic response is precisely how false parity is
       manufactured; so all are advice, each a concrete instruction. *)
    { hazard = "HZ-CAP-01";
      detect = "capture reports Interpreter_missing, Adapter_missing or Reference_missing";
      action =
        Manual
          "provision the missing piece (state/reference_env, the committed adapter, or \
           external/hermes_source); a capture with no reference must never be recorded as success" };
    { hazard = "HZ-CAP-02";
      detect = "capture reports Timed_out or Exited";
      action =
        Manual
          "read the adapter output; a reference that hangs or crashes on a scenario is itself \
           a finding, not something to retry blindly" };
    { hazard = "HZ-CAP-03";
      detect = "capture reports Unreadable or Reference_error";
      action =
        Manual
          "inspect the raw output by hand; do not record it as a trace and do not coerce it \
           into the expected shape" };
    { hazard = "HZ-FIX-01";
      detect = "a fixture's re-derived digest does not match its contents";
      action =
        Manual
          "recapture the fixture from the frozen reference; never hand-edit a committed trace \
           to make it match" };
    { hazard = "HZ-FIX-02";
      detect = "a fixture from a different snapshot is loaded";
      action =
        Manual
          "recapture under the current snapshot; a fixture is keyed by snapshot and one from \
           another must not be reused" };
    { hazard = "HZ-FIX-03";
      detect =
        "a reference payload does not exercise the capability its scenario is named for";
      action =
        Manual
          "author a scenario that FAILS against a deliberately wrong candidate before \
           pinning it; a trace every implementation reproduces is not differential \
           evidence, and adding more of them enlarges the denominator while proving \
           nothing. Never repair one by editing the committed trace (HZ-FIX-01) — \
           replace the scenario and recapture" };
    { hazard = "HZ-NRM-01";
      detect = "a real divergence disappears after a normalizer change";
      action =
        Manual
          "narrow the volatile set; elision must never be widened to clear a divergence, \
           which is how false parity is manufactured" };
    { hazard = "HZ-L3-02";
      detect = "a checking stub is stronger than the module it stands in for";
      action =
        Manual
          "weaken the stub to be strictly abstract; a stub must never grant a contract facts \
           the real module lacks" };
    { hazard = "HZ-CTL-01";
      detect = "an immutable table rejects a same-key, different-payload replay";
      action =
        Manual
          "treat the conflict as the finding; investigate why the payload changed, and never \
           delete rows to force the write through" };
    { hazard = "HZ-DET-01";
      detect = "the determinism gate reports an unstable producer (two different normalized renders for one input)";
      action =
        Manual
          "make the pipeline deterministic -- remove the RNG, wall-clock or hash-order \
           dependence that varies the output; never re-run until it passes, which hides the \
           defect (the GATE-DETERMINACY anti-pattern)" } ]

let for_hazard id = List.find_opt (fun countermeasure -> countermeasure.hazard = id) countermeasures

let is_automatic countermeasure =
  match countermeasure.action with Automatic _ -> true | Manual _ -> false

(* The ids that MUST have a countermeasure: every resource hazard and every
   hazard that realises H-1. Given the hazard analysis, so the requirement grows
   automatically as hazards are added. *)
let required_hazards () =
  Fractal_diagnostic.hazards
  |> List.filter (fun (hazard : Fractal_diagnostic.hazard) ->
         hazard.realises_h1
         || (String.length hazard.id >= 7 && String.sub hazard.id 0 7 = "HZ-RES-"))
  |> List.map (fun (hazard : Fractal_diagnostic.hazard) -> hazard.id)

let uncovered () =
  List.filter (fun id -> for_hazard id = None) (required_hazards ())

let render countermeasure =
  match countermeasure.action with
  | Automatic { command; rationale } ->
      Printf.sprintf "%s: AUTO  %s -- %s" countermeasure.hazard command rationale
  | Manual reason -> Printf.sprintf "%s: MANUAL  %s" countermeasure.hazard reason
