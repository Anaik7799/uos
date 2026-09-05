(** Deterministic replay executor for {!Openrouter_transport.submit}.

    Given a recording of provider responses keyed by request body, this returns
    the pinned response for a matching request and refuses -- without ever
    reaching the network -- on a miss. Replay is therefore byte-identical run to
    run: the candidate's full [submit -> decode] path is exercised offline, which
    is what makes it a deterministic-replay seam rather than a live call. Today
    [Parity_compare] tests request shaping and decoding separately and never
    drives [submit]; this closes that gap.

    A recording is pure data. There is no IO here and no network code, so a
    replay cannot depend on anything outside its arguments. Persisting a
    recording to a pinned session fixture is a separate concern (the keystone
    Session_fixture module). *)

type recording

val empty : recording

val record :
  request_body:string -> status:int -> response_body:string -> recording -> recording
(** Add a [request body -> (status, response body)] entry. A later entry for the
    same body shadows an earlier one. *)

val of_list : (string * (int * string)) list -> recording
(** [of_list [(request_body, (status, response_body)); ...]] *)

val size : recording -> int

val executor : recording -> Openrouter_transport.executor
(** The executor to hand to {!Openrouter_transport.submit}. Returns the pinned
    [(status, response_body)] for a request whose rendered body is recorded; on a
    miss returns an [Error] naming the miss. It makes no network call in either
    case -- there is no network code to make one. *)
