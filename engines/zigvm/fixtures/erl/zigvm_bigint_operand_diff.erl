%% zigvm_bigint_operand_diff — inline >i128 integer OPERAND differential
%% (gap-bigint-operand, DIVERGENCE 593). erlc emits a positive top-bit-set int
%% (e.g. 2^128-1, 17 bytes: 16 magnitude + a leading 0x00) as an INLINE bs_match
%% operand; the loader's 16-byte cap made these a hard BadOperand (whole-module
%% load failure). Now they load + run byte-EQ vs OTP. Run: erl -run ... g / zigvm run.
-module(zigvm_bigint_operand_diff).
-export([g/0]).
m(Tag, Bin, N, Lit) ->
    R = case Bin of <<Lit:N>> -> matched; _ -> nomatch end,
    erlang:display({Tag, R}).
g() ->
    %% 2^128-1 as an INLINE bs_match operand (the exact BadOperand trigger)
    m(u128max, <<255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255>>, 128,
      16#ffffffffffffffffffffffffffffffff),
    m(u128max_nomatch, <<0,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255>>, 128,
      16#ffffffffffffffffffffffffffffffff),
    %% a negative big int (via arithmetic, exercises the negative operand path)
    X = -(16#ffffffffffffffffffffffffffffffff),
    erlang:display({neg_big, X < 0, X band 255, (-X) band 255}),
    %% a wider (256-bit) inline operand
    m(w256, <<16#0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20:256>>, 256,
      16#0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20),
    halt(0).
