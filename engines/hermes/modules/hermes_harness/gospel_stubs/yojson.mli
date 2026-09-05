(* Checking-only stub of Yojson for `gospel check`.

   gospel resolves one file at a time and ignores `include module type of`, so
   the real yojson interface cannot supply `Yojson.Safe.t` to a contract under
   check. This stub supplies the name and nothing else.

   It is deliberately weaker than the real type, which is a variant: an
   abstract type gives gospel strictly fewer facts, so a specification that
   type-checks against this stub also type-checks against the real Yojson. The
   stub can therefore cause a false rejection, never a false acceptance. Do not
   add constructors or equations here: that would reverse the direction and let
   a contract pass on facts the real type does not provide. *)

module Safe : sig
  type t
end
