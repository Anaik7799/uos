(* The OCaml TRANSCRIPTION of proofs/Parity_Lattice.v -- line for line, so the
   full-domain differential (test_rocq_lattice) compares the proof script's
   definitions against the live algebra on every run.

   HONESTY OF PROVENANCE: this is a transcription, NOT coqc extraction output --
   no Rocq toolchain exists on this host (coqc_available=false, disclosed by the
   test). On a coqc host, the extraction block in the .v regenerates the
   machine-produced encoding and this file is byte-pinned against it (the zigvm
   generated/rocq freshness law); until then the differential below is what
   keeps this transcription honest. *)

type verdict = Unmapped | Blocked | Verified | Divergent

(* Definition rank *)
let rank = function Verified -> 0 | Unmapped -> 1 | Blocked -> 2 | Divergent -> 3

(* Definition combine := if Nat.leb (rank b) (rank a) then a else b *)
let combine a b = if rank b <= rank a then a else b

(* Definition grants_credit *)
let grants_credit = function Verified -> true | _ -> false

(* Definition gate := if grants_credit a then combine a b else a *)
let gate a b = if grants_credit a then combine a b else a
