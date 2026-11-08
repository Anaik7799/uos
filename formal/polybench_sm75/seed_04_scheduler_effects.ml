(* formal/polybench_sm75/seed_04_scheduler_effects.ml
   PolyBench-SM75 Language 4 (OCaml 5 Algebraic Effects & Tail-Call Discipline)
   Verifies native OCaml 5 Effect.Deep.match_with cooperative Yield generator
   without legacy OCaml 4 Lwt/fork patterns. *)

open Effect
open Effect.Deep

type _ Effect.t += Yield : int -> unit Effect.t

let run_producer (limit : int) : int list =
  let acc = ref [] in
  let comp () =
    for i = 1 to limit do
      perform (Yield (i * i))
    done
  in
  match_with comp ()
    { retc = (fun () -> List.rev !acc);
      exnc = raise;
      effc = (fun (type a) (eff : a Effect.t) ->
        match eff with
        | Yield v -> Some (fun (k : (a, _) continuation) ->
            acc := v :: !acc;
            continue k ())
        | _ -> None) }

let () =
  let res = run_producer 5 in
  assert (res = [1; 4; 9; 16; 25]);
  let formatted = String.concat ";" (List.map string_of_int res) in
  Printf.printf "POLYBENCH_OCAML5_EFFECTS_PASS:[%s]\n" formatted
