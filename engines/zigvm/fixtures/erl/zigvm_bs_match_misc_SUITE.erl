%% Curated PURE subset of erts/emulator/test/bs_match_misc_SUITE.erl (E7 suite
%% closure). The real suite exercises MIXED bit-syntax matching: float fields
%% (16/32/64, big/little/native endian, unaligned offsets), bound-variable and
%% bound-tail segments, literal string patterns, dynamic sizes drawn from
%% earlier fields, skip+extract combos, clause-selection ladders over binaries,
%% match contexts living in x(0), sub-binary subjects, and several historical
%% regressions (sean/kenneth/happi/wiger/OTP-7198/ERL-901) — plus CT-dependent
%% machinery (spawn_monitor GC probes, 2^27-bit huge-float binaries, process-
%% dictionary writable-binary stress, compile:forms bad-loader probes, fp16 and
%% native-endian fields). These cases MIRROR the pure algebraic core as
%% self-contained BOOLEAN assertions over DETERMINISTIC data. Every match
%% subject and every runtime operand is routed through the EXPORTED
%% ?MODULE:id/1 — an external call erlc cannot inline or constant-fold — so the
%% RUNTIME bs_start_match/bs_get_float/bs_get_binary/bs_get_integer kernels are
%% exercised, not the compiler's folder. Float equality is asserted only where
%% it is EXACT: 64-bit fields roundtrip a double bit-for-bit (=:=), 32-bit
%% extractions are compared by RE-ENCODING to bytes (never by decimal
%% formatting). EXCLUDED as non-pure or not-EQ: fp16 + native endian fields
%% (unsure => excluded), huge_float_field (2^27-bit allocations),
%% writable_binary_matched (process dictionary + append stress), otp_7198's
%% spawn_monitor/GC harness (its pure scanner IS mirrored), bad_bs_match
%% (compile:forms + code:load_binary), and the catch-wrap {'EXIT',{Reason,Stk}}
%% shape (zigvm lands the bare reason; try...catch error:function_clause /
%% error:{badmatch,V} ARE used — both EQ). lists:reverse is replaced by a local
%% rev/2 so the module is fully self-contained. No ct/port/node/io dependency —
%% runnable directly on the zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_bs_match_misc_SUITE).
-export([all/0, id/1, c_bound_var/1, c_bound_tail/1, c_float/1,
         c_little_float/1, c_sean/1, c_kenneth/1, c_encode_binary/1,
         c_happi/1, c_size_var/1, c_wiger/1, c_x0_context/1, c_otp_7198/1,
         c_unordered_bindings/1, c_ubgr/1]).

all() ->
    [c_bound_var, c_bound_tail, c_float, c_little_float, c_sean, c_kenneth,
     c_encode_binary, c_happi, c_size_var, c_wiger, c_x0_context, c_otp_7198,
     c_unordered_bindings, c_ubgr].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants (erlc cannot fold across
%% an exported call — the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

%% bound_var/1: an already-bound variable in a segment position is an equality
%% test, not a binding — mismatch falls through to the next clause.
c_bound_var(_) ->
    (bv(?MODULE:id(42), ?MODULE:id(13), ?MODULE:id(<<42,13>>)) =:= ok)
        andalso (bv(?MODULE:id(42), ?MODULE:id(13), ?MODULE:id(<<42,255>>)) =:= nope)
        andalso (bv(?MODULE:id(42), ?MODULE:id(13), ?MODULE:id(<<154,255>>)) =:= nope).

bv(A, B, <<A:8,B:8>>) -> ok;
bv(_, _, _) -> nope.

%% bound_tail/1: a bound BINARY variable as the tail segment — the whole
%% remaining suffix must equal it byte-for-byte (longer/shorter/differing
%% suffixes all fall through).
c_bound_tail(_) ->
    (bt(?MODULE:id(<<>>), ?MODULE:id(<<13,14>>)) =:= ok)
        andalso (bt(?MODULE:id(<<2,3>>), ?MODULE:id(<<1,1,2,3>>)) =:= ok)
        andalso (bt(?MODULE:id(<<2,3>>), ?MODULE:id(<<1,1,2,7>>)) =:= nope)
        andalso (bt(?MODULE:id(<<2,3>>), ?MODULE:id(<<1,1,2,3,4>>)) =:= nope)
        andalso (bt(?MODULE:id(<<2,3>>), ?MODULE:id(<<>>)) =:= nope).

bt(T, <<_:16,T/binary>>) -> ok;
bt(_, _) -> nope.

%% t_float/1 + float_middle_endian/1 (exact subset): big-endian float fields at
%% sizes 32/64 and bit offsets 0/1/13, matched out of an id-routed SUB-binary
%% (make_sub_bin, as in the real suite). 64-bit fields roundtrip a double
%% exactly; 32-bit extractions are compared by re-encoding to the same 4 bytes.
%% The middle-endian probe 9007199254740990.0 (which turns to -NaN if words are
%% swapped) must roundtrip exactly. float_sel: a case ladder that SELECTS among
%% float clauses by available size (64 -> 32 -> other).
c_float(_) ->
    F = ?MODULE:id(3.1415),
    One = ?MODULE:id(1.0),
    G32 = match_float(?MODULE:id(<<63,128,0,0>>), 32, 0),
    G64 = match_float(?MODULE:id(<<63,240,0,0,0,0,0,0>>), 64, 0),
    R64a = match_float(?MODULE:id(<<F:64/float>>), 64, 0),
    R64b = match_float(?MODULE:id(<<1:1,F:64/float,127:7>>), 64, 1),
    %% (real suite writes 127:3, which truncates to 7 — encoded directly)
    R64c = match_float(?MODULE:id(<<1:13,F:64/float,7:3>>), 64, 13),
    R32a = match_float(?MODULE:id(<<F:32/float>>), 32, 0),
    R32b = match_float(?MODULE:id(<<1:1,F:32/float,127:7>>), 32, 1),
    R32c = match_float(?MODULE:id(<<1:13,F:32/float,7:3>>), 32, 13),
    M = ?MODULE:id(9007199254740990.0),
    RM = match_float(?MODULE:id(<<M:64/float>>), 64, 0),
    (G32 =:= One) andalso (G64 =:= One)
        andalso (R64a =:= F) andalso (R64b =:= F) andalso (R64c =:= F)
        andalso (<<R32a:32/float>> =:= <<F:32/float>>)
        andalso (<<R32b:32/float>> =:= <<F:32/float>>)
        andalso (<<R32c:32/float>> =:= <<F:32/float>>)
        andalso (RM =:= M)
        andalso (float_sel(?MODULE:id(<<1.5:64/float>>)) =:= {f64,1.5})
        andalso (float_sel(?MODULE:id(<<63,128,0,0>>)) =:= {f32,1.0})
        andalso (float_sel(?MODULE:id(<<1,2>>)) =:= other).

float_sel(Bin) ->
    case Bin of
        <<X:64/float>> -> {f64,X};
        <<X:32/float>> -> {f32,X};
        _ -> other
    end.

match_float(Bin0, Fsz, I) ->
    Bin = make_sub_bin(Bin0),
    Bsz = byte_size(Bin) * 8,
    Tsz = Bsz - Fsz - I,
    <<_:I,F:Fsz/float,_:Tsz>> = Bin,
    F.

%% little_float/1 (exact subset): the same size/offset grid with little-endian
%% float fields, plus the byte-reversed 1.0 probes (<<0,0,128,63>> at 32,
%% <<0,0,0,0,0,0,240,63>> at 64).
c_little_float(_) ->
    F = ?MODULE:id(2.7133),
    One = ?MODULE:id(1.0),
    G64 = match_float_little(?MODULE:id(<<0,0,0,0,0,0,240,63>>), 64, 0),
    G32 = match_float_little(?MODULE:id(<<0,0,128,63>>), 32, 0),
    R64a = match_float_little(?MODULE:id(<<F:64/float-little>>), 64, 0),
    R64b = match_float_little(?MODULE:id(<<1:1,F:64/float-little,127:7>>), 64, 1),
    %% (real suite writes 127:3, which truncates to 7 — encoded directly)
    R64c = match_float_little(?MODULE:id(<<1:13,F:64/float-little,7:3>>), 64, 13),
    R32a = match_float_little(?MODULE:id(<<F:32/float-little>>), 32, 0),
    R32b = match_float_little(?MODULE:id(<<1:1,F:32/float-little,127:7>>), 32, 1),
    R32c = match_float_little(?MODULE:id(<<1:13,F:32/float-little,7:3>>), 32, 13),
    (G64 =:= One) andalso (G32 =:= One)
        andalso (R64a =:= F) andalso (R64b =:= F) andalso (R64c =:= F)
        andalso (<<R32a:32/float-little>> =:= <<F:32/float-little>>)
        andalso (<<R32b:32/float-little>> =:= <<F:32/float-little>>)
        andalso (<<R32c:32/float-little>> =:= <<F:32/float-little>>).

match_float_little(Bin0, Fsz, I) ->
    Bin = make_sub_bin(Bin0),
    Bsz = byte_size(Bin) * 8,
    Tsz = Bsz - Fsz - I,
    <<_:I,F:Fsz/float-little,_:Tsz>> = Bin,
    F.

%% The real suite's sub-binary maker: wrap, then match back out, so the float
%% subjects are OFFSET sub-binaries rather than freshly-built whole binaries.
make_sub_bin(Bin0) ->
    Sz = byte_size(Bin0),
    Bin1 = ?MODULE:id(<<37,Bin0/binary,38,39>>),
    <<_:8,Bin:Sz/binary,_:8,_:8>> = Bin1,
    Bin.

%% sean/1: clause selection between a guarded whole-binary clause
%% (byte_size < 4) and a literal-1-prefix clause; <<4,5,6,7>> matches neither
%% and raises function_clause (asserted with try + class discrimination — EQ,
%% unlike the catch-wrap shape).
c_sean(_) ->
    (sean1(?MODULE:id(<<>>)) =:= small)
        andalso (sean1(?MODULE:id(<<1>>)) =:= small)
        andalso (sean1(?MODULE:id(<<1,2>>)) =:= small)
        andalso (sean1(?MODULE:id(<<1,2,3>>)) =:= small)
        andalso (sean1(?MODULE:id(<<1,2,3,4>>)) =:= large)
        andalso (sean1(?MODULE:id(<<4>>)) =:= small)
        andalso (sean1(?MODULE:id(<<4,5>>)) =:= small)
        andalso (sean1(?MODULE:id(<<4,5,6>>)) =:= small)
        andalso (try sean1(?MODULE:id(<<4,5,6,7>>)) of
                     _ -> false
                 catch
                     error:function_clause -> true
                 end).

sean1(<<B/binary>>) when byte_size(B) < 4 -> small;
sean1(<<1, _B/binary>>) -> large.

%% kenneth/1: the MSISDN nibble scanner — 4-bit fields with guards, terminator
%% clauses for <<>>, an all-ones octet, and a 2#1111-prefixed final nibble;
%% out-of-range nibbles land in the {fault} clause.
c_kenneth(_) ->
    (msisdn(?MODULE:id(<<145,148,113,129,0,0,0,0>>), []) =:=
         {ok,[145,148,113,129,0,0,0,0]})
        andalso (msisdn(?MODULE:id(<<255,255>>), []) =:= {ok,[]})
        andalso (msisdn(?MODULE:id(<<16#F7>>), []) =:= {ok,[247]})
        andalso (msisdn(?MODULE:id(<<16#AB>>), []) =:= {fault}).

msisdn(<<>>, MSISDN) ->
    {ok,rev(MSISDN, [])};
msisdn(<<2#11111111:8,_Rest/binary>>, MSISDN) ->
    {ok,rev(MSISDN, [])};
msisdn(<<2#1111:4,DigitN:4,_Rest/binary>>, MSISDN) when DigitN < 10 ->
    {ok,rev([(DigitN bor 2#11110000)|MSISDN], [])};
msisdn(<<DigitNplus1:4,DigitN:4,Rest/binary>>, MSISDN) when
      DigitNplus1 < 10, DigitN < 10 ->
    msisdn(Rest, [((DigitNplus1 bsl 4) bor DigitN)|MSISDN]);
msisdn(_Rest, _MSISDN) ->
    {fault}.

%% encode_binary/1: the suite's base64-ish encoder — fixed-width binary
%% extraction clauses (exactly 1 / exactly 2 / 3-plus-rest bytes) with 6/4/2-bit
%% sub-splits; the char table is a skip-N-then-extract over one literal binary.
%% NOTE the remainder handling is the suite's own (unshifted low bits), NOT
%% RFC base64 — expectations mirror its actual algebra.
c_encode_binary(_) ->
    (encode_b(?MODULE:id(<<11,98,118,66,36,156>>), []) =:= "C2J2QiSc")
        andalso (encode_b(?MODULE:id(<<>>), []) =:= [])
        andalso (encode_b(?MODULE:id(<<255>>), []) =:= "/D==")
        andalso (encode_b(?MODULE:id(<<255,255>>), []) =:= "//P=").

encode_b(<<>>, Output) ->
    rev(Output, []);
encode_b(<<Data:1/binary>>, Output) ->
    <<DChar1:6, DChar2:2>> = Data,
    NewOutput = "=" ++ "=" ++ b64char(DChar2) ++ b64char(DChar1) ++ Output,
    encode_b(<<>>, NewOutput);
encode_b(<<Data:2/binary>>, Output) ->
    <<DChar1:6, DChar2:6, DChar3:4>> = Data,
    NewOutput = "=" ++ b64char(DChar3) ++ b64char(DChar2) ++ b64char(DChar1)
        ++ Output,
    encode_b(<<>>, NewOutput);
encode_b(<<Data:3/binary, Rest/binary>>, Output) ->
    <<DChar1:6, DChar2:6, DChar3:6, DChar4:6>> = Data,
    NewOutput = b64char(DChar4) ++ b64char(DChar3) ++ b64char(DChar2)
        ++ b64char(DChar1) ++ Output,
    encode_b(Rest, NewOutput).

%% Skip-then-extract over the base64 alphabet: <<_:N/binary, C, _/binary>>.
b64char(N) ->
    Tab = ?MODULE:id(
      <<"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/">>),
    <<_:N/binary, C, _/binary>> = Tab,
    [C].

%% happi/1: literal character/string prefixes in patterns — the two lex_digits
%% clause orders must agree — plus an explicit <<"abc",Rest/binary>>-style
%% literal-string prefix ladder (longest literal wins by clause order).
c_happi(_) ->
    Bin = ?MODULE:id(<<".123">>),
    (lex_digits1(Bin, 1, []) =:= <<"123">>)
        andalso (lex_digits2(Bin, 1, []) =:= <<"123">>)
        andalso (lex_digits1(?MODULE:id(<<"4.5">>), 1, []) =:= <<"5">>)
        andalso (lex_digits2(?MODULE:id(<<"4.5">>), 1, []) =:= <<"5">>)
        andalso (lex_digits1(?MODULE:id(<<"abc">>), 1, []) =:= not_ok)
        andalso (lex_digits2(?MODULE:id(<<"abc">>), 1, []) =:= not_ok)
        andalso (strip_pre(?MODULE:id(<<"abcdef">>)) =:= {abc,<<"def">>})
        andalso (strip_pre(?MODULE:id(<<"abx">>)) =:= {ab,<<"x">>})
        andalso (strip_pre(?MODULE:id(<<"xyz">>)) =:= none).

lex_digits1(<<$., Rest/binary>>, _Val, _Acc) ->
    Rest;
lex_digits1(<<N, Rest/binary>>, Val, Acc) when N >= $0, N =< $9 ->
    lex_digits1(Rest, Val*10+dec(N), Acc);
lex_digits1(_Other, _Val, _Acc) ->
    not_ok.

lex_digits2(<<N, Rest/binary>>, Val, Acc) when N >= $0, N =< $9 ->
    lex_digits2(Rest, Val*10+dec(N), Acc);
lex_digits2(<<$., Rest/binary>>, _Val, _Acc) ->
    Rest;
lex_digits2(_Other, _Val, _Acc) ->
    not_ok.

dec(A) ->
    A - $0.

strip_pre(<<"abc", Rest/binary>>) -> {abc, Rest};
strip_pre(<<"ab", Rest/binary>>) -> {ab, Rest};
strip_pre(_) -> none.

%% size_var/1: a size drawn from an EARLIER field of the same pattern
%% (<<N:16,B:N/binary,...>>), a size whose own WIDTH comes from an earlier
%% field (split_2), a bound-variable size argument (split/2 — mismatching N
%% raises function_clause), and skip-with-dynamic-size.
c_size_var(_) ->
    (split(?MODULE:id(<<1:16,45>>)) =:= {<<45>>,<<>>})
        andalso (split(?MODULE:id(<<1:16,45,46,47>>)) =:= {<<45>>,<<46,47>>})
        andalso (split(?MODULE:id(<<2:16,45,46,47>>)) =:= {<<45,46>>,<<47>>})
        andalso (split_2(?MODULE:id(<<16:8,3:16,45,46,47,48>>)) =:=
                     {<<45,46,47>>,<<48>>})
        andalso (split(?MODULE:id(2), ?MODULE:id(<<2:16,45,46,47>>)) =:=
                     {<<45,46>>,<<47>>})
        andalso (try split(?MODULE:id(42), ?MODULE:id(<<2:16,45,46,47>>)) of
                     _ -> false
                 catch
                     error:function_clause -> true
                 end)
        andalso (skip(?MODULE:id(<<2:8,"abcdef">>)) =:= <<"cdef">>).

split(<<N:16,B:N/binary,T/binary>>) ->
    {B,T}.

split(N, <<N:16,B:N/binary,T/binary>>) ->
    {B,T}.

split_2(<<N0:8,N:N0,B:N/binary,T/binary>>) ->
    {B,T}.

skip(<<N:8,_:N/binary,T/binary>>) -> T.

%% wiger/1: first-clause-wins selection among guarded single-byte, byte-plus-
%% fixed-binary, bare single-byte, and catch-all clauses.
c_wiger(_) ->
    (wcheck(?MODULE:id(<<3>>)) =:= ok1)
        andalso (wcheck(?MODULE:id(<<1,2,3>>)) =:= ok2)
        andalso (wcheck(?MODULE:id(<<4>>)) =:= ok3)
        andalso (wcheck(?MODULE:id(<<1,2,3,4>>)) =:= {error,<<1,2,3,4>>})
        andalso (wcheck(?MODULE:id(<<>>)) =:= {error,<<>>}).

wcheck(<<A>>) when A == 3 ->
    ok1;
wcheck(<<_,_:2/binary>>) ->
    ok2;
wcheck(<<_>>) ->
    ok3;
wcheck(Other) ->
    {error,Other}.

%% x0_context/1: the match context living in x(0) — a float LITERAL in pattern
%% position, dynamic float/integer/binary sizes over one shared subject,
%% re-matching with an already-bound binary segment, an unaligned 7+9-bit
%% integer view of the same bytes, and a final case ladder where earlier
%% near-miss clauses must fall through.
c_x0_context(_) ->
    Bin = ?MODULE:id(<<3.0:64/float,42:16,123456:32>>),
    case Bin of
        <<3.0:64/float,42:16,_/binary>> -> x0_1(Bin);
        _ -> false
    end.

x0_1(Bin) ->
    FloatSz = ?MODULE:id(64),
    IntSz = ?MODULE:id(16),
    BinSz = ?MODULE:id(2),
    <<_:FloatSz/float,42:IntSz,B:BinSz/binary,C:1/binary,D/binary>> = Bin,
    <<_:FloatSz/float,42:IntSz,B:BinSz/binary,_/binary>> = Bin,
    ({B,C,D} =:= {<<0,1>>,<<226>>,<<64>>}) andalso x0_2(Bin).

x0_2(Bin) ->
    case Bin of
        <<_:64,0:7,42:9,_/binary>> -> x0_3(Bin);
        _ -> false
    end.

x0_3(Bin) ->
    case Bin of
        <<_:72,7:8,_/binary>> -> false;
        <<_:64,0:16,_/binary>> -> false;
        <<_:64,42:16,123456:32,_/binary>> -> true;
        _ -> false
    end.

%% otp_7198/1 (pure scanner only — the real case wraps this in spawn_monitor
%% GC stress, excluded): a tokenizer whose clauses mix multi-byte lookahead
%% with guards, character-class guards, and a nested case on the tail.
c_otp_7198(_) ->
    (otp_7198_scan(?MODULE:id(<<"region:whatever">>), []) =:=
         [{'KEYWORD',114},{'KEYWORD',101},{'KEYWORD',103},{'KEYWORD',105},
          {'KEYWORD',111},{'FIELD',110},{'KEYWORD',119},{'KEYWORD',104},
          {'KEYWORD',97},{'KEYWORD',116},{'KEYWORD',101},{'KEYWORD',118},
          {'KEYWORD',101},{'KEYWORD',114},'$thats_all_folks$'])
        andalso (otp_7198_scan(?MODULE:id(<<"a:b">>), []) =:=
                     [{'FIELD',97},{'KEYWORD',98},'$thats_all_folks$'])
        andalso (otp_7198_scan(?MODULE:id(<<"d">>), []) =:=
                     ['AND','$thats_all_folks$']).

otp_7198_scan(<<>>, TokAcc) ->
    rev(['$thats_all_folks$' | TokAcc], []);
otp_7198_scan(<<D, Z, Rest/binary>>, TokAcc) when
      (D =:= $D orelse D =:= $d) and
      ((Z =:= $\s) or (Z =:= $() or (Z =:= $))) ->
    otp_7198_scan(<<Z, Rest/binary>>, ['AND' | TokAcc]);
otp_7198_scan(<<D>>, TokAcc) when
      (D =:= $D) or (D =:= $d) ->
    otp_7198_scan(<<>>, ['AND' | TokAcc]);
otp_7198_scan(<<N, Z, Rest/binary>>, TokAcc) when
      (N =:= $N orelse N =:= $n) and
      ((Z =:= $\s) or (Z =:= $() or (Z =:= $))) ->
    otp_7198_scan(<<Z, Rest/binary>>, ['NOT' | TokAcc]);
otp_7198_scan(<<C, Rest/binary>>, TokAcc) when
      (C >= $A) and (C =< $Z);
      (C >= $a) and (C =< $z);
      (C >= $0) and (C =< $9) ->
    case Rest of
        <<$:, R/binary>> ->
            otp_7198_scan(R, [{'FIELD', C} | TokAcc]);
        _ ->
            otp_7198_scan(Rest, [{'KEYWORD', C} | TokAcc])
    end.

%% unordered_bindings/1: three binary sizes bound from ARGUMENTS plus a final
%% bound-variable byte (PadLength appears both as a size and as a value);
%% a wrong trailing byte raises badmatch carrying the whole subject (asserted
%% with try + the bare {badmatch,V} reason — EQ).
c_unordered_bindings(_) ->
    (ub(?MODULE:id(4), ?MODULE:id(2), ?MODULE:id(3),
        ?MODULE:id(<<1,2,3,4, 42,42, 3,3,3, 3>>)) =:=
         {<<1,2,3,4>>,<<42,42>>,<<3,3,3>>})
        andalso (try ub(?MODULE:id(4), ?MODULE:id(2), ?MODULE:id(3),
                        ?MODULE:id(<<1,2,3,4, 42,42, 3,3,3, 9>>)) of
                     _ -> false
                 catch
                     error:{badmatch,V} -> V =:= <<1,2,3,4, 42,42, 3,3,3, 9>>
                 end).

ub(CompressedLength, HashSize, PadLength, T) ->
    <<Content:CompressedLength/binary,Mac:HashSize/binary,
      Padding:PadLength/binary,PadLength>> = T,
    {Content,Mac,Padding}.

%% unsafe_get_binary_reuse/1 (ERL-901): a match context must survive being
%% passed to another function that overwrites its register with a
%% bs_get_binary result — the original context is re-matched afterwards. Also
%% exercises utf8 extraction and an invalid-utf8 fallthrough.
c_ubgr(_) ->
    <<_First, Rest/binary>> = ?MODULE:id(<<"hello">>),
    R1 = ubgr_1(Rest),
    <<Second,_/bits>> = Rest,
    (Second =:= $e) andalso (R1 =:= <<"llo">>)
        andalso (ubgr_1(?MODULE:id(<<255,255>>)) =:= false).

ubgr_1(<<_CP/utf8, Rest/binary>>) -> ?MODULE:id(Rest);
ubgr_1(_) -> false.

%% Local list reverse (self-contained: no lists module dependency).
rev([], Acc) -> Acc;
rev([H|T], Acc) -> rev(T, [H|Acc]).
