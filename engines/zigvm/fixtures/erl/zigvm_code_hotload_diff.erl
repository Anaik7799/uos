%% zigvm_code_hotload_diff — gap-hot-load-code-lib (DIVERGENCE 600).
%% The RUNTIME-CAPABILITY-EQUIVALENCE differential for the code: hot-load LIBRARY
%% surface reachable from a COMPILED beam: code:purge/1, code:soft_purge/1,
%% code:delete/1, code:modified_modules/0 — previously handler-proven but undef via
%% compiled dispatch (FM-DISPATCH-DEAD). Byte-IDENTICAL on zigvm and pinned OTP-30
%% for the host-independent cases (a fresh module with no old code + a closed world).
-module(zigvm_code_hotload_diff).
-export([t/1]).
t(1) -> erlang:display({soft_purge, code:soft_purge(lists)});        % no old code -> true
t(2) -> erlang:display({purge,      code:purge(lists)});             % no proc killed -> false
t(3) -> erlang:display({delete,     code:delete(no_such_module_xyz)}); % absent -> false
t(4) -> erlang:display({modified,   code:modified_modules()});       % closed world -> []
t(5) -> erlang:display({check_old,  erlang:check_old_code(lists)}).  % no old -> false (already EQ)
