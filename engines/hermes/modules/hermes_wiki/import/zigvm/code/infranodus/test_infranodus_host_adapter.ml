module Host = Zigvm_harness_support.Infranodus_host_adapter
module Acquisition = Zigvm_harness_support.Infranodus_acquisition

let require condition message = if not condition then failwith message

let () =
  let hosts = [ Host.Browser; Host.Obsidian; Host.Ide; Host.N8n ] in
  List.iter
    (fun host ->
      let payload = Host.{ host; external_id = Host.host_name host ^ "-1"; title = "Host evidence";
                           body = (if host = Browser then "" else "graph host evidence");
                           locator = (if host = Browser then Some "https://example.test" else None); tags = [ "graph" ] } in
      let request = match Host.to_request payload with Ok value -> value | Error message -> failwith message in
      require (request.metadata <> []) "host provenance must survive mapping";
      let round_trip = match Host.of_yojson (Host.to_yojson payload) with Ok value -> value | Error message -> failwith message in
      require (round_trip = payload) "host payload codec must round-trip")
    hosts;
  let obsidian = Host.{ host = Obsidian; external_id = "note"; title = "Note"; body = "[[graph]] evidence"; locator = None; tags = [] } in
  let request = match Host.to_request obsidian with Ok value -> value | Error message -> failwith message in
  (match Acquisition.acquire [ request ] with Ok result -> require (result.statements <> []) "host request must enter acquisition" | Error _ -> failwith "local host acquisition failed");
  print_endline "infranodus host adapter laws: pass"
