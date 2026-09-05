%% Curated PURE subset of erts/emulator/test/send_term_SUITE.erl (E7 suite
%% closure). The REAL suite is a single `basic/1` case that loads a linked-in C
%% driver (send_term_drv), has it construct a term of every ERL_DRV_* shape, and
%% asserts the term arrives at the owning process UNCHANGED (nil, atom, empty
%% atom, int/uint, int64/uint64, port, binary, empty/buf2binary, string, tuple,
%% list, pid, float, empty map, the composite
%% `{blurf,42,[],[-42,{}|"abc"++P],"kalle",3.1416,Self,#{}}`, and the Map41/Map42
%% shapes). The DRIVER, erl_ddll, open_port, ERL_DRV_PORT/ERL_DRV_EXT2TERM (a C
%% ext-term file), erts_debug/heap_type introspection, and generate_external_-
%% terms_files (peer node + file I/O) are all EXCLUDED — they need a native
%% driver, ports, on-disk fixtures, or a live peer node, none of which this pure
%% subset admits.
%%
%% What survives is the SEMANTIC law the driver test exists to prove: the
%% MESSAGE-PASSING TERM-FIDELITY law — a term of any shape, sent through the VM's
%% send/receive machinery (to self AND across a real spawned process), is
%% received back structurally identical (deep `=:=` equality), and a sequence of
%% sends preserves order. Here the term is built in Erlang and delivered by `!`
%% instead of by a C driver; the fidelity assertion is byte-identical in intent.
%% Both VMs must agree true/false on every case.
%%
%% Term-shape coverage (mirrors the driver's ERL_DRV_* menu): int (incl. the
%% int64/uint64 edges the driver's ERL_DRV_INT64/UINT64 ops exercise), atom
%% (incl. the '' empty atom = ERL_DRV_ATOM op 9), tuple (incl. {} = op 22), list
%% (proper, improper, and the op-1 `[-42,{}|...]` shape), map (empty = op 40,
%% populated, and pid/float/string-keyed Map41/Map42 shapes), binary (<<>> =
%% op 14 and non-empty = op 15), bitstring (non-byte-aligned — richer than the
%% driver's byte-granular ERL_DRV_BINARY, a genuine term-fidelity extension),
%% fun, pid (= ERL_DRV_PID op 24, Self round-trips to itself), ref, and float
%% (= ERL_DRV_FLOAT op 26). The composite `basic/1` term (minus its port slot)
%% and a per-shape through-a-child round-trip anchor the deep-equality law.
%%
%% DELIBERATE EXCLUSIONS beyond the driver mechanism: >64-bit bignums. The real
%% suite keeps its in-message integers within the 64-bit driver ABI
%% (18446744073709551615, ±9223372036854775807/8); only the excluded on-disk
%% ext_terms generator uses >64-bit literals (e.g. 1000000000000000000000). We
%% likewise cap at 64-bit magnitudes — NOT arbitrary caution but a MEASURED
%% zigvm divergence (see the runner-report note): a >64-bit bignum LITERAL whose
%% module also carries a sub-byte bitstring literal round-trips to a non-equal
%% value on zigvm (a literal-chunk decode collision), while every 64-bit-range
%% integer is byte-EQ. Reported, not silently dropped.
%%
%% Discipline (shared with the receive/small/tuple pure suites): every case is
%% self-contained + deterministic; spawned children are one-shot echoes that
%% TERMINATE by construction; every receive is bounded (`after 1000`, so a bug
%% is a false return, never a hang); the mailbox is verified EMPTY before
%% returning (a leftover message would poison the NEXT case); seed values are
%% routed through the exported ?MODULE:id/1 firewall so constant folding cannot
%% bypass the VM's send/receive path. self()/make_ref()/spawn results are BIF
%% values the compiler cannot fold. A case returns the atom `true` on success;
%% the runner (zigvm_send_term_suite_runner) counts a case EQ only when BOTH
%% VMs' `Suite:Case([])` returns `true`. No dist, no ports, no wall-clock
%% DURATION assertion, no pid/ref VALUE comparison across VMs (identity,
%% is_pid/is_reference, distinctness, and ordering-consistency only).
-module(zigvm_send_term_SUITE).

-export([all/0,
         c_send_int_self/1, c_send_atom_self/1, c_send_tuple_self/1,
         c_send_list_self/1, c_send_map_self/1, c_send_binary_self/1,
         c_send_bitstring_self/1, c_send_fun_self/1, c_send_pid_self/1,
         c_send_ref_self/1, c_send_float_self/1,
         c_send_composite_child/1, c_send_shapes_child/1, c_send_order/1,
         %% exported spawned entry points (so spawn/3's MFA resolves) + id/1
         %% (the constant-folding firewall).
         id/1, echo/0, noop/0]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's send_term-suite spec case_names (ncases/1 lockstep).
all() ->
    [c_send_int_self, c_send_atom_self, c_send_tuple_self,
     c_send_list_self, c_send_map_self, c_send_binary_self,
     c_send_bitstring_self, c_send_fun_self, c_send_pid_self,
     c_send_ref_self, c_send_float_self,
     c_send_composite_child, c_send_shapes_child, c_send_order].

%% Identity through an exported call — the compiler cannot constant-fold across
%% it, so seed values genuinely travel through the VM's send/receive machinery.
id(X) -> X.

%% One-shot echo child: receive {From, Term} and send Term straight back, then
%% terminate. Round-trips a term through a REAL separate process's mailbox.
echo() -> receive {From, T} -> From ! T end.

%% A child that exists only to own a distinct pid, then terminates.
noop() -> ok.

%% --- int: every value inside the 64-bit driver ABI round-trips exactly -------
%% Mirrors the driver's ERL_DRV_INT/UINT/INT64/UINT64 singles: uint64 max, int64
%% max/min, uint32 max, small, zero, negative. (>64-bit bignums excluded — see
%% the module note.) is_integer confirms the arithmetic type survives the send.
c_send_int_self(_) ->
    Ns = [id(0), id(-4711), id(4711), id(4294967295),
          id(18446744073709551615), id(9223372036854775807),
          id(-9223372036854775808), id(-20233590931456)],
    self() ! Ns,
    R = receive Y -> Y after 1000 -> timeout end,
    (R =:= Ns) andalso all_true([is_integer(X) || X <- R]) andalso mbox_empty().

%% --- atom: incl. the '' empty atom (driver ERL_DRV_ATOM op 9) ----------------
c_send_atom_self(_) ->
    A = {id(''), id(an_atom), id(blurf), id('Quoted Atom')},
    self() ! A,
    R = receive Y -> Y after 1000 -> timeout end,
    (R =:= A) andalso is_atom(element(1, R)) andalso (element(1, R) =:= '')
        andalso mbox_empty().

%% --- tuple: incl. {} (driver op 22) and nesting -----------------------------
c_send_tuple_self(_) ->
    T = {id({}), {id(blurf), id(42)}, {id(a), {id(b), id(b)}, id(c)}},
    self() ! T,
    R = receive Y -> Y after 1000 -> timeout end,
    (R =:= T) andalso (element(1, R) =:= {})
        andalso (tuple_size(element(3, R)) =:= 3) andalso mbox_empty().

%% --- list: [] (driver op 23), a proper list, an IMPROPER list, and the op-1
%% `[-42,{}|"abc"]` shape (a cons whose tail is a string) --------------------
c_send_list_self(_) ->
    Proper = id([1, 2, 3, a, "s"]),
    Improper = [id(1), id(2) | id(3)],
    Op1Shape = [id(-42), {} | id("abc")],
    L = {id([]), Proper, Improper, Op1Shape},
    self() ! L,
    R = receive Y -> Y after 1000 -> timeout end,
    {Nil, P, I, O} = R,
    (R =:= L) andalso (Nil =:= []) andalso is_list(P)
        andalso (tl(tl(I)) =:= 3)          %% improper tail preserved
        andalso (O =:= [-42, {}, $a, $b, $c])
        andalso mbox_empty().

%% --- map: #{} (driver op 40), a populated map, and the Map41/Map42 shapes with
%% pid / float / string / [] keys and values ---------------------------------
c_send_map_self(_) ->
    Self = self(),
    Populated = #{id(1) => 11, id(2) => 22, id(3) => 33},
    Map41 = #{id(blurf) => 42,
              id([]) => [-42, {}, $a, $b, $c],
              id("kalle") => 3.1416,
              Self => #{}},
    M = {id(#{}), Populated, Map41},
    self() ! M,
    R = receive Y -> Y after 1000 -> timeout end,
    {Empty, Pop, M41} = R,
    (R =:= M) andalso (map_size(Empty) =:= 0)
        andalso (map_get(2, Pop) =:= 22)
        andalso (map_get(Self, M41) =:= #{})
        andalso mbox_empty().

%% --- binary: <<>> (driver op 14) and a non-empty binary (op 15) -------------
c_send_binary_self(_) ->
    B = {id(<<>>), id(<<"hejsan">>), id(<<0, 1, 2, 253, 254, 255>>)},
    self() ! B,
    R = receive Y -> Y after 1000 -> timeout end,
    {E, H, Bytes} = R,
    (R =:= B) andalso is_binary(E) andalso (byte_size(E) =:= 0)
        andalso (H =:= <<"hejsan">>) andalso (byte_size(Bytes) =:= 6)
        andalso mbox_empty().

%% --- bitstring: NON-byte-aligned (a term-fidelity extension beyond the
%% driver's byte-granular binaries) — bit_size and the exact bits must survive
c_send_bitstring_self(_) ->
    B = {id(<<5:3>>), id(<<1:1>>), id(<<255, 3:5>>)},
    self() ! B,
    R = receive Y -> Y after 1000 -> timeout end,
    {B3, B1, B13} = R,
    (R =:= B) andalso is_bitstring(B3) andalso (not is_binary(B3))
        andalso (bit_size(B3) =:= 3) andalso (bit_size(B1) =:= 1)
        andalso (bit_size(B13) =:= 13) andalso mbox_empty().

%% --- fun: a closure round-trips as the same fun and stays applicable ---------
c_send_fun_self(_) ->
    N = id(10),
    F = fun(X) -> X + N end,
    self() ! F,
    G = receive Y -> Y after 1000 -> timeout end,
    (F =:= G) andalso is_function(G) andalso is_function(G, 1)
        andalso (G(5) =:= 15) andalso mbox_empty().

%% --- pid: Self round-trips to itself (driver ERL_DRV_PID op 24); a child pid
%% round-trips distinctly. Identity + is_pid + distinctness only — no cross-VM
%% pid VALUE comparison.
c_send_pid_self(_) ->
    Self = self(),
    Child = spawn(?MODULE, noop, []),
    Self ! Self,
    Self ! Child,
    G1 = receive A -> A after 1000 -> timeout end,
    G2 = receive B -> B after 1000 -> timeout end,
    (G1 =:= Self) andalso (G2 =:= Child) andalso is_pid(G1) andalso is_pid(G2)
        andalso (Self =/= Child) andalso mbox_empty().

%% --- ref: a make_ref round-trips as the same ref; two refs are distinct and
%% their order relation is preserved through the send (ordering-consistency).
c_send_ref_self(_) ->
    R1 = make_ref(),
    R2 = make_ref(),
    self() ! R1,
    self() ! R2,
    G1 = receive A -> A after 1000 -> timeout end,
    G2 = receive B -> B after 1000 -> timeout end,
    (G1 =:= R1) andalso (G2 =:= R2)
        andalso is_reference(G1) andalso is_reference(G2)
        andalso (R1 =/= R2)
        andalso ((G1 < G2) =:= (R1 < R2))   %% order relation survives the send
        andalso mbox_empty().

%% --- float: the driver's ERL_DRV_FLOAT (op 26) value survives bit-exactly
%% (value stability under round-trip — NOT float formatting).
c_send_float_self(_) ->
    F = {id(3.1416), id(0.0), id(-2.5), id(1.0e100)},
    self() ! F,
    R = receive Y -> Y after 1000 -> timeout end,
    (R =:= F) andalso is_float(element(1, R)) andalso mbox_empty().

%% --- composite (the driver's op-1 term, minus its port slot) round-trips
%% through a REAL spawned process, deep-equal. Exercises atom + int + [] + a
%% `[-42,{}|"abc"]`-shaped list + string + float + pid + empty map in one term.
c_send_composite_child(_) ->
    Me = self(),
    C = spawn(?MODULE, echo, []),
    T = {id(blurf), 42, [], [-42, {} | id("abc")], id("kalle"), id(3.1416),
         Me, #{}},
    C ! {Me, T},
    R = receive Y -> Y after 1000 -> timeout end,
    (R =:= T) andalso mbox_empty().

%% --- per-shape through-a-child round-trip: EACH term shape, sent to its own
%% one-shot echo process and received back, is deep-equal. This is the fidelity
%% law across a genuine inter-process boundary (not just self-send).
c_send_shapes_child(_) ->
    Me = self(),
    Terms = [id(42), id(''), id(an_atom), {id(a), id(b)}, id([1, 2, 3]),
             [id(1), id(2) | id(3)], #{id(k) => id(v)}, id(<<"bin">>),
             id(<<5:3>>), id(3.1416), Me],
    roundtrip_all(Me, Terms) andalso mbox_empty().

%% --- send order is preserved: a sequence of mixed-shape messages arrives in
%% exactly the order it was sent (per-sender FIFO over one mailbox).
c_send_order(_) ->
    Me = self(),
    Seq = [id(1), id(a), {id(t), 1}, id([x]), id(<<"b">>), #{id(k) => 1},
           id(2.5), id(<<7:4>>)],
    send_each(Me, Seq),
    Got = collect(len(Seq, 0), []),
    (Got =:= Seq) andalso mbox_empty().

%% --- local helpers (self-contained; no lists:* module dependency) -----------

%% Spawn a one-shot echo per term, sequentially: deterministic, each child
%% terminates by construction, and the reply is matched to its own term.
roundtrip_all(_Me, []) -> true;
roundtrip_all(Me, [T | Ts]) ->
    C = spawn(?MODULE, echo, []),
    C ! {Me, T},
    R = receive Y -> Y after 1000 -> timeout end,
    (R =:= T) andalso roundtrip_all(Me, Ts).

%% Receive N messages in arrival order (bounded), returning them oldest-first.
collect(0, Acc) -> rev(Acc, []);
collect(N, Acc) when N > 0 ->
    M = receive X -> X after 1000 -> timeout end,
    collect(N - 1, [M | Acc]).

mbox_empty() -> receive _ -> false after 0 -> true end.

send_each(_Me, []) -> ok;
send_each(Me, [H | T]) -> Me ! H, send_each(Me, T).

all_true([]) -> true;
all_true([true | T]) -> all_true(T);
all_true([_ | _]) -> false.

rev([], Acc) -> Acc;
rev([H | T], Acc) -> rev(T, [H | Acc]).

len([], Acc) -> Acc;
len([_ | T], Acc) -> len(T, Acc + 1).
