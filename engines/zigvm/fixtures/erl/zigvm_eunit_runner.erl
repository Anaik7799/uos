%% zigvm_eunit_runner — the eunit-driver fixture (E2.14, --run-eunit harness
%% mode).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): this is an Erlang FIXTURE, not
%% harness logic. The OCaml harness (harness/eunit.ml) compiles it with the
%% pinned-or-host erlc and runs it on a VM's own `erl`/entry point:
%%
%%     erl -noshell -pa <ebin> -s zigvm_eunit_runner main <Module> -s init stop
%%
%% It calls `eunit:test/2` on the target `Module` with TWO listeners:
%%   - the built-in `eunit_tty` listener, muted via the `no_tty` option (eunit
%%     always runs it internally — it owns the final {result,...} handshake —
%%     but its human-readable, non-deterministic-timing prose must never reach
%%     our parser);
%%   - THIS module as an `eunit_listener` callback (`{report, {?MODULE, []}}`),
%%     which prints exactly one deterministic line per test case:
%%
%%         CASE <Mod>:<Func>/<Arity> <ok|fail>
%%
%%     and a single terminating summary line:
%%
%%         EUNIT_DONE pass=<N> fail=<N> skip=<N> cancel=<N>
%%
%%     No wall-clock time, no free-form text, ever appears in these lines —
%%     the OCaml side parses them with exact prefix matching (harness/eunit.ml
%%     parse_case_lines), so any non-deterministic byte here would be a
%%     silent-flake risk, which conformance rule 6 (measurement discipline)
%%     and rule 3 (UNTESTED visible, never silent) both forbid.
%%
%% A `{skipped,_}` or cancelled test is printed as `fail` here (never dropped)
%% — this fixture never distinguishes "didn't run" from "failed" in the CASE
%% stream; the summary line's skip/cancel counts carry that distinction for
%% anyone parsing the full picture.
%%
%% If the target module itself is missing/uncompilable, eunit reports that as
%% a *cancelled* top-level test (a `module_not_found` reason), which this
%% listener still turns into a `CASE ... fail` + `EUNIT_DONE ... cancel=1`
%% pair — never a bare crash, never a silently-empty stream.
-module(zigvm_eunit_runner).
-behaviour(eunit_listener).

-export([main/1]).
-export([start/0, start/1]).
-export([init/1, handle_begin/3, handle_end/3, handle_cancel/3, terminate/2]).

%% --- entry point -------------------------------------------------------

%% main([Module]) — Module arrives as an ATOM (erl -s passes -s args as
%% atoms), so both `-s zigvm_eunit_runner main mymod` and a list_to_atom'd
%% string are accepted defensively.
main([Module]) when is_atom(Module) ->
    run(Module);
main([Module]) when is_list(Module) ->
    run(list_to_atom(Module));
main(_) ->
    io:format("EUNIT_DONE error bad_args~n"),
    ok.

run(Module) ->
    try eunit:test(Module, [no_tty, {report, {?MODULE, []}}]) of
        _ -> ok
    catch
        Class:Reason ->
            %% eunit:test/2 itself raising (as opposed to a per-test failure,
            %% which the listener already prints) is a harness-visible event,
            %% never a silent drop.
            io:format("EUNIT_DONE error ~w:~w~n", [Class, Reason])
    end.

%% --- eunit_listener callbacks -------------------------------------------

start() -> start([]).
start(Options) -> eunit_listener:start(?MODULE, Options).

init(_Options) ->
    receive
        {start, _Reference} -> ok
    end.

handle_begin(_Kind, _Data, St) ->
    St.

handle_end(test, Data, St) ->
    Status = proplists:get_value(status, Data),
    Verdict = case Status of
                  ok -> "ok";
                  _ -> "fail"
              end,
    io:format("CASE ~s ~s~n", [test_name(Data), Verdict]),
    St;
handle_end(group, _Data, St) ->
    St.

handle_cancel(test, Data, St) ->
    io:format("CASE ~s fail~n", [test_name(Data)]),
    St;
handle_cancel(group, _Data, St) ->
    St.

terminate({ok, Data}, St) ->
    Pass = proplists:get_value(pass, Data, 0),
    Fail = proplists:get_value(fail, Data, 0),
    Skip = proplists:get_value(skip, Data, 0),
    Cancel = proplists:get_value(cancel, Data, 0),
    io:format("EUNIT_DONE pass=~w fail=~w skip=~w cancel=~w~n",
              [Pass, Fail, Skip, Cancel]),
    sync_end(ok, St);
terminate({error, Reason}, St) ->
    io:format("EUNIT_DONE error ~w~n", [Reason]),
    sync_end(error, St).

sync_end(Result, _St) ->
    receive
        {stop, Reference, ReplyTo} ->
            ReplyTo ! {result, Reference, Result},
            ok
    end.

test_name(Data) ->
    case proplists:get_value(source, Data) of
        {Mod, Func, Arity} -> io_lib:format("~w:~w/~w", [Mod, Func, Arity]);
        _ -> "unknown:unknown/0"
    end.
