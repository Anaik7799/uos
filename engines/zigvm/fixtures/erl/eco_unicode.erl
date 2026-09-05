%% eco_unicode — a reduced ecosystem app exercising the UTF-8 codec surface zigvm
%% genuinely hosts today (gap-erlang-cover-unicode, DIVERGENCE 655).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): an Erlang FIXTURE, not harness
%% logic. Self-contained single module run as `zigvm run eco_unicode.beam suite` —
%% no spawn, no --pa closure. Exercises the implemented `unicode:` codec envelope
%% (src/bifs/bif_table.zig: unicode:characters_to_binary/2 + characters_to_list/2,
%% the UTF-8 encode/decode a text-processing app hits) over ASCII, Latin-1
%% (café), multi-byte (emoji U+1F600 → 4-byte UTF-8), iolists, the round-trip
%% identity, and the invalid-UTF-8 {error,Good,Rest} path — byte-EQ vs OTP-30.
%%
%% HONESTY BOUND: only characters_to_binary/2 + characters_to_list/2 are the
%% implemented BIF envelope (the /1 default-encoding + /3 forms are NOT wired —
%% they dispatch undef). This fixture stays STRICTLY inside the /2 envelope so its
%% EQ is real, never a masked gap.
-module(eco_unicode).
-export([suite/0]).

suite() ->
    %% characters_to_binary/2 — encode to UTF-8.
    C1  = (unicode:characters_to_binary("hello", utf8) =:= <<"hello">>),
    C2  = (unicode:characters_to_binary("café", utf8) =:= <<99, 97, 102, 195, 169>>),
    C3  = (unicode:characters_to_binary([16#1F600], utf8) =:= <<240, 159, 152, 128>>),
    C4  = (unicode:characters_to_binary([<<"a">>, "b", $c], utf8) =:= <<"abc">>),
    C5  = (unicode:characters_to_binary([], utf8) =:= <<>>),
    C6  = (unicode:characters_to_binary(<<"ok">>, utf8) =:= <<"ok">>),
    %% characters_to_list/2 — decode from UTF-8.
    C7  = (unicode:characters_to_list(<<"hello">>, utf8) =:= "hello"),
    C8  = (unicode:characters_to_list(<<"café"/utf8>>, utf8) =:= [99, 97, 102, 233]),
    C9  = (unicode:characters_to_list(<<240, 159, 152, 128>>, utf8) =:= [16#1F600]),
    C10 = (unicode:characters_to_list(<<>>, utf8) =:= []),
    %% ROUND-TRIP: decode(encode(L)) == L over a mixed codepoint list.
    L   = [$A, 233, 16#20AC, 16#1F600, $z],   %% A, é, €, 😀, z
    Enc = unicode:characters_to_binary(L, utf8),
    C11 = (unicode:characters_to_list(Enc, utf8) =:= L),
    C12 = (is_binary(Enc) andalso byte_size(Enc) =:= (1 + 2 + 3 + 4 + 1)),
    %% INVALID UTF-8: a lone continuation byte → {error, Decoded, Rest}.
    C13 = (unicode:characters_to_binary(<<128>>, utf8) =:= {error, <<>>, <<128>>}),
    C14 = (unicode:characters_to_list(<<$a, 255>>, utf8) =:= {error, "a", <<255>>}),
    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14
    of
        true -> ok;
        false -> fail
    end.
