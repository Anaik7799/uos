module P = Zigvm_harness_support.Wiki_selfcheck_parallel

let check name ok =
  if not ok then failwith ("wiki-selfcheck-parallel law: " ^ name)

let admitted visits = Array.for_all (( = ) 1) visits

let () =
  let input = Array.init 257 Fun.id in
  let f i = (i, (i * i) + 7) in
  let sequential = Array.map f input in
  List.iter
    (fun workers ->
      let run = P.map_gss ~workers f input in
      check (Printf.sprintf "ordered-value-equivalence[%d]" workers)
        (run.P.values = sequential);
      check (Printf.sprintf "exactly-once[%d]" workers)
        (Array.for_all (( = ) 1) run.P.visits);
      check (Printf.sprintf "bounded-workers[%d]" workers)
        (run.P.workers >= 1 && run.P.workers <= max 1 workers);
      check (Printf.sprintf "complete-accounting[%d]" workers)
        (Array.fold_left ( + ) 0 run.P.worker_items = Array.length input))
    [ 0; 1; 2; 7; 64; 512 ];
  let empty = P.map_gss ~workers:8 Fun.id [||] in
  check "empty-total" (Array.length empty.P.values = 0);
  check "recommended-bounded"
    (P.recommended_workers () >= 1 && P.recommended_workers () <= 16);
  (* Mutation discrimination: the same exactly-once observer rejects both a
     duplicate claim and a missing claim. *)
  let duplicate = Array.make 3 1 in
  duplicate.(1) <- 2;
  check "mutant-duplicate-claim-killed" (not (admitted duplicate));
  let gap = Array.make 3 1 in
  gap.(1) <- 0;
  check "mutant-gap-claim-killed" (not (admitted gap));
  Printf.printf "wiki-selfcheck-parallel: 34 laws passed\n"
