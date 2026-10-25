%% Test-only ephemeral keys. Never loaded by production source builds.
-module(telegram_approval_test_crypto).
-export([public_key/1, sign/2, sign_header/3]).
key(Role) ->
    case get({?MODULE, Role}) of
        undefined ->
            Pair = crypto:generate_key(eddsa, ed25519),
            put({?MODULE, Role}, Pair),
            Pair;
        Pair -> Pair
    end.
encode(B) ->
    base64:encode(B, #{mode => urlsafe, padding => false}).
public_key(Role) ->
    {Pub, _} = key(Role), encode(Pub).
sign(Role, Payload) ->
    Header = iolist_to_binary(json:encode(#{
        <<"alg">> => <<"EdDSA">>, <<"kid">> => <<Role/binary, "-key">>,
        <<"typ">> => <<"JWT">>})),
    sign_header(Role, Payload, Header).
sign_header(Role, Payload, Header) ->
    {_, Private} = key(Role),
    H = encode(Header), P = encode(Payload),
    Bytes = <<H/binary, ".", P/binary>>,
    Signature = crypto:sign(eddsa, none, Bytes, [Private, ed25519]),
    <<Bytes/binary, ".", (encode(Signature))/binary>>.
