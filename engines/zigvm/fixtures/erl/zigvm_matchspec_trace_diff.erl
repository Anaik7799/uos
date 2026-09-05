%% Durable end-to-end differential for the trace-body ACTION wiring
%% (DIVERGENCE 633). erlang:match_spec_test(ArgList, MS, trace) must be byte-EQ
%% on zigvm and pinned OTP-30. Run: `zigvm run zigvm_matchspec_trace_diff.beam t 0`.
-module(zigvm_matchspec_trace_diff).
-export([t/1]).
tr(MS) -> erlang:match_spec_test([10,3], MS, trace).
t(_) ->
    erlang:display({plain,  tr([{['$1','$2'],[],[{'+','$1','$2'}]}])}),
    erlang:display({msg,    tr([{['$1','$2'],[],[{message,{'+','$1','$2'}}]}])}),
    erlang:display({msgf,   tr([{['$1','$2'],[],[{message,false}]}])}),
    erlang:display({ret,    tr([{['$1','$2'],[],[{return_trace}]}])}),
    erlang:display({bothf,  tr([{['$1','$2'],[],[{return_trace},{exception_trace}]}])}),
    erlang:display({multi,  tr([{['$1','$2'],[],[{message,'$2'},{return_trace}]}])}),
    erlang:display({gfail,  tr([{['$1','$2'],[{'>','$1',100}],[true]}])}),
    erlang:display({nomat,  tr([{[a,b],[],[true]}])}),
    ok.
