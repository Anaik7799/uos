-module(indrajaal_native_zenoh).
-export([open_session/1, put/3, get/2, subscribe/3, load_nif/1]).

%% Legacy NIF loader retained for backwards-compatible signature stability;
%% live Zenoh I/O and SSE subscriptions now execute inside OS-isolated
%% supervised OTP 29 Lean 4 + Zig port shards (`uos_zlp_sup` / `uos_zlp_router`)
%% so native faults can never crash beam.smp.
load_nif(Path) ->
    case erlang:load_nif(Path, 0) of
        ok ->
            error_logger:info_msg("  [ffi] Zenoh NIF Loaded Successfully~n"),
            ok;
        Error ->
            Error
    end.

open_session(Config) ->
    _ = case uos_zlp_router:is_binary_available() of
        true -> uos_zlp_sup:ensure_started(4);
        false -> {error, zlp_port_binary_not_built}
    end,
    error_logger:info_msg("  [ffi] open_session called with: ~p~n", [Config]),
    {ok, make_ref()}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L);
to_bin(A) when is_atom(A) -> atom_to_binary(A, utf8).

put(_Session, Key, Payload) ->
    case uos_zlp_sup:is_running() of
        true ->
            case uos_zlp_router:zenoh_publish(to_bin(Key), to_bin(Payload)) of
                {ok, _Receipt} -> ok;
                {error, Reason} -> {error, Reason}
            end;
        false ->
            ok
    end.

get(_Session, Key) ->
    case ensure_zlp_running() of
        ok ->
            case uos_zlp_router:zenoh_get(to_bin(Key)) of
                {ok, #{body := BodyBin}} -> {ok, BodyBin};
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

subscribe(_Session, Key, Pid) when is_pid(Pid) ->
    case ensure_zlp_running() of
        ok ->
            case uos_zlp_router:zenoh_subscribe(to_bin(Key), Pid) of
                {ShardId, {ok, _Receipt}} -> {ok, {zlp_subscription, ShardId, to_bin(Key)}};
                {_ShardId, {error, Reason}} -> {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

ensure_zlp_running() ->
    case uos_zlp_sup:is_running() of
        true ->
            ok;
        false ->
            case uos_zlp_sup:ensure_started(4) of
                {ok, _} -> ok;
                {error, Reason} -> {error, Reason}
            end
    end.
