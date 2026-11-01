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
    verify_ed25519_hex/3,
    advance_replay_seq_atomic/2,
    reset_session_ed25519_for_test/0,
    concurrent_cold_start_unique_pubkeys_for_test/1,
    concurrent_replay_winners_for_test/3
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

%% Warm path is a lock-free O(1) `persistent_term:get/2`. Only the cold-start
%% path is serialized through `global:trans/2` so that N concurrent first-use
%% callers observe exactly one identical `{PubHex, PrivHex}` pair (double-checked
%% locking: the loser of the race re-reads the slot the winner published).
ensure_session_keypair() ->
    case persistent_term:get(?SESSION_KEY_SLOT, undefined) of
        {PubHex, PrivHex} when is_binary(PubHex), is_binary(PrivHex) ->
            {PubHex, PrivHex};
        undefined ->
            global:trans({?SESSION_KEY_SLOT, self()}, fun() ->
                case persistent_term:get(?SESSION_KEY_SLOT, undefined) of
                    {PubHex, PrivHex} when is_binary(PubHex), is_binary(PrivHex) ->
                        {PubHex, PrivHex};
                    undefined ->
                        Pair = generate_ed25519_keypair_hex(),
                        persistent_term:put(?SESSION_KEY_SLOT, Pair),
                        Pair
                end
            end)
    end.

%% Test-only: clear the in-RAM ephemeral session keypair prior to a cold start.
reset_session_ed25519_for_test() ->
    _ = persistent_term:erase(?SESSION_KEY_SLOT),
    nil.

%% Test-only concurrency probe: erase the session slot, spawn `N` processes that
%% all block on a barrier, release them simultaneously, and require that every
%% signature verifies against the single final session public key. Returns the
%% number of distinct `PubHex` values observed across all `N` signers, or `-1` if
%% any signature failed to verify against the final session public key (fail-closed).
concurrent_cold_start_unique_pubkeys_for_test(N)
  when is_integer(N), N > 0, N =< 4096 ->
    _ = reset_session_ed25519_for_test(),
    Parent = self(),
    Msg = <<"cold_start_probe">>,
    Pids = [
        spawn(fun() ->
            receive
                {go, From} ->
                    From ! {result, self(), sign_with_session_ed25519_hex(Msg)}
            end
        end)
     || _ <- lists:seq(1, N)
    ],
    [Pid ! {go, Parent} || Pid <- Pids],
    Results = [
        receive
            {result, Pid, R} -> R
        after 30000 -> {error, <<"cold_start_probe_timeout">>}
        end
     || Pid <- Pids
    ],
    FinalPubHex = session_ed25519_pubkey_hex(),
    Observed = [
        {PubHex, SigHex}
     || {ok, {PubHex, SigHex}} <- Results
    ],
    AllSigned =
        length(Observed) =:= N andalso
            lists:all(
                fun({PubHex, SigHex}) ->
                    PubHex =:= FinalPubHex andalso
                        verify_ed25519_hex(Msg, SigHex, FinalPubHex)
                end,
                Observed
            ),
    case AllSigned of
        true -> length(lists:usort([PubHex || {PubHex, _} <- Observed]));
        false -> -1
    end.

%% Atomic monotonic high-water check-and-advance per `(signer_pubkey_hex, topic)`.
%% Serializes concurrent BEAM receivers racing on the same replay key via
%% `global:trans/2` over the durable `beam_cache_ffi` ETS table so at most ONE
%% caller ever accepts a given `SeqId`.
advance_replay_seq_atomic(ReplayKeyBin, SeqId)
  when is_binary(ReplayKeyBin), is_integer(SeqId) ->
    _ = beam_cache_ffi:ets_init(),
    global:trans({{core_bus_replay_seq, ReplayKeyBin}, self()}, fun() ->
        HighWater =
            case beam_cache_ffi:ets_get(ReplayKeyBin) of
                {ok, RawBin} when is_binary(RawBin) ->
                    try binary_to_integer(RawBin) catch _:_ -> 0 end;
                _ ->
                    0
            end,
        case SeqId > HighWater of
            false ->
                {error, HighWater};
            true ->
                case beam_cache_ffi:ets_put(ReplayKeyBin, integer_to_binary(SeqId)) of
                    {ok, nil} -> {ok, SeqId};
                    _ -> {error, -1}
                end
        end
    end).

%% Test-only concurrency probe: spawn `N` processes that block on a barrier and
%% race simultaneously on `consume_authenticated_envelope_once/2` for the exact
%% same authenticated wire frame. Returns `{AcceptedCount, RejectedCount}`.
concurrent_replay_winners_for_test(WireBin, ExpectedPubHex, N)
  when is_binary(WireBin), is_binary(ExpectedPubHex), is_integer(N), N > 0, N =< 4096 ->
    Parent = self(),
    Pids = [
        spawn(fun() ->
            receive
                {go_replay, From} ->
                    Res = cepaf_gleam@zenoh@core_bus:consume_authenticated_envelope_once(
                        WireBin,
                        ExpectedPubHex
                    ),
                    From ! {replay_result, self(), Res}
            end
        end)
     || _ <- lists:seq(1, N)
    ],
    [Pid ! {go_replay, Parent} || Pid <- Pids],
    Results = [
        receive
            {replay_result, Pid, R} -> R
        after 30000 -> {error, timeout}
        end
     || Pid <- Pids
    ],
    Accepted = length([ok || {ok, _} <- Results]),
    Rejected = length([err || {error, {auth_core_error, {err_non_monotonic_seq, _, _}}} <- Results]),
    {Accepted, Rejected}.

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
