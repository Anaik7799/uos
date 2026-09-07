%% Bounded, local Linux storage interpreter for uos_tui/session_sync.
%% Policy and replay live in Gleam. This shim never executes shell commands.
%% Journal records are immutable: one synced file per commit, then directory fsync.
%% Authority is the owning Unix account, not an unauthenticated remote board.
-module(session_sync_ffi).
-include_lib("kernel/include/file.hrl").
-export([transact/2, read/1, recover_lock/1, halt/1, unique_id/0]).

-define(MAX_EVENTS, 65536).
-define(MAX_BYTES, 67108864).
-define(MAX_EVENT, 65536).

-spec halt(integer()) -> no_return().
halt(Code) -> erlang:halt(Code).

-spec unique_id() -> binary().
unique_id() -> binary:encode_hex(crypto:strong_rand_bytes(16), lowercase).

-spec read(binary()) -> {ok, binary()} | {error, binary()}.
read(Root) -> guarded(fun() ->
    check_root(Root),
    {_, Body} = read_events(Root),
    {ok, Body}
end).

%% Callback returns {ok, {one_new_record_or_empty, receipt_json}}.
-spec transact(binary(), fun((binary(), binary(), binary(), integer(), integer()) -> term())) -> term().
transact(Root, Fun) -> guarded(fun() ->
    ensure_root(Root),
    Lock = filename:join(Root, <<"transaction.lock">>),
    Owner = owner(),
    acquire(Lock, Owner, 40),
    try
        {Count, Journal} = read_events(Root),
        {Host, Boot, Tick, Wall} = clock(),
        case Fun(Journal, Host, Boot, Tick, Wall) of
            {ok, {<<>>, Receipt}} -> {ok, Receipt};
            {ok, {Line, Receipt}} when is_binary(Line), byte_size(Line) =< ?MAX_EVENT ->
                demand(Count < ?MAX_EVENTS, <<"journal event capacity reached; archive with epoch-preserving migration required">>),
                demand(byte_size(Journal) + byte_size(Line) =< ?MAX_BYTES, <<"journal byte capacity reached">>),
                commit(Root, Count + 1, Line),
                {ok, Receipt};
            {ok, _} -> {error, <<"event exceeds 64 KiB storage bound">>};
            {error, _} = Error -> Error
        end
    after
        release_lock(Lock, Owner)
    end
end).

%% No time-based stealing: recovery requires Linux boot/PID/start-time evidence
%% that the exact owner is dead. A separate exclusive guard serializes recoverers.
-spec recover_lock(binary()) -> {ok, binary()} | {error, binary()}.
recover_lock(Root) -> guarded(fun() ->
    check_root(Root),
    Guard = filename:join(Root, <<"recovery.lock">>),
    Owner = owner(),
    acquire(Guard, Owner, 0),
    try
        Lock = filename:join(Root, <<"transaction.lock">>),
        case file:read_file(Lock) of
            {error, enoent} -> {ok, <<"no transaction lock">>};
            {ok, Old} ->
                demand(byte_size(Old) < 1024, <<"invalid lock owner record">>),
                demand(dead_owner(Old), <<"lock owner is live or cannot be verified; refused recovery">>),
                case file:read_file(Lock) of
                    {ok, Old} ->
                        ok = file:delete(Lock),
                        sync_dir(Root),
                        {ok, <<"recovered lock of verified dead local owner">>};
                    _ -> {error, <<"lock changed during recovery">>}
                end;
            {error, Why} -> fail(Why)
        end
    after release_lock(Guard, Owner)
    end
end).

guarded(Fun) ->
    try Fun()
    catch
        throw:{storage, Reason} -> {error, Reason};
        error:{badmatch, {error, Reason}} -> {error, reason(Reason)};
        Class:Reason -> {error, iolist_to_binary(io_lib:format("storage ~p: ~p", [Class, Reason]))}
    end.

fail(Reason) -> throw({storage, reason(Reason)}).
reason(Reason) when is_binary(Reason) -> Reason;
reason(Reason) when is_atom(Reason) -> atom_to_binary(Reason, utf8).
demand(true, _) -> ok;
demand(false, Reason) -> fail(Reason).

check_path(Root) ->
    demand(is_binary(Root) andalso byte_size(Root) > 1 andalso byte_size(Root) < 4096, <<"invalid state path">>),
    demand(filename:pathtype(Root) =:= absolute, <<"state path must be absolute">>),
    demand(binary:match(Root, <<0>>) =:= nomatch, <<"NUL in state path">>),
    demand(not lists:member(<<"..">>, filename:split(Root)), <<"parent traversal in state path">>).

private_dir(Path) ->
    case file:read_link_info(Path) of
        {ok, #file_info{type = directory, mode = Mode}} ->
            demand(Mode band 8#077 =:= 0, <<"state directories must have mode 0700">>);
        {ok, _} -> fail(<<"state path must be a real directory, never a symlink">>);
        {error, Why} -> fail(Why)
    end.

check_root(Root) ->
    check_path(Root),
    private_dir(Root),
    private_dir(filename:join(Root, <<"events">>)).

ensure_dir(Path) ->
    case file:make_dir(Path) of
        ok -> ok = file:change_mode(Path, 8#700);
        {error, eexist} -> private_dir(Path);
        {error, Why} -> fail(Why)
    end.

ensure_root(Root) ->
    check_path(Root),
    ensure_dir(Root),
    ensure_dir(filename:join(Root, <<"events">>)),
    sync_dir(Root).

acquire(Path, Owner, Attempts) ->
    case file:open(Path, [write, exclusive, raw, binary]) of
        {ok, Fd} ->
            try
                ok = file:change_mode(Path, 8#600),
                ok = file:write(Fd, Owner),
                ok = file:sync(Fd)
            after file:close(Fd)
            end,
            sync_dir(filename:dirname(Path));
        {error, eexist} when Attempts > 0 ->
            timer:sleep(50),
            acquire(Path, Owner, Attempts - 1);
        {error, eexist} -> fail(<<"transaction busy; retry same op_id, or use recover-lock only for a verified dead owner">>);
        {error, Why} -> fail(Why)
    end.

release_lock(Path, Owner) ->
    case file:read_file(Path) of
        {ok, Owner} ->
            ok = file:delete(Path),
            sync_dir(filename:dirname(Path));
        _ -> fail(<<"lock ownership changed; refusing to unlink another owner">>)
    end.

event_name(N) -> iolist_to_binary(io_lib:format("~10..0B.json", [N])).

read_events(Root) ->
    Dir = filename:join(Root, <<"events">>),
    {ok, Names} = file:list_dir(Dir),
    demand(length(Names) =< ?MAX_EVENTS + 128, <<"journal directory capacity reached">>),
    Files = lists:sort([unicode:characters_to_binary(N) || N <- Names,
        not lists:prefix(".pending-", N)]),
    demand(length(Files) =< ?MAX_EVENTS, <<"journal event capacity reached">>),
    {Next, Bytes, Rev} = lists:foldl(fun(Name, {Index, Size, Acc}) ->
        demand(Name =:= event_name(Index), <<"journal gap or unexpected file; replay refused">>),
        Path = filename:join(Dir, Name),
        {ok, #file_info{type = Kind, size = FileSize}} = file:read_link_info(Path),
        demand(Kind =:= regular andalso FileSize =< ?MAX_EVENT, <<"invalid or oversized event file">>),
        demand(Size + FileSize =< ?MAX_BYTES, <<"journal byte capacity reached">>),
        {ok, Bin} = file:read_file(Path),
        demand(byte_size(Bin) =:= FileSize, <<"event changed during read">>),
        {Index + 1, Size + FileSize, [<<"\n">>, Bin | Acc]}
    end, {1, 0, []}, Files),
    _ = Bytes,
    {Next - 1, iolist_to_binary(lists:reverse(Rev))}.

commit(Root, N, Line) ->
    Dir = filename:join(Root, <<"events">>),
    Target = filename:join(Dir, event_name(N)),
    demand(file:read_link_info(Target) =:= {error, enoent}, <<"immutable event already exists">>),
    Temp = filename:join(Dir, <<".pending-", (unique_id())/binary>>),
    {ok, Fd} = file:open(Temp, [write, exclusive, raw, binary]),
    try
        ok = file:change_mode(Temp, 8#600),
        ok = file:write(Fd, Line),
        ok = file:sync(Fd)
    after file:close(Fd)
    end,
    ok = file:rename(Temp, Target),
    sync_dir(Dir).

sync_dir(Path) ->
    {ok, Fd} = file:open(Path, [read, raw, directory]),
    try ok = file:sync(Fd) after file:close(Fd) end.

trim_read(Path) ->
    {ok, Bin} = file:read_file(Path),
    string:trim(Bin).

clock() ->
    Host = binary:encode_hex(crypto:hash(sha256, trim_read(<<"/etc/machine-id">>)), lowercase),
    Boot = trim_read(<<"/proc/sys/kernel/random/boot_id">>),
    [First | _] = binary:split(trim_read(<<"/proc/uptime">>), <<" ">>, [global]),
    [Seconds, Fraction] = binary:split(First, <<".">>),
    Scale = trunc(math:pow(10, byte_size(Fraction))),
    Tick = binary_to_integer(Seconds) * 1000000 + binary_to_integer(Fraction) * 1000000 div Scale,
    {Host, Boot, Tick, erlang:system_time(microsecond)}.

start_ticks(Pid) ->
    case file:read_file(<<"/proc/", Pid/binary, "/stat">>) of
        {ok, Stat} ->
            %% comm may contain ')' and spaces; the final ') ' precedes field 3.
            Parts = binary:split(Stat, <<") ">>, [global]),
            Fields = [F || F <- binary:split(lists:last(Parts), <<" ">>, [global]), F =/= <<>>],
            case length(Fields) >= 20 of
                true -> {ok, lists:nth(20, Fields)};
                false -> {error, invalid_stat}
            end;
        Other -> Other
    end.

owner() ->
    Pid = list_to_binary(os:getpid()),
    {ok, Start} = start_ticks(Pid),
    Boot = trim_read(<<"/proc/sys/kernel/random/boot_id">>),
    <<Pid/binary, "\n", Boot/binary, "\n", Start/binary, "\n", (unique_id())/binary>>.

dead_owner(Old) ->
    case binary:split(Old, <<"\n">>, [global]) of
        [Pid, Boot, Start, _Nonce] ->
            case Boot =/= trim_read(<<"/proc/sys/kernel/random/boot_id">>) of
                true -> true;
                false ->
                    case catch binary_to_integer(Pid) of
                        N when is_integer(N), N > 0 ->
                            case start_ticks(Pid) of
                                {error, enoent} -> true;
                                {ok, Current} when Current =/= Start -> true;
                                _ -> false
                            end;
                        _ -> false
                    end
            end;
        _ -> false
    end.
