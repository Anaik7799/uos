%% Curated PURE subset of erts/emulator/test/list_bif_SUITE.erl (E7 suite closure).
%% The real suite exercises the list BIFs — hd/1, tl/1, length/1, and the
%% list_to_* converters — most of which are entangled with common_test, peer
%% nodes, pids/ports/refs, and float formatting. This curated subset keeps ONLY
%% the representation-independent, value-stable list-BIF truths that BOTH VMs
%% must compute bit-for-bit, and rounds the coverage out with the pure list-BIF
%% family the focus names (reverse/append/subtract/member/keyfind/list_to_tuple).
%%
%% Every function used is confirmed on zigvm's proven surface:
%%   erlang: hd/1, tl/1, length/1, '++'/2, '--'/2, list_to_tuple/1,
%%           tuple_to_list/1, list_to_integer/1, integer_to_list/1
%%   lists:  member/2, reverse/2, keyfind/3, keysearch/3, keymember/3 (BIFs,
%%           resolved via the loader's bif_dispatch — NOT the pure-Erlang lists
%%           module, so lists:seq/reverse-1 are deliberately EXCLUDED).
%%
%% EXCLUDED from the real suite (would DIVERGE or need CT/nodes/formatting):
%%   t_list_to_pid/port/ref, t_list_to_ext_pidportref (pids/ports/refs, peer
%%   nodes, term_to_binary of externals), t_list_to_float (float parsing +
%%   formatting), the big-bignum list_to_integer (magnitude > i128 — zigvm's
%%   list_to_integer routes through i128, so a 137-bit literal overflows), and
%%   the system_limit 3e6-digit stress (host-timed, allocator substrate).
%% Mirrors: hd_test, tl_test, t_length, and the pure part of t_list_to_integer.
-module(zigvm_list_bif_SUITE).
-export([all/0, c_hd/1, c_tl/1, c_length/1, c_reverse/1, c_append/1,
         c_subtract/1, c_member/1, c_list_to_tuple/1, c_keyfind/1,
         c_keysearch_keymember/1, c_list_to_integer/1]).

all() ->
    [c_hd, c_tl, c_length, c_reverse, c_append, c_subtract, c_member,
     c_list_to_tuple, c_keyfind, c_keysearch_keymember, c_list_to_integer].

%% hd_test: hd/1 returns the head of a proper list (char lists included).
c_hd(_) ->
    (hd("hejsan") =:= $h)
        andalso (hd([1, 2, 3]) =:= 1)
        andalso (hd([a]) =:= a)
        andalso (hd([[x], y]) =:= [x]).

%% tl_test: tl/1 returns the tail of a proper list.
c_tl(_) ->
    (tl("hejsan") =:= "ejsan")
        andalso (tl([1, 2, 3]) =:= [2, 3])
        andalso (tl([a]) =:= [])
        andalso (tl([1, 2, 3, 4]) =:= [2, 3, 4]).

%% t_length: length/1 counts the cells of a proper list; char lists count bytes.
c_length(_) ->
    (length("") =:= 0)
        andalso (length([]) =:= 0)
        andalso (length([1]) =:= 1)
        andalso (length([1, a]) =:= 2)
        andalso (length("ab") =:= 2)
        andalso (length("abc") =:= 3)
        andalso (length([x | "abc"]) =:= 4)
        andalso (length("hejsan") =:= 6).

%% lists:reverse/2 (the BIF): fold-cons List onto Tail; round-trips.
c_reverse(_) ->
    (lists:reverse([1, 2, 3], []) =:= [3, 2, 1])
        andalso (lists:reverse([], []) =:= [])
        andalso (lists:reverse("abc", []) =:= "cba")
        andalso (lists:reverse([1, 2, 3], [4, 5]) =:= [3, 2, 1, 4, 5])
        andalso (lists:reverse(lists:reverse([a, b, c, d], []), []) =:= [a, b, c, d]).

%% erlang:'++'/2 (append): concatenation, with identities and associativity.
c_append(_) ->
    ([1, 2] ++ [3, 4] =:= [1, 2, 3, 4])
        andalso ([] ++ [a] =:= [a])
        andalso ([1] ++ [] =:= [1])
        andalso ("ab" ++ "cd" =:= "abcd")
        andalso (([1] ++ [2]) ++ [3] =:= [1] ++ ([2] ++ [3])).

%% erlang:'--'/2 (subtract): remove the first =:= match in A per element of B.
c_subtract(_) ->
    ([1, 2, 3, 2, 1] -- [2, 1] =:= [3, 2, 1])
        andalso ([1, 2, 3] -- [] =:= [1, 2, 3])
        andalso ([1, 2, 3] -- [4] =:= [1, 2, 3])
        andalso ([1, 1, 2] -- [1] =:= [1, 2])
        andalso ([a, b, c] -- [a, b, c] =:= []).

%% lists:member/2 (the BIF): EXACT (=:=) membership — member(1,[1.0]) is false.
c_member(_) ->
    (lists:member(2, [1, 2, 3]) =:= true)
        andalso (lists:member(5, [1, 2, 3]) =:= false)
        andalso (lists:member(a, []) =:= false)
        andalso (lists:member(1, [1.0]) =:= false)
        andalso (lists:member(c, [a, b, c]) =:= true).

%% list_to_tuple/1 & tuple_to_list/1: round-trip between lists and tuples.
c_list_to_tuple(_) ->
    (list_to_tuple([a, b, c]) =:= {a, b, c})
        andalso (list_to_tuple([]) =:= {})
        andalso (tuple_to_list({1, 2, 3}) =:= [1, 2, 3])
        andalso (list_to_tuple(tuple_to_list({x, y, z})) =:= {x, y, z})
        andalso (tuple_to_list(list_to_tuple([1, a, "s"])) =:= [1, a, "s"]).

%% lists:keyfind/3 (the BIF): first tuple whose N-th element =:= Key; proplist
%% tolerance (non-tuple / too-small elements are skipped, not rejected).
c_keyfind(_) ->
    (lists:keyfind(b, 1, [{a, 1}, {b, 2}]) =:= {b, 2})
        andalso (lists:keyfind(x, 1, [{a, 1}, {b, 2}]) =:= false)
        andalso (lists:keyfind(2, 2, [{a, 1}, {b, 2}]) =:= {b, 2})
        andalso (lists:keyfind(b, 1, [x, {b, 2}]) =:= {b, 2})
        andalso (lists:keyfind(k, 2, [{k}, {a, k}]) =:= {a, k}).

%% lists:keysearch/3 wraps keyfind as {value,T}|false; keymember/3 projects to
%% a boolean.
c_keysearch_keymember(_) ->
    (lists:keysearch(b, 1, [{a, 1}, {b, 2}]) =:= {value, {b, 2}})
        andalso (lists:keysearch(x, 1, [{a, 1}, {b, 2}]) =:= false)
        andalso (lists:keymember(b, 1, [{a, 1}, {b, 2}]) =:= true)
        andalso (lists:keymember(x, 1, [{a, 1}, {b, 2}]) =:= false).

%% t_list_to_integer (pure, in-range part): parse decimal digit lists, with
%% optional +/- sign; integer_to_list round-trips. Magnitudes kept well within
%% zigvm's i128-bounded list_to_integer (the suite's 137-bit literal is
%% EXCLUDED — it overflows i128 and would diverge).
c_list_to_integer(_) ->
    (list_to_integer("12373") =:= 12373)
        andalso (list_to_integer("-12373") =:= -12373)
        andalso (list_to_integer("+12373") =:= 12373)
        andalso (list_to_integer("0") =:= 0)
        andalso (integer_to_list(12373) =:= "12373")
        andalso (list_to_integer(integer_to_list(987654321)) =:= 987654321).
