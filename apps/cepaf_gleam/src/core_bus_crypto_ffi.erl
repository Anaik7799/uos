%% UOS-CORE-EVO Native OTP 29 Ed25519 Envelope Authentication FFI
%% (`SC-HARNESS-MCP-001`, `SC-PROVENANCE-001`, Zero-Muda pure OTP `crypto`)
%%
%% Zero private keys are ever persisted to disk: ephemeral session keypairs live
%% exclusively in BEAM RAM (`persistent_term`), while deterministic keypair
%% helpers support offline/unit verification of RFC 8032 Ed25519 signatures.
-module(core_bus_crypto_ffi).
-on_load(init_crypto_lock/0).

-export([
    generate_ed25519_keypair_hex/0,
    session_ed25519_pubkey_hex/0,
    sign_with_session_ed25519_hex/1,
    sign_ed25519_hex/2,
    verify_ed25519_hex/3,
    advance_replay_seq_atomic/2,
    reset_session_ed25519_for_test/0,
    reset_replay_table_for_test/0,
    concurrent_cold_start_unique_pubkeys_for_test/1,
    concurrent_replay_winners_for_test/3
]).

-define(SESSION_KEY_SLOT, {core_bus_crypto_ffi, session_ed25519_keypair}).
-define(REPLAY_TABLE, core_bus_replay_ets).
-define(REPLAY_OWNER, core_bus_replay_ets_owner).

generate_ed25519_keypair_hex() ->
    {Pub, Priv} = crypto:generate_key(eddsa, ed25519),
    {to_lower_hex(Pub), to_lower_hex(Priv)}.

session_ed25519_pubkey_hex() ->
    {PubHex, _PrivHex} = ensure_session_keypair(),
    PubHex.

init_crypto_lock() ->
    _ = code:stick_mod(?MODULE),
    MeshMod = 'cepaf_gleam@ecology@core_fpp_actor_twin_mesh',
    CandMod = core_fpp_candidate_ffi,
    case code:is_loaded(MeshMod) of
        {file, _} -> _ = code:stick_mod(MeshMod);
        false -> ok
    end,
    case code:is_loaded(CandMod) of
        {file, _} -> _ = code:stick_mod(CandMod);
        false -> ok
    end,
    ok.

sign_with_session_ed25519_hex(MsgBin) when is_binary(MsgBin) ->
    case verify_fpp_mesh_candidate_frame(MsgBin) of
        false ->
            {error, <<"candidate_integrity_violation">>};
        true ->
            {PubHex, PrivHex} = ensure_session_keypair(),
            case sign_ed25519_hex(MsgBin, PrivHex) of
                {ok, SigHex} -> {ok, {PubHex, SigHex}};
                {error, Reason} -> {error, Reason}
            end
    end.

verify_fpp_mesh_candidate_frame(MsgBin) ->
    case binary:split(MsgBin, <<"|">>, [global]) of
        [<<"uos.zenoh.core_evo.v1">>, _Topic, CandidateSha, <<"uos/universal-intelligent-fpp-actor-mesh/20261101-2232">> | _] ->
            MeshMod = 'cepaf_gleam@ecology@core_fpp_actor_twin_mesh',
            CandMod = core_fpp_candidate_ffi,
            _ = code:ensure_loaded(MeshMod),
            _ = code:ensure_loaded(CandMod),
            _ = code:stick_mod(?MODULE),
            _ = code:stick_mod(MeshMod),
            _ = code:stick_mod(CandMod),
            same_ebin_dir(?MODULE, CandMod, MeshMod) andalso
                disk_md5_matches(?MODULE) andalso
                disk_md5_matches(CandMod) andalso
                disk_md5_matches(MeshMod) andalso
                CandidateSha =/= <<>> andalso
                CandidateSha =:= CandMod:verified_candidate_sha256();
        _ ->
            true
    end.

same_ebin_dir(ModA, ModB, ModC) ->
    case {resolved_beam_dir(ModA), resolved_beam_dir(ModB), resolved_beam_dir(ModC)} of
        {{ok, Dir}, {ok, Dir}, {ok, Dir}} -> true;
        _ -> false
    end.

resolved_beam_dir(Mod) ->
    try
        case code:which(Mod) of
            Path when is_list(Path), Path =/= "" ->
                {ok, filename:dirname(filename:absname(Path))};
            _ ->
                error
        end
    catch
        _:_ -> error
    end.

disk_md5_matches(Mod) ->
    try
        case code:which(Mod) of
            Path when is_list(Path), Path =/= "" ->
                Abs = filename:absname(Path),
                case file:read_file(Abs) of
                    {ok, Bytes} ->
                        case beam_lib:md5(Bytes) of
                            {ok, {Mod, DiskMd5}} ->
                                erlang:get_module_info(Mod, md5) =:= DiskMd5;
                            _ ->
                                false
                        end;
                    _ ->
                        false
                end;
            _ ->
                false
        end
    catch
        _:_ -> false
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

%% Test-only: tear down `core_bus_replay_ets` + owner so cold-start short-lived
%% worker concurrency is exercised from a completely uninitialized ETS state.
reset_replay_table_for_test() ->
    case whereis(?REPLAY_OWNER) of
        undefined -> ok;
        Pid ->
            catch unregister(?REPLAY_OWNER),
            exit(Pid, kill),
            timer:sleep(10)
    end,
    case ets:whereis(?REPLAY_TABLE) of
        undefined -> ok;
        _ -> catch ets:delete(?REPLAY_TABLE)
    end,
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

%% Dedicated immortal ETS owner for replay high-water marks so that even if the
%% very first caller is a short-lived spawned request/worker process that exits
%% immediately after consuming an envelope, `core_bus_replay_ets` survives for
%% the entire BEAM VM lifetime and remains isolated from general cache eviction.
ensure_replay_table() ->
    case ets:whereis(?REPLAY_TABLE) of
        undefined ->
            global:trans({?REPLAY_TABLE, self()}, fun() ->
                case ets:whereis(?REPLAY_TABLE) of
                    undefined ->
                        Parent = self(),
                        Ref = make_ref(),
                        Owner = spawn(fun() ->
                            process_flag(trap_exit, true),
                            HeirOpts =
                                case whereis(init) of
                                    undefined -> [];
                                    InitPid -> [{heir, InitPid, none}]
                                end,
                            _ = ets:new(?REPLAY_TABLE, [
                                named_table,
                                public,
                                set,
                                {read_concurrency, true},
                                {write_concurrency, true}
                                | HeirOpts
                            ]),
                            try register(?REPLAY_OWNER, self()) catch _:_ -> ok end,
                            Parent ! {Ref, ready},
                            replay_owner_loop()
                        end),
                        true = is_pid(Owner),
                        receive
                            {Ref, ready} -> ?REPLAY_TABLE
                        after 5000 ->
                            erlang:error(replay_table_init_timeout)
                        end;
                    _Tid ->
                        ?REPLAY_TABLE
                end
            end);
        _Tid ->
            ?REPLAY_TABLE
    end.

replay_owner_loop() ->
    receive
        _ -> replay_owner_loop()
    end.

%% Atomic monotonic high-water check-and-advance per `(signer_pubkey_hex, topic)`.
%% Serializes concurrent BEAM receivers racing on the same replay key via
%% `global:trans/2` over the immortal `core_bus_replay_ets` table so at most ONE
%% caller ever accepts a given `SeqId`.
advance_replay_seq_atomic(ReplayKeyBin, SeqId)
  when is_binary(ReplayKeyBin), is_integer(SeqId) ->
    Table = ensure_replay_table(),
    global:trans({{core_bus_replay_seq, ReplayKeyBin}, self()}, fun() ->
        HighWater =
            case ets:lookup(Table, ReplayKeyBin) of
                [{_, PrevSeq}] when is_integer(PrevSeq) -> PrevSeq;
                _ -> 0
            end,
        case SeqId > HighWater of
            false ->
                {error, HighWater};
            true ->
                true = ets:insert(Table, {ReplayKeyBin, SeqId}),
                {ok, SeqId}
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
