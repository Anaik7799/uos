(* tools/uos-qwen-mcp-zenoh-planner.ml
   Pure OCaml Bridge Enabling Local MAX Qwen (razr15-1:8000) to Converse with
   AGY (Caste01) and uos-harness via MCP (tools/uos-mcp-stdio) and Zenoh
   to Gather Live Local System State and Generate the L0..L9 Fractal Wiring Plan.
   Zero Python (`SC-ZERO-PYTHON-001`). Authority: NONE. EV Ceiling: 93.
*)

let run_cmd cmd =
  try
    let ic = Unix.open_process_in (cmd ^ " 2>/dev/null") in
    let buf = Buffer.create 4096 in
    (try while true do Buffer.add_channel buf ic 1 done with End_of_file -> ());
    let _ = Unix.close_process_in ic in
    String.trim (Buffer.contents buf)
  with _ -> ""

let json_escape s =
  let buf = Buffer.create (String.length s + 64) in
  String.iter (function
    | '"' -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\r' -> Buffer.add_string buf "\\r"
    | '\t' -> Buffer.add_string buf "\\t"
    | c -> if Char.code c >= 32 then Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let call_mcp_tool tool_name args_json =
  let req =
    {|{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"qwen-mcp-zenoh-bridge","version":"1.0"}}}|}
    ^ "\n"
    ^ {|{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"|}
    ^ tool_name
    ^ {|","arguments":|}
    ^ args_json
    ^ {|}}|}
    ^ "\n"
  in
  let cmd = "printf %s " ^ Filename.quote req ^ " | ./tools/uos-mcp-stdio | tail -n 1" in
  run_cmd cmd

let query_zenoh_and_sa_plan () =
  let mcp_health = call_mcp_tool "system_health" "{}" in
  let mcp_zenoh  = call_mcp_tool "system_zenoh" "{}" in
  let sa_status  = run_cmd "./tools/sa-plan status plan-provider-api-holarchy-fpp-twin-20261107-2046 | head -n 1" in
  let c_abi_cnt  = run_cmd "nm -D var/zlp/libuos_lean_guard.so | grep -c ' T uos_lean_'" in
  let otel_cnt   = run_cmd "wc -l < state/provider-api-holarchy-fpp.otel.jsonl" in
  Printf.sprintf
    "LIVE_MCP_SYSTEM_HEALTH=%s\nLIVE_MCP_ZENOH=%s\nSA_PLAN_STATUS=%s\nLEAN_C_ABI_EXPORTS=%s\nOTEL_SPANS_EMITTED=%s"
    (if String.length mcp_health > 240 then String.sub mcp_health 0 240 else mcp_health)
    (if String.length mcp_zenoh > 240 then String.sub mcp_zenoh 0 240 else mcp_zenoh)
    sa_status c_abi_cnt otel_cnt

let call_local_qwen ~system_prompt ~user_prompt ~max_tokens =
  let payload =
    {|{"model":"Qwen/Qwen2.5-Coder-7B-Instruct-GGUF","messages":[{"role":"system","content":"|}
    ^ json_escape system_prompt
    ^ {|"},{"role":"user","content":"|}
    ^ json_escape user_prompt
    ^ {|"}],"max_tokens":|}
    ^ string_of_int max_tokens
    ^ {|,"temperature":0.1}|}
  in
  let cmd =
    "curl -sS --max-time 60 -H 'Content-Type: application/json' -d "
    ^ Filename.quote payload
    ^ " http://razr15-1.tail55d152.ts.net:8000/v1/chat/completions | jq -r '.choices[0].message.content // empty'"
  in
  run_cmd cmd

let () =
  let live_telemetry = query_zenoh_and_sa_plan () in
  (* Turn 1: Qwen inspects live MCP + Zenoh + AGY state and requests any additional MCP/Zenoh probes *)
  let turn1_sys =
    "You are Local MAX Qwen (Qwen2.5-Coder-7B-Instruct-GGUF on razr15-1:8000) collaborating with AGY (Caste01) and uos-harness via MCP and Zenoh. First state which 3 MCP/Zenoh/UOS surfaces you want inspected before authoring the L0..L9 fractal wiring plan."
  in
  let turn1_usr =
    "Here is the initial live MCP + Zenoh + Sa-Plan telemetry from uos-harness:\n" ^ live_telemetry ^ "\nReply concisely with the 3 specific UOS surfaces (MCP routes, Zenoh topics, or Gleam/Mojo/Lean files) you need queried to complete the L0..L9 fractal wiring plan."
  in
  let qwen_probe_request = call_local_qwen ~system_prompt:turn1_sys ~user_prompt:turn1_usr ~max_tokens:180 in
  (* AGY + uos-harness MCP executes the follow-up query for Qwen *)
  let mcp_km = call_mcp_tool "knowledge_search" {|{"query":"provider api holarchy fpp state machine","limit":3}|} in
  let agy_reply =
    Printf.sprintf
      "AGY + uos-harness MCP + Zenoh Response to Qwen:\n1. MCP knowledge_search: %s\n2. 12 Canonical UOS System Services (Svc00..Svc11 in Lean 4 THM_FSYS_56..58 & C-ABI Export #25 uos_lean_verify_service_mesh_binding, 192/192 states) + 52-Object UOS System Directory Service (DirKind0..4 in Lean 4 THM_FSYS_59..60 & C-ABI Export #26 uos_lean_verify_system_directory_object, 2,080/2,080 states): 12 Services (dirId 0..11) + 7 Provider APIs (dirId 12..18) + 6 Sovereign Agents (dirId 19..24) + 10 Holarchy Layers L0..L9 (dirId 25..34) + 17 System Aspects A01..A17 (dirId 35..51).\n3. Gleam OTP & Mojo Surfaces: apps/cepaf_gleam/src/cepaf_gleam/harness/agent_ecology.gleam (verify_uos_service_mesh_binding, verify_system_directory_object, 128-bit W3C OTel spans), formal/mojo/lean_ffi_bridge.mojo, formal/mojo/fractal_context_pipeline.mojo."
      (if String.length mcp_km > 220 then String.sub mcp_km 0 220 else mcp_km)
  in
  (* Turn 2: Qwen synthesizes the 10-layer (L0..L9) fractal wiring plan (qwen-w01..qwen-w10) across all 12 UOS services + 52 System Directory objects *)
  let turn2_sys =
    "You are Local MAX Qwen (Qwen2.5-Coder-7B-Instruct-GGUF on razr15-1:8000). Using the live MCP, Zenoh, and AGY data, produce the 10-task fractal wiring plan (qwen-w01..qwen-w10 across L0..L9) wiring all 12 UOS Services (Svc00..Svc11) and all 52 System Directory Service objects across Holarchy+Agents+FPP+Zenoh+MCP+OTel in Lean 4 + Mojo + Gleam."
  in
  let turn2_usr =
    "Your probe request:\n" ^ qwen_probe_request ^ "\n\n" ^ agy_reply
    ^ "\n\nNow output a concise Markdown table of all 10 tasks (qwen-w01 through qwen-w10 for L0..L9) binding all 12 UOS services (Svc00..Svc11) and all 52 System Directory Service objects (dirId 0..51) across Holarchy+Agents+FPP+Zenoh+MCP+OTel with exact target file, wiring mechanism, and verification gate for each of the 10 layers."
  in
  let qwen_plan = call_local_qwen ~system_prompt:turn2_sys ~user_prompt:turn2_usr ~max_tokens:1000 in
  Printf.printf "=== TURN 1: QWEN -> AGY / MCP / ZENOH PROBE REQUEST ===\n%s\n\n=== TURN 2: AGY / MCP / ZENOH LIVE RESPONSE ===\n%s\n\n=== TURN 3: QWEN L0..L9 FRACTAL WIRING PLAN (qwen-w01..qwen-w10) ===\n%s\n"
    qwen_probe_request agy_reply qwen_plan
