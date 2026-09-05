-module(httpd_gs).
-behaviour(gen_server).
-export([serve/0, init/1, handle_call/3, handle_cast/2]).
init(N) -> {ok, N}.
handle_call(next, _F, N) -> {reply, N+1, N+1}.
handle_cast(_, N) -> {noreply, N}.
serve() ->
    {ok, _} = gen_server:start({local, counter}, ?MODULE, 0, []),
    {ok, L} = gen_tcp:listen(8231, [binary,{active,false},{reuseaddr,true}]),
    R = loop(L, 60),
    gen_tcp:close(L), R.
loop(_, 0) -> timeout;
loop(L, K) ->
    case gen_tcp:accept(L) of
        {ok, S} ->
            _ = gen_tcp:recv(S, 0),
            Cnt = gen_server:call(counter, next),
            Body = integer_to_binary(Cnt),
            gen_tcp:send(S, [<<"HTTP/1.1 200 OK\r\nContent-Length: ">>,
                             integer_to_binary(byte_size(Body)),
                             <<"\r\nConnection: close\r\n\r\n">>, Body]),
            gen_tcp:close(S), served;
        {error, timeout} -> loop(L, K-1);
        {error, E} -> {error, E}
    end.
