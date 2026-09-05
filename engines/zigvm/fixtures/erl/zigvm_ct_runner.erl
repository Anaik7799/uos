%% zigvm_ct_runner -- Common Test fixture for harness/ct_runner.ml.
%%
%% This is an Erlang fixture, not harness logic. The OCaml harness compiles it
%% with a selected SUITE, then invokes case_n(Label, Idx) on the oracle and
%% attempts the same entry point on zigvm. The return value is intentionally the
%% smallest printable observation: 1 if common_test reports exactly one passing
%% case and no failures/skips; 0 if CT ran and the case did not pass; 2 if CT
%% itself could not run. The OCaml side parses only 0|1, so 2 remains UNTESTED.
-module(zigvm_ct_runner).

-export([case_n/2, ncases/2]).

suite(pure) -> zigvm_pure_SUITE;
suite(e4) -> zigvm_e4_SUITE.

ncases(Label, _Ignored) ->
    S = suite(Label),
    len(S:all(), 0).

case_n(Label, Idx) ->
    S = suite(Label),
    Case = nth(Idx, S:all()),
    LogDir = logdir(Label, Case),
    case ensure_dir(LogDir) of
        ok ->
            case catch ct:run_test([{suite, suite_path(S)},
                                    {testcase, Case},
                                    {auto_compile, false},
                                    {logdir, LogDir}]) of
                {'EXIT', _} -> 2;
                Result -> result_to_int(Result)
            end;
        _ ->
            0
    end.

suite_path(Suite) ->
    case code:which(Suite) of
        non_existing -> atom_to_list(Suite) ++ ".beam";
        Path -> Path
    end.

logdir(Label, Case) ->
    "/tmp/zigvm-ct-" ++ atom_to_list(Label) ++ "-" ++ atom_to_list(Case) ++ "-" ++
        integer_to_list(erlang:unique_integer([positive])).

ensure_dir(Dir) ->
    case filelib:ensure_dir(Dir ++ "/dummy") of
        ok ->
            case file:make_dir(Dir) of
                ok -> ok;
                {error, eexist} -> ok;
                Error -> Error
            end;
        Error -> Error
    end.

result_to_int({Ok, 0, {0, 0}}) when is_integer(Ok), Ok > 0 -> 1;
result_to_int({_Ok, _Failed, {_UserSkipped, _AutoSkipped}}) -> 0;
result_to_int(_) -> 2.

nth(1, [X | _]) -> X;
nth(N, [_ | T]) when N > 1 -> nth(N - 1, T).

len([], Acc) -> Acc;
len([_ | T], Acc) -> len(T, Acc + 1).
