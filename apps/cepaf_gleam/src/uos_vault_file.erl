%% =============================================================================
%% [C3I-SIL6] uos_vault_file — durable, passphrase-sealed secret store (v1)
%% =============================================================================
%% Why this exists (wave 6r, 2026-10-26): the host-provisioned rusty_vault_nif
%% keeps its key/value store in process memory only. Observed on nas-1: a put
%% in one BEAM is not_found in the next, no byte is written under the storage
%% or audit path it is given, and a master key derived from a WRONG passphrase
%% unseals it. A bot token kept there would not survive a restart and would be
%% protected by nothing. This module is the durable fallback the Telegram
%% staging service uses until a persisting vault backend is admitted; it keeps
%% the vault's name space ("telegram/staging/bot_token") so a later migration
%% is a rename, not a redesign.
%%
%% Format of one secret file (Store/<name with "/" as "__">.v1), mode 0600:
%%   "UOSV1" | salt:16 | iv:16 | mac:32 | ciphertext
%%   key material = PBKDF2-HMAC-SHA256(passphrase, salt, 200000, 64)
%%                = aes_key:32 || mac_key:32
%%   ciphertext   = AES-256-CBC(aes_key, iv, pkcs7(secret))
%%   mac          = HMAC-SHA256(mac_key, iv || ciphertext)   (encrypt-then-MAC)
%% The passphrase is read from a file the caller names (0600, operator-owned,
%% or a systemd credential); it is never taken from an argument or the
%% environment, so it cannot appear in a process listing. Nothing here logs,
%% prints or returns the passphrase or a plaintext except `get/3`'s result.
%% A wrong passphrase fails the MAC check before any decryption: {error, mac}.
-module(uos_vault_file).
-export([put/4, get/3, exists/2, put_from_stdin/3, secret_path/2]).
%% put returns {ok, nil} so a Gleam caller sees Result(Nil, Dynamic).

-define(MAGIC, <<"UOSV1">>).
-define(ITERATIONS, 200000).

secret_path(Store, Name) when is_binary(Store), is_binary(Name) ->
    Safe = binary:replace(Name, <<"/">>, <<"__">>, [global]),
    filename:join(Store, <<Safe/binary, ".v1">>).

exists(Store, Name) ->
    filelib:is_regular(secret_path(Store, Name)).

read_passphrase(PassFile) ->
    case file:read_file(PassFile) of
        {ok, Raw} ->
            case string:trim(Raw, trailing, "\r\n") of
                <<>> -> {error, empty_passphrase};
                Pass when byte_size(Pass) < 12 -> {error, passphrase_too_short};
                Pass -> {ok, Pass}
            end;
        {error, Reason} -> {error, {passphrase_file, Reason}}
    end.

keys(Pass, Salt) ->
    <<AesKey:32/binary, MacKey:32/binary>> =
        crypto:pbkdf2_hmac(sha256, Pass, Salt, ?ITERATIONS, 64),
    {AesKey, MacKey}.

put(Store, Name, Secret, PassFile) when is_binary(Secret) ->
    case read_passphrase(PassFile) of
        {error, R} -> {error, R};
        {ok, Pass} ->
            case Secret of
                <<>> -> {error, empty_secret};
                _ ->
                    Salt = crypto:strong_rand_bytes(16),
                    Iv = crypto:strong_rand_bytes(16),
                    {AesKey, MacKey} = keys(Pass, Salt),
                    Cipher = crypto:crypto_one_time(aes_256_cbc, AesKey, Iv, Secret,
                                                    [{encrypt, true}, {padding, pkcs_padding}]),
                    Mac = crypto:mac(hmac, sha256, MacKey, <<Iv/binary, Cipher/binary>>),
                    Path = secret_path(Store, Name),
                    ok = filelib:ensure_dir(Path),
                    Tmp = <<Path/binary, ".tmp">>,
                    case file:write_file(Tmp, <<?MAGIC/binary, Salt/binary, Iv/binary, Mac/binary, Cipher/binary>>) of
                        ok ->
                            ok = file:change_mode(Tmp, 8#600),
                            case file:rename(Tmp, Path) of
                                ok -> {ok, nil};
                                {error, R} -> _ = file:delete(Tmp), {error, {rename, R}}
                            end;
                        {error, R} -> {error, {write, R}}
                    end
            end
    end.

get(Store, Name, PassFile) ->
    case read_passphrase(PassFile) of
        {error, R} -> {error, R};
        {ok, Pass} ->
            case file:read_file(secret_path(Store, Name)) of
                {error, enoent} -> {error, not_found};
                {error, R} -> {error, {read, R}};
                {ok, <<"UOSV1", Salt:16/binary, Iv:16/binary, Mac:32/binary, Cipher/binary>>} ->
                    {AesKey, MacKey} = keys(Pass, Salt),
                    Expected = crypto:mac(hmac, sha256, MacKey, <<Iv/binary, Cipher/binary>>),
                    case crypto:hash_equals(Mac, Expected) of
                        false -> {error, mac};
                        true ->
                            try
                                {ok, crypto:crypto_one_time(aes_256_cbc, AesKey, Iv, Cipher,
                                                            [{encrypt, false}, {padding, pkcs_padding}])}
                            catch _:_ -> {error, decrypt}
                            end
                    end;
                {ok, _} -> {error, format}
            end
    end.

%% Operator entry: the secret arrives on stdin (one line, trailing newline
%% stripped), so it never appears in an argument list or shell history.
put_from_stdin(Store, Name, PassFile) ->
    case io:get_line("") of
        eof -> {error, empty_secret};
        {error, R} -> {error, {stdin, R}};
        Line ->
            Secret = string:trim(unicode:characters_to_binary(Line), trailing, "\r\n"),
            put(Store, Name, Secret, PassFile)
    end.
