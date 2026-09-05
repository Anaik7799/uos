%% eco_string — a reduced ecosystem app exercising the `string:` and `proplists:`
%% modules zigvm now hosts via the preloaded stock stdlib (gap-hof-string,
%% DIVERGENCE 662). `string:` needs its transitive closure (string + unicode +
%% unicode_util); `proplists:` is a pure accessor module. Both are Erlang code,
%% not BIFs — undef before this slice.
%%
%% Run as `zigvm run eco_string.beam suite` — the END-TO-END proof the `run` CLI
%% preloads the extended stdlib closure. HONESTY BOUNDS: every assertion compares
%% a FLAT string (list of codepoints), a binary, an int, or a bool — no chardata-
%% nesting-shaped return (replace/pad are deliberately avoided), so the EQ turns
%% only on the module semantics, not a printer/representation quirk.
-module(eco_string).
-export([suite/0]).

suite() ->
    %% string: — case, trim, split, search, slice, length (unicode grapheme).
    C1  = (string:uppercase("hello world") =:= "HELLO WORLD"),
    C2  = (string:lowercase("HeLLO") =:= "hello"),
    C3  = (string:titlecase("hello") =:= "Hello"),
    C4  = (string:trim("  padded  ") =:= "padded"),
    C5  = (string:trim("xxhixx", both, "x") =:= "hi"),
    C6  = (string:split("a,b,c,d", ",", all) =:= ["a", "b", "c", "d"]),
    C7  = (string:length("hello") =:= 5),
    C8  = (string:length("héllo") =:= 5),
    C9  = (string:find("hello world", "world") =:= "world"),
    C10 = (string:find("hello", "zzz") =:= nomatch),
    C11 = (string:prefix("foobar", "foo") =:= "bar"),
    C12 = (string:slice("hello", 1, 3) =:= "ell"),
    C13 = (string:equal("abc", "ABC", true) =:= true),
    C14 = (string:is_empty("") andalso (not string:is_empty("x"))),

    %% proplists: — the property-list accessor surface.
    L = [{a, 1}, {b, 2}, {c, 3}, flag],
    C15 = (proplists:get_value(b, L) =:= 2),
    C16 = (proplists:get_value(z, L, default) =:= default),
    C17 = (proplists:get_bool(flag, L) =:= true),
    C18 = (proplists:lookup(a, L) =:= {a, 1}),
    C19 = (proplists:is_defined(c, L) andalso (not proplists:is_defined(z, L))),
    C20 = (proplists:delete(b, L) =:= [{a, 1}, {c, 3}, flag]),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14 andalso C15 andalso C16 andalso C17 andalso C18 andalso C19
        andalso C20
    of
        true -> ok;
        false -> fail
    end.
