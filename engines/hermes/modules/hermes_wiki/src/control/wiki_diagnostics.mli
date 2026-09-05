(* Fractal diagnostics for the wiki/ZK/KM system — every finding carries
   its fractal coordinate (level) and its RCA origin, and the two answer
   different questions: the level says WHERE in the corpus fractal the
   finding sits, the origin says WHERE TO GO LOOKING.

   THE R5 LAW, HELD BY TYPE. A monitor senses and reports; it can never
   deny credit. Every constructor here therefore produces a diagnostic
   whose impact is [Blocks_credit] or [No_effect] — never
   [Denies_credit] — and whose origin is never [Implementation]. Neither
   is a runtime check: the functions below simply cannot build such a
   value, so a monitor that denied parity credit would have to be
   written HERE, as a reviewable change. (The wiki plane is not the
   parity plane; a dead link says nothing about the candidate.)

   THE FRACTAL LEVELS, MAPPED TO THIS DOMAIN. The corpus has its own
   fractal, and R9 forbids identifying it with the evidence chain — so
   the mapping below is a DECLARED convention for this plane, not a
   claim that the two fractals are the same:
     L0 corpus-wide (the whole product of the wiki)
     L1 a group / family of documents
     L2 a document's capability (its links, its schema)
     L3 a stated contract (a law a document claims)
     L4 a fixture (a pinned baseline entry)
     L5 a trace (a rendered artifact)
     L6 a receipt (a digest)
     LX the control plane (the auditor itself, never a corpus finding)

   OTEL BRIDGE, ONE DIRECTION. [to_otel] renders a diagnostic as a log
   record; there is no [of_otel]. Telemetry flows outward only (R4), and
   the absence of the inverse is the S38 seam. *)

type finding =
  | Dead_link of { source : string; target : string }
  | Ambiguous_ref of { source : string; target : string }
  | Dead_anchor of { source : string; target : string; anchor : string }
  | Schema_gap of { page : string; field : string }
  | Drifted_render of { page : string }
  | Stale_declaration of { row : string }
  | Grounded_anomaly of { claim : string }
  | Orphan of { page : string }
  | Unported_mirror of { module_ : string; row : string }
  | Ratchet_breach of { gauge : string; previous : int; current : int }
  | Journal_violation of { file : string; detail : string }
  | Term_gap of { page : string; term : string }
  | Index_violation of { page : string; target : string }
  | Corpus_defect of { detail : string }
  | Include_gap of { page : string; path : string; reason : string }
  | Toc_gap of { page : string; target : string }

(* The classifier: one finding, one diagnostic. Total. *)
val diagnose : finding -> Fractal_diagnostic.t

(* Every diagnostic this module can produce, for the meta-falsification
   leg: a catalogue nobody has seen fire is a catalogue nobody trusts. *)
val all_findings_sample : finding list

(* The one-directional bridge. Attributes carry the fractal coordinate
   so a log reader can filter by level and origin. *)
val to_otel : ts:string -> Fractal_diagnostic.t -> Wiki_otel.record
