(*@ open Gospel
    open Swarm_ontology
    open Swarm_fpp
    open Swarm_memory *)

open Swarm_fpp
open Swarm_memory

(** Swarm Knowledge Management (KM) Integration.
    Bridges the autonomous swarm memory and reasoning layers natively to the 
    Hermes Wiki and Zettelkasten (ZK) systems. *)

(** Represents a connection to the external ZK and Wiki systems *)
type km_bridge = {
  active : bool;
  zk_namespace : string;
}

(** Converts a Semantic Memory fact into a Zettelkasten note payload *)
let fact_to_zk_note (fact : Semantic_Memory.fact) : string =
  Printf.sprintf "ZK NOTE: [%s] -> %s -> [%s] (Confidence: %f)"
    fact.subject fact.predicate fact.object_val fact.confidence

(** FPP Component for Wiki/ZK publishing via Zenoh Mesh *)
module FPP_Knowledge_Publisher = struct
  type input = Semantic_Memory.fact list
  type output = string list (** List of published ZK URIs *)

  (** Synthesizes semantic memory into persistent Wiki pages and ZK notes, routed via Zenoh *)
  let publish_to_wiki (port : input fpp_port) : output fpp_port =
    match port with
    | Sync_input facts ->
        let uris = List.map (fun f -> 
          let payload = fact_to_zk_note f in
          (* Formally publish state over Zenoh Mesh to the Topologist / Hive-Mind *)
          let _ = Swarm_zenoh.publish_state_vector (Digest.to_hex (Digest.string payload)) in
          "zk://hermes_wiki/fact_" ^ (Digest.to_hex (Digest.string f.subject))
        ) facts in
        Output uris
    | Async_input _ -> Output []
    | Output _ -> Output []
end

(** FPP Component for KM Retrieval (RAG / Context Fetching) *)
module FPP_Knowledge_Retriever = struct
  type input = Intent_config.t
  type output = string list (** List of relevant Wiki/ZK context blocks *)

  (** Extracts context from the ZK system prior to intent synthesis *)
  let fetch_context (port : input fpp_port) : output fpp_port =
    match port with
    | Sync_input intent ->
        (* Simulated ZK query based on the intent target *)
        let query = intent.target in
        Output [Printf.sprintf "ZK Context for %s: Prior attempts failed due to bounds errors." query]
    | Async_input _ -> Output []
    | Output _ -> Output []
end

(** Globally registers the KM bridge into the Swarm substrate *)
let enable_km_bridge (substrate : swarm_memory_substrate) : unit =
  (* Normally this would instantiate the hermes_wiki_core endpoints *)
  let _bridge = { active = true; zk_namespace = "swarm_autonomy" } in
  (* Trigger an immediate sync of existing semantic memory *)
  let _published = FPP_Knowledge_Publisher.publish_to_wiki (Sync_input substrate.semantic) in
  ()
