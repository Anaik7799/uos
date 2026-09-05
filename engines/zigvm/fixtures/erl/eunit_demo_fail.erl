%% eunit_demo_fail — a tiny hand-written module with ONE deliberately failing
%% eunit case, used ONLY by the harness's own false-green mutant self-test
%% (E2.14 mutant (a): "runner swallows a failing case -> records EQ on a real
%% fail"). This fixture is a FIXTURE, not harness logic: it is real Erlang
%% that eunit really runs; the guard is that the OCaml side (harness/eunit.ml)
%% must classify its failing case as DIVERGENT/fail, never EQ.
-module(eunit_demo_fail).
-export([ok_thing/0]).

-include_lib("eunit/include/eunit.hrl").

ok_thing() -> ok.

ok_test() -> ok = ok_thing().
%% deliberately wrong: 1 =/= 2, so this test always fails.
broken_test() -> 1 = 2.
