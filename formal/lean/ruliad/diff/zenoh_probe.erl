%% Live probe of the Zenoh MCP ingress for the ruliad_oracle check.
%%
%% The oracle README previously claimed Zenoh reach "by code inspection". This
%% module replaces that with an observation: it builds a correctly signed
%% uos-mcp-zenoh-v1 envelope, feeds it to the real ingress
%% runtime_gateway:handle_zenoh_raw/2 that bridge/zenoh_mcp.gleam calls, and
%% prints the reply topic and body. It also runs the negative control: a forged
%% signature must not produce a reply.
-module(zenoh_probe).
-export([run/1]).

-define(SECRET, <<"oracle-probe-secret">>).
-define(TOPIC,  <<"indrajaal/mcp/request/oracle-probe/1">>).
%% The reply destination is PINNED by the transport, derived from the request
%% topic: it is never taken from untrusted input. A caller-chosen reply key is
%% refused with FOREIGN_REPLY_DESTINATION_FORBIDDEN, which is an exfiltration
%% guard worth stating: a signed envelope cannot redirect its own answer.
-define(REPLY,  <<"indrajaal/mcp/response/oracle-probe/1">>).
-define(ACTOR,  <<"oracle-probe">>).
-define(CLIENT, <<"claude">>).
-define(ROOT,   <<"/home/an/NAS-setup/uos">>).
-define(SESS,   <<"sess-1">>).

jsonrpc() -> jsonrpc(call).

jsonrpc(init) ->
    <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":"
      "{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},"
      "\"clientInfo\":{\"name\":\"oracle-probe\",\"version\":\"1\"}}}">>;
jsonrpc(list) ->
    <<"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}">>;
jsonrpc(ping) ->
    <<"{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"ping\",\"params\":{}}">>;
jsonrpc(call) ->
    <<"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":"
      "{\"name\":\"run_gate\",\"arguments\":{\"check_id\":\"ruliad_oracle\"}}}">>.

%% Minimal JSON string encoder for the one field that needs it.
json_str(B) ->
    E = binary:replace(B, <<"\"">>, <<"\\\"">>, [global]),
    <<$", E/binary, $">>.

envelope(Sig) -> envelope(Sig, jsonrpc()).

envelope(Sig, Pay) -> envelope_p(Sig, Pay).

envelope_p(Sig, Pay) ->
    iolist_to_binary(
      [<<"{\"topic\":">>, json_str(?TOPIC),
       <<",\"reply_topic\":">>, json_str(?REPLY),
       <<",\"sender_actor\":">>, json_str(?ACTOR),
       <<",\"client_name\":">>, json_str(?CLIENT),
       <<",\"workspace_root\":">>, json_str(?ROOT),
       <<",\"session_id\":">>, json_str(?SESS),
       <<",\"payload\":">>, json_str(Pay),
       <<",\"signature\":">>, json_str(Sig), <<"}">>]).

signature() -> signature(jsonrpc()).

signature(Pay) ->
    'cepaf_gleam@mcp@transports@zenoh':compute_signature(
      ?SECRET, ?TOPIC, ?REPLY, ?ACTOR, ?CLIENT, ?ROOT, ?SESS, Pay).

probe(Label, Kind) ->
    Pay = jsonrpc(Kind),
    Env = envelope_p(signature(Pay), Pay),
    case 'cepaf_gleam@mcp@runtime_gateway':handle_zenoh_raw(?TOPIC, Env) of
        {some, {RTopic, Body}} ->
            io:format("~-10s -> REPLY on ~ts~n             ~ts~n",
                      [Label, RTopic, binary:part(Body, 0, min(300, byte_size(Body)))]);
        none -> io:format("~-10s -> none~n", [Label])
    end.

run(_) ->
    io:setopts([{encoding, unicode}]),
    Sig = signature(),
    io:format("signature      : ~s...~n", [binary:part(Sig, 0, 24)]),

    Env = envelope(Sig),
    io:format("envelope bytes : ~p~n", [byte_size(Env)]),
    probe("initialize", init),
    probe("ping", ping),
    probe("tools/list", list),
    probe("tools/call", call),

    %% Negative control: forge one hex digit of the signature.
    Forged = case Sig of
                 <<$A, Rest/binary>> -> <<$B, Rest/binary>>;
                 <<_, Rest/binary>>  -> <<$A, Rest/binary>>
             end,
    case 'cepaf_gleam@mcp@runtime_gateway':handle_zenoh_raw(?TOPIC, envelope(Forged)) of
        {some, {_, B2}} ->
            io:format("FORGED  -> REPLIED (fence FAILED): ~ts~n",
                      [binary:part(B2, 0, min(200, byte_size(B2)))]);
        none ->
            io:format("FORGED  -> none (silently dropped, fence HELD)~n")
    end,

    %% Negative control: a topic outside the request namespace.
    Bad = <<"indrajaal/mcp/evil/oracle-probe/1">>,
    case 'cepaf_gleam@mcp@runtime_gateway':handle_zenoh_raw(Bad, Env) of
        {some, _} -> io:format("BADTOPIC-> REPLIED (guard FAILED)~n");
        none      -> io:format("BADTOPIC-> none (refused, guard HELD)~n")
    end,
    halt(0).
