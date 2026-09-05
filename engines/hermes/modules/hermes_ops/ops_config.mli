(* Configuration as DECLARATIVE INTENT — the single source, and the gate
   that makes "declarative only" true rather than aspirational.

   The rule is that all configuration is declared intent at every fractal
   layer. An environment variable read directly from code is the opposite
   of that: it is configuration that exists only in the place it is
   consumed, invisible to any model, undocumented until someone greps for
   it, and impossible to validate before the run that needs it.

   So there is one model. Every configuration element declares what it is
   FOR, which FRACTAL LAYER it belongs to, whether the system requires it,
   and how it is supplied. Everything else — the environment template, the
   operator documentation, the bootstrap expectations — is DERIVED from
   that model and regenerated, never hand-written.

   ---------------------------------------------------------------------
   THE GATE IS WHAT MAKES IT "ONLY"

   [undeclared] scans the tree for `Sys.getenv` and reports every variable
   the code reads that this model does not declare. A non-empty result is
   a gate failure. Without it, "all configuration is declarative" is a
   sentence in a document; with it, adding an undeclared variable breaks
   the build.

   The converse is reported too: [unused] names elements declared here
   that nothing reads. A model that accumulates dead declarations stops
   describing the system as surely as one that misses live ones.

   ---------------------------------------------------------------------
   SECRETS DECLARE HOW THEY ARE USED, NOT JUST THAT THEY EXIST

   [Presence_only] and [Value_used] are different security postures, and
   the distinction is load-bearing rather than descriptive. The bootstrap
   probe evaluates `Option.is_some (Sys.getenv_opt "OPENROUTER_API_KEY")`
   and never reads the value — so that element is [Presence_only], and a
   reviewer can see from the model alone that no code path can leak it.
   An element that promoted itself to [Value_used] would be a reviewable
   change to this file, not a silent change to a call site. *)

(* Where the element sits in the fractal ontology. Configuration has
   layers for the same reason diagnostics do: a missing prover binary
   (L3, contract) and a missing corpus root (L0, product) fail different
   things and want different responses. *)
type layer =
  | L0_product      (* what the deliverable is built from *)
  | L1_family       (* a subsystem's own wiring *)
  | L2_capability   (* one capability's switch *)
  | L3_contract     (* the checkers that discharge contracts *)
  | L4_fixture      (* oracles and reference environments *)
  | L5_trace        (* endpoints and sinks *)
  | LX_control      (* the harness observing itself *)

type supply =
  | Environment     (* supplied by the OS environment *)
  | Toolchain       (* established by the opam switch, not by a variable *)
  | Derived         (* computed by the system; declared so it is visible *)

type secrecy =
  | Not_secret
  | Presence_only   (* the value is never read — only whether it is set *)
  | Value_used      (* the value is consumed; handle accordingly *)

type necessity =
  | Required        (* the system cannot run without it *)
  | Optional_flag   (* absent means a disclosed skip, never a failure (R2) *)
  | Override        (* absent means a sensible default; set to redirect *)

type element = {
  key : string;
  layer : layer;
  supply : supply;
  secrecy : secrecy;
  necessity : necessity;
  purpose : string;      (* what it is FOR, in one sentence *)
  consumer : string;     (* the file whose Sys.getenv reads it *)
  note : string;         (* the thing that is easy to get wrong; "" if none *)
}

val layer_name : layer -> string
val elements : element list
val schema_id : string
(* SHA-256 over the exact ordered declaration fields. This binds intent
   schema only; it contains no configured value or currentness claim. *)
val declaration_digest_of : element list -> string
val declaration_digest : string

(* The environment template, DERIVED. Regenerating it after a model change
   is the whole point — the previous template was hand-written and was
   already the wrong shape the moment a variable moved. *)
val env_template : unit -> string

(* One line per element, grouped by fractal layer, for the operator. *)
val render : unit -> string
