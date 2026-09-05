(* Fractally contextual diagnostics for the harness.

   A harness message that says only "capture failed" is useless twice over: it
   does not say *where in the fractal* the failure sits, and it does not say
   what the failure means for parity. Both matter here, because the whole
   system is an evidence chain and a defect at one level invalidates different
   things than a defect at another.

   Every diagnostic therefore carries two independent coordinates:

     fractal   which level of the evidence fractal is implicated (L0 product
               through L6 verifier receipt), and which node
     rca       where the defect was *introduced*, not where it surfaced:
               Specification, Implementation, Environment, Evidence, Control

   The RCA axis is what makes these diagnosable rather than merely located. A
   gospel timeout and a wrong gospel verdict are both "L3 problems", but one is
   Environment (nothing was proved) and the other is Specification (something
   was disproved). Conflating them is how a tooling gap gets recorded as a
   contract defect, which is the single failure this evidence store exists to
   prevent.

   Each diagnostic also names the hazard it realises, from the STPA/FMEA
   analysis below, so a message in a log can be traced back to the analysis
   that predicted it -- and, if it names no hazard, that absence is itself a
   finding: something is failing in a way nobody analysed. *)

type fractal_level = L0_product | L1_family | L2_capability | L3_contract
                   | L4_fixture | L5_trace | L6_receipt
                   (* LX is NOT a level of the evidence chain: it is the
                      machinery that builds it. A control-plane failure filed
                      at an evidence level reads as a parity finding, which is
                      exactly the confusion R9 forbids (gap F-LX-1). *)
                   | LX_control

let level_name = function
  | L0_product -> "L0/product"
  | L1_family -> "L1/family"
  | L2_capability -> "L2/capability"
  | L3_contract -> "L3/contract"
  | L4_fixture -> "L4/fixture"
  | L5_trace -> "L5/trace"
  | L6_receipt -> "L6/receipt"
  | LX_control -> "LX/control-plane"

(* Where a defect enters. Deliberately not "severity": severity is a judgement
   about consequence, this is a claim about origin, and only the second one
   tells you where to go looking. *)
type origin =
  | Specification  (* the contract or scenario says the wrong thing *)
  | Implementation (* the candidate does not do what it says *)
  | Environment    (* a tool or dependency could not answer; nothing was proved *)
  | Evidence       (* recorded evidence is missing, edited, or self-inconsistent *)
  | Control        (* the harness itself misbehaved; every verdict is suspect *)

let origin_name = function
  | Specification -> "specification"
  | Implementation -> "implementation"
  | Environment -> "environment"
  | Evidence -> "evidence"
  | Control -> "control"

(* Whether the diagnostic bears on parity at all. An Environment failure must
   never reduce parity: nothing was disproved, so nothing may be deducted. *)
type parity_effect =
  | Blocks_credit    (* cannot grant credit, but grants no negative finding *)
  | Denies_credit    (* a genuine divergence: credit is refused *)
  | No_effect        (* informational *)

let effect_name = function
  | Blocks_credit -> "blocks credit (nothing proved)"
  | Denies_credit -> "denies credit (divergence proved)"
  | No_effect -> "no parity effect"

type t = {
  hazard : string;          (* identifier from the analysis, "" if unanalysed *)
  level : fractal_level;
  origin : origin;
  impact : parity_effect;
  node : string;            (* fractal node or scenario this concerns *)
  subject : string;         (* the specific artifact: a file, a contract id *)
  message : string;
  cause : string;
  fix : string;
}

let make ?(hazard = "") ?(node = "") ?(subject = "") ~level ~origin ~impact ~message
    ~cause ~fix () =
  { hazard; level; origin; impact; node; subject; message; cause; fix }

(* Rendered so that the fractal coordinate leads: a reader scanning a log is
   almost always asking "what is broken and does it cost me parity", and both
   answers are on the first line. *)
let render diagnostic =
  let buffer = Buffer.create 256 in
  Buffer.add_string buffer
    (Printf.sprintf "[%s %s] %s" (level_name diagnostic.level)
       (origin_name diagnostic.origin) diagnostic.message);
  if diagnostic.node <> "" then
    Buffer.add_string buffer (Printf.sprintf "\n    node: %s" diagnostic.node);
  if diagnostic.subject <> "" then
    Buffer.add_string buffer (Printf.sprintf "\n    subject: %s" diagnostic.subject);
  Buffer.add_string buffer (Printf.sprintf "\n    parity: %s" (effect_name diagnostic.impact));
  Buffer.add_string buffer (Printf.sprintf "\n    root cause: %s" diagnostic.cause);
  Buffer.add_string buffer (Printf.sprintf "\n    fix: %s" diagnostic.fix);
  (* A proved divergence is the harness working, not an unpredicted failure, so
     it is not a hazard and must not be tagged UNANALYSED. UNANALYSED is
     reserved for a harness failure -- anything that blocks credit -- that no
     hazard predicted, which is the case a reader must be alarmed by. *)
  let hazard_line =
    if diagnostic.hazard <> "" then diagnostic.hazard
    else if diagnostic.impact = Denies_credit then
      "n/a - a proved divergence is a result, not a harness failure mode"
    else "UNANALYSED - this failure mode is not in the hazard analysis"
  in
  Buffer.add_string buffer (Printf.sprintf "\n    hazard: %s" hazard_line);
  Buffer.contents buffer

(* ---------------------------------------------------------------- hazards *)

(* STPA framing. The harness is the controller; the controlled processes are
   the frozen reference and the OCaml candidate; the control actions are
   capture, check, and admit-credit. An unsafe control action is one that
   grants or withholds parity credit wrongly.

   The system-level hazard is single and specific:

     H-1  parity credit is granted for a capability that has not been shown
          equivalent to the frozen reference

   Its mirror, H-2 (credit withheld from a capability that *is* equivalent), is
   real but not dangerous: it under-reports, and under-reporting is recoverable.
   H-1 is not, because downstream work trusts it. Every entry below is
   classified by which it realises. *)

type hazard = {
  id : string;
  unsafe_action : string;   (* the STPA unsafe control action *)
  failure_mode : string;    (* the FMEA failure mode *)
  effect_if_undetected : string;
  detection : string;       (* how the harness actually detects it, today *)
  realises_h1 : bool;
}

let hazards =
  [ { id = "HZ-CAP-01";
      unsafe_action = "capture is treated as successful when the reference never ran";
      failure_mode = "interpreter, adapter or frozen reference absent";
      effect_if_undetected =
        "an empty or stale trace becomes the reference half of a comparison, and \
         the candidate is compared against nothing";
      detection =
        "Reference_capture returns Interpreter_missing / Adapter_missing / \
         Reference_missing; each is a distinct constructor with its own test";
      realises_h1 = true };
    { id = "HZ-CAP-02";
      unsafe_action = "capture is treated as successful when the reference crashed";
      failure_mode = "adapter exits non-zero, is signalled, or times out";
      effect_if_undetected = "a partial or empty trace is recorded as authoritative";
      detection =
        "Exited / Timed_out, with the child killed on deadline; chaos tests drive \
         SIGKILL and a slow child";
      realises_h1 = true };
    { id = "HZ-CAP-03";
      unsafe_action = "capture accepts output that is not a reference trace";
      failure_mode = "adapter emits garbage, valid JSON of the wrong shape, or nothing";
      effect_if_undetected = "an arbitrary document is compared as if it were the reference";
      detection =
        "Unreadable / Reference_error; chaos tests drive bare arrays, bare \
         strings, missing trace field, empty output and a 2000-line flood";
      realises_h1 = true };
    { id = "HZ-FIX-01";
      unsafe_action = "an edited fixture is loaded as the reference";
      failure_mode = "a committed trace is modified by hand or corrupted on disk";
      effect_if_undetected =
        "parity is measured against a fabricated reference, which is worse than \
         having no reference at all";
      detection =
        "load re-derives the digest from the trace instead of trusting the file; \
         fuzz corrupts 120 fixtures and asserts each is refused or provably intact";
      realises_h1 = true };
    { id = "HZ-FIX-02";
      unsafe_action = "a fixture from another snapshot is substituted";
      failure_mode = "scenario exists but was captured under a different frozen source";
      effect_if_undetected =
        "the candidate is compared against a reference that no longer exists";
      detection =
        "fixtures are keyed by scenario and snapshot digest; a different snapshot \
         is a different file, and loading the wrong one reports absence";
      realises_h1 = true };
    { id = "HZ-FIX-03";
      unsafe_action =
        "a scenario is pinned that does not exercise the capability it is named for";
      failure_mode =
        "a well-formed, correctly digested trace whose payload ANY implementation \
         reproduces — the fixture is valid in every respect the other checks test";
      effect_if_undetected =
        "the slice reports verified while nothing about the capability was \
         exercised, and the credit is indistinguishable from an earned one; the \
         denominator grows while the proof does not";
      detection =
        "Parity_compare.record refuses a reference payload matching the stub \
         template; test_parity_compare asserts the live corpus carries no stub \
         AND that the quarantined corpus is entirely flagged, so the detector \
         cannot pass by firing on nothing";
      realises_h1 = true };
    { id = "HZ-NRM-01";
      unsafe_action = "normalization erases a field that genuinely diverged";
      failure_mode = "a volatile path is declared too broadly";
      effect_if_undetected = "a real divergence is normalized away and parity is granted";
      detection =
        "elision is never inferred: only declared paths are dropped, the declared \
         set is part of the recorded normalization description, and a widened \
         normalizer invalidates existing fixture digests";
      realises_h1 = true };
    { id = "HZ-NRM-02";
      unsafe_action = "normalization leaves run-varying noise in place";
      failure_mode = "a volatile path is not declared";
      effect_if_undetected =
        "every comparison fails, the suite is muted, and real divergences stop \
         being looked at";
      detection = "declared volatile paths, with tests pinning both directions";
      realises_h1 = false };
    { id = "HZ-L3-01";
      unsafe_action = "a tooling gap is recorded as a contract rejection";
      failure_mode = "gospel cannot resolve a module, or is absent";
      effect_if_undetected =
        "a false negative enters the evidence store and a sound contract is \
         believed broken";
      detection =
        "gospel-lint separates not-checkable (exit 2) and unavailable (exit 3) \
         from rejected (exit 1); receipts are keyed by verifier so an \
         'unavailable' observation cannot overwrite a real check";
      realises_h1 = false };
    { id = "HZ-L3-02";
      unsafe_action = "a stub grants a contract facts the real module lacks";
      failure_mode = "a checking stub is written stronger than what it stands in for";
      effect_if_undetected = "a contract passes on properties that do not hold in reality";
      detection =
        "stubs are abstract and therefore strictly weaker; the convention is \
         recorded in the stub itself and in the zk note";
      realises_h1 = true };
    { id = "HZ-DEP-01";
      unsafe_action = "capabilities are implemented in an order that cannot be built";
      failure_mode = "the dependency graph contains a cycle";
      effect_if_undetected =
        "work is scheduled that can never complete, and the Sa-plan projection \
         silently disagrees with the catalog";
      detection =
        "z3 proves a ranking exists over the real catalog, independently of the \
         depth-first traversal that produces the order; the two must agree";
      realises_h1 = false };
    { id = "HZ-CTL-01";
      unsafe_action = "the harness records evidence it did not verify";
      failure_mode = "an immutable table silently absorbs a divergent replay";
      effect_if_undetected =
        "the evidence store stops being a record of what was checked, and every \
         verdict derived from it is suspect";
      detection =
        "every immutable table rejects a same-key/different-payload replay; \
         node_artifact is exempt only because every column is in its key";
      realises_h1 = true };
    (* Resource shortfalls. None realises H-1: an exhausted disk or a missing
       tool proves nothing about the candidate, so it can never grant credit --
       it can only block. The Resource_envelope preflight detects each before
       the operation runs, turning a mid-run crash into a named refusal. *)
    { id = "HZ-RES-TEMP";
      unsafe_action = "an operation writes temporary trees to a temp filesystem that is already exhausted";
      failure_mode = "the effective temp filesystem ($TMPDIR or /tmp) has less free space than needed plus margin";
      effect_if_undetected =
        "a capture or comparison dies with ENOSPC mid-write, surfacing as a lost \
         command result rather than a diagnosis, and the run cannot be trusted";
      detection =
        "Resource_envelope observes free space via df before the operation and \
         refuses when available < needed*(1+margin) or would fall below the floor";
      realises_h1 = false };
    { id = "HZ-RES-DISK";
      unsafe_action = "an operation writes fixtures, the evidence DB or _build to a full project disk";
      failure_mode = "the filesystem holding the repo has less free space than needed plus margin";
      effect_if_undetected = "a fixture, receipt or build artifact is truncated or fails to write";
      detection = "Resource_envelope checks project-disk free space with the same margin and floor";
      realises_h1 = false };
    { id = "HZ-RES-BIN";
      unsafe_action = "an operation starts without an external oracle it depends on";
      failure_mode = "a required binary (the reference interpreter, gospel, z3) is absent from PATH";
      effect_if_undetected =
        "the shortfall is discovered mid-run as a per-tool failure rather than surfaced together up front";
      detection = "Resource_envelope resolves each declared binary on PATH (or its override variable) before running";
      realises_h1 = false };
    { id = "HZ-RES-KERNEL";
      unsafe_action =
        "a supervised oracle starts before the host kernel facilities needed to contain it are known to exist";
      failure_mode =
        "the kernel does not expose /proc/self/fd executable-object access, RLIMIT_AS support, or process-group signalling";
      effect_if_undetected =
        "the worker can start without an enforceable memory boundary, stable executable object, or bounded group cleanup";
      detection =
        "Resource_envelope observes every declared kernel supervision capability before any worker is spawned and treats unknown as unmet";
      realises_h1 = false };
    { id = "HZ-RES-DB";
      unsafe_action = "the harness records receipts to an evidence store it cannot write";
      failure_mode = "the SQLite file or its directory is read-only";
      effect_if_undetected = "receipts are silently lost and a run reads as complete when evidence was not stored";
      detection = "Resource_envelope checks the store path (or its parent) is writable before comparison";
      realises_h1 = false };
    { id = "HZ-RES-REF";
      unsafe_action = "a comparison runs against an absent frozen reference";
      failure_mode = "external/hermes_source is missing or empty in this checkout";
      effect_if_undetected = "capture cannot produce the reference half and the shortfall surfaces late";
      detection =
        "Resource_envelope confirms the snapshot root is present and non-empty up front; the \
         digest pin itself is verified by Inventory";
      realises_h1 = false };
    (* Determinacy: a non-reproducible apparatus (the zigvm GATE-DETERMINACY
       concern). A flaky pass can grant credit for a candidate that is not
       consistently equivalent, so this realises H-1. *)
    { id = "HZ-DET-01";
      unsafe_action = "a parity verdict is trusted from a non-reproducible apparatus";
      failure_mode = "the candidate replay/decode/normalize pipeline is not byte-stable run to run";
      effect_if_undetected =
        "a flaky pass grants parity credit for a candidate that is not consistently \
         equivalent, and a flaky fail hides a real divergence";
      detection =
        "Determinism_verifier replays each producer twice and byte-compares the normalized \
         renders; any variance is a Control-origin block, fixed constructively not hidden";
      realises_h1 = true } ]

let hazard id = List.find_opt (fun hazard -> hazard.id = id) hazards
let realising_h1 () = List.filter (fun hazard -> hazard.realises_h1) hazards
(* ------------------------------------------------------------------- otel *)

(* OpenTelemetry log records, so a diagnostic is observable by the same tooling
   as everything else rather than being a bespoke string format.

   The fractal coordinates are carried as attributes, not folded into the body:
   a body is for humans, attributes are what a backend can filter and group on.
   That is what makes the fractal queryable -- "show me every L4 Environment
   event for this node" is an attribute query, and would be a regex over prose
   if the coordinates lived in the message.

   Timestamps and ids are parameters rather than generated here. A logger that
   invents its own time and identity cannot be tested for the shape it emits,
   and a diagnostic whose rendering changes run to run is not reproducible
   evidence. *)

let severity_number = function
  (* OTel severity numbers: ERROR 17, WARN 13, INFO 9. A blocked credit is a
     warning, not an error: nothing is broken, something is unproven. *)
  | Denies_credit -> 17
  | Blocks_credit -> 13
  | No_effect -> 9

let severity_text = function
  | Denies_credit -> "ERROR"
  | Blocks_credit -> "WARN"
  | No_effect -> "INFO"

let attribute key value : Yojson.Safe.t =
  `Assoc [ ("key", `String key); ("value", `Assoc [ ("stringValue", `String value) ]) ]

let bool_attribute key value : Yojson.Safe.t =
  `Assoc [ ("key", `String key); ("value", `Assoc [ ("boolValue", `Bool value) ]) ]

(** A single OTLP log record. [trace_id] must be 32 hex characters and
    [span_id] 16, per the OTLP specification; both are supplied by the caller
    so a whole verify run shares one trace. *)
let to_otlp_log ~time_unix_nano ~trace_id ~span_id diagnostic : Yojson.Safe.t =
  let realises =
    match hazard diagnostic.hazard with
    | Some hazard -> hazard.realises_h1
    | None -> false
  in
  `Assoc
    [ ("timeUnixNano", `String (Int64.to_string time_unix_nano));
      ("observedTimeUnixNano", `String (Int64.to_string time_unix_nano));
      ("severityNumber", `Int (severity_number diagnostic.impact));
      ("severityText", `String (severity_text diagnostic.impact));
      ("body", `Assoc [ ("stringValue", `String diagnostic.message) ]);
      ("traceId", `String trace_id);
      ("spanId", `String span_id);
      ( "attributes",
        `List
          [ attribute "hermes.fractal.level" (level_name diagnostic.level);
            attribute "hermes.rca.origin" (origin_name diagnostic.origin);
            attribute "hermes.parity.effect" (effect_name diagnostic.impact);
            attribute "hermes.fractal.node" diagnostic.node;
            attribute "hermes.subject" diagnostic.subject;
            attribute "hermes.hazard"
              (if diagnostic.hazard = "" then "unanalysed" else diagnostic.hazard);
            bool_attribute "hermes.hazard.realises_h1" realises;
            attribute "hermes.cause" diagnostic.cause;
            attribute "hermes.fix" diagnostic.fix ] ) ]

(** A full OTLP ExportLogsServiceRequest payload, ready to POST to a collector
    or write to a file. Resource attributes identify the emitter; scope
    identifies which part of the harness produced the records. *)
let to_otlp_payload ~service ~scope ~time_unix_nano ~trace_id ~span_id diagnostics :
    Yojson.Safe.t =
  `Assoc
    [ ( "resourceLogs",
        `List
          [ `Assoc
              [ ( "resource",
                  `Assoc
                    [ ( "attributes",
                        `List
                          [ attribute "service.name" service;
                            attribute "service.namespace" "hermes.harness" ] ) ] );
                ( "scopeLogs",
                  `List
                    [ `Assoc
                        [ ("scope", `Assoc [ ("name", `String scope) ]);
                          ( "logRecords",
                            `List
                              (List.map
                                 (to_otlp_log ~time_unix_nano ~trace_id ~span_id)
                                 diagnostics) ) ] ] ) ] ] ) ]


(* ------------------------------------------------- adapters for subsystems *)

(* A divergence between reference and candidate is the one thing that denies
   credit. It is Implementation, not Environment: something was proved. *)
let of_divergence ~node ~subject ~reference_digest ~candidate_digest =
  make ~hazard:"" ~level:L6_receipt ~origin:Implementation ~impact:Denies_credit ~node
    ~subject
    ~message:
      (Printf.sprintf "candidate diverges from the frozen reference (%s vs %s)"
         reference_digest candidate_digest)
    ~cause:
      "the normalized candidate trace differs from the normalized reference trace \
       at a path that is not declared volatile"
    ~fix:
      "either the candidate is wrong, or the divergence is intended and the \
       scenario needs revisiting; do not widen the normalizer to make it pass"
    ()
