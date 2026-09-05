%% http-laneC supervisor verify: a real supervisor (one_for_one) + gen_server child
%% runs byte-EQ vs OTP-30 loading the pinned stdlib beams (supervisor/gen_server/
%% gen/proc_lib/sys + lists/maps/sets). Both print {sup_started,true,1}. DIVERGENCE 639.
-module(zigvm_sup).
-behaviour(supervisor).
-export([go/1, init/1, start_worker/0]).
start_worker() -> zigvm_worker:start_link().
init(sup) ->
    Child = #{id => w, start => {?MODULE, start_worker, []}, restart => permanent, type => worker},
    {ok, {#{strategy => one_for_one, intensity => 1, period => 5}, [Child]}}.
go(_) ->
    {ok, Sup} = supervisor:start_link({local, zsup}, ?MODULE, sup),
    Kids = supervisor:which_children(Sup),
    erlang:display({sup_started, is_pid(Sup), length(Kids)}),
    ok.
