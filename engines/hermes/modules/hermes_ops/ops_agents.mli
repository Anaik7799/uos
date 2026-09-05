(* Per-module AGENTS.md, derived from the dune graph — see the .ml.

   Hand-written module guides drift; these are regenerated, so a module
   that gains a dependency gains it in its guide too. The ownership and
   boundary notes are the one part a machine cannot derive and are
   declared in the implementation.

   [generate ~write:false] reports what WOULD change without touching the
   tree, so a gate can fail on drift the way `gen_feature_model --check`
   does. Returns (module name, would-change) pairs. *)
val generate : write:bool -> (string * bool) list
