%% =============================================================================
%% beam_cache_ffi.erl — BEAM-native ETS + persistent_term FFI
%% Layer: L3_TRANSACTION
%% STAMP: SC-FUNC-004, SC-MUDA-001
%% =============================================================================
%%
%% ETS (Erlang Term Storage) — public named table, concurrent reads, O(1) access.
%% persistent_term — globally accessible hot config, O(1) read, amortised write.
%%
%% अक्षरं ब्रह्म परमम् — The imperishable is the supreme Brahman (Gita 8.3)

-module(beam_cache_ffi).
-export([ets_init/0, ets_put/2, ets_get/1, ets_delete/1, ets_keys/0, ets_size/0]).
-export([pt_set/2, pt_get/1]).

%% ---------------------------------------------------------------------------
%% ETS — named table, public, set, concurrent reads enabled
%% ---------------------------------------------------------------------------

%% @doc Create the c3i_cache ETS table. Safe to call multiple times; subsequent
%%      calls are no-ops when the table already exists.
ets_init() ->
    try
        ets:new(c3i_cache, [named_table, public, set, {read_concurrency, true}]),
        {ok, nil}
    catch
        error:badarg ->
            %% Table already exists — idempotent
            {ok, nil}
    end.

%% @doc Insert or replace a key/value pair. Both key and value are binaries.
ets_put(Key, Value) ->
    ets:insert(c3i_cache, {Key, Value}),
    {ok, nil}.

%% @doc Lookup a key. Returns {ok, Value} or {error, <<"not_found">>}.
ets_get(Key) ->
    case ets:lookup(c3i_cache, Key) of
        [{_, Value}] -> {ok, Value};
        []           -> {error, <<"not_found">>}
    end.

%% @doc Remove a key from the table. Safe even if the key is absent.
ets_delete(Key) ->
    ets:delete(c3i_cache, Key),
    {ok, nil}.

%% @doc Return a list of all keys currently in the table.
ets_keys() ->
    ets:foldl(fun({K, _}, Acc) -> [K | Acc] end, [], c3i_cache).

%% @doc Return the number of entries currently in the table.
ets_size() ->
    ets:info(c3i_cache, size).

%% ---------------------------------------------------------------------------
%% persistent_term — O(1) read, one-time GC cost on write
%% Key namespace: {c3i_config, BinaryKey}
%% ---------------------------------------------------------------------------

%% @doc Persist a config value globally. Triggers a GC scan of all processes
%%      on write — use for infrequently changing configuration only.
pt_set(Key, Value) ->
    persistent_term:put({c3i_config, Key}, Value),
    {ok, nil}.

%% @doc Retrieve a config value in O(1) with zero message passing.
%%      Returns {error, <<"not_found">>} when the key has never been set.
pt_get(Key) ->
    try
        {ok, persistent_term:get({c3i_config, Key})}
    catch
        error:badarg ->
            {error, <<"not_found">>}
    end.
