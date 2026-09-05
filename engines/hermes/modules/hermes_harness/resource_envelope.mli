(** Fail-closed resource-envelope preflight.

    The evidence chain already refuses to record anything it did not verify;
    this extends the same discipline to the resources an operation consumes.
    Nothing is used that was not checked, and a resource that is unknown or
    insufficient fails closed with a fractal diagnostic rather than a raw crash.

    The pure decision remains available through {!evaluate}.  Operational
    observation is deliberately unavailable until an R31-controlled owner can
    inject an opaque, receipt-bound observation.  Consequently {!check_one}
    and every non-empty {!preflight} fail closed rather than probing the host
    through raw filesystem, process, shell, environment, or Unix calls. *)

(** Stable filesystem object identity. This intentionally binds device and
    inode only; the consuming authority remains responsible for its canonical
    cryptographic digest and for rechecking the opened object at use time. *)
type executable_identity = { device : int; inode : int }

(** Kernel facilities a supervised worker may require. Observing support is a
    preflight fact, not proof that a later worker successfully applied a limit
    or contained a child. *)
type kernel_capability =
  | Proc_self_fd_executable
  | Rlimit_as
  | Process_group_signalling

type resource =
  | Temp_space of { bytes_needed : int; margin : float }
      (** Free space required on the effective temp filesystem ($TMPDIR or /tmp),
          where captures and comparisons write transient trees. *)
  | Disk_space of { path : string; bytes_needed : int; margin : float }
      (** Free space required on the filesystem holding [path] -- fixtures, the
          evidence database and [_build] all live on the project disk. *)
  | Binary of { name : string; env_var : string option }
      (** An executable that must be resolvable, either at the path named by
          [env_var] (when set and non-empty) or as [name] on PATH. *)
  | Exact_executable of { path : string; expected : executable_identity }
      (** [path] must currently resolve to the declared regular executable
          object. This is a cheap device/inode TOCTOU preflight; content digest
          and execute-time open-object identity remain downstream obligations. *)
  | Kernel_capability of kernel_capability
      (** A host-kernel supervision primitive that must be observable before a
          worker starts. Unknown and unsupported both fail closed. *)
  | Writable of string
      (** A path that must be writable now, or -- if it does not yet exist --
          whose parent directory must be, so a not-yet-created file counts. *)
  | Frozen_reference of { root : string }
      (** The frozen reference snapshot must be present and non-empty. The
          cryptographic digest pin is verified downstream by {!Inventory}; this
          is the cheap up-front presence gate, not the digest check. *)

(** A caller-supplied fact for the pure decision algebra.  This type carries no
    observation or execution authority: even a semantically met fact cannot
    satisfy {!satisfied} because it has no owner-produced receipt. *)
type reported_fact =
  | Space of { available_bytes : int }  (** free bytes on the relevant filesystem *)
  | Presence of bool                    (** found / writable / present *)
  | Executable of {
      identity : executable_identity;
      regular_file : bool;
      executable : bool;
    }
      (** Object identity and access properties observed for an exact path. *)
  | Capability of { capability : kernel_capability; supported : bool }
      (** A capability-bound observation; support for one kernel primitive may
          not be substituted for another. *)
  | Unknown of string                   (** could not be determined; the string says why *)

(** Opaque carriers reserved for the future controlled observation owner.
    No constructor or injection function is exported by this module. *)
type observation_receipt
type observation

type operational_status =
  | Implemented_unavailable of string
      (** The pure evaluator is implemented, but operational sensing is not
          available without the controlled owner and its receipt. *)

type check = private {
  resource : resource;
  met : bool;
  detail : string;
  receipt_bound : bool;
}

(** Current operational-observer lifecycle. *)
val operational_status : operational_status

(** The absolute free-space backstop: no space check passes if it would leave
    less than this free, regardless of the estimate. The tmpfs that motivated
    this module failed at 99% full, so a percentage margin alone is not enough;
    the floor is what actually guarantees headroom. 512 MiB. *)
val floor_bytes : int

(** The default proportional margin for space requirements: 20%. *)
val default_margin : float

(** Pure verdict for a resource given an already-gathered fact. Total: every
    (resource, observation) pairing returns a check and never raises. A space
    resource is met only when [available >= needed *. (1. +. margin)] AND
    [available - needed >= floor_bytes]; a presence resource is met only on
    [Presence true]; every [Unknown] and every mismatched observation kind is
    unmet. *)
val evaluate : resource -> reported_fact -> check

(** Return an unmet, non-receipt-bound check while the controlled operational
    observer is unavailable.  This function performs no external access. *)
val check_one : resource -> check

(** Check a whole envelope.  Every non-empty envelope is currently refused as
    [Implemented_unavailable]; an empty envelope remains vacuously satisfied
    because it consumes no resource. *)
val preflight : resource list -> check list

(** True only when every check is met AND owner-receipt-bound.  A pure
    {!evaluate} result can exercise the decision algebra but cannot authorize
    an operation. *)
val satisfied : check list -> bool

(** The unmet checks, in input order. *)
val unmet_checks : check list -> check list

(** One fractal diagnostic per unmet check, none for met checks. Every resource
    diagnostic is [Blocks_credit] with an Environment, Control or Evidence
    origin and a resource hazard with an HZ-RES- id: a resource shortfall proves
    nothing about the candidate, so it can never deny -- still less grant -- parity
    credit. Reuses {!Fractal_diagnostic} and its OTLP path so a preflight
    refusal is observable exactly like every other diagnostic. *)
val to_diagnostics : check list -> Fractal_diagnostic.t list

(** A one-line human description of a resource requirement. *)
val describe_resource : resource -> string

(** A one-line human rendering of a check's verdict. *)
val render_check : check -> string
