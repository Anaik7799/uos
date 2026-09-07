%% uos_openrouter_ffi: bounded HTTPS I/O for the OpenRouter advisory worker.
%%
%% Pure OTP (inets + ssl), no NIF, no vendor SDK. The API key is read from the
%% approved environment variable only, is never logged, and never appears in an
%% error value: httpc error terms carry the request URL and reason, not headers.
%% TLS verifies the peer against the system CA bundle with hostname checking.
-module(uos_openrouter_ffi).
-export([has_api_key/0, api_key/0, https_get/2, https_post_json/4]).

-define(CA_BUNDLE, "/etc/ssl/certs/ca-certificates.crt").

has_api_key() ->
    case api_key() of
        {ok, _} -> true;
        _ -> false
    end.

%% {ok, Key} | {error, nil}. Only OPENROUTER_API_KEY is consulted (approved env).
api_key() ->
    case os:getenv("OPENROUTER_API_KEY") of
        false -> {error, nil};
        "" -> {error, nil};
        K -> {ok, list_to_binary(string:trim(K))}
    end.

ssl_opts(Url) ->
    Host = case uri_string:parse(Url) of
        #{host := H} -> H;
        _ -> "openrouter.ai"
    end,
    [{verify, verify_peer},
     {cacertfile, ?CA_BUNDLE},
     {depth, 3},
     {server_name_indication, Host},
     {customize_hostname_check, [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]}].

start() ->
    _ = application:ensure_all_started(inets),
    _ = application:ensure_all_started(ssl),
    ok.

%% GET without credentials (public endpoints only). {ok, {Code, Body}} | {error, Reason}.
https_get(Url, TimeoutMs) ->
    start(),
    U = binary_to_list(Url),
    case httpc:request(get, {U, [{"accept", "application/json"}]},
                       [{timeout, TimeoutMs}, {connect_timeout, min(TimeoutMs, 10000)}, {ssl, ssl_opts(U)}],
                       [{body_format, binary}]) of
        {ok, {{_, Code, _}, _, Body}} -> {ok, {Code, Body}};
        {error, R} -> {error, safe_reason(R)}
    end.

%% POST JSON with a bearer credential. {ok, {Code, Body}} | {error, Reason}.
https_post_json(Url, Key, Body, TimeoutMs) ->
    start(),
    U = binary_to_list(Url),
    Headers = [{"authorization", "Bearer " ++ binary_to_list(Key)},
               {"accept", "application/json"},
               {"http-referer", "https://nas-1.tail55d152.ts.net:4100"},
               {"x-title", "UOS advisory worker"}],
    case httpc:request(post, {U, Headers, "application/json", Body},
                       [{timeout, TimeoutMs}, {connect_timeout, min(TimeoutMs, 10000)}, {ssl, ssl_opts(U)}],
                       [{body_format, binary}]) of
        {ok, {{_, Code, _}, _, RespBody}} -> {ok, {Code, RespBody}};
        {error, R} -> {error, safe_reason(R)}
    end.

%% Reasons are rendered without the request term (which could carry headers).
safe_reason({failed_connect, _}) -> <<"failed_connect">>;
safe_reason(timeout) -> <<"timeout">>;
safe_reason(R) when is_atom(R) -> atom_to_binary(R, utf8);
safe_reason(R) -> iolist_to_binary(io_lib:format("~p", [element(1, R)])).
