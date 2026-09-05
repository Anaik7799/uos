(* The corpus render differential (zigvm WIKI_PIPELINE §9) — the control
   that makes a renderer change LOUD instead of silent.

   Each baseline line is `<render-digest> <content-digest> <path>`. The
   second digest is what makes honesty possible: a document edited since
   the baseline was taken is reported `Edited_since` and SKIPPED, never
   quietly re-baselined, so the checker cannot absorb a change it was
   built to detect.

   Re-baselining ACCEPTS a corpus-wide rendering change and is therefore
   never run by the battery — doing it without a stated reason is exactly
   how silent drift would enter. *)

type entry = { render_digest : string; content_digest : string; path : string }

type verdict =
  | Checked            (* content unchanged, render matches: admitted *)
  | Drifted of string * string  (* expected, actual — the RED case *)
  | Edited_since       (* source changed: skipped, honestly *)
  | Unlisted           (* not in the baseline at all *)

type outcome = { path : string; verdict : verdict }

(* Pure: compare one document against a baseline. *)
val check_one :
  baseline:entry list -> path:string -> content:string -> render:string -> outcome

(* Pure: the whole corpus. Documents are (path, content, render). *)
val check :
  baseline:entry list -> (string * string * string) list -> outcome list

(* [] when every listed document is Checked or honestly skipped; the
   Drifted lines otherwise, rendered for an operator. *)
val drift : outcome list -> string list

(* Serialization. Deterministic, sorted by path. *)
val to_lines : entry list -> string list
val of_lines : string list -> entry list

(* Build the baseline for a corpus (the re-baseline operation). *)
val build : (string * string * string) list -> entry list

(* The digest used for both columns; SHA-256 via the harness's existing
   helper, so there is one digest implementation in the repository. *)
val digest : string -> string
