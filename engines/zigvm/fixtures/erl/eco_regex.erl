%% eco_regex — a reduced ecosystem app exercising the `re` regexp module. The
%% native re: BIFs (re:run/2,3, re:compile) are already implemented (src/
%% re_engine.zig); this fixture proves the re.erl WRAPPER functions
%% (re:replace/split) — Erlang code that calls the native BIFs — now resolve via
%% the preloaded stock stdlib (gap-hof-re, DIVERGENCE 667).
%%
%% Run as `zigvm run eco_regex.beam suite`. HONESTY BOUNDS: never compares the
%% OPAQUE compiled-regex mp() term (only uses it in a run); every assertion
%% compares a deterministic match tuple / flat string / string list.
-module(eco_regex).
-export([suite/0]).

suite() ->
    %% native re:run — capture, nomatch, all-captures.
    C1 = (re:run("hello123world", "[0-9]+", [{capture, first, list}]) =:= {match, ["123"]}),
    C2 = (re:run("abc", "x", []) =:= nomatch),
    C3 = (re:run("a1b2c3", "[0-9]", [global, {capture, first, list}]) =:= {match, [["1"], ["2"], ["3"]]}),

    %% re.erl WRAPPERS (need re.beam): replace + split.
    C4 = (re:replace("a-b-c", "-", "_", [global, {return, list}]) =:= "a_b_c"),
    C5 = (re:replace("a-b-c", "-", "_", [{return, list}]) =:= "a_b-c"),
    C6 = (re:replace("x1y2z", "[0-9]", "#", [global, {return, binary}]) =:= <<"x#y#z">>),
    C7 = (re:split("a,b,c,d", ",", [{return, list}]) =:= ["a", "b", "c", "d"]),
    C8 = (re:split("a1b2c", "[0-9]", [{return, list}]) =:= ["a", "b", "c"]),
    C9 = (re:split("nodigits", "[0-9]", [{return, list}]) =:= ["nodigits"]),

    %% compile then run the compiled mp (opaque term used, never compared).
    {ok, MP} = re:compile("[a-z]+"),
    C10 = (re:run("HELLO world", MP, [{capture, first, list}]) =:= {match, ["world"]}),

    %% anchors / groups.
    C11 = (re:run("2026-07-30", "([0-9]+)-([0-9]+)-([0-9]+)", [{capture, all_but_first, list}]) =:= {match, ["2026", "07", "30"]}),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11
    of
        true -> ok;
        false -> fail
    end.
