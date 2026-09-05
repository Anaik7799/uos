(* The wiki/ZK knowledge-management system AS an F Prime topology — every
   aspect of the build-out plan's monitoring table an actor, every gauge a
   telemetry channel, every control a command, the two control loops state
   machines. Mirrors harness_topology's construction (R14) and lives inside
   the wiki folder, with its base-id allocation supplied by the neutral
   hermes_fpp_window_authority leaf.

   The R5-shaped design law, enforced by test_wiki_topology: auditors SENSE
   and REPORT — no graph gives an auditor a connection into corpusStore, so
   a monitor cannot write the corpus by construction of the topology.

   Actual base ids are topology-local diagnostic facts. They are not a claim of
   global disjointness from Harness: both systems retain known legacy actual
   instances at 0x1000 and 0x1100. Normative owner allocations instead come
   from hermes_fpp_window_authority. *)

open Fpp_model

let ping_pair =
  [ General { name = "pingIn"; port = "Ping"; direction = Sync_input; count = 1 };
    General { name = "pingOut"; port = "Ping"; direction = Output; count = 1 } ]

let chan ?(update = Always) name id =
  { chan_name = name; chan_id = id; chan_type = Prim U32; update;
    chan_format = None; low = None; high = None }

let warn name id fmt =
  { event_name = name; event_id = id; severity = Warning_hi; format = fmt; throttle = None }

(* ------------------------------------------------------------ components *)

(* The corpus of record. The only component whose state IS the knowledge;
   everything else derives, senses or reports. PIN_BASELINE is GUARDED:
   re-pinning accepts a corpus-wide change and is a deliberate act. *)
let corpus_store =
  { comp_name = "corpusStore"; kind = Passive;
    ports = [ General { name = "read"; port = "Docs"; direction = Sync_input; count = 8 };
              Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = [ { cmd_name = "PIN_BASELINE"; opcode = 0; cmd_kind = Guarded_cmd; cmd_params = [] } ];
    events = [ warn "DRIFT_DETECTED" 0 "render drift on %s" ];
    channels = [ chan "corpus_docs" 0; chan "drift_count" 1 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Renderer: the AST catamorphism + section builder (Dep_sheaf). Its gauge
   is the sheaf's tightness — dead cover means wasted incremental work. *)
let renderer =
  { comp_name = "renderer"; kind = Passive;
    ports = [ General { name = "render"; port = "Docs"; direction = Sync_input; count = 4 };
              General { name = "docsOut"; port = "Docs"; direction = Output; count = 1 };
              Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = [];
    events = [];
    channels = [ chan "renders_total" 0; chan "dead_cover" 1 ~update:On_change;
                 chan "dirty_rebuilds" 2;
                 (* HW.3.5.1: embeds that could not be expanded, and
                    cycles broken where they closed. Both REPORTED — a
                    silent empty embed would make a missing definition
                    look like a definition that says nothing. *)
                 chan "embed_gaps" 6 ~update:On_change;
                 chan "embed_cycles" 7 ~update:On_change;
                 (* HW.9.3.1: tested examples drifting from the renderer *)
                 chan "doctest_drift" 3 ~update:On_change;
                 (* HW.9.2.1: source slices that did not resolve *)
                 chan "include_gaps" 4 ~update:On_change;
                 (* HW.2.6.6: fence options outside their own body *)
                 chan "fence_option_gaps" 5 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Query engine: totality is the law, so the gauge counts NAMED rejects —
   an unnamed failure would be the defect. *)
let query_engine =
  { comp_name = "queryEngine"; kind = Passive;
    ports = [ General { name = "eval"; port = "Query"; direction = Sync_input; count = 4 };
              General { name = "docsOut"; port = "Docs"; direction = Output; count = 1 };
              Special Telemetry_p ] @ ping_pair;
    commands = [];
    events = [];
    channels = [ chan "queries_total" 0; chan "query_rejects_named" 1 ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Link auditor: the three reference diagnoses, each its own gauge because
   each has its own fix. Queued: audits arrive as work items. *)
let link_auditor =
  { comp_name = "linkAuditor"; kind = Queued;
    ports = [ General { name = "audit"; port = "Audit";
                        direction = Async_input { priority = Some 3; queue_full = Block };
                        count = 1 };
              General { name = "gaugeOut"; port = "Counts"; direction = Output; count = 1 };
              General { name = "docsOut"; port = "Docs"; direction = Output; count = 1 };
              Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = [];
    events = [ warn "DEAD_ANCHOR" 0 "dead anchor %s" ];
    channels = [ chan "dead_links" 0 ~update:On_change;
                 chan "dead_anchors" 1 ~update:On_change;
                 chan "ambiguous_refs" 2 ~update:On_change;
                 (* HW.3.7.3: the render gate's own defects, pinned apart
                    from dead links since the gauge went honest *)
                 chan "corpus_defects" 3 ~update:On_change;
                 (* HW.3.7.6: opt-outs — disclosed telemetry, never pinned *)
                 chan "suppressed_refs" 4;
                 (* HW.3.7.4: the vocabulary's enforcement gauge *)
                 chan "term_gaps" 5 ~update:On_change;
                 (* HW.2.6.3: see-entries into nothing *)
                 chan "index_violations" 6 ~update:On_change ] ;
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Model gate: the MBSE spine's sensor. The programme's rule is that a
   feature is a MODEL ELEMENT before it is code, and this is the
   component that can tell whether that held — it reads the register's
   projection into SysML/OML/MMS and counts the requirements that carry
   no verification method.

   It is a MONITOR like every other auditor here: it senses and reports,
   and no edge runs from it to corpusStore. Its gauge BLOCKS credit and
   never denies it (R5) — a model gap is the harness's own bookkeeping
   debt and proves nothing whatever about a candidate, so its origin is
   Control and it can never be recorded as an implementation defect. *)
let model_gate =
  { comp_name = "modelGate"; kind = Queued;
    ports = [ General { name = "audit"; port = "Audit";
                        direction = Async_input { priority = Some 2; queue_full = Block };
                        count = 1 };
              General { name = "gaugeOut"; port = "Counts"; direction = Output; count = 1 };
              General { name = "docsOut"; port = "Docs"; direction = Output; count = 1 };
              Special Event_p; Special Telemetry_p ] @ ping_pair;
    commands = [];
    events =
      [ warn "MODEL_GAP" 0 "requirement with no verification method: %s";
        warn "MODEL_DANGLING" 1 "dependency on an element the model lacks: %s" ];
    channels =
      [ (* built rows whose model element states a requirement nothing
           executes — a requirement no run can ever contradict *)
        chan "model_gaps" 0 ~update:On_change;
        (* the model's own size and reach, disclosed rather than pinned:
           they grow as the register grows, and a ratchet on a number
           that must rise would fire on progress *)
        chan "model_elements" 1 ~update:On_change;
        chan "model_verified" 2 ~update:On_change;
        (* a dependency edge naming an element the model does not contain:
           the model referring to something it does not describe, which
           makes every traversal of it silently incomplete *)
        chan "model_dangling" 3 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Schema auditor: the PKM conformance debt (spec §3), the ratchet's
   largest gauge today. *)
let schema_auditor =
  { comp_name = "schemaAuditor"; kind = Queued;
    ports = [ General { name = "audit"; port = "Audit";
                        direction = Async_input { priority = Some 2; queue_full = Block };
                        count = 1 };
              General { name = "gaugeOut"; port = "Counts"; direction = Output; count = 1 };
              General { name = "docsOut"; port = "Docs"; direction = Output; count = 1 };
              Special Event_p; Special Telemetry_p ] @ ping_pair;
    commands = [];
    events = [ warn "SCHEMA_GAP" 0 "schema gap: %s" ];
    channels = [ chan "schema_debt" 0 ~update:On_change;
                 (* HW.1.4.1 — the visibility split. `drafts` is not a
                    defect count: a draft is a legitimate state, and the
                    gauge exists so the size of the unbuilt set is
                    visible rather than implicit. `visibility_malformed`
                    IS a defect: a misspelled value must never publish a
                    page by accident. *)
                 chan "drafts" 1 ~update:On_change;
                 chan "visibility_malformed" 2 ~update:On_change;
                 (* HW.1.3.11 — two sibling pages claiming the same
                    sidebar_position. NOT a malformed value (that clamps
                    to None and is unordered, which is defined); this is
                    two authors both declaring "I am third", which the
                    order can only resolve behind their backs. Reported
                    so the author breaks the tie, never the sort. *)
                 chan "position_conflicts" 3 ~update:On_change;
                 (* HW.8.5.3 — the concept model enforced: corpus values
                    outside a CLOSED controlled vocabulary. Distinct from
                    schema_debt, which counts values that are ABSENT: a
                    misspelled ktype and a missing one need different
                    fixes, and one gauge for both hides which you have. *)
                 chan "vocabulary_gaps" 4 ~update:On_change;
                 (* HW.1.2.6 — the declared-slug escape hatch. Overrides
                    are DISCLOSED (a legitimate act that must leave a
                    mark); a collision between two claims is a DEFECT. *)
                 chan "slug_collisions" 5 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Graph analyzer: structural health — orphans, grounded-standing
   anomalies, and the navigability eccentricity of the hub. *)
let graph_analyzer =
  { comp_name = "graphAnalyzer"; kind = Queued;
    ports = [ General { name = "audit"; port = "Audit";
                        direction = Async_input { priority = Some 2; queue_full = Block };
                        count = 1 };
              General { name = "gaugeOut"; port = "Counts"; direction = Output; count = 1 };
              General { name = "docsOut"; port = "Docs"; direction = Output; count = 1 };
              Special Event_p; Special Telemetry_p ] @ ping_pair;
    commands = [];
    events = [ warn "UNGROUNDED_CLAIM" 0 "claim outside the grounded extension: %s" ];
    channels = [ chan "orphans" 0 ~update:On_change;
                 chan "grounded_anomalies" 1 ~update:On_change;
                 chan "ecc_hub" 2 ~update:On_change;
                 (* HW.6.8.1: declarations that could not become edges *)
                 chan "toc_gaps" 3 ~update:On_change;
                 (* navigation debt: pages the DECLARED tree does not
                    place. Falls as navigation is authored — the whole
                    point of the row is that this number is a choice. *)
                 chan "toc_unplaced" 4 ~update:On_change;
                 (* HW.6.8.2: the verdict after disclosure *)
                 chan "toc_unreachable" 5 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Browser probe: the Playwright layer as an EXTERNAL ORACLE actor —
   out-of-band by design, so browser state can never perturb a render. *)
let browser_probe =
  { comp_name = "browserProbe"; kind = Queued;
    ports = [ General { name = "probe"; port = "Audit";
                        direction = Async_input { priority = Some 1; queue_full = Drop };
                        count = 1 };
              General { name = "gaugeOut"; port = "Counts"; direction = Output; count = 1 };
              Special Event_p; Special Telemetry_p ] @ ping_pair;
    commands = [];
    events = [ warn "LAYOUT_LAW_BROKEN" 0 "rendered-layout law broken: %s" ];
    channels = [ chan "playwright_pass" 0; chan "playwright_fail" 1 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Ratchet controller: THE control mechanism. Monotone non-increasing
   counts; a breach refuses. RatchetLoop is its machine. *)
let ratchet_controller =
  { comp_name = "ratchetController"; kind = Queued;
    ports = [ General { name = "counts"; port = "Counts";
                        direction = Async_input { priority = Some 4; queue_full = Assert };
                        count = 5 };
              Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = [ { cmd_name = "RATCHET_CHECK"; opcode = 0; cmd_kind = Sync_cmd; cmd_params = [] } ];
    events = [ { event_name = "RATCHET_BREACHED"; event_id = 0; severity = Warning_hi;
                 format = "gauge %s increased"; throttle = None } ];
    channels = [ chan "ratchet_previous" 0; chan "ratchet_current" 1 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = [ ("ratchet", "RatchetLoop") ]; matched = [] }

(* Reconciler: S36 as an actor — declared vs derived over every registry,
   the residue as its gauge (HW.8.2.7). Report-only like every auditor. *)
let reconciler =
  { comp_name = "reconciler"; kind = Queued;
    ports = [ General { name = "audit"; port = "Audit";
                        direction = Async_input { priority = Some 2; queue_full = Block };
                        count = 1 };
              General { name = "gaugeOut"; port = "Counts"; direction = Output; count = 1 };
              Special Event_p; Special Telemetry_p ] @ ping_pair;
    commands = [];
    events =
      [ warn "STALE_DECLARATION" 0 "declared and derived disagree: %s";
        warn "UNPORTED_MIRROR" 1 "an imported module still awaits its port: %s" ];
    channels =
      [ chan "stale_declarations" 0 ~update:On_change;
        chan "unported_mirrors" 1 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Backfiller: the converge loop's ACTUATOR — proposals are free, but the
   corpus-writing APPLY is a GUARDED command (the PIN_BASELINE discipline:
   a deliberate act, never ambient). Its writes happen out-of-band like a
   re-pin, so no graph edge targets corpusStore. *)
let backfiller =
  { comp_name = "backfiller"; kind = Queued;
    ports = [ General { name = "propose"; port = "Audit";
                        direction = Async_input { priority = Some 1; queue_full = Block };
                        count = 1 };
              Special Event_p; Special Telemetry_p ] @ ping_pair;
    commands =
      [ { cmd_name = "PROPOSE"; opcode = 0; cmd_kind = Sync_cmd; cmd_params = [] };
        { cmd_name = "APPLY_BATCH"; opcode = 1; cmd_kind = Guarded_cmd; cmd_params = [] } ];
    events = [ warn "FIELD_INVENTED" 0 "a proposal without evidence: %s" ];
    channels = [ chan "proposals_ready" 0 ~update:On_change; chan "applied_total" 1 ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* Journal keeper: the KM pillar's auditor — R16 names, append-only
   history, the closed privacy trio with Secret rejected. Report-only. *)
let journal_keeper =
  { comp_name = "journalKeeper"; kind = Queued;
    ports = [ General { name = "audit"; port = "Audit";
                        direction = Async_input { priority = Some 1; queue_full = Block };
                        count = 1 };
              General { name = "gaugeOut"; port = "Counts"; direction = Output; count = 1 };
              Special Event_p; Special Telemetry_p ] @ ping_pair;
    commands = [];
    events = [ warn "HISTORY_REWRITTEN" 0 "append-only violated: %s" ];
    channels = [ chan "journal_entries" 0; chan "journal_violations" 1 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = []; machines = [];
    matched = [] }

(* The audit loop: the converge shape — sense every gauge, diff against
   setpoints, report the exact worklist. Active: it owns the cadence. *)
let audit_loop =
  { comp_name = "auditLoop"; kind = Active;
    ports = [ General { name = "run"; port = "Audit";
                        direction = Async_input { priority = Some 5; queue_full = Block };
                        count = 1 };
              General { name = "senseOut"; port = "Audit"; direction = Output; count = 5 };
              Special Event_p; Special Telemetry_p; Special Time_get ] @ ping_pair;
    commands = [ { cmd_name = "RUN_AUDIT"; opcode = 0;
                   cmd_kind = Async_cmd { priority = Some 5; queue_full = Block };
                   cmd_params = [] } ];
    events = [];
    channels = [ chan "audits_total" 0; chan "worklist_items" 1 ~update:On_change ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = [ ("audit", "AuditLoop") ]; matched = [] }

(* ---------------------------------------------------------- state machines *)

let audit_machine =
  Internal_machine
    { machine_name = "AuditLoop";
      signals = [ { signal_name = "tick"; signal_type = None };
                  { signal_name = "gauges_ok"; signal_type = None };
                  { signal_name = "breach"; signal_type = None };
                  { signal_name = "reported"; signal_type = None } ];
      guards = [];
      actions = [ "sense"; "diff"; "report" ];
      states =
        [ { state_name = "Idle"; entry = []; exit_ = [];
            transitions = [ { on_signal = "tick"; guard = None; do_actions = [ "sense" ];
                              target = To_state "Sensing" } ] };
          { state_name = "Sensing"; entry = []; exit_ = [];
            transitions = [ { on_signal = "gauges_ok"; guard = None; do_actions = [ "diff" ];
                              target = To_state "Diffing" } ] };
          { state_name = "Diffing"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "breach"; guard = None; do_actions = [ "report" ];
                  target = To_state "Reporting" };
                { on_signal = "gauges_ok"; guard = None; do_actions = [];
                  target = To_state "Idle" } ] };
          { state_name = "Reporting"; entry = [ "report" ]; exit_ = [];
            transitions = [ { on_signal = "reported"; guard = None; do_actions = [];
                              target = To_state "Idle" } ] } ];
      choices = [];
      initial = ([], "Idle") }

let ratchet_machine =
  Internal_machine
    { machine_name = "RatchetLoop";
      signals = [ { signal_name = "count"; signal_type = None };
                  { signal_name = "not_worse"; signal_type = None };
                  { signal_name = "worse"; signal_type = None } ];
      guards = [];
      actions = [ "compare"; "hold"; "refuse" ];
      states =
        [ { state_name = "Idle"; entry = []; exit_ = [];
            transitions = [ { on_signal = "count"; guard = None; do_actions = [ "compare" ];
                              target = To_state "Checking" } ] };
          { state_name = "Checking"; entry = []; exit_ = [];
            transitions =
              [ { on_signal = "not_worse"; guard = None; do_actions = [ "hold" ];
                  target = To_state "Idle" };
                { on_signal = "worse"; guard = None; do_actions = [ "refuse" ];
                  target = To_state "Breached" } ] };
          (* Breached is terminal for the run: only a new battery run (a new
             machine instance) leaves it — a breach is never waved through. *)
          { state_name = "Breached"; entry = [ "refuse" ]; exit_ = []; transitions = [] } ];
      choices = [];
      initial = ([], "Idle") }

(* -------------------------------------------------------------- instances *)

let instances =
  let queued name base =
    (* queued components own a queue but NOT a thread: no priority/stack/cpu
       (FPP-INST-01 — the validator taught this distinction) *)
    { inst_name = name; of_component = name; base_id = base; queue_size = Some 16;
      stack_size = None; inst_priority = None; cpu = None }
  in
  let passive name base =
    { inst_name = name; of_component = name; base_id = base; queue_size = None;
      stack_size = None; inst_priority = None; cpu = None }
  in
  [ passive "corpusStore" 0x1000;
    passive "renderer" 0x1100;
    passive "queryEngine" 0x1200;
    queued "linkAuditor" 0x1300;
    queued "schemaAuditor" 0x1400;
    queued "graphAnalyzer" 0x1500;
    queued "browserProbe" 0x1600;
    queued "ratchetController" 0x1700;
    queued "reconciler" 0x1900;
    queued "backfiller" 0x1A00;
    queued "journalKeeper" 0x1B00;
    queued "modelGate" 0x1C00;
    { inst_name = "auditLoop"; of_component = "auditLoop";
      base_id = Fpp_window_authority.base_of_instance Fpp_window_authority.Wiki "auditLoop";
      queue_size = Some 16; stack_size = Some 65536; inst_priority = Some 5; cpu = Some 0 } ]

(* -------------------------------------------------------------- topology *)

let connect from_i port_ to_i tport =
  { from_ = { ep_instance = from_i; ep_port = port_; ep_index = None };
    to_ = { ep_instance = to_i; ep_port = tport; ep_index = None } }

let topology =
  { topo_name = "WikiZk";
    members = List.map (fun i -> i.inst_name) instances;
    graphs =
      [ (* SENSE: the loop drives every auditor; auditors READ the corpus. *)
        Direct
          { graph_name = "sense";
            connections =
              [ connect "auditLoop" "senseOut" "linkAuditor" "audit";
                connect "auditLoop" "senseOut" "schemaAuditor" "audit";
                connect "auditLoop" "senseOut" "graphAnalyzer" "audit";
                connect "auditLoop" "senseOut" "browserProbe" "probe";
                connect "auditLoop" "senseOut" "reconciler" "audit";
                connect "auditLoop" "senseOut" "modelGate" "audit" ] };
        (* CONTROL: gauges flow INTO the ratchet; nothing flows back to the
           corpus — the report-only law, visible as an absence. *)
        Direct
          { graph_name = "control";
            connections =
              [ connect "linkAuditor" "gaugeOut" "ratchetController" "counts";
                connect "schemaAuditor" "gaugeOut" "ratchetController" "counts";
                connect "graphAnalyzer" "gaugeOut" "ratchetController" "counts";
                connect "browserProbe" "gaugeOut" "ratchetController" "counts";
                connect "reconciler" "gaugeOut" "ratchetController" "counts";
                connect "modelGate" "gaugeOut" "ratchetController" "counts" ] };
        (* SERVE: readers hit the renderer and query engine over the corpus. *)
        Direct
          { graph_name = "serve";
            connections = [ connect "renderer" "docsOut" "corpusStore" "read";
                            connect "queryEngine" "docsOut" "corpusStore" "read" ] } ] }

let model =
  { model_name = Fpp_window_authority.declared_model_name Fpp_window_authority.Wiki;
    type_defs = [];
    port_defs =
      [ { port_name = "Ping"; params = []; return_type = None };
        { port_name = "Docs"; params = []; return_type = None };
        { port_name = "Query"; params = []; return_type = None };
        { port_name = "Audit"; params = []; return_type = None };
        { port_name = "Counts"; params = []; return_type = None };
        { port_name = "Time"; params = []; return_type = None };
        { port_name = "Rows"; params = []; return_type = None } ];
    constants = [];
    components =
      [ corpus_store; renderer; query_engine; link_auditor; schema_auditor;
        graph_analyzer; browser_probe; ratchet_controller; reconciler; backfiller;
        journal_keeper; model_gate; audit_loop ];
    machines = [ audit_machine; ratchet_machine ];
    instances;
    topologies = [ topology ] }
