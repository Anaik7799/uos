%% eco_registry — a reduced ecosystem app exercising the PROCESS REGISTRY
%% surface zigvm genuinely hosts today (gap-erlang-cover-registry, DIVERGENCE 658).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): an Erlang FIXTURE, not harness
%% logic. Self-contained single module run as `zigvm run eco_registry.beam suite`.
%% Exercises the implemented name-registry BIF envelope (src/bifs/bif_table.zig:
%% erlang:register/2, registered/0, unregister/1, whereis/1) — the local name
%% service every OTP app hits (gproc/gen_server-{local,Name}/registered singletons).
%%
%% HONESTY BOUNDS (kept STRICTLY inside the observationally-EQ envelope, so the
%% EQ is real, never a masked repr-coupled gap):
%%  (1) whereis/1 returns a PID whose NUMBER is repr-coupled (the boot-set pid
%%      numbering, see processes/0's deferred-bootset-pidvalues row) — so this
%%      fixture NEVER prints or value-compares a pid; it only compares pids by
%%      IDENTITY (=:= self(), =:= a spawned pid it holds, =:= undefined), which
%%      is observationally total (two terms for the same process compare equal
%%      on both VMs regardless of the printed number).
%%  (2) registered/0 returns an UNORDERED atom set that INCLUDES the boot-tree
%%      system names (init, code_server, application_controller, ...) whose
%%      membership differs from the oracle's node — so this fixture NEVER
%%      compares the whole list; it only asks `lists:member(Name, registered())`
%%      for names IT owns (present/absent), which is deterministic on both VMs.
%%  (3) a dead process's name auto-clears ASYNCHRONOUSLY (racing the exit) — so
%%      this fixture unregisters every name EXPLICITLY while the owner is alive,
%%      keeping every observation deterministic (no exit-teardown ordering dep).
-module(eco_registry).
-export([suite/0]).

%% A registered request/response worker: RECEIVES a ping by registered name,
%% replies to the sender; `stop` returns (the parent unregisters it first).
reg_worker() ->
    receive
        {From, ping} -> From ! {self(), pong}, reg_worker();
        stop         -> ok
    end.

suite() ->
    Self = self(),

    %% An unregistered name resolves to `undefined` and is absent from the set.
    C1 = (whereis(eco_reg_self) =:= undefined),
    C2 = (lists:member(eco_reg_self, registered()) =:= false),

    %% Register self: whereis resolves to self (IDENTITY), member true.
    true = register(eco_reg_self, Self),
    C3 = (whereis(eco_reg_self) =:= Self),
    C4 = (lists:member(eco_reg_self, registered()) =:= true),

    %% Register a worker; SEND to it BY REGISTERED NAME; it replies.
    W = spawn(fun() -> reg_worker() end),
    true = register(eco_reg_worker, W),
    C5 = (whereis(eco_reg_worker) =:= W),
    eco_reg_worker ! {Self, ping},                 %% send by registered name
    C6 = receive {W, pong} -> true after 1000 -> false end,

    %% Duplicate-NAME register (eco_reg_worker already taken) -> badarg.
    C7 = case catch register(eco_reg_worker, Self) of
             {'EXIT', {badarg, _}} -> true; _ -> false
         end,
    %% Register an ALREADY-registered pid (W) under a 2nd name -> badarg.
    C8 = case catch register(eco_reg_alias, W) of
             {'EXIT', {badarg, _}} -> true; _ -> false
         end,
    %% Unregister an UNKNOWN name -> badarg.
    C9 = case catch unregister(eco_no_such_reg) of
             {'EXIT', {badarg, _}} -> true; _ -> false
         end,

    %% Unregister self: whereis -> undefined, member false; then NAME REUSE.
    true = unregister(eco_reg_self),
    C10 = (whereis(eco_reg_self) =:= undefined),
    C11 = (lists:member(eco_reg_self, registered()) =:= false),
    true = register(eco_reg_self, Self),           %% re-register a freed name
    C12 = (whereis(eco_reg_self) =:= Self),

    %% Explicit deterministic cleanup (no exit-teardown race): unregister the
    %% worker while alive, confirm the name is freed, then stop it.
    true = unregister(eco_reg_worker),
    C13 = (whereis(eco_reg_worker) =:= undefined),
    W ! stop,
    true = unregister(eco_reg_self),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
    of
        true -> ok;
        false -> fail
    end.
