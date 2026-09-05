%% zigvm_gen_statem_timer_diff — compiled differential proving gen_statem's
%% state_timeout AND event timeout FIRE (DIVERGENCE 730, the swap-x15 keystone).
%%
%% ROOT CAUSE (now fixed): zigvm lowered BEAM `swap A B` into three `move`s using
%% x15 as scratch, on the (false) assumption x15 is never live. gen_statem's
%% `loop_timeouts/16` is a 16-ARITY function whose 16th arg (TimeoutOpts, x15) is
%% `[]`; a `swap` right after `{move,nil,{x,15}}` clobbered x15, so
%% `erlang:start_timer(Time, self(), state_timeout, <garbage-atom>)` was called →
%% `badarg` (Options must be a list) → the gen_statem process SILENTLY died →
%% EVERY gen_statem state/event timer never fired. The fix is a true `.swap`
%% instruction (native temp, no register reuse).
%%
%% VALUE differential (not display-string): each statem sends its parent an atom
%% ONLY when its timer fires; the parent returns `no_fire` on timeout. A correct
%% VM returns `{gen_statem_timers, state, yes, event, yes}`; pre-fix zigvm
%% returned `...state, no_fire, event, no_fire` (both dead).
%%
%% Run on BOTH VMs (needs stdlib — single --code-path, retry on the autoload
%% heisenbug's FunctionNotExported):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_gen_statem_timer_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_gen_statem_timer_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_gen_statem_timer_diff.beam --code-path third_party/otp/lib/stdlib/ebin t 0
%% Byte-EQ verdict (both): {gen_statem_timers,state,yes,event,yes}
-module(zigvm_gen_statem_timer_diff).
-behaviour(gen_statem).
-export([t/1, init/1, callback_mode/0, waiting/3]).

t(_) ->
    Self = self(),
    S = one(Self, state_timeout),
    E = one(Self, timeout),
    erlang:display({gen_statem_timers, state, S, event, E}).

%% Start a statem that arms a 50ms timer of the given kind in init, then wait for
%% its `fired` message (a live value), or `no_fire` after 4s.
one(Parent, Kind) ->
    {ok, _Pid} = gen_statem:start(?MODULE, {Parent, Kind}, []),
    receive {statem_fired, Kind} -> yes after 4000 -> no_fire end.

init({Parent, Kind}) ->
    {ok, waiting, {Parent, Kind}, [{Kind, 50, go}]}.

callback_mode() -> state_functions.

waiting(Kind, go, {Parent, Kind} = Data) ->
    Parent ! {statem_fired, Kind},
    {keep_state, Data}.
