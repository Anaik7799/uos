%% Durable differential for gap-procinfo-initial-call (DIVERGENCE 754).
%%
%% `process_info(Pid, initial_call)` = `{initial_call, {M, F, length(Args)}}` — the
%% spawn MFA recorded at BIRTH (proc.zig resolveSpawnMFA) — must be byte-EQ vs pinned
%% OTP-30's PCB `initial_call`. Verified BY VALUE (`=:=`, not a display string alone):
%% the `Match` element is `true` on both VMs. Run `run <beam> t 1` on zigvm AND
%% `erl -eval 'zigvm_procinfo_initial_call_diff:t(1), init:stop().'` on the oracle;
%% the two lines must be byte-identical.
-module(zigvm_procinfo_initial_call_diff).
-export([t/1, loop/0, loop1/1]).

loop() -> receive stop -> ok end.
loop1(_) -> receive stop -> ok end.

t(_) ->
    %% arity 0 spawn
    P0 = spawn(?MODULE, loop, []),
    {initial_call, IC0} = process_info(P0, initial_call),
    P0 ! stop,
    %% arity 1 spawn — proves the arity is EXACT, not a constant
    P1 = spawn(?MODULE, loop1, [arg]),
    {initial_call, IC1} = process_info(P1, initial_call),
    P1 ! stop,
    Match = (IC0 =:= {?MODULE, loop, 0}) andalso (IC1 =:= {?MODULE, loop1, 1}),
    io:format("~w~n", [{procinfo_initial_call, IC0, IC1, Match}]).
