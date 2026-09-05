%% =============================================================================
%% [C3I-SIL6-MSTS] OCaml bridge NIF shim
%% -----------------------------------------------------------------------------
%% Loads priv/c3i_ocaml_nif.so, which links the OCaml RETE-UL / Gospel substrate
%% (native/ocaml_nif/c3i_ocaml_bridge.ml) behind a C ErlNifFunc table.
%%
%% Every function returns a binary. rete_eval/1, gospel_verify/2, zenoh_dispatch/2
%% and parity_check/1 return JSON; version/0 returns a version string.
%%
%% Stubs below are replaced at load time. They are deliberately FAIL-CLOSED: if the
%% .so is missing, a gate evaluation must reject, never pass.
%% =============================================================================
-module(c3i_ocaml_nif).
-export([version/0, rete_eval/1, gospel_verify/2, zenoh_dispatch/2, parity_check/1]).
-on_load(init/0).

init() ->
    SoPath = case code:priv_dir(cepaf_gleam) of
        {error, _} -> "priv/c3i_ocaml_nif";
        PrivDir -> filename:join(PrivDir, "c3i_ocaml_nif")
    end,
    case erlang:load_nif(SoPath, 0) of
        ok -> ok;
        {error, {reload, _}} -> ok;
        {error, Reason} ->
            io:format("[c3i_ocaml_nif] NIF load failed: ~p (path: ~s)~n", [Reason, SoPath]),
            ok
    end.

%% NIF stubs — replaced by the C/OCaml substrate at load time.
version() ->
    <<"stub (NIF not loaded)">>.

rete_eval(_Facts) ->
    <<"{\"status\":\"error\",\"verdict\":\"rejected\",\"reason\":\"FAIL_CLOSED: c3i_ocaml_nif.so not loaded\"}">>.

gospel_verify(_Spec, _Payload) ->
    <<"{\"valid\":false,\"status\":\"rejected\",\"error\":\"FAIL_CLOSED: c3i_ocaml_nif.so not loaded\"}">>.

zenoh_dispatch(_Topic, _Payload) ->
    <<"{\"verdict\":\"failed\",\"error\":\"FAIL_CLOSED: c3i_ocaml_nif.so not loaded\"}">>.

parity_check(_Scenario) ->
    <<"{\"valid\":false,\"error\":\"FAIL_CLOSED: c3i_ocaml_nif.so not loaded\"}">>.
