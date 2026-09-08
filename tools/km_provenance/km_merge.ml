(* SC-PROVENANCE-001 — denotational model of MERGE READINESS.
   Companion to km_ev.ml: that answers "may this cycle be admitted", this
   answers "may this branch be merged".

   ================= WHAT WAS OBSERVED =================

   13 bookmarks sit unmerged, each exactly one commit ahead of main, aged 34
   minutes to 22 hours. One is literally named `review/codex-unification-50-
   merge-held`, and its commit says "broad native gates held". Yet that work's
   own risk record states blockers: [] and readiness: "ready".

   So the hold is not a failing check. It exists ONLY as a string inside a
   bookmark name and a commit message. Nothing can evaluate it, and nothing can
   clear it, so the work simply accumulates.

   Second observation: 48 of 49 risk assessments in the tree are EXPIRED. The
   median validity window is 120 minutes while the branches waiting on those
   assessments are hours to a day old. Authorisation expires faster than the
   review that consumes it, and SC-RISK-CHECK-001 forbids force-passing a stale
   result. Re-assessing costs time, during which the new assessment also
   expires: a treadmill.

   ================= DENOTATION =================

     [[mergeable]] : Branch -> Revision -> Time -> Verdict

     [[mergeable]](b, r, t) = Mergeable
         iff  exists a in Assessment.
                covers(a, b) and fresh(a, t) and readiness(a) = Ready
                and blockers(a) = empty
              and builds(b, r)
              and not exists h in Hold. applies(h, b) and not cleared(h)

     otherwise NotMergeable with the first failing conjunct as the reason.

   Verdict is two-valued and NotMergeable absorbing, for the same reason as in
   km_ev: an Unknown on a dashboard is read as a pass.

   ================= THE FRESHNESS AXIS IS WRONG =================

   fresh(a, t) above is wall-clock. That is what produces the treadmill. The
   design fix is revision_fresh: an assessment binds to a CONTENT REVISION, and
   stays valid for as long as that revision is unchanged. A branch nobody has
   touched does not become riskier because two hours passed.

   Both predicates are implemented so the difference is measurable rather than
   argued: see `fresh_wallclock` and `fresh_revision`. *)

exception Invalid of string
let require c m = if not c then raise (Invalid m)

type verdict = Mergeable | Not_mergeable of string

let to_string = function Mergeable -> "MERGEABLE" | Not_mergeable _ -> "NOT_MERGEABLE"
let reason = function Mergeable -> "" | Not_mergeable r -> r

type readiness = Ready | Blocked | Needs_evidence

let readiness_of_string = function
  | "ready" -> Ready
  | "blocked" -> Blocked
  | _ -> Needs_evidence

type assessment = {
  branch : string;
  revision : string;          (* the revision the assessment was taken against *)
  observed_at : float;        (* epoch seconds *)
  valid_until : float;        (* epoch seconds; the wall-clock window *)
  readiness : readiness;
  blockers : string list;
}

(* A hold as DATA, which is the repair for holds encoded in bookmark names.
   A hold that cannot name its clearing condition can never be discharged. *)
type hold = {
  h_branch : string;
  h_reason : string;
  h_clearing_condition : string;   (* what must become true; empty = undischargeable *)
  h_cleared : bool;
}

(* Wall-clock freshness: what the repository does today. *)
let fresh_wallclock a ~now = now <= a.valid_until

(* Revision freshness: valid while the branch content is unchanged. This does
   not weaken the check; it moves it onto the axis that actually carries risk. *)
let fresh_revision a ~current_revision = a.revision = current_revision

let applies h b = h.h_branch = b

(* The verdict. Conjuncts are evaluated in a fixed order so the reported reason
   is the FIRST failure, which is stable across runs and therefore diffable. *)
let mergeable
    ~(assessments : assessment list)
    ~(holds : hold list)
    ~(builds : bool)
    ~(now : float)
    ~(current_revision : string)
    ~(use_revision_freshness : bool)
    (branch : string) : verdict =
  match List.find_opt (fun a -> a.branch = branch) assessments with
  | None -> Not_mergeable "no risk assessment covers this branch"
  | Some a ->
    let is_fresh =
      if use_revision_freshness then fresh_revision a ~current_revision
      else fresh_wallclock a ~now in
    if not is_fresh then
      Not_mergeable
        (if use_revision_freshness
         then "assessment was taken against a different revision"
         else "assessment expired")
    else if a.readiness <> Ready then Not_mergeable "assessment readiness is not ready"
    else if a.blockers <> [] then
      Not_mergeable ("assessment lists blockers: " ^ String.concat ", " a.blockers)
    else if not builds then Not_mergeable "branch does not build green"
    else
      match List.find_opt (fun h -> applies h branch && not h.h_cleared) holds with
      | Some h ->
        Not_mergeable
          ("held: " ^ h.h_reason
           ^ (if String.trim h.h_clearing_condition = ""
              then " [NO CLEARING CONDITION RECORDED: this hold cannot be discharged]"
              else " [clears when: " ^ h.h_clearing_condition ^ "]"))
      | None -> Mergeable

(* A hold is well-formed only if it says what would clear it. An undischargeable
   hold is a permanent block wearing the costume of a temporary one. *)
let hold_well_formed h = String.trim h.h_clearing_condition <> ""
