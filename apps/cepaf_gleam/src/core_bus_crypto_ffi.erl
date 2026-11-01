%% UOS-CORE-EVO Native OTP 29 Ed25519 Envelope Authentication FFI
%% (`SC-HARNESS-MCP-001`, `SC-PROVENANCE-001`, Zero-Muda pure OTP `crypto`)
%%
%% Zero private keys are ever persisted to disk: ephemeral session keypairs live
%% exclusively in BEAM RAM (`persistent_term`), while deterministic keypair
%% helpers support offline/unit verification of RFC 8032 Ed25519 signatures.
-module(core_bus_crypto_ffi).

-export([
    generate_ed25519_keypair_hex/0,
    session_ed25519_pubkey_hex/0,
    sign_with_session_ed25519_hex/1,
    sign_ed25519_hex/2,
    verify_ed25519_hex/3
]).

-define(SESSION_KEY_SLOT, {core_bus_crypto_ffi, session_ed25519_keypair}).

generate_ed25519_keypair_hex() ->
    {Pub, Priv} = crypto:generate_key(eddsa, ed25519),
    {to_lower_hex(Pub), to_lower_hex(Priv)}.

session_ed25519_pubkey_hex() ->
    {PubHex, _PrivHex} = ensure_session_keypair(),
    PubHex.

sign_with_session_ed25519_hex(MsgBin) when is_binary(MsgBin) ->
    {PubHex, PrivHex} = ensure_session_keypair(),
    case sign_ed25519_hex(MsgBin, PrivHex) of
        {ok, SigHex} -> {ok, {PubHex, SigHex}};
        {error, Reason} -> {error, Reason}
    end.

sign_ed25519_hex(MsgBin, PrivHex) when is_binary(MsgBin), is_binary(PrivHex) ->
    case from_lower_hex(PrivHex, 32) of
        {ok, PrivBin} ->
            try
                Sig = crypto:sign(eddsa, none, MsgBin, [PrivBin, ed25519]),
                {ok, to_lower_hex(Sig)}
            catch
                _:_ -> {error, <<"ed25519_sign_failed">>}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

verify_ed25519_hex(MsgBin, SigHex, PubHex)
  when is_binary(MsgBin), is_binary(SigHex), is_binary(PubHex) ->
    case {from_lower_hex(SigHex, 64), from_lower_hex(PubHex, 32)} of
        {{ok, SigBin}, {ok, PubBin}} ->
            try
                crypto:verify(eddsa, none, MsgBin, SigBin, [PubBin, ed25519])
            catch
                _:_ -> false
            end;
        _ ->
            false
    end.

ensure_session_keypair() ->
    case persistent_term:get(?SESSION_KEY_SLOT, undefined) of
        {PubHex, PrivHex} when is_binary(PubHex), is_binary(PrivHex) ->
            {PubHex, PrivHex};
        undefined ->
            Pair = generate_ed25519_keypair_hex(),
            persistent_term:put(?SESSION_KEY_SLOT, Pair),
            Pair
    end.

to_lower_hex(Bin) ->
    binary:encode_hex(Bin, lowercase).

from_lower_hex(HexBin, ExpectedBytes) ->
    ExpectedHexLen = ExpectedBytes * 2,
    case byte_size(HexBin) =:= ExpectedHexLen andalso is_lower_hex(HexBin) of
        true ->
            try
                Decoded = binary:decode_hex(HexBin),
                case byte_size(Decoded) =:= ExpectedBytes of
                    true -> {ok, Decoded};
                    false -> {error, <<"unexpected_decoded_byte_length">>}
                end
            catch
                _:_ -> {error, <<"hex_decode_failed">>}
            end;
        false ->
            {error, <<"invalid_lowercase_hex_length_or_alphabet">>}
    end.

is_lower_hex(<<>>) ->
    true;
is_lower_hex(<<C, Rest/binary>>)
  when (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f) ->
    is_lower_hex(Rest);
is_lower_hex(_) ->
    false.
