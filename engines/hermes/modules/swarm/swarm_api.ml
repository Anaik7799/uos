open Intent_config

(** Pure OCaml Combinator API for Swarm Declarative Intents 
    This provides a fluent builder surface for programmatic swarm execution without relying on YAML/JSON. *)

(** Creates a base intent targeting a specific goal *)
let make_intent (target : string) : t =
  {
    target;
    constraints = [];
    capabilities = [];
    success_criteria = [];
    miq_routing = [];
  }

(** Adds an execution constraint (e.g., parallelism level, integrity mode) *)
let with_constraint (key : string) (value : string) (intent : t) : t =
  { intent with constraints = (key, value) :: intent.constraints }

(** Adds a required capability to the swarm's DAG synthesizer *)
let requiring_capability (cap : string) (intent : t) : t =
  { intent with capabilities = cap :: intent.capabilities }

(** Adds an objective success criterion that the Victory Auditor will evaluate *)
let requiring_success_criterion (criterion : string) (intent : t) : t =
  { intent with success_criteria = criterion :: intent.success_criteria }

(** Combines multiple intents into a unified intent goal *)
let merge_intents (primary : t) (secondary : t) : t =
  {
    target = primary.target ^ " AND " ^ secondary.target;
    constraints = primary.constraints @ secondary.constraints;
    capabilities = primary.capabilities @ secondary.capabilities;
    success_criteria = primary.success_criteria @ secondary.success_criteria;
    miq_routing = primary.miq_routing @ secondary.miq_routing;
  }

(** Routes the intent through a specific intelligence service to boost MIQ *)
let requiring_intelligence (service : Swarm_ontology.intelligence_service) (intent : t) : t =
  { intent with miq_routing = service :: intent.miq_routing }

(** 
   Example Usage:
   
   let my_intent = 
     make_intent "Refactor database schema"
     |> with_constraint "parallelism" "max"
     |> with_constraint "integrity" "benchmark"
     |> requiring_capability "database_design"
     |> requiring_success_criterion "0 dune test failures"
     |> requiring_intelligence Fast_OODA
     |> requiring_intelligence Raven
     
   let dag = Intent_config.synthesize_dag my_intent
*)
