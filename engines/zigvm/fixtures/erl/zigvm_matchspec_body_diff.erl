%% Durable differential oracle for src/eval.zig (the shared expression kernel).
%% Runs the ETS match-spec BODY grammar through the live engine; the captured
%% answers are mirrored byte-for-byte in eval.zig's "LAW eval-differential".
%% Subject is the pair {10,3} so $1=10, $2=3.
-module(zigvm_matchspec_body_diff).
-export([t/1]).

run(Body) ->
    MS = [{{'$1','$2'}, [], [Body]}],
    C = ets:match_spec_compile(MS),
    ets:match_spec_run([{10,3}], C).

t(_) ->
    io:format("plus     ~p~n", [run({'+','$1','$2'})]),
    io:format("minus    ~p~n", [run({'-','$1','$2'})]),
    io:format("times    ~p~n", [run({'*','$1','$2'})]),
    io:format("gt       ~p~n", [run({'>','$1','$2'})]),
    io:format("eqexact  ~p~n", [run({'=:=','$1','$1'})]),
    io:format("element  ~p~n", [run({element,1,{{'$1','$2'}}})]),
    io:format("tuple2   ~p~n", [run({{'$2','$1'}})]),
    io:format("const    ~p~n", [run({const,{a,b}})]),
    ok.
