%% Ordinary public-file pin checks only. No credential/provider/ledger/process
%% dispatch is exercised. The read-only API cannot make ready/0 succeed.
-module(pi_review_runtime_pin_test).
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/file.hrl").

inputs() ->
 Root=list_to_binary(os:getenv("UOS_PI_PIN_SOURCE_ROOT")),
 {ok,Runtime}=file:read_file(os:getenv("UOS_PI_PIN_RUNTIME")),
 {Root,Runtime}.

actual_pinned_node_above_old_cap_test() ->
 {ok,#file_info{size=Size,type=regular}}=
  file:read_file_info("/home/an/NAS-setup/uos/toolchains/nix-profile/bin/node"),
 ?assertEqual(73394160,Size),?assert(Size>67108864),?assert(Size=<134217728),
 {Root,Runtime}=inputs(),
 ?assertEqual({ok,nil},pi_review_io:check_runtime_pins(Root,Runtime)).

ordinary_nonmatching_pin_refuses_test() ->
 {Root,Runtime}=inputs(),Pins=json:decode(Runtime),
 Other=iolist_to_binary(json:encode(Pins#{<<"node_sha256">>=>binary:copy(<<"0">>,64)})),
 ?assertEqual({error,<<"review_runtime_pins_unverified">>},
              pi_review_io:check_runtime_pins(Root,Other)).

runtime_pin_metadata_is_closed_test() ->
 {Root,Runtime}=inputs(),Pins=json:decode(Runtime),
 Extra=iolist_to_binary(json:encode(Pins#{<<"executable">>=><<"not selectable">>})),
 ?assertEqual({error,<<"review_runtime_pins_unverified">>},
              pi_review_io:check_runtime_pins(Root,Extra)).

successful_pins_do_not_enable_production_test() ->
 {Root,Runtime}=inputs(),
 ?assertEqual({ok,nil},pi_review_io:check_runtime_pins(Root,Runtime)),
 ?assertEqual({error,<<"review_transport_unavailable_clean_env_post_fence_runtime_closure">>},
              pi_review_io:ready()),
 %% Current invoke refuses at ready(), before any file/secret/provider access.
 ?assertEqual({error,<<"review_runtime_or_cleanup_unavailable">>},
              pi_review_io:invoke(Root,Runtime,<<"PUBLIC ORDINARY DATA">>)).
