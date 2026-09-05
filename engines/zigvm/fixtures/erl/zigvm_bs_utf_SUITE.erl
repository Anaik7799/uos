%% Curated PURE subset of erts/emulator/test/bs_utf_SUITE.erl (E7 suite
%% closure). The real suite sweeps every codepoint 0..16#10FFFF (minus the
%% surrogate gap) through utf8/utf16/utf32 construction+matching, and probes
%% illegal sequences (overlong utf8, short sequences, lonely hi / leading lo
%% surrogates, out-of-range values) using ct:fail, spawned worker fleets,
%% erts_debug:unaligned_bitstring, erl_eval re-interpretation and a big-file
%% corpus. These cases MIRROR the same groups (utf8_roundtrip, utf16_roundtrip,
%% utf32_roundtrip, utf8/16/32_illegal_sequences, bad_construction) as
%% self-contained BOOLEAN assertions over the BOUNDARY codepoints — the utf8
%% 1/2/3/4-byte width edges 16#7F/16#80/16#7FF/16#800/16#FFFF/16#10000, the
%% surrogate-gap edges 16#D7FF/16#E000, and the top 16#10FFFF — plus
%% deterministic illegal-byte probes. Every construction operand and match
%% subject is routed through the EXPORTED ?MODULE:id/1 (an external call erlc
%% cannot inline or constant-fold — the zigvm_big_SUITE c_bitwise_2pow
%% pattern), so the RUNTIME bs_put_utf/bs_get_utf kernels are exercised, not
%% the compiler's folder. Illegal-ENCODING match failure is expressed as
%% case-clause fallthrough (no exceptions); illegal-VALUE construction failure
%% as try ... catch error:badarg (class+reason discrimination — EQ; never the
%% catch-expr {'EXIT',{Reason,Stk}} wrap shape, per the E1 divergence). No
%% ct/port/node/spawn/io/file/timing dependency — runnable directly on the
%% zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_bs_utf_SUITE).
-export([all/0, id/1, c_utf8_encode/1, c_utf8_roundtrip/1, c_utf8_unaligned/1,
         c_utf16_bmp/1, c_utf16_surrogate_pair/1, c_utf16_little/1,
         c_utf32_roundtrip/1, c_utf8_overlong/1, c_utf8_bad_first/1,
         c_utf8_short/1, c_utf16_reject/1, c_utf32_reject/1,
         c_construct_badarg/1]).

all() ->
    [c_utf8_encode, c_utf8_roundtrip, c_utf8_unaligned, c_utf16_bmp,
     c_utf16_surrogate_pair, c_utf16_little, c_utf32_roundtrip,
     c_utf8_overlong, c_utf8_bad_first, c_utf8_short, c_utf16_reject,
     c_utf32_reject, c_construct_badarg].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants.
id(X) -> X.

%% The boundary codepoints every roundtrip case sweeps: the utf8 width edges
%% (1->2 at 16#80, 2->3 at 16#800, 3->4 at 16#10000), both surrogate-gap
%% edges, and both ends of the domain.
bound_cps() ->
    [0, 1, 16#7F, 16#80, 16#7FF, 16#800, 16#D7FF, 16#E000,
     16#FFFF, 16#10000, 16#10FFFF].

%% utf8_roundtrip (encode half): construction emits the EXACT RFC-3629 byte
%% sequence at every width boundary, and appending onto an id-routed empty
%% binary (the real suite's <<(id(<<>>))/binary,First/utf8>> probe) agrees.
c_utf8_encode(_) ->
    enc8([{0,          <<0>>},
          {16#7F,      <<16#7F>>},
          {16#80,      <<16#C2,16#80>>},
          {16#7FF,     <<16#DF,16#BF>>},
          {16#800,     <<16#E0,16#A0,16#80>>},
          {16#D7FF,    <<16#ED,16#9F,16#BF>>},
          {16#E000,    <<16#EE,16#80,16#80>>},
          {16#FFFF,    <<16#EF,16#BF,16#BF>>},
          {16#10000,   <<16#F0,16#90,16#80,16#80>>},
          {16#10FFFF,  <<16#F4,16#8F,16#BF,16#BF>>}]).

enc8([]) -> true;
enc8([{C,Bytes} | T]) ->
    V = ?MODULE:id(C),
    (<<V/utf8>> =:= Bytes)
        andalso (<<(?MODULE:id(<<>>))/binary,V/utf8>> =:= Bytes)
        andalso enc8(T).

%% utf8_roundtrip (match half): construct-then-match is the identity at every
%% boundary codepoint, on BOTH utf8 match code paths — the exact-fit binary
%% and the extended binary with 64 trailing bits (the real suite's
%% <<First/utf8,0:64>> dual-path probe).
c_utf8_roundtrip(_) -> rt8(bound_cps()).

rt8([]) -> true;
rt8([C | T]) ->
    V = ?MODULE:id(C),
    Bin = ?MODULE:id(<<V/utf8>>),
    Ext = ?MODULE:id(<<Bin/binary,0:64>>),
    case {Bin, Ext} of
        {<<V/utf8>>, <<V/utf8,0:64>>} -> rt8(T);
        _ -> false
    end.

%% utf8 at NON-ZERO bit offsets (the unaligned_match walk, bounded): a utf8
%% segment constructed after a 1..7-bit zero pad matches back at the same
%% offset, and the real suite's <<3:2,Char/utf8>> probe yields an unaligned
%% byte-multiple tail equal to the aligned encoding.
c_utf8_unaligned(_) -> un8(bound_cps()).

un8([]) -> true;
un8([C | T]) ->
    V = ?MODULE:id(C),
    Bin = ?MODULE:id(<<V/utf8>>),
    Un = ?MODULE:id(<<3:2,V/utf8>>),
    <<_:2,Tail/binary>> = Un,
    (Tail =:= Bin) andalso un8_off(V, 7) andalso un8(T).

un8_off(_V, 0) -> true;
un8_off(V, Off) ->
    case ?MODULE:id(<<0:Off,V/utf8>>) of
        <<0:Off,V/utf8>> -> un8_off(V, Off - 1);
        _ -> false
    end.

%% utf16_roundtrip (BMP): below the pair threshold a utf16 code unit is the
%% codepoint itself — big-endian bytes equal <<V:16>>, little-endian bytes
%% equal <<V:16/little>> — and both orders match back to the codepoint.
c_utf16_bmp(_) ->
    b16([0, 16#7F, 16#80, 16#7FF, 16#800, 16#D7FF, 16#E000, 16#FFFF]).

b16([]) -> true;
b16([C | T]) ->
    V = ?MODULE:id(C),
    Big = ?MODULE:id(<<V/utf16>>),
    Lit = ?MODULE:id(<<V/little-utf16>>),
    RB = case Big of <<X/utf16>> -> X; _ -> nomatch end,
    RL = case Lit of <<Y/little-utf16>> -> Y; _ -> nomatch end,
    (Big =:= <<V:16>>) andalso (Lit =:= <<V:16/little>>)
        andalso (RB =:= V) andalso (RL =:= V) andalso b16(T).

%% utf16_roundtrip (astral): codepoints >= 16#10000 encode as a hi/lo
%% surrogate pair with the EXACT unit values (D800+((C-10000) bsr 10),
%% DC00+((C-10000) band 3FF)); little-endian swaps bytes WITHIN each 16-bit
%% unit, not across the pair; both orders match back, including on the
%% extended-binary path.
c_utf16_surrogate_pair(_) ->
    sp16([{16#10000,  <<16#D8,16#00,16#DC,16#00>>},
          {16#10437,  <<16#D8,16#01,16#DC,16#37>>},
          {16#E0000,  <<16#DB,16#40,16#DC,16#00>>},
          {16#10FFFF, <<16#DB,16#FF,16#DF,16#FF>>}]).

sp16([]) -> true;
sp16([{C,BigBytes} | T]) ->
    V = ?MODULE:id(C),
    Big = ?MODULE:id(<<V/utf16>>),
    Lit = ?MODULE:id(<<V/little-utf16>>),
    <<H1,H2,L1,L2>> = ?MODULE:id(BigBytes),
    (Big =:= BigBytes) andalso (Lit =:= <<H2,H1,L2,L1>>)
        andalso (case Big of <<X/utf16>> -> X =:= V; _ -> false end)
        andalso (case Lit of <<Y/little-utf16>> -> Y =:= V; _ -> false end)
        andalso (case ?MODULE:id(<<Big/binary,0:64>>) of
                     <<Z/utf16,0:64>> -> Z =:= V;
                     _ -> false
                 end)
        andalso sp16(T).

%% utf16_little_roundtrip: little-endian construct-then-match is the identity
%% over ALL boundary codepoints (BMP and astral), and the real suite's
%% <<3:2,Char/little-utf16>> probe yields an unaligned tail equal to the
%% aligned encoding.
c_utf16_little(_) -> l16(bound_cps()).

l16([]) -> true;
l16([C | T]) ->
    V = ?MODULE:id(C),
    Bin = ?MODULE:id(<<V/little-utf16>>),
    Un = ?MODULE:id(<<3:2,V/little-utf16>>),
    <<_:2,Tail/binary>> = Un,
    (Tail =:= Bin)
        andalso (case Bin of <<X/little-utf16>> -> X =:= V; _ -> false end)
        andalso l16(T).

%% utf32_roundtrip: utf32 is the codepoint as a plain 32-bit integer in the
%% chosen byte order; both orders roundtrip at every boundary codepoint and
%% the <<3:2,...>> unaligned-tail probe agrees with the aligned encoding.
c_utf32_roundtrip(_) -> r32(bound_cps()).

r32([]) -> true;
r32([C | T]) ->
    V = ?MODULE:id(C),
    Big = ?MODULE:id(<<V/utf32>>),
    Lit = ?MODULE:id(<<V/little-utf32>>),
    Un = ?MODULE:id(<<3:2,V/utf32>>),
    <<_:2,Tail/binary>> = Un,
    (Big =:= <<V:32>>) andalso (Lit =:= <<V:32/little>>) andalso (Tail =:= Big)
        andalso (case Big of <<X/utf32>> -> X =:= V; _ -> false end)
        andalso (case Lit of <<Y/little-utf32>> -> Y =:= V; _ -> false end)
        andalso r32(T).

%% utf8_illegal_sequences (overlong): encoding a codepoint in more bytes than
%% necessary is REJECTED by the utf8 matcher — the case falls through to the
%% nomatch clause on both the exact-fit and extended-binary paths (the
%% overlong/2 walk at each width boundary, deterministic subset).
c_utf8_overlong(_) ->
    nomatch8([<<16#C0,16#80>>,               %% 2-byte NUL
              <<16#C1,16#BF>>,               %% 2-byte 16#7F
              <<16#E0,16#80,16#80>>,         %% 3-byte NUL
              <<16#E0,16#9F,16#BF>>,         %% 3-byte 16#7FF
              <<16#F0,16#80,16#80,16#80>>,   %% 4-byte NUL
              <<16#F0,16#8F,16#BF,16#BF>>]). %% 4-byte 16#FFFF

%% utf8_illegal_sequences (bad leading byte / forbidden ranges): a
%% continuation byte first, 16#F5..16#FF leads, an ENCODED surrogate
%% (fail_range 16#D800..16#DFFF as 3-byte utf8), and an encoded 16#110000
%% (fail_range above 16#10FFFF) all fall through.
c_utf8_bad_first(_) ->
    nomatch8([<<16#80,16#8F,16#8F,16#8F>>,
              <<16#BF,16#8F,16#8F,16#8F>>,
              <<16#F5,16#8F,16#8F,16#8F>>,
              <<16#FE,16#8F,16#8F,16#8F>>,
              <<16#FF,16#8F,16#8F,16#8F>>,
              <<16#ED,16#A0,16#80>>,          %% encoded 16#D800
              <<16#ED,16#BF,16#BF>>,          %% encoded 16#DFFF
              <<16#F4,16#90,16#80,16#80>>]).  %% encoded 16#110000

%% utf8_illegal_sequences (short_sequences): truncated multi-byte sequences,
%% and sequences whose continuation slot holds a non-continuation byte
%% (16#7F), fall through — at each of the 2/3/4-byte widths.
c_utf8_short(_) ->
    nomatch8([<<16#C2>>, <<16#DF>>,
              <<16#E0,16#A0>>, <<16#EF,16#BF>>,
              <<16#F0,16#90,16#80>>, <<16#F4,16#8F,16#BF>>,
              <<16#C2,16#7F>>,
              <<16#E0,16#A0,16#7F>>,
              <<16#F0,16#90,16#80,16#7F>>]).

nomatch8([]) -> true;
nomatch8([Bin | T]) ->
    (u8d(?MODULE:id(Bin)) =:= nomatch)
        andalso (u8dx(?MODULE:id(<<Bin/binary,0:64>>)) =:= nomatch)
        andalso nomatch8(T).

u8d(Bin) ->
    case Bin of
        <<C/utf8>> -> {ok,C};
        _ -> nomatch
    end.

u8dx(Bin) ->
    case Bin of
        <<C/utf8,_:64>> -> {ok,C};
        _ -> nomatch
    end.

%% utf16_illegal_sequences: a lonely hi surrogate (no low unit follows), a
%% leading LO surrogate, and a hi surrogate followed by a non-lo unit are all
%% rejected in both byte orders — while a well-formed pair still decodes (the
%% lonely_hi_surrogate/leading_lo_surrogate walks, deterministic subset).
c_utf16_reject(_) ->
    (d16b(?MODULE:id(<<16#D800:16>>)) =:= nomatch)
        andalso (d16b(?MODULE:id(<<16#DBFF:16>>)) =:= nomatch)
        andalso (d16l(?MODULE:id(<<16#D800:16/little>>)) =:= nomatch)
        andalso (d16bt(?MODULE:id(<<16#DC00:16,16#DC00:16>>)) =:= nomatch)
        andalso (d16bt(?MODULE:id(<<16#DFFF:16,16#D800:16>>)) =:= nomatch)
        andalso (d16bt(?MODULE:id(<<16#D800:16,16#0041:16>>)) =:= nomatch)
        andalso (d16lt(?MODULE:id(<<16#DC00:16/little,16#DC00:16/little>>))
                 =:= nomatch)
        andalso (d16b(?MODULE:id(<<16#D800:16,16#DC00:16>>)) =:= {ok,16#10000}).

d16b(Bin)  -> case Bin of <<C/big-utf16>> -> {ok,C}; _ -> nomatch end.
d16l(Bin)  -> case Bin of <<C/little-utf16>> -> {ok,C}; _ -> nomatch end.
d16bt(Bin) -> case Bin of <<C/big-utf16,_/bits>> -> {ok,C}; _ -> nomatch end.
d16lt(Bin) -> case Bin of <<C/little-utf16,_/bits>> -> {ok,C}; _ -> nomatch end.

%% utf32_illegal_sequences: surrogate codepoints, values above 16#10FFFF, and
%% a full-width out-of-range word are rejected in both byte orders — while
%% 16#10FFFF itself still decodes (utf32_fail_range, deterministic subset).
c_utf32_reject(_) ->
    (d32b(?MODULE:id(<<16#D800:32>>)) =:= nomatch)
        andalso (d32b(?MODULE:id(<<16#DFFF:32>>)) =:= nomatch)
        andalso (d32b(?MODULE:id(<<16#110000:32>>)) =:= nomatch)
        andalso (d32b(?MODULE:id(<<16#FFFFFFFF:32>>)) =:= nomatch)
        andalso (d32l(?MODULE:id(<<16#D800:32/little>>)) =:= nomatch)
        andalso (d32l(?MODULE:id(<<16#110000:32/little>>)) =:= nomatch)
        andalso (d32b(?MODULE:id(<<16#10FFFF:32>>)) =:= {ok,16#10FFFF})
        andalso (d32l(?MODULE:id(<<16#10FFFF:32/little>>)) =:= {ok,16#10FFFF}).

d32b(Bin) -> case Bin of <<C/utf32>> -> {ok,C}; _ -> nomatch end.
d32l(Bin) -> case Bin of <<C/little-utf32>> -> {ok,C}; _ -> nomatch end.

%% bad_construction: CONSTRUCTING a utf segment from a surrogate, a negative,
%% an above-range integer, or a float raises error:badarg (class+reason
%% discriminated via try — never the catch-wrap shape), while the top valid
%% codepoint still constructs. All values id-routed so the RUNTIME
%% construction path raises, not the compiler.
c_construct_badarg(_) ->
    (mk8(?MODULE:id(16#D800)) =:= badarg)
        andalso (mk16(?MODULE:id(16#D800)) =:= badarg)
        andalso (mk32(?MODULE:id(16#D800)) =:= badarg)
        andalso (mk8(?MODULE:id(-1)) =:= badarg)
        andalso (mk16(?MODULE:id(-1)) =:= badarg)
        andalso (mk32(?MODULE:id(-1)) =:= badarg)
        andalso (mk8(?MODULE:id(16#110000)) =:= badarg)
        andalso (mk16(?MODULE:id(16#110000)) =:= badarg)
        andalso (mk32(?MODULE:id(16#110000)) =:= badarg)
        andalso (mk8(?MODULE:id(3.14)) =:= badarg)
        andalso (mk8(?MODULE:id(16#10FFFF)) =:= made)
        andalso (mk16(?MODULE:id(16#10FFFF)) =:= made)
        andalso (mk32(?MODULE:id(16#10FFFF)) =:= made).

mk8(V)  -> try <<V/utf8>>  of _ -> made catch error:badarg -> badarg end.
mk16(V) -> try <<V/utf16>> of _ -> made catch error:badarg -> badarg end.
mk32(V) -> try <<V/utf32>> of _ -> made catch error:badarg -> badarg end.
