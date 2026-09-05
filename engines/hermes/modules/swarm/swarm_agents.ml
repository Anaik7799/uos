(*@ open Gospel
    open Swarm_ontology *)
open Swarm_ontology

(** Core Council (Static: 15 Agents - Maximum CPS Topology) *)
type core_role =
  | Synthesizer
  | Cybernetic_Navigator
  | Knowledge_Conservator
  | Bayesian_Critic
  | Neural_Weaver
  | Conductor
  | Topologist
  | Sensorium
  | Byzantine_Sentinel
  | Chrono_Arbiter
  | Cryptographic_Sentinel
  | Quantum_Arbiter
  | Kinematic_Weaver
  | Fluidic_Controller
  | Swarm_Hive_Mind

type agent_identity = {
  id : string;
  role : core_role;
  capabilities : fractal_layer list;
}

(** 15-Agent Core Matrix Definition *)
let agent_1 = { id = "Synthesizer"; role = Synthesizer; capabilities = [L0_product; L1_subsystem] }
let agent_2 = { id = "Cybernetic_Navigator"; role = Cybernetic_Navigator; capabilities = [LX_control; L4_part] }
let agent_3 = { id = "Knowledge_Conservator"; role = Knowledge_Conservator; capabilities = [L1_subsystem; L2_component] }
let agent_4 = { id = "Bayesian_Critic"; role = Bayesian_Critic; capabilities = [L2_component; LX_control] }
let agent_5 = { id = "Neural_Weaver"; role = Neural_Weaver; capabilities = [L0_product; L4_part] }
let agent_6 = { id = "Conductor"; role = Conductor; capabilities = [L3_assembly; L5_material] }
let agent_7 = { id = "Topologist"; role = Topologist; capabilities = [L5_material; LX_control] }
let agent_8 = { id = "Sensorium"; role = Sensorium; capabilities = [L1_subsystem; L5_material] }
let agent_9 = { id = "Byzantine_Sentinel"; role = Byzantine_Sentinel; capabilities = [L2_component; LX_control] }
let agent_10 = { id = "Chrono_Arbiter"; role = Chrono_Arbiter; capabilities = [L3_assembly; LX_control] }
let agent_11 = { id = "Cryptographic_Sentinel"; role = Cryptographic_Sentinel; capabilities = [L2_component; L5_material] }
let agent_12 = { id = "Quantum_Arbiter"; role = Quantum_Arbiter; capabilities = [LX_control] }
let agent_13 = { id = "Kinematic_Weaver"; role = Kinematic_Weaver; capabilities = [L0_product; L5_material] }
let agent_14 = { id = "Fluidic_Controller"; role = Fluidic_Controller; capabilities = [L4_part; L5_material] }
let agent_15 = { id = "Swarm_Hive_Mind"; role = Swarm_Hive_Mind; capabilities = [L1_subsystem; L3_assembly] }

(** Elastic Fabric and Fractal Satellites *)
type elastic_role =
  | Worker_Executor of int
  | Formal_Sentinel

type elastic_agent = {
  e_id : string;
  e_role : elastic_role;
  active_nodes : string list;
}

(** Spawns N Worker Executors for a DAG step width *)
let summon_executors (width : int) : elastic_agent list =
  List.init width (fun i -> { e_id = Printf.sprintf "Executor_%d" i; e_role = Worker_Executor i; active_nodes = [] })

(** Spawns a Domain Expert (e.g., Formal Sentinel) *)
let summon_sentinel (node : string) : elastic_agent =
  { e_id = "Formal_Sentinel_" ^ node; e_role = Formal_Sentinel; active_nodes = [node] }
