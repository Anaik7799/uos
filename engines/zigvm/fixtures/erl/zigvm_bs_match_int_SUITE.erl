%% Curated PURE subset of erts/emulator/test/bs_match_int_SUITE.erl (E7 suite
%% closure). The real suite exercises bit-syntax INTEGER MATCHING: unsigned/
%% signed fields, big/little endian, non-byte sizes, unaligned offsets, dynamic
%% sizes, unit factors, bignum-sized fields, and match-failure fallthrough —
%% driven by rand-seeded roundtrips, md5 corpora, huge (2^27-bit) binaries and
%% ct hooks. These cases MIRROR the same groups (integer, mixed_sizes,
%% signed_integer, dynamic, mml, bignum, unaligned_32_bit, unit) as
%% self-contained BOOLEAN assertions over DETERMINISTIC data. Every matched
%% binary and every dynamic size is routed through the EXPORTED ?MODULE:id/1 —
%% an external call erlc cannot inline or constant-fold — so the RUNTIME
%% bs_start_match/bs_get_integer/bs_skip/bs_test_tail kernels are exercised,
%% not the compiler's folder. Match failure is expressed as case-clause
%% fallthrough (no exceptions, per the E1 catch-shape divergence). No ct/port/
%% node/rand/md5/io dependency, no huge allocations — runnable directly on the
%% zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_bs_match_int_SUITE).
-export([all/0, id/1, c_integer/1, c_mixed_sizes/1, c_signed/1,
         c_signed_nonbyte/1, c_little/1, c_dynamic/1, c_skip_tail/1,
         c_match_fail/1, c_mml/1, c_bignum/1, c_unit/1, c_unaligned/1]).

all() ->
    [c_integer, c_mixed_sizes, c_signed, c_signed_nonbyte, c_little,
     c_dynamic, c_skip_tail, c_match_fail, c_mml, c_bignum, c_unit,
     c_unaligned].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants (erlc cannot fold across
%% an exported call — the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

%% integer/1: unsigned big-endian extraction at byte and near-word sizes,
%% using the suite's own constants (42, 256, 65534, 16776455, 4245492555,
%% 4294967295, and the cafe/beef/feed probes at 57..64 bits, which cross the
%% small/big boundary at 2^59).
c_integer(_) ->
    <<I8:8>> = ?MODULE:id(<<42>>),
    <<I16:16>> = ?MODULE:id(<<1,0>>),
    <<J16:16>> = ?MODULE:id(<<255,254>>),
    <<I24:24>> = ?MODULE:id(<<255,253,7>>),
    <<I32:32>> = ?MODULE:id(<<253,13,19,75>>),
    <<M32:32>> = ?MODULE:id(<<255,255,255,255>>),
    <<I57:57>> = ?MODULE:id(<<16#1cafebeeffeed42:57>>),
    <<I59:59>> = ?MODULE:id(<<16#7cafebeeffeed42:59>>),
    <<I64:64>> = ?MODULE:id(<<16#cafebeeffeedface:64>>),
    (I8 =:= 42) andalso (I16 =:= 256) andalso (J16 =:= 65534)
        andalso (I24 =:= 16776455) andalso (I32 =:= 4245492555)
        andalso (M32 =:= 4294967295)
        andalso (I57 =:= 16#1cafebeeffeed42)
        andalso (I59 =:= 16#7cafebeeffeed42)
        andalso (I64 =:= 16#cafebeeffeedface).

%% mixed_sizes/1: several fields of different (non-byte) widths packed into one
%% bitstring, including a literal 1:1 marker field and a big/little mix —
%% construction and matching must be mutually inverse, and each extracted
%% field must equal the value packed in (the deterministic_mixed shapes).
%% c_mixed_sizes RE-ADDED (bs-little-oddsize fix, 2026-07-23): odd-size
%% little-endian matching now follows the erts 8k+r layout. DIVERGENT->EQ.
c_mixed_sizes(_) ->
    <<A1:9,1:1,B1:6>> = ?MODULE:id(<<345:9,1:1,42:6>>),
    <<A2:16,B2:16,C2:32,D2:22,E2:2>> =
        ?MODULE:id(<<27033:16,59991:16,16#c001cafe:32,12345:22,2:2>>),
    <<A3:7/little,B3:8/big,C3:15/little,_:3,D3:17/little,E3:23/big>> =
        ?MODULE:id(<<79:7/little,153:8/big,17555:15/little,0:3,
                     50000:17/little,777000:23/big>>),
    ({A1,B1} =:= {345,42})
        andalso ({A2,B2,C2,D2,E2} =:= {27033,59991,16#c001cafe,12345,2})
        andalso ({A3,B3,C3,D3,E3} =:= {79,153,17555,50000,777000}).
%% signed_integer/1: lifted verbatim — sint/1's case falls through to a
%% {no_match,Bin} tuple when neither signed-8 clause applies.
c_signed(_) ->
    ({no_match,<<>>} =:= sint(?MODULE:id(<<>>)))
        andalso ({no_match,<<1,2,3>>} =:= sint(?MODULE:id(<<1,2,3>>)))
        andalso (127 =:= sint(?MODULE:id(<<127>>)))
        andalso (-1 =:= sint(?MODULE:id(<<255>>)))
        andalso (-128 =:= sint(?MODULE:id(<<128>>)))
        andalso (42 =:= sint(?MODULE:id(<<42,255>>)))
        andalso (127 =:= sint(?MODULE:id(<<127,255>>))).

sint(Bin) ->
    case Bin of
        <<I:8/signed>> -> I;
        <<I:8/signed,_:3,_:5>> -> I;
        Other -> {no_match,Other}
    end.

%% Signed extraction at NON-BYTE sizes (the get_signed_big ladder in
%% miniature): the sign bit is the top bit of the field, not of the byte.
%% Negative expectations are packed as their explicit two's-complement bit
%% patterns (127:7 = -1, 3996:12 = -100, 6:3 = -2, 25:5 = -7), so the match
%% side alone performs the sign extension under test.
c_signed_nonbyte(_) ->
    <<A:7/signed>> = ?MODULE:id(<<127:7>>),
    <<B:12/signed>> = ?MODULE:id(<<3996:12>>),
    <<C:5/signed>> = ?MODULE:id(<<15:5>>),
    <<D:3/signed,E:5/signed>> = ?MODULE:id(<<6:3,25:5>>),
    %% 57-bit signed: |value| must stay under 2^56; encode 2^57 - |V57|.
    V57 = ?MODULE:id((1 bsl 55) + 12345),
    Enc57 = ?MODULE:id((1 bsl 57) - V57),
    <<F:57/signed>> = ?MODULE:id(<<Enc57:57>>),
    (A =:= -1) andalso (B =:= -100) andalso (C =:= 15)
        andalso (D =:= -2) andalso (E =:= -7)
        andalso (F =:= -V57).

%% Little-endian extraction (the get_unsigned_little/get_signed_little
%% ladders): byte order reverses on byte-sized fields (concrete cross-endian
%% constants), and non-byte little fields roundtrip through construction.
c_little(_) ->
    <<L16:16/little>> = ?MODULE:id(<<258:16>>),        % bytes <<1,2>> -> 513
    <<L24:24/little>> = ?MODULE:id(<<1,2,3>>),         % 3*65536+2*256+1
    <<SL:16/signed-little>> = ?MODULE:id(<<255,255>>), % -1
    V = ?MODULE:id(3000),
    <<R13:13/little>> = ?MODULE:id(<<V:13/little>>),
    W = ?MODULE:id(-12345),
    <<R21:21/signed-little>> = ?MODULE:id(<<W:21/signed-little>>),
    (L16 =:= 513) andalso (L24 =:= 197121) andalso (SL =:= -1)
        andalso (R13 =:= V) andalso (R21 =:= W).

%% dynamic/1: sizes held in RUNTIME variables (id-routed). The dyn_all walk
%% mirrors the suite's dynamic/5 loop over an all-ones binary: for every
%% split S1+S2 = 16 both fields must equal their all-ones expectation
%% ((1 bsl S)-1), matched via bound-variable segments with variable sizes.
c_dynamic(_) ->
    Bin = ?MODULE:id(<<16#ABCDEF:24>>),
    N = ?MODULE:id(11),
    M = ?MODULE:id(13),
    <<A:N,B:M>> = Bin,
    Full = ?MODULE:id(16#ABCDEF),
    (A =:= (Full bsr 13))
        andalso (B =:= (Full band ((1 bsl 13) - 1)))
        andalso dyn_all(?MODULE:id(<<255,255>>), 16).

dyn_all(Bin, S1) when S1 >= 0 ->
    S2 = 16 - S1,
    A = (1 bsl S1) - 1,
    B = (1 bsl S2) - 1,
    case Bin of
        <<A:S1,B:S2>> -> dyn_all(Bin, S1 - 1);
        _ -> false
    end;
dyn_all(_Bin, S1) when S1 < 0 -> true.

%% Skip patterns (_:N) and tail matching (/binary, /bits): skipped bits are
%% consumed exactly, the byte tail is the remaining suffix, and a bit tail
%% carries the precise remaining bit count.
%% c_skip_tail RE-ADDED (bs-unaligned-tail fix, 2026-07-23): both bugs fixed —
%% (a) fused bs_match ensure_at_least now uses the erts NumBits+Unit-divisibility
%% semantics (was stride*unit over-demand) and the epilogue no longer clobbers a
%% get_tail dst that IS the ctx register; (b) bit_size/byte_size of a match
%% context now answer with the REMAINING view. DIVERGENT->EQ.
c_skip_tail(_) ->
    <<_:8,X:8,Rest/binary>> = ?MODULE:id(<<1,2,3,4>>),
    <<_:3,Y:5,T/bits>> = ?MODULE:id(<<255,255>>),
    <<_:12,Z:4>> = ?MODULE:id(<<16#ABCD:16>>),
    (X =:= 2) andalso (Rest =:= <<3,4>>)
        andalso (Y =:= 31) andalso (bit_size(T) =:= 8) andalso (T =:= <<255>>)
        andalso (Z =:= 16#D).
%% Match failure -> NEXT case clause (no exception): a 24-bit binary fails the
%% 32-bit clause and lands in the 16+8 clause; the empty and non-byte
%% bitstring inputs fall through to their own clauses (fun_clause/mml spirit
%% without relying on the catch-wrap shape).
c_match_fail(_) ->
    (fallthrough(?MODULE:id(<<1,2,3>>)) =:= {sixteen_plus,258,3})
        andalso (fallthrough(?MODULE:id(<<7>>)) =:= {eight,7})
        andalso (fallthrough(?MODULE:id(<<>>)) =:= empty)
        andalso (fallthrough(?MODULE:id(<<1:1>>)) =:= other)
        andalso (sint(?MODULE:id(<<9,9,9>>)) =:= {no_match,<<9,9,9>>}).

fallthrough(Bin) ->
    case Bin of
        <<A:32>> -> {thirtytwo,A};
        <<A:16,B:8>> -> {sixteen_plus,A,B};
        <<A:8>> -> {eight,A};
        <<>> -> empty;
        _ -> other
    end.

%% mml/1: lifted verbatim — first-clause-wins between a whole-byte match and
%% a byte-plus-tail match.
c_mml(_) ->
    (mml_choose(?MODULE:id(<<42>>)) =:= single_byte_binary)
        andalso (mml_choose(?MODULE:id(<<42,43>>)) =:= multi_byte_binary).

mml_choose(<<_A:8>>) -> single_byte_binary;
mml_choose(<<_A:8,_T/binary>>) -> multi_byte_binary.

%% bignum/1 (bounded): fields wider than 64 bits extract exact bignums; the
%% 64-bit little-signed boundary values (2^63-1 and -2^63) roundtrip exactly
%% (the ERL-1391 probes, deterministic subset).
c_bignum(_) ->
    <<I80:80>> = ?MODULE:id(<<0:16,16#cafebeeffeedface:64>>),
    V = ?MODULE:id((1 bsl 100) + 12345),
    <<J:112>> = ?MODULE:id(<<V:112>>),
    MPos = ?MODULE:id((1 bsl 63) - 1),
    MNeg = ?MODULE:id(-(1 bsl 63)),
    <<P:64/integer-little-signed>> = ?MODULE:id(<<MPos:64/integer-little-signed>>),
    <<Q:64/integer-little-signed>> = ?MODULE:id(<<MNeg:64/integer-little-signed>>),
    (I80 =:= 16#cafebeeffeedface) andalso (J =:= V)
        andalso (P =:= MPos) andalso (Q =:= MNeg).

%% unit/1 (GH-6732): size*unit factoring — 5 units of 8 bits and 8 units of
%% 5 bits both denote a 40-bit field; plus a runtime-size unit match.
c_unit(_) ->
    <<V1:5/integer-unit:8>> = ?MODULE:id(<<16#cafebeef:5/integer-unit:8>>),
    <<V2:8/integer-unit:5>> = ?MODULE:id(<<16#cafebeef:8/integer-unit:5>>),
    N = ?MODULE:id(5),
    <<V3:N/unit:8>> = ?MODULE:id(<<16#cafebeef:40>>),
    (V1 =:= 16#cafebeef) andalso (V2 =:= 16#cafebeef)
        andalso (V3 =:= 16#cafebeef).

%% unaligned_32_bit/1 (bounded): a 32-bit field extracted at every non-zero
%% bit offset 1..7 must reproduce the value packed at that offset.
c_unaligned(_) ->
    <<_:3,U:32,Pad:5>> = ?MODULE:id(<<7:3,16#deadbeef:32,9:5>>),
    (U =:= 16#deadbeef) andalso (Pad =:= 9)
        andalso unaligned_probe(?MODULE:id(16#cafe1234), 7).

unaligned_probe(_I, 0) -> true;
unaligned_probe(I, Off) when Off > 0 ->
    R = 8 - Off,
    case ?MODULE:id(<<0:Off,I:32,0:R>>) of
        <<0:Off,X:32,0:R>> when X =:= I ->
            unaligned_probe(I, Off - 1);
        _ ->
            false
    end.
