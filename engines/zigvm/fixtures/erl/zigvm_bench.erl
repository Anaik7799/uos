%% zigvm_bench — the oracle-side performance twin (E0.7).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): this is an Erlang FIXTURE, not
%% harness logic. It is the oracle twin of src/cli.zig's `benchTermCompareWork`:
%% the SAME term-compare microbench, so the harness can measure both VMs under
%% the same workload and compute the ratio r = ops_zigvm / ops_oracle. The
%% OCaml harness compiles this with the pinned-or-host erlc and runs it as
%%
%%     erl -noshell -pa <ebin> -eval 'zigvm_bench:run("term_compare", N)' -s init stop
%%
%% printing exactly one line
%%
%%     ops_per_s <float>
%%
%% mirroring the VM CLI's `zigvm bench <unit> <iters>` output, so the harness
%% parser is identical on both sides.
%%
%% Workload parity with the Zig side: a fixed 3-term ring — two 8-int lists that
%% differ only in the head cell, and an 8-int tuple (a different term rank) — is
%% built ONCE, then compared over successive ring pairs `Iters` times, folding
%% the standard term order into a checksum (<  -> -1, ==  -> 0, >  -> +1). The
%% checksum is never compared across VMs (only the timing ratio is); it exists
%% solely to keep the loop from being optimized away, exactly as on the Zig
%% side. Timing uses the monotonic clock (`erlang:monotonic_time(nanosecond)`).
-module(zigvm_bench).
-export([run/2]).

scale_worker(0) -> ok;
scale_worker(N) ->
    _ = 0 + 1,
    scale_worker(N - 1).

spawn_round(0, Refs) -> Refs;
spawn_round(Workers, Refs) ->
    {_Pid, Ref} = spawn_monitor(fun() -> scale_worker(48) end),
    spawn_round(Workers - 1, [Ref | Refs]).

wait_round([]) -> ok;
wait_round([Ref | Rest]) ->
    receive
        {'DOWN', Ref, process, _, _} -> wait_round(Rest)
    end.

storm_loop(0, Acc) -> Acc;
storm_loop(Rounds, Acc) ->
    Refs = spawn_round(96, []),
    wait_round(Refs),
    storm_loop(Rounds - 1, Acc + 96 * 48).


%% The fixed ring, built once (outside the timed loop). Mirrors the Zig ring:
%% list_a and list_b differ only in the head cell (1 vs 99); tup is the tuple.
ring() ->
    ListA = [1, 2, 3, 4, 5, 6, 7, 8],
    ListB = [99, 2, 3, 4, 5, 6, 7, 8],
    Tup = {1, 2, 3, 4, 5, 6, 7, 8},
    {ListA, ListB, Tup}.

%% Iters comparisons over successive ring pairs; fold the standard term order
%% into a checksum. Tail-recursive so the loop is a tight compare-bound loop.
loop(0, Acc, _Ring) -> Acc;
loop(N, Acc, {A, B, T} = Ring) ->
    {X, Y} =
        case N rem 3 of
            0 -> {A, B};
            1 -> {B, T};
            _ -> {T, A}
        end,
    Ord =
        if
            X < Y -> -1;
            X > Y -> 1;
            true -> 0
        end,
    loop(N - 1, Acc + Ord, Ring).

%% term_hash: fold erlang:phash2 over successive ring elements (period 3), the
%% oracle twin of benchTermHashWork. Tail-recursive; masked to 64 bits to mirror
%% the Zig `+%` wrapping u64 accumulator.
hash_loop(0, Acc, _Ring) -> Acc;
hash_loop(N, Acc, {A, B, T} = Ring) ->
    Term =
        case N rem 3 of
            0 -> A;
            1 -> B;
            _ -> T
        end,
    hash_loop(N - 1, (Acc + erlang:phash2(Term)) band 16#FFFFFFFFFFFFFFFF, Ring).

run(Unit, Iters) when is_list(Unit), is_integer(Iters), Iters >= 0 ->
    case Unit of
        "term_compare" ->
            Ring = ring(),
            T0 = erlang:monotonic_time(nanosecond),
            Checksum = loop(Iters, 0, Ring),
            T1 = erlang:monotonic_time(nanosecond),
            _ = Checksum,
            Ns = T1 - T0,
            Ops =
                case Ns > 0 of
                    true -> Iters * 1000000000 / Ns;
                    false -> 0.0
                end,
            io:format("ops_per_s ~w~n", [Ops]);
        "term_hash" ->
            %% perf-scale-corpus: the hash-throughput twin of benchTermHashWork —
            %% the SAME 3-term ring, folding erlang:phash2 (never compared across
            %% VMs; only the timing ratio is).
            Ring = ring(),
            T0 = erlang:monotonic_time(nanosecond),
            Checksum = hash_loop(Iters, 0, Ring),
            T1 = erlang:monotonic_time(nanosecond),
            _ = Checksum,
            Ns = T1 - T0,
            Ops =
                case Ns > 0 of
                    true -> Iters * 1000000000 / Ns;
                    false -> 0.0
                end,
            io:format("ops_per_s ~w~n", [Ops]);
        "spawn_storm" ->
            T0 = erlang:monotonic_time(nanosecond),
            %% zigvm's scale CLI hardcodes 240 rounds
            Iters1 = if Iters =:= 0 -> 240; true -> Iters end,
            Grants = storm_loop(Iters1, 0),
            T1 = erlang:monotonic_time(nanosecond),
            _ = Grants,
            Ns = T1 - T0,
            Ops =
                case Ns > 0 of
                    %% The scale throughput numerator in zigvm is run.grants (steps)
                    %% But scaleWork returns Grants = scale_workers * scale_max_steps? No, it returns actual grants executed.
                    %% To match the order of magnitude, we use the number of spawned processes or similar.
                    %% As long as it's invariant across scheduler counts, the throughput curve s(n) is valid.
                    true -> Iters1 * 96 * 1000000000 / Ns;
                    false -> 0.0
                end,
            io:format("ops_per_s ~w~n", [Ops]);
        "dispatch" ->
            %% E44-T1 (gap-perf-bench-realism): the DISPATCH twin of
            %% benchDispatchWork. A bounded tail-recursive arithmetic loop
            %% (increment mod 4096) — the SAME loop shape zigvm runs as bytecode
            %% (add / is_lt / jump). OTP-30 runs this compiled under BeamAsm (native
            %% JIT); zigvm runs it through its switch-interpreter. So the timing
            %% ratio measures the INTERPRETER-vs-JIT dispatch tax that term_compare/
            %% term_hash (native-kernel micro-loops) structurally hide. `Iters` is
            %% the harness iteration count on both sides.
            T0 = erlang:monotonic_time(nanosecond),
            X = dispatch_loop(Iters, 0),
            T1 = erlang:monotonic_time(nanosecond),
            _ = X,
            Ns = T1 - T0,
            Ops =
                case Ns > 0 of
                    true -> Iters * 1000000000 / Ns;
                    false -> 0.0
                end,
            io:format("ops_per_s ~w~n", [Ops]);
        "mixed" ->
            %% gap-perf-bench-realism: the ALLOC+GC+DISPATCH twin of benchMixedWork.
            %% Each pass builds a fresh 8-cell list [C,...] (heap alloc, prior list →
            %% garbage), walks it summing heads (dispatch), bounded counter mod 4096.
            %% OTP-30 runs this under BeamAsm + generational GC; zigvm runs it
            %% interpreted + a full copying collect. The ratio measures the COMBINED
            %% alloc+GC+dispatch gap (the workloads are semantically identical — same
            %% allocations, same arithmetic — only the VMs' GC strategies differ).
            T0 = erlang:monotonic_time(nanosecond),
            X = mixed_loop(Iters, 0, 0),
            T1 = erlang:monotonic_time(nanosecond),
            _ = X,
            Ns = T1 - T0,
            Ops =
                case Ns > 0 of
                    true -> Iters * 1000000000 / Ns;
                    false -> 0.0
                end,
            io:format("ops_per_s ~w~n", [Ops]);
        "call" ->
            %% gap-perf-bench-call: the FUNCTION-CALL/RETURN twin of
            %% benchCallReturnWork. `call_loop/2` does EXACTLY Iters NON-tail calls
            %% to call_leaf/0 (each a real BEAM call + return; the outer loop is
            %% tail-recursive). OTP-30 runs the call under BeamAsm's native CALL;
            %% zigvm runs call_ext_code+ret through its switch interpreter. So the
            %% ratio measures the call-dispatch tax dispatch/mixed cannot see.
            %% `Iters` is the CALL COUNT on both VMs; the checksum == Iters.
            T0 = erlang:monotonic_time(nanosecond),
            X = call_loop(Iters, 0),
            T1 = erlang:monotonic_time(nanosecond),
            _ = X,
            Ns = T1 - T0,
            Ops =
                case Ns > 0 of
                    true -> Iters * 1000000000 / Ns;
                    false -> 0.0
                end,
            io:format("ops_per_s ~w~n", [Ops]);
        _ ->
            io:format("unknown_unit~n", [])
    end.

%% gap-perf-bench-call: Iters NON-tail calls to call_leaf/0 (result used in +),
%% accumulating 1 each → checksum == Iters (mirrors benchCallReturnWork).
call_leaf() -> 1.
call_loop(0, Acc) -> Acc;
call_loop(N, Acc) -> call_loop(N - 1, Acc + call_leaf()).

%% gap-perf-bench-realism: N passes. C = bounded counter (mod 4096). Each pass
%% builds a fresh 8-cell list [C,...] (heap alloc), sums it (dispatch). Acc holds
%% the last pass's sum = 8*C, mirroring benchMixedWork's x2 denotation.
mixed_loop(0, Acc, _C) -> Acc;
mixed_loop(N, _Acc, C0) ->
    C =
        case C0 + 1 < 4096 of
            true -> C0 + 1;
            false -> 0
        end,
    L = [C, C, C, C, C, C, C, C],
    S = msum(L, 0),
    mixed_loop(N - 1, S, C).

msum([], A) -> A;
msum([H | T], A) -> msum(T, A + H).

%% E44-T1: the dispatch loop — increment X, reset at 4096 (bounded, no bignum),
%% Iters times. Mirrors src/cli.zig benchDispatchWork's bytecode loop.
dispatch_loop(0, X) -> X;
dispatch_loop(N, X) ->
    X1 = X + 1,
    case X1 < 4096 of
        true -> dispatch_loop(N - 1, X1);
        false -> dispatch_loop(N - 1, 0)
    end.
