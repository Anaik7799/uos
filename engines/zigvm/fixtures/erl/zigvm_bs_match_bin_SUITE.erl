%% Curated PURE subset of erts/emulator/test/bs_match_bin_SUITE.erl (E7 suite
%% closure). The real suite exercises bit-syntax BINARY-FIELD MATCHING:
%% splitting at every byte/bit position, huge-size overflow fallthrough,
%% >4095-bit bs_match_string (GH-5871), match contexts in memory-backed X
%% registers, empty-binary heap reservation, small-bitstring heap reservation
%% (GH-7292), known-position extraction, and non-1/8 units (GH-10937) — driven
%% by rand bytes, erlang:md5 corpora, erts_debug:unaligned_bitstring, 2^27-bit
%% binaries and 1M-iteration loops. These cases MIRROR the same shapes
%% (byte_split_binary, bit_split_binary, match_huge_bin's overflow ladders,
%% bs_match_string_edge_case, contexts, empty_binary, small_bitstring,
%% known_position, units) as self-contained BOOLEAN assertions over
%% DETERMINISTIC data: seq-byte binaries replace rand/md5, an id-routed
%% <<0:3,B/binary,0:5>> re-extraction replaces erts_debug:unaligned_bitstring,
%% bounded 2^26..2^32 sizes replace the huge-binary ladders (overflow must
%% FALL THROUGH, never match), and fixed-vs-dynamic size agreement replaces
%% the GH-7292 random walk. Every match subject and every dynamic size is
%% routed through the EXPORTED ?MODULE:id/1 — an external call erlc cannot
%% inline or constant-fold — so the RUNTIME bs_start_match/bs_get_binary/
%% bs_skip/bs_test_tail/bs_match_string kernels are exercised, not the
%% compiler's folder. Match failure is expressed as case-clause fallthrough
%% (no exceptions, per the E1 catch-shape divergence). No ct/port/node/rand/
%% md5/erts_debug/io dependency, no huge allocations — runnable directly on
%% the zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_bs_match_bin_SUITE).
-export([all/0, id/1, c_byte_split/1, c_byte_split_unaligned/1, c_bit_split/1,
         c_size_from_prior/1, c_nested_rematch/1, c_tails/1, c_match_string/1,
         c_contexts/1, c_empty_binary/1, c_small_bitstring/1,
         c_known_position/1, c_overflow_sizes/1, c_units/1]).

all() ->
    [c_byte_split, c_byte_split_unaligned, c_bit_split, c_size_from_prior,
     c_nested_rematch, c_tails, c_match_string, c_contexts, c_empty_binary,
     c_small_bitstring, c_known_position, c_overflow_sizes, c_units].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants (erlc cannot fold across
%% an exported call — the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

%% mkseq(N): the deterministic stand-in for the real suite's
%% mkbin(lists:seq(...)) — an N-byte binary whose byte at index I is I, built
%% by runtime construction (no stdlib).
mkseq(N) -> mkseq(0, N).
mkseq(I, N) when I < N -> Rest = mkseq(I + 1, N), <<I:8, Rest/binary>>;
mkseq(_, _) -> <<>>.

%% byte_split_binary/1: split a seq-byte binary at EVERY byte position with
%% two dynamically-sized binary fields; each half must have the right size,
%% re-concatenate to the whole, and carry the right boundary bytes (checked
%% by dynamic-offset rematching of the extracted halves).
c_byte_split(_) ->
    B = mkseq(?MODULE:id(16)),
    byte_split(B, byte_size(B)).

byte_split(_B, Pos) when Pos < 0 -> true;
byte_split(B, Pos) ->
    Sz2 = byte_size(B) - Pos,
    case B of
        <<B1:Pos/binary, B2:Sz2/binary>> ->
            case split_ok(B, B1, B2, Pos) of
                true -> byte_split(B, Pos - 1);
                false -> false
            end;
        _ -> false
    end.

split_ok(B, B1, B2, Pos) ->
    (byte_size(B1) =:= Pos)
        andalso (<<B1/binary, B2/binary>> =:= B)
        andalso last_is(B1, Pos - 1)
        andalso first_is(B2, Pos, byte_size(B)).

%% Last byte of a seq-prefix is its index (rematch at a dynamic offset).
last_is(<<>>, _) -> true;
last_is(B1, Exp) ->
    P = byte_size(B1) - 1,
    <<_:P/binary, L:8>> = B1,
    L =:= Exp.

%% First byte of a seq-suffix at split Pos is Pos.
first_is(<<>>, Pos, Total) -> Pos =:= Total;
first_is(<<F:8, _/binary>>, Pos, _) -> F =:= Pos.

%% byte_split_binary/1 (unaligned leg): the real suite re-splits an
%% erts_debug-made unaligned sub-binary; here the unaligned subject is made
%% portably — the payload is packed between a 3-bit and a 5-bit pad, then a
%% binary field is extracted AT BIT OFFSET 3 and put through the same
%% every-position split.
c_byte_split_unaligned(_) ->
    Base = mkseq(?MODULE:id(8)),
    Padded = ?MODULE:id(<<0:3, Base/binary, 0:5>>),
    <<0:3, U:8/binary, 0:5>> = Padded,
    (U =:= Base) andalso byte_split(U, byte_size(U)).

%% bit_split_binary/1 (bounded): a 24-bit binary-unit:1 field extracted at
%% every bit offset 0..7 must agree with the integer field extracted at the
%% same offset AND with the arithmetic expectation from the full value —
%% three independent decodings of the same unaligned bits.
c_bit_split(_) ->
    Bin = ?MODULE:id(<<16#0123456789ABCDEF:64>>),
    Full = ?MODULE:id(16#0123456789ABCDEF),
    bit_probe(Bin, Full, 0).

bit_probe(_Bin, _Full, Off) when Off > 7 -> true;
bit_probe(Bin, Full, Off) ->
    N = ?MODULE:id(24),
    Aft = 64 - Off - N,
    <<_:Off, Out:N/binary-unit:1, _:Aft>> = Bin,
    <<OutInt:N>> = Out,
    <<_:Off, IntVal:N, _:Aft>> = Bin,
    Expected = (Full bsr Aft) band ((1 bsl N) - 1),
    case (OutInt =:= Expected) andalso (IntVal =:= Expected)
        andalso (byte_size(Out) =:= 3) of
        true -> bit_probe(Bin, Full, Off + 1);
        false -> false
    end.

%% Size from a prior field — the length-prefixed shape <<S:8,B:S/binary,...>>
%% (the overflow_huge_bin size-in-variable spirit at sane sizes), including a
%% zero-length field and a full TLV-style walk to the empty tail.
c_size_from_prior(_) ->
    {B1, R1} = lp(?MODULE:id(<<3, 10, 11, 12, 99, 100>>)),
    {B2, R2} = lp(?MODULE:id(<<0, 7>>)),
    Segs = walk(?MODULE:id(<<2, 1, 2, 0, 3, 7, 8, 9>>)),
    (B1 =:= <<10, 11, 12>>) andalso (R1 =:= <<99, 100>>)
        andalso (B2 =:= <<>>) andalso (R2 =:= <<7>>)
        andalso (Segs =:= [<<1, 2>>, <<>>, <<7, 8, 9>>]).

lp(<<S:8, B:S/binary, Rest/binary>>) -> {B, Rest}.

walk(<<S:8, B:S/binary, Rest/binary>>) -> [B | walk(Rest)];
walk(<<>>) -> [].

%% Nested rematching of extracted sub-binaries (the contexts/1 spirit):
%% a sized field and a tail are extracted, then REMATCHED — two levels deep —
%% and repeated variables assert the extractions agree across paths.
c_nested_rematch(_) ->
    Outer = ?MODULE:id(<<255, 16#DEADBEEF:32, 1, 2, 3, 4, 7>>),
    <<_:8, Sub:8/binary, Last:8>> = Outer,
    <<W:32, Sub2:4/binary>> = Sub,
    <<A:8, Rest2/binary>> = Sub2,
    <<B:16, C:8>> = Rest2,
    <<_:8, Tail/binary>> = Outer,
    <<W:32, Tail2/binary>> = Tail,
    <<A:8, _/binary>> = Tail2,
    (W =:= 16#DEADBEEF) andalso (A =:= 1) andalso (B =:= 515)
        andalso (C =:= 4) andalso (Last =:= 7)
        andalso (Tail2 =:= <<1, 2, 3, 4, 7>>).

%% _/binary and /bits tails: full-consumption, empty tails, a zero-size
%% binary field, a bit tail after a binary field, and the byte-divisibility
%% REJECTION of a /binary tail over a non-byte bitstring (fallthrough, no
%% exception).
c_tails(_) ->
    <<_:2/binary, R1/binary>> = ?MODULE:id(<<1, 2, 3, 4, 5>>),
    <<_:5/binary, R2/binary>> = ?MODULE:id(<<1, 2, 3, 4, 5>>),
    <<A:8, _:0/binary, R3/binary>> = ?MODULE:id(<<9, 8, 7>>),
    <<_:1/binary, R4/bits>> = ?MODULE:id(<<1, 2, 3:2>>),
    NonByte = case ?MODULE:id(<<1, 2, 3:2>>) of
                  <<_:8, _/binary>> -> false;
                  _ -> true
              end,
    (R1 =:= <<3, 4, 5>>) andalso (R2 =:= <<>>)
        andalso (A =:= 9) andalso (R3 =:= <<8, 7>>)
        andalso (bit_size(R4) =:= 10) andalso (R4 =:= <<2, 3:2>>)
        andalso NonByte.

%% bs_match_string_edge_case/1 in miniature: literal string prefixes with
%% binary tails, and the extracted tail rematched against a further literal —
%% the repeated Tail1 asserts both decompositions agree.
c_match_string(_) ->
    Bin = ?MODULE:id(<<"hello world">>),
    <<"hello", Tail0/binary>> = Bin,
    <<"hello ", Tail1/binary>> = Bin,
    <<" ", Tail1/binary>> = ?MODULE:id(Tail0),
    (Tail0 =:= <<" world">>) andalso (Tail1 =:= <<"world">>).

%% contexts/1: every prefix length 0..12 of a seq binary is extracted with a
%% dynamic size, then re-identified by a 13-clause exact-size ladder (each
%% clause <<R:K/binary>> matches exactly one byte size, no tail).
c_contexts(_) ->
    Bytes = mkseq(?MODULE:id(12)),
    ctx_walk(Bytes, ?MODULE:id(12)).

ctx_walk(_Bytes, N) when N < 0 -> true;
ctx_walk(Bytes, N) ->
    <<B:N/binary, _/binary>> = Bytes,
    case (bin_ladder(B) =:= B) andalso (byte_size(B) =:= N) of
        true -> ctx_walk(Bytes, N - 1);
        false -> false
    end.

bin_ladder(Bin) ->
    case Bin of
        <<R:0/binary>> -> R;
        <<R:1/binary>> -> R;
        <<R:2/binary>> -> R;
        <<R:3/binary>> -> R;
        <<R:4/binary>> -> R;
        <<R:5/binary>> -> R;
        <<R:6/binary>> -> R;
        <<R:7/binary>> -> R;
        <<R:8/binary>> -> R;
        <<R:9/binary>> -> R;
        <<R:10/binary>> -> R;
        <<R:11/binary>> -> R;
        <<R:12/binary>> -> R
    end.

%% empty_binary/1 (single-shot): four zero-size fields (bits/bitstring/bytes/
%% bits spellings) matched out of <<>>, with repeated variables asserting they
%% are all the SAME empty bitstring; plus a zero-size binary field mid-match.
c_empty_binary(_) ->
    <<V1:0/bits, V1:0/bitstring, V2:0/bytes, V2:0/bits>> = ?MODULE:id(<<>>),
    <<E:0/binary, R/binary>> = ?MODULE:id(<<5, 6>>),
    (V1 =:= <<>>) andalso (V2 =:= <<>>) andalso (bit_size(V1) =:= 0)
        andalso (E =:= <<>>) andalso (R =:= <<5, 6>>).

%% small_bitstring/1 (deterministic): matching FIXED bitstring sizes must give
%% the same result as matching the same sizes as DYNAMIC (id-routed)
%% expressions — the GH-7292 shape at 3..15-bit and 63..65-bit widths.
c_small_bitstring(_) ->
    Bin = ?MODULE:id(<<16#0123456789ABCDEF:64, 16#FEDCBA9876543210:64>>),
    N7 = ?MODULE:id(7),
    <<A1:3/bits, A2:7/bits, A3:7/bits, A4:15/bits, _:32, As/binary>> = Bin,
    <<B1:(N7 - 4)/bits, B2:N7/bits, B3:N7/bits, B4:(N7 + N7 + 1)/bits,
      _:32, Bs/binary>> = Bin,
    N64 = ?MODULE:id(64),
    <<C1:63/bits, C2:65/bits, Cs/binary>> = Bin,
    <<D1:(N64 - 1)/bits, D2:(N64 + 1)/bits, Ds/binary>> = Bin,
    ({A1, A2, A3, A4, As} =:= {B1, B2, B3, B4, Bs})
        andalso (A1 =:= <<0:3>>)
        andalso ({C1, C2, Cs} =:= {D1, D2, Ds})
        andalso (Cs =:= <<>>)
        andalso (bit_size(C1) =:= 63).

%% known_position/1: lifted verbatim — an extracted binary field between a
%% known integer prefix and a literal char suffix.
c_known_position(_) ->
    <<Int:8, BitString:9/binary, $j:8>> = ?MODULE:id(<<42:8, "abcdefghij">>),
    (Int =:= 42) andalso (BitString =:= <<"abcdefghi">>).

%% match_huge_bin/1 (overflow legs, bounded): binary-field sizes that vastly
%% exceed the subject (2^30/2^32 bytes, 2^24 x unit:128) must FALL THROUGH to
%% the next clause — both as literals and as id-routed dynamic sizes — never
%% match, never raise.
c_overflow_sizes(_) ->
    Bin = ?MODULE:id(<<1, 2, 3, 4>>),
    Sz32 = ?MODULE:id(1 bsl 32),
    Sz26 = ?MODULE:id(1 bsl 26),
    Dyn1 = case Bin of
               <<_:Sz32/binary, _/binary>> -> false;
               _ -> true
           end,
    Dyn2 = case Bin of
               <<B0:Sz26/binary-unit:128, _/binary>> -> {false, B0};
               _ -> true
           end,
    (huge(Bin) =:= nomatch) andalso Dyn1 andalso (Dyn2 =:= true)
        andalso (huge(?MODULE:id(<<>>)) =:= nomatch).

huge(<<_:4294967296/binary, _/binary>>) -> a;                 % 1 bsl 32 bytes
huge(<<_:16777216/binary-unit:128, _/binary>>) -> b;          % 1 bsl 24 x 128
huge(<<B:1073741824/binary, _/binary>>) -> {c, B};            % 1 bsl 30 bytes
huge(_) -> nomatch.

%% units/1 (GH-10937): sized binary fields with unit 16/32 (including size
%% from a prior field), and unit-13/unit-16 TAIL divisibility — a
%% /binary-unit:U tail matches iff the remaining bit size is divisible by U
%% (non-binaries fall through to error).
c_units(_) ->
    <<U1:2/binary-unit:16, R/binary>> = ?MODULE:id(<<1, 2, 3, 4, 5>>),
    <<Sz:8, U2:Sz/binary-unit:32, R2/binary>> = ?MODULE:id(<<1, 9, 8, 7, 6, 42>>),
    (U1 =:= <<1, 2, 3, 4>>) andalso (R =:= <<5>>)
        andalso (Sz =:= 1) andalso (U2 =:= <<9, 8, 7, 6>>) andalso (R2 =:= <<42>>)
        andalso (u13(?MODULE:id(<<>>)) =:= ok)
        andalso (u13(?MODULE:id(<<42:13>>)) =:= ok)
        andalso (u13(?MODULE:id(<<67108863:26>>)) =:= ok)
        andalso (u13(?MODULE:id(<<"a">>)) =:= error)
        andalso (u13(?MODULE:id(<<"ab">>)) =:= error)
        andalso (u16(?MODULE:id(<<>>)) =:= ok)
        andalso (u16(?MODULE:id(<<"ab">>)) =:= ok)
        andalso (u16(?MODULE:id(<<"a">>)) =:= error)
        andalso (u16(?MODULE:id(<<"abc">>)) =:= error)
        andalso (u16(?MODULE:id(<<7:3>>)) =:= error)
        andalso (u16(?MODULE:id(nonbin)) =:= error).

u13(Bin) ->
    case Bin of
        <<_/binary-unit:13>> -> ok;
        _ -> error
    end.

u16(Bin) ->
    case Bin of
        <<_/binary-unit:16>> -> ok;
        _ -> error
    end.
