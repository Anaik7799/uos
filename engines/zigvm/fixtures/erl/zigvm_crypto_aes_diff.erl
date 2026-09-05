%% zigvm_crypto_aes_diff — AES-CBC + AES-GCM differential (gap-crypto-aes-gcm-cbc,
%% DIVERGENCE 591). The OTP crypto NIF cannot load in-sandbox (no libcrypto), so
%% the oracle is the PUBLISHED standard vectors (NIST SP800-38A F.2.1 for CBC,
%% TRIPLE-cross-checked vs openssl 3.x; the NIST-tested std.crypto GCM vector).
%% Vectors are built from <=128-bit chunks (zigvm bit-syntax mis-encodes >128-bit
%% segments). All booleans must be `true`; badtag must be the atom `error`.
%% Run: zigvm run f.beam g   (OTP `erl` cannot run this — the crypto NIF fails).
-module(zigvm_crypto_aes_diff).
-export([g/0]).
g() ->
    %% AES-128-CBC, NIST SP800-38A F.2.1 blocks 1+2 (openssl-verified)
    Kc  = <<16#2b7e151628aed2a6abf7158809cf4f3c:128>>,
    IVc = <<16#000102030405060708090a0b0c0d0e0f:128>>,
    Pc  = <<16#6bc1bee22e409f96e93d7e117393172a:128, 16#ae2d8a571e03ac9c9eb76fac45af8e51:128>>,
    ECc = <<16#7649abac8119b246cee98e9b12e9197d:128, 16#5086cb9b507219ee95db113a917678b2:128>>,
    Cc = crypto:crypto_one_time(aes_128_cbc, Kc, IVc, Pc, true),
    erlang:display({cbc_ct_nist, Cc =:= ECc}),
    erlang:display({cbc_roundtrip, crypto:crypto_one_time(aes_128_cbc, Kc, IVc, Cc, false) =:= Pc}),
    %% AES-256-GCM, the NIST-tested std.crypto vector
    Kg  = <<16#6969696969696969:64,16#6969696969696969:64,16#6969696969696969:64,16#6969696969696969:64>>,
    IVg = <<16#424242424242424242424242:96>>,
    Mg  = <<"Test with message only">>,
    ECg = <<16#5ca1642d90009fea33d01f78cf6eefaf:128, 16#01d539472f7c:48>>,
    ETg = <<16#07cd7fc9103e2f9e9bf2dfaa319caff4:128>>,
    {Cg, Tg} = crypto:crypto_one_time_aead(aes_256_gcm, Kg, IVg, Mg, <<>>, true),
    erlang:display({gcm_ct_std, Cg =:= ECg}),
    erlang:display({gcm_tag_std, Tg =:= ETg}),
    erlang:display({gcm_roundtrip, crypto:crypto_one_time_aead(aes_256_gcm, Kg, IVg, Cg, <<>>, Tg, false) =:= Mg}),
    erlang:display({gcm_badtag, crypto:crypto_one_time_aead(aes_256_gcm, Kg, IVg, Cg, <<>>, <<0:128>>, false)}),
    halt(0).
