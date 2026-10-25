%% Deterministic timestamp parsing; policy and freshness are owned by Gleam.
-module(telegram_risk_files).
-export([parse_utc_ms/1]).
parse_utc_ms(<<Y:4/binary,$-,M:2/binary,$-,D:2/binary,$T,H:2/binary,$:,N:2/binary,$:,S:2/binary,$Z>>) ->
  try
    Parts=[Y,M,D,H,N,S],
    true=lists:all(fun(B)->lists:all(fun(C)->C>=$0 andalso C=<$9 end,binary_to_list(B)) end,Parts),
    [YY,MM,DD,HH,NN,SS]=[binary_to_integer(B)||B<-Parts],
    true=YY>=1970 andalso calendar:valid_date({YY,MM,DD}),
    true=HH>=0 andalso HH<24 andalso NN>=0 andalso NN<60 andalso SS>=0 andalso SS<60,
    Epoch=calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
    {ok,(calendar:datetime_to_gregorian_seconds({{YY,MM,DD},{HH,NN,SS}})-Epoch)*1000}
  catch _:_ -> {error,<<"invalid_utc_timestamp">>} end;
parse_utc_ms(_) -> {error,<<"invalid_utc_timestamp">>}.
