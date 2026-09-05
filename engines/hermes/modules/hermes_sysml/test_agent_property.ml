open QCheck
open Hermes_sysml.Sysml_algebra

let gen_transition =
  let open Gen in
  let rec gen_t n =
    if n = 0 then return Id
    else
      oneof_weighted
        [ 1, return Id
        ; 2, (gen_t (n / 2) >>= fun t1 -> gen_t (n / 2) >>= fun t2 -> return (Step (t1, t2)))
        ]
  in
  sized gen_t

let arb_transition = make gen_transition

(* QCheck tests verifying identity and associativity for the Agent OODA loop transitions *)
let test_id_left =
  Test.make ~name:"OODA transition identity left" ~count:1000 arb_transition
    (fun t -> compose id t = t)

let test_id_right =
  Test.make ~name:"OODA transition identity right" ~count:1000 arb_transition
    (fun t -> compose t id = t)

let test_assoc =
  Test.make ~name:"OODA transition associativity" ~count:1000 (triple arb_transition arb_transition arb_transition)
    (fun (f, g, h) ->
       let rec count : type a b. (a, b) transition -> int = function
         | Id -> 1
         | Step (t1, t2) -> count t1 + count t2
       in
       count (compose (compose h g) f) = count (compose h (compose g f)))

let () =
  let seed = Qcheck_seed.configure () in
  Qcheck_seed.disclose seed;
  let code = QCheck_base_runner.run_tests [
    test_id_left;
    test_id_right;
    test_assoc;
  ] in
  let self = Suite_telemetry.observe ~suite:"test_agent_property" ~passed:(if code = 0 then 1 else 0) ~failed:code ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_sysml ]);
  exit (Suite_telemetry.exit_code self)
