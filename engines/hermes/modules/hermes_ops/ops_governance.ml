type domain =
  | Authority | Prompting | Surfaces | Fractal | Fast_ooda
  | Sysml | Oml | Openmbee | Fpp | Formal
  | Safety | Reliability | Security | Provenance | Supply_chain
  | Lifecycle | Evidence | Observability | Metrics | Performance
  | Recovery | Data_governance | Human_control | Publication

type obligation = {
  id : string;
  domain : domain;
  title : string;
  guidance : string;
  command : string;
  declaration_id : string;
  plane : Ops_capability.plane;
  path : Ops_capability.coordinate list;
  required_evidence : Ops_capability.evidence list;
  gates : string list;
  metric : string;
  completion_criterion : string;
}

type sop_step = {
  step_id : string;
  phase : Ops_capability.ooda_phase;
  title : string;
  command : string;
  dependencies : string list;
  completion_criterion : string;
}

let string_of_domain = function
  | Authority -> "Executable authority"
  | Prompting -> "Prompt and acceptance contract"
  | Surfaces -> "Four native command surfaces"
  | Fractal -> "Fractal ontology, atlas, and algebra"
  | Fast_ooda -> "Causal Fast OODA"
  | Sysml -> "SysML v2"
  | Oml -> "OML and OWL"
  | Openmbee -> "OpenMBEE MMS"
  | Fpp -> "FPP architecture"
  | Formal -> "Formal verification"
  | Safety -> "STPA, UCA, and FMEA safety"
  | Reliability -> "Reliability and failure envelopes"
  | Security -> "Zero-trust security"
  | Provenance -> "Source and evidence provenance"
  | Supply_chain -> "Supply-chain and licensing"
  | Lifecycle -> "Lifecycle and exact-head currency"
  | Evidence -> "Evidence and parity admission"
  | Observability -> "Structured logging and observability"
  | Metrics -> "Metrics and FPP channels"
  | Performance -> "Performance, scale, and resources"
  | Recovery -> "Replay, rollback, and disaster recovery"
  | Data_governance -> "Data governance and privacy"
  | Human_control -> "Human authority and approval"
  | Publication -> "Publication and durable history"

let c level phase = Ops_capability.{ level; phase }

let item ~id ~domain ~title ~guidance ~declaration_id ~plane ~path
    ~required_evidence ~gates ~metric ~completion_criterion =
  { id; domain; title; guidance;
    command = "ops governance check --obligation " ^ id;
    declaration_id; plane; path; required_evidence; gates; metric;
    completion_criterion }

let obligations =
  let open Ops_capability in
  [ item ~id:"GOV-01" ~domain:Authority ~title:"OCaml is executable authority"
      ~guidance:"Declare every mechanizable rule, skill, superpower, agent, capability, SOP, and activity in typed OCaml; judgment-only prose grants no executable credit."
      ~declaration_id:"capability.governance-check" ~plane:Control_plane
      ~path:[ c L0 Observe; c L1 Orient ] ~required_evidence:[ Structural; Mutation ]
      ~gates:[ "test_ops_capability"; "ocaml_only_guard" ] ~metric:"governance_authority_gaps"
      ~completion_criterion:"Zero undeclared or prose-only mechanizable authorities at the current head";
    item ~id:"GOV-02" ~domain:Prompting ~title:"Typed task and acceptance envelope"
      ~guidance:"Resolve every request to objective, scope, mechanical acceptance criteria, ownership constraints, and inherited fail-closed defaults before execution."
      ~declaration_id:"capability.governance-check" ~plane:Control_plane
      ~path:[ c L0 Observe; c L1 Orient ] ~required_evidence:[ Structural ]
      ~gates:[ "test_ops_governance"; "completion preflight" ] ~metric:"prompt_contract_gaps"
      ~completion_criterion:"Every admitted run has a nonempty objective, scope, criteria, and ownership envelope";
    item ~id:"GOV-03" ~domain:Surfaces ~title:"One command, four equivalent projections"
      ~guidance:"Project the same typed request through OCaml API, CLI, MCP, and Zenoh with identical mediation, action semantics, errors, and normalized receipt identity."
      ~declaration_id:"capability.governance-check" ~plane:Control_plane
      ~path:[ c L2 Decide; c L3 Act ] ~required_evidence:[ Functional; Differential; Mutation ]
      ~gates:[ "test_ops_command"; "live MCP probe"; "live Zenoh probe" ] ~metric:"command_surface_gaps"
      ~completion_criterion:"Every required command is live and receipt-equivalent on all four native surfaces";
    item ~id:"GOV-04" ~domain:Fractal ~title:"Total ontology, atlas, and algebra"
      ~guidance:"Connect every declaration through command, surface, semantic activity or SOP, receipt, and criterion while preserving canonical fractal coordinates and RCA origins."
      ~declaration_id:"capability.governance-check" ~plane:Control_plane
      ~path:[ c L0 Observe; c L1 Orient; c L2 Decide ] ~required_evidence:[ Structural; Formal; Mutation ]
      ~gates:[ "test_ops_governance_model"; "test_formal_coverage" ] ~metric:"fractal_correspondence_gaps"
      ~completion_criterion:"Every required node has one continuous validated atlas path and all algebraic laws hold";
    item ~id:"GOV-05" ~domain:Fast_ooda ~title:"Causal Fast OODA closure"
      ~guidance:"Require Observe, Orient, Decide, Act, and a closing Observe in one bounded run; authored semantic paths replace synthetic Cartesian label coverage."
      ~declaration_id:"sop.fast-ooda-completion" ~plane:Control_plane
      ~path:[ c L0 Observe; c L1 Orient; c L2 Decide; c L3 Act; c L0 Observe ]
      ~required_evidence:[ Functional; Formal; Publication ]
      ~gates:[ "whole_system_sop"; "OODA causal law" ] ~metric:"fast_ooda_open_cycles"
      ~completion_criterion:"Every Act receipt is consumed by a fresh closing Observe within the declared budget";
    item ~id:"GOV-06" ~domain:Sysml ~title:"SysML v2 model correspondence"
      ~guidance:"Derive textual SysML v2 elements, requirements, dependencies, activities, states, ports, and verification methods from the OCaml model of record."
      ~declaration_id:"capability.mbse-sysml" ~plane:Data_plane
      ~path:[ c L3 Observe ] ~required_evidence:[ Structural; Formal ]
      ~gates:[ "test_feature_model"; "test_sysml_algebra" ] ~metric:"sysml_model_gaps"
      ~completion_criterion:"The current SysML projection is total, drift-free, and every Built requirement has a verifier";
    item ~id:"GOV-07" ~domain:Oml ~title:"OML ontology and OWL subsumption"
      ~guidance:"Project the same model into OML and OWL with stable identifiers, real subclass relations, typed properties, and no independent semantic authority."
      ~declaration_id:"capability.mbse-oml" ~plane:Data_plane
      ~path:[ c L3 Observe ] ~required_evidence:[ Structural; Formal ]
      ~gates:[ "test_feature_model"; "OML projection laws" ] ~metric:"oml_projection_gaps"
      ~completion_criterion:"OML and OWL projections are total, deterministic, drift-free, and semantically linked";
    item ~id:"GOV-08" ~domain:Openmbee ~title:"OpenMBEE MMS projection"
      ~guidance:"Emit deterministic OpenMBEE MMS elements with stable ids, ownership, dependencies, and provenance; distinguish local projection checks from live server publication."
      ~declaration_id:"capability.mbse-openmbee" ~plane:Data_plane
      ~path:[ c L3 Observe; c L3 Act ] ~required_evidence:[ Structural; Publication ]
      ~gates:[ "test_feature_model"; "MMS schema check"; "optional live MMS receipt" ] ~metric:"openmbee_projection_gaps"
      ~completion_criterion:"The MMS payload is drift-free and any claimed live publication has a current server receipt";
    item ~id:"GOV-09" ~domain:Fpp ~title:"FPP actors, topology, dictionary, and telemetry"
      ~guidance:"Model control and data actors, ports, commands, state machines, events, channels, parameters, and topology in FPP before accepting runtime surfaces."
      ~declaration_id:"capability.fpp-check" ~plane:Control_plane
      ~path:[ c L3 Observe; c L3 Orient ] ~required_evidence:[ Structural; Formal; Mutation ]
      ~gates:[ "Fpp_model.validate"; "test_fpp_bdd"; "test_fpp_fuzz" ] ~metric:"fpp_model_gaps"
      ~completion_criterion:"All FPP models validate, all emitted artifacts are current, and every metric has a channel";
    item ~id:"GOV-10" ~domain:Formal ~title:"Non-vacuous formal verification"
      ~guidance:"Check Gospel, Rocq, Quint, Lean, SMT, and algebraic obligations in staged environments; theorem negations must be Unsat with live Sat controls."
      ~declaration_id:"capability.formal-check" ~plane:Control_plane
      ~path:[ c L3 Observe; c L3 Orient ] ~required_evidence:[ Formal; Mutation ]
      ~gates:[ "ops formal"; "formal-coverage"; "non-vacuity controls" ] ~metric:"formal_open_obligations"
      ~completion_criterion:"No required formal artifact is refuted, unavailable, stale, or accepted vacuously";
    item ~id:"GOV-11" ~domain:Safety ~title:"STPA, UCA, and FMEA control"
      ~guidance:"Model unsafe control actions, hazards, losses, causal scenarios, failure modes, mitigations, residual risk, and safety ownership for each effectful path."
      ~declaration_id:"capability.governance-check" ~plane:Control_plane
      ~path:[ c L2 Orient; c L3 Decide ] ~required_evidence:[ Formal; Functional; Mutation ]
      ~gates:[ "STPA validation"; "FMEA envelope"; "hazard mutant" ] ~metric:"safety_open_hazards"
      ~completion_criterion:"Every effectful path has enforced mitigations and no unaccepted high-severity residual";
    item ~id:"GOV-12" ~domain:Reliability ~title:"Functional failure envelope"
      ~guidance:"Test timeout, cancellation, retry, replay, partial response, malformed input, dependency loss, concurrency, rollback, and clean recovery, not only happy paths."
      ~declaration_id:"capability.verify-full" ~plane:Control_plane
      ~path:[ c L4 Act; c L4 Observe ] ~required_evidence:[ Functional; Differential; Mutation ]
      ~gates:[ "hermes-functional-envelope"; "chaos suites" ] ~metric:"reliability_envelope_gaps"
      ~completion_criterion:"Every applicable failure mode has a current receipt and preserves stated invariants";
    item ~id:"GOV-13" ~domain:Security ~title:"Zero-trust command mediation"
      ~guidance:"Authenticate, authorize, mediate, fence, validate, and audit every effectful command through one front door with fail-closed denial and idempotent receipts."
      ~declaration_id:"capability.governance-check" ~plane:Control_plane
      ~path:[ c L2 Decide; c L3 Act ] ~required_evidence:[ Functional; Formal; Mutation ]
      ~gates:[ "mediation laws"; "fence replay tests"; "threat model" ] ~metric:"security_control_gaps"
      ~completion_criterion:"No command bypass exists and stale, forged, unauthorized, or replayed effects are safely rejected";
    item ~id:"GOV-14" ~domain:Provenance ~title:"Authority and receipt provenance"
      ~guidance:"Bind source authority, revision, configuration, tool version, attempt identity, evidence digest, and verifier to every model, command, proof, and completion receipt."
      ~declaration_id:"capability.governance-check" ~plane:Data_plane
      ~path:[ c L0 Observe; c L4 Observe ] ~required_evidence:[ Structural; Publication ]
      ~gates:[ "authority manifest"; "exact-head gate" ] ~metric:"provenance_gaps"
      ~completion_criterion:"Every admitted artifact and receipt resolves to immutable current authority and digest metadata";
    item ~id:"GOV-15" ~domain:Supply_chain ~title:"Supply-chain, SBOM, and licensing"
      ~guidance:"Record dependencies, pins, source digests, licenses, semantic-credit boundaries, vulnerabilities, toolchain closure, and reproducible acquisition state."
      ~declaration_id:"capability.governance-check" ~plane:Data_plane
      ~path:[ c L0 Observe; c L3 Orient ] ~required_evidence:[ Structural; Resource ]
      ~gates:[ "toolchain_check"; "authority lock"; "license policy" ] ~metric:"supply_chain_gaps"
      ~completion_criterion:"Every production dependency has current provenance, license posture, digest, and reproducible build evidence";
    item ~id:"GOV-16" ~domain:Lifecycle ~title:"Declared, implemented, executed, current"
      ~guidance:"Keep the four lifecycle states distinct and admit Current only for this run, source head, configuration digest, scope, dependencies, and verifier version."
      ~declaration_id:"capability.governance-check" ~plane:Control_plane
      ~path:[ c L0 Observe; c L1 Orient ] ~required_evidence:[ Structural; Publication ]
      ~gates:[ "completion history"; "exact-head admission" ] ~metric:"lifecycle_noncurrent_items"
      ~completion_criterion:"Every mandatory atomic activity and SOP is Current in the same admitted run";
    item ~id:"GOV-17" ~domain:Evidence ~title:"Evidence and parity admission"
      ~guidance:"Accept parity only from L4-L6 differential receipts; missing or control evidence blocks credit, and only Implementation-origin divergence may deny it."
      ~declaration_id:"capability.governance-check" ~plane:Data_plane
      ~path:[ c L4 Observe; c L5 Orient; c L6 Observe ] ~required_evidence:[ Differential; Formal ]
      ~gates:[ "parity algebra"; "evidence rollup" ] ~metric:"parity_evidence_gaps"
      ~completion_criterion:"Every required family has current accepted L4-L6 differential evidence without provenance gaps";
    item ~id:"GOV-18" ~domain:Observability ~title:"Run-scoped structured observability"
      ~guidance:"Log run, request, source, configuration, plane, surface, fractal, OODA, RCA, mediation, resource, duration, verdict, and receipt identities as typed attributes."
      ~declaration_id:"capability.metrics-observe" ~plane:Data_plane
      ~path:[ c LX Observe ] ~required_evidence:[ Functional; Publication ]
      ~gates:[ "OTLP attribute schema"; "trace correlation test" ] ~metric:"observability_attribute_gaps"
      ~completion_criterion:"Every command and SOP step is trace-correlated end to end with no required attribute missing";
    item ~id:"GOV-19" ~domain:Metrics ~title:"Typed metrics with modeled homes"
      ~guidance:"Define name, unit, type, source, aggregation, objective, owner, cardinality, and FPP channel for every reported numeric metric; reject fabricated measurements."
      ~declaration_id:"capability.metrics-observe" ~plane:Data_plane
      ~path:[ c LX Observe; c LX Orient ] ~required_evidence:[ Structural; Functional ]
      ~gates:[ "metric registry"; "FPP channel census" ] ~metric:"metric_definition_gaps"
      ~completion_criterion:"Every emitted metric has a unique typed definition, live source, modeled channel, and objective";
    item ~id:"GOV-20" ~domain:Performance ~title:"Performance, scalability, and resources"
      ~guidance:"Measure bounded latency, throughput, memory, CPU, disk, concurrency, growth ratios, saturation, and resource preflight under representative and adversarial loads."
      ~declaration_id:"capability.verify-full" ~plane:Control_plane
      ~path:[ c L4 Act; c L4 Observe ] ~required_evidence:[ Functional; Resource; Mutation ]
      ~gates:[ "resource envelope"; "performance suite"; "stress suite" ] ~metric:"performance_slo_breaches"
      ~completion_criterion:"All declared budgets and scaling laws hold under the required current load profiles";
    item ~id:"GOV-21" ~domain:Recovery ~title:"Replay, rollback, and disaster recovery"
      ~guidance:"Prove deterministic replay, checkpoint integrity, idempotent recovery, rollback safety, backup restoration, and bounded recovery time without rewriting evidence history."
      ~declaration_id:"capability.governance-check" ~plane:Control_plane
      ~path:[ c L3 Act; c L4 Observe ] ~required_evidence:[ Functional; Formal; Resource ]
      ~gates:[ "replay verification"; "restore drill"; "rollback law" ] ~metric:"recovery_open_failures"
      ~completion_criterion:"Current restore and replay drills meet RPO and RTO while preserving evidence invariants";
    item ~id:"GOV-22" ~domain:Data_governance ~title:"Data classification, retention, and privacy"
      ~guidance:"Classify data, secrets, credentials, prompts, histories, receipts, and telemetry; enforce minimization, retention, access, redaction, residency, and deletion policy."
      ~declaration_id:"capability.governance-check" ~plane:Data_plane
      ~path:[ c L0 Observe; c L3 Act ] ~required_evidence:[ Structural; Functional ]
      ~gates:[ "data classification census"; "secret scan"; "retention test" ] ~metric:"data_governance_gaps"
      ~completion_criterion:"Every persisted or transmitted field has an enforced classification and lifecycle policy";
    item ~id:"GOV-23" ~domain:Human_control ~title:"Explicit human authority and forks"
      ~guidance:"Represent approvals, policy forks, risk acceptance, ownership transfers, and irreducible judgment as typed predicates that remain blocking until the named authority decides."
      ~declaration_id:"capability.governance-check" ~plane:Control_plane
      ~path:[ c L1 Orient; c L2 Decide ] ~required_evidence:[ Structural; Publication ]
      ~gates:[ "policy fork registry"; "approval receipt" ] ~metric:"human_decision_blockers"
      ~completion_criterion:"No unresolved mandatory fork, ownership conflict, or approval predicate is hidden or auto-waived";
    item ~id:"GOV-24" ~domain:Publication ~title:"Append-only journal and completion history"
      ~guidance:"Persist prompts, actions, decisions, agent interactions, commands, full failure output, receipts, digests, residuals, and publication paths without rewriting prior observations."
      ~declaration_id:"capability.history-observe" ~plane:Data_plane
      ~path:[ c L0 Observe; c L3 Act; c L0 Observe ] ~required_evidence:[ Publication; Structural ]
      ~gates:[ "journal audit"; "completion history schema"; "publication check" ] ~metric:"publication_history_gaps"
      ~completion_criterion:"The current run has a complete append-only journal and durable queryable receipt history" ]

let whole_system_sop =
  let open Ops_capability in
  [ { step_id = "observe-inventory"; phase = Observe;
      title = "Inventory exact-head authority, scope, owners, resources, and receipts";
      command = "ops completion inventory --scope whole-system --request-id RUN_ID"; dependencies = [];
      completion_criterion = "A current nonempty denominator and preflight receipt exist" };
    { step_id = "orient-gaps"; phase = Orient;
      title = "Classify every gap by coordinate, canonical RCA, risk, and owner";
      command = "ops completion plan --scope whole-system --request-id RUN_ID";
      dependencies = [ "observe-inventory" ];
      completion_criterion = "Every incomplete obligation has one typed diagnosis and disposition" };
    { step_id = "decide-intent"; phase = Decide;
      title = "Compile admitted work into one real declarative execution intent";
      command = "ops completion decide --scope whole-system --request-id RUN_ID";
      dependencies = [ "orient-gaps" ];
      completion_criterion = "The intent preserves dependencies, constraints, capabilities, and success criteria" };
    { step_id = "act-sop"; phase = Act;
      title = "Execute real action closures through Sop_execution and record receipts";
      command = "ops completion act --scope whole-system --request-id RUN_ID";
      dependencies = [ "decide-intent" ];
      completion_criterion = "Every scheduled action terminates with an immutable success or failure receipt" };
    { step_id = "observe-close"; phase = Observe;
      title = "Re-observe exact head, admit current receipts, and publish residuals";
      command = "ops completion check --scope whole-system --request-id RUN_ID";
      dependencies = [ "act-sop" ];
      completion_criterion = "All mandatory obligations are Current or the exact blockers are published" } ]

let all_domains =
  [ Authority; Prompting; Surfaces; Fractal; Fast_ooda; Sysml; Oml; Openmbee;
    Fpp; Formal; Safety; Reliability; Security; Provenance; Supply_chain;
    Lifecycle; Evidence; Observability; Metrics; Performance; Recovery;
    Data_governance; Human_control; Publication ]

let valid_metric metric =
  metric <> "" && String.for_all
    (fun ch -> (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch = '_')
    metric

let validate () =
  let errors = ref [] in
  let add text = errors := text :: !errors in
  let ids = List.map (fun item -> item.id) obligations in
  if obligations = [] then add "governance registry is empty";
  if List.length ids <> List.length (List.sort_uniq compare ids) then add "duplicate obligation id";
  List.iter
    (fun domain ->
      if not (List.exists (fun item -> item.domain = domain) obligations) then
        add ("missing domain: " ^ string_of_domain domain))
    all_domains;
  let declaration_ids = List.map (fun (d : Ops_capability.declaration) -> d.id) Ops_capability.all in
  List.iter
    (fun item ->
      if item.path = [] then add (item.id ^ ": empty semantic path");
      if item.required_evidence = [] then add (item.id ^ ": no required evidence");
      if item.gates = [] then add (item.id ^ ": no gate");
      if not (List.mem item.declaration_id declaration_ids) then
        add (item.id ^ ": unknown declaration " ^ item.declaration_id);
      if not (valid_metric item.metric) then add (item.id ^ ": invalid metric");
      if String.length item.guidance < 40 || String.length item.completion_criterion < 24 then
        add (item.id ^ ": guidance or criterion is not substantive"))
    obligations;
  let metrics = List.map (fun item -> item.metric) obligations in
  if List.length metrics <> List.length (List.sort_uniq compare metrics) then add "duplicate metric";
  if List.map (fun step -> step.phase) whole_system_sop
     <> Ops_capability.[ Observe; Orient; Decide; Act; Observe ]
  then add "whole-system SOP is not causal Fast OODA";
  let rec dependencies = function
    | [] | [ _ ] -> ()
    | left :: (right :: _ as rest) ->
        if not (List.mem left.step_id right.dependencies) then
          add (right.step_id ^ ": missing predecessor dependency");
        dependencies rest
  in
  dependencies whole_system_sop;
  List.rev !errors

let evidence_name = function
  | Ops_capability.Structural -> "structural"
  | Functional -> "functional" | Differential -> "differential"
  | Formal -> "formal" | Mutation -> "mutation" | Resource -> "resource"
  | Publication -> "publication"

let path_text path =
  path |> List.map (fun (c : Ops_capability.coordinate) ->
      Ops_capability.string_of_level c.level ^ "/" ^ Ops_capability.string_of_phase c.phase)
  |> String.concat " → "

let prompt_template =
  "Execute as a whole-system declarative-intent task under AGENTS.md and R1-R29.\n\
   Objective: <observable outcome>\n\
   Scope: <systems, modules, paths, control/data planes>\n\
   Acceptance: <exact mechanical gates and required receipts>\n\
   Constraints/owners: <boundaries, exclusions, approval points>"

let render_guidance () =
  let b = Buffer.create 32768 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  p "---\nid: hermes-whole-system-executable-governance-checklist\n";
  p "title: Whole-system executable governance checklist and guidance\n";
  p "date: 2026-08-10\nstatus: generated\n---\n\n";
  p "# Whole-system executable governance checklist and guidance\n\n";
  p "> GENERATED from `Ops_governance`; do not hand-edit. Regenerate with `ops governance --write-guidance` and verify with `ops governance --check-guidance`.\n\n";
  p "The typed sources of authority are `Ops_capability`, `Ops_command`, and `Ops_governance`. This document is the human and native-agent projection. A checked box is not evidence; only a current admitted receipt satisfies an item.\n\n";
  p "## What to write in every prompt\n\nUse the following compact envelope. The repository rules supply the rest.\n\n```text\n%s\n```\n\n" prompt_template;
  p "The inherited defaults require typed OCaml authority, real `Sop_execution`, all applicable native surfaces, MBSE/FPP correspondence, formal/safety/security/resource gates, run-scoped observability, append-only history, and exact residuals.\n\n";
  p "## Command surfaces\n\n";
  p "- OCaml API: `Ops_command.dispatch` with `Ops_command_runtime.execute`.\n";
  p "- CLI: `ops completion ACTION --scope SCOPE --request-id ID`.\n";
  p "- MCP: tool `hermes_completion` with the same request fields.\n";
  p "- Zenoh: `hermes/{control|data}/completion/ACTION` with the same JSON payload.\n\n";
  p "An adapter that is not live remains a blocker. Transport success never substitutes for command admission or completion.\n\n";
  p "## Comprehensive checklist\n\n";
  List.iter
    (fun item ->
      p "### - [ ] %s — %s\n\n" item.id item.title;
      p "- Domain: %s\n" (string_of_domain item.domain);
      p "- Plane: %s\n" (Ops_capability.string_of_plane item.plane);
      p "- Semantic path: %s\n" (path_text item.path);
      p "- Declarative command: `%s`\n" item.command;
      p "- Authority declaration: `%s`\n" item.declaration_id;
      p "- Required evidence: %s\n" (String.concat ", " (List.map evidence_name item.required_evidence));
      p "- Gates: %s\n" (String.concat "; " item.gates);
      p "- Metric/FPP channel: `%s`\n" item.metric;
      p "- Guidance: %s\n" item.guidance;
      p "- Complete only when: %s.\n\n" item.completion_criterion)
    obligations;
  p "## Whole-system Fast OODA SOP\n\n";
  List.iteri
    (fun index step ->
      p "%d. **%s — %s.** `%s`\n\n" (index + 1)
        (Ops_capability.string_of_phase step.phase) step.title step.command;
      p "   Dependencies: %s. Completion: %s.\n\n"
        (if step.dependencies = [] then "none" else String.concat ", " step.dependencies)
        step.completion_criterion)
    whole_system_sop;
  p "## Admission and reporting rules\n\n";
  p "- `Verified`: current mechanical receipt at the exact source/configuration head.\n";
  p "- `Partial`: some required obligations lack current admissible receipts.\n";
  p "- `Unavailable_observed`: an oracle or resource was observed unavailable; it blocks mandatory completion and never passes.\n";
  p "- Only Implementation-origin L4-L6 differential divergence may deny parity; only accepted L4-L6 differential receipts may grant it.\n";
  p "- Preserve full failures, real exit codes, ownership boundaries, and all policy forks.\n";
  Buffer.contents b

let guidance_path = "docs/hermes/whole-system-executable-governance-checklist.md"

let write_guidance () =
  let temp = guidance_path ^ ".tmp" in
  let channel = open_out_bin temp in
  Fun.protect ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel (render_guidance ()));
  Sys.rename temp guidance_path

let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let check_guidance () =
  if not (Sys.file_exists guidance_path) then Error ("missing generated guidance: " ^ guidance_path)
  else if read_file guidance_path = render_guidance () then Ok ()
  else Error ("generated guidance drift: " ^ guidance_path)

let find_obligation id = List.find_opt (fun item -> item.id = id) obligations

let render_obligation item =
  Printf.sprintf
    "obligation=%s\ndomain=%s\nplane=%s\npath=%s\ncommand=%s\nmetric=%s\nstatus=declared\ncurrent=false\ncriterion=%s\n"
    item.id (string_of_domain item.domain) (Ops_capability.string_of_plane item.plane)
    (path_text item.path) item.command item.metric item.completion_criterion
