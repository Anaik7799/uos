%% zigvm_trace_info_diff — gap-tracing-trace-info (DIVERGENCE 601).
%% The RUNTIME-CAPABILITY-EQUIVALENCE differential for erlang:trace_info/2 (the
%% FUNCTION-trace query form) + erlang:trace_delivered/1. Byte-IDENTICAL on zigvm
%% and pinned OTP-30. Traces an EXISTING function (foo/0) so {traced,_} is defined.
-module(zigvm_trace_info_diff).
-export([t/1, foo/0]).
foo() -> ok.
t(1) -> erlang:display({untraced, erlang:trace_info({zigvm_trace_info_diff,foo,0}, traced)}); % {traced,false}
t(2) -> erlang:display({td_ref, is_reference(erlang:trace_delivered(all))});                  % true
t(3) -> erlang:trace_pattern({zigvm_trace_info_diff,foo,0}, true, [global]),
        erlang:display({traced, erlang:trace_info({zigvm_trace_info_diff,foo,0}, traced)});   % {traced,global}
t(4) -> erlang:display({ms_untraced, erlang:trace_info({zigvm_trace_info_diff,foo,0}, match_spec)}); % {match_spec,false}
t(5) -> erlang:trace_pattern({zigvm_trace_info_diff,foo,0}, true, [global]),
        erlang:display({ms_traced, erlang:trace_info({zigvm_trace_info_diff,foo,0}, match_spec)}); % {match_spec,[]}
t(6) -> erlang:trace_pattern({zigvm_trace_info_diff,foo,0}, true, [global]),
        erlang:display({all, erlang:trace_info({zigvm_trace_info_diff,foo,0}, all)}). % full proplist
