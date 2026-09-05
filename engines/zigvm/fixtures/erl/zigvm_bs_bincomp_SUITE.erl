%% Curated PURE subset of erts/emulator/test/bs_bincomp_SUITE.erl (E7 suite
%% closure). The real suite (Per Gustafsson's) exercises BINARY COMPREHENSIONS:
%% byte-aligned and bit-aligned element construction, extended (list<->binary)
%% generators, mixed multi-generator cross products, and nested comprehensions
%% (OTP-16899) — plus a tracing case (OTP-8179) that spawns a tracer process.
%% These cases MIRROR the pure groups (byte_aligned, bit_aligned,
%% extended_byte_aligned, extended_bit_aligned, mixed, the nested regression)
%% as self-contained BOOLEAN assertions over DETERMINISTIC data, and add the
%% comprehension-specific semantics the group set implies: filters, sized and
%% dynamically-sized elements, odd-size little-endian roundtrips, the
%% stop-at-unmatched-tail generator law, and empty/bit-level results. Every
%% generator source and every dynamic size is routed through the EXPORTED
%% ?MODULE:id/1 — an external call erlc cannot inline or constant-fold — so
%% the RUNTIME bs_create_bin/append + bs_match kernels are exercised, not the
%% compiler's folder. The tracing case is EXCLUDED (spawn/trace_pattern —
%% Stratum-B effects, out of pure scope). No ct/port/node/rand/io dependency —
%% runnable directly on the zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_bs_bincomp_SUITE).
-export([all/0, id/1, c_byte_aligned/1, c_bit_aligned/1, c_ext_byte_aligned/1,
         c_ext_bit_aligned/1, c_mixed/1, c_nested/1, c_filter/1, c_sized/1,
         c_odd_little/1, c_tail_stop/1, c_empty/1, c_bit_result/1]).

all() ->
    [c_byte_aligned, c_bit_aligned, c_ext_byte_aligned, c_ext_bit_aligned,
     c_mixed, c_nested, c_filter, c_sized, c_odd_little, c_tail_stop,
     c_empty, c_bit_result].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants (erlc cannot fold across
%% an exported call — the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

%% byte_aligned/1 (verbatim data): byte elements from byte generators, and
%% 32-bit big->little re-serialisation from both 32-bit and 16-bit sources.
c_byte_aligned(_) ->
    B1 = << <<(X+32)>> || <<X>> <= ?MODULE:id(<<"ABCDEFG">>) >>,
    B2 = << <<X:32/little>> || <<X:32>> <= ?MODULE:id(<<1:32,2:32,3:32,4:32>>) >>,
    B3 = << <<X:32/little>> || <<X:16>> <= ?MODULE:id(<<1:16,2:16,3:16,4:16>>) >>,
    (B1 =:= <<"abcdefg">>)
        andalso (B2 =:= <<1:32/little,2:32/little,3:32/little,4:32/little>>)
        andalso (B3 =:= <<1:32/little,2:32/little,3:32/little,4:32/little>>).

%% bit_aligned/1 (verbatim data): 7-bit elements built from bytes and bytes
%% rebuilt from 7-bit fields; 31-bit little elements from 31- and 15-bit
%% big-endian sources (odd-size, non-byte-aligned accumulation).
c_bit_aligned(_) ->
    B1 = << <<(X+32):7>> || <<X>> <= ?MODULE:id(<<"ABCDEFG">>) >>,
    B2 = << <<(X-32)>> ||
            <<X:7>> <= ?MODULE:id(<<$a:7,$b:7,$c:7,$d:7,$e:7,$f:7,$g:7>>) >>,
    B3 = << <<X:31/little>> || <<X:31>> <= ?MODULE:id(<<1:31,2:31,3:31,4:31>>) >>,
    B4 = << <<X:31/little>> || <<X:15>> <= ?MODULE:id(<<1:15,2:15,3:15,4:15>>) >>,
    (B1 =:= <<$a:7,$b:7,$c:7,$d:7,$e:7,$f:7,$g:7>>)
        andalso (B2 =:= <<"ABCDEFG">>)
        andalso (B3 =:= <<1:31/little,2:31/little,3:31/little,4:31/little>>)
        andalso (B4 =:= <<1:31/little,2:31/little,3:31/little,4:31/little>>).

%% extended_byte_aligned/1 (verbatim data): list generator -> binary result,
%% binary generator -> list result, in both directions at 8/16/32-bit sizes.
c_ext_byte_aligned(_) ->
    B1 = << <<(X+32)>> || X <- ?MODULE:id("ABCDEFG") >>,
    L1 = [(X+32) || <<X>> <= ?MODULE:id(<<"ABCDEFG">>)],
    B2 = << <<X:32/little>> || X <- ?MODULE:id([1,2,3,4]) >>,
    L2 = [X || <<X:16/little>> <= ?MODULE:id(<<1:16,2:16,3:16,4:16>>)],
    (B1 =:= <<"abcdefg">>) andalso (L1 =:= "abcdefg")
        andalso (B2 =:= <<1:32/little,2:32/little,3:32/little,4:32/little>>)
        andalso (L2 =:= [256,512,768,1024]).

%% extended_bit_aligned/1 (verbatim data): the same list<->binary crossings
%% at NON-BYTE sizes (7-, 31- and 15-bit little fields).
c_ext_bit_aligned(_) ->
    B1 = << <<(X+32):7>> || X <- ?MODULE:id("ABCDEFG") >>,
    L1 = [(X-32) ||
             <<X:7>> <= ?MODULE:id(<<$a:7,$b:7,$c:7,$d:7,$e:7,$f:7,$g:7>>)],
    B2 = << <<X:31/little>> || X <- ?MODULE:id([1,2,3,4]) >>,
    L2 = [X || <<X:15/little>> <= ?MODULE:id(<<1:15,2:15,3:15,4:15>>)],
    (B1 =:= <<$a:7,$b:7,$c:7,$d:7,$e:7,$f:7,$g:7>>)
        andalso (L1 =:= "ABCDEFG")
        andalso (B2 =:= <<1:31/little,2:31/little,3:31/little,4:31/little>>)
        andalso (L2 =:= [256,512,768,1024]).

%% mixed/1 (verbatim data): multi-generator cross products — binary x binary,
%% binary x list, list x list — with byte results, list results, and 3-bit
%% results. Rightmost generator varies fastest.
c_mixed(_) ->
    B1 = << <<(X+Y)>> ||
            <<X>> <= ?MODULE:id(<<1,2,3,4>>), <<Y>> <= ?MODULE:id(<<1,2>>) >>,
    B2 = << <<(X+Y)>> ||
            <<X>> <= ?MODULE:id(<<1,2,3,4>>), Y <- ?MODULE:id([1,2]) >>,
    B3 = << <<(X+Y)>> || X <- ?MODULE:id([1,2,3,4]), Y <- ?MODULE:id([1,2]) >>,
    L1 = [(X+Y) ||
             <<X>> <= ?MODULE:id(<<1,2,3,4>>), <<Y>> <= ?MODULE:id(<<1,2>>)],
    B4 = << <<(X+Y):3>> ||
            <<X:3>> <= ?MODULE:id(<<1:3,2:3,3:3,4:3>>),
            <<Y:3>> <= ?MODULE:id(<<1:3,2:3>>) >>,
    (B1 =:= <<2,3,3,4,4,5,5,6>>) andalso (B2 =:= <<2,3,3,4,4,5,5,6>>)
        andalso (B3 =:= <<2,3,3,4,4,5,5,6>>)
        andalso (L1 =:= [2,3,3,4,4,5,5,6])
        andalso (B4 =:= <<2:3,3:3,3:3,4:3,4:3,5:3,5:3,6:3>>).

%% mixed/1 OTP-16899 regression (verbatim shape): nested binary comprehensions
%% (a comprehension as a /binary segment of an outer comprehension, including
%% the generator-less `|| true` form and a dynamic trailing size).
c_nested(_) ->
    (mixed_nested(?MODULE:id([1,2,3])) =:= <<0,1,0,2,0,3,99>>)
        andalso (nested_flat(?MODULE:id(<<1,2>>)) =:= <<1,1,2,2>>).

mixed_nested(L) ->
    << << << << E:16 >> || E <- L >> || true >>/binary, 99:(?MODULE:id(8))>>.

nested_flat(Bin) ->
    << <<(<< <<B>> || _ <- ?MODULE:id([1,2]) >>)/binary>> || <<B>> <= Bin >>.

%% Filters: a boolean filter drops elements from binary and list results;
%% a filter can drop everything (empty binary result); bit-level (4-bit
%% nibble) generators filter exactly.
c_filter(_) ->
    B1 = << <<X>> || <<X>> <= ?MODULE:id(<<1,2,3,4,5,6>>), X rem 2 =:= 0 >>,
    L1 = [X || <<X>> <= ?MODULE:id(<<5,10,15,20>>), X > 9],
    B2 = << <<X>> || <<X>> <= ?MODULE:id(<<1,2,3>>), X > 100 >>,
    B3 = << <<X:4>> || <<X:4>> <= ?MODULE:id(<<16#5A5A:16>>), X =:= 5 >>,
    (B1 =:= <<2,4,6>>) andalso (L1 =:= [10,15,20]) andalso (B2 =:= <<>>)
        andalso (B3 =:= <<5:4,5:4>>).

%% Sized elements: fixed 16- and 12-bit element sizes, and sizes held in
%% RUNTIME variables (id-routed) on both the construction and match sides.
c_sized(_) ->
    B1 = << <<X:16>> || X <- ?MODULE:id([1,2,3,4]) >>,
    B2 = << <<X:12>> || X <- ?MODULE:id([100,200,3000]) >>,
    N = ?MODULE:id(16),
    B3 = << <<X:N>> || X <- ?MODULE:id([513,514]) >>,
    M = ?MODULE:id(5),
    L4 = [X || <<X:M>> <= ?MODULE:id(<<1:5,2:5,3:5>>)],
    (B1 =:= <<0,1,0,2,0,3,0,4>>)
        andalso (B2 =:= <<100:12,200:12,3000:12>>)
        andalso (bit_size(B2) =:= 36)
        andalso (B3 =:= <<2,1,2,2>>)
        andalso (L4 =:= [1,2,3]).

%% Odd-size little-endian elements: 13- and 11-bit little fields roundtrip
%% through construct-then-match comprehensions, and the 13-bit little layout
%% is pinned to the erts 8k+r shape (low byte first, then the top 5 bits) so
%% a self-consistent-but-wrong layout cannot pass.
c_odd_little(_) ->
    Vals = ?MODULE:id([0, 1, 3000, 8191, 4096]),
    B13 = << <<V:13/little>> || V <- Vals >>,
    R13 = [V || <<V:13/little>> <= B13],
    W = ?MODULE:id([1, 511, 1023, 512]),
    B11 = << <<V:11/little>> || V <- W >>,
    R11 = [V || <<V:11/little>> <= B11],
    C = ?MODULE:id(2748),
    (R13 =:= Vals) andalso (R11 =:= W)
        andalso (bit_size(B13) =:= 65) andalso (bit_size(B11) =:= 44)
        andalso (<<C:13/little>> =:= <<(C band 255):8, (C bsr 8):5>>)
        andalso (<< <<V:13/little>> || <<V:13/little>> <= ?MODULE:id(B13) >>
                     =:= B13).

%% Generator termination law: a bitstring generator STOPS (silently discards
%% the tail) when the pattern no longer matches — a short byte tail under a
%% 16-bit pattern, a 7-byte source under a 32-bit pattern, a 4-bit source
%% under an 8-bit pattern, and a literal-prefix pattern that stops matching
%% mid-stream.
c_tail_stop(_) ->
    B1 = << <<X:16>> || <<X:16>> <= ?MODULE:id(<<1,2,3>>) >>,
    L1 = [X || <<X:32>> <= ?MODULE:id(<<0,0,0,7,0,0,0>>)],
    B2 = << <<X>> || <<X:8>> <= ?MODULE:id(<<1:4>>) >>,
    L2 = [X || <<1:8,X:8>> <= ?MODULE:id(<<1,5,1,6,2,7>>)],
    (B1 =:= <<1,2>>) andalso (L1 =:= [7]) andalso (B2 =:= <<>>)
        andalso (L2 =:= [5,6]).

%% Empty sources and empty results: comprehensions over <<>> and [] denote
%% the empty binary/list, and a filter that rejects everything does too.
c_empty(_) ->
    (<< <<X>> || <<X>> <= ?MODULE:id(<<>>) >> =:= <<>>)
        andalso (<< <<X:16>> || X <- ?MODULE:id([]) >> =:= <<>>)
        andalso ([X || <<X:7>> <= ?MODULE:id(<<>>)] =:= [])
        andalso (<< <<Y:3>> || <<Y:3>> <= ?MODULE:id(<<6:3>>), Y < 2 >> =:= <<>>)
        andalso (bit_size(<< <<X>> || <<X>> <= ?MODULE:id(<<>>) >>) =:= 0).

%% Bit-level results: a comprehension whose total size is not a multiple of 8
%% denotes a BITSTRING (not a binary) with the exact bit count and value.
c_bit_result(_) ->
    B = << <<X:3>> || X <- ?MODULE:id([1,2,3]) >>,
    C = << <<X:5>> || <<X:5>> <= ?MODULE:id(<<1:5,2:5,3:5,4:5>>) >>,
    (bit_size(B) =:= 9) andalso (B =:= <<1:3,2:3,3:3>>)
        andalso is_bitstring(B) andalso (not is_binary(B))
        andalso (bit_size(C) =:= 20) andalso (C =:= <<1:5,2:5,3:5,4:5>>).
