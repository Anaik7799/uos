%% zigvm_io_format_unicode_diff — the ~ts/~tc UNICODE differential fixture
%% (gap-io-format-unicode, DIVERGENCE 626). Renders ~ts/~tc of codepoint lists
%% and chars; the UTF-8 byte output is byte-identical on pinned OTP-30 and on
%% zigvm's native io_lib:format interpreter. Manual sequential calls (no lists:*)
%% so it runs on zigvm with NO --code-path. Run:
%%   erlc -o D f.erl; erl -noshell -pa D -run zigvm_io_format_unicode_diff main
%%   zig-out/bin/zigvm run f.beam main
%% and diff (strip trailing run-harness line + CR; drop the OTP-absent last line).
-module(zigvm_io_format_unicode_diff).
-export([main/0]).

main() ->
    io:format("~ts~n", [[955]]),                 % λ  = CE BB
    io:format("~ts~n", [[104,105]]),             % hi
    io:format("~ts~n", [[104,955,105]]),         % hλi
    io:format("~tc~n", [955]),                   % λ
    io:format("~2tc~n", [955]),                  % λλ
    io:format("~ts~n", [[0,955,956,957]]),       % NUL λ μ ν
    io:format("~ts~n", [[128512]]),              % 😀 = F0 9F 98 80
    ok.
