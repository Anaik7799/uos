(* HW.8.2.7 — the reconciliation pair: declared vs derived, residue computed.

   THE PATTERN, ONCE. Feature_register.status prefers a live probe and
   reports stale_declarations; Gap_plan does the same; Formal_coverage
   declares intent and reconciles against computed actuals, fail-closed on
   unknown subjects; the render baseline compares pinned digests against
   recomputed renders and splits the residue into Drifted and Edited_since;
   Hermes_wiki.schema_gaps reports missing required fields;
   Dep_sheaf.dead_cover_elements compares a declared cover against observed
   sensitivity, with widen_with as the meta-falsification hook; the evidence
   store REFUSES a same-key/different-payload replay (R3). Seven sites, one
   algebra: two partial sections of one bundle, a computed difference, and a
   fail-closed totalisation. This module is that algebra, written once.

   THE LAW, AND WHY IT IS (PARTLY) A TYPE. [t] is abstract and [status] is
   the only reader; the declared claim has no accessor of its own. A
   consumer that trusts a declaration over a live probe cannot be written
   against this interface — enabling one requires adding an accessor HERE,
   a reviewable change (the no-widen move of Dep_sheaf, applied to
   registries).

   ADMISSIBILITY. Pure: probes are supplied as closures by the instance and
   run only under [snapshot]; this module performs no IO. Residues are
   lists with one deterministic order (key order), so P1 holds and a
   residue can be pinned, diffed and ratcheted. *)

module type SUBJECT = sig
  type key
  type claim

  val compare_key : key -> key -> int      (* total: residues are sorted *)
  val equal_claim : claim -> claim -> bool
  val show_key : key -> string
  val show_claim : claim -> string
end

module Make (S : SUBJECT) : sig
  type t

  (* One row: a key, an optional declaration, an optional probe. At least
     one of the two must be present, or the row is refused: a key with
     neither is a claim nobody made. Duplicate keys are refused outright —
     write functionality, R3's shape at registration time. *)
  val register :
    (S.key * S.claim option * (unit -> S.claim option) option) list ->
    (t, string) result

  (* Evaluate every probe once, under this call, and freeze the result:
     status/residue/report below are then pure reads of the frozen
     snapshot, so one battery run sees one consistent world (S40). *)
  val snapshot : t -> t

  (* The ONLY reader. Probe answer if the probe exists and answered;
     otherwise the declaration; otherwise None — never a default, never a
     pass (fail-closed). *)
  val status : t -> S.key -> S.claim option

  (* Both defined and differing, sorted by key. Each entry names declared
     and observed — the worklist form, like stale_declarations. *)
  val residue : t -> (S.key * S.claim * S.claim) list

  (* Fail-closed validation of foreign claims: every claimed key this
     register does not know, sorted. The Formal_coverage.reconcile rule —
     "unknown subjects are drift too". *)
  val unknown : t -> claimed:S.key list -> S.key list

  (* Meta-falsification: overlay a deliberate observation and prove the
     residue can fire. The widen_with of Dep_sheaf, generalised. Never
     used outside tests; exported because a residue nobody has seen fire
     is a residue nobody has confirmed works. *)
  val inject : t -> S.key -> S.claim -> t

  (* The one-line summary every driver prints: total rows, probed rows,
     residue size, unknown-claim count for a supplied claim set. *)
  type report = { rows : int; probed : int; stale : int; unknown : int }

  val report : t -> claimed:S.key list -> report
end
