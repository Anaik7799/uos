-module(indrajaal_native_zenoh).
-export([open_session/1, put/3, get/2, subscribe/3, load_nif/1]).

load_nif(Path) ->
    case erlang:load_nif(Path, 0) of
        ok -> 
            error_logger:info_msg("  [ffi] Zenoh NIF Loaded Successfully~n"),
            ok;
        Error -> Error
    end.

open_session(Config) ->
    error_logger:info_msg("  [ffi] open_session called with: ~p~n", [Config]),
    {ok, make_ref()}.

put(_Session, _Key, _Payload) ->
    ok.

get(_Session, _Key) ->
    erlang:nif_error(nif_not_loaded).

subscribe(_Session, _Key, _Pid) ->
    erlang:nif_error(nif_not_loaded).
