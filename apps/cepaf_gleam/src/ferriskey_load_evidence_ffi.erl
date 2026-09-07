%% =============================================================================
%% [C3I-SIL6-MSTS] ferriskey_load_evidence_ffi — load-evidence test helper
%% =============================================================================
%% TEST-ONLY helper for test/ferriskey_nif_load_evidence_test.gleam.
%%
%% resolved_so_path/0 resolves the on-disk path of priv/ferriskey_nif.so
%% using the EXACT same algorithm as src/ferriskey_nif:init/0 (that file,
%% lines 76-85), so the load-evidence test agrees with what the -on_load
%% loader itself will try to open. This cannot be expressed in pure Gleam
%% because code:priv_dir/1 and code:which/1 are Erlang/OTP code-server
%% primitives with no Gleam stdlib wrapper in this package.
%%
%% safe_ping/0 is a crash-safe probe of ferriskey_nif:ferriskey_ping/0.
%%
%% FINDING (verified empirically in a throwaway ebin sandbox: erlc + a
%% freshly started `erl -pa`, with no priv/ferriskey_nif.so on the code
%% path — this repo's own priv/ artifacts were never touched):
%% src/ferriskey_nif:init/0 returns erlang:load_nif/2's raw result
%% straight from -on_load, unlike src/c3i_nif:init/0, which always returns
%% `ok` and separately records load success/failure in a persistent_term
%% (see c3i_nif:runtime_loaded/0). Per Erlang on_load semantics, when an
%% -on_load function does not return `ok`, the ENTIRE module fails to load
%% (code:is_loaded/1 reports false) — so on a host without
%% priv/ferriskey_nif.so, calling ferriskey_nif:ferriskey_ping/0 directly
%% raises `error:undef`, NOT a clean {error, _} stub return from the
%% nif_error/... bodies below the -on_load line (those bodies are only
%% reachable if the module itself is loaded, which it is not in this case).
%% safe_ping/0 catches that (and any other unexpected crash) at this
%% boundary and normalizes it into a typed {ok, _} | {error, _} Result so
%% the Gleam test never observes a raw BEAM crash and can assert
%% fail-closed behavior honestly on every host.
%%
%% This module MUST NOT be reachable from production code paths.
%% =============================================================================
-module(ferriskey_load_evidence_ffi).
-export([resolved_so_path/0, safe_ping/0]).

%% @doc Mirror of ferriskey_nif:init/0's PrivDir/Lib resolution
%% (src/ferriskey_nif.erl:76-85), returned as a binary path to
%% "<priv_dir>/ferriskey_nif.so" for on-disk existence checks.
-spec resolved_so_path() -> binary().
resolved_so_path() ->
    PrivDir = case code:priv_dir(cepaf_gleam) of
        {error, _} ->
            EbinDir = filename:dirname(code:which(ferriskey_nif)),
            AppPath = filename:dirname(EbinDir),
            filename:join(AppPath, "priv");
        Path -> Path
    end,
    unicode:characters_to_binary(filename:join(PrivDir, "ferriskey_nif.so")).

%% @doc Crash-safe probe of ferriskey_nif:ferriskey_ping/0. See module
%% header for why this cannot simply call the typed `ping()` Gleam binding
%% unconditionally: on a host where priv/ferriskey_nif.so is absent, the
%% whole ferriskey_nif module fails -on_load and any direct call raises
%% error:undef instead of returning an Erlang term.
-spec safe_ping() -> {ok, binary()} | {error, binary()}.
safe_ping() ->
    try ferriskey_nif:ferriskey_ping() of
        {ok, Json} when is_binary(Json) ->
            {ok, Json};
        {error, Reason} ->
            {error, to_bin(Reason)};
        Other ->
            {error,
                unicode:characters_to_binary(
                    io_lib:format("unexpected_return:~p", [Other])
                )}
    catch
        error:undef ->
            {error,
                <<"ferriskey_nif module failed -on_load (priv/ferriskey_nif.so "
                    "absent or unloadable); direct calls raise error:undef">>};
        Class:Reason:_Stack ->
            {error,
                unicode:characters_to_binary(
                    io_lib:format("~p:~p", [Class, Reason])
                )}
    end.

to_bin(B) when is_binary(B) -> B;
to_bin(Other) -> unicode:characters_to_binary(io_lib:format("~p", [Other])).
