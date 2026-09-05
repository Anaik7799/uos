%% http M3 (DIVERGENCE 650): SOAK + INDUCED CRASH + supervised recovery — a stock
%% Cowboy node serves a sustained request stream, isolates a crashing handler (the
%% request process dies → 500, the LISTENER + acceptor pool stay up), and keeps
%% serving AFTER the crash, byte-EQ vs pinned OTP-30. Returns a display-independent
%% deterministic verdict {PreOk, BoomStatus, PostOk} = {10, 500, 10}: 10 pre-crash
%% 200s, the induced crash isolated to a 500, 10 post-crash 200s (the node survived).
%% Run one-shot:
%%   zigvm run zigvm_cowboy_m3.beam t --code-path <cowboy|ranch|cowlib/ebin + stdlib+kernel>
%%   erl -pa ... -eval 'io:format("~p~n",[zigvm_cowboy_m3:t()]), init:stop().'
-module(zigvm_cowboy_m3).
-export([t/0, init/2]).

init(Req0, State) ->
    case cowboy_req:path(Req0) of
        <<"/boom">> -> erlang:error(induced_crash);   %% INDUCED CRASH: the handler dies
        _ ->
            Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain">>}, <<"ok">>, Req0),
            {ok, Req, State}
    end.

t() ->
    {ok, _} = ranch_sup:start_link(),
    D = cowboy_router:compile([{'_', [{"/", ?MODULE, []}, {"/boom", ?MODULE, []}]}]),
    {ok, _} = cowboy:start_clear(http, #{socket_opts => [{port,0}], num_acceptors => 4},
                                 #{env => #{dispatch => D}}),
    Port = ranch:get_port(http),
    PreOk    = soak(Port, "/", 10),         %% SOAK: 10 good requests, all 200
    BoomStat = req(Port, "/boom"),          %% INDUCED CRASH → isolated to a 500
    PostOk   = soak(Port, "/", 10),         %% node STAYS UP: 10 more, all 200
    {PreOk, BoomStat, PostOk}.

soak(Port, Path, N) ->
    lists:sum([ case req(Port, Path) of 200 -> 1; _ -> 0 end || _ <- lists:seq(1, N) ]).

req(Port, Path) ->
    {ok, C} = gen_tcp:connect({127,0,0,1}, Port, [binary, {active, false}]),
    ReqBin = iolist_to_binary(["GET ", Path, " HTTP/1.1\r\nHost: localhost:",
                               integer_to_list(Port), "\r\n\r\n"]),
    ok = gen_tcp:send(C, ReqBin),
    ok = inet:setopts(C, [{active, once}]),
    R = receive
            {tcp, C, Resp}     -> status(Resp);
            {tcp_closed, C}    -> closed;
            {tcp_error, C, _E} -> error
        after 3000 -> timeout end,
    gen_tcp:close(C),
    R.

%% parse the 3-digit status code out of "HTTP/1.1 NNN ..." (display-independent).
status(<<"HTTP/1.1 ", A, B, Cc, _/binary>>) -> (A - $0) * 100 + (B - $0) * 10 + (Cc - $0);
status(_) -> malformed.
