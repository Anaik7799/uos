-module(zigvm_phash2_nil_diff).
-export([t/1]).
%% phash2 of [] — /1 (masked to 2^27) + /2 with 2^32 (the raw make_hash2 u32).
%% Both VMs must byte-EQ {113427502, 3468870702}.
t(_) -> {erlang:phash2([]), erlang:phash2([], 4294967296)}.
