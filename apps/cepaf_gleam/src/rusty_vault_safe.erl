%%% Safe wrapper around rusty_vault_nif — catches Undef when the NIF .so is
%%% not loaded (test env), so callers get a typed Result instead of a panic.
%%%
%%% Pass-23: lets vault_supervisor.attempt_passphrase_unseal call the kek_chain
%%% NIF entries in environments where the .so is loaded (production) AND in
%%% environments where it isn't (gleam test before native build), without
%%% crashing the Gleam side.

-module(rusty_vault_safe).

-export([
    safe_kek_derive/2,
    safe_kek_generate_salt/0,
    safe_kek_tpm_present/1,
    vault_kv_put/5
]).

%% Pass-3 Slice B wire — typed Gleam-friendly result for vault_kv_put.
%% Module name is `rusty_vault_nif_safe` per vault.gleam @external attribute;
%% wired here in `rusty_vault_safe` as a sibling. Returns one of:
%%   {nif_put_ok, Version, LeaseId} | nif_put_sealed | nif_put_storage_error
%%   nif_put_ttl_expired | {nif_put_other, Reason}
vault_kv_put(Handle, Name, Value, Ttl, MaxTtl) ->
    try rusty_vault_nif:vault_kv_put(Handle, Name, Value, Ttl, MaxTtl) of
        {ok, #{version := V, lease_id := L}} ->
            {nif_put_ok, V, L};
        {error, sealed} ->
            nif_put_sealed;
        {error, storage_error} ->
            nif_put_storage_error;
        {error, ttl_expired} ->
            nif_put_ttl_expired;
        Other ->
            ReasonStr = iolist_to_binary(io_lib:format("~p", [Other])),
            {nif_put_other, ReasonStr}
    catch
        error:undef ->
            {nif_put_other, <<"nif_unavailable">>};
        error:{load_failed, _} ->
            {nif_put_other, <<"nif_load_failed">>};
        Class:Reason ->
            ReasonStr = iolist_to_binary(io_lib:format("~p:~p", [Class, Reason])),
            {nif_put_other, ReasonStr}
    end.

%% Returns {ok, Binary} | {error, {Code, Msg}}
%% Code = "salt_too_short" | "bad_param" | "derive_failed" | "bad_output_len"
%%      | "nif_unavailable"
safe_kek_derive(Pass, Salt) ->
    try rusty_vault_nif:kek_derive_master_key(Pass, Salt) of
        Result -> Result
    catch
        error:undef ->
            {error, {<<"nif_unavailable">>, <<"rusty_vault_nif not loaded">>}};
        error:{load_failed, _} ->
            {error, {<<"nif_unavailable">>, <<"rusty_vault_nif load_failed">>}};
        Class:Reason ->
            ReasonStr = iolist_to_binary(io_lib:format("~p:~p", [Class, Reason])),
            {error, {<<"nif_exception">>, ReasonStr}}
    end.

%% Returns {ok, Binary} | {error, Msg}
safe_kek_generate_salt() ->
    try rusty_vault_nif:kek_generate_salt() of
        Result -> Result
    catch
        error:undef -> {error, <<"nif_unavailable">>};
        error:{load_failed, _} -> {error, <<"nif_unavailable">>};
        Class:Reason ->
            ReasonStr = iolist_to_binary(io_lib:format("~p:~p", [Class, Reason])),
            {error, ReasonStr}
    end.

%% Returns Bool (false on NIF unavailable — fail-safe)
safe_kek_tpm_present(OverridePath) ->
    try rusty_vault_nif:kek_tpm_present(OverridePath) of
        Result when is_boolean(Result) -> Result
    catch
        _:_ -> false
    end.
