(* The vision system AS an FPP model.

   The repository's directive is that every capability is a modelled
   component before it is a command. This is that model for
   `hermes_vision`, and it is PROJECTED from the ontologies rather than
   written beside them — the channels come from the six stages, the
   events from their hazards, and the state machine from
   Vision_restart's transition relation. A model authored separately
   drifts from the code the day after it is written; one projected from
   the code cannot.

   Base-id window 0x4000+, disjoint from the wiki topology (0x1000+),
   the ops topology (0x2000+), the swarm bridge (0x3000+) and the
   harness (0x100..0xB00). A shared id makes two components
   indistinguishable in one telemetry stream, which is the failure this
   partitioning exists to prevent. *)

val instance_base : int

(* One channel per pipeline stage, carrying that stage's verdict, plus
   the aggregate counts a dashboard needs. Every metric this system
   reports must appear here: a metric with no channel is a number
   nothing can receive. *)
val stage_channels : Fpp_model.channel list

(* One WARNING event per stage hazard, so a hazard that fires is
   announced rather than merely counted. Derived from
   Vision_ontology.hazard, so a new stage cannot be added without its
   event. *)
val hazard_events : Fpp_model.event list

(* The restart lifecycle, as an FPP state machine projected from
   Vision_restart.legal_transition. [machine_agrees] checks the
   projection mechanically, so the model and the executable cannot
   disagree. *)
val restart_machine : Fpp_model.state_machine
val machine_agrees : unit -> bool

(* The pipeline component: a producer with commands, because unlike the
   ops verifier this one ACTS on the world. *)
val pipeline_component : Fpp_model.component

(* The control component: the Zenoh queryable surface. Separate from the
   pipeline because it has a different failure posture — the pipeline is
   fail-open, the control plane fail-closed — and merging them would
   hide that. *)
val control_component : Fpp_model.component

val components : Fpp_model.component list

(* Every channel name the model declares. A telemetry emitter must only
   name one of these; Vision_telemetry's keys are checked against it. *)
val declared_channels : unit -> string list

(* Channels declared here that no stage would ever emit, and stages whose
   channel is missing. Both empty is the law. *)
val channel_drift : unit -> string list

val render : unit -> string
