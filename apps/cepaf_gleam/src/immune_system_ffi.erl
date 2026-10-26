%%% immune_system_ffi — the fixed registered name of the immune system actor.
%%%
%%% gleam_erlang's `process.new_name/1` mints a unique atom per call, which is
%%% right for a name one module creates and hands around, and wrong for an
%%% actor that other modules must discover without being handed anything.
%%% A `Name(a)` is an atom at runtime; this module returns the one atom that
%%% `cepaf_gleam/immune/system.registry_name/0` names, so `start_named/0`,
%%% `child_spec/0` and `lookup/0` agree on it across restarts and modules.
-module(immune_system_ffi).
-export([registry_name/0]).

registry_name() -> uos_immune_system.
