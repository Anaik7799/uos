%% zigvm_fileinfo_diff — the file:read_file_info/1 #file_info DIFFERENTIAL fixture
%% (gap-file-info-stat-tz, DIVERGENCE 588). The full 14-field #file_info record —
%% size/type/access + LOCAL-datetime tuples {{Y,Mo,D},{H,Mi,S}} (via the host TZif
%% offset) + mode/major_device/minor_device/inode/uid/gid (via a raw statx) — is
%% byte-identical on pinned OTP-30 and zigvm.
%%
%% DETERMINISTIC REPRODUCIBLE RUN — the file must be FROZEN (a fixed mtime) and
%% READ by BOTH runtimes (do NOT let each run re-write it, or the mtime differs):
%%   printf 'frozen' > /tmp/zigvm_fileinfo_frozen.dat
%%   touch -d '2026-07-20 08:15:30' /tmp/zigvm_fileinfo_frozen.dat
%%   erlc -o D f.erl
%%   erl  -noshell -pa D -run zigvm_fileinfo_diff g        # oracle
%%   zig-out/bin/zigvm run f.beam g                        # zigvm
%%   diff (strip \r). ctime = the touch time; atime/mtime = the frozen mtime.
-module(zigvm_fileinfo_diff).
-export([g/0]).

g() ->
    {ok, FI} = file:read_file_info("/tmp/zigvm_fileinfo_frozen.dat"),
    erlang:display(FI),
    halt(0).
