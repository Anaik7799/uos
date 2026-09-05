%% http-laneC-cowboy-bif-subset: the pure cowboy/cowlib HTTP-PARSING surface
%% (cowboy's request hot path) runs byte-EQ on zigvm vs pinned OTP-30, loaded
%% from the rebar3-fetched beams (harness/fetch_cowboy; gitignored, fetch-on-demand).
%% Deps on zigvm --pa: cowlib/ebin/{cow_qs,cow_cookie,cow_date}.beam +
%% cowboy/ebin/cowboy_bstr.beam + stdlib/ebin/{lists,binary,string}.beam.
%% All five display byte-identically:
%%   {qs,[{<<"a">>,<<"1">>},{<<"b">>,<<"2">>}]} {urldec,<<"a b">>}
%%   {urlenc,<<"a+b%26c">>} {lower,<<"hello">>}
%%   {cookie,[{<<"foo">>,<<"bar">>},{<<"baz">>,<<"qux">>}]}
-module(zigvm_cowboy_diff).
-export([t/1]).
t(_) ->
    erlang:display({qs,     cow_qs:parse_qs(<<"a=1&b=2">>)}),
    erlang:display({urldec, cow_qs:urldecode(<<"a%20b">>)}),
    erlang:display({urlenc, cow_qs:urlencode(<<"a b&c">>)}),
    erlang:display({lower,  cowboy_bstr:to_lower(<<"HeLLo">>)}),
    erlang:display({cookie, cow_cookie:parse_cookie(<<"foo=bar; baz=qux">>)}),
    ok.
