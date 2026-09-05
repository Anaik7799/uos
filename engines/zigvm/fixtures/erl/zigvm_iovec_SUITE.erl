%% Curated PURE subset of erts/emulator/test/iovec_SUITE.erl (E7 suite closure).
%% The real suite exercises erlang:iolist_to_iovec/1 — the iolist "flattening"
%% BIF that reduces an arbitrarily nested/improper iolist to a flat list of
%% binaries (an iovec), merging small fragments — cross-checked against
%% iolist_to_binary/1, plus its idempotence, its badarg rejection domain, and
%% the direct-binary argument forms. These cases assert REPRESENTATION-
%% INDEPENDENT, VALUE-STABLE truths both VMs must compute identically (byte-EQ),
%% mirroring the suite's integer_lists, binary_lists, empty_lists,
%% empty_binary_lists, mixed_lists, improper_lists, illegal_lists, cons_bomb,
%% iolist_to_iovec_idempotence, iolist_to_iovec_correctness, and
%% direct_binary_arg cases. iolist_size/1 and list_to_binary/1 (both EQ on
%% zigvm) anchor the size/concatenation laws.
%%
%% EXCLUDED — the real suite's sub_binary_lists and unaligned_sub_binaries
%% cases: feeding an OFFSET sub-binary (a non-zero byte-offset match binding,
%% e.g. <<_:32/binary, C/binary>>) into any iolist-flattening BIF
%% (iolist_to_iovec/1, iolist_to_binary/1, list_to_binary/1, iolist_size/1)
%% PANICS the current zigvm CLI ("index out of bounds" in
%% term_algebra.zig:ioAccList) while OTP returns the flattened bytes. This is a
%% real, isolated zigvm bug (sub-binaries compare/size correctly OUTSIDE an
%% iolist; only the flattening walk mis-indexes the offset). Reported as a
%% divergence rather than curated to green — every case here uses offset-0
%% (whole) binaries only, where both VMs agree byte-for-byte.
%%
%% No ct/port/node dependency and no lists:* calls (undef on zigvm) — runnable
%% on the zigvm CLI. Runtime operands are routed through the exported
%% ?MODULE:id/1 so constant folding cannot bypass the VM. A case returns the
%% atom `true` on success; the runner counts a case EQ only when BOTH VMs'
%% Suite:Case([]) return true.
-module(zigvm_iovec_SUITE).

-export([all/0,
         c_integer_lists/1, c_binary_lists/1, c_empty_lists/1,
         c_empty_binary_lists/1, c_mixed_lists/1, c_improper_lists/1,
         c_illegal_lists/1, c_direct_binary_arg/1, c_idempotence/1,
         c_correctness/1, c_cons_bomb/1, c_iolist_size/1, c_list_to_binary/1,
         c_merge/1,
         id/1]).

%% The suite manifest (common_test all/0 contract). MIRRORED in order by
%% harness/suite_runner.ml's iovec-suite spec case_names (ncases/1 lockstep).
all() ->
    [c_integer_lists, c_binary_lists, c_empty_lists, c_empty_binary_lists,
     c_mixed_lists, c_improper_lists, c_illegal_lists, c_direct_binary_arg,
     c_idempotence, c_correctness, c_cons_bomb, c_iolist_size,
     c_list_to_binary, c_merge].

%% Identity through an exported call — the compiler cannot constant-fold across
%% it, so seed values genuinely travel through the VM's iolist machinery.
id(X) -> X.

%% --- integer_lists: structurally-different iolists of the SAME bytes reduce to
%% the same iovec (proven by iolist_to_binary equality), and that equals the
%% flat concatenation of the source bytes. Mirrors integer_lists' equivalence.
c_integer_lists(_) ->
    Base = id([1, 2, 3, 4, 5]),
    Flat = Base,
    Nested = [[1, [2, 3]], [4], 5],
    Nasty = [[[1], 2], [[3, [4]], 5]],
    Want = <<1, 2, 3, 4, 5>>,
    all_equal_iovec([Flat, Nested, Nasty], Want).

%% --- binary_lists: iolists whose leaves are whole binaries. Every structural
%% variation flattens to the same bytes. Mirrors binary_lists.
c_binary_lists(_) ->
    Flat = [id(<<1>>), <<2>>, <<3>>, <<4>>],
    Nested = [[<<1>>, [<<2>>, <<3>>]], [<<4>>]],
    Nasty = [[[<<1>>], <<2>>], [[<<3>>], <<4>>]],
    Want = <<1, 2, 3, 4>>,
    all_equal_iovec([Flat, Nested, Nasty], Want).

%% --- empty_lists: a list of empty lists reduces to the empty iovec []; and
%% iolist_to_iovec([]) =:= []. Mirrors empty_lists.
c_empty_lists(_) ->
    V = [id([]), [], [], []],
    (erlang:iolist_to_iovec(V) =:= [])
        andalso (erlang:iolist_to_iovec(id([])) =:= [])
        andalso (iolist_to_binary(erlang:iolist_to_iovec(V)) =:= <<>>).

%% --- empty_binary_lists: a list of empty binaries also reduces to []. Mirrors
%% empty_binary_lists (bounded to a modest count under the virtual clock).
c_empty_binary_lists(_) ->
    V = [id(<<>>) || _ <- seq(64)],
    (erlang:iolist_to_iovec(V) =:= [])
        andalso (erlang:iolist_to_iovec(id(<<>>)) =:= []).

%% --- mixed_lists: empties, integer runs, and binaries interleaved flatten to
%% the concatenation in order. Mirrors mixed_lists.
c_mixed_lists(_) ->
    V = [id(<<>>), [1, 2, 3, 4], <<12, 45, 78>>, [], <<>>, [5, 6]],
    Want = <<1, 2, 3, 4, 12, 45, 78, 5, 6>>,
    iolist_to_binary(erlang:iolist_to_iovec(V)) =:= Want.

%% --- improper_lists: improper tails (a binary in the cons tail position) are
%% legal iolists and flatten in order. Mirrors improper_lists.
c_improper_lists(_) ->
    V1 = [[[[1 | <<2>>] | <<3>>] | <<4>>] | <<5>>],
    V2 = [[<<1>>, 2] | <<3, 4, 5>>],
    V3 = [1, 2, 3 | <<4, 5>>],
    (iolist_to_binary(erlang:iolist_to_iovec(id(V1))) =:= <<1, 2, 3, 4, 5>>)
        andalso (iolist_to_binary(erlang:iolist_to_iovec(id(V2))) =:= <<1, 2, 3, 4, 5>>)
        andalso (iolist_to_binary(erlang:iolist_to_iovec(id(V3))) =:= <<1, 2, 3, 4, 5>>).

%% --- illegal_lists: iolist_to_iovec REJECTS non-iodata with badarg — a
%% bitstring leaf (non-byte-aligned), an out-of-range integer (>255), an atom,
%% and an illegal (bitstring) improper tail. Mirrors illegal_lists. Bare-reason
%% try/catch (no {'EXIT',...} catch-wrap, no stacktrace shape).
c_illegal_lists(_) ->
    rejects([id(1), <<1:1>>])          %% bitstring leaf
        andalso rejects([id(1), 890])  %% integer out of 0..255
        andalso rejects([gurka, id(1)])%% atom leaf
        andalso rejects(["gaffel" | <<1:1>>]). %% bitstring improper tail

%% --- direct_binary_arg: a whole binary argument flattens to a singleton
%% iovec; <<>> to []; a bitstring argument is badarg. Mirrors direct_binary_arg
%% (bitstring reason asserted BARE, not as a catch-wrapped {'EXIT',_}).
c_direct_binary_arg(_) ->
    (erlang:iolist_to_iovec(id(<<1>>)) =:= [<<1>>])
        andalso (erlang:iolist_to_iovec(id(<<>>)) =:= [])
        andalso (iolist_to_binary(erlang:iolist_to_iovec(id(<<7, 8, 9>>))) =:= <<7, 8, 9>>)
        andalso rejects(id(<<1:1>>)).

%% --- iolist_to_iovec_idempotence: the output of iolist_to_iovec is already an
%% iovec, so a second pass is a no-op. Mirrors iolist_to_iovec_idempotence.
c_idempotence(_) ->
    V = id([[1, 2, 3], [<<4>>, 5], [[6]], <<7, 8>>]),
    O = erlang:iolist_to_iovec(V),
    O =:= erlang:iolist_to_iovec(O).

%% --- iolist_to_iovec_correctness: the flattened iovec carries exactly the same
%% bytes as iolist_to_binary of the input. Mirrors iolist_to_iovec_correctness.
c_correctness(_) ->
    V = id([[1, 2, 3], [<<4>>, 5], [[6]], <<7, 8>>, [], <<>>]),
    iolist_to_binary(erlang:iolist_to_iovec(V)) =:= iolist_to_binary(V).

%% --- cons_bomb: a deeply-repeated nested structure still flattens correctly
%% (bounded depth/width under the virtual clock; the real suite's 16x blow-up is
%% shrunk to a deterministic, quick fixed shape). Mirrors cons_bomb's intent.
c_cons_bomb(_) ->
    Base = id([1, 2, 3]),
    Layer1 = [Base || _ <- seq(8)],
    Layer2 = [Layer1 || _ <- seq(8)],
    Once = iolist_to_binary(Layer2),
    iolist_to_binary(erlang:iolist_to_iovec(Layer2)) =:= Once.

%% --- iolist_size: iolist_size/1 counts bytes over nested lists, integers, and
%% whole binaries — and agrees with byte_size(iolist_to_binary(_)).
c_iolist_size(_) ->
    V = id([<<1, 2, 3>>, 4, [5, <<6, 7>>], [[8]], []]),
    (iolist_size(V) =:= 8)
        andalso (iolist_size(id([])) =:= 0)
        andalso (iolist_size(id(<<9, 9, 9>>)) =:= 3)
        andalso (iolist_size(V) =:= byte_size(iolist_to_binary(V))).

%% --- list_to_binary: list_to_binary/1 flattens an iolist to one binary
%% (offset-0 binaries only), agreeing with iolist_to_binary. Anchors the
%% concatenation law the iovec cases lean on.
c_list_to_binary(_) ->
    V = id([[1, 2], <<3, 4>>, [[5], 6], <<7>>]),
    (list_to_binary(V) =:= <<1, 2, 3, 4, 5, 6, 7>>)
        andalso (list_to_binary(V) =:= iolist_to_binary(V)).

%% --- merge: adjacent binary fragments in the input are coalesced by
%% iolist_to_iovec, but the reconstructed bytes are invariant (both VMs merge
%% identically, so iolist_to_binary of the result is stable regardless of how
%% many output fragments each VM emits).
c_merge(_) ->
    V = id([<<1>>, <<2>>, <<3>>, [<<4>>, <<5>>], <<6>>]),
    O = erlang:iolist_to_iovec(V),
    is_list(O) andalso (iolist_to_binary(O) =:= <<1, 2, 3, 4, 5, 6>>).

%% --- local helpers (self-contained; no lists:* to load) ---------------------

%% seq(N) -> [1, 2, ..., N]  (lists:seq/2 replacement).
seq(N) -> seq(N, []).
seq(0, Acc) -> Acc;
seq(N, Acc) when N > 0 -> seq(N - 1, [N | Acc]).

%% Each structural variation flattens (via iolist_to_iovec) to the same Want
%% bytes — the suite's equivalence check that differently-shaped iolists of the
%% same content reduce identically.
all_equal_iovec(Variations, Want) ->
    each_equal(Variations, Want).

each_equal([], _Want) -> true;
each_equal([V | T], Want) ->
    case iolist_to_binary(erlang:iolist_to_iovec(V)) =:= Want of
        true -> each_equal(T, Want);
        false -> false
    end.

%% rejects(X): iolist_to_iovec(X) must raise error:badarg. Bare reason only.
rejects(X) ->
    try erlang:iolist_to_iovec(X) of
        _ -> false
    catch
        error:badarg -> true
    end.
