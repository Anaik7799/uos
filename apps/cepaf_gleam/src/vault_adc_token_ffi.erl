%% =============================================================================
%% [C3I-SIL6] vault_adc_token_ffi — Wave 8 Worker 1 (service-account RS256 JWT)
%% =============================================================================
%% Wave 7 shipped the gcloud user-credentials (authorized_user) path.
%% Wave 8 Worker 1 adds the service-account JSON path:
%%   - JSON has fields {client_email, private_key, token_uri, type:"service_account"}
%%   - Build JWT header {"alg":"RS256","typ":"JWT"}
%%   - Build JWT claim {iss=client_email, scope=cloud-platform, aud=token_uri,
%%     iat=now, exp=now+3600}
%%   - Sign header.claim via crypto:sign(rsa, sha256, _, RsaKey)
%%   - POST grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer
%%     &assertion=<signed_jwt> to token_uri
%%   - Parse access_token from response
%%
%% Stub-That-Lies guard ([zk-3346fc607a1ef9e6]): every error path is explicit.
%% NEVER returns a fabricated bearer. The previous "adc_not_yet_wired" stub
%% is replaced — the lock-in trap test asserts the wider error vocabulary
%% (adc_no_credentials_found / adc_unsupported_format / sa_jwt_sign_failed /
%% sa_token_exchange_failed / sa_pem_decode_failed / etc.).
%%
%% Honest scope (deferred):
%%   - GCE metadata-server path (option 3) is hardware-bound — requires running
%%     on GCE; separate gate.
%% =============================================================================
-module(vault_adc_token_ffi).

-export([resolve_token/0]).

-define(TIMEOUT_MS, 10000).
-define(TOKEN_URL, "https://oauth2.googleapis.com/token").

ensure_inets() ->
    _ = application:ensure_all_started(ssl),
    _ = application:ensure_all_started(inets),
    ok.

%% Returns {ok, BinaryAccessToken} | {error, BinaryReason}
%% Reasons (canonical wire vocabulary; tests gate on these):
%%   <<"adc_no_credentials_found">>   — neither env-var nor default path readable
%%   <<"adc_unsupported_format">>     — file present but not 'authorized_user' type
%%   <<"adc_malformed_json">>         — file present but not parseable
%%   <<"adc_token_refresh_failed: …">> — token endpoint returned !=200 / no access_token
%%   <<"adc_transport_error: …">>      — httpc transport error
resolve_token() ->
    ok = ensure_inets(),
    case locate_credentials_file() of
        {ok, Path} ->
            case read_and_parse(Path) of
                {ok, {authorized_user, RefreshTok, ClientId, ClientSecret}} ->
                    exchange_refresh_token(RefreshTok, ClientId, ClientSecret);
                {ok, {service_account, ClientEmail, PrivateKeyPem, TokenUri}} ->
                    exchange_service_account_jwt(ClientEmail, PrivateKeyPem, TokenUri);
                {error, _} = Err ->
                    Err
            end;
        {error, _} = Err ->
            Err
    end.

%% Resolution chain:
%%   1. GOOGLE_APPLICATION_CREDENTIALS env var → that path
%%   2. ~/.config/gcloud/application_default_credentials.json
%% No metadata-server fallback in this wave (deferred).
locate_credentials_file() ->
    case os:getenv("GOOGLE_APPLICATION_CREDENTIALS") of
        Path when is_list(Path), Path =/= "" ->
            case filelib:is_regular(Path) of
                true -> {ok, Path};
                false -> try_default_path()
            end;
        _ ->
            try_default_path()
    end.

try_default_path() ->
    case os:getenv("HOME") of
        Home when is_list(Home), Home =/= "" ->
            P = filename:join([Home, ".config", "gcloud", "application_default_credentials.json"]),
            case filelib:is_regular(P) of
                true -> {ok, P};
                false -> {error, <<"adc_no_credentials_found">>}
            end;
        _ ->
            {error, <<"adc_no_credentials_found">>}
    end.

%% Returns {ok, {authorized_user, RefreshTok, ClientId, ClientSecret}}
%%       | {ok, {service_account, ClientEmail, PrivateKeyPem, TokenUri}}
%%       | {error, BinaryReason}
read_and_parse(Path) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            case decode_json(Bin) of
                {ok, Map} ->
                    Type = map_get_str(<<"type">>, Map),
                    case Type of
                        <<"authorized_user">> ->
                            R = map_get_str(<<"refresh_token">>, Map),
                            CI = map_get_str(<<"client_id">>, Map),
                            CS = map_get_str(<<"client_secret">>, Map),
                            case {R, CI, CS} of
                                {<<>>, _, _} -> {error, <<"adc_unsupported_format">>};
                                {_, <<>>, _} -> {error, <<"adc_unsupported_format">>};
                                {_, _, <<>>} -> {error, <<"adc_unsupported_format">>};
                                _ -> {ok, {authorized_user, R, CI, CS}}
                            end;
                        <<"service_account">> ->
                            CE = map_get_str(<<"client_email">>, Map),
                            PK = map_get_str(<<"private_key">>, Map),
                            TU0 = map_get_str(<<"token_uri">>, Map),
                            %% token_uri is sometimes absent on older keys; default
                            %% to Google's OAuth2 endpoint (RFC: same endpoint accepts
                            %% both refresh_token and jwt-bearer grants).
                            TU = case TU0 of
                                <<>> -> <<"https://oauth2.googleapis.com/token">>;
                                _    -> TU0
                            end,
                            case {CE, PK} of
                                {<<>>, _} -> {error, <<"adc_unsupported_format">>};
                                {_, <<>>} -> {error, <<"adc_unsupported_format">>};
                                _ -> {ok, {service_account, CE, PK, TU}}
                            end;
                        _Other ->
                            {error, <<"adc_unsupported_format">>}
                    end;
                {error, _} ->
                    {error, <<"adc_malformed_json">>}
            end;
        {error, _} ->
            {error, <<"adc_no_credentials_found">>}
    end.

%% Use thoas if available (already a transitive dep via gleam_json), else fail
%% with adc_malformed_json. We avoid hard-linking thoas in case the dep set
%% changes; fall back to a minimal hand parser is out of scope.
decode_json(Bin) ->
    try thoas:decode(Bin) of
        {ok, V} when is_map(V) -> {ok, V};
        {ok, _} -> {error, not_a_map};
        {error, _} = E -> E
    catch
        error:undef -> {error, no_json_decoder};
        _:_ -> {error, decode_exception}
    end.

map_get_str(K, M) when is_map(M) ->
    case maps:get(K, M, <<>>) of
        V when is_binary(V) -> V;
        V when is_list(V) -> unicode:characters_to_binary(V);
        _ -> <<>>
    end;
map_get_str(_, _) -> <<>>.

%% POST to https://oauth2.googleapis.com/token with form-urlencoded body:
%%   grant_type=refresh_token&refresh_token=…&client_id=…&client_secret=…
exchange_refresh_token(RefreshTok, ClientId, ClientSecret) ->
    Body = build_form_body([
        {"grant_type", "refresh_token"},
        {"refresh_token", binary_to_list(RefreshTok)},
        {"client_id", binary_to_list(ClientId)},
        {"client_secret", binary_to_list(ClientSecret)}
    ]),
    Headers = [],
    Request = {?TOKEN_URL, Headers, "application/x-www-form-urlencoded", Body},
    HttpOpts = [{timeout, ?TIMEOUT_MS}, {connect_timeout, ?TIMEOUT_MS}, {autoredirect, false}],
    Opts = [{body_format, binary}],
    case httpc:request(post, Request, HttpOpts, Opts) of
        {ok, {{_, 200, _}, _, RespBody}} ->
            extract_access_token(iolist_to_binary(RespBody));
        {ok, {{_, Status, _}, _, RespBody}} ->
            Snippet = first_n_bytes(iolist_to_binary(RespBody), 200),
            Reason = io_lib:format("adc_token_refresh_failed: status=~p body=~s", [Status, Snippet]),
            {error, list_to_binary(lists:flatten(Reason))};
        {error, Why} ->
            Reason = io_lib:format("adc_transport_error: ~p", [Why]),
            {error, list_to_binary(lists:flatten(Reason))}
    end.

extract_access_token(Bin) ->
    case decode_json(Bin) of
        {ok, M} ->
            case map_get_str(<<"access_token">>, M) of
                <<>> -> {error, <<"adc_token_refresh_failed: no access_token in response">>};
                Tok -> {ok, Tok}
            end;
        {error, _} ->
            {error, <<"adc_token_refresh_failed: response not parseable">>}
    end.

build_form_body(KVs) ->
    Encoded = [url_encode(K) ++ "=" ++ url_encode(V) || {K, V} <- KVs],
    string:join(Encoded, "&").

url_encode(S) when is_binary(S) -> url_encode(binary_to_list(S));
url_encode(S) when is_list(S) ->
    lists:flatten([encode_char(C) || C <- S]).

encode_char(C) when C >= $A, C =< $Z -> [C];
encode_char(C) when C >= $a, C =< $z -> [C];
encode_char(C) when C >= $0, C =< $9 -> [C];
encode_char(C) when C =:= $-; C =:= $_; C =:= $.; C =:= $~ -> [C];
encode_char(C) -> io_lib:format("%~2.16.0B", [C]).

first_n_bytes(B, N) when is_binary(B), byte_size(B) =< N -> binary_to_list(B);
first_n_bytes(B, N) when is_binary(B) -> binary_to_list(binary:part(B, 0, N));
first_n_bytes(L, N) when is_list(L), length(L) =< N -> L;
first_n_bytes(L, N) when is_list(L) -> lists:sublist(L, N).

%% =============================================================================
%% Wave 8 Worker 1 — Service-Account RS256 JWT exchange.
%% =============================================================================

%% Exchange a service-account JSON for a Google OAuth2 access token by
%% (a) building a self-signed RS256 JWT and (b) presenting it as the assertion
%% on the jwt-bearer grant. NEVER fabricates a token; every error path is typed.
%%
%% Internal helpers are exported via -compile({nowarn_export_all, true}) only
%% if needed for direct test access; primary surface is exchange/3.
exchange_service_account_jwt(ClientEmail, PrivateKeyPem, TokenUri) ->
    case sign_assertion(ClientEmail, PrivateKeyPem, TokenUri) of
        {ok, Jwt} ->
            post_jwt_assertion(TokenUri, Jwt);
        {error, _} = Err ->
            Err
    end.

%% Build + sign the JWT. Returns {ok, BinaryJwt} | {error, BinaryReason}.
sign_assertion(ClientEmail, PrivateKeyPem, TokenUri) ->
    Now = erlang:system_time(second),
    Header = #{<<"alg">> => <<"RS256">>, <<"typ">> => <<"JWT">>},
    Claim  = #{
        <<"iss">>   => ClientEmail,
        <<"scope">> => <<"https://www.googleapis.com/auth/cloud-platform">>,
        <<"aud">>   => TokenUri,
        <<"iat">>   => Now,
        <<"exp">>   => Now + 3600
    },
    case {encode_json(Header), encode_json(Claim)} of
        {{ok, HBin}, {ok, CBin}} ->
            HB64 = base64url_encode(HBin),
            CB64 = base64url_encode(CBin),
            SigningInput = <<HB64/binary, $., CB64/binary>>,
            case decode_rsa_pem(PrivateKeyPem) of
                {ok, RsaKey} ->
                    case safe_sign_rs256(SigningInput, RsaKey) of
                        {ok, Sig} ->
                            SigB64 = base64url_encode(Sig),
                            {ok, <<SigningInput/binary, $., SigB64/binary>>};
                        {error, Why} ->
                            R = io_lib:format("sa_jwt_sign_failed: ~p", [Why]),
                            {error, list_to_binary(lists:flatten(R))}
                    end;
                {error, Why} ->
                    R = io_lib:format("sa_pem_decode_failed: ~p", [Why]),
                    {error, list_to_binary(lists:flatten(R))}
            end;
        _ ->
            {error, <<"sa_jwt_sign_failed: json_encode">>}
    end.

%% RFC 4648 §5: base64url with no padding.
base64url_encode(Bin) when is_binary(Bin) ->
    Std = base64:encode(Bin),
    %% Strip '=' padding, replace '+'->'-' and '/'->'_'.
    Stripped = << <<C>> || <<C>> <= Std, C =/= $= >>,
    << case C of
           $+ -> $-;
           $/ -> $_;
           _  -> C
       end || <<C>> <= Stripped >>.

%% Encode a map to JSON via thoas (already a transitive dep). Returns
%% {ok, BinaryJson} | error.
encode_json(M) when is_map(M) ->
    try
        {ok, iolist_to_binary(thoas:encode(M))}
    catch
        error:undef -> error;
        _:_ -> error
    end.

%% Decode a PEM-armored RSA private key into the term shape that
%% crypto:sign/4 understands. Accepts both PKCS#1 ("-----BEGIN RSA PRIVATE KEY-----")
%% and PKCS#8 ("-----BEGIN PRIVATE KEY-----") forms (Google emits PKCS#8).
%% Returns {ok, [E, N, D]} suitable for crypto:sign(rsa, sha256, _, [E,N,D])
%% OR a #'RSAPrivateKey'{} record passed directly to public_key:sign/3 (we use
%% the public_key path for cleaner code).
%% Result type: {ok, RsaPrivateKeyRecord} | {error, Reason}.
decode_rsa_pem(PemBin) when is_binary(PemBin) ->
    try
        case public_key:pem_decode(PemBin) of
            [] ->
                {error, no_pem_entries};
            Entries ->
                %% Find the first private-key entry. PKCS#8 yields
                %% {'PrivateKeyInfo', _, _}; we then re-derive the RSA
                %% sub-key. PKCS#1 yields {'RSAPrivateKey', _, _} directly.
                case find_pem_key(Entries) of
                    {ok, Key} -> {ok, Key};
                    {error, _} = E -> E
                end
        end
    catch
        _:Reason -> {error, {pem_decode_exception, Reason}}
    end.

find_pem_key([]) ->
    {error, no_private_key};
find_pem_key([Entry | Rest]) ->
    case Entry of
        {'RSAPrivateKey', _, _} = E ->
            try
                Key = public_key:pem_entry_decode(E),
                {ok, Key}
            catch
                _:_ -> find_pem_key(Rest)
            end;
        {'PrivateKeyInfo', _, _} = E ->
            try
                Key = public_key:pem_entry_decode(E),
                %% PKCS#8 unwrap → for RSA this yields #'RSAPrivateKey'{} directly
                %% in modern OTP. If somehow we got a different type, reject.
                case Key of
                    {'RSAPrivateKey', _, _, _, _, _, _, _, _, _, _} -> {ok, Key};
                    _ -> find_pem_key(Rest)
                end
            catch
                _:_ -> find_pem_key(Rest)
            end;
        _ ->
            find_pem_key(Rest)
    end.

%% Sign with RS256 using public_key (which delegates to crypto). Honest about
%% all error paths; never fabricates a signature.
safe_sign_rs256(Data, RsaKey) ->
    try
        Sig = public_key:sign(Data, sha256, RsaKey),
        {ok, Sig}
    catch
        Class:Reason -> {error, {Class, Reason}}
    end.

%% POST the signed JWT as the assertion on the jwt-bearer grant.
post_jwt_assertion(TokenUri, Jwt) ->
    Body = build_form_body([
        {"grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"},
        {"assertion", binary_to_list(Jwt)}
    ]),
    Headers = [],
    Url = binary_to_list(TokenUri),
    Request = {Url, Headers, "application/x-www-form-urlencoded", Body},
    HttpOpts = [{timeout, ?TIMEOUT_MS}, {connect_timeout, ?TIMEOUT_MS}, {autoredirect, false}],
    Opts = [{body_format, binary}],
    case httpc:request(post, Request, HttpOpts, Opts) of
        {ok, {{_, 200, _}, _, RespBody}} ->
            extract_access_token_sa(iolist_to_binary(RespBody));
        {ok, {{_, Status, _}, _, RespBody}} ->
            Snippet = first_n_bytes(iolist_to_binary(RespBody), 200),
            R = io_lib:format("sa_token_exchange_failed: status=~p body=~s", [Status, Snippet]),
            {error, list_to_binary(lists:flatten(R))};
        {error, Why} ->
            R = io_lib:format("sa_transport_error: ~p", [Why]),
            {error, list_to_binary(lists:flatten(R))}
    end.

%% Extract access_token from JWT-bearer response. Same shape as user-credentials.
extract_access_token_sa(Bin) ->
    case decode_json(Bin) of
        {ok, M} ->
            case map_get_str(<<"access_token">>, M) of
                <<>> -> {error, <<"sa_token_exchange_failed: no access_token in response">>};
                Tok -> {ok, Tok}
            end;
        {error, _} ->
            {error, <<"sa_token_exchange_failed: response not parseable">>}
    end.
