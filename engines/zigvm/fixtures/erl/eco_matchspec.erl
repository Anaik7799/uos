%% eco_matchspec — a reduced ecosystem app exercising the MATCH-SPEC compile/run
%% surface zigvm genuinely hosts today (gap-erlang-cover-matchspec, DIVERGENCE 657).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): an Erlang FIXTURE, not harness
%% logic. Self-contained single module run as `zigvm run eco_matchspec.beam suite` —
%% no spawn, no --pa closure. Exercises the implemented match-spec BIF envelope
%% (src/bifs/bif_table.zig: ets:match_spec_compile/1, ets:match_spec_run_r/3,
%% ets:is_compiled_ms/1, erlang:match_spec_test/3) — the ETS/dbg select engine an
%% observability/query app hits.
%%
%% HONESTY BOUND: the COMPILED match-spec term is an OPAQUE, representation-coupled
%% handle (zigvm's `{'$zigvm_compiled_ms',_}` vs erts's internal binary) — it is
%% NEVER compared directly, only `is_compiled_ms/1` (a bool) and the RUN OUTPUT
%% (deterministic). `match_spec_run/2` is an ets.erl LIBRARY wrapper (undef on the
%% single-beam surface) — this fixture uses the `match_spec_run_r/3` BIF (results
%% accumulate onto Acc → reverse-of-input order, deterministic + byte-EQ). Stays
%% STRICTLY inside the observationally-EQ envelope — real EQ, never a masked gap.
-module(eco_matchspec).
-export([suite/0]).

run(Spec, In) -> ets:match_spec_run_r(In, ets:match_spec_compile(Spec), []).

suite() ->
    %% is_compiled_ms: a compiled MS is; a raw spec list / any term is NOT.
    C   = ets:match_spec_compile([{'$1', [], ['$1']}]),
    C1  = (ets:is_compiled_ms(C) =:= true),
    C2  = (ets:is_compiled_ms([{'$1', [], ['$1']}]) =:= false),
    C3  = (ets:is_compiled_ms(foo) =:= false) andalso (ets:is_compiled_ms(42) =:= false),

    %% match_spec_run_r: copy production ['$_'] over a tuple stream (reverse order).
    C4  = (run([{{'$1', '$2'}, [], ['$_']}], [{a, 1}, {b, 2}]) =:= [{b, 2}, {a, 1}]),
    %% key extraction '$1'.
    C5  = (run([{{'$1', '$2'}, [], ['$1']}], [{a, 1}, {b, 2}, {c, 3}]) =:= [c, b, a]),
    %% GUARD filter V > 1, then TRANSFORM to {K, V*10}.
    C6  = (run([{{'$1', '$2'}, [{'>', '$2', 1}], [{{'$1', {'*', '$2', 10}}}]}], [{a, 1}, {b, 2}, {c, 3}])
          =:= [{c, 30}, {b, 20}]),
    %% compound guard (andalso), and a full-term pattern '$1' copy.
    C7  = (run([{'$1', [{'andalso', {'>', {element, 2, '$1'}, 1}, {'<', {element, 2, '$1'}, 4}}], ['$1']}],
               [{a, 1}, {b, 2}, {c, 3}, {d, 5}]) =:= [{c, 3}, {b, 2}]),
    %% empty input → [].
    C8  = (run([{'$1', [], ['$1']}], []) =:= []),
    %% no clause matches → [].
    C9  = (run([{{a, '$1'}, [], ['$1']}], [{b, 1}, {c, 2}]) =:= []),

    %% erlang:match_spec_test/3: a MATCH yields {ok, Production, [], []}; a
    %% guard-reject yields {ok, false, [], []}.
    MS  = [{{'$1', '$2'}, [{'>', '$2', 1}], [{{'$1', '$2'}}]}],
    C10 = (erlang:match_spec_test({b, 2}, MS, table) =:= {ok, {b, 2}, [], []}),
    C11 = (erlang:match_spec_test({a, 1}, MS, table) =:= {ok, false, [], []}),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11
    of
        true -> ok;
        false -> fail
    end.
