%%% telegram_real_traffic_probe_ffi — typed view of a vault read for the probe.
%%% `uos_vault_file:get/3` answers {ok, Bin} | {error, Reason}; the probe only
%%% ever sees the binary or a printable reason, never a crash on an unexpected
%%% shape.
-module(telegram_real_traffic_probe_ffi).
-export([ok_binary/1]).

ok_binary({ok, Bin}) when is_binary(Bin) -> {ok, Bin};
ok_binary({error, Reason}) -> {error, iolist_to_binary(io_lib:format("~p", [Reason]))};
ok_binary(Other) -> {error, iolist_to_binary(io_lib:format("unexpected:~p", [Other]))}.
