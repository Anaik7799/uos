%% eco_parse — a reduced ecosystem app exercising the Erlang TOKENIZER + PARSER
%% closure (erl_scan + erl_parse + erl_features + epp + eval_bits) zigvm now
%% hosts via the preloaded stock stdlib + the native init:get_arguments/0
%% (gap-hof-parse, DIVERGENCE 673). All are Erlang code — undef before this slice.
%%
%% Run as `zigvm run eco_parse.beam suite`. HONESTY BOUNDS: asserts only
%% deterministic tokenizer output (token categories) and parse+normalise of TERM
%% LITERALS (ints/floats/atoms/tuples/lists/maps/binaries/strings) — the AST
%% forms carry anno line numbers (deterministic here, both start at line 1) but
%% we mostly normalise back to plain terms so the comparison is representation-free.
-module(eco_parse).
-export([suite/0]).

tok(Str) -> {ok, Toks, _} = erl_scan:string(Str), Toks.
pterm(Str) -> {ok, [Form]} = erl_parse:parse_exprs(tok(Str)), erl_parse:normalise(Form).

suite() ->
    %% erl_scan — token category sequences.
    C1  = ([element(1, T) || T <- tok("1 + 2 * 3.")] =:= [integer, '+', integer, '*', integer, dot]),
    C2  = ([element(1, T) || T <- tok("foo(X) when X > 0 -> ok.")]
               =:= [atom, '(', var, ')', 'when', var, '>', integer, '->', atom, dot]),
    C3  = (erl_scan:symbol(hd(tok("hello."))) =:= hello),
    C4  = (erl_scan:category(hd(tok("42."))) =:= integer),

    %% erl_parse — parse_exprs + normalise on term literals.
    C5  = (pterm("42.") =:= 42),
    C6  = (pterm("3.14.") =:= 3.14),
    C7  = (pterm("ok.") =:= ok),
    C8  = (pterm("{ok, [1, 2, 3], <<\"hi\">>}.") =:= {ok, [1, 2, 3], <<"hi">>}),
    C9  = (pterm("#{a => 1, b => 2}.") =:= #{a => 1, b => 2}),
    C10 = (pterm("[{name, \"bob\"}, {age, 42}].") =:= [{name, "bob"}, {age, 42}]),
    C11 = (pterm("\"a string\".") =:= "a string"),

    %% erl_parse:abstract — term -> AST -> term round-trip.
    C12 = (erl_parse:normalise(erl_parse:abstract([1, {a, b}, <<"x">>])) =:= [1, {a, b}, <<"x">>]),
    C13 = (erl_parse:normalise(erl_parse:abstract(#{k => [1, 2], v => <<1, 2, 3>>})) =:= #{k => [1, 2], v => <<1, 2, 3>>}),

    %% erl_parse:parse_form — an attribute form.
    {ok, Form} = erl_parse:parse_form(tok("-module(foo).")),
    C14 = (element(1, Form) =:= attribute),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14
    of
        true -> ok;
        false -> fail
    end.
