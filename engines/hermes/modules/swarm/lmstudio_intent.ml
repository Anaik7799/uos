(* L1 Declarative Intent: Local LM Studio (Gemma) Pipeline Envelope *)

type model_family =
  | Gemma_4_Multimodal
  | PaliGemma_Vision
  | CodeGemma
  | FunctionGemma
  | EmbeddingGemma
  | Generic_OpenAI_Compatible of string

type generation_params = {
  temperature : float;
  top_p : float;
  max_tokens : int option;
  stop_sequences : string list;
  json_schema_structured_output : bool;
}

type fine_tuning_strategy =
  | Zero_Shot
  | QLoRA_Adapter of string (* path or id to the LoRA weights *)
  | System_Prompt_Only

type execution_endpoint =
  | Native_LM_Studio_Chat
  | OpenAI_Chat_Completions
  | Anthropic_Messages

type lmstudio_topology = {
  api_host : string;
  api_port : int;
  endpoint : execution_endpoint;
  model_id : string;
  family : model_family;
}

type telemetry_hook =
  | Log_Token_Velocity
  | Capture_Context_Window_Usage
  | Trace_Function_Calls
  | Emit_To_Zenoh of string

type lmstudio_envelope = {
  topology : lmstudio_topology;
  params : generation_params;
  tuning : fine_tuning_strategy;
  telemetry : telemetry_hook list;
  max_retry : int;
  timeout_ms : int;
}

let default_gemma_4_envelope = {
  topology = {
    api_host = "100.114.9.28";
    api_port = 1234;
    endpoint = OpenAI_Chat_Completions;
    model_id = "google/gemma-4-e4b";
    family = Gemma_4_Multimodal;
  };
  params = {
    temperature = 0.7;
    top_p = 0.95;
    max_tokens = Some 8192;
    stop_sequences = [];
    json_schema_structured_output = true;
  };
  tuning = Zero_Shot;
  telemetry = [ Log_Token_Velocity; Capture_Context_Window_Usage ];
  max_retry = 3;
  timeout_ms = 30000;
}

let synthesize_curl_command (env : lmstudio_envelope) (prompt : string) : string =
  let url_path = match env.topology.endpoint with
    | Native_LM_Studio_Chat -> "/api/v1/chat"
    | OpenAI_Chat_Completions -> "/v1/chat/completions"
    | Anthropic_Messages -> "/v1/messages"
  in
  let url = Printf.sprintf "http://%s:%d%s" env.topology.api_host env.topology.api_port url_path in
  Printf.sprintf
    "curl -s --connect-timeout %d --max-time %d -X POST %s -H \"Content-Type: application/json\" -d '{\"model\": \"%s\", \"messages\": [{\"role\": \"user\", \"content\": \"%s\"}], \"temperature\": %f}'"
    (env.timeout_ms / 1000)
    (env.timeout_ms / 1000)
    url
    env.topology.model_id
    prompt
    env.params.temperature
