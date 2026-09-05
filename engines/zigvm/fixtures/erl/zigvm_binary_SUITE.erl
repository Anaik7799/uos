%% Curated PURE subset of erts/emulator/test/binary_SUITE.erl (E7 suite closure).
%% The real erts suite is dominated by term_to_binary / io-vec / huge-binary and
%% port machinery; the PURE, representation-independent core it shares with the
%% `binary` module BIFs is what we mirror here. Every case is a self-contained
%% boolean assertion over VALUE-STABLE binary operations that BOTH VMs must
%% compute byte-for-byte identically: byte_size/1, binary:part/binary_part,
%% binary:split/2,3, binary:at/first/last, binary_to_list/list_to_bin,
%% binary:copy/1,2, binary:matches/2, binary:longest_common_prefix/suffix,
%% binary:encode_unsigned/decode_unsigned. No ct/port/node/timing dependency.
-module(zigvm_binary_SUITE).
-export([all/0, c_byte_size/1, c_binary_part/1, c_part_from_end/1, c_split/1,
         c_at_first_last/1, c_to_list_and_back/1, c_copy/1, c_matches/1,
         c_longest_common/1, c_encode_decode_unsigned/1, c_bit_syntax/1,
         c_concat_part_roundtrip/1]).

all() ->
    [c_byte_size, c_binary_part, c_part_from_end, c_split,
     c_at_first_last, c_to_list_and_back, c_copy, c_matches,
     c_longest_common, c_encode_decode_unsigned, c_bit_syntax,
     c_concat_part_roundtrip].

%% byte_size/1: byte count of a binary is exact and stable.
c_byte_size(_) ->
    (byte_size(<<>>) =:= 0)
        andalso (byte_size(<<1,2,3,4,5>>) =:= 5)
        andalso (byte_size(<<"hello">>) =:= 5)
        andalso (byte_size(<<0:64>>) =:= 8).

%% binary:part/2,3 == binary_part/2,3 : sub-range extraction, value-stable.
c_binary_part(_) ->
    B = <<1,2,3,4,5,6,7,8,9,10>>,
    (binary:part(B, 0, 3) =:= <<1,2,3>>)
        andalso (binary:part(B, {2, 4}) =:= <<3,4,5,6>>)
        andalso (binary_part(B, 0, 3) =:= <<1,2,3>>)
        andalso (binary_part(B, byte_size(B), 0) =:= <<>>)
        andalso (binary:part(B, 7, 3) =:= <<8,9,10>>).

%% binary:part with a negative length reads leftwards from the offset.
c_part_from_end(_) ->
    B = <<1,2,3,4,5,6,7,8,9,10>>,
    (binary:part(B, {byte_size(B), -3}) =:= <<8,9,10>>)
        andalso (binary:part(B, 10, -10) =:= B)
        andalso (binary:part(B, 5, -2) =:= <<4,5>>).

%% binary:split/2,3 : split on a pattern; /3 with `global` splits every match.
c_split(_) ->
    (binary:split(<<"a,b,c">>, <<",">>) =:= [<<"a">>, <<"b,c">>])
        andalso (binary:split(<<"a,b,c">>, <<",">>, [global]) =:= [<<"a">>, <<"b">>, <<"c">>])
        andalso (binary:split(<<"abc">>, <<",">>) =:= [<<"abc">>])
        andalso (binary:split(<<"x=1">>, <<"=">>) =:= [<<"x">>, <<"1">>]).

%% binary:at/2, first/1, last/1 : indexed byte access.
c_at_first_last(_) ->
    B = <<10,20,30,40,50>>,
    (binary:at(B, 0) =:= 10)
        andalso (binary:at(B, 4) =:= 50)
        andalso (binary:first(B) =:= 10)
        andalso (binary:last(B) =:= 50).

%% binary_to_list/1 and binary:list_to_bin/1 are mutual inverses on byte lists.
c_to_list_and_back(_) ->
    B = <<1,2,3,4,5>>,
    L = binary_to_list(B),
    (L =:= [1,2,3,4,5])
        andalso (binary:list_to_bin(L) =:= B)
        andalso (binary:list_to_bin([<<1,2>>, 3, [4,5]]) =:= B)
        andalso (binary_to_list(<<>>) =:= []).

%% binary:copy/1,2 : content-identical, count-parameterised replication.
c_copy(_) ->
    (binary:copy(<<1,2,3>>) =:= <<1,2,3>>)
        andalso (binary:copy(<<"ab">>, 3) =:= <<"ababab">>)
        andalso (binary:copy(<<7>>, 0) =:= <<>>)
        andalso (byte_size(binary:copy(<<0,0>>, 5)) =:= 10).

%% binary:matches/2 : all non-overlapping match positions as {Start,Len}.
c_matches(_) ->
    (binary:matches(<<"ababab">>, <<"ab">>) =:= [{0,2}, {2,2}, {4,2}])
        andalso (binary:matches(<<"xyz">>, <<"q">>) =:= [])
        andalso (binary:matches(<<"aaa">>, <<"aa">>) =:= [{0,2}]).

%% binary:longest_common_prefix/1 and longest_common_suffix/1 over a list.
c_longest_common(_) ->
    (binary:longest_common_prefix([<<"foobar">>, <<"foobaz">>, <<"foo">>]) =:= 3)
        andalso (binary:longest_common_suffix([<<"1x">>, <<"2x">>, <<"33x">>]) =:= 1)
        andalso (binary:longest_common_prefix([<<"abc">>, <<"xyz">>]) =:= 0)
        andalso (binary:longest_common_prefix([<<"same">>, <<"same">>]) =:= 4).

%% binary:encode_unsigned/1,2 and decode_unsigned/1,2 : big/little-endian
%% integer<->binary round trips, value-stable.
c_encode_decode_unsigned(_) ->
    (binary:encode_unsigned(258) =:= <<1,2>>)
        andalso (binary:encode_unsigned(258, little) =:= <<2,1>>)
        andalso (binary:decode_unsigned(<<1,2>>) =:= 258)
        andalso (binary:decode_unsigned(<<2,1>>, little) =:= 258)
        andalso (binary:decode_unsigned(binary:encode_unsigned(1000000)) =:= 1000000)
        andalso (binary:encode_unsigned(0) =:= <<0>>).

%% bit-syntax construction/matching agree on segment layout, value-stable.
c_bit_syntax(_) ->
    <<A, B, C>> = <<1,2,3>>,
    <<X:16, Y:16>> = <<16#0102:16, 16#0304:16>>,
    (A =:= 1) andalso (B =:= 2) andalso (C =:= 3)
        andalso (X =:= 16#0102) andalso (Y =:= 16#0304)
        andalso (<<1:4, 2:4>> =:= <<16#12>>)
        andalso (byte_size(<<0:1, 0:7>>) =:= 1).

%% concat then part recovers each half — a homomorphism-style round trip.
c_concat_part_roundtrip(_) ->
    L = <<1,2,3>>,
    R = <<4,5,6,7>>,
    Both = <<L/binary, R/binary>>,
    (byte_size(Both) =:= 7)
        andalso (binary:part(Both, 0, byte_size(L)) =:= L)
        andalso (binary:part(Both, byte_size(L), byte_size(R)) =:= R).
