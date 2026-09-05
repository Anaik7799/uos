(* A digest-pinned session tying one request to its pinned provider response and
   to the reference's normalized decode.

   Mirrors Reference_capture (R14): the same digest-keyed path, the same
   re-derive-on-load freshness law, and it reuses Reference_capture's sha256,
   read_file and write_file rather than duplicating them. The digest is over the
   normalized reference decode -- the oracle half a comparison rests on -- so an
   edited fixture is rejected. *)

type request = { endpoint : string; body : Yojson.Safe.t }

type t = {
  session_id : string;
  snapshot_digest : string;
  reference_revision : string;
  request : request;
  provider_response : Yojson.Safe.t;
  reference_decode : Yojson.Safe.t;
  normalized_digest : string;
  normalization : string;
}

type error =
  | Missing of string
  | Unreadable of string
  | Digest_mismatch of string

let describe = function
  | Missing path -> "session fixture not found: " ^ path
  | Unreadable reason -> "unreadable session fixture: " ^ reason
  | Digest_mismatch reason -> "session digest mismatch: " ^ reason

let sha256 = Reference_capture.sha256

let make ~normalizer ~session_id ~snapshot_digest ~reference_revision ~request
    ~provider_response ~reference_decode =
  { session_id; snapshot_digest; reference_revision; request; provider_response;
    reference_decode;
    normalized_digest = sha256 (Parity_normalizer.render normalizer reference_decode);
    normalization = Parity_normalizer.describe normalizer }

(* Keyed by session and snapshot, like Reference_capture: a capture under a
   different snapshot is a different fixture, never a silent overwrite. *)
let fixture_path ~root session_id ~snapshot_digest =
  let short =
    if String.length snapshot_digest >= 12 then String.sub snapshot_digest 0 12
    else snapshot_digest
  in
  Filename.concat root
    (Printf.sprintf "modules/hermes_harness/fixtures/sessions/%s.%s.json" session_id short)

let request_to_json (request : request) =
  `Assoc [ ("endpoint", `String request.endpoint); ("body", request.body) ]

let to_json t =
  `Assoc
    [ ("session_id", `String t.session_id);
      ("snapshot_digest", `String t.snapshot_digest);
      ("reference_revision", `String t.reference_revision);
      ("request", request_to_json t.request);
      ("provider_response", t.provider_response);
      ("reference_decode", t.reference_decode);
      ("normalization", `String t.normalization);
      ("normalized_digest", `String t.normalized_digest) ]

let of_json value =
  match value with
  | `Assoc fields ->
      let text name =
        match List.assoc_opt name fields with Some (`String s) -> Some s | _ -> None
      in
      let json name = List.assoc_opt name fields in
      let request =
        match json "request" with
        | Some (`Assoc rf) -> (
            match (List.assoc_opt "endpoint" rf, List.assoc_opt "body" rf) with
            | Some (`String endpoint), Some body -> Some { endpoint; body }
            | _ -> None)
        | _ -> None
      in
      (match
         ( text "session_id", text "snapshot_digest", text "reference_revision", request,
           json "provider_response", json "reference_decode", text "normalization",
           text "normalized_digest" )
       with
      | ( Some session_id, Some snapshot_digest, Some reference_revision, Some request,
          Some provider_response, Some reference_decode, Some normalization,
          Some normalized_digest ) ->
          Ok
            { session_id; snapshot_digest; reference_revision; request; provider_response;
              reference_decode; normalized_digest; normalization }
      | _ -> Error (Unreadable "session fixture is missing required fields"))
  | _ -> Error (Unreadable "session fixture was not an object")

let save ~root t =
  let path = fixture_path ~root t.session_id ~snapshot_digest:t.snapshot_digest in
  let directory = Filename.dirname path in
  let rec ensure path =
    if not (Sys.file_exists path) then begin
      ensure (Filename.dirname path);
      try Unix.mkdir path 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
    end
  in
  ensure directory;
  Reference_capture.write_file path (Yojson.Safe.pretty_to_string (to_json t) ^ "\n");
  path

(* Loading re-derives the digest from the stored reference decode instead of
   trusting the one on disk: a fixture whose recorded digest does not match its
   own decode has been edited, and an edited oracle is worse than none. *)
let load ~root ~normalizer session_id ~snapshot_digest =
  let path = fixture_path ~root session_id ~snapshot_digest in
  if not (Sys.file_exists path) then Error (Missing path)
  else
    match Yojson.Safe.from_string (Reference_capture.read_file path) with
    | exception Yojson.Json_error message -> Error (Unreadable message)
    | value -> (
        match of_json value with
        | Error _ as error -> error
        | Ok t ->
            let recomputed = sha256 (Parity_normalizer.render normalizer t.reference_decode) in
            if String.equal recomputed t.normalized_digest then Ok t
            else
              Error
                (Digest_mismatch
                   (Printf.sprintf "recorded %s, recomputed %s for %s" t.normalized_digest
                      recomputed session_id)))
