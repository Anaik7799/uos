(* Extraction driver: nat -> int so the output is the clean table over ints. *)
From Coq Require Import Extraction.
From Coq Require Import ExtrOcamlBasic ExtrOcamlNatInt.
Require Import Parity_Lattice.
Extraction "parity_lattice_extracted.ml" verdict combine grants_credit gate.
