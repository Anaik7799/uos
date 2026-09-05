(*@ open Gospel
    open Hermes_harness_fractal_ontology *)

(** MBASE Fractal Ontology for Swarm
    Defines the SysML mappings and layer configurations specifically for the 5-Agent parallel execution engine. *)

type agent_id =
  | Agent_1
  | Agent_2
  | Agent_3
  | Agent_4
  | Agent_5

(** Represents the full 7-layer fractal progression of a swarm intent execution *)
type fractal_layer =
  | L0_product
  | L1_subsystem
  | L2_component
  | L3_assembly
  | L4_part
  | L5_material
  | LX_control

(** Machine IQ (MIQ) Intelligence Services for autonomous swarm cognition *)
type intelligence_service =
  | Rete_UL      (** Expert System Rule Engine *)
  | STPA         (** System-Theoretic Process Analysis (Safety Constraints) *)
  | FEMA         (** Failure Mode and Effects Analysis *)
  | STAN         (** Bayesian Inference & Statistical Analysis *)
  | Ruliad       (** Computational Rule Space Search *)
  | Fast_OODA    (** Cybernetic OODA Loop *)
  | Control_Alg  (** Cybernetic Control Algorithms (PID, MPC) *)
  | Raven        (** Abstract Reasoning & General Intelligence (MIQ Booster) *)

(** Telemetry node linking the execution layer back to the ontology *)
type telemetry_node = {
  layer : fractal_layer;
  agent : agent_id;
  digest : string;
}

let agent_to_string = function
  | Agent_1 -> "System Architect & Initiator"
  | Agent_2 -> "Code Synthesizer"
  | Agent_3 -> "Static Analysis Specialist"
  | Agent_4 -> "Dynamic Testing & Formal Engine"
  | Agent_5 -> "Resource Auditor & Summarizer"

let layer_to_string = function
  | L0_product -> "L0: Top-level declarative intent outcome"
  | L1_subsystem -> "L1: Sub-goal DAG routing"
  | L2_component -> "L2: Agent role allocation"
  | L3_assembly -> "L3: Multi-agent interaction sequence"
  | L4_part -> "L4: OCaml 5 Domain execution step"
  | L5_material -> "L5: System service effect (Eio/Irmin)"
  | LX_control -> "LX: Autonomic Homeostasis loop"
