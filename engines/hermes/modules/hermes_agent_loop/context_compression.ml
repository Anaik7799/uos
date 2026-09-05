type compression_strategy =
  | Truncate_oldest of { keep_last_n : int }
  | Summarize_history of { summary_prefix : string }
  | Cache_ephemeral_prompts

type compression_result = {
  compressed_messages : Yojson.Safe.t list;
  original_count : int;
  compressed_count : int;
  tokens_saved : int;
}

let is_system_msg msg =
  match msg with
  | `Assoc fields -> (
      match List.assoc_opt "role" fields with
      | Some (`String "system") | Some (`String "developer") -> true
      | _ -> false)
  | _ -> false

let compress_history ~strategy messages =
  let original_count = List.length messages in
  match strategy with
  | Truncate_oldest { keep_last_n } ->
      let keep_n = if keep_last_n < 0 then 0 else keep_last_n in
      let system_header, normal_msgs =
        match messages with
        | first :: rest when is_system_msg first -> (Some first, rest)
        | msgs -> (None, msgs)
      in
      let total_normal = List.length normal_msgs in
      let truncated_normal =
        if total_normal <= keep_n then normal_msgs
        else
          let drop_count = total_normal - keep_n in
          let rec drop n lst =
            if n <= 0 then lst
            else match lst with [] -> [] | _ :: r -> drop (n - 1) r
          in
          drop drop_count normal_msgs
      in
      let compressed_messages =
        match system_header with
        | Some sys -> sys :: truncated_normal
        | None -> truncated_normal
      in
      let compressed_count = List.length compressed_messages in
      let tokens_saved = max 0 ((original_count - compressed_count) * 10) in
      { compressed_messages; original_count; compressed_count; tokens_saved }

  | Summarize_history { summary_prefix } ->
      let system_header, normal_msgs =
        match messages with
        | first :: rest when is_system_msg first -> (Some first, rest)
        | msgs -> (None, msgs)
      in
      if List.length normal_msgs <= 1 then
        { compressed_messages = messages; original_count; compressed_count = original_count; tokens_saved = 0 }
      else
        let summary_text = summary_prefix ^ " [summarized " ^ string_of_int (List.length normal_msgs) ^ " turns]" in
        let summary_msg = `Assoc [ ("role", `String "user"); ("content", `String summary_text) ] in
        let compressed_messages =
          match system_header with
          | Some sys -> [ sys; summary_msg ]
          | None -> [ summary_msg ]
        in
        let compressed_count = List.length compressed_messages in
        let tokens_saved = max 0 ((original_count - compressed_count) * 15) in
        { compressed_messages; original_count; compressed_count; tokens_saved }

  | Cache_ephemeral_prompts ->
      let annotate msg =
        match msg with
        | `Assoc fields ->
            let cache_control = ("cache_control", `Assoc [ ("type", `String "ephemeral") ]) in
            `Assoc (cache_control :: fields)
        | _ -> msg
      in
      let compressed_messages = List.map annotate messages in
      { compressed_messages; original_count; compressed_count = original_count; tokens_saved = 50 }

let compress ~model_id ~messages =
  let sanitized = Message_hygiene.sanitize_messages ~model_id messages in
  `Assoc [ ("messages", `List sanitized); ("model", `String model_id) ]
