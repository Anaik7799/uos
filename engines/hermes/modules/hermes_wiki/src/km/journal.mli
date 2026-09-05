(* KM journal integrity — the journal pillar's laws, ported from the
   imported journal_bundle model (its privacy trio and validation shape).

   R16: the name carries the date the ENVIRONMENT supplied when the entry
   was born: YYYYMMDD-HHSS-<slug>.md, slug non-empty, lowercase [a-z0-9-].
   HH is 00-23 and SS is 00-59. This user-mandated timestamp law is exact;
   date-only frontmatter fields remain their separate schema type.
   Append-only: a later session may only APPEND to a journal; an edit
   that rewrites history is a violation, detected as "old content is no
   longer a prefix". Privacy: the bundle model's trio — and a Secret
   artifact is REJECTED, never bundled (the imported model's own law). *)

val valid_name : string -> bool

type privacy = Public_data | Personal_identifier | Secret

val privacy_of_string : string -> (privacy, string) result

(* Secret is never admissible in a journal bundle — the rejection is the
   law, not a policy knob. *)
val admissible : privacy -> bool

(* old must be a byte-prefix of new (modulo nothing — bytes): append-only.
   Returns None when honest, Some diagnostic naming the first divergence
   line when history was rewritten. *)
val append_violation : old_content:string -> new_content:string -> string option
