%% eco_anno — a reduced ecosystem app exercising the `erl_anno` parser-annotation
%% module zigvm now hosts via the preloaded stock stdlib (gap-hof-anno,
%% DIVERGENCE 672). Self-contained Erlang code — undef before this slice.
%%
%% Run as `zigvm run eco_anno.beam suite`. HONESTY BOUNDS: never compares the raw
%% anno term (its representation — a bare integer for the compact location form,
%% or a keyword list — is impl-detail); only the ACCESSOR observations
%% (line/column/location/text/generated + is_anno) are asserted, all deterministic.
-module(eco_anno).
-export([suite/0]).

suite() ->
    A = erl_anno:new(42),
    C1  = (erl_anno:line(A) =:= 42),
    C2  = (erl_anno:location(A) =:= 42),
    C3  = (erl_anno:is_anno(A)) andalso (not erl_anno:is_anno(foo)) andalso (not erl_anno:is_anno({a, b, c})),
    A2  = erl_anno:set_line(99, A),
    C4  = (erl_anno:line(A2) =:= 99),
    AC  = erl_anno:new({5, 10}),
    C5  = (erl_anno:line(AC) =:= 5),
    C6  = (erl_anno:column(AC) =:= 10),
    C7  = (erl_anno:location(AC) =:= {5, 10}),
    C8  = (erl_anno:column(A) =:= undefined),
    AT  = erl_anno:set_text("hello", A),
    C9  = (erl_anno:text(AT) =:= "hello"),
    C10 = (erl_anno:text(A) =:= undefined),
    AG  = erl_anno:set_generated(true, A),
    C11 = (erl_anno:generated(AG) =:= true) andalso (erl_anno:generated(A) =:= false),
    A3  = erl_anno:set_location({7, 3}, A),
    C12 = (erl_anno:location(A3) =:= {7, 3}) andalso (erl_anno:line(A3) =:= 7) andalso (erl_anno:column(A3) =:= 3),
    C13 = (erl_anno:to_term(A) =:= erl_anno:to_term(erl_anno:from_term(erl_anno:to_term(A)))),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
    of
        true -> ok;
        false -> fail
    end.
