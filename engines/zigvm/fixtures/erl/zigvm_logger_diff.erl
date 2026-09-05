%% zigvm_logger_diff — compiled differential for the logger null-sink surface
%% (DIVERGENCE 742). A DIRECT `logger:LEVEL(...)` / `logger:log(...)` call in app
%% code (a proc_lib crash report, a gen_server `terminate`) used to `undef`-KILL
%% the caller on zigvm — the highest-severity FM-DISPATCH-DEAD instance for the
%% logging spine. zigvm now wires them (like the error_logger null sink, 650, and
%% `logger:allow → false`, e47-a1) to RETURN `ok` — the public API's exact return.
%%
%% VALUE differential (the RETURNS, not the emitted output): every call returns
%% `ok`. The EMIT (`=ERROR REPORT==== <ts> ===\n<msg>` to stdout, async,
%% level-filtered at `notice`) is the DISCLOSED "no logger tree" bound — EQUIV,
%% not compared here; grep the `logger_diff` verdict line only.
%%
%% Run on BOTH VMs (needs stdlib+kernel for the logger module):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_logger_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_logger_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run --code-path <stdlib> --code-path <kernel> OUT/zigvm_logger_diff.beam t 0
%% Byte-EQ verdict (both, on the `logger_diff` line): {logger_diff,8,all_ok,true}
-module(zigvm_logger_diff).
-export([t/1]).
t(_) ->
    Rs = [logger:error("e ~p", [1]),
          logger:warning("w"),
          logger:info("i ~p ~p", [2, 3]),
          logger:notice("n"),
          logger:debug("d"),
          logger:critical("c ~p", [4]),
          logger:log(error, "l ~p", [5]),
          logger:log(info, "m")],
    AllOk = lists:all(fun(R) -> R =:= ok end, Rs),
    erlang:display({logger_diff, length(Rs), all_ok, AllOk}).
