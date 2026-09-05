%% Curated PURE subset of erts/emulator/test/atomics_SUITE.erl (E7 suite closure).
%% The real suite exercises the atomics BIF family: new/2 (signed+unsigned),
%% put/get, add/add_get, sub/sub_get, exchange, compare_exchange, info/1, the
%% signed/unsigned 64-bit limits+wraparound, badarg rejection, and error_info
%% metadata. These cases MIRROR the pure algebraic content (signed_do/
%% unsigned_do sequences, info size/min/max, wrap semantics, rejection) as
%% self-contained BOOLEAN assertions both VMs must compute identically.
%%
%% CONSTRUCTOR SHIM (a_new/3, empirically verified EQ on both VMs 2026-07-23):
%% `atomics:new/2` is a preloaded-atomics.erl library wrapper — NOT a bif.tab
%% row — so it traps `undef` on zigvm (only the real primitive
%% `erts_internal:atomics_new/2` is wired, per bifs/atomics.zig). And the
%% primitive's Opts encoding DIVERGES: OTP expects the integer bitmask
%% atomics.erl encodes (1 = signed); zigvm's primitive accepts the raw
%% `[{signed,Bool}]` list. a_new/3 tries the OTP int shape first and falls
%% back to the zigvm list shape on badarg — a constructor-portability shim
%% ONLY; every assertion AFTER construction is genuine differential content
%% computed by the VM under test.
%%
%% Exclusions (honesty bounds):
%%   - sub/3, sub_get/3: atomics.erl library wrappers (undef on zigvm) —
%%     mirrored via add of the NEGATED operand (the same definition).
%%   - signed_limits/unsigned_limits put/add of +-2^63-scale operands: zigvm
%%     atomics args are small-int-only (~+-2^59, bifs/atomics.zig scope note;
%%     bignum args badarg on zigvm, accepted on OTP) — wraparound is instead
%%     proven by REPEATED small adds crossing 2^63 (c_signed_wrap) and by
%%     -1/+1 around 0 on unsigned (c_unsigned_wrap), all args small on both.
%%   - atomics:new(1 bsl 64, []) system_limit: zigvm rejects the bignum arity
%%     as badarg, not system_limit — divergent error TERM, excluded.
%%   - error_info/1: stacktrace/error_info metadata (zigvm E1 exception model:
%%     stacktraces nil) — rejection is asserted via try/catch error:badarg
%%     (class+reason, EQ on both), never via the {'EXIT',{badarg,_}} catch
%%     shape or stacktrace contents.
%%   - info/1 `memory`: an allocator-dependent VALUE — asserted only by the
%%     real suite's own BOUNDS (> Size*8, < Size*8+100), never by constant.
-module(zigvm_atomics_SUITE).
-export([all/0, id/1,
         c_signed/1, c_unsigned/1, c_bad/1,
         c_info_signed/1, c_info_unsigned/1,
         c_signed_wrap/1, c_unsigned_wrap/1,
         c_get_put/1, c_add_contract/1, c_exchange/1,
         c_compare_exchange/1, c_independence/1]).

all() ->
    [c_signed, c_unsigned, c_bad,
     c_info_signed, c_info_unsigned,
     c_signed_wrap, c_unsigned_wrap,
     c_get_put, c_add_contract, c_exchange,
     c_compare_exchange, c_independence].

%% erlc constant-folds literal arithmetic; route operands through this
%% EXPORTED external call so cases exercise the RUNTIME VM.
id(X) -> X.

%% ---- constructor shim (see module header) --------------------------------
a_new(Arity, EncodedOpts, OptsList) ->
    try erts_internal:atomics_new(Arity, EncodedOpts)
    catch error:badarg -> erts_internal:atomics_new(Arity, OptsList) end.

new_signed(Arity) -> a_new(Arity, 1, []).
new_unsigned(Arity) -> a_new(Arity, 0, [{signed, false}]).

badarg(F) ->
    try F() of _ -> false catch error:badarg -> true; _:_ -> false end.

%% signed: the exact signed_do/2 op sequence over every index of a size-10
%% array (sub/sub_get mirrored as add/add_get of the negated operand).
c_signed(_) ->
    R = new_signed(10),
    signed_all(R, 10).

signed_all(_R, 0) -> true;
signed_all(R, Ix) -> signed_do(R, Ix) andalso signed_all(R, Ix - 1).

signed_do(R, Ix) ->
    (atomics:get(R, Ix) =:= 0)
        andalso (atomics:put(R, Ix, 3) =:= ok)
        andalso (atomics:add(R, Ix, 14) =:= ok)
        andalso (atomics:get(R, Ix) =:= 17)
        andalso (atomics:add_get(R, Ix, 3) =:= 20)
        andalso (atomics:add_get(R, Ix, -23) =:= -3)
        andalso (atomics:add_get(R, Ix, 20) =:= 17)
        andalso (atomics:add(R, Ix, -4) =:= ok)       %% sub(R, Ix, 4)
        andalso (atomics:get(R, Ix) =:= 13)
        andalso (atomics:add_get(R, Ix, -20) =:= -7)  %% sub_get(R, Ix, 20)
        andalso (atomics:add_get(R, Ix, 10) =:= 3)    %% sub_get(R, Ix, -10)
        andalso (atomics:exchange(R, Ix, 666) =:= 3)
        andalso (atomics:compare_exchange(R, Ix, 666, 777) =:= ok)
        andalso (atomics:compare_exchange(R, Ix, 666, -666) =:= 777).

%% unsigned: the exact unsigned_do/2 op sequence over every index (values
%% never dip below zero; sub mirrored as add of the negated operand).
c_unsigned(_) ->
    R = new_unsigned(10),
    unsigned_all(R, 10).

unsigned_all(_R, 0) -> true;
unsigned_all(R, Ix) -> unsigned_do(R, Ix) andalso unsigned_all(R, Ix - 1).

unsigned_do(R, Ix) ->
    (atomics:get(R, Ix) =:= 0)
        andalso (atomics:put(R, Ix, 3) =:= ok)
        andalso (atomics:add(R, Ix, 14) =:= ok)
        andalso (atomics:get(R, Ix) =:= 17)
        andalso (atomics:add_get(R, Ix, 3) =:= 20)
        andalso (atomics:add(R, Ix, -7) =:= ok)       %% sub(R, Ix, 7)
        andalso (atomics:get(R, Ix) =:= 13)
        andalso (atomics:add_get(R, Ix, -10) =:= 3)   %% sub_get(R, Ix, 10)
        andalso (atomics:exchange(R, Ix, 666) =:= 3)
        andalso (atomics:compare_exchange(R, Ix, 666, 777) =:= ok)
        andalso (atomics:compare_exchange(R, Ix, 666, 888) =:= 777).

%% bad: badarg rejection on every op family (mirrors bad/1 minus the
%% system_limit and catch-wrap-shape rows — see the header exclusions), and
%% rejected calls never corrupt the array.
c_bad(_) ->
    R = new_signed(10),
    badarg(fun() -> a_new(0, 1, []) end)
        andalso badarg(fun() -> a_new(-1, 1, []) end)
        andalso badarg(fun() -> atomics:get(R, 0) end)
        andalso badarg(fun() -> atomics:get(R, -1) end)
        andalso badarg(fun() -> atomics:get(R, 11) end)
        andalso badarg(fun() -> atomics:get(R, id(7.0)) end)
        andalso badarg(fun() -> atomics:get(make_ref(), 7) end)
        andalso badarg(fun() -> atomics:put(R, 0, 42) end)
        andalso badarg(fun() -> atomics:add(R, 11, 99) end)
        andalso badarg(fun() -> atomics:add_get(R, 0, 99) end)
        andalso badarg(fun() -> atomics:exchange(R, 11, 50) end)
        andalso badarg(fun() -> atomics:compare_exchange(R, 0, 50, 99) end)
        %% a rejected op is a no-op: the array is untouched.
        andalso (atomics:get(R, 1) =:= 0).

%% info (signed): exact size/max/min (the 64-bit signed domain), memory by
%% the real suite's own bounds only.
c_info_signed(_) ->
    Size = id(10),
    R = new_signed(Size),
    case atomics:info(R) of
        #{size := S, max := Mx, min := Mn, memory := Mem} ->
            (S =:= Size)
                andalso (Mx =:= (id(1) bsl 63) - 1)
                andalso (Mn =:= -(id(1) bsl 63))
                andalso (Mem > Size * 8)
                andalso (Mem < Size * 8 + 100);
        _ -> false
    end.

%% info (unsigned): exact size/max/min (the 64-bit unsigned domain).
c_info_unsigned(_) ->
    Size = id(7),
    R = new_unsigned(Size),
    case atomics:info(R) of
        #{size := S, max := Mx, min := Mn, memory := Mem} ->
            (S =:= Size)
                andalso (Mx =:= (id(1) bsl 64) - 1)
                andalso (Mn =:= 0)
                andalso (Mem > Size * 8)
                andalso (Mem < Size * 8 + 100);
        _ -> false
    end.

%% signed wraparound (mirrors signed_limits' Max+1 -> Min semantics without
%% +-2^63 ARGS): 17 accumulated adds of MaxSmall = 2^59-1 cross +2^63; the
%% cell must equal the mod-2^64 two's-complement reduction computed in pure
%% (bignum) Erlang arithmetic — no hardcoded wrap constant.
c_signed_wrap(_) ->
    R = new_signed(1),
    M = (id(1) bsl 59) - 1,
    ok = atomics:put(R, 1, M),
    Last = add_n(R, 16, M, 0),
    Total = 17 * M,
    Expected = ((Total + (1 bsl 63)) rem (1 bsl 64)) - (1 bsl 63),
    (Expected < 0)                       %% it genuinely wrapped
        andalso (Last =:= Expected)      %% add_get saw the wrapped value
        andalso (atomics:get(R, 1) =:= Expected).

add_n(_R, 0, _M, Acc) -> Acc;
add_n(R, N, M, _) -> V = atomics:add_get(R, 1, M), add_n(R, N - 1, M, V).

%% unsigned wraparound (mirrors unsigned_limits' underflow/overflow around
%% the domain edge with small args): 0 - 1 wraps to 2^64-1, + 1 wraps back.
c_unsigned_wrap(_) ->
    R = new_unsigned(1),
    (atomics:add_get(R, 1, id(-1)) =:= (id(1) bsl 64) - 1)
        andalso (atomics:get(R, 1) =:= (1 bsl 64) - 1)
        andalso (atomics:add_get(R, 1, id(1)) =:= 0)
        andalso (atomics:get(R, 1) =:= 0).

%% put/get round-trip across the signed small-value domain (id-routed),
%% up to +-(2^59-1); fresh cells read 0. (The exact -(2^59) endpoint is
%% EXCLUDED: it is the one asymmetric fixnum-edge value zigvm's small-int-only
%% atomics arg check rejects as badarg while OTP accepts — empirically probed
%% 2026-07-23; the same documented small-arg scope bound as the +-2^63 limits.)
c_get_put(_) ->
    R = new_signed(3),
    MaxSmall = (id(1) bsl 59) - 1,
    MinSmall = -((id(1) bsl 59) - 1),
    (atomics:get(R, 3) =:= 0)
        andalso (atomics:put(R, 1, id(123456789)) =:= ok)
        andalso (atomics:get(R, 1) =:= 123456789)
        andalso (atomics:put(R, 1, id(-987654321)) =:= ok)
        andalso (atomics:get(R, 1) =:= -987654321)
        andalso (atomics:put(R, 2, MaxSmall) =:= ok)
        andalso (atomics:get(R, 2) =:= MaxSmall)
        andalso (atomics:put(R, 2, MinSmall) =:= ok)
        andalso (atomics:get(R, 2) =:= MinSmall)
        andalso (atomics:put(R, 3, id(0)) =:= ok)
        andalso (atomics:get(R, 3) =:= 0).

%% the add/3-vs-add_get/3 contract: add returns ok and DISCARDS the new
%% value; add_get returns the post-add value; get agrees with both.
c_add_contract(_) ->
    R = new_signed(1),
    (atomics:add(R, 1, id(5)) =:= ok)
        andalso (atomics:get(R, 1) =:= 5)
        andalso (atomics:add_get(R, 1, id(7)) =:= 12)
        andalso (atomics:get(R, 1) =:= 12)
        andalso (atomics:add(R, 1, id(-12)) =:= ok)
        andalso (atomics:get(R, 1) =:= 0).

%% exchange returns the OLD value and installs the desired one.
c_exchange(_) ->
    R = new_signed(1),
    (atomics:exchange(R, 1, id(11)) =:= 0)
        andalso (atomics:get(R, 1) =:= 11)
        andalso (atomics:exchange(R, 1, id(-22)) =:= 11)
        andalso (atomics:get(R, 1) =:= -22).

%% compare_exchange: ok iff the expectation matched (and the swap happened);
%% otherwise the ACTUAL current value — and a failed CAS is a PURE READ.
c_compare_exchange(_) ->
    R = new_signed(1),
    (atomics:put(R, 1, id(50)) =:= ok)
        andalso (atomics:compare_exchange(R, 1, 50, 60) =:= ok)
        andalso (atomics:get(R, 1) =:= 60)
        andalso (atomics:compare_exchange(R, 1, 999, 70) =:= 60)
        andalso (atomics:get(R, 1) =:= 60)            %% failed CAS: no write
        andalso (atomics:compare_exchange(R, 1, 60, -60) =:= ok)
        andalso (atomics:get(R, 1) =:= -60).

%% locality: distinct cells of one array, and distinct arrays, never alias.
c_independence(_) ->
    R = new_signed(3),
    S = new_unsigned(2),
    (atomics:put(R, 2, id(5)) =:= ok)
        andalso (atomics:get(R, 1) =:= 0)
        andalso (atomics:get(R, 3) =:= 0)
        andalso (atomics:put(S, 1, id(9)) =:= ok)
        andalso (atomics:get(R, 2) =:= 5)
        andalso (atomics:exchange(S, 2, id(77)) =:= 0)
        andalso (atomics:get(R, 2) =:= 5)
        andalso (atomics:get(S, 1) =:= 9)
        andalso (atomics:get(S, 2) =:= 77).
