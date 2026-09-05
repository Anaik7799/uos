(* Deterministic replay executor for Openrouter_transport.submit.

   A recording maps a rendered request body to the pinned provider response.
   The executor returns that response for a matching request and refuses on a
   miss -- there is no network code, so a replay is byte-identical run to run
   and cannot depend on anything outside its arguments. This is the seam that
   lets the candidate's full submit -> decode path be exercised offline. *)

type recording = (string * (int * string)) list

let empty = []

let record ~request_body ~status ~response_body recording =
  (request_body, (status, response_body)) :: recording

let of_list entries = entries

let size recording = List.length recording

(* Keyed by the exact rendered request body -- the same string
   Openrouter_transport.submit passes to the executor -- so a match is exact and
   deterministic. A later record for the same body shadows an earlier one, since
   List.assoc_opt returns the first. *)
let executor recording : Openrouter_transport.executor =
 fun ~endpoint:_ ~api_key:_ ~body ->
  match List.assoc_opt body recording with
  | Some (status, response_body) -> Ok (status, response_body)
  | None ->
      let preview =
        if String.length body > 80 then String.sub body 0 80 ^ "..." else body
      in
      Error ("replay miss: no recorded response for request body: " ^ preview)
