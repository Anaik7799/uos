%% Independent local acceptance checks against the frozen candidate modules.
%% Run in an env -i VM. Keys exist only in memory and all authority is synthetic.
%% No listener, network request, production configuration, or mutation is used.
-module(oidc_independent_review).
-export([run/0]).

-define(OIDC, 'cepaf_gleam@auth@oidc').
-define(AUTH, 'cepaf_gleam@ui@wisp@auth').
-define(ROUTER, 'cepaf_gleam@ui@wisp@router').

run() ->
    {Public, Private} = crypto:generate_key(eddsa, ed25519),
    Now = erlang:system_time(second),
    Issuer = <<"https://review.example/realms/local">>,
    Audience = <<"local-review-api">>,
    Key = #{<<"kty">> => <<"OKP">>, <<"crv">> => <<"Ed25519">>,
            <<"alg">> => <<"EdDSA">>, <<"kid">> => <<"ephemeral-review-key">>,
            <<"x">> => b64(Public), <<"use">> => <<"sig">>,
            <<"key_ops">> => [<<"verify">>]},
    Jwks = encode(#{<<"keys">> => [Key]}),
    Base = {oidc_config, Issuer, <<Issuer/binary, "/certs">>, Audience, Audience, none},
    {ok, Config} = ?OIDC:load_jwks_snapshot(Base, Jwks, Now - 1, 300),
    Header = #{<<"alg">> => <<"EdDSA">>, <<"kid">> => <<"ephemeral-review-key">>},
    Claims = #{<<"sub">> => <<"local-user">>, <<"iss">> => Issuer,
               <<"aud">> => Audience, <<"exp">> => Now + 120,
               <<"nbf">> => Now - 10, <<"iat">> => Now - 10},
    Token = sign(Header, encode(Claims), Private),
    Validate = fun(H, C) -> ?OIDC:validate_token(sign(H, encode(C), Private), Config, Now) end,
    Payload = encode(Claims),
    NestedDuplicate = <<"{\"nested\":{\"x\":1,\"x\":2},", (binary:part(Payload, 1, byte_size(Payload) - 1))/binary>>,
    DuplicateEscaped = <<"{\"\\u0061ud\":\"wrong\",", (binary:part(Payload, 1, byte_size(Payload) - 1))/binary>>,
    BadSignatureToken = tamper_signature(Token),
    Pure = [
      {"ephemeral_signed_positive", fun() -> accepted(?OIDC:validate_token(Token, Config, Now)) end},
      {"issuer_exact_suffix_rejected", fun() -> rejected(Validate(Header, Claims#{<<"iss">> => <<Issuer/binary, "/">>})) end},
      {"audience_empty_rejected", fun() -> rejected(Validate(Header, Claims#{<<"aud">> => <<>>})) end},
      {"audience_empty_array_rejected", fun() -> rejected(Validate(Header, Claims#{<<"aud">> => []})) end},
      {"audience_mixed_type_rejected", fun() -> rejected(Validate(Header, Claims#{<<"aud">> => [Audience, 7]})) end},
      {"audience_seventeen_rejected", fun() -> rejected(Validate(Header, Claims#{<<"aud">> => lists:duplicate(17, Audience)})) end},
      {"expiry_exact_now_rejected", fun() -> rejected(Validate(Header, Claims#{<<"exp">> => Now})) end},
      {"nbf_skew_boundary_accepted", fun() -> accepted(Validate(Header, Claims#{<<"nbf">> => Now + 60})) end},
      {"nbf_past_skew_rejected", fun() -> rejected(Validate(Header, Claims#{<<"nbf">> => Now + 61})) end},
      {"iat_skew_boundary_accepted", fun() -> accepted(Validate(Header, Claims#{<<"iat">> => Now + 60})) end},
      {"iat_past_skew_rejected", fun() -> rejected(Validate(Header, Claims#{<<"iat">> => Now + 61})) end},
      {"nbf_at_expiry_rejected", fun() -> rejected(Validate(Header, Claims#{<<"nbf">> => Now + 120})) end},
      {"iat_negative_rejected", fun() -> rejected(Validate(Header, Claims#{<<"iat">> => -1})) end},
      {"subject_whitespace_rejected", fun() -> rejected(Validate(Header, Claims#{<<"sub">> => <<" \t\n">>})) end},
      {"subject_over_limit_rejected", fun() -> rejected(Validate(Header, Claims#{<<"sub">> => binary:copy(<<"x">>, 513)})) end},
      {"unknown_kid_rejected", fun() -> rejected(Validate(Header#{<<"kid">> => <<"other">>}, Claims)) end},
      {"inline_jwk_rejected", fun() -> rejected(Validate(Header#{<<"jwk">> => Key}, Claims)) end},
      {"critical_header_rejected", fun() -> rejected(Validate(Header#{<<"crit">> => []}, Claims)) end},
      {"wrong_typ_rejected", fun() -> rejected(Validate(Header#{<<"typ">> => <<"at+jwt">>}, Claims)) end},
      {"signature_tamper_rejected", fun() -> rejected(?OIDC:validate_token(BadSignatureToken, Config, Now)) end},
      {"nested_duplicate_rejected", fun() -> rejected(?OIDC:validate_token(sign(Header, NestedDuplicate, Private), Config, Now)) end},
      {"escaped_duplicate_rejected", fun() -> rejected(?OIDC:validate_token(sign(Header, DuplicateEscaped, Private), Config, Now)) end},
      {"trailing_payload_rejected", fun() -> rejected(?OIDC:validate_token(sign(Header, <<Payload/binary, " x">>, Private), Config, Now)) end},
      {"snapshot_future_rejected", fun() -> snapshot_decision(Base, Jwks, Now + 1, 300, Token, Now, false) end},
      {"snapshot_age_boundary_accepted", fun() -> snapshot_decision(Base, Jwks, Now - 300, 300, Token, Now, true) end},
      {"snapshot_age_expired_rejected", fun() -> snapshot_decision(Base, Jwks, Now - 301, 300, Token, Now, false) end},
      {"snapshot_zero_age_rejected", fun() -> rejected(?OIDC:load_jwks_snapshot(Base, Jwks, Now, 0)) end},
      {"snapshot_over_max_age_rejected", fun() -> rejected(?OIDC:load_jwks_snapshot(Base, Jwks, Now, 3601)) end},
      {"snapshot_duplicate_kid_rejected", fun() -> rejected(?OIDC:load_jwks_snapshot(Base, encode(#{<<"keys">> => [Key, Key]}), Now, 300)) end},
      {"snapshot_sign_only_key_rejected", fun() -> rejected(?OIDC:load_jwks_snapshot(Base, encode(#{<<"keys">> => [Key#{<<"key_ops">> => [<<"sign">>]}]}), Now, 300)) end},
      {"snapshot_too_large_rejected", fun() -> rejected(?OIDC:load_jwks_snapshot(Base, binary:copy(<<"x">>, 32769), Now, 300)) end}
    ],
    PureResults = checks(Pure),
    setenv("FERRISKEY_ENABLED", <<"true">>),
    setenv("FERRISKEY_ISSUER_URL", Issuer),
    setenv("FERRISKEY_AUDIENCE", Audience),
    setenv("FERRISKEY_CLIENT_ID", Audience),
    setenv("FERRISKEY_JWKS_SNAPSHOT", Jwks),
    setenv("FERRISKEY_JWKS_LOADED_AT", integer_to_binary(Now)),
    setenv("FERRISKEY_JWKS_MAX_AGE_SECONDS", <<"300">>),
    setenv("C3I_API_TOKEN", BadSignatureToken),
    GoodRequest = request(post, <<"/api/review/nonexistent">>, Token),
    BadRequest = request(post, <<"/api/review/nonexistent">>, BadSignatureToken),
    BoundaryResults = checks([
      {"real_wrapper_oidc_positive", fun() -> oidc_authenticated(?AUTH:validate_request(GoodRequest)) end},
      {"real_wrapper_no_static_signature_downgrade", fun() -> invalid(?AUTH:validate_request(BadRequest)) end},
      {"real_wrapper_no_admin_user_downgrade", fun() -> rejected(?AUTH:get_authenticated_user(BadRequest)) end},
      {"real_router_valid_unknown_post_is_404", fun() -> element(2, ?ROUTER:handle_request(GoodRequest)) =:= 404 end},
      {"real_router_bad_post_is_401", fun() -> element(2, ?ROUTER:handle_request(BadRequest)) =:= 401 end},
      {"real_wrapper_missing_header", fun() -> ?AUTH:validate_request(request(post, <<"/api/review/nonexistent">>, none)) =:= unauthenticated end}
    ]),
    %% Stop before enumerating any real mutation path unless both the actual
    %% wrapper and the harmless unknown-route check have confirmed rejection.
    true = lists:all(fun(#{passed := P}) -> P end, BoundaryResults),
    %% These known mutation paths are tested only with a rejected credential;
    %% the actual router must return before reaching any mutation handler.
    Paths = [<<"/api/v1/podman/action">>, <<"/api/v1/podman/restart">>, <<"/api/v1/podman/stop">>,
             <<"/api/v1/emergency/trigger">>, <<"/api/v1/guardian/respond">>, <<"/api/v1/ooda/trigger">>,
             <<"/api/v1/system/ooda-trigger">>, <<"/api/v1/plan/update">>, <<"/api/v1/planning/add">>,
             <<"/api/v1/reload">>, <<"/api/v1/zenoh/publish">>, <<"/api/v1/cockpit/mode">>,
             <<"/api/v1/pi/prompt">>, <<"/ag-ui/run">>, <<"/ag-ui/hitl/respond">>, <<"/ag-ui/tools/result">>],
    RouteResults = checks([{binary_to_list(<<"post_boundary:", Path/binary>>),
        fun() -> element(2, ?ROUTER:handle_request(request(post, Path, BadSignatureToken))) =:= 401 end} || Path <- Paths]),
    MethodResults = checks([{atom_to_list(Method) ++ "_rejects_unsupported_method", fun() ->
        element(2, ?ROUTER:handle_request(request(Method, <<"/api/review/nonexistent">>, none))) =:= 405 end}
        || Method <- [put, delete, patch]]),
    true = os:unsetenv("FERRISKEY_JWKS_SNAPSHOT"),
    MissingResult = checks([{"real_wrapper_missing_snapshot_no_downgrade", fun() -> invalid(?AUTH:validate_request(BadRequest)) end}]),
    setenv("FERRISKEY_JWKS_SNAPSHOT", Jwks),
    setenv("FERRISKEY_JWKS_LOADED_AT", integer_to_binary(Now - 301)),
    StaleResult = checks([{"real_wrapper_stale_snapshot_no_downgrade", fun() -> invalid(?AUTH:validate_request(BadRequest)) end}]),
    setenv("FERRISKEY_ENABLED", <<"false">>),
    StaticResult = checks([{"real_wrapper_explicit_static_mode", fun() ->
        ?AUTH:validate_request(BadRequest) =:= {authenticated, <<"api-client">>} end}]),
    Results = PureResults ++ BoundaryResults ++ RouteResults ++ MethodResults ++ MissingResult ++ StaleResult ++ StaticResult,
    Passed = length([ok || #{passed := true} <- Results]),
    io:put_chars(encode(#{schema => <<"uos-oidc-independent-review/v1">>,
      otp_release => list_to_binary(erlang:system_info(otp_release)),
      total => length(Results), passed => Passed, failed => length(Results) - Passed,
      production_secret_access => false, external_traffic => false, results => Results})),
    io:nl(),
    case Passed =:= length(Results) of true -> 0; false -> 1 end.

checks(Cases) -> [begin
    Passed = try Check() =:= true catch _:_ -> false end,
    #{name => list_to_binary(Name), passed => Passed}
  end || {Name, Check} <- Cases].

accepted({ok, _}) -> true;
accepted(_) -> false.
rejected({error, _}) -> true;
rejected(_) -> false.
invalid({invalid_token, _}) -> true;
invalid(_) -> false.
oidc_authenticated({authenticated_oidc, _}) -> true;
oidc_authenticated(_) -> false.

snapshot_decision(Base, Jwks, At, Age, Token, Now, Expected) ->
    {ok, Config} = ?OIDC:load_jwks_snapshot(Base, Jwks, At, Age),
    accepted(?OIDC:validate_token(Token, Config, Now)) =:= Expected.

request(Method, Path, none) -> {request, Method, [], <<"{}">>, http, <<"review.invalid">>, none, Path, none};
request(Method, Path, Token) -> {request, Method, [{<<"authorization">>, <<"Bearer ", Token/binary>>}], <<"{}">>, http, <<"review.invalid">>, none, Path, none}.

setenv(Key, Value) -> true = os:putenv(Key, binary_to_list(Value)).
encode(Value) -> iolist_to_binary(json:encode(Value)).
sign(Header, Payload, Private) ->
    Input = <<(b64(encode(Header)))/binary, ".", (b64(Payload))/binary>>,
    Signature = crypto:sign(eddsa, none, Input, [Private, ed25519]),
    <<Input/binary, ".", (b64(Signature))/binary>>.
b64(Bin) -> base64:encode(Bin, #{mode => urlsafe, padding => false}).
tamper_signature(Token) ->
    [H, P, S] = binary:split(Token, <<".">>, [global]),
    <<First, Rest/binary>> = S,
    Replacement = case First of $A -> $B; _ -> $A end,
    <<H/binary, ".", P/binary, ".", Replacement, Rest/binary>>.
