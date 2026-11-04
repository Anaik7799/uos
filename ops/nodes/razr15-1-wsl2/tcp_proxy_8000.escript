main(_) ->
    {ok, Listen} = gen_tcp:listen(8000, [binary, {packet, 0}, {active, false}, {reuseaddr, true}]),
    accept_loop(Listen).

accept_loop(Listen) ->
    case gen_tcp:accept(Listen) of
        {ok, Client} ->
            spawn(fun() -> handle_client(Client) end),
            accept_loop(Listen);
        _ ->
            accept_loop(Listen)
    end.

handle_client(Client) ->
    case gen_tcp:connect({172,17,154,247}, 8000, [binary, {packet, 0}, {active, false}], 5000) of
        {ok, Upstream} ->
            Self = self(),
            spawn(fun() -> pipe(Client, Upstream), Self ! done end),
            spawn(fun() -> pipe(Upstream, Client), Self ! done end),
            receive done -> ok end,
            receive done -> ok end,
            gen_tcp:close(Client),
            gen_tcp:close(Upstream);
        _ ->
            gen_tcp:close(Client)
    end.

pipe(From, To) ->
    case gen_tcp:recv(From, 0, 180000) of
        {ok, Data} ->
            case gen_tcp:send(To, Data) of
                ok -> pipe(From, To);
                _ -> ok
            end;
        _ ->
            gen_tcp:shutdown(To, write)
    end.
