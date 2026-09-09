(** Denotational semantics and equational laws for the UOS toolchain preflight
    (SC-NIX-DEVENV-001).

    This module is PURE: no filesystem, process, network or clock access. Every
    observation — whether a binary executed, what it printed, what the clock
    said — is supplied by the effectful shell (`tools/preflight`). That split is
    the point: the shell decides WHAT WAS OBSERVED, this module decides WHAT
    THAT MEANS, and only the second half is provable.

    {1 Semantic domain}

    A verdict is a two-point lattice ordered [Fail < Pass], carrying findings:

    {v
      Verdict ::= Pass | Fail of finding list
      ⊓ : Verdict -> Verdict -> Verdict          (meet: conjunction of arms)
      ⊤ = Pass                                    (identity of ⊓)
      ⊥ = Fail _                                  (absorbing under ⊓)
    v}

    [(Verdict, ⊓, Pass)] is a bounded commutative idempotent monoid — a
    meet-semilattice with top. Findings accumulate rather than being discarded,
    so a composite failure names every arm that failed, not the first.

    {1 Why fail-closed is an algebraic property, not a coding habit}

    The interpretation of an observation is total: there is no [Unknown] verdict.
    An absent, unreadable or unparseable observation denotes [Fail], and because
    [Fail] absorbs under [⊓], one unknown anywhere makes the whole run [Fail].
    Fail-closed is therefore a consequence of the absorbing element, provable
    once, rather than a discipline re-applied at every call site.

    {1 The useability observation}

    Deliberately richer than an exit status. [Exited_zero_silent] is a DISTINCT
    observation from [Exited_zero_with_output] because a zero-byte file with the
    execute bit set is a valid empty shell script: it exits 0 and prints nothing.
    Collapsing those two into "success" is exactly the defect that let a broken
    npm report itself healthy. *)

type finding = { arm : string; name : string; detail : string }

type verdict = Pass | Fail of finding list

(** {2 The verdict semilattice} *)

val top : verdict
val meet : verdict -> verdict -> verdict
val meet_all : verdict list -> verdict
val is_pass : verdict -> bool
val findings : verdict -> finding list

(** {2 Observations, as supplied by the effectful shell} *)

type execution =
  | Not_executable
  | Exited_nonzero of int
  | Exited_zero_silent          (** exit 0, no output — NOT success *)
  | Exited_zero_with_output of string

(** A probe declares whether silence is legitimate for the tool it runs.
    [Silent_ok] is for tools that say nothing on success (erlc, quint typecheck)
    and must carry a separate artefact assertion; [Output_required] is everything
    else. *)
type probe_expectation = Silent_ok | Output_required

val interpret_execution :
  arm:string -> name:string -> probe_expectation -> execution -> verdict

(** {2 Locality} *)

(** An entrypoint's own path must lie under the project root; the store path it
    resolves to need not, and that asymmetry is the honest boundary — Nix
    binaries cannot be relocated out of /nix/store and still run. *)
val interpret_locality :
  name:string ->
  root:string ->
  entrypoint:string ->
  resolved:string ->
  barred_prefixes:string list ->
  verdict

(** {2 Tracking} *)

(** Both directions. [tracked] comes from the VCS, [present] from the
    filesystem; neither alone is the property. *)
val interpret_tracking :
  tracked:string list -> present:string list -> verdict

(** {2 Receipts} *)

type receipt = {
  status : verdict;
  epoch_s : int;
  checker_sha256 : string;
  table_sha256 : string;
}

(** A cached verdict is evidence about a SPECIFIC checker examining a SPECIFIC
    table. Validity therefore conjoins four independent conditions, and is
    antitone in age: if a receipt is invalid at age [a] it is invalid at every
    age above [a]. *)
val receipt_valid :
  now_s:int ->
  max_age_s:int ->
  checker_sha256:string ->
  table_sha256:string ->
  receipt ->
  verdict

(** {2 Equational laws — the executable specification} *)

module Laws : sig
  val meet_associative : verdict -> verdict -> verdict -> bool
  val meet_commutative : verdict -> verdict -> bool
  val meet_idempotent : verdict -> bool
  val meet_identity : verdict -> bool
  val fail_absorbs : verdict -> finding list -> bool

  (** A composite verdict passes iff every component does. *)
  val meet_all_pass_iff_all_pass : verdict list -> bool

  (** Every finding of every component survives into the composite: a composite
      failure names all failing arms, never only the first. *)
  val findings_preserved : verdict list -> bool

  (** Exit 0 with no output where output was required denotes Fail. *)
  val silent_zero_is_not_success : arm:string -> name:string -> bool

  (** Receipt validity is antitone in age. *)
  val receipt_validity_antitone_in_age : receipt -> int -> int -> int -> bool

  (** Any change to either digest invalidates the receipt, whatever its age. *)
  val digest_change_invalidates : receipt -> int -> bool
end
