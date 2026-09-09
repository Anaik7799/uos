(* ==============================================================================
   [C3I-SIL6-MSTS] UOS HIGH-PERFORMANCE TELEGRAM CYBERNETIC CLIENT
   ==============================================================================
   <c3i-module>
     <identity>
       <module>tools/telegram_client.ml</module>
       <authority>UOS-CANONICAL-AGENT-POLICY</authority>
     </identity>
     <fractal-topology>
       <layer>L7_FEDERATION</layer>
       <mesh-domain>Telegram Bot API & WebApp Gateway</mesh-domain>
     </fractal-topology>
     <compliance>
       <criticality>DAL-B / SIL-6 / ISOLATED</criticality>
       <stamp-controls>
         SC-ZENOH-005, SC-ZMOF-001, SC-JIDOKA-001, SC-CHECKLIST-001
       </stamp-controls>
     </compliance>
   </c3i-module>
   ==============================================================================
   Full Telegram surface client in pure OCaml:
   - Typed update parsing (Messages, Callback Queries, Reactions, Forum Topics)
   - Bounded SQLite WAL state persistence & update deduplication
   - Cryptokit HMAC-SHA256 Mini App signature validation
   - MarkdownV2 escaping and 4096-byte safe draft chunking
   - Interactive 2oo3 approval buttons and callback handling
   - Eclipse Zenoh pub/sub mesh bridge (ingress & egress)
   ============================================================================== *)

open Yojson.Safe.Util

let to_int64 = function
  | `Int i -> Int64.of_int i
  | `Intlit s -> Int64.of_string s
  | json -> failwith ("Expected int64, got " ^ Yojson.Safe.to_string json)

let root = "/home/an/NAS-setup/uos"
let default_smriti = "/home/an/dev/ver/c3i/data/smriti/Smriti.db"
let state_db_path = root ^ "/var/telegram/state.sqlite3"
let zenoh_rest_default = "http://127.0.0.1:8080"

(* ----------------------------------------------------------------------------
   1. State Persistence & SQLite WAL
   ---------------------------------------------------------------------------- *)

let init_db () =
  let db = Sqlite3.db_open state_db_path in
  let _ = Sqlite3.exec db "PRAGMA journal_mode = WAL;" in
  let _ = Sqlite3.exec db "PRAGMA synchronous = NORMAL;" in
  let _ = Sqlite3.exec db "
    CREATE TABLE IF NOT EXISTS preferences (
      key TEXT PRIMARY KEY,
      value TEXT,
      updated_at INTEGER
    );
    CREATE TABLE IF NOT EXISTS processed_updates (
      update_id INTEGER PRIMARY KEY,
      processed_at INTEGER
    );
    CREATE TABLE IF NOT EXISTS processed_sutra_events (
      event_id TEXT PRIMARY KEY,
      processed_at INTEGER
    );
  " in
  db

let now_ms () = Int64.of_float (Unix.gettimeofday () *. 1000.0)

let get_db_preference key =
  let db = init_db () in
  let stmt = Sqlite3.prepare db "SELECT value FROM preferences WHERE key = ?;" in
  let _ = Sqlite3.bind_text stmt 1 key in
  let res =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> Some (Sqlite3.column_text stmt 0)
    | _ -> None
  in
  let _ = Sqlite3.finalize stmt in
  let _ = Sqlite3.db_close db in
  res

let set_db_preference key value =
  let db = init_db () in
  let stmt = Sqlite3.prepare db "INSERT OR REPLACE INTO preferences (key, value, updated_at) VALUES (?, ?, ?);" in
  let _ = Sqlite3.bind_text stmt 1 key in
  let _ = Sqlite3.bind_text stmt 2 value in
  let _ = Sqlite3.bind_int64 stmt 3 (now_ms ()) in
  let _ = Sqlite3.step stmt in
  let _ = Sqlite3.finalize stmt in
  let _ = Sqlite3.db_close db in
  ()

let is_update_processed update_id =
  let db = init_db () in
  let stmt = Sqlite3.prepare db "SELECT 1 FROM processed_updates WHERE update_id = ?;" in
  let _ = Sqlite3.bind_int64 stmt 1 update_id in
  let res =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> true
    | _ -> false
  in
  let _ = Sqlite3.finalize stmt in
  let _ = Sqlite3.db_close db in
  res

let mark_update_processed update_id =
  let db = init_db () in
  let stmt = Sqlite3.prepare db "INSERT OR IGNORE INTO processed_updates (update_id, processed_at) VALUES (?, ?);" in
  let _ = Sqlite3.bind_int64 stmt 1 update_id in
  let _ = Sqlite3.bind_int64 stmt 2 (now_ms ()) in
  let _ = Sqlite3.step stmt in
  let _ = Sqlite3.finalize stmt in
  let _ = Sqlite3.db_close db in
  ()

let is_sutra_event_processed event_id =
  let db = init_db () in
  let stmt = Sqlite3.prepare db "SELECT 1 FROM processed_sutra_events WHERE event_id = ?;" in
  let _ = Sqlite3.bind_text stmt 1 event_id in
  let res =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> true
    | _ -> false
  in
  let _ = Sqlite3.finalize stmt in
  let _ = Sqlite3.db_close db in
  res

let mark_sutra_event_processed event_id =
  let db = init_db () in
  let stmt = Sqlite3.prepare db "INSERT OR IGNORE INTO processed_sutra_events (event_id, processed_at) VALUES (?, ?);" in
  let _ = Sqlite3.bind_text stmt 1 event_id in
  let _ = Sqlite3.bind_int64 stmt 2 (now_ms ()) in
  let _ = Sqlite3.step stmt in
  let _ = Sqlite3.finalize stmt in
  let _ = Sqlite3.db_close db in
  ()

let get_smriti_preference key =
  if Sys.file_exists default_smriti then
    try
      let db = Sqlite3.db_open ~mode:`READONLY default_smriti in
      let stmt = Sqlite3.prepare db "SELECT value FROM UserPreferences WHERE key = ?;" in
      let _ = Sqlite3.bind_text stmt 1 key in
      let res =
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW -> Some (Sqlite3.column_text stmt 0)
        | _ -> None
      in
      let _ = Sqlite3.finalize stmt in
      let _ = Sqlite3.db_close db in
      res
    with _ -> None
  else None

let get_preference key =
  match Sys.getenv_opt (String.uppercase_ascii key) with
  | Some v when String.trim v <> "" -> String.trim v
  | _ ->
      match get_db_preference key with
      | Some v when String.trim v <> "" -> String.trim v
      | _ ->
          match get_smriti_preference key with
          | Some v when String.trim v <> "" -> String.trim v
          | _ -> ""

(* ----------------------------------------------------------------------------
   2. Cryptokit HMAC-SHA256 for Mini App Validation
   ---------------------------------------------------------------------------- *)

let sha256_hex data =
  Cryptokit.hash_string (Cryptokit.Hash.sha256 ()) data
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())

let hmac_sha256 ~key ~data =
  let hmac = Cryptokit.MAC.hmac_sha256 key in
  Cryptokit.hash_string hmac data

let hmac_sha256_hex ~key ~data =
  hmac_sha256 ~key ~data
  |> Cryptokit.transform_string (Cryptokit.Hexa.encode ())

let validate_telegram_init_data ~bot_token ~init_data =
  let pairs = String.split_on_char '&' init_data in
  let rec extract (hash_val, rest) = function
    | [] -> (hash_val, rest)
    | p :: ps ->
        match String.index_opt p '=' with
        | Some idx ->
            let k = String.sub p 0 idx in
            let v = String.sub p (idx + 1) (String.length p - idx - 1) in
            if k = "hash" then extract (Some v, rest) ps
            else extract (hash_val, (k, v) :: rest) ps
        | None -> extract (hash_val, rest) ps
  in
  let (given_hash, params) = extract (None, []) pairs in
  match given_hash with
  | None -> false
  | Some expected_hash ->
      let sorted = List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) params in
      let data_check_string =
        String.concat "\n" (List.map (fun (k, v) -> k ^ "=" ^ v) sorted)
      in
      let secret_key = hmac_sha256 ~key:"WebAppData" ~data:bot_token in
      let calculated_hash = hmac_sha256_hex ~key:secret_key ~data:data_check_string in
      String.lowercase_ascii calculated_hash = String.lowercase_ascii expected_hash

(* ----------------------------------------------------------------------------
   3. MarkdownV2 Escaper & Safe 4096-Byte Draft Chunking
   ---------------------------------------------------------------------------- *)

let escape_markdown_v2 text =
  let b = Buffer.create (String.length text * 2) in
  let special = "_*[]()~>#+-=|{}.!\\" in
  let in_code = ref false in
  let len = String.length text in
  let i = ref 0 in
  while !i < len do
    if !i + 2 < len && text.[!i] = '`' && text.[!i+1] = '`' && text.[!i+2] = '`' then begin
      in_code := not !in_code;
      Buffer.add_string b "```";
      i := !i + 3
    end else if text.[!i] = '`' then begin
      in_code := not !in_code;
      Buffer.add_char b '`';
      incr i
    end else begin
      let c = text.[!i] in
      if (not !in_code) && String.contains special c then
        Buffer.add_char b '\\';
      Buffer.add_char b c;
      incr i
    end
  done;
  Buffer.contents b

let chunk_text ?(max_bytes=4096) text =
  if String.length text <= max_bytes then [text]
  else begin
    let chunks = ref [] in
    let len = String.length text in
    let pos = ref 0 in
    while !pos < len do
      let remaining = len - !pos in
      if remaining <= max_bytes then begin
        chunks := String.sub text !pos remaining :: !chunks;
        pos := len
      end else begin
        let cut = ref (!pos + max_bytes) in
        let found = ref false in
        (* Scan backwards for newline *)
        let search_start = !cut in
        let search_floor = max !pos (!cut - 512) in
        let i = ref search_start in
        while !i >= search_floor && not !found do
          if text.[!i] = '\n' then begin
            cut := !i + 1;
            found := true
          end;
          decr i
        done;
        if not !found then begin
          (* Scan backwards for space *)
          let j = ref search_start in
          while !j >= search_floor && not !found do
            if text.[!j] = ' ' then begin
              cut := !j + 1;
              found := true
            end;
            decr j
          done
        end;
        let chunk_len = !cut - !pos in
        chunks := String.sub text !pos chunk_len :: !chunks;
        pos := !cut
      end
    done;
    List.rev !chunks
  end

(* ----------------------------------------------------------------------------
   4. Zenoh REST Mesh Client
   ---------------------------------------------------------------------------- *)

let zenoh_put ~endpoint key payload =
  try
    let url = endpoint ^ "/" ^ key in
    let cmd = Bos.Cmd.(v "curl" % "-s" % "-X" % "PUT" % "-H" % "Content-Type: application/json" % "-d" % payload % url) in
    match Bos.OS.Cmd.run_status cmd with
    | Ok (`Exited 0) -> true
    | _ -> false
  with _ -> false

(* ----------------------------------------------------------------------------
   5. Telegram Bot API Invocation Core
   ---------------------------------------------------------------------------- *)

let telegram_call ~token method_name (payload_json : Yojson.Safe.t) =
  let url = Printf.sprintf "https://api.telegram.org/bot%s/%s" token method_name in
  let body = Yojson.Safe.to_string payload_json in
  let cmd = Bos.Cmd.(v "curl" % "-s" % "--max-time" % "15" % "--connect-timeout" % "5" % "-X" % "POST" % "-H" % "Content-Type: application/json" % "-d" % body % url) in
  match Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.to_string with
  | Ok out ->
      (try Yojson.Safe.from_string out
       with ex -> `Assoc ["ok", `Bool false; "error", `String (Printexc.to_string ex)])
  | Error (`Msg e) ->
      `Assoc ["ok", `Bool false; "error", `String e]

let get_me ~token =
  telegram_call ~token "getMe" (`Assoc [])

let get_updates ~token ?(offset = -1L) ?(timeout = 2) () =
  let payload =
    if offset >= 0L then
      `Assoc ["offset", `Intlit (Int64.to_string offset); "timeout", `Int timeout]
    else
      `Assoc ["timeout", `Int timeout]
  in
  telegram_call ~token "getUpdates" payload

let send_message_raw ~token ~chat_id ?parse_mode ?message_thread_id ?reply_markup text =
  let fields = ref [
    "chat_id", `String chat_id;
    "text", `String text;
  ] in
  (match parse_mode with
   | Some pm -> fields := ("parse_mode", `String pm) :: !fields
   | None -> ());
  (match message_thread_id with
   | Some tid -> fields := ("message_thread_id", `Intlit (Int64.to_string tid)) :: !fields
   | None -> ());
  (match reply_markup with
   | Some rm -> fields := ("reply_markup", rm) :: !fields
   | None -> ());
  telegram_call ~token "sendMessage" (`Assoc !fields)

let send_message ~token ~chat_id ?parse_mode ?message_thread_id ?reply_markup text =
  let res = send_message_raw ~token ~chat_id ?parse_mode ?message_thread_id ?reply_markup text in
  match member "ok" res with
  | `Bool true -> res
  | _ when parse_mode <> None ->
      (* Fallback immediately to unformatted plaintext if Telegram rejected formatting entities *)
      send_message_raw ~token ~chat_id ?message_thread_id ?reply_markup text
  | _ -> res

let edit_message_text ~token ~chat_id ~message_id ?parse_mode ?reply_markup text =
  let fields = ref [
    "chat_id", `String chat_id;
    "message_id", `Intlit (Int64.to_string message_id);
    "text", `String text;
  ] in
  (match parse_mode with
   | Some pm -> fields := ("parse_mode", `String pm) :: !fields
   | None -> ());
  (match reply_markup with
   | Some rm -> fields := ("reply_markup", rm) :: !fields
   | None -> ());
  telegram_call ~token "editMessageText" (`Assoc !fields)

let delete_message ~token ~chat_id ~message_id =
  let payload = `Assoc [
    "chat_id", `String chat_id;
    "message_id", `Intlit (Int64.to_string message_id);
  ] in
  telegram_call ~token "deleteMessage" payload

let send_chat_action ~token ~chat_id ?message_thread_id action_str =
  let fields = ref [
    "chat_id", `String chat_id;
    "action", `String action_str;
  ] in
  (match message_thread_id with
   | Some tid -> fields := ("message_thread_id", `Intlit (Int64.to_string tid)) :: !fields
   | None -> ());
  telegram_call ~token "sendChatAction" (`Assoc !fields)

let set_message_reaction ~token ~chat_id ~message_id emoji =
  let reaction = `List [
    `Assoc ["type", `String "emoji"; "emoji", `String emoji]
  ] in
  let payload = `Assoc [
    "chat_id", `String chat_id;
    "message_id", `Intlit (Int64.to_string message_id);
    "reaction", reaction;
  ] in
  telegram_call ~token "setMessageReaction" payload

let answer_callback_query ~token ~callback_query_id ?text ?(show_alert = false) () =
  let fields = ref [
    "callback_query_id", `String callback_query_id;
    "show_alert", `Bool show_alert;
  ] in
  (match text with
   | Some t -> fields := ("text", `String t) :: !fields
   | None -> ());
  telegram_call ~token "answerCallbackQuery" (`Assoc !fields)

(* ----------------------------------------------------------------------------
   6. High-Level Workflows: 2oo3 Interactive Approval Buttons
   ---------------------------------------------------------------------------- *)

let make_approval_keyboard ~plan_id ~task_id =
  `Assoc [
    "inline_keyboard", `List [
      `List [
        `Assoc ["text", `String "✅ Approve (2oo3)"; "callback_data", `String (Printf.sprintf "approve:%s:%s" plan_id task_id)];
        `Assoc ["text", `String "❌ Reject"; "callback_data", `String (Printf.sprintf "reject:%s:%s" plan_id task_id)];
      ];
      `List [
        `Assoc ["text", `String "📊 View Cockpit"; "url", `String "http://nas-1.tail55d152.ts.net:4100/planning"];
      ]
    ]
  ]

let send_approval_request ~token ~chat_id ~plan_id ~task_id ~title =
  let keyboard = make_approval_keyboard ~plan_id ~task_id in
  let text = Printf.sprintf "🛡️ *UOS Constitutional 2oo3 Action Required*\n\n*Plan:* `%s`\n*Task:* `%s`\n*Title:* %s\n\nPlease approve or reject this effect grant."
    plan_id task_id title in
  send_message ~token ~chat_id ~parse_mode:"Markdown" ~reply_markup:keyboard text

(* ----------------------------------------------------------------------------
   6.1 Interactive Telegram Bot Directives & Remote Command Handlers
   ---------------------------------------------------------------------------- *)

let run_command_capture cmd =
  match Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.to_string with
  | Ok out -> String.trim out
  | Error (`Msg e) -> "Error: " ^ e

let string_contains haystack needle =
  let hl = String.length haystack and nl = String.length needle in
  if nl = 0 then true
  else if hl < nl then false
  else begin
    let found = ref false in
    let i = ref 0 in
    while !i <= hl - nl && not !found do
      if String.sub haystack !i nl = needle then found := true;
      incr i
    done;
    !found
  end

let dispatch_to_gleam_harness payload_json_str =
  let cmd = Bos.Cmd.(v (root ^ "/tools/telegram-harness-dispatch") % payload_json_str) in
  match Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.to_string with
  | Ok out when String.trim out <> "" ->
      (try
         let json = Yojson.Safe.from_string (String.trim out) in
         let text = member "text" json |> to_string in
         let parse_mode =
           match member "parse_mode" json with
           | `String s -> Some s
           | _ -> None
         in
         Some (text, parse_mode)
       with _ -> None)
  | _ -> None


let decode_zenoh_payload encoded =
  try
    Cryptokit.transform_string (Cryptokit.Base64.decode ()) encoded
  with _ -> encoded

let parse_zenoh_entries out =
  try
    match Yojson.Safe.from_string out with
    | `List items -> items
    | _ -> []
  with _ -> []

let check_outbound_zenoh ~token ~default_chat ~zenoh_endpoint =
  try
    let url = zenoh_endpoint ^ "/c3i/a2a/telegram/outbound" in
    let cmd = Bos.Cmd.(v "curl" % "-s" % url) in
    match Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.to_string with
    | Ok out when String.trim out <> "" && out <> "[]" ->
        let entries = parse_zenoh_entries out in
        List.iter (fun entry ->
          try
            let json =
              match member "value" entry with
              | `String s ->
                  (try Yojson.Safe.from_string (decode_zenoh_payload s)
                   with _ -> Yojson.Safe.from_string s)
              | `Assoc _ as obj -> obj
              | other -> other
            in
            let text = member "text" json |> to_string in
            let chat_id =
              match member "chat_id" json with
              | `String s -> s
              | `Int i -> string_of_int i
              | `Intlit s -> s
              | _ -> default_chat
            in
            let parse_mode =
              match member "parse_mode" json with
              | `String s -> Some s
              | _ -> None
            in
            let chunks = chunk_text text in
            List.iter (fun ch -> ignore (send_message ~token ~chat_id ?parse_mode ch)) chunks;
            let del_cmd = Bos.Cmd.(v "curl" % "-s" % "-X" % "DELETE" % url) in
            ignore (Bos.OS.Cmd.run del_cmd)
          with _ -> ()
        ) entries
    | _ -> ()
  with _ -> ()

let check_sutra_matrix_relay ~token ~default_chat ~zenoh_endpoint =
  try
    let url = zenoh_endpoint ^ "/indrajaal/sutra/message/sent" in
    let cmd = Bos.Cmd.(v "curl" % "-s" % url) in
    match Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.to_string with
    | Ok out when String.trim out <> "" && out <> "[]" ->
        let entries = parse_zenoh_entries out in
        List.iter (fun entry ->
          try
            let json =
              match member "value" entry with
              | `String s ->
                  (try Yojson.Safe.from_string (decode_zenoh_payload s)
                   with _ -> Yojson.Safe.from_string s)
              | `Assoc _ as obj -> obj
              | other -> other
            in
            let event_id =
              match member "event_id" json with
              | `String s -> s
              | _ -> Printf.sprintf "ev-%Ld" (now_ms ())
            in
            if not (is_sutra_event_processed event_id) then begin
              mark_sutra_event_processed event_id;
              let room_id = match member "room_id" json with `String s -> s | _ -> "matrix:sutra" in
              let sender = match member "sender" json with `String s -> s | _ -> "matrix_user" in
              let msg_type = match member "msg_type" json with `String s -> s | _ -> "m.text" in
              let body =
                match member "body" json with
                | `String s -> s
                | _ ->
                    match member "action" json with
                    | `String a -> Printf.sprintf "[Matrix Event %s: %s]" a event_id
                    | _ -> Printf.sprintf "[Matrix Message %s]" event_id
              in
              let relay_msg = Printf.sprintf
                "💬 *[Matrix Sutra Relay]*\n\
                 • *Sender:* `%s`\n\
                 • *Room:* `%s`\n\
                 • *Type:* `%s`\n\
                 • *Event ID:* `%s`\n\n\
                 %s"
                sender room_id msg_type event_id body
              in
              let chunks = chunk_text relay_msg in
              List.iter (fun ch -> ignore (send_message ~token ~chat_id:default_chat ~parse_mode:"Markdown" ch)) chunks;
              let del_cmd = Bos.Cmd.(v "curl" % "-s" % "-X" % "DELETE" % url) in
              ignore (Bos.OS.Cmd.run del_cmd)
            end
          with _ -> ()
        ) entries
    | _ -> ()
  with _ -> ()

(* ----------------------------------------------------------------------------
   7. Inbound Update Processor & Dispatch Loop
   ---------------------------------------------------------------------------- *)

let process_single_update ~token ~zenoh_endpoint update =
  let update_id = member "update_id" update |> to_int64 in
  if is_update_processed update_id then ()
  else begin
    mark_update_processed update_id;
    set_db_preference "telegram_poll_offset" (Int64.to_string (Int64.add update_id 1L));

    (* Case 1: Inbound Message *)
    (match member "message" update with
     | `Null -> ()
     | msg ->
         let msg_id = member "message_id" msg |> to_int64 in
         let chat_id = member "chat" msg |> member "id" |> to_int64 |> Int64.to_string in
         let from_user =
           match member "from" msg with
           | `Null -> "unknown"
           | u ->
               (match member "username" u with
                | `String s -> s
                | _ -> member "first_name" u |> to_string)
         in
         let text =
           match member "text" msg with
           | `String s -> s
           | _ -> ""
         in
         Printf.printf "📥 [inbound] Msg %Ld from @%s (%s): %s\n%!" msg_id from_user chat_id text;

         (* Acknowledge immediately with Telegram reaction *)
         let reaction = if String.starts_with ~prefix:"/" text then "⚡" else "👍" in
         ignore (set_message_reaction ~token ~chat_id ~message_id:msg_id reaction);

         (* Construct inbound event payload *)
         let inbound_event = `Assoc [
           "update_id", `Intlit (Int64.to_string update_id);
           "message_id", `Intlit (Int64.to_string msg_id);
           "chat_id", `String chat_id;
           "from_user", `String from_user;
           "text", `String text;
           "timestamp_ms", `Intlit (Int64.to_string (now_ms ()))
         ] in
         let inbound_payload_str = Yojson.Safe.to_string inbound_event in

         (* Publish intent to Zenoh mesh (c3i/a2a/telegram/inbound and indrajaal/l5/cog/intent/req) *)
         let _ = zenoh_put ~endpoint:zenoh_endpoint "c3i/a2a/telegram/inbound" inbound_payload_str in
         let _ = zenoh_put ~endpoint:zenoh_endpoint "indrajaal/l5/cog/intent/req" inbound_payload_str in
         let _ = zenoh_put ~endpoint:zenoh_endpoint "indrajaal/sutra/telegram/relay" inbound_payload_str in

         (* Delegate all message handling to the UOS Gleam Harness *)
         Printf.printf "⚙️ [harness] Delegating message %Ld to UOS Gleam Harness...\n%!" msg_id;
         (match dispatch_to_gleam_harness inbound_payload_str with
          | Some (reply_text, parse_mode) ->
              Printf.printf "📤 [harness] Received reply from Gleam harness (%d chars)\n%!" (String.length reply_text);
              let chunks = chunk_text reply_text in
              List.iter (fun ch -> ignore (send_message ~token ~chat_id ?parse_mode ch)) chunks
          | None ->
              Printf.eprintf "⚠️ [harness] Gleam harness dispatch returned None for msg %Ld\n%!" msg_id);
         ());

    (* Case 2: Callback Query from Inline Keyboard *)
    (match member "callback_query" update with
     | `Null -> ()
     | cb ->
         let cb_id = member "id" cb |> to_string in
         let cb_data = member "data" cb |> to_string in
         let from_user =
           match member "from" cb with
           | `Null -> "unknown"
           | u ->
               match member "username" u with
               | `String s -> s
               | _ ->
                   match member "first_name" u with
                   | `String f -> f
                   | _ -> "user"
         in
         let msg = member "message" cb in
         let chat_id = member "chat" msg |> member "id" |> to_int64 |> Int64.to_string in
         let msg_id = member "message_id" msg |> to_int64 in

         Printf.printf "⚡ [callback] CallbackQuery %s from @%s: data=%s\n%!" cb_id from_user cb_data;

         if String.starts_with ~prefix:"approve:" cb_data then begin
           let parts = String.split_on_char ':' cb_data in
           let plan_id = List.nth parts 1 and task_id = List.nth parts 2 in
           ignore (answer_callback_query ~token ~callback_query_id:cb_id ~text:"✅ Constitutional Approval Registered!" ());
           let updated_text = Printf.sprintf "✅ *APPROVED by @%s*\nPlan: `%s`\nTask: `%s`\nTime: %s"
             from_user plan_id task_id (Int64.to_string (now_ms ())) in
           ignore (edit_message_text ~token ~chat_id ~message_id:msg_id ~parse_mode:"Markdown" updated_text);
           let cb_payload = Yojson.Safe.to_string (`Assoc [
             "event", `String "constitutional_approval";
             "user", `String from_user;
             "plan_id", `String plan_id;
             "task_id", `String task_id;
             "status", `String "approved";
             "timestamp_ms", `Intlit (Int64.to_string (now_ms ()))
           ]) in
           let _ = zenoh_put ~endpoint:zenoh_endpoint "indrajaal/l0/const/consensus" cb_payload in
           let _ = zenoh_put ~endpoint:zenoh_endpoint "indrajaal/l5/cog/intent/req" cb_payload in
           ()
         end else if String.starts_with ~prefix:"reject:" cb_data then begin
           let parts = String.split_on_char ':' cb_data in
           let plan_id = List.nth parts 1 and task_id = List.nth parts 2 in
           ignore (answer_callback_query ~token ~callback_query_id:cb_id ~text:"❌ Action Rejected!" ());
           let updated_text = Printf.sprintf "❌ *REJECTED by @%s*\nPlan: `%s`\nTask: `%s`" from_user plan_id task_id in
           ignore (edit_message_text ~token ~chat_id ~message_id:msg_id ~parse_mode:"Markdown" updated_text);
           let cb_payload = Yojson.Safe.to_string (`Assoc [
             "event", `String "constitutional_rejection";
             "user", `String from_user;
             "plan_id", `String plan_id;
             "task_id", `String task_id;
             "status", `String "rejected";
             "timestamp_ms", `Intlit (Int64.to_string (now_ms ()))
           ]) in
           let _ = zenoh_put ~endpoint:zenoh_endpoint "indrajaal/l0/const/consensus" cb_payload in
           ()
         end else begin
           ignore (answer_callback_query ~token ~callback_query_id:cb_id ~text:"Acknowledged" ())
         end)
  end

let poll_once ~token ~zenoh_endpoint () =
  let offset =
    match get_preference "telegram_poll_offset" with
    | "" -> -1L
    | s -> (try Int64.of_string s with _ -> -1L)
  in
  let res = get_updates ~token ~offset ~timeout:2 () in
  match member "ok" res with
  | `Bool true ->
      let updates = member "result" res |> to_list in
      List.iter (process_single_update ~token ~zenoh_endpoint) updates;
      let default_chat = get_preference "telegram_chat_id" in
      check_outbound_zenoh ~token ~default_chat ~zenoh_endpoint;
      check_sutra_matrix_relay ~token ~default_chat ~zenoh_endpoint;
      List.length updates
  | _ ->
      let err =
        match member "description" res with
        | `String d -> d
        | _ ->
            match member "error" res with
            | `String e -> e
            | _ -> Yojson.Safe.to_string res
      in
      if not (string_contains err "exited with 56" || string_contains err "CURLE_RECV_ERROR" || string_contains err "timed out") then
        Printf.eprintf "[!] getUpdates failed: %s\n%!" err;
      0

(* ----------------------------------------------------------------------------
   8. Microbenchmark Suite
   ---------------------------------------------------------------------------- *)

let run_benchmarks () =
  Printf.printf "=================================================================\n";
  Printf.printf "   UOS TELEGRAM HIGH-VELOCITY OCAML MICROBENCHMARK SUITE         \n";
  Printf.printf "=================================================================\n\n";

  (* Bench 1: MarkdownV2 Escaping *)
  let sample_md = "Here is an alert [CRITICAL]: system.health = degraded (p < 0.05) & disk ~ 98%! `int *p = NULL;`" in
  let iterations = 200_000 in
  let t0 = Unix.gettimeofday () in
  for _ = 1 to iterations do
    ignore (escape_markdown_v2 sample_md)
  done;
  let t1 = Unix.gettimeofday () in
  let elapsed1 = t1 -. t0 in
  let ops_sec1 = float_of_int iterations /. elapsed1 in
  Printf.printf "[1] MarkdownV2 Escaping (%d iterations):\n" iterations;
  Printf.printf "    Elapsed: %.4fs | Throughput: %.0f ops/sec\n\n" elapsed1 ops_sec1;

  (* Bench 2: Draft Chunking *)
  let sample_long = String.make 12000 'A' in
  let t2 = Unix.gettimeofday () in
  for _ = 1 to iterations do
    ignore (chunk_text ~max_bytes:4096 sample_long)
  done;
  let t3 = Unix.gettimeofday () in
  let elapsed2 = t3 -. t2 in
  let ops_sec2 = float_of_int iterations /. elapsed2 in
  Printf.printf "[2] Safe 4096-Byte Chunking (%d iterations):\n" iterations;
  Printf.printf "    Elapsed: %.4fs | Throughput: %.0f ops/sec\n\n" elapsed2 ops_sec2;

  (* Bench 3: HMAC-SHA256 Validation *)
  let sample_init_data = "auth_date=1710000000&query_id=AAHd&user=%7B%22id%22%3A123456%7D&hash=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" in
  let t4 = Unix.gettimeofday () in
  for _ = 1 to iterations do
    ignore (validate_telegram_init_data ~bot_token:"dummy_token" ~init_data:sample_init_data)
  done;
  let t5 = Unix.gettimeofday () in
  let elapsed3 = t5 -. t4 in
  let ops_sec3 = float_of_int iterations /. elapsed3 in
  Printf.printf "[3] Mini App HMAC-SHA256 Validation (%d iterations):\n" iterations;
  Printf.printf "    Elapsed: %.4fs | Throughput: %.0f ops/sec\n\n" elapsed3 ops_sec3;
  Printf.printf "=================================================================\n"

(* ----------------------------------------------------------------------------
   9. CLI Entry Point
   ---------------------------------------------------------------------------- *)

let print_usage () =
  Printf.printf "UOS Telegram High-Performance Client\n";
  Printf.printf "Usage: telegram_client [OPTIONS]\n\n";
  Printf.printf "Options:\n";
  Printf.printf "  --status                         Check bot info, target chat, and Zenoh\n";
  Printf.printf "  --poll [--once]                  Poll incoming updates (daemon by default)\n";
  Printf.printf "  --check-queues                   Check Zenoh outbound and Sutra Matrix queues once\n";
  Printf.printf "  --exec-cmd <cmd>                 Execute bot command directly via CLI dispatcher\n";
  Printf.printf "  --send <text> [--chat-id <id>]   Send text message (auto-chunked)\n";
  Printf.printf "  --action <action>                Send chat action (typing, upload_photo, etc.)\n";
  Printf.printf "  --react <msg_id> <emoji>         Set message reaction\n";
  Printf.printf "  --approval <plan> <task> <title> Send 2oo3 constitutional approval buttons\n";
  Printf.printf "  --verify-init-data <init_data>   Verify Telegram WebApp HMAC-SHA256 signature\n";
  Printf.printf "  --bench                          Run microbenchmark suite\n"

let () =
  let args = Array.to_list Sys.argv in
  let token = get_preference "telegram_token" in
  let default_chat = get_preference "telegram_chat_id" in
  let zenoh_endpoint =
    match get_preference "zenoh_rest_endpoint" with
    | "" -> zenoh_rest_default
    | ep -> ep
  in

  match args with
  | _ :: "--bench" :: _ ->
      run_benchmarks ()

  | _ :: "--status" :: _ ->
      if token = "" then begin
        Printf.eprintf "[!] No telegram_token configured in Smriti.db or TELEGRAM_TOKEN env\n";
        exit 1
      end;
      let me = get_me ~token in
      if member "ok" me |> to_bool then begin
        let res = member "result" me in
        Printf.printf "📡 Telegram Bot Connected: @%s (ID: %Ld)\n"
          (member "username" res |> to_string)
          (member "id" res |> to_int64);
        Printf.printf "   Default Target Chat: %s\n" default_chat;
        Printf.printf "   State DB:            %s\n" state_db_path;
        Printf.printf "   Zenoh REST Bus:      %s\n" zenoh_endpoint;
        let processed_count =
          let db = init_db () in
          let stmt = Sqlite3.prepare db "SELECT COUNT(*) FROM processed_updates;" in
          let count = match Sqlite3.step stmt with Sqlite3.Rc.ROW -> Sqlite3.column_int64 stmt 0 | _ -> 0L in
          let _ = Sqlite3.finalize stmt in
          let _ = Sqlite3.db_close db in
          count
        in
        Printf.printf "   Deduplicated Updates: %Ld\n" processed_count
      end else begin
        Printf.eprintf "[!] getMe failed: %s\n" (Yojson.Safe.to_string me);
        exit 1
      end

  | _ :: "--poll" :: rest ->
      if token = "" then begin
        Printf.eprintf "[!] No telegram_token configured\n";
        exit 1
      end;
      let once = List.mem "--once" rest in
      if once then begin
        let n = poll_once ~token ~zenoh_endpoint () in
        Printf.printf "[poll] Cycle finished, processed %d update(s)\n" n
      end else begin
        Printf.printf "🚀 Starting continuous Telegram OCaml client daemon...\n%!";
        while true do
          (try
             let _ = poll_once ~token ~zenoh_endpoint () in ()
           with ex ->
             Printf.eprintf "[!] Error in poll loop: %s\n%!" (Printexc.to_string ex));
          Unix.sleep 2
        done
      end

  | _ :: "--send" :: text :: rest ->
      if token = "" then begin Printf.eprintf "[!] No token\n"; exit 1 end;
      let chat_id =
        let rec find_chat = function
          | "--chat-id" :: cid :: _ -> cid
          | _ :: xs -> find_chat xs
          | [] -> default_chat
        in
        find_chat rest
      in
      let parse_mode = if List.mem "--markdown" rest then Some "MarkdownV2" else None in
      let chunks = chunk_text text in
      List.iteri (fun idx chunk ->
        let res = send_message ~token ~chat_id ?parse_mode chunk in
        if member "ok" res |> to_bool then
          let msg_id = member "result" res |> member "message_id" |> to_int64 in
          Printf.printf "[send chunk %d/%d] Delivered msg_id: %Ld\n%!" (idx+1) (List.length chunks) msg_id
        else
          Printf.eprintf "[send] Failed: %s\n%!" (Yojson.Safe.to_string res)
      ) chunks

  | _ :: "--action" :: act :: _ ->
      if token = "" then begin Printf.eprintf "[!] No token\n"; exit 1 end;
      let res = send_chat_action ~token ~chat_id:default_chat act in
      Printf.printf "[action] Result: %s\n" (Yojson.Safe.to_string res)

  | _ :: "--react" :: msg_id_str :: emoji :: _ ->
      if token = "" then begin Printf.eprintf "[!] No token\n"; exit 1 end;
      let msg_id = Int64.of_string msg_id_str in
      let res = set_message_reaction ~token ~chat_id:default_chat ~message_id:msg_id emoji in
      Printf.printf "[reaction] Result: %s\n" (Yojson.Safe.to_string res)

  | _ :: "--approval" :: plan_id :: task_id :: title :: _ ->
      if token = "" then begin Printf.eprintf "[!] No token\n"; exit 1 end;
      let res = send_approval_request ~token ~chat_id:default_chat ~plan_id ~task_id ~title in
      Printf.printf "[approval] Sent 2oo3 prompt: %s\n" (Yojson.Safe.to_string res)

  | _ :: "--verify-init-data" :: init_data :: _ ->
      let ok = validate_telegram_init_data ~bot_token:token ~init_data in
      Printf.printf "Signature Validation: %s\n" (if ok then "VALID" else "INVALID")

  | _ :: "--check-queues" :: _ ->
      if token = "" then begin Printf.eprintf "[!] No token\n"; exit 1 end;
      Printf.printf "Checking Zenoh outbound and Sutra Matrix queues...\n%!";
      check_outbound_zenoh ~token ~default_chat ~zenoh_endpoint;
      check_sutra_matrix_relay ~token ~default_chat ~zenoh_endpoint;
      Printf.printf "Queue check complete.\n"

  | _ :: "--exec-cmd" :: cmd_text :: _ ->
      if token = "" then begin Printf.eprintf "[!] No token\n"; exit 1 end;
      let inbound_event = `Assoc [
        "update_id", `Intlit "999999";
        "message_id", `Intlit "999999";
        "chat_id", `String default_chat;
        "from_user", `String "cli_operator";
        "text", `String cmd_text;
        "timestamp_ms", `Intlit (Int64.to_string (now_ms ()))
      ] in
      let inbound_payload_str = Yojson.Safe.to_string inbound_event in
      Printf.printf "[exec-cmd] Delegating directive to UOS Gleam Harness: %s\n%!" cmd_text;
      (match dispatch_to_gleam_harness inbound_payload_str with
       | Some (reply_text, parse_mode) ->
           Printf.printf "Result:\n%s\n%!" reply_text;
           let chunks = chunk_text reply_text in
           List.iter (fun ch -> ignore (send_message ~token ~chat_id:default_chat ?parse_mode ch)) chunks
       | None ->
           Printf.eprintf "[exec-cmd] Gleam harness execution failed\n%!")

  | _ ->
      print_usage ()
