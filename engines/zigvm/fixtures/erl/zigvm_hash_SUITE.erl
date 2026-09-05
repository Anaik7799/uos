%% Curated PURE subset of erts/emulator/test/hash_SUITE.erl (E7 suite closure).
%% The real suite pins EXACT phash/phash2 values (basic_test/phash2_test/
%% otp_7127/bit_level_binaries tables), compares against a reference
%% implementation (cmp_test), and measures spread — all of which are
%% HASH-CONSTANT-dependent and out of scope for zigvm (its phash2 is
%% documented as deterministic, in-range, and =:=-COHERENT, but NOT
%% bit-for-bit the erts constant table; see src/bifs/term_ops.zig).
%% These cases therefore mirror the suite's REPRESENTATION-INDEPENDENT
%% contracts only, which BOTH VMs must satisfy identically:
%%   - RANGE:     phash2(T) in [0, 2^27) and phash2(T, N) in [0, N)
%%                (test_range / phash2_test's Max discipline);
%%   - COHERENCE: T =:= T' implies phash2(T) =:= phash2(T'), across
%%                structurally-distinct RUNTIME constructions of the same
%%                value — integers vs arithmetic (otp_5292), binaries built
%%                differently and aligned-vs-unaligned sub-binaries
%%                (test_phash2_binary_aligned_and_unaligned_equal),
%%                bit-level bitstrings (bit_level_binaries' unaligned_sub_bitstr
%%                checks), lists/tuples/maps (phash2_test rows, large-map
%%                benchmarks), and deep composites.
%% NO specific hash value is ever asserted, and no hash DISTINCTNESS either
%% (collision patterns differ between hash functions). Excluded outright:
%% test_basic/test_cmp/test_spread (legacy phash constants + reference impl +
%% spread statistics), hash_zero (the OTP-27 -0.0/+0.0 equal-hash special
%% case), external pids/ports/refs/funs via binary_to_term, 4GB+/10MB+ bins,
%% md5_large, test_native_record (erts_debug), phash2(T,0) badarg (zigvm's
%% E1 catch model lands the bare reason, a documented divergence).
%% Operands are routed through the EXPORTED ?MODULE:id/1 so erlc cannot
%% constant-fold the constructions (see zigvm_big_SUITE c_bitwise_2pow).
%% No ct/port/node/file dependency — runnable directly on the zigvm CLI.
-module(zigvm_hash_SUITE).
-export([all/0, id/1, c_range_default/1, c_range_explicit/1,
         c_int_coherence/1, c_big_coherence/1, c_atom_coherence/1,
         c_float_coherence/1, c_binary_coherence/1, c_sub_binary_coherence/1,
         c_bit_level_coherence/1, c_list_coherence/1, c_tuple_coherence/1,
         c_map_coherence/1, c_deep_coherence/1]).

all() ->
    [c_range_default, c_range_explicit, c_int_coherence, c_big_coherence,
     c_atom_coherence, c_float_coherence, c_binary_coherence, c_sub_binary_coherence, c_bit_level_coherence, c_list_coherence,
     c_tuple_coherence, c_map_coherence, c_deep_coherence].

%% erlc cannot inline or constant-fold an external call, so id-routed
%% operands force the RUNTIME hash/constructor paths on both VMs.
id(X) -> X.

%% ---- shared helpers ------------------------------------------------------

%% The coherence contract under test: equal terms hash equal, in every range.
%% (Asserts =:= FIRST so a construction bug fails as term-inequality, not as
%% a mysterious hash mismatch.)
eqh(X, Y) ->
    (X =:= Y)
        andalso (erlang:phash2(X) =:= erlang:phash2(Y))
        andalso (erlang:phash2(X, 1 bsl 32) =:= erlang:phash2(Y, 1 bsl 32))
        andalso (erlang:phash2(X, 97) =:= erlang:phash2(Y, 97)).

%% phash2/1's documented default range is [0, 2^27).
in_default_range(T) ->
    H = erlang:phash2(T),
    is_integer(H) andalso (H >= 0) andalso (H < (1 bsl 27)).

in_range(T, N) ->
    H = erlang:phash2(T, N),
    is_integer(H) andalso (H >= 0) andalso (H < N).

all_default([]) -> true;
all_default([T | Ts]) -> in_default_range(T) andalso all_default(Ts).

all_ranges(_T, []) -> true;
all_ranges(T, [N | Ns]) -> in_range(T, N) andalso all_ranges(T, Ns).

all_terms_ranges([], _Ns) -> true;
all_terms_ranges([T | Ts], Ns) ->
    all_ranges(T, Ns) andalso all_terms_ranges(Ts, Ns).

%% One term of every hashable shape under test, all runtime-built.
terms() ->
    [id([]), id(abc), id(0), id(1), id(-1),
     id(1 bsl 20), id(-(1 bsl 20)),
     id(4294967296), id((1 bsl 200) + 7), id(-(1 bsl 100)),
     id(3.14), id(-3.14),
     id(<<>>), id(<<0:8>>), id(<<"abc">>), id(<<"12345678901234567890">>),
     id(<<0:7>>), id(<<5:3, "12345678901234567890">>),
     id([a, b, c]), id([a, b | c]), id("abc" ++ [1009]),
     id({}), id({a, 1, {}, 7.5}), id(#{}), id(#{a => 1, b => 2}),
     erlang:make_ref()].

app([], Ys) -> Ys;
app([X | Xs], Ys) -> [X | app(Xs, Ys)].

%% N bytes 0,1,2,...,255,0,... as a binary (forward bit-syntax accumulation).
mk_bytes(I, N, Acc) when I >= N -> Acc;
mk_bytes(I, N, Acc) -> mk_bytes(I + 1, N, <<Acc/binary, (I band 255):8>>).

%% ...and the same bytes as a list, for the list_to_binary route.
mk_byte_list(N, I) when I >= N -> [];
mk_byte_list(N, I) -> [I band 255 | mk_byte_list(N, I + 1)].

%% Map of K => K*K for K in 1..N, ascending vs descending insertion order.
mkmap_up(N, I, M) when I > N -> M;
mkmap_up(N, I, M) -> mkmap_up(N, I + 1, M#{I => I * I}).

mkmap_down(0, M) -> M;
mkmap_down(N, M) -> mkmap_down(N - 1, M#{N => N * N}).

%% ---- cases ---------------------------------------------------------------

%% test_range / phash2_test's Max: phash2/1 lands in its default [0, 2^27)
%% for every term shape.
c_range_default(_) ->
    all_default(terms()).

%% test_range: phash2(T, N) in [0, N) for ranges from 1 (forced 0) through
%% the maximum 2^32, powers of two and primes alike.
c_range_explicit(_) ->
    Ns = [id(1), id(2), id(3), id(7), id(97), id(256),
          id(1 bsl 16), id(1 bsl 27), id(1 bsl 32)],
    all_terms_ranges(terms(), Ns)
        %% range 1 admits only 0 — the one value the bound itself pins.
        andalso (erlang:phash2(id({a, b, c}), 1) =:= 0).

%% otp_5292 (integer hashing), coherence form: the same small integer built
%% by runtime arithmetic hashes identically to its direct construction.
c_int_coherence(_) ->
    eqh(id(2), id(1) + id(1))
        andalso eqh(id(-1), id(1) - id(2))
        andalso eqh(id(0), id(7) - id(7))
        andalso eqh(id(1 bsl 20), id(1 bsl 10) * id(1 bsl 10))
        andalso eqh(id(-(1 bsl 20)), id(0) - id(1 bsl 20)).

%% otp_5292 big fragment: bignums built via *, +, -, bsl routes hash equal,
%% including values that cross the small/big fixnum boundary (2^59).
c_big_coherence(_) ->
    eqh(id(1 bsl 64), id(1 bsl 32) * id(1 bsl 32))
        andalso eqh(id(4294967296), id(4294967295) + id(1))
        andalso eqh(id(1 bsl 59), (id(1 bsl 59) - id(1)) + id(1))
        andalso eqh(id(-(1 bsl 100)), id(0) - id(1 bsl 100))
        andalso eqh(id(1 bsl 200), id(1 bsl 120) * id(1 bsl 80)).

%% phash2_test atom rows, coherence form: the same atom reached via
%% list_to_atom / binary_to_atom hashes like its literal.
c_atom_coherence(_) ->
    eqh(id(abc), list_to_atom(id("abc")))
        andalso eqh(id(abc), binary_to_atom(id(<<"abc">>), utf8))
        andalso eqh(id(true), list_to_atom(id("true")))
        andalso eqh(id('a b'), list_to_atom(id("a b"))).

%% phash2_test float rows, coherence form: floats produced by runtime
%% arithmetic hash like their direct constructions. (-0.0/+0.0 hash_zero
%% special-casing deliberately NOT mirrored.)
c_float_coherence(_) ->
    eqh(id(1.5), id(3.0) / id(2.0))
        andalso eqh(id(2.0), id(1.0) + id(1.0))
        andalso eqh(id(0.5), id(1.0) / id(2.0))
        andalso eqh(id(-2.5), id(2.5) * id(-1.0))
        andalso eqh(id(7.5), id(2.5) * id(3.0)).

%% phash2_test binary rows + otp_7127, coherence form: the same bytes built
%% via literals, list_to_binary, binary append, split_binary, and byte-wise
%% bit-syntax accumulation (300 bytes: past OTP's 64-byte heap-bin ceiling,
%% so heap-bin and refc-bin representations must hash alike).
c_binary_coherence(_) ->
    B = id(<<"abc">>),
    {_, Tail} = split_binary(id(<<"xxabc">>), 2),
    Big1 = mk_bytes(0, 300, id(<<>>)),
    Big2 = list_to_binary(mk_byte_list(300, 0)),
    eqh(B, list_to_binary(id("abc")))
        andalso eqh(B, <<(id(<<"a">>))/binary, (id(<<"bc">>))/binary>>)
        andalso eqh(B, Tail)
        andalso eqh(id(<<"Scott9">>), <<(id(<<"Scott">>))/binary, $9:8>>)
        andalso eqh(Big1, Big2).

%% test_phash2_binary_aligned_and_unaligned_equal: an UNALIGNED sub-binary
%% (bit offset 3 into a padded carrier) and an aligned sub-binary both hash
%% exactly like the plain binary they denote.
%% c_sub_binary_coherence RE-ADDED (bs-unaligned-tail fix, 2026-07-23): the
%% incoherence was DOWNSTREAM of the fused bs_match ensure_at_least/get_tail
%% bugs (wrong extraction path) — with those fixed the unaligned sub-binary
%% hashes cohere. DIVERGENT->EQ.
c_sub_binary_coherence(_) ->
    Bin = mk_bytes(0, 40, id(<<>>)),
    %% aligned sub-binary: bytes 8..27 of a 40-byte carrier
    <<_:8/binary, AlignedSub:20/binary, _/binary>> = Bin,
    AlignedRef = mk_bytes(8, 28, id(<<>>)),
    %% unaligned sub-binary: same 40 bytes matched back out at bit offset 3
    Padded = <<0:3, Bin/binary, 0:5>>,
    <<_:3, Unaligned:40/binary, _:5>> = Padded,
    eqh(AlignedSub, AlignedRef)
        andalso eqh(Unaligned, Bin).
%% bit_level_binaries' unaligned_sub_bitstr discipline, coherence form:
%% bit-level bitstrings built directly, matched out of larger carriers, at
%% runtime-chosen sizes, or by bitstring append, hash like their value.
c_bit_level_coherence(_) ->
    %% <<255, 5:3>> minus its first byte is <<5:3>>
    <<_:8, D/bitstring>> = id(<<255, 5:3>>),
    %% the real suite's fun case: <<255, 7:3>> minus 4 bits is <<127:7>>
    <<_:4, D2/bitstring>> = id(<<255, 7:3>>),
    Sz = id(13),
    eqh(id(<<5:3>>), D)
        andalso eqh(id(<<127:7>>), D2)
        andalso eqh(id(<<1:13>>), <<1:Sz>>)
        andalso eqh(id(<<5:3, 3:2>>),
                    <<(id(<<5:3>>))/bitstring, (id(<<3:2>>))/bitstring>>).

%% phash2_test list rows, coherence form: proper, improper, and appended
%% lists built by different runtime routes hash like their values.
c_list_coherence(_) ->
    eqh(id([a, b, c]), [id(a) | id([b, c])])
        andalso eqh(id([a, b | c]), [id(a), id(b) | id(c)])
        andalso eqh(id("abc"), app(id("ab"), id("c")))
        andalso eqh(id("1234567890123456"),
                    app(id("12345678"), id("90123456")))
        andalso eqh(id([[], {}, <<>>]), [id([]), id({}) | id([<<>>])]).

%% phash2_test tuple rows, coherence form: tuples via list_to_tuple,
%% setelement (fresh-copy semantics), and make_tuple hash like literals.
c_tuple_coherence(_) ->
    eqh(id({}), list_to_tuple(id([])))
        andalso eqh(id({a, 1, [], 7.5}), list_to_tuple(id([a, 1, [], 7.5])))
        andalso eqh(id({1, 2, 3}), setelement(1, id({0, 2, 3}), id(1)))
        andalso eqh(id({x, x, x}), erlang:make_tuple(id(3), id(x))).

%% test_phash2_large_map's subject in coherence form: maps with the same
%% pairs hash equal REGARDLESS of insertion order — both under and over the
%% 32-key flatmap→hashmap threshold — and update-overwrite is coherent.
c_map_coherence(_) ->
    Ma = ((id(#{}))#{a => id(1)})#{b => id(2)},
    Mb = ((id(#{}))#{b => id(2)})#{a => id(1)},
    Mixed1 = ((((id(#{}))#{1 => id(a)})#{b => id(2)})
                  #{{c} => id([3])})#{<<"k">> => id(4.5)},
    Mixed2 = ((((id(#{}))#{<<"k">> => id(4.5)})#{{c} => id([3])})
                  #{b => id(2)})#{1 => id(a)},
    Up = mkmap_up(64, 1, id(#{})),
    Down = mkmap_down(64, id(#{})),
    eqh(Ma, Mb)
        andalso eqh(Ma, id(#{a => 1, b => 2}))
        andalso eqh((id(#{a => 0}))#{a => id(1)}, id(#{a => 1}))
        andalso eqh(Mixed1, Mixed2)
        andalso eqh(Up, Down).

%% phash2_test's composite rows, coherence form: one deep term containing
%% every shape, built literal-side vs constructor-side, hashes identically.
c_deep_coherence(_) ->
    <<_:8, Bits/bitstring>> = id(<<0, 7:3>>),
    T1 = id({abc, [1, 1 bsl 64], #{k => <<"v">>}, 3.5, <<7:3>>}),
    T2 = list_to_tuple(
           [list_to_atom(id("abc")),
            [id(1) | [id(1 bsl 32) * id(1 bsl 32)]],
            (id(#{}))#{k => list_to_binary(id("v"))},
            id(7.0) / id(2.0),
            Bits]),
    eqh(T1, T2).
