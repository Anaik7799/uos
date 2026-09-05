type context_reference = {
  ref_id : string;
  kind : string;
  uri : string;
  content : string;
  token_count : int;
}

type context_state = {
  active_references : context_reference list;
  total_tokens : int;
  max_context_tokens : int;
}

let create ~max_context_tokens =
  let max_context_tokens = if max_context_tokens < 0 then 0 else max_context_tokens in
  { active_references = []; total_tokens = 0; max_context_tokens }

let add_reference st ref_item =
  let token_count = if ref_item.token_count < 0 then 0 else ref_item.token_count in
  let ref_item' = { ref_item with token_count } in
  let filtered = List.filter (fun r -> r.ref_id <> ref_item.ref_id) st.active_references in
  let new_refs = filtered @ [ ref_item' ] in
  let total = List.fold_left (fun acc r -> acc + r.token_count) 0 new_refs in
  { st with active_references = new_refs; total_tokens = total }

let remove_reference st ~ref_id =
  let filtered = List.filter (fun r -> r.ref_id <> ref_id) st.active_references in
  let total = List.fold_left (fun acc r -> acc + r.token_count) 0 filtered in
  { st with active_references = filtered; total_tokens = total }

let process ~model_id ~messages =
  let sanitized = Message_hygiene.sanitize_messages ~model_id messages in
  `Assoc [ ("messages", `List sanitized); ("model", `String model_id) ]
