type fpp_port = { name: string; typ: string }
type fpp_component = { name: string; inputs: fpp_port list; outputs: fpp_port list }

let lmstudio_engine_comp = {
  name = "LMStudio_Engine";
  inputs = [ {name = "prompt_in"; typ = "Text/Prompt"} ];
  outputs = [ {name = "response_out"; typ = "Text/Completion"} ];
}

let zenoh_telemetry_comp = {
  name = "Zenoh_Telemetry";
  inputs = [ {name = "telemetry_in"; typ = "JSON/Telemetry"} ];
  outputs = [];
}
