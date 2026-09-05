%% zigvm_term_print_totality_diff — compiled differential for ~w/~p totality over
%% pid/ref/port/fun (DIVERGENCE 728). Was the CRASH-AMPLIFIER: io_lib:format of any
%% term carrying a pid/ref/fun raised badarg and killed the printing process. The
%% pid/ref NUMBERS are VM-run-specific (EQUIV) so this asserts SURVIVAL + the byte-EQ
%% SHAPE STRUCTURE (the ASCII markers), not the raw numeric bytes.
%%
%% Run on BOTH VMs (needs stdlib for io_lib/string — single --code-path, retry on the
%% autoload heisenbug's FunctionNotExported):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_term_print_totality_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_term_print_totality_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/...beam --code-path third_party/otp/lib/stdlib/ebin t 0
%% Byte-EQ verdict (both): {survived,true,haspid,true,hasref,true,hasfun,true,p_pid,true}
-module(zigvm_term_print_totality_diff).
-export([t/1]).
t(_) ->
    F = fun(X) -> X + 1 end,
    W = lists:flatten(io_lib:format("~w", [{self(), make_ref(), F}])),
    P = lists:flatten(io_lib:format("~p", [self()])),
    Has = fun(S, Sub) -> case string:find(S, Sub) of nomatch -> false; _ -> true end end,
    erlang:display({survived, true,
                    haspid, Has(W, "<0."), hasref, Has(W, "#Ref<0."), hasfun, Has(W, "#Fun<"),
                    p_pid, Has(P, "<0.")}).
