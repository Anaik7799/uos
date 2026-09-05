type role = Completion_reservation | Completion_final
type kind = Reserve | Finalize

type common = {
  completion : Jj_id.Receipt.t;
  source : Jj_id.Receipt.t;
  head : Jj_id.Operation.t;
  campaign : Jj_id.Intent.t;
  payload : Jj_id.Receipt.t;
}

type finalize_dependencies = {
  bookmark : Jj_id.Bookmark.t;
  readback : Jj_id.Receipt.t;
  lease_release : Jj_id.Receipt.t;
}

type prepared =
  | Prepared_reserve of common
  | Prepared_finalize of common * finalize_dependencies

let common ~completion ~source ~head ~campaign ~payload =
  { completion; source; head; campaign; payload }

let prepare_reserve ~completion ~source ~head ~campaign ~payload =
  Ok (Prepared_reserve (common ~completion ~source ~head ~campaign ~payload))

let prepare_finalize ~completion ~source ~head ~campaign ~payload ~bookmark
    ~readback ~lease_release =
  Ok
    (Prepared_finalize
       (common ~completion ~source ~head ~campaign ~payload,
        { bookmark; readback; lease_release }))

let kind = function Prepared_reserve _ -> Reserve | Prepared_finalize _ -> Finalize
let role = function
  | Prepared_reserve _ -> Completion_reservation
  | Prepared_finalize _ -> Completion_final

let common_of = function
  | Prepared_reserve common | Prepared_finalize (common, _) -> common

let completion_id prepared = (common_of prepared).completion

let common_fields common =
  [ Jj_id.Receipt.to_string common.completion;
    Jj_id.Receipt.to_string common.source;
    Jj_id.Operation.to_string common.head;
    Jj_id.Intent.to_string common.campaign;
    Jj_id.Receipt.to_string common.payload ]

let reservation_payload_digest prepared =
  Jj_id.length_frame
    ("jj-completion-reservation-payload-v1" :: common_fields (common_of prepared))
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let payload_digest prepared =
  let fields =
    match prepared with
    | Prepared_reserve common -> "reserve" :: common_fields common
    | Prepared_finalize (common, dependencies) ->
        "finalize" :: common_fields common
        @ [ Jj_id.Bookmark.to_string dependencies.bookmark;
            Jj_id.Receipt.to_string dependencies.readback;
            Jj_id.Receipt.to_string dependencies.lease_release ]
  in
  Jj_id.length_frame fields
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let canonical_digest = payload_digest

let compatible_replay left right =
  String.equal
    (Jj_id.Receipt.to_string (completion_id left))
    (Jj_id.Receipt.to_string (completion_id right))
  && String.equal (payload_digest left) (payload_digest right)

let source_digest =
  Jj_id.length_frame
    [ "jj-completion-store-protocol-v1"; "reserve"; "finalize";
      "shared-reservation-payload-digest";
      "same-id-same-payload-replay"; "same-id-different-payload-conflict" ]
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex
