-module(rule_engine_nif).
-export([evaluate/3, parse_rules_count/1, engine_version/0]).
-on_load(init/0).

init() ->
    %% Try priv_dir first, then fallback to relative path
    SoPath = case code:priv_dir(cepaf_gleam) of
        {error, _} -> "priv/rule_engine_nif";
        PrivDir -> filename:join(PrivDir, "rule_engine_nif")
    end,
    case erlang:load_nif(SoPath, 0) of
        ok -> ok;
        {error, {reload, _}} -> ok;  %% Already loaded
        {error, Reason} ->
            io:format("[rule_engine_nif] NIF load failed: ~p (path: ~s)~n", [Reason, SoPath]),
            ok  %% Non-fatal — stubs will return nif_not_loaded
    end.

%% NIF stubs — replaced by Rust at load time
evaluate(_Domain, _RulesGrl, _Facts) ->
    {error, <<"NIF not loaded — rule_engine_nif.so not found">>}.

parse_rules_count(_RulesGrl) ->
    -1.

engine_version() ->
    <<"stub (NIF not loaded)">>.
