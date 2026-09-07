-module(oidc_jwt_ffi).

-export([validate_jwks_snapshot/1, verify_ed25519_jwt/2]).

-define(MAX_TOKEN_BYTES, 8192).
-define(MAX_JWKS_BYTES, 32768).
-define(MAX_KEYS, 16).

-spec validate_jwks_snapshot(binary()) -> {ok, nil} | {error, binary()}.
validate_jwks_snapshot(JwksJson) when is_binary(JwksJson) ->
    case decode_jwks(JwksJson) of
        {ok, _Keys} -> {ok, nil};
        {error, Reason} -> {error, reason_binary(Reason)}
    end;
validate_jwks_snapshot(_) ->
    {error, <<"invalid_jwks_snapshot">>}.

-spec verify_ed25519_jwt(binary(), binary()) ->
    {ok, binary()} | {error, binary()}.
verify_ed25519_jwt(Token, JwksJson)
        when is_binary(Token), is_binary(JwksJson) ->
    Result =
        case byte_size(Token) > 0 andalso byte_size(Token) =< ?MAX_TOKEN_BYTES of
            false -> {error, bad_token_length};
            true -> verify_bounded_token(Token, JwksJson)
        end,
    case Result of
        {ok, Payload} -> {ok, Payload};
        {error, Reason} -> {error, reason_binary(Reason)}
    end;
verify_ed25519_jwt(_, _) ->
    {error, <<"malformed_compact_jwt">>}.

verify_bounded_token(Token, JwksJson) ->
    case binary:split(Token, <<".">>, [global]) of
        [Header64, Payload64, Signature64]
                when byte_size(Header64) > 0,
                     byte_size(Payload64) > 0,
                     byte_size(Signature64) > 0 ->
            verify_segments(Header64, Payload64, Signature64, JwksJson);
        _ ->
            {error, malformed_compact_jwt}
    end.

verify_segments(Header64, Payload64, Signature64, JwksJson) ->
    with_decoded(Header64, fun(HeaderJson) ->
        with_decoded(Payload64, fun(PayloadJson) ->
            with_decoded(Signature64, fun(Signature) ->
                case byte_size(Signature) of
                    64 -> verify_decoded(
                        Header64, Payload64, HeaderJson, PayloadJson,
                        Signature, JwksJson
                    );
                    _ -> {error, invalid_signature_size}
                end
            end)
        end)
    end).

verify_decoded(Header64, Payload64, HeaderJson, PayloadJson, Signature, JwksJson) ->
    case decode_strict_json(HeaderJson) of
        {ok, Header} when is_map(Header) ->
            case validate_header(Header) of
                {ok, Kid} ->
                    case decode_strict_json(PayloadJson) of
                        {ok, Claims} when is_map(Claims) ->
                            verify_with_snapshot(
                                Header64, Payload64, PayloadJson,
                                Signature, Kid, JwksJson
                            );
                        {ok, _} -> {error, claims_not_object};
                        {error, Reason} -> {error, Reason}
                    end;
                {error, Reason} -> {error, Reason}
            end;
        {ok, _} -> {error, header_not_object};
        {error, Reason} -> {error, Reason}
    end.

verify_with_snapshot(Header64, Payload64, PayloadJson, Signature, Kid, JwksJson) ->
    case decode_jwks(JwksJson) of
        {ok, Keys} ->
            case [PublicKey || {KeyKid, PublicKey} <- Keys, KeyKid =:= Kid] of
                [PublicKey] ->
                    SigningInput = <<Header64/binary, ".", Payload64/binary>>,
                    try crypto:verify(
                        eddsa, none, SigningInput, Signature,
                        [PublicKey, ed25519]
                    ) of
                        true -> {ok, PayloadJson};
                        false -> {error, invalid_signature}
                    catch
                        _:_ -> {error, invalid_signature}
                    end;
                [] -> {error, key_not_found};
                _ -> {error, duplicate_kid}
            end;
        {error, Reason} -> {error, Reason}
    end.

validate_header(Header) ->
    Allowed = [<<"alg">>, <<"kid">>, <<"typ">>],
    case only_allowed_keys(Header, Allowed) of
        false -> {error, disallowed_header};
        true ->
            case {
                maps:get(<<"alg">>, Header, undefined),
                maps:get(<<"kid">>, Header, undefined),
                maps:get(<<"typ">>, Header, <<"JWT">>)
            } of
                {<<"EdDSA">>, Kid, <<"JWT">>}
                        when is_binary(Kid),
                             byte_size(Kid) > 0,
                             byte_size(Kid) =< 128 ->
                    {ok, Kid};
                {Alg, _, _} when Alg =/= <<"EdDSA">> ->
                    {error, unsupported_algorithm};
                {_, Kid, _} when not is_binary(Kid); byte_size(Kid) =:= 0 ->
                    {error, missing_kid};
                _ ->
                    {error, invalid_header}
            end
    end.

decode_jwks(JwksJson) when byte_size(JwksJson) =< ?MAX_JWKS_BYTES ->
    case decode_strict_json(JwksJson) of
        {ok, #{<<"keys">> := RawKeys} = Root} when is_list(RawKeys) ->
            case only_allowed_keys(Root, [<<"keys">>]) of
                false -> {error, invalid_jwks_snapshot};
                true -> validate_keys(RawKeys)
            end;
        {ok, _} -> {error, invalid_jwks_snapshot};
        {error, Reason} -> {error, Reason}
    end;
decode_jwks(_) ->
    {error, jwks_snapshot_too_large}.

validate_keys([]) ->
    {error, empty_jwks_snapshot};
validate_keys(Keys) when length(Keys) > ?MAX_KEYS ->
    {error, too_many_jwks_keys};
validate_keys(Keys) ->
    validate_keys(Keys, [], []).

validate_keys([], Acc, Kids) ->
    case length(Kids) =:= length(lists:usort(Kids)) of
        true -> {ok, lists:reverse(Acc)};
        false -> {error, duplicate_kid}
    end;
validate_keys([Key | Rest], Acc, Kids) when is_map(Key) ->
    case validate_key(Key) of
        {ok, Kid, PublicKey} ->
            validate_keys(Rest, [{Kid, PublicKey} | Acc], [Kid | Kids]);
        {error, Reason} ->
            {error, Reason}
    end;
validate_keys(_, _, _) ->
    {error, invalid_jwk}.

validate_key(Key) ->
    Allowed = [<<"kty">>, <<"crv">>, <<"x">>, <<"kid">>, <<"alg">>, <<"use">>, <<"key_ops">>],
    case only_allowed_keys(Key, Allowed) of
        false -> {error, invalid_jwk};
        true ->
            case {
                maps:get(<<"kty">>, Key, undefined),
                maps:get(<<"crv">>, Key, undefined),
                maps:get(<<"alg">>, Key, undefined),
                maps:get(<<"kid">>, Key, undefined),
                maps:get(<<"x">>, Key, undefined),
                valid_optional_use(Key),
                valid_optional_key_ops(Key)
            } of
                {<<"OKP">>, <<"Ed25519">>, <<"EdDSA">>, Kid, X, true, true}
                        when is_binary(Kid), is_binary(X),
                             byte_size(Kid) > 0, byte_size(Kid) =< 128 ->
                    case decode_base64url_canonical(X) of
                        {ok, PublicKey} when byte_size(PublicKey) =:= 32 ->
                            {ok, Kid, PublicKey};
                        _ -> {error, invalid_public_key}
                    end;
                _ -> {error, invalid_jwk}
            end
    end.

valid_optional_use(Key) ->
    case maps:get(<<"use">>, Key, <<"sig">>) of
        <<"sig">> -> true;
        _ -> false
    end.

valid_optional_key_ops(Key) ->
    case maps:get(<<"key_ops">>, Key, [<<"verify">>]) of
        [<<"verify">>] -> true;
        _ -> false
    end.

only_allowed_keys(Map, Allowed) ->
    lists:all(fun(Key) -> lists:member(Key, Allowed) end, maps:keys(Map)).

decode_strict_json(Json) ->
    Push = fun(Key, Value, Acc) ->
        case lists:keymember(Key, 1, Acc) of
            true -> error({duplicate_key, Key});
            false -> [{Key, Value} | Acc]
        end
    end,
    try json:decode(Json, ok, #{object_push => Push}) of
        {Value, ok, Rest} ->
            case only_json_whitespace(Rest) of
                true -> {ok, Value};
                false -> {error, trailing_json_data}
            end
    catch
        error:{duplicate_key, _} -> {error, duplicate_json_member};
        _:_ -> {error, invalid_json}
    end.

only_json_whitespace(<<>>) -> true;
only_json_whitespace(<<C, Rest/binary>>)
        when C =:= 16#20; C =:= 16#09; C =:= 16#0A; C =:= 16#0D ->
    only_json_whitespace(Rest);
only_json_whitespace(_) -> false.

with_decoded(Encoded, Next) ->
    case decode_base64url_canonical(Encoded) of
        {ok, Decoded} -> Next(Decoded);
        {error, Reason} -> {error, Reason}
    end.

decode_base64url_canonical(Encoded) when is_binary(Encoded), byte_size(Encoded) > 0 ->
    case valid_base64url_chars(Encoded) andalso byte_size(Encoded) rem 4 =/= 1 of
        false -> {error, noncanonical_base64url};
        true ->
            Padded = pad_base64url(Encoded),
            Standard = binary:replace(
                binary:replace(Padded, <<"-">>, <<"+">>, [global]),
                <<"_">>, <<"/">>, [global]
            ),
            try base64:decode(Standard) of
                Decoded ->
                    case base64url_encode(Decoded) of
                        Encoded -> {ok, Decoded};
                        _ -> {error, noncanonical_base64url}
                    end
            catch
                _:_ -> {error, noncanonical_base64url}
            end
    end;
decode_base64url_canonical(_) ->
    {error, noncanonical_base64url}.

valid_base64url_chars(Bin) ->
    valid_base64url_chars(Bin, true).

valid_base64url_chars(<<>>, Acc) -> Acc;
valid_base64url_chars(<<C, Rest/binary>>, true)
        when (C >= $A andalso C =< $Z);
             (C >= $a andalso C =< $z);
             (C >= $0 andalso C =< $9);
             C =:= $-;
             C =:= $_ ->
    valid_base64url_chars(Rest, true);
valid_base64url_chars(_, _) -> false.

pad_base64url(Bin) ->
    case byte_size(Bin) rem 4 of
        0 -> Bin;
        2 -> <<Bin/binary, "==">>;
        3 -> <<Bin/binary, "=">>
    end.

base64url_encode(Bin) ->
    Standard = base64:encode(Bin),
    Url = binary:replace(
        binary:replace(Standard, <<"+">>, <<"-">>, [global]),
        <<"/">>, <<"_">>, [global]
    ),
    binary:replace(Url, <<"=">>, <<>>, [global]).

reason_binary(Reason) when is_atom(Reason) -> atom_to_binary(Reason, utf8);
reason_binary(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).
