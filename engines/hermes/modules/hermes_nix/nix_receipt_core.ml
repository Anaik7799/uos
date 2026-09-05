type verdict =
  | Success
  | Failed of Nix_error.t

type t = {
  receipt_id : Nix_id.Receipt_id.t;
  intent_id : Nix_id.Intent_id.t;
  timestamp : string;
  duration_ms : int;
  output_paths : Nix_id.Store_path.t list;
  closure_digest : Nix_id.Closure_digest.t option;
  summary : string;
  verdict : verdict;
}

let format_timestamp () =
  let tm = Unix.gmtime (Unix.gettimeofday ()) in
  Printf.sprintf "%04d%02d%02d-%02d%02d"
    (tm.Unix.tm_year + 1900)
    (tm.Unix.tm_mon + 1)
    tm.Unix.tm_mday
    tm.Unix.tm_hour
    tm.Unix.tm_sec

let make ~intent ~duration_ms ~output_paths ~closure_digest ~summary ~verdict =
  let i_id = Nix_intent.intent_id intent in
  let ts = format_timestamp () in
  let seed = Printf.sprintf "%s:%s:%d:%s" (Nix_id.Intent_id.to_string i_id) ts duration_ms summary in
  let digest = Digestif.SHA256.digest_string seed in
  let r_id = Nix_id.Receipt_id.of_string_exn ("nix-rcpt-" ^ (Digestif.SHA256.to_hex digest |> fun s -> String.sub s 0 16)) in
  { receipt_id = r_id;
    intent_id = i_id;
    timestamp = ts;
    duration_ms;
    output_paths;
    closure_digest;
    summary;
    verdict }

let is_success t =
  match t.verdict with
  | Success -> true
  | Failed _ -> false

let to_yojson t =
  `Assoc
    [ ("receipt_id", `String (Nix_id.Receipt_id.to_string t.receipt_id));
      ("intent_id", `String (Nix_id.Intent_id.to_string t.intent_id));
      ("timestamp", `String t.timestamp);
      ("duration_ms", `Int t.duration_ms);
      ("output_paths", `List (List.map (fun p -> `String (Nix_id.Store_path.to_string p)) t.output_paths));
      ("closure_digest",
       match t.closure_digest with
       | Some d -> `String (Nix_id.Closure_digest.to_string d)
       | None -> `Null);
      ("summary", `String t.summary);
      ("verdict",
       match t.verdict with
       | Success -> `String "success"
       | Failed e -> Nix_error.to_yojson e) ]
