type poodavr_phase =
  | Predict
  | Observe
  | Orient
  | Decide
  | Act
  | Verify
  | Reflect
  | ConstitutionalHalt

let phase_to_string = function
  | Predict -> "Predict"
  | Observe -> "Observe"
  | Orient -> "Orient"
  | Decide -> "Decide"
  | Act -> "Act"
  | Verify -> "Verify"
  | Reflect -> "Reflect"
  | ConstitutionalHalt -> "ConstitutionalHalt"

let hard_denied_system_os_serial = "25503L801736"

type poodavr_intent = {
  intent_id : string;
  target_disk : string;
  is_ledgered_in_sa_plan : bool;
  health_ppm : int;
}

type poodavr_state = {
  phase : poodavr_phase;
  causal_epoch : int;
  halt_code : int option;
  receipt_sha256 : string option;
}

let is_safe_intent (intent : poodavr_intent) : bool =
  intent.target_disk <> hard_denied_system_os_serial
  && intent.is_ledgered_in_sa_plan
  && intent.health_ppm >= 850000

let orient_step (intent : poodavr_intent) (st : poodavr_state) : poodavr_state =
  if is_safe_intent intent then
    { st with phase = Decide }
  else
    { st with phase = ConstitutionalHalt; halt_code = Some (-32002) }

let verify_step (ok : bool) (st : poodavr_state) : poodavr_state =
  if ok then
    { st with phase = Reflect; causal_epoch = st.causal_epoch + 1 }
  else
    { st with phase = ConstitutionalHalt; halt_code = Some (-32003) }

type aspect_status = AspectActive | AspectDegraded | AspectHalted

type aspect_entry = {
  id : int;
  name : string;
  domain : string;
  authority : string;
  status : aspect_status;
  description : string;
}

let all_17_aspects () : aspect_entry list = [
  { id = 1; name = "Substrate & Hardware Safety"; domain = "Infrastructure"; authority = "Rust spec.rs"; status = AspectActive; description = "OS NVMe 25503L801736 lock" };
  { id = 2; name = "Standalone Jujutsu Monorepo"; domain = "Version Control"; authority = "Jujutsu .jj/"; status = AspectActive; description = "Pure standalone Jujutsu without Git mutations" };
  { id = 3; name = "Zero-Muda Purity"; domain = "Governance"; authority = "SC-MUDA-001"; status = AspectActive; description = "0 Bevy, 0 Graphite, 0 foreign NIF shared libs" };
  { id = 4; name = "Gleam/OTP Supervision & Actors"; domain = "Supervision"; authority = "uos_sup.gleam"; status = AspectActive; description = "4-domain supervisor, Prajna breakers" };
  { id = 5; name = "Deterministic Runtime Engine"; domain = "Kernel"; authority = "ZigVM & VFS"; status = AspectActive; description = "Descriptor-relative VFS (8/8 laws)" };
  { id = 6; name = "Formal Evidence & Analysis"; domain = "Evidence Plane"; authority = "Hermes OCaml & Gospel"; status = AspectActive; description = "Gospel contracts, Z3, SQLite WAL" };
  { id = 7; name = "Mathematical Authority"; domain = "Formal Proof"; authority = "Lean 4 & Quint"; status = AspectActive; description = "13D Traceability conservation" };
  { id = 8; name = "Biosemiotic Cybernetics"; domain = "Control Theory"; authority = "Rocha Semiotics"; status = AspectActive; description = "Decoupled semiotic cut, feedback loops" };
  { id = 9; name = "Quarantined AI Inference"; domain = "Inference Tier"; authority = "Modular MAX / Mojo"; status = AspectActive; description = "Supervised Python daemon over stdio" };
  { id = 10; name = "Mesh Telemetry & Communication"; domain = "Network Plane"; authority = "Zenoh pub/sub"; status = AspectActive; description = "OoZ and MoZ fractal backplane" };
  { id = 11; name = "Agent Event Bus Protocol"; domain = "Agent Plane"; authority = "AG-UI 32-Event Spec"; status = AspectActive; description = "Lifecycle, Text, Tool, State events" };
  { id = 12; name = "Declarative UI Component Catalog"; domain = "Presentation"; authority = "A2UI Catalog"; status = AspectActive; description = "233 verified JSON component specs" };
  { id = 13; name = "Multi-Interface Accessibility"; domain = "Interface Tier"; authority = "Penta-Stack UI"; status = AspectActive; description = "Lustre Web, Wisp REST, ANSI TUI" };
  { id = 14; name = "Universal Tailscale FQDN Web Navigation"; domain = "Network Routing"; authority = "Tailscale FQDN"; status = AspectActive; description = "Direct clickable links on port 4100" };
  { id = 15; name = "Comprehensive Verification Checklist"; domain = "Quality Assurance"; authority = "SC-CHECKLIST-001"; status = AspectActive; description = "5 Domains, 18 Checkpoints 100% green" };
  { id = 16; name = "Knowledge Management Triad"; domain = "Knowledge Plane"; authority = "KM Triad"; status = AspectActive; description = "Wiki, ZK (ADR-001..047), Ontology" };
  { id = 17; name = "Sa-Plan Durable Execution & Workflow Engine"; domain = "Execution Plane"; authority = "Sa-Plan Bridge"; status = AspectActive; description = "12 Suites, Oban jobs, Temporal recovery" };
]

let verify_aspect_coverage (aspects : aspect_entry list) : bool =
  List.length aspects = 17 && List.for_all (fun a -> a.status = AspectActive) aspects
