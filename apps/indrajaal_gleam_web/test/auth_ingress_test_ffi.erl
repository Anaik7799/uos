-module(auth_ingress_test_ffi).
-export([with_oidc_env/1]).

with_oidc_env(Fun) ->
    Names = [
        "FERRISKEY_ENABLED",
        "FERRISKEY_ISSUER_URL",
        "FERRISKEY_CLIENT_ID",
        "FERRISKEY_AUDIENCE",
        "FERRISKEY_JWKS_SNAPSHOT",
        "FERRISKEY_JWKS_LOADED_AT",
        "FERRISKEY_JWKS_MAX_AGE_SECONDS",
        "C3I_API_TOKEN"
    ],
    Saved = [{Name, os:getenv(Name)} || Name <- Names],
    Values = [
        {"FERRISKEY_ENABLED", "true"},
        {"FERRISKEY_ISSUER_URL", "https://issuer.example/realms/c3i"},
        {"FERRISKEY_CLIENT_ID", "c3i-wisp-api"},
        {"FERRISKEY_AUDIENCE", "c3i-wisp-api"},
        {"FERRISKEY_JWKS_SNAPSHOT", "{\"keys\":[{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"kid\":\"rfc8037-test\",\"alg\":\"EdDSA\",\"use\":\"sig\",\"key_ops\":[\"verify\"],\"x\":\"11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo\"}]}"},
        {"FERRISKEY_JWKS_LOADED_AT", integer_to_list(erlang:system_time(second))},
        {"FERRISKEY_JWKS_MAX_AGE_SECONDS", "300"},
        {"C3I_API_TOKEN", "must-not-authorize-in-oidc-mode"}
    ],
    lists:foreach(fun({Name, Value}) -> true = os:putenv(Name, Value) end, Values),
    try Fun()
    after
        lists:foreach(fun restore_env/1, Saved)
    end.

restore_env({Name, false}) -> true = os:unsetenv(Name);
restore_env({Name, Value}) -> true = os:putenv(Name, Value).
