-module(planning_nif).
-export([plan_status/0, plan_list_pending/0, plan_list_by_status/1,
         plan_get_task/1, plan_add_task/2, plan_update_task/2, plan_search/1]).
-on_load(init/0).

init() ->
    SoPath = case code:priv_dir(cepaf_gleam) of
        {error, _} -> "priv/native/planning_nif";
        PrivDir -> filename:join(PrivDir, "planning_nif")
    end,
    case erlang:load_nif(SoPath, 0) of
        ok -> ok;
        {error, {reload, _}} -> ok;
        {error, Reason} ->
            io:format("[planning_nif] NIF load failed: ~p (path: ~s)~n", [Reason, SoPath]),
            ok
    end.

%% NIF stubs — replaced by Rust at load time
plan_status() -> <<"{\"error\":\"NIF not loaded\"}">>.
plan_list_pending() -> <<"[]">>.
plan_list_by_status(_Status) -> <<"[]">>.
plan_get_task(_Id) -> <<"{\"error\":\"NIF not loaded\"}">>.
plan_add_task(_Title, _Priority) -> <<"{\"ok\":false,\"error\":\"NIF not loaded\"}">>.
plan_update_task(_Id, _Status) -> <<"{\"ok\":false,\"error\":\"NIF not loaded\"}">>.
plan_search(_Query) -> <<"[]">>.
