%% eco_binary — a reduced ecosystem app exercising the BINARY + term-CONVERSION
%% surface zigvm genuinely hosts today (gap-erlang-cover-binary, DIVERGENCE 654).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): an Erlang FIXTURE, not harness
%% logic. Self-contained single module run as `zigvm run eco_binary.beam suite` —
%% no spawn, no --pa closure. Deliberately exercises the `binary:` module + the
%% integer<->binary conversion BIFs that resolve to zigvm's implemented envelope
%% (src/bifs/bif_table.zig `binary`: part/2,3, match/2,3, matches/2, split/2, at/2,
%% first/1, last/1, copy/1,2, decode_unsigned/1,2, encode_unsigned/1,2,
%% compile_pattern/1, longest_common_prefix/1, list_to_bin/1, referenced_byte_size/1;
%% conv: integer_to_binary/1,2, binary_to_integer/1,2, list_to_binary, binary_to_list)
%% plus the bit-syntax construct/match. The pure byte-manipulation surface a
%% gleam/elixir-style app hits — genuinely runnable and byte-EQ vs pinned OTP-30.
%%
%% HONESTY BOUND: only the functions above are the implemented BIF envelope. This
%% fixture stays STRICTLY inside it so its EQ is real, never a masked gap.
-module(eco_binary).
-export([suite/0]).

suite() ->
    %% binary: part / match / matches / split
    C1  = (binary:part(<<"hello">>, 1, 3) =:= <<"ell">>),
    C2  = (binary:part(<<"hello">>, {1, 3}) =:= <<"ell">>),
    C3  = (binary:match(<<"abcabc">>, <<"bc">>) =:= {1, 2}),
    C4  = (binary:match(<<"abc">>, <<"zz">>) =:= nomatch),
    C5  = (binary:matches(<<"abcabc">>, <<"bc">>) =:= [{1, 2}, {4, 2}]),
    C6  = (binary:split(<<"a,b,c">>, <<",">>) =:= [<<"a">>, <<"b,c">>]),
    C7  = (binary:split(<<"a,b,c">>, <<",">>, [global]) =:= [<<"a">>, <<"b">>, <<"c">>]),
    %% binary: at / first / last / copy / referenced_byte_size / list_to_bin
    C8  = (binary:at(<<7, 8, 9>>, 1) =:= 8),
    C9  = (binary:first(<<7, 8>>) =:= 7),
    C10 = (binary:last(<<7, 8>>) =:= 8),
    C11 = (binary:copy(<<"ab">>, 3) =:= <<"ababab">>),
    C12 = (binary:copy(<<"x">>) =:= <<"x">>),
    C13 = (binary:list_to_bin([<<"ab">>, "cd", [$e]]) =:= <<"abcde">>),
    C14 = (binary:longest_common_prefix([<<"abcx">>, <<"abcy">>]) =:= 3),
    %% binary: unsigned codecs
    C15 = (binary:decode_unsigned(<<1, 0>>) =:= 256),
    C16 = (binary:encode_unsigned(256) =:= <<1, 0>>),
    C17 = (binary:decode_unsigned(<<0, 1>>, little) =:= 256),
    %% conversion: integer<->binary (base 10 + 16)
    C18 = (integer_to_binary(255) =:= <<"255">>),
    C19 = (integer_to_binary(255, 16) =:= <<"FF">>),
    C20 = (binary_to_integer(<<"255">>) =:= 255),
    C21 = (binary_to_integer(<<"ff">>, 16) =:= 255),
    C22 = (list_to_binary([104, 105]) =:= <<"hi">>),
    C23 = (binary_to_list(<<"hi">>) =:= [104, 105]),
    C24 = (byte_size(<<"xyz">>) =:= 3),
    %% bit-syntax: construct + match (the parser idiom eco apps lean on)
    Packet = <<1:8, 258:16, "ok">>,
    <<Tag:8, Len:16, Rest/binary>> = Packet,
    C25 = (Tag =:= 1) andalso (Len =:= 258) andalso (Rest =:= <<"ok">>),
    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14 andalso C15 andalso C16 andalso C17 andalso C18 andalso C19
        andalso C20 andalso C21 andalso C22 andalso C23 andalso C24 andalso C25
    of
        true -> ok;
        false -> fail
    end.
