%%% Erlang NIF shim for rusty_vault_nif Rust crate.
%%% SC-VAULT-001..025: secrets vault NIF surface.
%%% Generated alongside lib/cepaf_gleam/native/rusty_vault_nif/src/lib.rs

-module(rusty_vault_nif).

-export([
    vault_init/2,
    vault_unseal/2,
    vault_seal/1,
    vault_status/1,
    vault_kv_put/5,
    vault_kv_get/2,
    vault_kv_versions/2,
    vault_kv_destroy/3,
    vault_lease_renew/3,
    vault_audit_tail/2,
    kek_derive_master_key/2,
    kek_generate_salt/0,
    kek_tpm_present/1
]).

-on_load(init/0).

init() ->
    NifPath = filename:join([code:priv_dir(cepaf_gleam), "rusty_vault_nif"]),
    erlang:load_nif(NifPath, 0).

vault_init(_StoragePath, _AuditPath) -> erlang:nif_error({not_loaded, ?MODULE}).
vault_unseal(_Handle, _MasterKey)    -> erlang:nif_error({not_loaded, ?MODULE}).
vault_seal(_Handle)                  -> erlang:nif_error({not_loaded, ?MODULE}).
vault_status(_Handle)                -> erlang:nif_error({not_loaded, ?MODULE}).
vault_kv_put(_Handle, _Name, _Value, _Ttl, _MaxTtl) ->
    erlang:nif_error({not_loaded, ?MODULE}).
vault_kv_get(_Handle, _Name)         -> erlang:nif_error({not_loaded, ?MODULE}).
vault_kv_versions(_Handle, _Name)    -> erlang:nif_error({not_loaded, ?MODULE}).
vault_kv_destroy(_Handle, _Name, _Version) ->
    erlang:nif_error({not_loaded, ?MODULE}).
vault_lease_renew(_Handle, _LeaseId, _Ttl) ->
    erlang:nif_error({not_loaded, ?MODULE}).
vault_audit_tail(_Handle, _SinceTs)  -> erlang:nif_error({not_loaded, ?MODULE}).
kek_derive_master_key(_Pass, _Salt)  -> erlang:nif_error({not_loaded, ?MODULE}).
kek_generate_salt()                  -> erlang:nif_error({not_loaded, ?MODULE}).
kek_tpm_present(_OverridePath)       -> erlang:nif_error({not_loaded, ?MODULE}).
