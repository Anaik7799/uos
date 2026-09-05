(* The port is verified against its SOURCE'S own numeric anchors — the paste
   claims "a 0/40 site moving carries 6.36 b; a 26/40 site, 0.63 b" — so the
   adaptation is checked against the upstream's published numbers, not
   assumed. Exact identities are asserted exactly; anchors to 3 decimals. *)

let passed = ref 0
let failures = ref []
let check c l = if c then incr passed else failures := l :: !failures
let close ?(eps = 1e-9) a b = Float.abs (a -. b) < eps
let anchor a b = Float.abs (a -. b) < 5e-3

open Info_math

let () =
  (* THE PASTE'S OWN ANCHORS. Jeffreys Beta(0.5,0.5). *)
  check (anchor (surprisal (beta_pred ~k:0.0 ~n:40.0 ~a:0.5 ~b:0.5)) 6.358)
    "ANCHOR a 0-of-40 site moving carries ~6.36 bits";
  check (anchor (surprisal (beta_pred ~k:26.0 ~n:40.0 ~a:0.5 ~b:0.5)) 0.630)
    "ANCHOR a 26-of-40 site moving carries ~0.63 bits";
  (* Jeffreys never yields zero: a never-changed site is not infinitely
     surprising when it finally moves. *)
  check (beta_pred ~k:0.0 ~n:1000.0 ~a:0.5 ~b:0.5 > 0.0)
    "PRIOR Jeffreys assigns no site probability zero";

  (* h2 exact points, and totality at the edges. *)
  check (close (h2 0.5) 1.0) "H2 h2(1/2) = 1 exactly";
  check (close (h2 0.0) 0.0 && close (h2 1.0) 0.0) "H2 total at the edges, no NaN";

  (* CAPACITY: the zero-capacity flake, formally. epsilon = 0.5 is the
     event-store finding stated as a theorem: verdict independent of code. *)
  check (close (capacity ~epsilon:0.5) 0.0) "CAPACITY a 50% flake carries 0 bits";
  check (close (capacity ~epsilon:0.0) 1.0) "CAPACITY a deterministic site carries 1 bit";
  check (capacity ~epsilon:0.1 > capacity ~epsilon:0.3)
    "CAPACITY monotone: flakier is worth less";

  (* Surprisal monotone (negative control for a sign error). *)
  check (surprisal 0.9 < surprisal 0.1) "SURPRISAL rarer is more surprising";

  (* lse2 / normalize identities. *)
  check (close (lse2 [ 3.0 ]) 3.0) "LSE2 singleton is the identity";
  check (lse2 [] = neg_infinity) "LSE2 empty is -inf, not a crash";
  let p = normalize_log2 [ 0.0; -1.0; -2.0 ] in
  check (close (List.fold_left ( +. ) 0.0 p) 1.0) "NORMALIZE sums to 1";

  (* Entropy and KL exact points. *)
  check (close (entropy_bits [ 0.25; 0.25; 0.25; 0.25 ]) 2.0)
    "ENTROPY uniform over 4 is exactly 2 bits";
  check (close (kl_bits [ 0.3; 0.7 ] [ 0.3; 0.7 ]) 0.0) "KL identical is 0";
  check (close (kl_bits [ 1.0; 0.0 ] [ 0.5; 0.5 ]) 1.0)
    "KL point mass vs fair coin is exactly 1 bit";

  (* EIG (Lindley): the discriminator math. A PERFECT probe over two
     equiprobable hypotheses gains exactly 1 bit; a USELESS probe gains 0;
     a noisy symmetric probe gains its channel capacity. *)
  let post = [| 0.5; 0.5 |] in
  check
    (close (eig_bits ~post ~outcomes:[ ("y", [| 1.0; 0.0 |]); ("n", [| 0.0; 1.0 |]) ]) 1.0)
    "EIG a perfectly discriminating probe gains exactly 1 bit";
  check
    (close (eig_bits ~post ~outcomes:[ ("y", [| 0.7; 0.7 |]); ("n", [| 0.3; 0.3 |]) ]) 0.0)
    "EIG a probe blind to the hypotheses gains 0 (negative control)";
  check
    (anchor
       (eig_bits ~post ~outcomes:[ ("y", [| 0.9; 0.1 |]); ("n", [| 0.1; 0.9 |]) ])
       (capacity ~epsilon:0.1))
    "EIG a symmetric noisy probe gains its channel capacity";

  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_info_math" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_info_math ]);
  exit (Suite_telemetry.exit_code self)
