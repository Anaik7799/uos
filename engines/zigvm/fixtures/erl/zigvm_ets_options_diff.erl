%% zigvm_ets_options_diff — compiled differential for the ETS table-OPTION
%% observation algebra (DIVERGENCE 772 + its correction 773).
%%
%% `ets:new/2` accepted read_concurrency / write_concurrency /
%% decentralized_counters / compressed and the access atoms and then DISCARDED
%% them, so every one of them was a `badarg` through `ets:info/2` against a real
%% OTP-30 value; `protection` returned a hardcoded `protected`.
%%
%% The load-bearing case is `decentralized_counters`, which is DERIVED:
%%   dc = (protection /= private)
%%        AND write_concurrency enabled (true|auto)
%%        AND (dc_option ORELSE type == ordered_set)
%% The first nine cells of this vector were enumerated without varying
%% `protection`, and the implementation shipped WRONG for `private` as a direct
%% result — which is why the private rows below are not optional decoration.
-module(zigvm_ets_options_diff).
-export([t/1]).

i(L, Opts, Key) ->
    try
        T = ets:new(x, Opts),
        io:format("~-46s = ~p~n", [L, ets:info(T, Key)])
    catch C:R -> io:format("~-46s = EXC ~p:~p~n", [L, C, R])
    end.

t(_) ->
    %% read_concurrency / write_concurrency round-trip + defaults.
    i("default rc",            [set], read_concurrency),
    i("default wc",            [set], write_concurrency),
    i("default compressed",    [set], compressed),
    i("rc=true",               [set, {read_concurrency, true}], read_concurrency),
    i("wc=true",               [set, {write_concurrency, true}], write_concurrency),
    i("wc=auto",               [set, {write_concurrency, auto}], write_concurrency),
    i("compressed",            [compressed], compressed),
    %% protection: all three, the constant that used to be hardcoded.
    i("public",                [public], protection),
    i("protected",             [protected], protection),
    i("private",               [private], protection),
    %% decentralized_counters — the derived value, all dimensions varied.
    i("dc: set",                       [set], decentralized_counters),
    i("dc: set {dc,true}",             [set, {decentralized_counters, true}], decentralized_counters),
    i("dc: oset {dc,true}",            [ordered_set, {decentralized_counters, true}], decentralized_counters),
    i("dc: oset wc=true",              [ordered_set, {write_concurrency, true}], decentralized_counters),
    i("dc: oset wc=auto",              [ordered_set, {write_concurrency, auto}], decentralized_counters),
    i("dc: set wc=true",               [set, {write_concurrency, true}], decentralized_counters),
    i("dc: set wc=true dc=true",       [set, {write_concurrency, true}, {decentralized_counters, true}], decentralized_counters),
    i("dc: oset wc=true dc=false",     [ordered_set, {write_concurrency, true}, {decentralized_counters, false}], decentralized_counters),
    %% …and the dimension the first nine cells did not vary.
    i("dc: oset wc=true private",      [ordered_set, {write_concurrency, true}, private], decentralized_counters),
    i("dc: oset wc=true dc=true priv", [ordered_set, {write_concurrency, true}, {decentralized_counters, true}, private], decentralized_counters),
    i("dc: set wc=true dc=true priv",  [set, {write_concurrency, true}, {decentralized_counters, true}, private], decentralized_counters),
    i("dc: oset wc=auto private",      [ordered_set, {write_concurrency, auto}, private], decentralized_counters),
    i("dc: set wc=true dc=true public",[set, {write_concurrency, true}, {decentralized_counters, true}, public], decentralized_counters),
    i("dc: oset wc=true public",       [ordered_set, {write_concurrency, true}, public], decentralized_counters),
    %% REJECTION: option values are validated, and the tuple form of
    %% `compressed` is illegal — an accept-everything parser passes every
    %% positive row above.
    i("reject {rc,notabool}",  [{read_concurrency, notabool}], read_concurrency),
    i("reject {wc,7}",         [{write_concurrency, 7}], write_concurrency),
    i("reject {dc,notabool}",  [{decentralized_counters, notabool}], decentralized_counters),
    i("reject {compressed,true}", [{compressed, true}], compressed),
    %% LAST WINS, both orders.
    i("last-wins rc t,f",      [{read_concurrency, true}, {read_concurrency, false}], read_concurrency),
    i("last-wins rc f,t",      [{read_concurrency, false}, {read_concurrency, true}], read_concurrency),
    halt(0).  %% clean exit on both — a returned value would be printed by
              %% `zigvm run` and swallowed by `erl -eval` (a RECIPE artifact,
              %% not a divergence; the io_format vector solved it the same way).
