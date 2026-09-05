%% Curated subset of erts/emulator/test/nested_SUITE.erl (E7 suite closure),
%% widened to its natural term-algebra neighbourhood: DEEPLY NESTED TERMS.
%%
%% The real nested_SUITE is a 4-case regression probe for syntactic NESTING —
%% case-in-case, a nested case computing a `receive after` timeout,
%% catch-in-catch, and bif-in-bif. The first three are pure control-flow
%% nesting and are mirrored here verbatim in spirit (c_case_in_case,
%% c_case_in_after, c_catch_in_catch). bif_in_bif is EXCLUDED: it exercises
%% register/2 + the process dictionary (a GLOBAL, cross-case side effect —
%% registering ?MODULE would leak between cases/VMs), not term algebra.
%%
%% The bulk of this suite covers what "nested" means for TERMS: nested
%% tuples/lists/maps built and structurally matched, deep observational
%% equality (and deep INequality distinguished at a single deep leaf), nested
%% pattern binding that reaches variables several layers down, nested term
%% ordering, guards that walk into a nested term, functional update deep inside
%% nested maps, a nested-comprehension builder, and a term_to_binary /
%% binary_to_term round-trip of a heterogeneous nested structure. Every one
%% asserts a REPRESENTATION-INDEPENDENT, VALUE-STABLE truth both VMs must
%% compute identically (byte-EQ).
%%
%% catch_in_catch matches only the {'EXIT', _} TAG (it never inspects the
%% reason term or a stacktrace), so no {EXIT,{R,Stk}} shape is compared — the
%% observable is the plain atom/tuple result. Runtime operands are routed
%% through the exported ?MODULE:id/1 so constant folding cannot bypass the VM.
%% No ct/port/node dependency and no lists:* calls — runnable on zigvm. A case
%% returns the atom `true` on success; the runner (zigvm_nested_suite_runner)
%% counts a case EQ only when BOTH VMs' Suite:Case([]) returns `true`.
-module(zigvm_nested_SUITE).
-export([all/0, c_deep_tuple/1, c_deep_list/1, c_deep_map/1, c_mixed_nesting/1,
         c_nested_pattern_binding/1, c_nested_inequality/1, c_term_roundtrip/1,
         c_nested_map_update/1, c_nested_ordering/1, c_nested_guard/1,
         c_case_in_case/1, c_case_in_after/1, c_catch_in_catch/1,
         c_nested_comprehension/1, id/1]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's nested-suite spec case_names (ncases/1 lockstep).
all() ->
    [c_deep_tuple, c_deep_list, c_deep_map, c_mixed_nesting,
     c_nested_pattern_binding, c_nested_inequality, c_term_roundtrip,
     c_nested_map_update, c_nested_ordering, c_nested_guard,
     c_case_in_case, c_case_in_after, c_catch_in_catch,
     c_nested_comprehension].

%% Identity through an exported call — the compiler cannot constant-fold across
%% it, so seed values genuinely travel through the VM.
id(X) -> X.

%% --- deeply nested tuples: build, structurally match, deep-equal ------------
c_deep_tuple(_) ->
    T = {a, {b, {c, id(1)}}, {d, {e, {f, id(2)}}}},
    {a, {b, {c, X}}, {d, {e, {f, Y}}}} = T,
    (X =:= 1) andalso (Y =:= 2)
        andalso (T =:= {a, {b, {c, 1}}, {d, {e, {f, 2}}}})
        andalso (tuple_size(element(2, T)) =:= 2).

%% --- deeply nested (right-spined) lists: build + deep-equal -----------------
c_deep_list(_) ->
    L = [id(1), [id(2), [id(3), [id(4), [id(5), []]]]]],
    (L =:= [1, [2, [3, [4, [5, []]]]]])
        andalso (L =/= [1, [2, [3, [4, [6, []]]]]])
        andalso ([[a], [b, [c]]] =:= [[a], [b, [c]]]).

%% --- nested maps: `:=` match several layers down + maps:get chain -----------
c_deep_map(_) ->
    M = #{outer => #{mid => #{inner => id(42)}}},
    #{outer := #{mid := #{inner := V}}} = M,
    (V =:= 42)
        andalso (maps:get(inner, maps:get(mid, maps:get(outer, M))) =:= 42).

%% --- heterogeneous nesting: map > list > tuple > map ------------------------
c_mixed_nesting(_) ->
    T = #{list => [{tag, #{n => id(1)}}, {tag, #{n => id(2)}}]},
    #{list := [{tag, #{n := N1}}, {tag, #{n := N2}}]} = T,
    (N1 =:= 1) andalso (N2 =:= 2)
        andalso (T =:= #{list => [{tag, #{n => 1}}, {tag, #{n => 2}}]}).

%% --- nested pattern binding: reach vars deep inside a tree term -------------
c_nested_pattern_binding(_) ->
    Tree = {node, id(1), [{node, id(2), []}, {leaf, id(9)}]},
    {node, A, [{node, B, _}, {leaf, C}]} = Tree,
    (A =:= 1) andalso (B =:= 2) andalso (C =:= 9).

%% --- deep INequality: structures differ at exactly one deep leaf ------------
c_nested_inequality(_) ->
    P = {1, [2, {3, #{x => [4, {id(5)}]}}]},
    Same = {1, [2, {3, #{x => [4, {5}]}}]},
    Diff = {1, [2, {3, #{x => [4, {6}]}}]},
    (P =:= Same) andalso (P =/= Diff) andalso (P < Diff).

%% --- term_to_binary / binary_to_term round-trip of a nested structure -------
c_term_roundtrip(_) ->
    T = {a, [1, 2, {b, #{k => [3, 4]}}], id("xy")},
    B = term_to_binary(T),
    is_binary(B) andalso (binary_to_term(B) =:= T).

%% --- functional update DEEP inside nested maps (no mutation of the original)-
c_nested_map_update(_) ->
    M = #{a => #{b => id(1)}},
    Inner = maps:get(a, M),
    M2 = M#{a => Inner#{b => 2}},
    (maps:get(b, maps:get(a, M2)) =:= 2)
        andalso (maps:get(b, maps:get(a, M)) =:= 1).

%% --- nested term ordering: element-wise, recursing into sub-terms -----------
c_nested_ordering(_) ->
    ([1, [2, 3]] < [1, [2, 4]])
        andalso ({a, {b, 1}} < {a, {b, 2}})
        andalso ([[1], [2]] < [[1], [2], [3]])
        andalso (#{k => [1, 2]} < #{k => [1, 3]}).

%% --- guard walking into a nested term (element/2 nested in a guard) ---------
c_nested_guard(_) ->
    T = {p, {q, id(5)}},
    R = if element(1, element(2, T)) =:= q -> yes; true -> no end,
    R =:= yes.

%% --- case_in_case: a case scrutinising the value of an inner case (mirror) --
c_case_in_case(_) ->
    R = case case id(a) of a -> inner_a; _ -> inner_other end of
            inner_a -> outer_a;
            _ -> outer_other
        end,
    R =:= outer_a.

%% --- case_in_after: a nested case computes the `receive after` timeout ------
%% (mirror of the real suite's case_in_after; timeout is a constant 0, no
%% wall-clock value is observed — only that the after-branch runs).
c_case_in_after(_) ->
    R = receive
        after case {x, y, z} of {x, y, z} -> 0 end -> after_ran
        end,
    R =:= after_ran.

%% --- catch_in_catch: a catch nested inside a catch (mirror) -----------------
%% The inner expression raises (badarith on division by zero); each catch
%% matches only the {'EXIT', _} TAG — no reason/stacktrace shape is inspected.
c_catch_in_catch(_) ->
    Res = case (catch case (catch id(1) div id(0)) of
                          {'EXIT', _} -> inner_exit;
                          V1 -> {inner, V1}
                      end) of
              {'EXIT', _} -> outer_exit;
              V2 -> {outer, V2}
          end,
    Res =:= {outer, inner_exit}.

%% --- nested-comprehension builder: a list of nested terms -------------------
c_nested_comprehension(_) ->
    L = [{X, [X, {X}]} || X <- id([1, 2, 3])],
    L =:= [{1, [1, {1}]}, {2, [2, {2}]}, {3, [3, {3}]}].
