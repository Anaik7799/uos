%% zigvm_procinfo_keys2_diff — compiled differential for process_info/2 group_leader
%% + monitored_by (DIVERGENCE 736, the 735 follow-up). Both raised `badarg` on zigvm
%% (not in the accepted subset) where OTP returns a value. A valid item must RETURN,
%% not badarg (FM-OBS-1).
%%
%% VALUE differential: `group_leader` → a pid (EQUIV: the pid NUMBER is VM-run-
%% specific, so this asserts is_pid, not the exact pid). `monitored_by` → `[]` when no
%% one monitors the process (BYTE-EQ), else the WATCHER pids — asserted by membership
%% of the actual child pid (byte-EQ WITHIN a run: the returned watcher IS the child).
%%
%% Run on BOTH VMs (no stdlib needed):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_procinfo_keys2_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_procinfo_keys2_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_procinfo_keys2_diff.beam t 0
%% Byte-EQ verdict (both): {procinfo_keys2,gl_pid,true,mb0_empty,true,mb1_has_child,true}
-module(zigvm_procinfo_keys2_diff).
-export([t/1]).
t(_) ->
    {group_leader, GL} = erlang:process_info(self(), group_leader),
    {monitored_by, MB0} = erlang:process_info(self(), monitored_by),
    Self = self(),
    Child = spawn(fun() -> erlang:monitor(process, Self), Self ! ok, receive done -> ok end end),
    receive ok -> ok end,
    {monitored_by, MB1} = erlang:process_info(self(), monitored_by),
    Child ! done,
    erlang:display({procinfo_keys2, gl_pid, is_pid(GL), mb0_empty, MB0 =:= [],
                    mb1_has_child, lists:member(Child, MB1)}).
