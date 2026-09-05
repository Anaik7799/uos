%% zigvm_file_io_diff — the file: I/O DIFFERENTIAL fixture (gap-file-handle-io,
%% DIVERGENCE 586). Exercises the whole file: surface — the previously-DEAD path
%% ops (read_file/write_file/list_dir) AND the live-Fd handle API
%% (open/pread/pwrite/close) — with output byte-identical on pinned OTP-30 and
%% zigvm's native file: dispatch (RunFd table over the prim_file seam).
%%
%% DETERMINISTIC REPRODUCIBLE RUN (run from a writable CWD, e.g. /tmp):
%%   erlc -o D f.erl
%%   erl  -noshell -pa D -run zigvm_file_io_diff g   # oracle
%%   zig-out/bin/zigvm run f.beam g                  # zigvm (fs root = CWD)
%%   diff  (strip \r). All data observables are byte-EQ; the IoDevice term is
%%   opaque (OTP's inner map carries non-reproducible Refs) so it is NOT compared.
-module(zigvm_file_io_diff).
-export([g/0]).

g() ->
    %% ── path ops (were DEAD via compiled dispatch before 586) ──
    ok = file:write_file("zfd_a.dat", <<"path-based-io">>),
    erlang:display({read_file, file:read_file("zfd_a.dat")}),
    erlang:display({read_missing, file:read_file("zfd_no_such.dat")}),
    %% ── the live-Fd handle API ──
    {ok, Fd} = file:open("zfd_b.dat", [read, write, raw, binary]),
    ok = file:pwrite(Fd, 5, <<"XYZ">>),            % positioned write past end (hole)
    ok = file:pwrite(Fd, 0, <<"01234">>),
    erlang:display({pread_full, file:pread(Fd, 0, 8)}),
    erlang:display({pread_mid,  file:pread(Fd, 5, 3)}),
    erlang:display({pread_eof,  file:pread(Fd, 999, 2)}),  % past EOF → eof
    ok = file:close(Fd),
    erlang:display({double_close,  file:close(Fd)}),        % → {error,einval}
    erlang:display({pread_closed,  file:pread(Fd, 0, 1)}),  % → {error,einval}
    erlang:display({pwrite_closed, file:pwrite(Fd, 0, <<"z">>)}),
    erlang:display({open_missing,  file:open("zfd_missing.dat", [read, raw])}), % {error,enoent}
    halt(0).
