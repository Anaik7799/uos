%% http-laneC full-boot EQ (DIVERGENCE 648): stock Cowboy boots end-to-end on
%% zigvm and serves a real HTTP request byte-identically to pinned OTP-30.
%% `ranch_sup:start_link` + `cowboy:start_clear` (a 4-acceptor pool → exercises the
%% accept_waiters FIFO queue, DIVERGENCE 647), then the SAME process connects and
%% sends a request whose `Host: localhost:<Port>` header forces cowboy's
%% `cow_http_hd:parse_host` → `binary_to_integer(<<Port>>)` (the FM-DISPATCH-DEAD +
%% sub-binary-read fixes, DIVERGENCE 646). Returns a DISPLAY-INDEPENDENT deterministic
%% verdict `{Status200, BodyOk}` (both booleans) so the two VMs' outputs are byte-EQ
%% without tripping over the non-deterministic Date header or the erlang:display
%% printable-binary form. Run one-shot (NOT --resident — the fn returns its verdict):
%%   zigvm run zigvm_cowboy_det.beam t --code-path <cowboy|ranch|cowlib/ebin + stdlib+kernel>
%%   erl -pa ... -eval 'io:format("~p~n",[zigvm_cowboy_det:t()]), init:stop().'
-module(zigvm_cowboy_det).
-export([t/0, init/2]).

init(Req0, State) ->
    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain">>},
                           <<"hello from zigvm cowboy">>, Req0),
    {ok, Req, State}.

t() ->
    {ok, _} = ranch_sup:start_link(),
    D = cowboy_router:compile([{'_', [{"/", ?MODULE, []}]}]),
    {ok, _} = cowboy:start_clear(http, #{socket_opts => [{port, 0}], num_acceptors => 4},
                                 #{env => #{dispatch => D}}),
    Port = ranch:get_port(http),
    HostHdr = iolist_to_binary(["Host: localhost:", integer_to_list(Port), "\r\n"]),
    ReqBin = <<"GET / HTTP/1.1\r\n", HostHdr/binary, "\r\n">>,
    {ok, C} = gen_tcp:connect({127,0,0,1}, Port, [binary, {active, false}]),
    ok = gen_tcp:send(C, ReqBin),
    ok = inet:setopts(C, [{active, once}]),
    receive
        {tcp, C, Resp} ->
            Status200 = binary:part(Resp, 0, 15) =:= <<"HTTP/1.1 200 OK">>,
            BodyOk = binary:match(Resp, <<"hello from zigvm cowboy">>) =/= nomatch,
            {Status200, BodyOk};
        {tcp_closed, C} -> closed
    after 5000 -> timeout end.
