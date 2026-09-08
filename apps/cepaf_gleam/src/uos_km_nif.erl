%% =============================================================================
%% UOS KM provenance metrics NIF shim (SC-PROVENANCE-001)
%% -----------------------------------------------------------------------------
%% Loads priv/uos_km_nif.so, a C-ABI facade (native/nifs/mojo/uos_km_nif.c) over
%% the Mojo kernel (native/nifs/mojo/uos_km_kernel.mojo).
%%
%% The stubs below are FAIL-CLOSED by construction: when the .so is absent every
%% entry point returns {error, nif_not_loaded}. A metric that cannot be computed
%% must never be reported as a passing number.
%% =============================================================================
-module(uos_km_nif).
-export([abi_version/0, conformance_score/2, shannon_entropy_bits/1,
         drift_distance/2, fmea_band/3, column_means/1, loaded/0]).
-on_load(init/0).

init() ->
    SoPath = case code:priv_dir(cepaf_gleam) of
        {error, _} -> "priv/uos_km_nif";
        PrivDir -> filename:join(PrivDir, "uos_km_nif")
    end,
    case erlang:load_nif(SoPath, 0) of
        ok -> ok;
        {error, {reload, _}} -> ok;
        {error, Reason} ->
            io:format("[uos_km_nif] NIF load failed: ~p (path: ~s)~n", [Reason, SoPath]),
            ok
    end.

%% loaded/0 answers whether the kernel is actually behind these functions.
%% Callers use it to distinguish "kernel says 0.0" from "kernel is absent".
loaded() ->
    case abi_version() of
        {error, nif_not_loaded} -> false;
        V when is_integer(V) -> true;
        _ -> false
    end.

%% --- NIF stubs, replaced at load time ---------------------------------------
abi_version() -> {error, nif_not_loaded}.
conformance_score(_Features, _Weights) -> {error, nif_not_loaded}.
shannon_entropy_bits(_Counts) -> {error, nif_not_loaded}.
drift_distance(_Observed, _Nominal) -> {error, nif_not_loaded}.
fmea_band(_S, _O, _D) -> {error, nif_not_loaded}.
column_means(_Matrix) -> {error, nif_not_loaded}.
