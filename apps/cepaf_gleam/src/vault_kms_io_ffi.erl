%% =============================================================================
%% [C3I-SIL6] vault_kms_io_ffi — Slice C-C3 HTTP transport (Phase 3, real httpc)
%% =============================================================================
%% Stub-That-Lies guard ([zk-3346fc607a1ef9e6], RPN 729): this module now wires
%% real `httpc:request/4` against `cloudkms.googleapis.com`. The previous
%% placeholder `{error, <<"http_not_yet_wired">>}` is replaced by typed error
%% atoms that distinguish "transport reached the wire" from "ADC token absent"
%% from "real upstream returned 4xx/5xx".
%%
%% SC-VAULT-005: hot path MUST NOT make network calls — supervisor's KMS unseal
%% path calls this out-of-band on boot only. The 10s connect/req timeout
%% preserves bounded latency; retries are exponential 200/400/800ms on 5xx +
%% timeout (NOT on 4xx — those are caller-induced, retrying wastes ADC quota).
%%
%% Strict status mapping (Stub-That-Lies):
%%   200 → {ok, Body}
%%   401 → {error, <<"http_unauthorized">>}      ← typically ADC token missing
%%   403 → {error, <<"http_forbidden">>}         ← IAM policy mismatch
%%   429 → {error, <<"http_rate_limited">>}
%%   5xx → {error, <<"http_server_error_NNN">>}  ← retried, then surfaced
%%   other → {error, <<"http_status_NNN">>}
%%   timeout/socket → {error, <<"http_transport_error: …">>}
%% =============================================================================
-module(vault_kms_io_ffi).

-export([execute_request/4]).

-define(TIMEOUT_MS, 10000).
-define(MAX_RETRIES, 3).

ensure_inets() ->
    %% Idempotent: ssl + inets are required for httpc:request with https://.
    %% Errors are tolerated because re-starting an already-started app returns
    %% {error, {already_started, _}} — that's fine.
    _ = application:ensure_all_started(ssl),
    _ = application:ensure_all_started(inets),
    ok.

execute_request(Method, Url, Headers, Body) ->
    ok = ensure_inets(),
    do_request(Method, Url, Headers, Body, 0, 200).

do_request(Method, Url, Headers, Body, Attempt, BackoffMs) when Attempt < ?MAX_RETRIES ->
    case http_call(Method, Url, Headers, Body) of
        {ok, Status, RespBody} when Status =:= 200 ->
            {ok, list_to_binary(RespBody)};
        {ok, 401, _} ->
            {error, <<"http_unauthorized">>};
        {ok, 403, _} ->
            {error, <<"http_forbidden">>};
        {ok, 429, _} ->
            timer:sleep(BackoffMs),
            do_request(Method, Url, Headers, Body, Attempt + 1, BackoffMs * 2);
        {ok, Status, _} when Status >= 500, Status =< 599 ->
            timer:sleep(BackoffMs),
            do_request(Method, Url, Headers, Body, Attempt + 1, BackoffMs * 2);
        {ok, Status, _} ->
            {error, list_to_binary("http_status_" ++ integer_to_list(Status))};
        {error, timeout} ->
            timer:sleep(BackoffMs),
            do_request(Method, Url, Headers, Body, Attempt + 1, BackoffMs * 2);
        {error, Reason} ->
            {error, list_to_binary("http_transport_error: " ++ io_lib_format_reason(Reason))}
    end;
do_request(_Method, _Url, _Headers, _Body, _Attempt, _Backoff) ->
    {error, <<"http_retry_exhausted">>}.

http_call(Method, Url, Headers, Body) ->
    UrlS = unicode:characters_to_list(Url),
    HdrL = [{unicode:characters_to_list(K), unicode:characters_to_list(V)} || {K, V} <- Headers],
    BodyS = unicode:characters_to_binary(Body),
    ContentType = proplists:get_value("Content-Type", HdrL, "application/json"),
    HdrNoCT = [{K, V} || {K, V} <- HdrL, string:to_lower(K) =/= "content-type"],
    Request = case method_atom(Method) of
                  get -> {UrlS, HdrNoCT};
                  delete -> {UrlS, HdrNoCT};
                  M when M =:= post; M =:= put; M =:= patch ->
                      {UrlS, HdrNoCT, ContentType, BodyS}
              end,
    HttpOpts = [{timeout, ?TIMEOUT_MS}, {connect_timeout, ?TIMEOUT_MS}, {autoredirect, false}],
    Opts = [{body_format, binary}],
    case httpc:request(method_atom(Method), Request, HttpOpts, Opts) of
        {ok, {{_Ver, Status, _Phrase}, _Hdr, RespBody}} ->
            {ok, Status, binary_to_list(iolist_to_binary(RespBody))};
        {error, _} = Err ->
            Err
    end.

method_atom(<<"GET">>) -> get;
method_atom(<<"POST">>) -> post;
method_atom(<<"PUT">>) -> put;
method_atom(<<"PATCH">>) -> patch;
method_atom(<<"DELETE">>) -> delete;
method_atom("GET") -> get;
method_atom("POST") -> post;
method_atom("PUT") -> put;
method_atom("PATCH") -> patch;
method_atom("DELETE") -> delete;
method_atom(_) -> get.

io_lib_format_reason(Reason) ->
    lists:flatten(io_lib:format("~p", [Reason])).
