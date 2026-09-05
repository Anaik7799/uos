%% eco_concurrency — a reduced ecosystem app exercising the CONCURRENCY
%% substrate that zigvm genuinely hosts today (e21-t3, DIVERGENCE 230/420-amend).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3, DIVERGENCE 199/202): an Erlang
%% FIXTURE, not harness logic. Run as `zigvm run <one .beam> suite` through the
%% E0 CLI surface, whose scheduler (`cli.runMulti` -> `proc.Scheduler.drive`)
%% really executes multiple processes. It asserts the spawn / send / receive /
%% link / monitor / trap_exit PRIMITIVES that every OTP worker-pool style app
%% (poolboy, cowboy's acceptor) sits on — the family proven EQ end-to-end since
%% E4.1 and completed for fun-spawn at e21-t1 (`spawn/1`, `spawn_link/1`).
%%
%% The suite drives a request/response worker (the parent SENDS the request, the
%% worker RECEIVES then replies — the round-trip mailbox pattern), then a
%% monitored short-lived worker (DOWN signal) and a linked worker (trap_exit
%% 'EXIT' signal). This is the reduced shape of poolboy's checkout/checkin loop.
%%
%% HONESTY BOUND (the e21-t3 frontier, DIVERGENCE 490/97): this fixture stays
%% inside the request/response ordering where the PARENT sends first. The
%% UNSOLICITED child->parent message pattern (a plain-spawn child sending a user
%% message to a parent that is blocked in `receive` having sent nothing first)
%% still DIVERGES on zigvm today (observed under e21-t3: timeout / panic) and is
%% the behaviour-closure frontier the four upstream apps need — it is
%% deliberately NOT asserted here so this fixture's EQ is real, never a masked
%% gap. gen_server/supervisor callback loops remain UNTESTED upstream.
-module(eco_concurrency).
-export([suite/0]).

%% A request/response worker: RECEIVES a request, then replies to the sender.
%% Mirrors poolboy's checkout server (the parent always sends first).
worker(Parent) ->
    receive
        {From, {add, A, B}} -> From ! {self(), A + B}, worker(Parent);
        {From, ping}        -> From ! {self(), pong}, worker(Parent);
        stop                -> Parent ! stopped
    end.

suite() ->
    Self = self(),
    %% spawn/1 of a closure capturing Self (e21-t1 fun-spawn closure).
    W = spawn(fun() -> worker(Self) end),

    %% Round-trip 1: parent sends {add,...}, worker replies.
    W ! {Self, {add, 20, 21}},
    R1 = receive {W, V1} -> V1 after 1000 -> timeout end,
    C1 = (R1 =:= 41),

    %% Round-trip 2: a second request on the SAME worker (mailbox ordering).
    W ! {Self, ping},
    R2 = receive {W, V2} -> V2 after 1000 -> timeout end,
    C2 = (R2 =:= pong),

    %% spawn_monitor: DOWN signal delivery on normal exit.
    {P2, Ref} = spawn_monitor(fun() -> ok end),
    C3 = receive {'DOWN', Ref, process, P2, normal} -> true after 1000 -> false end,

    %% spawn_link + trap_exit: EXIT signal delivery on abnormal exit.
    process_flag(trap_exit, true),
    P3 = spawn_link(fun() -> exit(boom) end),
    C4 = receive {'EXIT', P3, boom} -> true after 1000 -> false end,

    %% Graceful stop of the worker (parent sends, worker replies to Parent).
    W ! stop,
    C5 = receive stopped -> true after 1000 -> false end,

    case C1 andalso C2 andalso C3 andalso C4 andalso C5 of
        true -> ok;
        false -> fail
    end.
