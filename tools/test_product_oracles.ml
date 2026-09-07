#use "product_workflow.ml";;
let ()=
 let count=ref 0 in
 let check name ok = require ok name;incr count;Printf.printf "ok oracle %s\n%!" name in
 check "input limit rejects before process creation" (try ignore(O.run O.Sha256 ~version:false(String.make 65537 'x'));false with Failure _->true);
 let hash=O.run O.Sha256 ~version:false "abc" in
 check "isolated executable hash equals Cryptokit" (successful hash && lines hash.output=[sha "abc"^"  -"]);
 let proof=O.run O.Z3 ~version:false(truth_query()) in
 check "actual kernel matches Z3 with two SAT controls" (successful proof && lines proof.output=["sat";"unsat";"sat"]);
 let mutant=Str.global_replace(Str.regexp_string "(assert (xor candidate spec))") "(assert (xor true spec))" (truth_query()) in
 let disproved=O.run O.Z3 ~version:false mutant in
 check "known permissive mutant has a real counterexample" (successful disproved && lines disproved.output=["sat";"sat";"sat"]);
 let malformed=O.run O.Z3 ~version:false "(not-valid-smt)\n" in
 check "invalid solver input is not accepted as evidence" (not(successful malformed) || lines malformed.output<>["sat";"unsat";"sat"]);
 let noisy=O.run O.Z3 ~version:false "(declare-const x (_ BitVec 1000000))\n(assert (= x (_ bv0 1000000)))\n(check-sat)\n(get-model)\n" in
 check "output flood is bounded and nonpassing" (noisy.fault=Some "output_limit" && String.length noisy.output+String.length noisy.error<=65536 && noisy.elapsed<10.);
 Printf.printf "fixed oracle tests: %d passed; proof_elapsed=%.4fs flood_elapsed=%.4fs\n" !count proof.elapsed noisy.elapsed
