%% Test fixture values, never a production risk source.
-module(telegram_fmea_test_io).
-export([fixture/2]).
fixture(_,<<"malformed">>) -> <<"[{">>;
fixture(Plan,Variant) ->
  Now=erlang:system_time(second),
  {Observed,Until}=case Variant of <<"stale">>->{Now-7200,Now-3600};_->{Now-10,Now+3600} end,
  Stamp=fun(T)->list_to_binary(calendar:system_time_to_rfc3339(T,[{offset,"Z"},{unit,second}])) end,
  {S,O}=case Variant of <<"changed">>->{5,4};_->{4,3} end,
  Mode=#{id=><<"FM-FIXTURE">>,cause=><<"Recorded fixture cause">>,effect=><<"Recorded fixture effect">>,
    controls=><<"Recorded fixture controls">>,s=>S,o=>O,det=>3,rpn=>S*O*3,'band'=>4},
  iolist_to_binary(json:encode([#{assessment_id=><<"fixture-assessment">>,plan_id=>Plan,
    task_id=><<"lease-e2e-01">>,observed_at=>Stamp(Observed),valid_until=>Stamp(Until),
    task_state=><<"executing">>,fmea_modes=>[Mode]}])).
