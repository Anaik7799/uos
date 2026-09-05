type t = { db : Sqlite3.db }

let init_db path =
  let db = Sqlite3.db_open path in
  Sqlite3.busy_timeout db 5000;
  let sql_create = "
    CREATE TABLE IF NOT EXISTS lmstudio_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp TEXT DEFAULT (datetime('now', 'localtime')),
      vector_space TEXT,
      depth INTEGER,
      prompt TEXT,
      response TEXT,
      evaluation_score REAL,
      vram_ok INTEGER,
      context_ok INTEGER,
      interpretation TEXT,
      api_endpoint TEXT,
      model_id TEXT,
      curl_command TEXT,
      raw_log_segment TEXT,
      temperature REAL,
      max_tokens INTEGER,
      fine_tuning_strategy TEXT,
      oracle_advice TEXT
    );
  " in
  match Sqlite3.exec db sql_create with
  | Sqlite3.Rc.OK -> Ok { db }
  | rc -> Error ("Failed to initialize schema: " ^ Sqlite3.Rc.to_string rc)

let log_transaction t vector_space depth prompt response score vram_ok context_ok interpretation 
                    api_endpoint model_id curl_command raw_log_segment temp max_tokens tuning oracle_advice =
  let sql = "
    INSERT INTO lmstudio_history (
      vector_space, depth, prompt, response, evaluation_score, vram_ok, context_ok, interpretation,
      api_endpoint, model_id, curl_command, raw_log_segment, temperature, max_tokens, fine_tuning_strategy, oracle_advice
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  " in
  let stmt = Sqlite3.prepare t.db sql in
  let bind_ok =
    let open Sqlite3.Data in
    let (&&) a b = match a with Sqlite3.Rc.OK -> b | rc -> rc in
    Sqlite3.bind stmt 1 (TEXT vector_space) &&
    Sqlite3.bind stmt 2 (INT (Int64.of_int depth)) &&
    Sqlite3.bind stmt 3 (TEXT prompt) &&
    Sqlite3.bind stmt 4 (TEXT response) &&
    Sqlite3.bind stmt 5 (FLOAT score) &&
    Sqlite3.bind stmt 6 (INT (if vram_ok then 1L else 0L)) &&
    Sqlite3.bind stmt 7 (INT (if context_ok then 1L else 0L)) &&
    Sqlite3.bind stmt 8 (TEXT interpretation) &&
    Sqlite3.bind stmt 9 (TEXT api_endpoint) &&
    Sqlite3.bind stmt 10 (TEXT model_id) &&
    Sqlite3.bind stmt 11 (TEXT curl_command) &&
    Sqlite3.bind stmt 12 (TEXT raw_log_segment) &&
    Sqlite3.bind stmt 13 (FLOAT temp) &&
    Sqlite3.bind stmt 14 (INT (Int64.of_int max_tokens)) &&
    Sqlite3.bind stmt 15 (TEXT tuning) &&
    Sqlite3.bind stmt 16 (TEXT oracle_advice)
  in
  match bind_ok with
  | Sqlite3.Rc.OK ->
      let step_res = Sqlite3.step stmt in
      ignore (Sqlite3.finalize stmt : Sqlite3.Rc.t);
      if step_res = Sqlite3.Rc.DONE then begin
        let _ = Swarm_zenoh.publish_telemetry "{\"fractal_layer\": \"L6/receipt\", \"event\": \"SQLITE_COMMIT\", \"target\": \"lmstudio_history\"}" in
        Ok ()
      end
      else Error ("Insert step failed: " ^ Sqlite3.Rc.to_string step_res)
  | rc ->
      ignore (Sqlite3.finalize stmt : Sqlite3.Rc.t);
      Error ("Bind failed: " ^ Sqlite3.Rc.to_string rc)

let close_db t =
  ignore (Sqlite3.db_close t.db : bool)

let print_history t out_buffer =
  let sql = "SELECT id, timestamp, vector_space, depth, evaluation_score, interpretation, api_endpoint, model_id, temperature, fine_tuning_strategy FROM lmstudio_history;" in
  let stmt = Sqlite3.prepare t.db sql in
  let rec loop () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let id = Sqlite3.column_int64 stmt 0 in
        let ts = Sqlite3.column_text stmt 1 in
        let vector = Sqlite3.column_text stmt 2 in
        let depth = Sqlite3.column_int64 stmt 3 in
        let score = Sqlite3.column_double stmt 4 in
        let interp = Sqlite3.column_text stmt 5 in
        let endpoint = Sqlite3.column_text stmt 6 in
        let model = Sqlite3.column_text stmt 7 in
        let temp = Sqlite3.column_double stmt 8 in
        let tuning = Sqlite3.column_text stmt 9 in
        Buffer.add_string out_buffer (
          Printf.sprintf "Transaction [%Ld] [%s]\n  - Target: Model: %s via %s\n  - Config: Temp: %.2f | Tuning: %s\n  - State:  %s (Depth %Ld) - Score: %.1f -> %s\n" 
            id ts model endpoint temp tuning vector depth score interp
        );
        loop ()
    | Sqlite3.Rc.DONE -> ()
    | rc -> Buffer.add_string out_buffer (Printf.sprintf "Error scanning history: %s\n" (Sqlite3.Rc.to_string rc))
  in
  Buffer.add_string out_buffer "Retrieving exhaustive transaction logs from database:\n";
  loop ();
  ignore (Sqlite3.finalize stmt : Sqlite3.Rc.t)
