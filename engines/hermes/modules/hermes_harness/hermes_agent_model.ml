open Hermes_sysml
open Sysml_types
open Sysml_vocabularies
open Sysml_grammar

(** 
    MBSE, OML, and OpenMBEE Specifications for the Hermes Agent.
    This file acts as the executable system model of the Hermes Agent itself,
    utilizing the formal fractal algebra.
*)

(* ======================================================================== *)
(* 1. OML Semantic Grounding (Ontological Vocabulary & Concepts)            *)
(* ======================================================================== *)

(** The specific vocabulary governing the Hermes Agent domain *)
let hermes_agent_vocabulary =
  harness_vocabulary 
    "http://hermes.indrajaal.io/agent/v1" 
    "hermes_agent"
    [
      Concept (Component ("AutonomousAgent", "An agent capable of executing OODA loops."));
      Concept (Component ("CognitiveCore", "The LLM reasoning engine driving the agent."));
      Concept (Component ("ToolRegistry", "The execution boundary for MCP and native tools."));
      Relation (Contains ("rel1", "The agent controls the tool registry.", "AutonomousAgent", "ToolRegistry"));
      Relation (Contains ("rel2", "The agent uses the cognitive core.", "AutonomousAgent", "CognitiveCore"));
      Property (ScalarProperty ("prop1", "The version of the underlying LLM.", "CognitiveCore", String));
      Property (ScalarProperty ("prop2", "The maximum number of concurrent subagents.", "AutonomousAgent", Integer));
    ]

(* ======================================================================== *)
(* 2. SysML v2 Structural Specification (Blocks & Parts)                    *)
(* ======================================================================== *)

(** Define the Cognitive Core component *)
let cognitive_core_part = 
  Part.create ~name:"Cognitive_Core" ~typ:"CognitiveCore" ()

(** Define the Tool Registry component *)
let tool_registry_part = 
  Part.create ~name:"Tool_Registry" ~typ:"ToolRegistry" ()

(** Define the Subagent swarm (Multiplicity example) *)
let subagent_swarm_part =
  Part.create 
    ~name:"Subagent_Swarm" 
    ~typ:"AutonomousAgent" 
    ~multiplicity:Sysml_types.Collection 
    ()

(** Define the full Hermes Agent Block (Generalization of AutonomousAgent) *)
let hermes_agent_block =
  Block.define
    ~name:"Hermes_Agent"
    ~supertypes:["AutonomousAgent"]
    ~parts:[
      cognitive_core_part;
      tool_registry_part;
      subagent_swarm_part
    ]
    ~value_properties:[
      { id = "HA_001"; name = "MaxParallelism"; property_type = Integer; multiplicity = Single };
      { id = "HA_002"; name = "ActiveStateSync"; property_type = Boolean; multiplicity = Single };
    ]
    ()

(* ======================================================================== *)
(* 3. SysML v2 Behavioral Specification (State Machine & Action Graph)      *)
(* ======================================================================== *)

(** State Machine representing the Agent's Fast OODA Loop *)
let ooda_loop_behavior =
  Behavior.state_machine
    ~states:["Observe"; "Orient"; "Decide"; "Act"; "Idle"]
    ~transitions:[
      ("Idle", "Wake", "Observe");
      ("Observe", "Contextualize", "Orient");
      ("Orient", "Plan", "Decide");
      ("Decide", "ExecuteTool", "Act");
      ("Act", "Feedback", "Observe");
      ("Act", "Complete", "Idle");
    ]

(* ======================================================================== *)
(* 4. OpenMBEE System Assembly (Connections & Flows)                        *)
(* ======================================================================== *)

(** Connect the internal parts of the Hermes Agent *)
let llm_to_tools_connection =
  Connection.connect cognitive_core_part tool_registry_part

let agent_to_swarm_connection =
  Connection.connect cognitive_core_part subagent_swarm_part

(** The final Executable System Definition *)
let hermes_agent_system_model =
  System.define
    ~name:"Hermes_Autonomous_Agent_System"
    ~parts:[
      cognitive_core_part;
      tool_registry_part;
      subagent_swarm_part
    ]
    ~connections:[
      llm_to_tools_connection;
      agent_to_swarm_connection
    ]
    ~behavior:ooda_loop_behavior
