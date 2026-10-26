%%% rusty_vault_persistence_test — VF-01 laws observed through the loaded NIF.
%%%
%%% The wave 6r finding: the vault NIF persisted nothing and unsealed with any
%%% 32-byte key. These laws pin the closure: a put through one handle is read
%%% through a fresh handle on the same file, a wrong key is refused and leaves
%%% the vault sealed, and neither the plaintext nor the master key reaches
%%% the file. The cross-BEAM form of the first law is observed by
%%% tools evidence (three erl processes), not here.
%%%
%%% Runs only where the host-provisioned apps/cepaf_gleam/priv/rusty_vault_nif.so
%%% is present (INV-WS-08); an unprovisioned workspace reports nif_unavailable,
%%% which is a provisioning fact, not a vault defect.
-module(rusty_vault_persistence_test).
-include_lib("eunit/include/eunit.hrl").

key(B) -> binary:copy(<<B>>, 32).

fresh_dir() ->
    Dir = filename:join(["/tmp", "rusty_vault_persistence_" ++ integer_to_list(erlang:unique_integer([positive]))]),
    ok = file:make_dir(Dir),
    list_to_binary(Dir).

nif_available() ->
    try rusty_vault_nif:kek_generate_salt() of
        {ok, _} -> true;
        _ -> false
    catch
        error:undef -> false;
        error:{load_failed, _} -> false
    end.

law_persistence_across_handles_test() ->
    case nif_available() of
        false -> ?debugMsg("rusty_vault_nif unavailable: provisioning, not a defect"), ok;
        true ->
            Dir = fresh_dir(),
            Db = <<Dir/binary, "/vault.sqlite3">>,
            {ok, H1} = rusty_vault_nif:vault_init(Dir, <<Dir/binary, "/audit.log">>),
            ?assertEqual(sealed, maps:get(name, rusty_vault_nif:vault_status(H1))),
            ?assertEqual({ok, nil}, rusty_vault_nif:vault_unseal(H1, key(16#11))),
            {ok, #{version := 1, lease_id := Lease}} =
                rusty_vault_nif:vault_kv_put(H1, <<"telegram/staging/bot_token">>, <<"123456:not-a-real-token">>, 60, 600),
            ?assert(binary:match(Lease, <<"lease-telegram/staging/bot_token-1-">>) =/= nomatch),
            ok = rusty_vault_nif:vault_seal(H1),
            %% a fresh handle on the same file, as a restarted BEAM would open it
            {ok, H2} = rusty_vault_nif:vault_init(Db, <<Dir/binary, "/audit.log">>),
            ?assertEqual({error, sealed}, rusty_vault_nif:vault_kv_get(H2, <<"telegram/staging/bot_token">>)),
            ?assertEqual({ok, nil}, rusty_vault_nif:vault_unseal(H2, key(16#11))),
            ?assertEqual({ok, <<"123456:not-a-real-token">>}, rusty_vault_nif:vault_kv_get(H2, <<"telegram/staging/bot_token">>)),
            {ok, Versions} = rusty_vault_nif:vault_kv_versions(H2, <<"telegram/staging/bot_token">>),
            ?assertEqual([1], [maps:get(version, V) || V <- Versions]),
            {ok, Expiry} = rusty_vault_nif:vault_lease_renew(H2, Lease, 120),
            ?assert(is_integer(Expiry)),
            ok = rusty_vault_nif:vault_kv_destroy(H2, <<"telegram/staging/bot_token">>, 1),
            ?assertEqual({error, {not_found, <<"telegram/staging/bot_token">>}},
                         rusty_vault_nif:vault_kv_get(H2, <<"telegram/staging/bot_token">>))
    end.

law_wrong_key_is_refused_and_vault_stays_sealed_test() ->
    case nif_available() of
        false -> ok;
        true ->
            Dir = fresh_dir(),
            {ok, H1} = rusty_vault_nif:vault_init(Dir, <<Dir/binary, "/audit.log">>),
            {ok, nil} = rusty_vault_nif:vault_unseal(H1, key(16#11)),
            {ok, _} = rusty_vault_nif:vault_kv_put(H1, <<"k">>, <<"v">>, 60, 600),
            {ok, H2} = rusty_vault_nif:vault_init(Dir, <<Dir/binary, "/audit.log">>),
            ?assertEqual({error, wrong_key}, rusty_vault_nif:vault_unseal(H2, key(16#22))),
            ?assertEqual(sealed, maps:get(name, rusty_vault_nif:vault_status(H2))),
            ?assertEqual({error, sealed}, rusty_vault_nif:vault_kv_get(H2, <<"k">>)),
            ?assertEqual({error, wrong_key}, rusty_vault_nif:vault_unseal(H2, <<1, 2, 3>>)),
            ?assertEqual({ok, nil}, rusty_vault_nif:vault_unseal(H2, key(16#11))),
            ?assertEqual({ok, <<"v">>}, rusty_vault_nif:vault_kv_get(H2, <<"k">>)),
            {ok, Audit} = rusty_vault_nif:vault_audit_tail(H2, 0),
            Events = [maps:get(<<"event">>, M) || M <- Audit],
            ?assert(lists:member(<<"key_established">>, Events)),
            ?assert(lists:member(<<"unseal_refused">>, Events)),
            ?assertEqual(<<"key_established">>, hd(Events))
    end.

law_no_plaintext_or_key_on_disk_test() ->
    case nif_available() of
        false -> ok;
        true ->
            Dir = fresh_dir(),
            Secret = <<"8660817750:AAAA-not-a-real-token-but-long-enough-to-find">>,
            {ok, H} = rusty_vault_nif:vault_init(Dir, <<Dir/binary, "/audit.log">>),
            {ok, nil} = rusty_vault_nif:vault_unseal(H, key(16#44)),
            {ok, _} = rusty_vault_nif:vault_kv_put(H, <<"t">>, Secret, 60, 600),
            ok = rusty_vault_nif:vault_seal(H),
            {ok, Files} = file:list_dir(binary_to_list(Dir)),
            Bytes = iolist_to_binary([element(2, file:read_file(filename:join(binary_to_list(Dir), F))) || F <- Files]),
            ?assert(byte_size(Bytes) > 0),
            ?assertEqual(nomatch, binary:match(Bytes, Secret)),
            ?assertEqual(nomatch, binary:match(Bytes, key(16#44)))
    end.
