%% zigvm_counters_SUITE — a PURE curated subset of erts `counters_SUITE`, in the
%% common_test SUITE shape (`all/0` + `Case(Config)` funs) with NO common_test /
%% test_server dependency (CT-on-zigvm is Epoch E7). Every case drives the
%% `erts_internal:counters_*` PRIMITIVES directly — the write_concurrency backend
%% underneath `counters.erl` (`counters:new(N,[write_concurrency])` →
%% `erts_internal:counters_new/1`, then `get/2`/`add/3`/`put/3`/`info/1`) — exactly
%% as `zigvm_atomics_SUITE` drives `erts_internal:atomics_new/2`. On the OTP-30
%% oracle these return/accept a real opaque counters ref; on zigvm a small-int
%% registry id (bifs/counters.zig, reusing the atomics-array algebra). The ref is
%% treated OPAQUELY — every case asserts counter VALUES, never the ref shape or the
%% `memory` byte count (which is representation-dependent), so both VMs agree
%% byte-for-byte on value-stable facts.
%%
%% counters semantics mirrored: 1-based indices; a fresh array reads 0; `add/3`
%% accumulates and returns `ok`; a NEGATIVE increment is the `counters:sub/3` path;
%% `put/3` overwrites; independent indices are isolated; `info/1` reports a map with
%% `size` (= the requested Size) and `memory` (an integer — value NOT asserted). All
%% integer operands travel through the exported `?MODULE:id/1` so the compiler
%% cannot constant-fold them out of the VM. A case returns `true` on success.
-module(zigvm_counters_SUITE).

-export([all/0,
         c_new_zeroed/1, c_put_get/1, c_add_accumulate/1, c_sub_via_negative/1,
         c_independent_indices/1, c_info_keys/1, c_bad_index/1, c_bad_ref/1,
         c_sequence/1, c_wide_array/1,
         id/1]).

all() ->
    [c_new_zeroed, c_put_get, c_add_accumulate, c_sub_via_negative,
     c_independent_indices, c_info_keys, c_bad_index, c_bad_ref,
     c_sequence, c_wide_array].

id(X) -> X.

new(N) -> erts_internal:counters_new(id(N)).
get(R, Ix) -> erts_internal:counters_get(R, id(Ix)).
add(R, Ix, V) -> erts_internal:counters_add(R, id(Ix), id(V)).
put(R, Ix, V) -> erts_internal:counters_put(R, id(Ix), id(V)).
info(R) -> erts_internal:counters_info(R).

%% --- a fresh counters array reads 0 at every index --------------------------
c_new_zeroed(_) ->
    R = new(3),
    (get(R, 1) =:= 0) andalso (get(R, 2) =:= 0) andalso (get(R, 3) =:= 0).

%% --- put then get round-trips -----------------------------------------------
c_put_get(_) ->
    R = new(2),
    ok = put(R, 1, 42),
    ok = put(R, 2, -7),
    (get(R, 1) =:= 42) andalso (get(R, 2) =:= -7).

%% --- add accumulates and returns ok -----------------------------------------
c_add_accumulate(_) ->
    R = new(1),
    ok = add(R, 1, 10),
    ok = add(R, 1, 7),
    ok = add(R, 1, 100),
    get(R, 1) =:= 117.

%% --- a NEGATIVE increment is the counters:sub/3 path ------------------------
c_sub_via_negative(_) ->
    R = new(1),
    ok = put(R, 1, 50),
    ok = add(R, 1, -20), % sub(R,1,20)
    ok = add(R, 1, -5),  % sub(R,1,5)
    get(R, 1) =:= 25.

%% --- independent indices do not interfere -----------------------------------
c_independent_indices(_) ->
    R = new(4),
    ok = put(R, 1, 11),
    ok = add(R, 3, 33),
    ok = add(R, 4, 44),
    (get(R, 1) =:= 11) andalso (get(R, 2) =:= 0)
        andalso (get(R, 3) =:= 33) andalso (get(R, 4) =:= 44).

%% --- info/1 reports size (= requested) + an integer memory (value NOT tested) --
c_info_keys(_) ->
    R = new(5),
    I = info(R),
    (maps:get(size, I) =:= 5)
        andalso is_integer(maps:get(memory, I))
        andalso is_map(I).

%% --- an out-of-range index raises badarg (1-based; 0 and N+1 are invalid) ----
c_bad_index(_) ->
    R = new(2),
    A = try get(R, 0) catch error:badarg -> caught end,
    B = try get(R, 3) catch error:badarg -> caught end,
    C = try add(R, 0, 1) catch error:badarg -> caught end,
    (A =:= caught) andalso (B =:= caught) andalso (C =:= caught).

%% --- a bad ref raises badarg -------------------------------------------------
c_bad_ref(_) ->
    A = try erts_internal:counters_get(not_a_ref, 1) catch error:badarg -> caught end,
    A =:= caught.

%% --- a deterministic op sequence accumulates predictably ---------------------
c_sequence(_) ->
    R = new(2),
    ok = add(R, 1, 1),
    ok = add(R, 2, 10),
    ok = add(R, 1, 2),
    ok = add(R, 2, 20),
    ok = put(R, 1, 100),
    ok = add(R, 1, 5),
    (get(R, 1) =:= 105) andalso (get(R, 2) =:= 30).

%% --- a wider array: ops across many indices ---------------------------------
c_wide_array(_) ->
    R = new(8),
    ok = fill(R, 1, 8),
    (get(R, 1) =:= 1) andalso (get(R, 5) =:= 5) andalso (get(R, 8) =:= 8)
        andalso (maps:get(size, info(R)) =:= 8).

fill(_R, Ix, N) when Ix > N -> ok;
fill(R, Ix, N) -> ok = put(R, Ix, Ix), fill(R, Ix + 1, N).
