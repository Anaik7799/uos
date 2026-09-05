%% =============================================================================
%% [C3I-SIL6] vault_gcp_sm_io_ffi — Slice D HTTP transport (Phase 3, real httpc)
%% =============================================================================
%% Stub-That-Lies guard ([zk-3346fc607a1ef9e6], RPN 729): real `httpc:request/4`
%% wired against `secretmanager.googleapis.com`. Same strict status mapping +
%% retry policy as `vault_kms_io_ffi`. Per SC-VAULT-005 the sync actor calls
%% this out-of-band only.
%%
%% Strict status mapping:
%%   200 → {ok, Body}
%%   401 → {error, <<"http_unauthorized">>}
%%   403 → {error, <<"http_forbidden">>}
%%   404 → {error, <<"http_not_found">>}    ← secret/version absent
%%   429 → retried, then http_rate_limited
%%   5xx → retried, then http_server_error_NNN
%%   other → http_status_NNN
%% =============================================================================
-module(vault_gcp_sm_io_ffi).

-export([execute_request/4]).

-define(TIMEOUT_MS, 10000).
-define(MAX_RETRIES, 3).

ensure_inets() ->
    _ = application:ensure_all_started(ssl),
    _ = application:ensure_all_started(inets),
    ok.

execute_request(Method, Url, Headers, Body) ->
    ok = ensure_inets(),
    do_request(Method, Url, Headers, Body, 0, 200).

do_request(Method, Url, Headers, Body, Attempt, BackoffMs) when Attempt < ?MAX_RETRIES ->
    case http_call(Method, Url, Headers, Body) of
        {ok, 200, RespBody} ->
            {ok, list_to_binary(RespBody)};
        {ok, 401, _} ->
            {error, <<"http_unauthorized">>};
        {ok, 403, _} ->
            {error, <<"http_forbidden">>};
        {ok, 404, _} ->
            {error, <<"http_not_found">>};
        {ok, 429, _} when Attempt + 1 < ?MAX_RETRIES ->
            timer:sleep(BackoffMs),
            do_request(Method, Url, Headers, Body, Attempt + 1, BackoffMs * 2);
        {ok, 429, _} ->
            {error, <<"http_rate_limited">>};
        {ok, Status, _} when Status >= 500, Status =< 599, Attempt + 1 < ?MAX_RETRIES ->
            timer:sleep(BackoffMs),
            do_request(Method, Url, Headers, Body, Attempt + 1, BackoffMs * 2);
        {ok, Status, _} when Status >= 500, Status =< 599 ->
            {error, list_to_binary("http_server_error_" ++ integer_to_list(Status))};
        {ok, Status, _} ->
            {error, list_to_binary("http_status_" ++ integer_to_list(Status))};
        {error, timeout} when Attempt + 1 < ?MAX_RETRIES ->
            timer:sleep(BackoffMs),
            do_request(Method, Url, Headers, Body, Attempt + 1, BackoffMs * 2);
        {error, timeout} ->
            {error, <<"http_timeout">>};
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
