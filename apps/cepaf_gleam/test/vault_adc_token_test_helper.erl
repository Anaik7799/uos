%% =============================================================================
%% [C3I-SIL6] vault_adc_token_test_helper — Wave 8 Worker 1 test helper
%% =============================================================================
%% Generates a fresh RSA-2048 key pair, writes a Google-shaped service_account
%% JSON to a temp file, points GOOGLE_APPLICATION_CREDENTIALS at it, and
%% invokes the real resolver. Cleans up env + file regardless of outcome.
%%
%% This is a TEST-ONLY helper. It MUST NOT be reachable from production code.
%% The lock-in trap test in vault_adc_token_test.gleam asserts that the
%% resolver dispatches into the JWT signing path (returning sa_* error family)
%% rather than rejecting at the parse stage with adc_unsupported_format.
%%
%% [zk-3346fc607a1ef9e6] Stub-That-Lies guard: the Ok branch in the consuming
%% gleeunit test forces a failure, so any code path that fabricates a token
%% will be caught.
%% =============================================================================
-module(vault_adc_token_test_helper).
-export([with_service_account_creds/0]).

with_service_account_creds() ->
    %% Generate a real RSA-2048 keypair. crypto:generate_key/2 returns
    %% {Public, Private} where Private is a list of integers
    %% [E, N, D, P1, P2, E1, E2, C].
    {_Public, Private} = crypto:generate_key(rsa, {2048, 65537}),
    %% Convert to #'RSAPrivateKey'{} record so public_key:pem_entry_encode/2
    %% can produce a PKCS#1 PEM. crypto:generate_key/2 returns binaries; the
    %% ASN.1 record requires plain integers — convert via decode_unsigned/1.
    [E, N, D, P1, P2, E1, E2, C] = Private,
    Be  = b2i(E),  Bn  = b2i(N),  Bd  = b2i(D),
    Bp1 = b2i(P1), Bp2 = b2i(P2),
    Be1 = b2i(E1), Be2 = b2i(E2), Bc = b2i(C),
    RsaRec = {'RSAPrivateKey', 'two-prime', Bn, Be, Bd, Bp1, Bp2, Be1, Be2, Bc, asn1_NOVALUE},
    PemEntry = public_key:pem_entry_encode('RSAPrivateKey', RsaRec),
    PemBin = public_key:pem_encode([PemEntry]),

    %% Build a Google-shaped service_account JSON manually. We avoid taking
    %% a hard dep on thoas by hand-encoding the small fixed map. Only string
    %% values appear; we JSON-escape backslashes, double-quotes, and newlines
    %% (PEM contains plenty of newlines).
    PemEsc = json_escape_str(PemBin),
    JsonBin = iolist_to_binary([
        <<"{">>,
            <<"\"type\":\"service_account\",">>,
            <<"\"client_email\":\"test-helper@c3i-vault-test.iam.gserviceaccount.com\",">>,
            <<"\"private_key\":\"">>, PemEsc, <<"\",">>,
            <<"\"token_uri\":\"https://oauth2.googleapis.com/token\",">>,
            <<"\"project_id\":\"c3i-vault-test\"">>,
        <<"}">>
    ]),

    %% Write to a temp file with mode 0600 (vault-style). Use erlang:unique_integer
    %% so parallel test runs don't collide.
    TmpDir = case os:getenv("TMPDIR") of
        false -> "/tmp";
        ""    -> "/tmp";
        T     -> T
    end,
    Suffix = integer_to_list(erlang:unique_integer([positive])),
    Path = filename:join(TmpDir, "c3i-vault-sa-test-" ++ Suffix ++ ".json"),
    ok = file:write_file(Path, JsonBin),
    _ = file:change_mode(Path, 8#0600),

    %% Save + override env var. We MUST restore it afterwards even on crash.
    Prior = os:getenv("GOOGLE_APPLICATION_CREDENTIALS"),
    true = os:putenv("GOOGLE_APPLICATION_CREDENTIALS", Path),

    Result =
        try
            vault_adc_token_ffi:resolve_token()
        catch
            Class:Reason ->
                R = io_lib:format("test_helper_caught: ~p:~p", [Class, Reason]),
                {error, list_to_binary(lists:flatten(R))}
        end,

    %% Cleanup — restore env, delete temp file. Best-effort; errors swallowed.
    case Prior of
        false -> os:unsetenv("GOOGLE_APPLICATION_CREDENTIALS");
        ""    -> os:unsetenv("GOOGLE_APPLICATION_CREDENTIALS");
        Old   -> os:putenv("GOOGLE_APPLICATION_CREDENTIALS", Old)
    end,
    _ = file:delete(Path),

    %% Normalize binary tokens to lists/strings for Gleam's String type.
    case Result of
        {ok, Tok} when is_binary(Tok) -> {ok, Tok};
        {ok, Tok} when is_list(Tok)   -> {ok, list_to_binary(Tok)};
        {error, Msg} when is_binary(Msg) -> {error, Msg};
        {error, Msg} when is_list(Msg) -> {error, list_to_binary(Msg)};
        Other ->
            R2 = io_lib:format("test_helper_unexpected: ~p", [Other]),
            {error, list_to_binary(lists:flatten(R2))}
    end.

%% Convert crypto-returned binary-encoded big-endian integer to Erlang integer.
b2i(B) when is_binary(B) -> binary:decode_unsigned(B);
b2i(I) when is_integer(I) -> I.

%% Minimal JSON string escape. Handles the characters that actually appear in
%% PEM-encoded keys: backslash, double quote, newline, carriage return, tab.
%% Other control chars are passed through (PEM doesn't contain them).
json_escape_str(Bin) when is_binary(Bin) ->
    << <<(esc_byte(B))/binary>> || <<B>> <= Bin >>.

esc_byte($\\) -> <<"\\\\">>;
esc_byte($")  -> <<"\\\"">>;
esc_byte($\n) -> <<"\\n">>;
esc_byte($\r) -> <<"\\r">>;
esc_byte($\t) -> <<"\\t">>;
esc_byte(B)   -> <<B>>.
