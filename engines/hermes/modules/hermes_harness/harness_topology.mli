(* The Hermes harness described AS an F Prime topology, in the FPP metamodel
   (fpp_model.mli). The description is data: eleven real components as FPP
   component instances, their real dataflow as connection graphs, the
   converge loop as an FPP state machine, the two lattices as FPP enums.

   The differential law: this encoding and the fractal ontology describe the
   same system, so (1) every instance's component must be registered in
   Fractal_ontology, and (2) every DIRECT connection must lie over an
   ontology edge (either direction, any relation). Pattern graphs are
   framework plumbing (time/health/telemetry/event fan-out) and are governed
   by the FPP checks instead. A gap in either direction means one encoding
   is wrong — found live once already: the parity_compare -> evidence_store
   receipt flow had no ontology edge until this law demanded it. *)

val model : Fpp_model.model
val topology : Fpp_model.topology

(* Fpp_model.validate over the real model. [] = the harness description is
   FPP-well-formed (opcode/id dictionaries, base-id ranges, connection
   types, the passive/async law, the state machine laws). *)
val validate : unit -> Fractal_diagnostic.t list

(* The direct (non-pattern) connections of the topology. *)
val direct_connections : unit -> Fpp_model.connection list

(* The differential law. [] = the two encodings agree. *)
val ontology_gaps : unit -> string list

(* Look up component for instance name *)
val component_of_instance : string -> string

(* The law's two halves, exposed so tests can prove the law CAN fail. *)
val gaps_for_instances : Fpp_model.instance list -> string list
val gaps_for_connections : Fpp_model.connection list -> string list

(* Atlas artifacts. *)
val to_fpp : unit -> string
val dictionary : unit -> (Yojson.Safe.t, string) result
