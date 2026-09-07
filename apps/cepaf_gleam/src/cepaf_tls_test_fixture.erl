%% =============================================================================
%% [C3I-SIL6] cepaf_tls_test_fixture — Wave-17 W7 follow-up (worker W-E)
%% =============================================================================
%% test/tls_listener_test.gleam asserts the PEM-envelope contract that
%% server.gleam's `mist.with_tls(certfile: "priv/ssl/cert.pem", keyfile:
%% "priv/ssl/key.pem")` call depends on (server.gleam:1222-1223, unchanged by
%% this module). `priv/ssl/` does not exist in the repo and committing real
%% key/certificate material is barred (CLAUDE.md: "Never commit key or
%% certificate material into the repository").
%%
%% This TEST-ONLY helper generates a fresh, ephemeral, self-signed cert/key
%% pair at test time via Erlang/OTP's own `public_key` test-data generator
%% (public_key:pkix_test_data/1, which itself may delegate to
%% public_key:pkix_test_root_cert/2 for the root) and writes real PEM files
%% (via public_key:pem_encode/1) to a scratch directory outside the repo's
%% tracked tree — never priv/ssl/, never committed. The pair is regenerated
%% on every call, so nothing here is a persisted, reused fixture.
%%
%% Scratch directory resolution:
%%   1. env UOS_TLS_TEST_ROOT, if set and non-empty
%%   2. else DefaultRoot as passed by the caller (test/ uses "build/tls-test")
%%
%% This module MUST NOT be reachable from production code paths.
%% =============================================================================
-module(cepaf_tls_test_fixture).
-export([ensure_pem/1]).

%% @doc Ensure an ephemeral self-signed cert.pem/key.pem pair exists on disk
%% for TLS listener tests and return their paths.
-spec ensure_pem(unicode:chardata()) ->
    {ok, {binary(), binary()}} | {error, binary()}.
ensure_pem(DefaultRoot) ->
    try
        Root = resolve_root(DefaultRoot),
        ok = filelib:ensure_path(binary_to_list(Root)),
        CertPath = filename:join(Root, <<"cert.pem">>),
        KeyPath = filename:join(Root, <<"key.pem">>),
        {CertPem, KeyPem} = generate_pem_pair(),
        ok = file:write_file(CertPath, CertPem),
        ok = file:write_file(KeyPath, KeyPem),
        {ok, {CertPath, KeyPath}}
    catch
        Class:Reason:Stack ->
            Msg = io_lib:format(
                "cepaf_tls_test_fixture:ensure_pem failed ~p:~p ~p",
                [Class, Reason, Stack]
            ),
            {error, unicode:characters_to_binary(Msg)}
    end.

%% -----------------------------------------------------------------------
%% Internal
%% -----------------------------------------------------------------------

resolve_root(DefaultRoot) ->
    case os:getenv("UOS_TLS_TEST_ROOT") of
        false -> to_bin(DefaultRoot);
        "" -> to_bin(DefaultRoot);
        Env -> to_bin(Env)
    end.

%% Generate a fresh ephemeral self-signed leaf cert + private key using
%% OTP's own test-data generator and PEM-encode both.
generate_pem_pair() ->
    _ = code:ensure_loaded(public_key),
    Conf = public_key:pkix_test_data(
        #{root => [], intermediates => [], peer => []}
    ),
    Cert = proplists:get_value(cert, Conf),
    {KeyType, KeyDer} = proplists:get_value(key, Conf),
    CertPem = public_key:pem_encode([{'Certificate', Cert, not_encrypted}]),
    KeyPem = public_key:pem_encode([{KeyType, KeyDer, not_encrypted}]),
    {CertPem, KeyPem}.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> unicode:characters_to_binary(L).
