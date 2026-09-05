%% eco_ttb — a reduced ecosystem app exercising the TERM ↔ EXTERNAL-TERM-FORMAT
%% (ETF) surface zigvm genuinely hosts today (gap-erlang-cover-ttb, DIVERGENCE 660).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): an Erlang FIXTURE, not harness
%% logic. Self-contained single module run as `zigvm run eco_ttb.beam suite`.
%% Exercises the implemented serialization BIF envelope (src/etf.zig via
%% src/bifs/bif_table.zig: term_to_binary/1,2, binary_to_term/1,2) — the wire
%% codec every OTP app hits (mnesia/dets on-disk, gen_server state hand-off,
%% dist message bodies, ETS `term_to_binary` blobs, DETS).
%%
%% HONESTY BOUNDS (kept STRICTLY inside the observationally-EQ envelope, so the
%% EQ is real, never a masked repr-coupled gap):
%%  (1) the ENCODED bytes of term_to_binary/1 are a valid-but-implementation-
%%      chosen ETF serialization (atom tag, int-size boundary, map-key order in
%%      the wire, compression heuristics) — so this fixture NEVER value-compares
%%      the raw encoded binary across VMs. It asserts DENOTATION-PRESERVING
%%      properties only: the ROUND-TRIP `binary_to_term(term_to_binary(T)) =:= T`
%%      (each VM's own codec) and the spec-fixed VERSION MAGIC byte 131.
%%  (2) the CROSS-DECODE cases feed a HARD-CODED OTP-produced ETF byte sequence
%%      to binary_to_term on BOTH VMs — testing zigvm's DECODER against the real
%%      OTP-30 wire format (SMALL_ATOM_UTF8_EXT tag 119, MAP_EXT, SMALL_TUPLE_EXT,
%%      SMALL_INTEGER_EXT). Both decode the SAME literal bytes → the same term.
%%  (3) NO pids/refs/ports/funs — their ETF encoding embeds the node atom +
%%      creation + serial (repr/host-coupled); term equality would still hold on
%%      one node but the surface is deliberately excluded to keep the EQ clean.
%%  (4) NO higher-order `lists:` helpers (map/filter/foldl/all/any/foreach) — a
%%      curation probe (DIVERGENCE 660) found those are `undef` on zigvm today
%%      (only the pure/data `lists:` functions are wired; `lists.erl` is not
%%      autoloaded). This fixture uses LIST COMPREHENSIONS instead (zigvm hosts
%%      them natively), so its EQ turns only on the ETF codec under test. The
%%      higher-order-lists gap is a separate, larger slice (fun-reentrant BIFs or
%%      lists.erl autoload), deliberately NOT conflated with this ETF fixture.
-module(eco_ttb).
-export([suite/0]).

suite() ->
    Big = 123456789012345678901234567890,          %% a bignum (LARGE_BIG_EXT)
    Neg = -98765432109876543210,                   %% a negative bignum
    Nested = #{list => [1, {2, 3}, <<"x">>],
               nums => [3.14, -1, Big, Neg],
               t    => {a, {b, {c, []}}},
               str  => "an embedded string"},

    %% (1) ROUND-TRIP over a wide term-shape set (each VM's own codec).
    %%     Asserted via a comprehension that COLLECTS the failures — an empty
    %%     residue means every term round-tripped (no higher-order lists helper).
    Terms = [42, -7, 0, 255, 256, 100000, Big, Neg,
             foo, '', 'a longer atom name', true, false,
             3.14, -0.5, 1.0e10,
             {ok, 1, <<"hi">>}, {}, {single},
             [1, 2, 3], [], "hello", [1 | 2],
             <<1, 2, 3>>, <<>>, <<"a binary string">>,
             #{a => 1, b => 2}, #{}, #{nested => #{deep => [1, 2]}},
             Nested],
    RT = ([X || X <- Terms, binary_to_term(term_to_binary(X)) =/= X] =:= []),

    %% (2) VERSION MAGIC byte 131 (spec-fixed, both VMs) — collect non-magic.
    Magic = ([X || X <- Terms,
                   case term_to_binary(X) of
                       <<131, _/binary>> -> false;
                       _ -> true
                   end] =:= []),

    %% (3) term_to_binary/2 OPTIONS all round-trip (compressed / minor_version /
    %%     safe) — the codec is denotation-preserving under every option.
    O1 = (binary_to_term(term_to_binary(Nested, [compressed])) =:= Nested),
    O2 = (binary_to_term(term_to_binary(Nested, [{compressed, 9}])) =:= Nested),
    O3 = (binary_to_term(term_to_binary(Nested, [{minor_version, 1}])) =:= Nested),
    O4 = (binary_to_term(term_to_binary(Nested, [{minor_version, 2}])) =:= Nested),
    %% [safe] accepts a pure-data term (no NEW atoms/funs to reject).
    O5 = (binary_to_term(term_to_binary({data, 42, <<"bin">>}), [safe]) =:= {data, 42, <<"bin">>}),

    %% (4) CROSS-DECODE hard-coded OTP-30 wire bytes → the exact term.
    X1 = (binary_to_term(<<131, 97, 42>>) =:= 42),                         %% SMALL_INTEGER_EXT
    X2 = (binary_to_term(<<131, 104, 3, 119, 2, 111, 107, 97, 1,
                           109, 0, 0, 0, 2, 104, 105>>) =:= {ok, 1, <<"hi">>}), %% tuple+atom+bin
    X3 = (binary_to_term(<<131, 116, 0, 0, 0, 1, 119, 1, 97, 97, 1>>) =:= #{a => 1}), %% MAP_EXT
    X4 = (binary_to_term(<<131, 106>>) =:= []),                            %% NIL_EXT

    %% (5) ROUND-TRIP STABILITY: re-encoding a decoded term reproduces the same
    %%     term (codec is idempotent on the term denotation) — collect failures.
    Stable = ([X || X <- Terms,
                    binary_to_term(term_to_binary(binary_to_term(term_to_binary(X)))) =/= X] =:= []),

    case RT andalso Magic andalso O1 andalso O2 andalso O3 andalso O4 andalso O5
         andalso X1 andalso X2 andalso X3 andalso X4 andalso Stable
    of
        true -> ok;
        false -> fail
    end.
