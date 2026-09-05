(* The control plane: a Zenoh queryable exposing status and restart for
   every pipeline component.

   Telemetry (see {!Vision_telemetry}) is one-way and fail-open — an
   observation nobody must act on. This is the other direction, and it
   is FAIL-CLOSED: a query that cannot be understood, for a component
   that does not exist, or naming an action that is not offered, replies
   with an explicit error. It never replies with a success shape, and it
   never guesses which component was meant.

   The reason is asymmetry of harm. A dropped telemetry message costs a
   line in a dashboard. A restart dispatched to the wrong component, or
   a malformed query silently treated as `status`, acts on a live media
   pipeline. So the parser refuses rather than interprets. *)

type action = Status | Restart

val action_name : action -> string

(* Actions are named exactly. There is no prefix matching and no
   case-insensitive fallback: "rest", "RESTART " and "restart-now" are
   all refused, because a control plane that is generous about spelling
   is one that eventually restarts something on a typo. *)
val parse_action : string -> (action, string) result

type component = {
  name : string;
  (* Current state as JSON. Called on every status query, so it must
     MEASURE rather than return a cached flag — a status that reports
     what was true at startup is how a dead component stays green. *)
  status : unit -> string;
  (* Stop and start again, returning a description of the new state, or
     a named error. A restart that cannot confirm the component came
     back must return [Error]: reporting success because the stop half
     worked is the failure mode this exists to prevent. *)
  restart : unit -> (string, string) result;
}

(* `hermes/vision/control` — queries arrive at
   `hermes/vision/control/<component>`. *)
val key_prefix : string
val key_for : string -> string

(* The component named by a key, or None. Total. *)
val component_of_key : component list -> string -> component option

(* Handle one query. TOTAL: every input produces a JSON reply, including
   a reply that says why the input was refused. This is the function the
   tests drive, so the whole control surface is testable without a
   router. *)
val dispatch : component list -> string -> string -> string

(* Serve until the process is stopped. [Error] on setup failure — a
   missing or disabled router is never reported as serving. *)
val serve : component list -> (unit, string) result

(* The pipeline itself as a controllable component: status probes the
   live process and its packaged output; restart stops ffmpeg and starts
   it again from the same declared intent. *)
val ffmpeg_component :
  intent:Vision_intent.intent -> dir:string ->
  handle:Vision_controller.handle ref -> component

(* The SERVER's restart, where the zero-downtime shape genuinely
   applies: two instances can share a listening socket (SO_REUSEPORT),
   so the old one keeps serving through the gate and no client meets a
   closed port.

   The gate polls /whoami for the NEW identity. With a shared port a
   plain health check may be answered by the OLD instance and pass
   regardless of whether the replacement works — a gate that cannot
   fail. Requiring the new id is what makes it real.

   Draining sits at the END here, not the start: the contended encoder
   must drain first because two cannot coexist; the server must not,
   because coexistence is the mechanism. Same phases, different
   operation carrying the drain — a property of the resource, not of the
   restart. *)
val server_component :
  host:string -> port:int -> dir:string ->
  spawn:(id:string -> (int, string) result) ->
  stop_old:(unit -> unit) ->
  next_id:(unit -> string) ->
  component
