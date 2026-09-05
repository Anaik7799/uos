open QCheck
open Hermes_sysml

module StringQueuePort : Sysml_algebra.PORT with type msg = string and type t = string Queue.t = struct
  type msg = string
  type t = string Queue.t
  
  let send q m = Queue.add m q
  
  let recv q = Queue.take_opt q
end

module AgentContextPort : Sysml_algebra.PORT with type msg = string and type t = unit = struct
  type msg = string
  type t = unit
  
  let send () m = 
    (* Simulate processing the payload, just making sure it doesn't crash *)
    ignore (String.length m)
    
  let recv () = None
end

module Injector = Sysml_algebra.Connect(StringQueuePort)(AgentContextPort)

let test_fuzz_oml_payloads =
  Test.make ~name:"fuzz_oml_semantic_context_ports" (string)
    (fun payload ->
       let q = Queue.create () in
       StringQueuePort.send q payload;
       Injector.sync q ();
       true)

let () =
  let seed = Qcheck_seed.configure () in
  Qcheck_seed.disclose seed;
  let code = QCheck_base_runner.run_tests [
    test_fuzz_oml_payloads;
  ] in
  let self = Suite_telemetry.observe ~suite:"test_agent_fuzz" ~passed:(if code = 0 then 1 else 0) ~failed:code ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_sysml ]);
  exit (Suite_telemetry.exit_code self)
