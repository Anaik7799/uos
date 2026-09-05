(* The multiway explorer: memoized states (the HashLife collapse), exact path
   counts, confluence as causal invariance -- and, per the proven-not-differential
   trap, the chaos layer proves the detector can FIRE: a non-commutative system
   is reported non-confluent, a cyclic one is an Error, a cap hit is an Error. *)

let passed = ref 0
let failures = ref []

let check condition label detail =
  if condition then incr passed
  else failures := (if detail = "" then label else label ^ " :: " ^ detail) :: !failures

(* n independent commuting moves: flip bit i from 0 to 1. States = subsets
   (2^n), maximal paths = n!, single terminal = all-ones. The canonical small
   ruliad slice. *)
let independent n : (bool array, int) Ruliad.system =
  { initial = Array.make n false;
    moves = (fun s -> List.filter (fun i -> not s.(i)) (List.init n Fun.id));
    apply = (fun s i -> let t = Array.copy s in t.(i) <- true; t);
    canonical = (fun s -> String.concat "" (List.map (fun b -> if b then "1" else "0") (Array.to_list s))) }

let factorial n = List.fold_left ( * ) 1 (List.init n (fun i -> i + 1))

(* ------------------------------------------------------------- UNIT layer *)

let unit_layer () =
  (match Ruliad.explore (independent 3) with
  | Ok g ->
      check (g.state_count = 8) "UNIT 3 independent moves reach 2^3 states" (string_of_int g.state_count);
      check (g.path_count = 6) "UNIT 3! maximal paths" (string_of_int g.path_count);
      check g.confluent "UNIT independent moves are confluent" "";
      check (List.length g.terminals = 1) "UNIT one terminal" "";
      check (g.max_depth = 3) "UNIT depth = move count" (string_of_int g.max_depth);
      check (g.edge_count = 12) "UNIT edges = sum over states of applicable moves" (string_of_int g.edge_count);
      (* The reachable list IS the signature: complete and duplicate-free. *)
      check (List.length g.reachable = g.state_count) "UNIT reachable list covers every state" "";
      let keys = List.map (fun s -> String.concat "" (List.map (fun b -> if b then "1" else "0") (Array.to_list s))) g.reachable in
      check (List.length (List.sort_uniq compare keys) = 8) "UNIT reachable states are distinct" ""
  | Error e -> check false "UNIT explore succeeds" e);
  (* A terminal-only system: one state, one (empty) path. *)
  (match Ruliad.explore (independent 0) with
  | Ok g ->
      check (g.state_count = 1 && g.path_count = 1 && g.confluent) "UNIT empty system is trivially confluent" ""
  | Error e -> check false "UNIT empty system explores" e)

(* --------------------------------------------------------- PROPERTY layer *)

let property_layer () =
  (* The HashLife collapse, quantified: n! paths live on 2^n memoized states. *)
  List.iter
    (fun n ->
      match Ruliad.explore (independent n) with
      | Ok g ->
          check (g.state_count = 1 lsl n) "PROPERTY states = 2^n" (string_of_int n);
          check (g.path_count = factorial n) "PROPERTY paths = n!" (string_of_int n);
          check g.confluent "PROPERTY commuting moves are causally invariant" ""
      | Error e -> check false "PROPERTY explore succeeds" e)
    [ 1; 2; 4; 6; 8 ];
  (* Join-fold system: folding verdict ranks with max (commutative) from any
     order is confluent -- the config-algebra shape in miniature. *)
  let ranks = [| 2; 0; 3; 1 |] in
  let fold_system : (int list * int, int) Ruliad.system =
    { initial = ([ 0; 1; 2; 3 ], 0);
      moves = (fun (remaining, _) -> remaining);
      apply = (fun (remaining, acc) i -> (List.filter (( <> ) i) remaining, max acc ranks.(i)));
      canonical =
        (fun (remaining, acc) ->
          String.concat "," (List.map string_of_int (List.sort compare remaining))
          ^ "|" ^ string_of_int acc) }
  in
  (match Ruliad.explore fold_system with
  | Ok g ->
      check g.confluent "PROPERTY a commutative fold is confluent under all orders" "";
      check (g.path_count = 24) "PROPERTY 4! orderings" (string_of_int g.path_count)
  | Error e -> check false "PROPERTY fold explores" e)

(* ------------------------------------------------------------ CHAOS layer *)

let chaos_layer () =
  (* The detector can FIRE: a non-commutative fold ("last move wins") has
     order-dependent terminals -> NOT confluent. *)
  let last_wins : (int list * int, int) Ruliad.system =
    { initial = ([ 1; 2 ], 0);
      moves = (fun (remaining, _) -> remaining);
      apply = (fun (remaining, _) i -> (List.filter (( <> ) i) remaining, i));
      canonical =
        (fun (remaining, acc) ->
          String.concat "," (List.map string_of_int (List.sort compare remaining))
          ^ "|" ^ string_of_int acc) }
  in
  (match Ruliad.explore last_wins with
  | Ok g ->
      check (not g.confluent) "CHAOS a non-commutative system is detected as non-confluent" "";
      check (List.length g.terminals = 2) "CHAOS both order-dependent terminals surface" ""
  | Error e -> check false "CHAOS last-wins explores" e);
  (* A cyclic system is an Error, not a hang. *)
  let cyclic : (int, unit) Ruliad.system =
    { initial = 0;
      moves = (fun _ -> [ () ]);
      apply = (fun s () -> 1 - s);
      canonical = string_of_int }
  in
  (match Ruliad.explore cyclic with
  | Error _ -> incr passed
  | Ok _ -> check false "CHAOS a cyclic system must be an Error" "");
  (* The state cap fails closed with an Error, never a silent truncation. *)
  (match Ruliad.explore ~max_states:5 (independent 4) with
  | Error _ -> incr passed
  | Ok _ -> check false "CHAOS the state cap must refuse, not truncate" "")

(* ------------------------------------------------------------- FUZZ layer *)

let fuzz_layer () =
  Random.init 20260808;
  let survived = ref 0 in
  for _ = 1 to 100 do
    let n = 1 + Random.int 6 in
    (* random commuting weights folded with max: always confluent, always n! paths *)
    let weights = Array.init n (fun _ -> Random.int 10) in
    let system : (int list * int, int) Ruliad.system =
      { initial = (List.init n Fun.id, 0);
        moves = (fun (remaining, _) -> remaining);
        apply = (fun (remaining, acc) i -> (List.filter (( <> ) i) remaining, max acc weights.(i)));
        canonical =
          (fun (remaining, acc) ->
            String.concat "," (List.map string_of_int (List.sort compare remaining))
            ^ "|" ^ string_of_int acc) }
    in
    match Ruliad.explore system with
    | Ok g when g.confluent && g.path_count = factorial n -> incr survived
    | Ok _ -> check false "FUZZ commutative fold must be confluent with n! paths" ""
    | Error e -> check false "FUZZ explore must not fail" e
  done;
  check (!survived = 100) "FUZZ 100 random commutative systems behave" (string_of_int !survived)

let () =
  print_endline "ruliad suite";
  List.iter
    (fun (name, layer) -> layer (); Printf.printf "  %-12s done\n" name)
    [ ("unit", unit_layer); ("property", property_layer); ("chaos", chaos_layer);
      ("fuzz", fuzz_layer) ];
  Printf.printf "\npassed: %d   failed: %d\n" !passed (List.length !failures);
  List.iter (fun f -> print_endline ("  FAIL  " ^ f)) (List.rev !failures);
  let self =
    Suite_telemetry.observe ~suite:"test_ruliad" ~passed:!passed
      ~failed:(List.length !failures) ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_ruliad ]);
  exit (Suite_telemetry.exit_code self)
