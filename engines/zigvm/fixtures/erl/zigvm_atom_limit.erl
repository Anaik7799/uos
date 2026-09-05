%% gap-atom-and-heap-limits (atom observability): system_info(atom_limit) is the
%% erts default max (byte-EQ 1048576); atom_count is the truthful live count.
-module(zigvm_atom_limit).
-export([t/1]).
t(_) ->
    erlang:display({atom_limit, erlang:system_info(atom_limit)}),
    C = erlang:system_info(atom_count),
    erlang:display({atom_count_is_pos_int_below_limit, is_integer(C) andalso C >= 0 andalso C < erlang:system_info(atom_limit)}),
    ok.
