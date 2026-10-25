%% Erlang host module for the Rustler zenoh_nif (C3I native/zenoh_nif, rustler 0.37,
%% zenoh =1.8.0). The library registers itself as 'Elixir.Indrajaal.Native.Zenoh', so
%% erlang:load_nif/2 refuses to load it into any other module (bad_lib). This module
%% carries that name so cepaf_gleam_ffi:zenoh_module/0 resolves to it.
%%
%% The .so is a host-provisioned artifact at priv/zenoh_nif.so, pinned by
%% priv/zenoh_nif.sha256. It is loaded only from priv; there is no fallback into
%% external evidence trees. When the library is absent every stub fails closed
%% with nif_not_loaded.
-module('Elixir.Indrajaal.Native.Zenoh').
-on_load(init/0).

-export([open_session/1]).
-export([zenoh_open_session/1, close_session/1, session_info/1, session_status/1,
         get/2, get_timeout/3, publish/3, put/3, delete/2, publish_batch/2,
         zenoh_verify_proof_token/1, zenoh_verify_session_token/1, zenoh_classify_tier/1,
         subscribe/3, unsubscribe/1, poll_messages/2, subscription_stats/1]).

init() ->
    SoPath = case code:priv_dir(cepaf_gleam) of
        {error, _} -> "priv/zenoh_nif";
        Dir -> filename:join(Dir, "zenoh_nif")
    end,
    case erlang:load_nif(SoPath, 0) of
        ok -> ok;
        {error, {reload, _}} -> ok;
        {error, _Reason} -> ok
    end.

%% Alias used by cepaf_gleam_ffi:zenoh_open/1.
open_session(ConfigJson) -> zenoh_open_session(ConfigJson).

zenoh_open_session(_ConfigJson) -> erlang:nif_error(nif_not_loaded).
close_session(_Session) -> erlang:nif_error(nif_not_loaded).
session_info(_Session) -> erlang:nif_error(nif_not_loaded).
session_status(_Session) -> erlang:nif_error(nif_not_loaded).
get(_Session, _KeyExpr) -> erlang:nif_error(nif_not_loaded).
get_timeout(_Session, _KeyExpr, _TimeoutMs) -> erlang:nif_error(nif_not_loaded).
publish(_Session, _Key, _Payload) -> erlang:nif_error(nif_not_loaded).
put(_Session, _Key, _Payload) -> erlang:nif_error(nif_not_loaded).
delete(_Session, _Key) -> erlang:nif_error(nif_not_loaded).
publish_batch(_Session, _Messages) -> erlang:nif_error(nif_not_loaded).
zenoh_verify_proof_token(_TokenBinary) -> erlang:nif_error(nif_not_loaded).
zenoh_verify_session_token(_TokenBinary) -> erlang:nif_error(nif_not_loaded).
zenoh_classify_tier(_KeyExpr) -> erlang:nif_error(nif_not_loaded).
subscribe(_Session, _KeyExpr, _CallbackPid) -> erlang:nif_error(nif_not_loaded).
unsubscribe(_Subscription) -> erlang:nif_error(nif_not_loaded).
poll_messages(_Subscription, _MaxMessages) -> erlang:nif_error(nif_not_loaded).
subscription_stats(_Subscription) -> erlang:nif_error(nif_not_loaded).
