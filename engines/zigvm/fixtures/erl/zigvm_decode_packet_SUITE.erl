%% zigvm_decode_packet_SUITE — a PURE curated subset of erts `decode_packet_SUITE`,
%% in the common_test SUITE shape (`all/0` + `Case(Config)`), NO common_test /
%% test_server dependency. Every case drives `erlang:decode_packet/3` over the
%% FRAMING packet types (raw/0, sz1/2/4, line, sunrm, cdr, fcgi, tpkt, asn1 — every
%% type whose erts `packet_parse` returns a plain-binary body), asserting the exact
%% `{ok, Body, Rest} | {more, Length|undefined} | {error, invalid}` term OTP
%% produces. These are byte-for-byte identical on the OTP-30 oracle and zigvm
%% (bifs/erlang.zig `decode_packet_3`, a faithful port of erts `packet_get_length`/
%% `packet_get_body`).
%%
%% EXCLUDED (the HONEST scope limit, not silently dropped): the STRUCTURED protocol
%% types `http`/`httph`/`http_bin`/`httph_bin`/`ssl_tls`, whose erts `packet_parse`
%% builds `{http_request,…}`/`{http_header,…}`/`{ssl_tls,…}` terms via the ~350-line
%% HTTP header/method parser + SSL record parser. zigvm does NOT yet implement those
%% (it raises badarg — a documented divergence kept OUT of this suite), so the
%% `erlang:decode_packet/3` bif row stays JUSTIFIED with those five types named;
%% this suite curates ONLY the framing subset, which is genuinely EQ. When the
%% structured parser lands the excluded cases re-enter and the bif flips EQ.
%%
%% The packet type travels through `?MODULE:id/1` so the compiler cannot fold it.
%% A case returns the atom `true` on success.
-module(zigvm_decode_packet_SUITE).

-export([all/0,
         c_raw/1, c_sz1/1, c_sz2/1, c_sz4/1, c_line/1, c_line_opts/1,
         c_sunrm/1, c_tpkt/1, c_cdr/1, c_asn1/1, c_bad_option/1,
         c_http_request/1, c_http_response/1, c_http_error/1, c_http_more/1,
         c_http_bin/1, c_http_uri/1, c_http_methods/1,
         c_httph_known/1, c_httph_case/1, c_httph_unknown/1, c_httph_eoh/1,
         c_httph_more/1, c_httph_bin/1, c_httph_value/1,
         c_ssl_tls/1, c_ssl_tls_more/1,
         id/1]).

all() ->
    [c_raw, c_sz1, c_sz2, c_sz4, c_line, c_line_opts,
     c_sunrm, c_tpkt, c_cdr, c_asn1, c_bad_option,
     c_http_request, c_http_response, c_http_error, c_http_more,
     c_http_bin, c_http_uri, c_http_methods,
     c_httph_known, c_httph_case, c_httph_unknown, c_httph_eoh,
     c_httph_more, c_httph_bin, c_httph_value,
     c_ssl_tls, c_ssl_tls_more].

id(X) -> X.

dp(Type, Bin, Opts) -> erlang:decode_packet(id(Type), Bin, Opts).

%% --- raw/0: the whole binary is the body; empty ⇒ {more, undefined} ----------
c_raw(_) ->
    (dp(0, <<1, 2, 3>>, []) =:= {ok, <<1, 2, 3>>, <<>>})
        andalso (dp(raw, <<1, 2, 3>>, []) =:= {ok, <<1, 2, 3>>, <<>>})
        andalso (dp(0, <<>>, []) =:= {more, undefined}).

%% --- type 1: a 1-byte length prefix; body EXCLUDES the header -----------------
c_sz1(_) ->
    (dp(1, <<3, $a, $b, $c, 4, 5>>, []) =:= {ok, <<"abc">>, <<4, 5>>})
        andalso (dp(1, <<3, $a>>, []) =:= {more, 4})
        andalso (dp(1, <<>>, []) =:= {more, undefined}).

%% --- type 2: a 2-byte big-endian length prefix -------------------------------
c_sz2(_) ->
    (dp(2, <<0, 3, $a, $b, $c>>, []) =:= {ok, <<"abc">>, <<>>})
        andalso (dp(2, <<0, 3, $a>>, []) =:= {more, 5}).

%% --- type 4: a 4-byte big-endian length prefix -------------------------------
c_sz4(_) ->
    (dp(4, <<0, 0, 0, 2, 9, 9, 7>>, []) =:= {ok, <<9, 9>>, <<7>>})
        andalso (dp(4, <<0, 0, 0, 5, 1, 2>>, []) =:= {more, 9}).

%% --- line: default '\n'; the body INCLUDES the terminator --------------------
c_line(_) ->
    (dp(line, <<"hello\nworld">>, []) =:= {ok, <<"hello\n">>, <<"world">>})
        andalso (dp(line, <<"noline">>, []) =:= {more, undefined}).

%% --- line options: line_delimiter, line_length (truncate), packet_size (cap) --
c_line_opts(_) ->
    (dp(line, <<"a;b">>, [{line_delimiter, $;}]) =:= {ok, <<"a;">>, <<"b">>})
        andalso (dp(line, <<"abcdef">>, [{line_length, 3}]) =:= {ok, <<"abc">>, <<"def">>})
        andalso (dp(line, <<"abcdef">>, [{packet_size, 3}]) =:= {error, invalid}).

%% --- sunrm: a 4-byte length header; body is the WHOLE packet ------------------
c_sunrm(_) ->
    dp(sunrm, <<16#80, 0, 0, 3, $a, $b, $c>>, []) =:= {ok, <<16#80, 0, 0, 3, $a, $b, $c>>, <<>>}.

%% --- tpkt: a 4-byte header (vrsn=3); a wrong version ⇒ {error, invalid} -------
c_tpkt(_) ->
    (dp(tpkt, <<3, 0, 0, 6, 1, 2>>, []) =:= {ok, <<3, 0, 0, 6, 1, 2>>, <<>>})
        andalso (dp(tpkt, <<4, 0, 0, 6>>, []) =:= {error, invalid}).

%% --- cdr: "GIOP" magic; a byte-order flag picks BE/LE size; bad magic ⇒ error --
c_cdr(_) ->
    BE = <<"GIOP", 1, 0, 0, 0, 0, 0, 0, 2, 88, 89>>,
    LE = <<"GIOP", 1, 0, 1, 0, 2, 0, 0, 0, 88, 89>>,
    (dp(cdr, BE, []) =:= {ok, BE, <<>>})
        andalso (dp(cdr, LE, []) =:= {ok, LE, <<>>})
        andalso (dp(cdr, <<"XIOP", 1, 0, 0, 0, 0, 0, 0, 2>>, []) =:= {error, invalid}).

%% --- asn1: a BER length; a plain-binary body ---------------------------------
c_asn1(_) ->
    %% tag 0x30 (SEQUENCE), short-form length 3, then 3 content bytes + trailer.
    (dp(asn1, <<16#30, 3, 1, 2, 3, 9>>, []) =:= {ok, <<16#30, 3, 1, 2, 3>>, <<9>>})
        andalso (dp(asn1, <<16#30, 3, 1>>, []) =:= {more, 5}).

%% --- a bad option value raises badarg ----------------------------------------
c_bad_option(_) ->
    A = try dp(1, <<0>>, [{packet_size, -1}]) catch error:badarg -> caught end,
    B = try dp(1, <<0>>, [bogus_opt]) catch error:badarg -> caught end,
    (A =:= caught) andalso (B =:= caught).

%% --- http request line → {http_request, Method, Uri, {Maj,Min}} (E41-T1) -----
c_http_request(_) ->
    (dp(http, <<"GET /path HTTP/1.1\r\n">>, [])
        =:= {ok, {http_request, 'GET', {abs_path, "/path"}, {1, 1}}, <<>>})
        andalso (dp(http, <<"POST /x HTTP/1.0\r\nrest">>, [])
            =:= {ok, {http_request, 'POST', {abs_path, "/x"}, {1, 0}}, <<"rest">>}).

%% --- http response line → {http_response, {Maj,Min}, Status, Phrase} ---------
c_http_response(_) ->
    (dp(http, <<"HTTP/1.1 200 OK\r\n">>, [])
        =:= {ok, {http_response, {1, 1}, 200, "OK"}, <<>>})
        andalso (dp(http, <<"HTTP/1.0 404 Not Found\r\n">>, [])
            =:= {ok, {http_response, {1, 0}, 404, "Not Found"}, <<>>}).

%% --- a non-request/response line → {http_error, WholeLine} -------------------
c_http_error(_) ->
    (dp(http, <<"Host: example.com\r\n">>, [])
        =:= {ok, {http_error, "Host: example.com\r\n"}, <<>>})
        andalso (dp(http, <<"\r\n">>, []) =:= {ok, {http_error, "\r\n"}, <<>>}).

%% --- no line terminator yet → {more, undefined} -----------------------------
c_http_more(_) ->
    (dp(http, <<"GET / HTTP/1.1">>, []) =:= {more, undefined})
        andalso (dp(http, <<>>, []) =:= {more, undefined}).

%% --- http_bin: binary bodies (method-atom + version identical to http) ------
c_http_bin(_) ->
    (dp(http_bin, <<"GET /p HTTP/1.1\r\n">>, [])
        =:= {ok, {http_request, 'GET', {abs_path, <<"/p">>}, {1, 1}}, <<>>})
        andalso (dp(http_bin, <<"HTTP/1.1 200 OK\r\n">>, [])
            =:= {ok, {http_response, {1, 1}, 200, <<"OK">>}, <<>>}).

%% --- URI forms: '*', absoluteURI (with/without port), scheme -----------------
c_http_uri(_) ->
    (dp(http, <<"GET * HTTP/1.1\r\n">>, [])
        =:= {ok, {http_request, 'GET', '*', {1, 1}}, <<>>})
        andalso (dp(http, <<"GET http://h/p HTTP/1.1\r\n">>, [])
            =:= {ok, {http_request, 'GET', {absoluteURI, http, "h", undefined, "/p"}, {1, 1}}, <<>>})
        andalso (dp(http, <<"GET http://h:8/p HTTP/1.1\r\n">>, [])
            =:= {ok, {http_request, 'GET', {absoluteURI, http, "h", 8, "/p"}, {1, 1}}, <<>>})
        andalso (dp(http, <<"GET host:99 HTTP/1.1\r\n">>, [])
            =:= {ok, {http_request, 'GET', {scheme, "host", "99"}, {1, 1}}, <<>>}).

%% --- the 7 known methods are atoms; an unknown method stays a string ---------
%% (self-contained: no lists:*/atom_to_binary — the fixture-purity convention.)
c_http_methods(_) ->
    M = fun(Bin, Expect) ->
        dp(http, Bin, []) =:= {ok, {http_request, Expect, {abs_path, "/"}, {1, 1}}, <<>>}
    end,
    M(<<"OPTIONS / HTTP/1.1\r\n">>, 'OPTIONS')
        andalso M(<<"GET / HTTP/1.1\r\n">>, 'GET')
        andalso M(<<"HEAD / HTTP/1.1\r\n">>, 'HEAD')
        andalso M(<<"POST / HTTP/1.1\r\n">>, 'POST')
        andalso M(<<"PUT / HTTP/1.1\r\n">>, 'PUT')
        andalso M(<<"DELETE / HTTP/1.1\r\n">>, 'DELETE')
        andalso M(<<"TRACE / HTTP/1.1\r\n">>, 'TRACE')
        andalso M(<<"PATCH / HTTP/1.1\r\n">>, "PATCH").

%% --- httph: a KNOWN header → canonical atom + erts Bit number (E42-T1) -------
%% (a trailing byte after \r\n is required — the erts continuation lookahead.)
c_httph_known(_) ->
    (dp(httph, <<"Content-Length: 42\r\nrest">>, [])
        =:= {ok, {http_header, 38, 'Content-Length', "Content-Length", "42"}, <<"rest">>})
        andalso (dp(httph, <<"Host: h\r\nx">>, [])
            =:= {ok, {http_header, 14, 'Host', "Host", "h"}, <<"x">>}).

%% --- httph: case-INSENSITIVE match → canonical atom; Reserved = original -----
c_httph_case(_) ->
    (dp(httph, <<"content-length: 42\r\nx">>, [])
        =:= {ok, {http_header, 38, 'Content-Length', "content-length", "42"}, <<"x">>})
        andalso (dp(httph, <<"CONTENT-LENGTH: 42\r\nx">>, [])
            =:= {ok, {http_header, 38, 'Content-Length', "CONTENT-LENGTH", "42"}, <<"x">>}).

%% --- httph: an UNKNOWN field → Bit 0 + http-capitalised Field ----------------
c_httph_unknown(_) ->
    (dp(httph, <<"X-Foo: bar\r\nx">>, [])
        =:= {ok, {http_header, 0, "X-Foo", "X-Foo", "bar"}, <<"x">>})
        andalso (dp(httph, <<"x-foo: bar\r\nx">>, [])
            =:= {ok, {http_header, 0, "X-Foo", "x-foo", "bar"}, <<"x">>}).

%% --- httph: the empty line → http_eoh (no lookahead needed) ------------------
c_httph_eoh(_) ->
    (dp(httph, <<"\r\n">>, []) =:= {ok, http_eoh, <<>>})
        andalso (dp(httph, <<"\r\nrest">>, []) =:= {ok, http_eoh, <<"rest">>}).

%% --- httph: a header with no trailing byte → {more, undefined} ---------------
c_httph_more(_) ->
    (dp(httph, <<"Host: x\r\n">>, []) =:= {more, undefined})
        andalso (dp(httph, <<"partial">>, []) =:= {more, undefined}).

%% --- httph_bin: binary bodies (Bit + canonical atom identical to httph) ------
c_httph_bin(_) ->
    (dp(httph_bin, <<"Content-Length: 42\r\nx">>, [])
        =:= {ok, {http_header, 38, 'Content-Length', <<"Content-Length">>, <<"42">>}, <<"x">>})
        andalso (dp(httph_bin, <<"X-Foo: y\r\nx">>, [])
            =:= {ok, {http_header, 0, <<"X-Foo">>, <<"X-Foo">>, <<"y">>}, <<"x">>}).

%% --- httph: value has LEADING ws stripped, TRAILING kept; no-space works -----
c_httph_value(_) ->
    (dp(httph, <<"Content-Length:42\r\nx">>, [])
        =:= {ok, {http_header, 38, 'Content-Length', "Content-Length", "42"}, <<"x">>})
        andalso (dp(httph, <<"Content-Length:   42  \r\nx">>, [])
            =:= {ok, {http_header, 38, 'Content-Length', "Content-Length", "42  "}, <<"x">>}).

%% --- ssl_tls: a TLS record → {ssl_tls, [], ContentType, {Maj,Min}, Data} -----
c_ssl_tls(_) ->
    (dp(ssl_tls, <<22, 3, 1, 0, 2, 1, 2>>, [])
        =:= {ok, {ssl_tls, [], 22, {3, 1}, <<1, 2>>}, <<>>})
        andalso (dp(ssl_tls, <<23, 3, 3, 0, 3, 9, 9, 9, 7>>, [])
            =:= {ok, {ssl_tls, [], 23, {3, 3}, <<9, 9, 9>>}, <<7>>}).

%% --- ssl_tls framing: short header/data → {more, undefined|Total} ------------
c_ssl_tls_more(_) ->
    (dp(ssl_tls, <<22, 3, 1>>, []) =:= {more, undefined})
        andalso (dp(ssl_tls, <<22, 3, 1, 0, 5, 1, 2>>, []) =:= {more, 10}).
