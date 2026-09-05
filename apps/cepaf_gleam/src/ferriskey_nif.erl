%% =============================================================================
%% [C3I-SIL6-MSTS] ferriskey_nif Erlang load shim
%% =============================================================================
%% Loads the ferriskey_nif cdylib at module init. Functions below are stubs
%% replaced by the real NIF implementations once the .so is loaded; calls
%% before load complete return `{:error, "nif_not_loaded"}`.
%%
%% Pattern: parity with src/c3i_nif.erl (lines 1-50). Same on_load semantics.
%%
%% STAMP: SC-FERRISKEY-NIF-001 (load on BEAM start),
%%        SC-FERRISKEY-NIF-009 (panic isolation via rustler).
%% =============================================================================
-module(ferriskey_nif).

-export([
    ferriskey_ping/0,
    ferriskey_db_init/1,
    ferriskey_realm_create/4,
    ferriskey_realm_get/2,
    ferriskey_realm_list/1,
    ferriskey_realm_delete/2,
    ferriskey_user_create/5,
    ferriskey_user_get/2,
    ferriskey_user_list/2,
    ferriskey_user_update/3,
    ferriskey_user_delete/2,
    ferriskey_user_password_verify/3,
    ferriskey_user_list_filtered/3,
    ferriskey_group_create/4,
    ferriskey_group_list/2,
    ferriskey_group_add_member/3,
    ferriskey_group_remove_member/3,
    ferriskey_role_create/5,
    ferriskey_role_list/2,
    ferriskey_role_assign/4,
    ferriskey_role_revoke/3,
    ferriskey_signing_key_rotate/3,
    ferriskey_token_issue/6,
    ferriskey_token_validate/2,
    ferriskey_jwks_publish/2,
    ferriskey_jwks_get_cached/2,
    ferriskey_gcp_sts_exchange/8,
    ferriskey_gcp_sts_cache_get/2,
    ferriskey_gcp_sts_cache_invalidate/2,
    ferriskey_signing_key_export_seed/2,
    ferriskey_signing_key_purge_local/2,
    ferriskey_token_issue_with_seed/8,
    ferriskey_scim_filter_parse/1,
    ferriskey_scim_user_to_internal/2,
    ferriskey_scim_internal_to_user/3,
    ferriskey_scim_outbound_enqueue/5,
    ferriskey_scim_outbound_drain/3,
    ferriskey_gcp_impersonate/5,
    ferriskey_gcp_deny_policy_apply/5,
    ferriskey_gcp_id_token/4,
    ferriskey_gcp_iam_policy_get/3,
    ferriskey_gcp_iam_policy_set/4,
    ferriskey_gcp_recommender_list/2,
    ferriskey_gcp_policy_troubleshoot/3,
    ferriskey_gcp_policy_analyze/1,
    ferriskey_gcp_org_policy_list/1,
    ferriskey_gcp_directory_user_list/1,
    ferriskey_gcp_cloud_identity_groups_list/1,
    ferriskey_gcp_directory_user_create/4,
    ferriskey_gcp_directory_user_get/1,
    ferriskey_gcp_directory_user_update/2,
    ferriskey_gcp_directory_user_delete/1,
    ferriskey_gcp_cloud_identity_group_create/4,
    ferriskey_gcp_cloud_identity_group_get/1,
    ferriskey_gcp_cloud_identity_group_update/2,
    ferriskey_gcp_cloud_identity_group_delete/1
]).

-on_load(init/0).

init() ->
    PrivDir = case code:priv_dir(cepaf_gleam) of
        {error, _} ->
            EbinDir = filename:dirname(code:which(?MODULE)),
            AppPath = filename:dirname(EbinDir),
            filename:join(AppPath, "priv");
        Path -> Path
    end,
    Lib = filename:join(PrivDir, "ferriskey_nif"),
    erlang:load_nif(Lib, 0).

ferriskey_ping() ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_db_init(_DbPath) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_realm_create(_DbPath, _Name, _IssuerUrl, _GcpBindingJson) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_realm_get(_DbPath, _IdOrName) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_realm_list(_DbPath) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_realm_delete(_DbPath, _Id) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_user_create(_DbPath, _RealmId, _Username, _Email, _Password) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_user_get(_DbPath, _IdOrSub) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_user_list(_DbPath, _RealmId) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_user_update(_DbPath, _Id, _FieldsJson) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_user_delete(_DbPath, _Id) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_user_password_verify(_DbPath, _Id, _Password) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_user_list_filtered(_DbPath, _RealmId, _ScimFilter) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_group_create(_DbPath, _RealmId, _Name, _DisplayName) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_group_list(_DbPath, _RealmId) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_group_add_member(_DbPath, _GroupId, _UserId) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_group_remove_member(_DbPath, _GroupId, _UserId) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_role_create(_DbPath, _RealmId, _Name, _LayerMask, _RequiresMfa) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_role_list(_DbPath, _RealmId) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_role_assign(_DbPath, _UserId, _RoleId, _GrantedBy) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_role_revoke(_DbPath, _UserId, _RoleId) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_signing_key_rotate(_DbPath, _RealmId, _Alg) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_token_issue(_DbPath, _RealmId, _UserId, _Audience, _ScopesCsv, _TtlSeconds) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_token_validate(_DbPath, _Jwt) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_jwks_publish(_DbPath, _RealmId) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_jwks_get_cached(_DbPath, _RealmId) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_sts_exchange(_DbPath, _RealmId, _Sub, _Audience, _Scope, _TargetSa, _SubjectToken, _DryRun) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_sts_cache_get(_DbPath, _CacheKey) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_sts_cache_invalidate(_DbPath, _CacheKey) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_signing_key_export_seed(_DbPath, _Kid) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_signing_key_purge_local(_DbPath, _Kid) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_token_issue_with_seed(_DbPath, _RealmId, _UserId, _Audience, _ScopesCsv, _TtlSeconds, _Kid, _SeedB64) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_scim_filter_parse(_Filter) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_scim_user_to_internal(_ScimJson, _RealmId) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_scim_internal_to_user(_DbPath, _UserId, _BaseUrl) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_scim_outbound_enqueue(_DbPath, _Target, _Op, _ResourceType, _Payload) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_scim_outbound_drain(_DbPath, _Now, _Limit) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_impersonate(_TargetSa, _ScopesCsv, _LifetimeSeconds, _Bearer, _DryRun) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_deny_policy_apply(_AttachmentPoint, _PolicyId, _RulesJson, _Bearer, _DryRun) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_id_token(_TargetSa, _Audience, _Bearer, _DryRun) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_iam_policy_get(_Resource, _Bearer, _DryRun) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_iam_policy_set(_Resource, _PolicyJson, _Bearer, _DryRun) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_recommender_list(_ProjectId, _Location) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_policy_troubleshoot(_Principal, _ResourceFullName, _Permission) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_policy_analyze(_Scope) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_org_policy_list(_Parent) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_directory_user_list(_Domain) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_cloud_identity_groups_list(_Parent) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_directory_user_create(_PrimaryEmail, _GivenName, _FamilyName, _PasswordHash) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_directory_user_get(_UserKey) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_directory_user_update(_UserKey, _BodyJson) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_directory_user_delete(_UserKey) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_cloud_identity_group_create(_Parent, _GroupKeyId, _DisplayName, _Description) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_cloud_identity_group_get(_Name) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_cloud_identity_group_update(_Name, _BodyJson) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).

ferriskey_gcp_cloud_identity_group_delete(_Name) ->
    erlang:nif_error({nif_not_loaded, ?MODULE, ?LINE}).
