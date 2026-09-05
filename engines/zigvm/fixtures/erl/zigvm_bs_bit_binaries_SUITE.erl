%% Curated PURE subset of erts/emulator/test/bs_bit_binaries_SUITE.erl (E7
%% suite closure). The real suite (originally Per Gustafsson's) exercises
%% BIT-LEVEL BINARIES: construction/matching at odd bit_size values, bitstring
%% tails, asymmetric literal-vs-segment matches at small and ~900-bit widths,
%% bit_size/byte_size, list_to_bitstring/bitstring_to_list roundtrips, and
%% bit-at-a-time append loops. These cases MIRROR the same groups (misc,
%% horrid_match, test_bitstr, test_bit_size, asymmetric_tests,
%% big_asymmetric_tests, binary_to_and_from_list, big_binary_to_and_from_list,
%% append) as self-contained BOOLEAN assertions over DETERMINISTIC data, plus
%% the term-ORDER surface for bitstrings differing only in the final partial
%% byte (prefix-is-smaller, bitwise-lexicographic). Excluded: send_and_receive*
%% (process/message cases) and append's erts_debug:get_internal_state
%% allocation-exactness probe (Stratum-C internals, not term semantics).
%% Every match subject and constructed operand is routed through the EXPORTED
%% ?MODULE:id/1 — an external call erlc cannot inline or constant-fold — so
%% the RUNTIME bs_create_bin/bs_start_match/bs_get_binary/bs_test_tail kernels
%% are exercised, not the compiler's folder. No ct/port/node/io dependency —
%% runnable directly on the zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_bs_bit_binaries_SUITE).
-export([all/0, id/1, c_misc/1, c_horrid_match/1, c_bitstr_tail/1,
         c_bit_size/1, c_byte_size_rounding/1, c_asymmetric/1,
         c_big_asymmetric/1, c_bits_concat/1, c_compare_partial_byte/1,
         c_b2l_roundtrip/1, c_big_b2l/1, c_append_bits/1]).

all() ->
    [c_misc, c_horrid_match, c_bitstr_tail, c_bit_size, c_byte_size_rounding,
     c_asymmetric, c_big_asymmetric, c_bits_concat, c_compare_partial_byte,
     c_b2l_roundtrip, c_big_b2l, c_append_bits].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants (erlc cannot fold across
%% an exported call — the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

%% misc/1: a 100-bit value survives identity, and the match/match1 helpers
%% (odd runtime sizes 7/9 and little-endian 15/31, binary inside a list to
%% force a different instruction) all succeed.
c_misc(_) ->
    <<1:100>> = ?MODULE:id(<<1:100>>),
    match(7) andalso match(9) andalso match1(15) andalso match1(31).

match(N0) ->
    N = ?MODULE:id(N0),
    case ?MODULE:id(<<0:N>>) of
        <<0:N>> ->
            case ?MODULE:id(<<0:N, 0:1>>) of
                <<0:N, 0:1>> -> true;
                _ -> false
            end;
        _ -> false
    end.

match1(N0) ->
    N = ?MODULE:id(N0),
    case ?MODULE:id([<<42:N/little>>]) of
        [<<42:N/little>>] -> true;
        _ -> false
    end.

%% horrid_match/1: a 24-bit little-endian field extracted as a /bitstring
%% segment at a 4-bit offset is the exact 24-bit value.
c_horrid_match(_) ->
    <<1:4, B:24/bitstring>> = ?MODULE:id(<<1:4, 42:24/little>>),
    (B =:= <<42:24/little>>) andalso (bit_size(B) =:= 24).

%% test_bitstr/1: an unaligned /bitstring tail (after a 7-bit field) carries
%% the exact 9-bit suffix <<1:1,6>>.
c_bitstr_tail(_) ->
    <<1:7, B/bitstring>> = ?MODULE:id(<<1:7, <<1:1, 6>>/bitstring>>),
    (B =:= <<1:1, 6>>) andalso (bit_size(B) =:= 9).

%% test_bit_size/1 (bounded): bit_size is exact at odd and large sizes
%% (the 2^28-bit BigBin probe is excluded as a memory case, per the suite's
%% own "only on computers with lots of memory" precedent).
c_bit_size(_) ->
    (bit_size(?MODULE:id(<<1:101>>)) =:= 101)
        andalso (bit_size(?MODULE:id(<<1:1001>>)) =:= 1001)
        andalso (bit_size(?MODULE:id(<<1:80>>)) =:= 80)
        andalso (bit_size(?MODULE:id(<<1:800>>)) =:= 800)
        andalso (bit_size(?MODULE:id(<<>>)) =:= 0)
        andalso (bit_size(?MODULE:id(<<0:7, 1:1, 7:3>>)) =:= 11).

%% byte_size on a bitstring rounds UP to the nearest whole byte.
c_byte_size_rounding(_) ->
    (byte_size(?MODULE:id(<<>>)) =:= 0)
        andalso (byte_size(?MODULE:id(<<0:1>>)) =:= 1)
        andalso (byte_size(?MODULE:id(<<0:7>>)) =:= 1)
        andalso (byte_size(?MODULE:id(<<0:8>>)) =:= 1)
        andalso (byte_size(?MODULE:id(<<0:9>>)) =:= 2)
        andalso (byte_size(?MODULE:id(<<1:101>>)) =:= 13)
        andalso (byte_size(?MODULE:id(<<1:801>>)) =:= 101).

%% asymmetric_tests/1: the same 12/26-bit strings built with different segment
%% splits are the SAME term (match both ways), and unbounded vs sized
%% /bitstring extraction agree on the 25-bit suffix.
c_asymmetric(_) ->
    R1 = case ?MODULE:id(<<0, 1:4>>) of <<1:12>> -> true; _ -> false end,
    R2 = case ?MODULE:id(<<1:12>>) of <<0, 1:4>> -> true; _ -> false end,
    <<1:1, X/bitstring>> = ?MODULE:id(<<128, 255, 0, 0:2>>),
    <<1:1, X1:25/bitstring>> = ?MODULE:id(<<128, 255, 0, 0:2>>),
    R1 andalso R2
        andalso (X =:= <<1, 254, 0, 0:1>>)
        andalso (X1 =:= <<1, 254, 0, 0:1>>)
        andalso (X =:= X1)
        andalso (bit_size(X) =:= 25).

%% big_asymmetric_tests/1: the same shapes pushed past heap-binary sizes with
%% an 875-bit prefix/suffix (887- and 901-bit strings).
c_big_asymmetric(_) ->
    R1 = case ?MODULE:id(<<1:875, 0, 1:4>>) of
             <<1:875, 1:12>> -> true;
             _ -> false
         end,
    R2 = case ?MODULE:id(<<1:875, 1:12>>) of
             <<1:875, 0, 1:4>> -> true;
             _ -> false
         end,
    <<1:1, X/bitstring>> = ?MODULE:id(<<128, 255, 0, 0:2, 1:875>>),
    <<1:1, X1:900/bitstring>> = ?MODULE:id(<<128, 255, 0, 0:2, 1:875>>),
    R1 andalso R2
        andalso (X =:= <<1, 254, 0, 0:1, 1:875>>)
        andalso (X1 =:= X)
        andalso (bit_size(X) =:= 900).

%% <<B1/bits,B2/bits>> concatenation of odd-size runtime bitstrings: sizes
%% add, bit order is left-to-right, and 3+5 bits fuse into one exact byte.
c_bits_concat(_) ->
    B1 = ?MODULE:id(<<5:3>>),
    B2 = ?MODULE:id(<<9:5>>),
    C = <<B1/bits, B2/bits>>,
    B3 = ?MODULE:id(<<16#ABC:12>>),
    D = <<C/bits, B3/bits>>,
    (C =:= <<5:3, 9:5>>) andalso (C =:= <<169>>)
        andalso (bit_size(C) =:= 8)
        andalso (<<B2/bits, B1/bits>> =:= <<77>>)
        andalso (D =:= <<169, 16#ABC:12>>)
        andalso (bit_size(D) =:= 20).

%% Term ORDER over bitstrings differing only in the final partial byte:
%% bitwise-lexicographic, a proper prefix is smaller, and equality is
%% bit-count-exact (<<2:2>> IS <<1:1,0:1>>, but <<1:1>> is NOT <<1:2>>).
c_compare_partial_byte(_) ->
    A = ?MODULE:id(<<1, 2, 3:3>>),
    B = ?MODULE:id(<<1, 2, 4:3>>),
    P = ?MODULE:id(<<1, 2>>),
    Q = ?MODULE:id(<<1, 2, 0:1>>),
    (A < B) andalso (B > A) andalso (A =/= B)
        andalso (P < Q) andalso (Q > P)
        andalso (?MODULE:id(<<2:2>>) =:= ?MODULE:id(<<1:1, 0:1>>))
        andalso (?MODULE:id(<<1:1>>) =/= ?MODULE:id(<<1:2>>))
        andalso (?MODULE:id(<<1:1>>) > ?MODULE:id(<<1:2>>))
        andalso (min(A, B) =:= A) andalso (max(A, B) =:= B).

%% binary_to_and_from_list/1: bitstring_to_list yields whole bytes plus one
%% final sub-byte bitstring; list_to_bitstring is its exact inverse and
%% accepts mixed byte/bitstring lists (bit-shifted reassembly).
c_b2l_roundtrip(_) ->
    (list_to_bitstring(bitstring_to_list(?MODULE:id(<<1, 2, 3, 4, 1:1>>)))
         =:= <<1, 2, 3, 4, 1:1>>)
        andalso (bitstring_to_list(?MODULE:id(<<1, 2, 3, 4, 1:1>>))
                     =:= [1, 2, 3, 4, <<1:1>>])
        andalso (list_to_bitstring(?MODULE:id([<<1:1>>, 1, 2, 3, 4]))
                     =:= <<1:1, 1, 2, 3, 4>>)
        andalso (bitstring_to_list(?MODULE:id(<<1:1, 1, 2, 3, 4>>))
                     =:= [128, 129, 1, 130, <<0:1>>]).

%% big_binary_to_and_from_list/1: the same roundtrip past heap-binary sizes
%% (801/833-bit strings), and the byte prefix of a long mixed bitstring.
c_big_b2l(_) ->
    Big = ?MODULE:id(<<1:800, 2, 3, 4, 1:1>>),
    (list_to_bitstring(bitstring_to_list(Big)) =:= Big)
        andalso (list_to_bitstring(?MODULE:id([<<1:801>>, 1, 2, 3, 4]))
                     =:= <<1:801, 1, 2, 3, 4>>)
        andalso prefix4(bitstring_to_list(?MODULE:id(<<1, 2, 3, 4, 1:800, 1:1>>))).

prefix4([1, 2, 3, 4 | _]) -> true;
prefix4(_) -> false.

%% append/1 (bounded, minus the erts_debug allocation probe): growing a
%% bitstring 1 and 2 bits at a time crosses every intermediate partial-byte
%% alignment; 64 one-bits equal <<-1:64/signed>> however they were appended,
%% and a 13-bit run is the exact 13-bit all-ones value.
c_append_bits(_) ->
    A = do_append(?MODULE:id(<<>>), 64),
    B = do_append2(?MODULE:id(<<>>), 32),
    T = do_append(?MODULE:id(<<>>), 13),
    (A =:= <<(-1):8/signed-unit:8>>) andalso (B =:= A)
        andalso (bit_size(A) =:= 64)
        andalso (T =:= <<8191:13>>) andalso (bit_size(T) =:= 13).

do_append(Bin, N) when N > 0 -> do_append(<<Bin/bits, 1:1>>, N - 1);
do_append(Bin, 0) -> Bin.

do_append2(Bin, N) when N > 0 -> do_append2(<<Bin/binary-unit:2, 3:2>>, N - 1);
do_append2(Bin, 0) -> Bin.
