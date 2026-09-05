%% beam_metrics_ffi — BEAM VM runtime metrics for F17 scheduler utilisation monitoring.
%% SC-GLM-UI-001, SC-MUDA-001
%%
%% Returns a beam_metrics record matching the Gleam BeamMetrics custom type.
%% All memory values are divided by 1_048_576 (1 MiB) to yield integer MB figures.
%% I/O counters are cumulative since VM start (monotonically increasing).
%%
%% erlang:statistics(io) returns {{input, N}, {output, N}} — we extract the inner
%% integers directly rather than pattern-matching the outer pair.
-module(beam_metrics_ffi).
-export([snapshot/0]).

snapshot() ->
    Mem = erlang:memory(),
    {WallClock, _} = erlang:statistics(wall_clock),
    {input,  InputBytes}  = element(1, erlang:statistics(io)),
    {output, OutputBytes} = element(2, erlang:statistics(io)),
    {beam_metrics,
     erlang:system_info(schedulers_online),
     erlang:system_info(process_count),
     proplists:get_value(total,     Mem) div 1048576,
     proplists:get_value(processes, Mem) div 1048576,
     proplists:get_value(ets,       Mem) div 1048576,
     proplists:get_value(binary,    Mem) div 1048576,
     erlang:statistics(run_queue),
     WallClock div 1000,
     InputBytes  div 1048576,
     OutputBytes div 1048576,
     erlang:system_info(atom_count),
     erlang:system_info(port_count)
    }.
