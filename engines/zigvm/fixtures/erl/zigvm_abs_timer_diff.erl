%% zigvm_abs_timer_diff — compiled differential for an ABSOLUTE-time erlang timer
%% (DIVERGENCE 729). `erlang:start_timer(AbsMs, self(), Msg, [{abs,true}])` arms a
%% timer whose `time` is an ABSOLUTE monotonic-millisecond deadline, not a relative
%% delay. zigvm armed it as `self.vclock + AbsMs` (treating the ~1e9 absolute value
%% as a relative offset) so it landed ~1e9 vclock-ticks out and NEVER fired before
%% any real relative timer — every `{abs,true}` timer silently timed out. The fix
%% translates the absolute deadline into vclock space (`vclock + (AbsMs - now_ms)`).
%%
%% This is a VALUE differential (not display-string): the receive returns the atom
%% `fired` iff the abs timer's {timeout,Ref,Msg} message actually arrives, `no_fire`
%% otherwise. Deadline is only ~80ms out, well under the 5s receive guard, so a
%% correct VM ALWAYS returns fired; the pre-fix zigvm ALWAYS returned no_fire.
%%
%% Run on BOTH VMs (no stdlib needed — all built-in BIFs):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_abs_timer_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_abs_timer_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_abs_timer_diff.beam t 0
%% Byte-EQ verdict (both): {abs_timer,fired}
-module(zigvm_abs_timer_diff).
-export([t/1]).
t(_) ->
    Now = erlang:monotonic_time(millisecond),
    Ref = erlang:start_timer(Now + 80, self(), soon, [{abs, true}]),
    R = receive
            {timeout, Ref, soon} -> fired
        after 5000 -> no_fire
        end,
    erlang:display({abs_timer, R}).
