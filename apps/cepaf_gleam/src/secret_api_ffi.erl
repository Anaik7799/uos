%%% =============================================================================
%%% [C3I-SIL6] secret_api_ffi — Wave 11 wisp endpoint plumbing.
%%% =============================================================================
%%% Provides three primitives for ui/wisp/secret_api.gleam:
%%%
%%%   1. expected_token_sha256/0       — read pi_session.token, return SHA-256 hex.
%%%   2. constant_time_eq/2            — timing-safe binary comparison.
%%%   3. fetch_secret_via_subprocess/1 — spawn vault_migrate --get and capture JSON.
%%%
%%% SC-VAULT-005: hot path no network. The vault read shells out to a release
%%% binary on local disk; no HTTP/RPC hop. Stub-That-Lies guard is honored:
%%% if KEK or DB is missing, the subprocess exits non-zero and we surface the
%%% actual stderr token, never a fake-success.
%%%
%%% SC-VAULT-009: caller MUST emit Zenoh audit envelope after invoking this.
%%% This module deliberately does NOT publish — that's the Gleam caller's job
%%% to keep the FFI surface minimal.
%%%
%%% [zk-3346fc607a1ef9e6] Stub-That-Lies guard: every error path returns a
%%% distinct atom token ('kek_missing', 'binary_missing', 'subprocess_failed',
%%% 'secret_not_found', 'parse_failed'), never a generic 'error'.
%%% =============================================================================

-module(secret_api_ffi).
-export([
    expected_token_sha256/0,
    constant_time_eq/2,
    fetch_secret_via_subprocess/1,
    fetch_vault_status_via_subprocess/0,
    sha256_hex/1
]).

%% Canonical paths (operator-provisioned in Wave 10).
session_token_path() ->
    case os:getenv("HOME") of
        false -> "/home/an/.config/c3i/pi_session.token";
        Home -> Home ++ "/.config/c3i/pi_session.token"
    end.

vault_migrate_binary() ->
    "/home/an/dev/ver/c3i/sub-projects/c3i/target/release/vault_migrate".

kek_path() ->
    case os:getenv("HOME") of
        false -> "/home/an/.config/c3i/master.kek";
        Home -> Home ++ "/.config/c3i/master.kek"
    end.

%% sha256_hex/1 — returns lowercase hex string of SHA-256 of binary input.
sha256_hex(Bin) when is_binary(Bin) ->
    Digest = crypto:hash(sha256, Bin),
    list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= Digest]
    )).

%% expected_token_sha256/0 — read session token from disk, hash it, return hex.
%% Returns {ok, HexBin} on success, {error, Token} on failure.
%% This is called once at module load by the Gleam caller and held in a
%% process-dictionary or persistent_term cache.
expected_token_sha256() ->
    Path = session_token_path(),
    case file:read_file(Path) of
        {ok, Raw} ->
            %% Token may have trailing newline from `tr -d '\n'` operator step
            %% being skipped; strip whitespace to be lenient.
            Trimmed = string:trim(Raw),
            {ok, sha256_hex(Trimmed)};
        {error, enoent} ->
            {error, <<"session_token_missing">>};
        {error, eacces} ->
            {error, <<"session_token_unreadable">>};
        {error, Other} ->
            ErrBin = list_to_binary(io_lib:format("session_token_error:~p", [Other])),
            {error, ErrBin}
    end.

%% constant_time_eq/2 — timing-safe equality on two binaries of equal length.
%% Returns true | false. NEVER short-circuits on mismatch.
%% If lengths differ, returns false but still iterates the shorter to keep
%% the timing roughly stable.
constant_time_eq(A, B) when is_binary(A), is_binary(B) ->
    LA = byte_size(A),
    LB = byte_size(B),
    %% XOR each byte; OR results. Equal iff accumulator stays 0.
    case LA =:= LB of
        false ->
            %% Still iterate to avoid trivial timing leak; result is always false.
            _ = compare_bytes(A, A, 0),
            false;
        true ->
            compare_bytes(A, B, 0) =:= 0
    end.

compare_bytes(<<>>, <<>>, Acc) -> Acc;
compare_bytes(<<X, RestA/binary>>, <<Y, RestB/binary>>, Acc) ->
    compare_bytes(RestA, RestB, Acc bor (X bxor Y));
compare_bytes(_, _, _) -> 1.

%% fetch_secret_via_subprocess/1 — invoke vault_migrate --get --name <Name>.
%%
%% Returns the Gleam custom type FetchResult:
%%   {fetch_ok, JsonBin}     — exit 0, stdout has JSON
%%   {fetch_err, TokenBin}   — distinct token string per failure mode:
%%     <<"not_found">>           exit 6
%%     <<"kek_missing">>         exit 2 (or KEK file missing)
%%     <<"binary_missing">>      vault_migrate binary missing
%%     <<"subprocess_failed:N">> other non-zero (N=exit code or "timeout")
fetch_secret_via_subprocess(Name) when is_binary(Name) ->
    Bin = vault_migrate_binary(),
    case filelib:is_regular(Bin) of
        false ->
            {fetch_err, <<"binary_missing">>};
        true ->
            Kek = kek_path(),
            case filelib:is_regular(Kek) of
                false ->
                    {fetch_err, <<"kek_missing">>};
                true ->
                    Args = ["--get", "--name", binary_to_list(Name)],
                    Env = [{"C3I_VAULT_KEK_PATH", Kek}],
                    %% vault_migrate uses relative path "sub-projects/c3i/data/kms/smriti_vault.db".
                    %% BEAM cwd is lib/cepaf_gleam; subprocess must run from repo root.
                    Cwd = "/home/an/dev/ver/c3i",
                    Port = open_port(
                        {spawn_executable, Bin},
                        [
                            {args, Args},
                            {env, Env},
                            {cd, Cwd},
                            exit_status,
                            stderr_to_stdout,
                            binary,
                            stream
                        ]
                    ),
                    collect_port(Port, <<>>)
            end
    end.

collect_port(Port, Acc) ->
    receive
        {Port, {data, Chunk}} ->
            collect_port(Port, <<Acc/binary, Chunk/binary>>);
        {Port, {exit_status, 0}} ->
            {fetch_ok, string:trim(Acc)};
        {Port, {exit_status, 6}} ->
            {fetch_err, <<"not_found">>};
        {Port, {exit_status, 2}} ->
            {fetch_err, <<"kek_missing">>};
        {Port, {exit_status, N}} ->
            Token = list_to_binary(io_lib:format("subprocess_failed:~p", [N])),
            {fetch_err, Token}
    after 5000 ->
        catch port_close(Port),
        {fetch_err, <<"subprocess_failed:timeout">>}
    end.

%% fetch_vault_status_via_subprocess/0 — Wave 16 W4: SC-VAULT-009 dashboard tile
%% backing. Invokes `vault_migrate --status` (read-only, NO KEK access; never
%% decrypts). Returns:
%%   {fetch_ok, JsonBin}     — exit 0, stdout has status JSON
%%   {fetch_err, TokenBin}   — distinct error tokens
%%
%% Stub-That-Lies guard: when the binary is missing, returns binary_missing
%% (NOT a fake "vault Active" payload).
fetch_vault_status_via_subprocess() ->
    Bin = vault_migrate_binary(),
    case filelib:is_regular(Bin) of
        false ->
            {fetch_err, <<"binary_missing">>};
        true ->
            Args = ["--status"],
            %% --status mode does NOT need KEK; reads vault.db read-only.
            Cwd = "/home/an/dev/ver/c3i",
            Port = open_port(
                {spawn_executable, Bin},
                [
                    {args, Args},
                    {cd, Cwd},
                    exit_status,
                    stderr_to_stdout,
                    binary,
                    stream
                ]
            ),
            collect_port(Port, <<>>)
    end.
