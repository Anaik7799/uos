%% zigvm_fun_print_diff — compiled differential for the local-closure print shape
%% (DIVERGENCE 740). erts `erts_print_fun` renders a LOCAL closure as
%% `#Fun<Module.Index.OldUniq>` (module NAME + the FunT Index + OldUniq). zigvm
%% used to print the codebase `#Fun<Label.Arity>` convention (the disclosed 728
%% funmeta follow-up), so `~p`/`~w` of any anonymous fun — crash reports, logger
%% output, `io:format` debugging — diverged.
%%
%% VALUE differential (the exact rendered string + its length — printable ASCII,
%% no control chars, so display is faithful): both VMs load the SAME .beam FunT,
%% so Module/Index/OldUniq are identical → byte-EQ.
%%
%% Run on BOTH VMs (needs stdlib for io_lib):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_fun_print_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_fun_print_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run --code-path <stdlib ebin> OUT/zigvm_fun_print_diff.beam t 0
%% Byte-EQ verdict (both): {fun_print,anon,"#Fun<zigvm_fun_print_diff.0.<uniq>>",<len>,extfun,"fun lists:sum/1"}
-module(zigvm_fun_print_diff).
-export([t/1]).

t(_) ->
    Anon = fun(X) -> X + 1 end,
    Ext = fun lists:sum/1,
    AnonS = lists:flatten(io_lib:format("~p", [Anon])),
    ExtS = lists:flatten(io_lib:format("~p", [Ext])),
    erlang:display({fun_print, anon, AnonS, length(AnonS), extfun, ExtS}).
