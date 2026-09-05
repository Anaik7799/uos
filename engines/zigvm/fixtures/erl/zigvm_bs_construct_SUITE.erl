%% Curated PURE subset of erts/emulator/test/bs_construct_SUITE.erl (E7 suite
%% closure). The real suite drives bit-syntax CONSTRUCTION through erl_eval
%% against compiled forms over a big ?T-table (test1..test5), plus targeted
%% cases (coerce_to_float, zero_width, little, floats, dynamic). These cases
%% MIRROR the pure algebraic core of that table as self-contained BOOLEAN
%% assertions: integer fields at byte and NON-byte sizes (1/3/4/7/12/13/33/39
%% bits), signed/unsigned via matching round-trips, big/little endianness
%% (including the multi-segment non-byte little probes lifted verbatim from
%% l/1), bignum operands truncated into 8..64-bit fields, unit sizes
%% (unit:2/unit:8/binary-unit:4), binary/bitstring fields, utf8/utf16/utf32
%% encodings, float fields (64/32, big/little, integer coercion), dynamic
%% sizes, zero-width segments, construction<->matching round-trips, and
%% byte_size/bit_size of the results. Expected byte vectors come from the real
%% suite's l/1 facit table or from the IEEE-754/UTF standards. All operands are
%% routed through the EXPORTED ?MODULE:id/1 so erlc cannot constant-fold the
%% construction — every case exercises the RUNTIME bs_* kernels. No ct/port/
%% node/file dependency, no float FORMATTING, no phash, no stacktraces —
%% runnable directly on the zigvm CLI.
-module(zigvm_bs_construct_SUITE).
-export([all/0, id/1, c_int_fields/1, c_big_fields/1, c_non_byte_sizes/1,
         c_unit_sizes/1, c_binary_fields/1, c_dynamic_sizes/1,
         c_signed_match/1, c_little_endian/1, c_utf8/1, c_utf16/1,
         c_utf32/1, c_float_fields/1, c_roundtrip/1]).

all() ->
    [c_int_fields, c_big_fields, c_non_byte_sizes, c_unit_sizes,
     c_binary_fields, c_dynamic_sizes, c_signed_match, c_little_endian,
     c_utf8, c_utf16, c_utf32, c_float_fields, c_roundtrip].

%% External call erlc cannot inline or constant-fold: forces the construction
%% below to run in the VM at runtime (the bs_construct_SUITE pattern is
%% id/1-routing every ?T operand through Vars for the erl_eval leg).
id(X) -> X.

%% test1/l: byte-aligned integer fields — value truncation to the field width
%% (<<-43>> and <<256*45+47>>), multi-segment ordering, 16-bit big vs little.
c_int_fields(_) ->
    A = ?MODULE:id(-43),
    B = ?MODULE:id(56),
    C = ?MODULE:id(777),
    D = ?MODULE:id(256 * 45 + 47),
    (<<A>> =:= <<213>>)
        andalso (<<B>> =:= <<56>>)
        andalso (<<(?MODULE:id(1)), (?MODULE:id(2))>> =:= <<1, 2>>)
        andalso (<<C:16/big>> =:= <<3, 9>>)
        andalso (<<C:16/little>> =:= <<9, 3>>)
        andalso (<<D>> =:= <<47>>)
        andalso (byte_size(<<C:16>>) =:= 2).

%% test1/l "different sizes": the I_big1 bignum truncated into 8..64-bit
%% fields (facit bytes lifted verbatim), value not bleeding into the previous
%% segment, and a 32-bit little slice of a bignum.
c_big_fields(_) ->
    IBig = ?MODULE:id(57285702734876389752897683),
    (<<IBig:8>> =:= <<147>>)
        andalso (<<IBig:16>> =:= <<0, 147>>)
        andalso (<<IBig:24>> =:= <<99, 0, 147>>)
        andalso (<<IBig:32>> =:= <<138, 99, 0, 147>>)
        andalso (<<IBig:48>> =:= <<229, 5, 138, 99, 0, 147>>)
        andalso (<<IBig:64>> =:= <<42, 249, 229, 5, 138, 99, 0, 147>>)
        andalso (<<1, IBig:8>> =:= <<1, 147>>)
        andalso (<<4, IBig:32>> =:= <<4, 138, 99, 0, 147>>)
        andalso (<<IBig:32/little>> =:= <<147, 0, 99, 138>>).

%% test1/l non-byte sizes + zero_width: 4+4, 1+6+1, 13-bit, and the 33/39-bit
%% bignum facit rows; zero-width segments vanish exactly.
c_non_byte_sizes(_) ->
    N4 = ?MODULE:id(4),
    N7 = ?MODULE:id(7),
    One = ?MODULE:id(1),
    Zero = ?MODULE:id(0),
    IBig = ?MODULE:id(57285702734876389752897683),
    Z = ?MODULE:id(57),
    (<<N4:4, N7:4>> =:= <<71>>)
        andalso (<<One:1, Zero:6, One:1>> =:= <<129>>)
        andalso (<<(?MODULE:id(4711)):13, (?MODULE:id(5876)):13,
                   (?MODULE:id(3)):6>>
                     =:= <<4711:13, 5876:13, 3:6>>)
        andalso (<<IBig:33>> =:= <<197, 49, 128, 73, 1:1>>)
        andalso (<<IBig:39>> =:= <<11, 20, 198, 1, 19:7>>)
        andalso (<<17, IBig:33>> =:= <<17, 197, 49, 128, 73, 1:1>>)
        andalso (<<Z:0>> =:= <<>>)
        andalso (bit_size(<<Z:0>>) =:= 0)
        andalso (<<Z:0, (?MODULE:id(5))>> =:= <<5>>)
        andalso (bit_size(<<N4:3>>) =:= 3).

%% test1/l unit sizes: integer unit:2/unit:8 padding, -1 sign-filling
%% 17 bytes, and the binary-unit:4 bitstring append row.
c_unit_sizes(_) ->
    A = ?MODULE:id(4),
    B = ?MODULE:id(5),
    M = ?MODULE:id(-1),
    Nib = ?MODULE:id(<<7:4>>),
    (<<A:8/unit:2, B:2/unit:8>> =:= <<0, 4, 0, 5>>)
        andalso (<<M:3/unit:8>> =:= <<255, 255, 255>>)
        andalso (byte_size(<<M:17/unit:8>>) =:= 17)
        andalso (all_ones_136(<<M:17/unit:8>>))
        andalso (<<42, Nib/binary-unit:4>> =:= <<42, 7:4>>).

all_ones_136(<<V:136>>) -> V =:= ((1 bsl 136) - 1);
all_ones_136(_) -> false.

%% test1/l binary/bitstring fields: whole-binary splice, sized binary slice,
%% mixed literal+binary segments, bitstring splice, and the
%% << <<153,27:5>>:13/bits, 1:3 >> facit row.
c_binary_fields(_) ->
    B12 = ?MODULE:id(<<1, 2>>),
    B53 = ?MODULE:id(<<5:3>>),
    S = ?MODULE:id(<<153, 27:5>>),
    I13 = ?MODULE:id(13),
    (<<B12/binary>> =:= <<1, 2>>)
        andalso (<<B12:1/binary>> =:= <<1>>)
        andalso (<<4, 3, B12:1/binary>> =:= <<4, 3, 1>>)
        andalso (<<B53/bitstring>> =:= <<5:3>>)
        andalso (bit_size(<<B53/bitstring>>) =:= 3)
        andalso (<<S:I13/bits, (?MODULE:id(1)):3>> =:= <<153, 217>>).

%% dynamic: field sizes are runtime values (id-routed), for integer fields,
%% integer fields with a unit, and sized binary slices.
c_dynamic_sizes(_) ->
    S = ?MODULE:id(4),
    N = ?MODULE:id(13),
    B = ?MODULE:id(<<1, 2, 3, 4>>),
    Sz = ?MODULE:id(2),
    (<<(?MODULE:id(7)):S, (?MODULE:id(4)):S>> =:= <<116>>)
        andalso (<<(?MODULE:id(4711)):N>> =:= <<4711:13>>)
        andalso (<<B:Sz/binary>> =:= <<1, 2>>)
        andalso (<<(?MODULE:id(5)):S/unit:2>> =:= <<5>>)
        andalso (bit_size(<<(?MODULE:id(0)):N>>) =:= 13).

%% construction is signedness-blind; signed/unsigned is a MATCHING property —
%% two's-complement round-trips at 12/16(little)/7 bits.
c_signed_match(_) ->
    Bin = <<(?MODULE:id(-5)):12>>,
    Bin2 = <<(?MODULE:id(-1000)):16/little>>,
    Bin3 = <<(?MODULE:id(-3)):7>>,
    (unsigned12(Bin) =:= 4091)
        andalso (signed12(Bin) =:= -5)
        andalso (signed16l(Bin2) =:= -1000)
        andalso (signed7(Bin3) =:= -3)
        andalso (Bin =:= <<4091:12>>).

unsigned12(<<V:12>>) -> V.
signed12(<<V:12/signed>>) -> V.
signed16l(<<V:16/little-signed>>) -> V.
signed7(<<V:7/signed>>) -> V.

%% little: byte-reversal at 32 bits plus the multi-segment NON-byte-aligned
%% little-endian facit rows lifted verbatim from l/1 (I_big1/I_13 operands).
%% c_little_endian RE-ADDED (bs-little-oddsize fix, 2026-07-23): odd-size
%% little-endian fields now follow the erts 8k+r layout (k LOW value bytes
%% first, then the HIGH r-bit fragment) in BOTH directions. DIVERGENT->EQ.
c_little_endian(_) ->
    X = ?MODULE:id(16#12345678),
    IBig = ?MODULE:id(57285702734876389752897683),
    I13 = ?MODULE:id(13),
    (<<X:32/big>> =:= <<16#12, 16#34, 16#56, 16#78>>)
        andalso (<<X:32/little>> =:= <<16#78, 16#56, 16#34, 16#12>>)
        andalso (<<IBig:16/little, I13:24/little>> =:= <<147, 0, 13, 0, 0>>)
        andalso (<<IBig:13/little, I13:3/little, IBig:16/little>>
                     =:= <<147, 5, 147, 0>>)
        andalso (<<0:5, IBig:16/little, I13:3/little>> =:= <<4, 152, 5>>).
%% utf8: 1/2/3/4-byte encodings (standard UTF-8 byte vectors), a decode
%% round-trip, and multi-segment utf8 text.
c_utf8(_) ->
    ((<<(?MODULE:id($a))/utf8>>) =:= <<97>>)
        andalso ((<<(?MODULE:id(16#7FF))/utf8>>) =:= <<223, 191>>)
        andalso ((<<(?MODULE:id(16#20AC))/utf8>>) =:= <<226, 130, 172>>)
        andalso ((<<(?MODULE:id(16#10348))/utf8>>) =:= <<240, 144, 141, 136>>)
        andalso (utf8_cp(<<(?MODULE:id(16#10348))/utf8>>) =:= 16#10348)
        andalso ((<<(?MODULE:id($a))/utf8, (?MODULE:id($p))/utf8,
                    (?MODULE:id($a))/utf8>>) =:= <<"apa">>)
        andalso (byte_size(<<(?MODULE:id(16#20AC))/utf8>>) =:= 3).

utf8_cp(<<C/utf8>>) -> C.

%% utf16: BMP code points big+little and a surrogate-pair (U+10437)
%% encode+decode round-trip (explicit endianness — no /native).
c_utf16(_) ->
    ((<<(?MODULE:id($a))/utf16>>) =:= <<0, 97>>)
        andalso ((<<(?MODULE:id($a))/utf16-little>>) =:= <<97, 0>>)
        andalso ((<<(?MODULE:id(16#442))/utf16>>) =:= <<4, 66>>)
        andalso ((<<(?MODULE:id(16#10437))/utf16>>) =:= <<216, 1, 220, 55>>)
        andalso ((<<(?MODULE:id(16#10437))/utf16-little>>)
                     =:= <<1, 216, 55, 220>>)
        andalso (utf16_cp(<<(?MODULE:id(16#10437))/utf16>>) =:= 16#10437)
        andalso (byte_size(<<(?MODULE:id(16#10437))/utf16>>) =:= 4).

utf16_cp(<<C/utf16>>) -> C.

%% utf32: fixed 4-byte encodings big+little and a decode round-trip
%% (explicit endianness — no /native).
c_utf32(_) ->
    ((<<(?MODULE:id($a))/utf32>>) =:= <<0, 0, 0, 97>>)
        andalso ((<<(?MODULE:id($a))/utf32-little>>) =:= <<97, 0, 0, 0>>)
        andalso ((<<(?MODULE:id(16#432))/utf32>>) =:= <<0, 0, 4, 50>>)
        andalso (utf32_cp(<<(?MODULE:id(16#10348))/utf32>>) =:= 16#10348)
        andalso (byte_size(<<(?MODULE:id(16#432))/utf32>>) =:= 4).

utf32_cp(<<C/utf32>>) -> C.

%% floats/coerce_to_float: IEEE-754 byte vectors for 32/64-bit fields
%% (big+little; facit rows 0.0/0.125 lifted from l/1), integer operands
%% coerced to float, and a 64-bit encode+decode round-trip. Binary IMAGES of
%% floats — no float-to-string formatting anywhere.
c_float_fields(_) ->
    Z = ?MODULE:id(0.0),
    F = ?MODULE:id(0.125),
    One = ?MODULE:id(1.0),
    G = ?MODULE:id(2.5),
    (<<Z:32/float>> =:= <<0, 0, 0, 0>>)
        andalso (<<F:32/float>> =:= <<62, 0, 0, 0>>)
        andalso (<<F:32/little-float>> =:= <<0, 0, 0, 62>>)
        andalso (<<One:64/float>> =:= <<63, 240, 0, 0, 0, 0, 0, 0>>)
        andalso (<<One:64/little-float>> =:= <<0, 0, 0, 0, 0, 0, 240, 63>>)
        andalso (<<(?MODULE:id(2)):64/float>> =:= <<(?MODULE:id(2.0)):64/float>>)
        andalso (f64(<<G:64/float>>) =:= 2.5)
        andalso (byte_size(<<G:32/float>>) =:= 4).

f64(<<V:64/float>>) -> V.

%% construction<->matching round-trip over a mixed-width segment stack
%% (7+9+16/little), plus byte_size rounding up for a 9-bit result.
c_roundtrip(_) ->
    A = ?MODULE:id(5),
    B = ?MODULE:id(300),
    C = ?MODULE:id(1234),
    Bin = <<A:7, B:9, C:16/little>>,
    (bit_size(Bin) =:= 32)
        andalso (byte_size(Bin) =:= 4)
        andalso (rt(Bin) =:= {A, B, C})
        andalso (bit_size(<<A:3, B:6>>) =:= 9)
        andalso (byte_size(<<A:3, B:6>>) =:= 2).

rt(<<A:7, B:9, C:16/little>>) -> {A, B, C}.
