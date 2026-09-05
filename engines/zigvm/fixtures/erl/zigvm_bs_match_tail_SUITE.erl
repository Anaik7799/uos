%% Curated PURE subset of erts/emulator/test/bs_match_tail_SUITE.erl (E7 suite
%% closure). The real suite exercises bit-syntax TAIL MATCHING: aligned tails
%% (used and unused), dynamically-sized heads before a tail, the divisibility
%% rule for /binary tails (the remaining SIZE must be a whole number of bytes
%% -- head-position alignment is irrelevant), zero-length tails, and huge tails
%% (immediate-width probes on the JIT cmp encodings). These cases MIRROR the
%% same groups (aligned, unaligned, zero_tail, huge_tail in miniature) as
%% self-contained BOOLEAN assertions over DETERMINISTIC data, and add the
%% freshly-fixed observations: bit_size/byte_size of a matched tail answer with
%% the REMAINING view, and a matched tail is itself re-matchable (a /bits tail
%% re-enters bs_start_match). Every match subject, every dynamic size, and
%% every constructed comparand is routed through the EXPORTED ?MODULE:id/1 --
%% an external call erlc cannot inline or constant-fold -- so the RUNTIME
%% bs_start_match/bs_get_binary/bs_get_tail/bs_test_tail kernels are exercised,
%% not the compiler's folder. /binary-divisibility failure is expressed as
%% case-clause fallthrough; the unaligned group's exception shapes use
%% try...catch with BARE reasons (error:function_clause, error:{badmatch,V})
%% -- both EQ; the catch-wrap {'EXIT',{Reason,Stk}} shape is NOT used (the E1
%% catch-shape divergence). The 2Gb huge_tail probe is bounded to the real
%% suite's 16#1001-bit (AArch64 cmp-immediate) tail -- ~513 bytes. No ct/port/
%% node/io dependency -- runnable directly on the zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_bs_match_tail_SUITE).
-export([all/0, id/1, c_aligned_used/1, c_aligned_unused/1, c_dyn_tail/1,
         c_unaligned_fallthrough/1, c_unaligned_error/1, c_bits_tail/1,
         c_tail_sizes/1, c_rematch_tail/1, c_zero_tail/1, c_long_tail/1]).

all() ->
    [c_aligned_used, c_aligned_unused, c_dyn_tail, c_unaligned_fallthrough,
     c_unaligned_error, c_bits_tail, c_tail_sizes, c_rematch_tail,
     c_zero_tail, c_long_tail].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants (erlc cannot fold across
%% an exported call -- the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

%% aligned/1 (tail USED): a byte-aligned /binary tail after a 16-bit head is
%% the exact remaining suffix -- empty, short, and multi-byte (the
%% al_get_tail_used probes: 258 over <<1,2>>, 35091 over <<137,19,...>>).
c_aligned_used(_) ->
    ({258,<<>>} =:= tail16_used(?MODULE:id(<<1,2>>)))
        andalso ({35091,<<7,8,9>>} =:= tail16_used(?MODULE:id(<<137,19,7,8,9>>)))
        andalso ({16#cafe,<<16#de,16#ad,16#be,16#ef>>}
                 =:= tail16_used(?MODULE:id(<<16#cafe:16,16#deadbeef:32>>))).

tail16_used(<<A:16,T/binary>>) -> {A,T}.

%% aligned/1 (tail UNUSED): a wildcard /binary tail (_/binary) still demands
%% byte divisibility but discards the suffix -- the head extraction must be
%% unaffected by the tail's length (the al_get_tail_unused probes: 64896,
%% 64895 with and without trailing bytes).
c_aligned_unused(_) ->
    (64896 =:= tail16_unused(?MODULE:id(<<253,128>>)))
        andalso (64895 =:= tail16_unused(?MODULE:id(<<253,127,42,43,44,45>>)))
        andalso (64895 =:= tail16_unused(?MODULE:id(<<253,127>>))).

tail16_unused(<<A:16,_/binary>>) -> A.

%% aligned/1 (DYNAMIC head): the head size is a RUNTIME value (id-routed), so
%% the tail split point is computed at run time -- including the Sz=0 edge
%% where the tail is the whole subject (the get_dyn_tail_used/unused probes:
%% {0,<<>>}, {73,Tail}, 233, 23).
c_dyn_tail(_) ->
    ({0,<<>>} =:= dyn_tail_used(?MODULE:id(<<>>), ?MODULE:id(0)))
        andalso ({0,<<10,20,30>>} =:= dyn_tail_used(?MODULE:id(<<10,20,30>>), ?MODULE:id(0)))
        andalso ({73,<<0,1,2,3,4>>} =:= dyn_tail_used(?MODULE:id(<<73,0,1,2,3,4>>), ?MODULE:id(8)))
        andalso (0 =:= dyn_tail_unused(?MODULE:id(<<>>), ?MODULE:id(0)))
        andalso (233 =:= dyn_tail_unused(?MODULE:id(<<233>>), ?MODULE:id(8)))
        andalso (23 =:= dyn_tail_unused(?MODULE:id(<<23,22,2>>), ?MODULE:id(8))).

dyn_tail_used(Bin, Sz) ->
    <<A:Sz,T/binary>> = Bin,
    {A,T}.

dyn_tail_unused(Bin, Sz) ->
    <<A:Sz,_/binary>> = Bin,
    A.

%% unaligned/1 as CASE-CLAUSE FALLTHROUGH: a /binary tail matches iff the
%% remaining SIZE is divisible by 8 -- head-position alignment is irrelevant.
%% A 1-bit head over 8 bits leaves 7 bits (no match), over 9 bits leaves 8
%% bits (match); a 15-bit head over 16 bits leaves 1 bit (no match), over 23
%% bits leaves 8 bits (match).
c_unaligned_fallthrough(_) ->
    (no_match =:= tb1(?MODULE:id(<<42>>)))
        andalso ({1,<<255>>} =:= tb1(?MODULE:id(<<1:1,255:8>>)))
        andalso (no_match =:= tb15(?MODULE:id(<<42,33>>)))
        andalso ({5000,<<129>>} =:= tb15(?MODULE:id(<<5000:15,129:8>>)))
        andalso (no_match =:= tb1(?MODULE:id(<<3:2>>))).

tb1(Bin) ->
    case Bin of
        <<A:1,T/binary>> -> {A,T};
        _ -> no_match
    end.

tb15(Bin) ->
    case Bin of
        <<A:15,T/binary>> -> {A,T};
        _ -> no_match
    end.

%% unaligned/1 exception shapes (BARE reasons via try, never catch-wrap): a
%% function head whose only clause demands a divisible /binary tail raises
%% function_clause; a direct dynamic-size match raises {badmatch,Subject}
%% carrying the SUBJECT binary (the real suite's get_tail_used/
%% get_dyn_tail_used EXIT probes).
c_unaligned_error(_) ->
    R1 = try fc_tail(?MODULE:id(<<42>>))
         catch error:function_clause -> fc end,
    R2 = try dyn_tail_used(?MODULE:id(<<137>>), ?MODULE:id(3))
         catch error:{badmatch,V1} -> {bm,V1} end,
    R3 = try dyn_tail_unused(?MODULE:id(<<44>>), ?MODULE:id(7))
         catch error:{badmatch,V2} -> {bm,V2} end,
    R4 = try fc_tail(?MODULE:id(<<1:1,7:8>>))
         catch error:function_clause -> fc end,
    (R1 =:= fc) andalso (R2 =:= {bm,<<137>>})
        andalso (R3 =:= {bm,<<44>>}) andalso (R4 =:= {1,<<7>>}).

%% Only clause: 1-bit head + /binary tail (fails unless remaining size % 8 == 0).
%% Over <<1:1,7:8>> (9 bits) the head bit is 1 and the tail byte is <<7>>.
fc_tail(<<A:1,T/binary>>) -> {A,T}.

%% /bits tails carry ANY remainder: the same subjects that fail /binary match
%% /bits, and the tail value is the exact remaining bitstring (id-routed
%% comparands so both sides are runtime bit-syntax).
c_bits_tail(_) ->
    <<A:1,T1/bits>> = ?MODULE:id(<<42>>),
    <<_:15,T2/bits>> = ?MODULE:id(<<42,33>>),
    <<B:8,T3/bits>> = ?MODULE:id(<<7,5:3>>),
    (A =:= 0) andalso (T1 =:= ?MODULE:id(<<42:7>>))
        andalso (T2 =:= ?MODULE:id(<<1:1>>))
        andalso (B =:= 7) andalso (T3 =:= ?MODULE:id(<<5:3>>)).

%% bit_size/byte_size of matched tails (freshly fixed: sizes answer with the
%% REMAINING view, not the whole subject): byte tails report exact bytes;
%% bit tails report exact bits, and byte_size of a ragged tail rounds UP.
c_tail_sizes(_) ->
    <<_:8,T1/binary>> = ?MODULE:id(<<1,2,3,4>>),
    <<_:3,T2/bits>> = ?MODULE:id(<<255,255>>),
    <<_:1,T3/bits>> = ?MODULE:id(<<42>>),
    <<_:16,T4/binary>> = ?MODULE:id(<<9,9>>),
    (byte_size(T1) =:= 3) andalso (bit_size(T1) =:= 24)
        andalso (bit_size(T2) =:= 13) andalso (byte_size(T2) =:= 2)
        andalso (bit_size(T3) =:= 7) andalso (byte_size(T3) =:= 1)
        andalso (bit_size(T4) =:= 0) andalso (byte_size(T4) =:= 0)
        andalso (T4 =:= <<>>).

%% Re-matching a matched tail: a tail is a first-class (bit)string that
%% re-enters bs_start_match -- chain byte tails, then finish a ragged /bits
%% tail with an exact-width field.
c_rematch_tail(_) ->
    <<_:8,T1/binary>> = ?MODULE:id(<<1,2,3,4,5>>),
    <<A:16,T2/binary>> = T1,
    <<B:8,T3/binary>> = T2,
    <<_:3,U1/bits>> = ?MODULE:id(<<255,254>>),
    <<C:5,U2/bits>> = U1,
    <<D:8>> = U2,
    (A =:= 515) andalso (B =:= 4) andalso (T3 =:= <<5>>)
        andalso (C =:= 31) andalso (D =:= 254)
        andalso (bit_size(U2) =:= 8).

%% zero_tail/1: an exact-width clause accepts ONLY the exact size -- longer
%% input falls through to the tail clause, and an 8-bit two-field clause
%% rejects a 24-bit subject (the test_zero_tail/test_zero_tail2 probes as
%% case fallthrough).
c_zero_tail(_) ->
    ({one,7} =:= zt(?MODULE:id(<<7>>)))
        andalso ({more,1} =:= zt(?MODULE:id(<<1,2>>)))
        andalso (other =:= zt(?MODULE:id(<<>>)))
        andalso (nibbles =:= zt2(?MODULE:id(<<16#5A>>)))
        andalso (no_match =:= zt2(?MODULE:id(<<1,2,3>>))).

zt(Bin) ->
    case Bin of
        <<A:8>> -> {one,A};
        <<A:8,_/binary>> -> {more,A};
        _ -> other
    end.

zt2(Bin) ->
    case Bin of
        <<5:4,10:4>> -> nibbles;
        _ -> no_match
    end.

%% huge_tail/1 (bounded): the real suite's 16#1001-bit skip-tail (the AArch64
%% cmp-immediate probe, ~513 bytes -- the 2Gb x86_64 probe is out of scope) --
%% a wide literal-width skip both succeeds on the exact size and falls through
%% on a short subject.
c_long_tail(_) ->
    N = ?MODULE:id(16#1001),
    (42 =:= ht(?MODULE:id(<<42,0:N>>)))
        andalso (no_match =:= ht(?MODULE:id(<<0:8,0:10>>)))
        andalso (no_match =:= ht(?MODULE:id(<<>>))).

ht(Bin) ->
    case Bin of
        <<B:8,_:16#1001>> -> B;
        _ -> no_match
    end.
