(* Deterministic corpus generator for the model-to-source differential oracle.
   Seeded LCG, so a corpus is reproducible from (seed, count) alone and a
   divergence can be replayed exactly. OCaml per the repository helper-language
   rule; no shell, Python or Node logic.

   Usage: gen_corpus SEED COUNT > corpus-gen.tsv

   ASCII only, by design: forecast G1 is specifically about whether the model
   and the deployed engine agree once the byte/grapheme question is removed. *)

let state = ref 0

let next () =
  (* Numerical Recipes LCG; modulus 2^31 kept inside OCaml's 63-bit int. *)
  state := (1103515245 * !state + 12345) land 0x3FFFFFFF;
  !state

(* The low bits of an LCG with a power-of-two modulus have very short periods:
   taking `next () mod 4` directly produced a constant `steps` across the whole
   corpus. Shift the high bits down first. *)
let pick n = ((next ()) lsr 12) mod n

let alphabet = [| 'a'; 'b'; 'c' |]

let rand_word lo hi =
  let n = lo + pick (hi - lo + 1) in
  String.init n (fun _ -> alphabet.(pick (Array.length alphabet)))

let () =
  let seed = int_of_string Sys.argv.(1) in
  let count = int_of_string Sys.argv.(2) in
  state := seed;
  for _ = 1 to count do
    (* Measured coverage of an earlier version of this generator: 9,833 OK and
       167 budget-exceeded out of 10,000, but ZERO cases exercising the input
       guard, because every generated input was valid. The guard has five
       rejection paths and they were covered only by the 23-case hand corpus.
       So roughly one case in eight is now deliberately malformed. *)
    let malformed = pick 8 = 0 in
    (* Seed: 1..6 symbols. Short enough that growth rules mostly stay inside
       the 64-state budget, long enough for overlapping matches to occur.
       Occasionally long enough to breach the 128-byte seed bound. *)
    let s =
      if malformed && pick 3 = 0 then ""            (* empty seed *)
      else if malformed && pick 5 = 0 then rand_word 129 140  (* over byte bound *)
      else rand_word 1 6
    in
    let nrules =
      if malformed && pick 4 = 0 then 0             (* no rules *)
      else if malformed && pick 4 = 1 then 9 + pick 3   (* too many rules *)
      else 1 + pick 3
    in
    let rules =
      List.init nrules (fun i ->
        (* lhs nonempty unless deliberately malformed; rhs may be empty. *)
        let lhs =
          if malformed && i = 0 && pick 3 = 1 then ""
          else if malformed && i = 0 && pick 7 = 2 then rand_word 33 36 (* over 32 *)
          else rand_word 1 2
        in
        let rhs =
          if malformed && i = 0 && pick 9 = 3 then rand_word 33 36
          else rand_word 0 3
        in
        lhs ^ ">" ^ rhs)
    in
    let steps =
      if malformed && pick 3 = 2 then pick 2 * 5    (* 0 or 5: out of 1..4 *)
      else 1 + pick 4
    in
    Printf.printf "%s\t%s\t%d\n" s (String.concat "," rules) steps
  done
