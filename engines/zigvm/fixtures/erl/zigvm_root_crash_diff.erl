%% zigvm_root_crash_diff — compiled differential for the root-crash EXIT CODE
%% (DIVERGENCE 743). A crashed ROOT process must be an ERROR exit (non-zero), not
%% silent success: `exit 0` on a crash is an EVIDENCE-INTEGRITY hazard — a failing
%% run reads as passing to any `$?`-checking harness. zigvm used to exit 0 on a
%% crashed root; erts exits 1 + prints `Runtime terminating during boot (<reason>)`
%% on STDERR.
%%
%% VALUE differential = the EXIT CODE (byte-EQ 1 on a crash, 0 on a normal run) +
%% the stderr banner SHAPE. The banner's boot-frame stacktrace + the file string
%% are EQUIV (zigvm's `run` path has no init:do_boot frames; the crash-reason
%% printer's list→string heuristic is a separate diag residual) — the EXIT CODE is
%% the byte-EQ contract this fixture pins.
%%
%% Run on BOTH VMs and compare `$?`:
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_root_crash_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -run zigvm_root_crash_diff boom 0 -s init stop; echo $?   %% => 1
%%   third_party/otp/bin/erl -noshell -pa OUT -run zigvm_root_crash_diff ok   0 -s init stop; echo $?   %% => 0
%%   zig-out/bin/zigvm run OUT/zigvm_root_crash_diff.beam boom 0; echo $?   %% => 1
%%   zig-out/bin/zigvm run OUT/zigvm_root_crash_diff.beam ok   0; echo $?   %% => 0
-module(zigvm_root_crash_diff).
-export([boom/1, ok/1]).

boom(_) -> erlang:error(boom).           %% uncaught error → crashed root → exit 1
ok(_) -> erlang:display({root, ok}).     %% normal termination → exit 0
