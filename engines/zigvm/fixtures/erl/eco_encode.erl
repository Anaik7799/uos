%% eco_encode — a reduced ecosystem app exercising the `base64` codec and the
%% `uri_string` URI module zigvm now hosts via the preloaded stock stdlib
%% (gap-hof-encode, DIVERGENCE 670). Both are Erlang code, not BIFs — undef
%% before this slice.
%%
%% Run as `zigvm run eco_encode.beam suite`. HONESTY BOUNDS: base64/uri_string
%% outputs are deterministic (binaries / flat strings / order-independent parse
%% maps). uri_string:recompose/1 is NOT asserted (an internal-dep gap, still
%% undef on zigvm); every asserted uri_string fn (parse/quote/unquote/
%% compose_query/dissect_query) resolves.
-module(eco_encode).
-export([suite/0]).

suite() ->
    %% base64 — encode/decode/round-trip, string + binary forms, padding cases.
    C1  = (base64:encode("hello world") =:= <<"aGVsbG8gd29ybGQ=">>),
    C2  = (base64:decode(<<"aGVsbG8gd29ybGQ=">>) =:= <<"hello world">>),
    C3  = (base64:encode_to_string("foo") =:= "Zm9v"),
    C4  = (base64:decode_to_string(<<"Zm9v">>) =:= "foo"),
    C5  = (base64:decode(base64:encode(<<1, 2, 3, 255, 0, 128>>)) =:= <<1, 2, 3, 255, 0, 128>>),
    C6  = (base64:encode(<<>>) =:= <<>>),
    C7  = (base64:encode(<<"a">>) =:= <<"YQ==">>),
    C8  = (base64:encode(<<"ab">>) =:= <<"YWI=">>),
    C9  = (base64:encode(<<"abc">>) =:= <<"YWJj">>),

    %% uri_string — parse (order-independent map), quote/unquote, query codec.
    C10 = (uri_string:parse("http://example.com:8080/path?q=1#frag")
               =:= #{scheme => "http", host => "example.com", port => 8080,
                     path => "/path", query => "q=1", fragment => "frag"}),
    C11 = (uri_string:parse("mailto:user@example.com")
               =:= #{scheme => "mailto", path => "user@example.com"}),
    C12 = (uri_string:quote("a b/c") =:= "a%20b%2Fc"),
    C13 = (uri_string:unquote("a%20b") =:= "a b"),
    C14 = (uri_string:compose_query([{"a", "1"}, {"b", "2"}]) =:= "a=1&b=2"),
    C15 = (uri_string:dissect_query("a=1&b=2") =:= [{"a", "1"}, {"b", "2"}]),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14 andalso C15
    of
        true -> ok;
        false -> fail
    end.
