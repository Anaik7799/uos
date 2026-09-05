%% zigvm_pure_SUITE — a PURE subset of erts/emulator/test behaviours, in the
%% common_test SUITE shape (`all/0` + `Case(Config)` funs) but with NO
%% common_test / test_server dependency (CT-on-zigvm is Epoch E7; the real
%% erts/emulator/test suites `-include_lib("common_test/include/ct.hrl")` and
%% call `test_server`/`ct` at runtime, so they are UNTESTED(needs-ct -> E7) for
%% this driver — see OTP30_E3_PLAN.md Task 19 Step 2).
%%
%% Every case exercises ONLY functionality the zigvm interpreter genuinely
%% supports end-to-end from a compiled `.beam` today (E0–E3): integer/bignum
%% arithmetic (num_bif_SUITE-class), list construction/recursion, tuples, maps
%% (map_SUITE-class), binaries + bit-syntax construction<->matching round-trips
%% (bs_construct_SUITE / bs_match_SUITE-class), exact/loose term comparison &
%% ordering (term_SUITE-class), guards, try/catch class discrimination
%% (exception_SUITE-class), and funs/closures (fun_SUITE-class). A case returns
%% the atom `true` on success; the runner (zigvm_suite_runner) counts a case EQ
%% only when BOTH VMs' `Suite:Case([])` returns `true`. A case that needs an
%% opcode/BIF the VM lacks would raise/`undef` -> caught -> counted `fail`
%% (visible divergence, never silent).
-module(zigvm_pure_SUITE).

-export([all/0,
         c_int_arith/1, c_int_large/1, c_int_div_rem/1, c_bitwise/1,
         c_list_build/1, c_list_rev/1, c_tuple/1,
         c_map_basic/1, c_map_update/1,
         c_bin_size/1, c_bs_int_rt/1, c_bs_utf8_rt/1, c_bs_bits/1,
         c_cmp_order/1, c_exact_eq/1,
         c_guard/1, c_try_error/1, c_try_throw/1, c_try_exit/1,
         c_closure/1, c_recursion/1,
         %% E4.1 process-effect cases (proc_SUITE / registration_SUITE-class):
         %% spawn/3 + send + receive; register/whereis; monitor/'DOWN';
         %% link + trap_exit/'EXIT'. ps_child/2, ps_waiter/1, ps_boom/0 are the
         %% spawned entry points (exported so spawn/3's MFA resolves).
         c_spawn/1, c_register/1, c_monitor/1, c_link_trap/1,
         ps_child/2, ps_waiter/1, ps_boom/0]).

%% The suite manifest (common_test `all/0` contract).
all() ->
    [c_int_arith, c_int_large, c_int_div_rem, c_bitwise,
     c_list_build, c_list_rev, c_tuple,
     c_map_basic, c_map_update,
     c_bin_size, c_bs_int_rt, c_bs_utf8_rt, c_bs_bits,
     c_cmp_order, c_exact_eq,
     c_guard, c_try_error, c_try_throw, c_try_exit,
     c_closure, c_recursion,
     c_spawn, c_register, c_monitor, c_link_trap].

%% --- arithmetic (num_bif_SUITE-class) -------------------------------------
c_int_arith(_) -> (2 + 3 * 4 - 1) =:= 13.

c_int_large(_) ->
    %% Large-but-in-bounds integer arithmetic (2^40 range, a 41-bit small).
    %% True bignum arithmetic BEYOND the VM's standing 60-bit bounds is a
    %% deliberately-EQUIV scope item (OTP30_E3_PLAN.md "known scope honesty":
    %% "bignum arith beyond the standing bounds") and is NOT a pure-suite case.
    B = pow2(40),
    (B div 2 =:= pow2(39)) andalso (B - pow2(40) =:= 0)
        andalso (B rem 2 =:= 0) andalso (B > pow2(39)).

c_int_div_rem(_) -> (17 div 5 =:= 3) andalso (17 rem 5 =:= 2).

c_bitwise(_) ->
    (5 band 3 =:= 1) andalso (5 bor 2 =:= 7)
        andalso (5 bxor 1 =:= 4) andalso (1 bsl 4 =:= 16).

%% --- lists / tuples -------------------------------------------------------
c_list_build(_) -> [1,2,3 | [4,5]] =:= [1,2,3,4,5].

c_list_rev(_) -> my_rev([1,2,3,4], []) =:= [4,3,2,1].

c_tuple(_) ->
    T = {a, 2, "x"},
    (element(1, T) =:= a) andalso (element(2, T) =:= 2)
        andalso (setelement(2, T, 9) =:= {a, 9, "x"}).

%% --- maps (map_SUITE-class) -----------------------------------------------
c_map_basic(_) ->
    M = #{a => 1, b => 2},
    (maps:get(a, M) =:= 1) andalso (map_size(M) =:= 2)
        andalso maps:is_key(b, M).

c_map_update(_) ->
    M0 = #{x => 1},
    M1 = M0#{x := 10, y => 20},
    (maps:get(x, M1) =:= 10) andalso (maps:get(y, M1) =:= 20).

%% --- binaries & bit-syntax (bs_construct/bs_match-class) ------------------
c_bin_size(_) -> byte_size(<<1, 2, 3, 4>>) =:= 4.

c_bs_int_rt(_) ->
    %% construction <-> matching round-trip of a 16-bit big-endian integer.
    N = 300,
    Bin = <<N:16>>,
    <<M:16>> = Bin,
    M =:= N.

c_bs_utf8_rt(_) ->
    %% UTF-8 codepoint construction + match (bs_*_utf8).
    Cp = 945,                         %% Greek small alpha
    Bin = <<Cp/utf8>>,
    <<Got/utf8>> = Bin,
    Got =:= Cp.

c_bs_bits(_) ->
    %% sub-byte bitstring: 3 bits + 5 bits == one byte, recovered exactly.
    Bs = <<5:3, 9:5>>,
    (bit_size(Bs) =:= 8) andalso begin <<A:3, B:5>> = Bs, (A =:= 5) andalso (B =:= 9) end.

%% --- term ordering / equality (term_SUITE-class) --------------------------
c_cmp_order(_) ->
    %% number < atom < tuple < map < list < bitstring (partial, over supported).
    (1 < a) andalso (a < {1}) andalso ({1} < [1]) andalso (1.0 < 2).

c_exact_eq(_) -> (1 =:= 1) andalso not (1 =:= 1.0) andalso (1 == 1.0).

%% --- guards & exceptions (exception_SUITE-class) --------------------------
c_guard(_) ->
    F = fun (X) when is_integer(X), X > 0 -> pos;
            (X) when is_integer(X) -> nonpos;
            (_) -> other
        end,
    (F(5) =:= pos) andalso (F(-1) =:= nonpos) andalso (F(a) =:= other).

c_try_error(_) ->
    R = try erlang:error(boom) catch C:E -> {C, E} end,
    R =:= {error, boom}.

c_try_throw(_) ->
    R = try throw(hi) catch C:E -> {C, E} end,
    R =:= {throw, hi}.

c_try_exit(_) ->
    R = try exit(bye) catch C:E -> {C, E} end,
    R =:= {exit, bye}.

%% --- funs / closures (fun_SUITE-class) ------------------------------------
c_closure(_) ->
    A = 10,
    F = fun (Y) -> Y + A end,
    (F(5) =:= 15) andalso (F(0) =:= 10).

c_recursion(_) -> fact(6) =:= 720.

%% --- local helpers (no external lists/*, so nothing to load) --------------
pow2(0) -> 1;
pow2(N) -> 2 * pow2(N - 1).

my_rev([], Acc) -> Acc;
my_rev([H | T], Acc) -> my_rev(T, [H | Acc]).

fact(0) -> 1;
fact(N) -> N * fact(N - 1).

%% --- process-effect cases (E4.1 scheduler-as-driver) ----------------------
ps_child(Parent, N) -> Parent ! N.
ps_waiter(Parent) -> receive go -> Parent ! done end.
ps_boom() -> exit(boom).

%% spawn/3 (MFA resolved against the linked export index) + send + receive.
c_spawn(_) ->
    Parent = self(),
    _P = spawn(zigvm_pure_SUITE, ps_child, [Parent, 42]),
    (receive X -> X end) =:= 42.

%% register/whereis/unregister bijection.
c_register(_) ->
    register(zps_reg, self()),
    R1 = whereis(zps_reg) =:= self(),
    unregister(zps_reg),
    R2 = whereis(zps_reg) =:= undefined,
    R1 andalso R2.

%% monitor a child, wake it, observe its 'DOWN' exactly once.
c_monitor(_) ->
    Parent = self(),
    P = spawn(zigvm_pure_SUITE, ps_waiter, [Parent]),
    _Ref = monitor(process, P),
    P ! go,
    ok = receive done -> ok end,
    receive {'DOWN', _, process, _, _} -> true end.

%% link + trap_exit: a linked abnormal exit arrives as {'EXIT', Pid, Reason}
%% binding the specific child pid (not a wildcard).
c_link_trap(_) ->
    process_flag(trap_exit, true),
    P = spawn_opt(zigvm_pure_SUITE, ps_boom, [], [link]),
    receive {'EXIT', P, boom} -> true end.
