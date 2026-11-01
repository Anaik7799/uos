%% Full live MCP-over-Zenoh round-trip for the ruliad_oracle check.
%%
%% Opens a subscription-capable UOS-ZLP-v3 session, starts the real
%% bridge/zenoh_mcp actor (which subscribes to indrajaal/mcp/request/**),
%% publishes a correctly signed envelope on the request key, and reads the
%% reply off the pinned response key. This is the leg the oracle README could
%% previously only claim by code inspection.
-module(zenoh_live).
-export([run/0, envelope/0]).

-define(SECRET, <<"oracle-probe-secret">>).
-define(TOPIC,  <<"indrajaal/mcp/request/oracle-probe/1">>).
-define(REPLY,  <<"indrajaal/mcp/response/oracle-probe/1">>).

payload() ->
    <<"{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":"
      "{\"name\":\"run_gate\",\"arguments\":{\"check_id\":\"ruliad_oracle\"}}}">>.

json_str(B) ->
    <<$", (binary:replace(B, <<"\"">>, <<"\\\"">>, [global]))/binary, $">>.

envelope() ->
    A = <<"oracle-probe">>, C = <<"claude">>,
    W = <<"/home/an/NAS-setup/uos">>, S = <<"sess-live">>,
    Sig = 'cepaf_gleam@mcp@transports@zenoh':compute_signature(
             ?SECRET, ?TOPIC, ?REPLY, A, C, W, S, payload()),
    iolist_to_binary(
      [<<"{\"topic\":">>, json_str(?TOPIC),
       <<",\"reply_topic\":">>, json_str(?REPLY),
       <<",\"sender_actor\":">>, json_str(A),
       <<",\"client_name\":">>, json_str(C),
       <<",\"workspace_root\":">>, json_str(W),
       <<",\"session_id\":">>, json_str(S),
       <<",\"payload\":">>, json_str(payload()),
       <<",\"signature\":">>, json_str(Sig), <<"}">>]).

run() ->
    io:setopts([{encoding, unicode}]),
    io:format("zlp binary available : ~p~n",
              ['cepaf_gleam@mcp@transports@zlp_hyperplane':is_binary_available()]),
    case 'cepaf_gleam@zenoh@client':open_zlp(4) of
        {error, E} -> io:format("open_zlp ERROR: ~p~n", [E]), halt(1);
        {ok, Sess} ->
            io:format("session backend      : ~ts~n",
                      ['cepaf_gleam@zenoh@client':backend(Sess)]),
            io:format("supports subs        : ~p~n",
                      ['cepaf_gleam@zenoh@client':supports_subscriptions(Sess)]),
            case 'cepaf_gleam@bridge@zenoh_mcp':start(Sess, <<"oracle-probe-node">>) of
                {error, BE} -> io:format("bridge start ERROR   : ~p~n", [BE]), halt(1);
                {ok, Subj} ->
                    io:format("bridge               : started~n"),
                    %% zenohd here has no storage plugin for this keyexpr, so a
                    %% get() after put() returns nothing. The reply must be
                    %% observed by SUBSCRIBING to the pinned response key.
                    Collector = spawn(fun() -> collect(0) end),
                    _ = 'cepaf_gleam@zenoh@client':subscribe(
                          Sess, <<"indrajaal/mcp/response/**">>, Collector),
                    timer:sleep(600),
                    Env = envelope(),
                    %% Publish on the request key through the session.
                    P = 'cepaf_gleam@zenoh@client':put(Sess, ?TOPIC, Env),
                    io:format("put request          : ~p~n", [P]),
                    %% The subscription is asynchronous; also drive the actor
                    %% directly so the test distinguishes "bridge logic works"
                    %% from "subscription delivery works".
                    %% NO manual hand-off. The subscription is the only path,
                    %% so a reply proves the bridge decoded the ZLP push itself.
                    _ = Subj,
                    timer:sleep(4000),
                    Collector ! {report, self()},
                    receive {replies, N, Keys} ->
                        io:format("pushes observed      : ~p~n", [N]),
                        lists:foreach(fun(K) ->
                            io:format("  key                : ~ts~n", [K]) end, Keys)
                    after 3000 -> io:format("collector timeout~n") end,
                    halt(0)
            end
    end.

fmt({ok, B}) -> binary:part(B, 0, min(420, byte_size(B)));
fmt(Other)   -> iolist_to_binary(io_lib:format("~p", [Other])).

%% Accepts any delivery shape, so the collector itself cannot be the reason a
%% reply is not seen.
collect(N) -> collect(N, []).
collect(N, Keys) ->
    receive
        {report, From} -> From ! {replies, N, lists:reverse(Keys)};
        {zlp_zenoh_push, _, _, _, Json} ->
            K = try maps:get(<<"key">>, json:decode(Json)) catch _:_ -> <<"?">> end,
            collect(N + 1, [K | Keys]);
        _Other -> collect(N + 1, [<<"non-push">> | Keys])
    end.
