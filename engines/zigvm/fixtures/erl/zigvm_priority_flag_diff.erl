%% zigvm_priority_flag_diff — gap-eep76-priority-flag (DIVERGENCE 602).
%% The RUNTIME-CAPABILITY-EQUIVALENCE differential for the process SCHEDULING
%% priority surface + the EEP-76 feature-off contract, byte-EQ vs pinned OTP-30.
%% process_flag(priority, Level) returns the OLD priority (default normal). The
%% EEP-76 priority_messages flag is REJECTED on the rc (feature off) — that
%% rejection is itself the oracle-differentiable contract.
-module(zigvm_priority_flag_diff).
-export([t/1]).
c(F) -> try F() catch error:badarg -> caught_badarg end.
t(1) -> erlang:display({set_high, process_flag(priority, high)});   % old -> normal
t(2) -> process_flag(priority, high),
        erlang:display({roundtrip, process_flag(priority, low)});   % old -> high
t(3) -> erlang:display({bad_level, c(fun() -> process_flag(priority, bogus) end)}); % caught_badarg
t(4) -> erlang:display({prio_msgs, c(fun() -> process_flag(priority_messages, true) end)}); % caught_badarg (rc: off)
t(5) -> erlang:display({send_prio, erlang:send(self(), hi, [priority])}). % ok (accepted, normal delivery)
