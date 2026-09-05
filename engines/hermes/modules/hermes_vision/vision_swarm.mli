(* Vision stage requests, prepared and nothing more.

   This module used to execute. It built a step per ontology stage, gave
   each one an action that ran a real probe, and called
   [Sop_execution.execute_sop_workflow] — the sole unauthorized direct
   engine call in the repository, and the one the swarm scanner named at
   21/22.

   It was removed rather than grandfathered. The scheduler it called can
   order ready steps and join Domains, but it proves no authorization, no
   current intent, no safety or formal admission, no effect idempotency
   and no durable terminal. Dispatching through it is the
   provided-unsafely control action (FM-T7-09, RPN 60, critical): a call
   made before the authorities that would make it safe exist.

   What remains is preparation. This module validates a stage declaration
   and derives the request carrier a future admitted bridge may wrap. It
   owns no scheduler, process, effect, telemetry transport or verdict,
   and it cannot claim execution, durability or parity.

   -------------------------------------------------------------------
   THE DAG IS STILL DERIVED, NOT DECLARED

   Request identity and edges come from [Vision_ontology.stages] in its
   canonical order — each stage depends on exactly the stage before it,
   and [Source] on nothing. A stage added to the ontology joins with its
   edge already correct, and a caller that reorders, omits or duplicates
   the declaration is rejected rather than quietly prepared.

   -------------------------------------------------------------------
   NO SUBSTITUTE SUCCESS

   There is deliberately no [execute], not even one returning a fake run.
   A compatibility front door with an execution-shaped signature and no
   admission authority behind it is the failure this removal exists to
   prevent. Execution is [Unavailable_observed] until the canonical
   bridge lands, and that status is a first-class value rather than an
   exception or an empty success. *)

type stage_request = private {
  stage : Vision_ontology.stage;
  request_id : string;          (* VISION- plus the uppercased stage name *)
  dependencies : string list;   (* the singleton upstream request, or [] *)
}

type preparation_error =
  | Stage_declarations_not_canonical of Vision_ontology.stage list

type availability =
  | Prepared of stage_request list
  | Unavailable_observed of string

(* Accepts exactly [Vision_ontology.stages], in its canonical order.
   Total: a reordered, short, extended or duplicated declaration returns
   [Stage_declarations_not_canonical] carrying what was actually offered.
   Performs no IO and starts no process. *)
val prepare :
  stages:Vision_ontology.stage list ->
  (stage_request list, preparation_error) result

(* Always [Unavailable_observed] while the canonical bridge is absent.
   It does not probe, schedule or simulate execution, and it must never
   be made to answer [Prepared] by anything short of a real admitted
   dispatch path. *)
val execution_availability : stage_request list -> availability
