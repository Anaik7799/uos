-module(httpd).
-export([serve/0]).
serve() ->
    {ok, L} = gen_tcp:listen(8099, [binary, {active,false}, {reuseaddr,true}]),
    R = accept_loop(L, 100),
    gen_tcp:close(L),
    R.
accept_loop(_L, 0) -> timeout;
accept_loop(L, N) ->
    case gen_tcp:accept(L) of
        {ok, S} ->
            {ok, _Req} = gen_tcp:recv(S, 0),
            gen_tcp:send(S, <<"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nhi\n">>),
            gen_tcp:close(S),
            served;
        {error, timeout} -> accept_loop(L, N-1);
        {error, E} -> {error, E}
    end.
