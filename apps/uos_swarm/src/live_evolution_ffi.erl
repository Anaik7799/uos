%% Fixed-allowlist BEAM artifact verifier/loader for live evolution.
%% It never constructs atoms from input and never purges or deletes code.
-module(live_evolution_ffi).
-include_lib("kernel/include/file.hrl").
-export([loaded_artifact/1, verify_artifact/3, load_verified/3]).

-define(MAX_BEAM_BYTES, 16777216).

loaded_artifact(Label) ->
    guarded(fun() ->
        {Module, _File} = allowed(Label),
        case code:which(Module) of
            Path when is_list(Path) ->
                Root = filename:dirname(Path),
                {ok, Digest, _Binary, Module, _Path} = inspect(
                    unicode:characters_to_binary(Root), Label, any),
                {ok, {unicode:characters_to_binary(Root), Digest}};
            _ -> fail(<<"allowlisted module has no regular loaded artifact">>)
        end
    end).

verify_artifact(Root, Label, Expected) ->
    guarded(fun() ->
        {ok, Digest, _Binary, _Module, _Path} = inspect(Root, Label, Expected),
        {ok, Digest}
    end).

load_verified(Root, Label, Expected) ->
    guarded(fun() ->
        {ok, Digest, Binary, Module, Path} = inspect(Root, Label, Expected),
        Key = {?MODULE, loaded_once, Module},
        demand(persistent_term:get(Key, false) =:= false,
               <<"old-version retention slot already used in this VM">>),
        demand(not erlang:check_old_code(Module),
               <<"active old code exists; refusing a third code version">>),
        case code:load_binary(Module, binary_to_list(Path), Binary) of
            {module, Module} ->
                persistent_term:put(Key, {Digest, Path}),
                {ok, Digest};
            {error, Reason} ->
                fail(iolist_to_binary(io_lib:format("code load failed: ~p", [Reason])))
        end
    end).

inspect(Root, Label, Expected) ->
    demand(is_binary(Root) andalso byte_size(Root) > 1 andalso byte_size(Root) < 4096,
           <<"artifact root must be a bounded absolute path">>),
    demand(filename:pathtype(Root) =:= absolute,
           <<"artifact root must be absolute">>),
    demand(binary:match(Root, <<0>>) =:= nomatch,
           <<"NUL in artifact root">>),
    demand(not lists:member(<<"..">>, filename:split(Root)),
           <<"parent traversal in artifact root">>),
    {Module, File} = allowed(Label),
    Path = filename:join(Root, File),
    {ok, #file_info{type = regular, size = Size}} = file:read_link_info(Path),
    demand(Size > 0 andalso Size =< ?MAX_BEAM_BYTES,
           <<"BEAM artifact size is outside the allowed bound">>),
    {ok, Binary} = file:read_file(Path),
    demand(byte_size(Binary) =:= Size, <<"BEAM artifact changed during read">>),
    Digest = string:lowercase(binary:encode_hex(crypto:hash(sha256, Binary))),
    case Expected of
        any -> ok;
        _ ->
            demand(valid_digest(Expected), <<"expected SHA-256 must be lowercase hex">>),
            demand(crypto:hash_equals(Digest, Expected), <<"artifact SHA-256 mismatch">>)
    end,
    case beam_lib:chunks(Binary, [attributes]) of
        {ok, {Module, _Chunks}} -> ok;
        {ok, {Other, _Chunks}} ->
            fail(iolist_to_binary(io_lib:format(
                "BEAM module mismatch: expected ~p got ~p", [Module, Other])));
        {error, beam_lib, Reason} ->
            fail(iolist_to_binary(io_lib:format("invalid BEAM artifact: ~p", [Reason])))
    end,
    {ok, Digest, Binary, Module, unicode:characters_to_binary(Path)}.

allowed(<<"clock_guard">>) ->
    {'uos_swarm@clock_guard', <<"uos_swarm@clock_guard.beam">>};
allowed(<<"coord">>) ->
    {'uos_swarm@coord', <<"uos_swarm@coord.beam">>};
allowed(<<"live_evolution">>) ->
    {'uos_swarm@live_evolution', <<"uos_swarm@live_evolution.beam">>};
allowed(<<"manager">>) ->
    {'uos_swarm@manager', <<"uos_swarm@manager.beam">>};
allowed(_) -> fail(<<"module is not in the compiled live-evolution allowlist">>).

valid_digest(Digest) when is_binary(Digest), byte_size(Digest) =:= 64 ->
    lists:all(fun(C) ->
        (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f)
    end, binary_to_list(Digest));
valid_digest(_) -> false.

guarded(Fun) ->
    try Fun()
    catch
        throw:{live_evolution, Reason} -> {error, Reason};
        error:{badmatch, {error, Reason}} ->
            {error, iolist_to_binary(io_lib:format("artifact access failed: ~p", [Reason]))};
        Class:Reason ->
            {error, iolist_to_binary(io_lib:format(
                "live evolution loader ~p: ~p", [Class, Reason]))}
    end.

demand(true, _) -> ok;
demand(false, Reason) -> fail(Reason).

fail(Reason) -> throw({live_evolution, Reason}).
