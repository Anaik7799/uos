%% gap-processes-0 (DIVERGENCE 651): erlang:processes/0 returns the TRUTHFUL live
%% pid list on zigvm (was undef — `.justified` in bif.tab, unreachable). The SHAPE
%% properties are byte-EQ vs OTP-30 (is_list, all-pids, self-in-list, >=2 procs);
%% the enumerated COUNT/pid-VALUES differ (OTP's per-node boot-set vs zigvm's live
%% table) — the disclosed residual that keeps the ledger row `.justified`.
%%   zigvm run zigvm_processes.beam t --code-path <stdlib+kernel ebin>
%%   erl -pa ... -eval 'io:format("~p~n",[zigvm_processes:t()]), init:stop().'
-module(zigvm_processes).
-export([t/0]).
t() ->
    %% spawn a couple of extra procs so the list is non-trivial on both VMs.
    _ = [ spawn(fun() -> receive stop -> ok end end) || _ <- [1, 2] ],
    Ps = erlang:processes(),
    {is_list, is_list(Ps),
     all_pids, lists:all(fun erlang:is_pid/1, Ps),
     self_in, lists:member(self(), Ps),
     ge2, length(Ps) >= 2}.
