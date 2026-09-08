%% =============================================================================
%% Gleam FFI adapter for the Mojo KM metrics kernel (SC-PROVENANCE-001)
%% -----------------------------------------------------------------------------
%% uos_km_nif returns bare values on success and {error, Atom} on rejection.
%% Gleam's Result wants {ok, V} | {error, Reason}. This module is the shape
%% adapter and nothing else: it adds no policy and no defaulting.
%%
%% A rejection is converted to {error, BinaryReason} so the Gleam side can
%% report the kernel's own reason rather than inventing one.
%% =============================================================================
-module(cepaf_km_ffi).
-export([conformance_score/2, shannon_entropy_bits/1, drift_distance/2,
         fmea_band/3, column_means/1]).

wrap({error, Reason}) when is_atom(Reason) -> {error, atom_to_binary(Reason, utf8)};
wrap({error, Reason}) -> {error, iolist_to_binary(io_lib:format("~p", [Reason]))};
wrap({ok, Value}) -> {ok, Value};
wrap(Value) -> {ok, Value}.

conformance_score(Features, Weights) -> wrap(uos_km_nif:conformance_score(Features, Weights)).
shannon_entropy_bits(Counts) -> wrap(uos_km_nif:shannon_entropy_bits(Counts)).
drift_distance(Observed, Nominal) -> wrap(uos_km_nif:drift_distance(Observed, Nominal)).
fmea_band(S, O, D) -> wrap(uos_km_nif:fmea_band(S, O, D)).
column_means(Matrix) -> wrap(uos_km_nif:column_means(Matrix)).
