(* Closed EV98 component recipe. Any recipe/tool/acceptance update requires review. *)
let id = "uos.ev98.component-campaign.v2"
let canonical_root = "/home/an/NAS-setup/uos"
let baseline = "9c590e75b87e2bca63adb4af966e465269203b4d"
let previous_baseline = "f5f86e7e9841ae20da69f3d6c7fc44f1a2e50396"
let previous_recipe_sha256 = "412ab8bc2e203603f8fe8a5f57b8bf1359b59c82dce5fd37b523a64502cea6d8"
let update_notes = ["Version 2 explicitly stages the reviewed wire codec and all 25 codec cases; version 1's 42 case IDs remain obligations"; "Any baseline acceptance byte correction must appear in acceptance_updates with old/new digest and requirement rationale"]
let sources = [
 "apps/cepaf_gleam/src/cepaf_gleam/crdt/delta_state.gleam";
 "apps/cepaf_gleam/src/cepaf_gleam/crdt/health_bridge.gleam";
 "apps/cepaf_gleam/src/cepaf_gleam/crdt/mesh_sync.gleam";
 "apps/cepaf_gleam/src/cepaf_gleam/crdt/mesh_wire.gleam";
 "apps/cepaf_gleam/src/cepaf_gleam/crdt/delta_mesh_engine.gleam";
 "apps/cepaf_gleam/src/cepaf_gleam/ha/deadman_freshness.gleam";
]
let baseline_fixed = [
 "apps/cepaf_gleam/test/delta_mesh_engine_test.gleam","1e48182f8a94c44a3a9885f58adde2de8628d9a130ab9420c077f4653028d13b";
 "apps/cepaf_gleam/test/deadman_freshness_test.gleam","e6ea49acee8d58d076087f2ebd6dcbdc738ba0883ee76f21b475ef2b1df3e138";
 "apps/cepaf_gleam/test/crdt_health_bridge_test.gleam","c9f10351c62d927277943ca9ec1a7c2f2fd3491f80d22ea1d892a0713eb5852d";
 "apps/cepaf_gleam/test/crdt_mesh_sync_test.gleam","28b7fab329415f3cb48bd022f497bfdeb7a312e6ae19bb206ac35aeb961b8b83";
 "apps/cepaf_gleam/test/ev_delta_freshness_runner.gleam","bdb4753d8a90403747cdb87258fa160d6df6ce49882f36892b3a6969f3ed0e0b";
 "contracts/rules/20260908-0912-provenance-integrity-contract.md","f764207e524b5c493252be58fc1a7e426dd92239f8d92bc43ae2e74fc50f8d57";
]
let acceptance_updates : (string * string * string * string) list = []
let codec_fixed = [
 "apps/cepaf_gleam/test/mesh_sync_codec_test.gleam","140eddbe3e47c4e1b3e24daca0416dd681bdc9413e23b298caa0be56b0af16f0";
]
let fixed = List.map (fun (path, original) -> path,
 match List.find_opt (fun (p,_,_,_) -> p=path) acceptance_updates with
 | None -> original
 | Some (_,expected,updated,_) -> if expected<>original then failwith "acceptance baseline mismatch"; updated) baseline_fixed @ codec_fixed
let baseline_cases = [
 "delta_mesh_engine_test.engine_init_test";
 "delta_mesh_engine_test.engine_register_peer_test";
 "delta_mesh_engine_test.engine_local_mutation_and_gossip_test";
 "delta_mesh_engine_test.engine_two_node_reconciliation_test";
 "delta_mesh_engine_test.engine_health_aggregation_test";
 "delta_mesh_engine_test.health_observation_advances_causal_clock_test";
 "delta_mesh_engine_test.worker_observation_epoch_cannot_regress_test";
 "delta_mesh_engine_test.stale_health_does_not_advance_clock_test";
 "delta_mesh_engine_test.gossip_queue_is_bounded_test";
 "deadman_freshness_test.deadman_init_test";
 "deadman_freshness_test.deadman_registration_nominal_test";
 "deadman_freshness_test.deadman_warning_escalation_test";
 "deadman_freshness_test.deadman_trip_and_failover_test";
 "deadman_freshness_test.repeated_trip_emits_no_duplicate_actions_test";
 "deadman_freshness_test.backward_tick_cannot_clear_a_trip_test";
 "deadman_freshness_test.stale_heartbeat_cannot_recover_a_trip_test";
 "deadman_freshness_test.fresh_recovery_rearms_one_new_trip_test";
 "deadman_freshness_test.exact_single_interval_trips_test";
 "delta_mesh_engine_test.full_queue_rejects_without_advancing_round_and_can_drain_test";
 "delta_mesh_engine_test.outbound_drain_retains_fifo_and_is_empty_on_repeat_test";
 "delta_mesh_engine_test.full_queue_defers_delta_application_until_retry_test";
 "delta_mesh_engine_test.full_queue_can_receive_ack_and_peer_time_does_not_regress_test";
 "delta_mesh_engine_test.health_only_change_generates_delta_against_previous_clock_test";
 "delta_mesh_engine_test.full_queue_rejects_both_digest_response_branches_test";
 "delta_mesh_engine_test.gossip_timestamp_cannot_precede_latest_observation_test";
 "delta_mesh_engine_test.repeated_health_sample_is_idempotent_test";
 "deadman_freshness_test.repeated_warning_and_duplicate_tick_are_quiet_test";
 "deadman_freshness_test.invalid_intervals_are_quarantined_and_not_heartbeat_recovered_test";
 "deadman_freshness_test.stale_reregistration_cannot_clear_a_trip_test";
 "deadman_freshness_test.actor_order_is_stable_across_ticks_test";
 "deadman_freshness_test.explicit_valid_configuration_can_recover_quarantine_test";
 "deadman_freshness_test.heartbeat_at_trip_observation_time_does_not_rearm_test";
 "delta_mesh_engine_test.reversed_same_tick_health_deltas_preserve_latest_sample_test";
 "delta_mesh_engine_test.concurrent_same_target_health_converges_in_both_orders_test";
 "delta_mesh_engine_test.local_health_after_merge_supersedes_same_tick_remote_sample_test";
 "delta_mesh_engine_test.successive_gossip_retains_accepted_epoch_test";
 "delta_mesh_engine_test.incoming_ack_and_digest_observations_advance_outgoing_epoch_test";
 "delta_mesh_engine_test.newer_sample_time_wins_over_an_older_logical_counter_test";
 "crdt_health_bridge_test.record_and_merge_health_test";
 "crdt_health_bridge_test.health_telemetry_lww_convergence_test";
 "crdt_mesh_sync_test.mesh_sync_digest_and_drift_test";
 "crdt_mesh_sync_test.mesh_sync_reconciliation_and_ack_test";
]
let codec_cases = [
 "mesh_sync_codec_test.diagnostic_delta_retains_payload_test";
 "mesh_sync_codec_test.all_fields_and_forwarding_origin_roundtrip_test";
 "mesh_sync_codec_test.digest_and_ack_roundtrip_test";
 "mesh_sync_codec_test.empty_delta_and_zero_boundaries_roundtrip_test";
 "mesh_sync_codec_test.independent_exact_wire_layout_test";
 "mesh_sync_codec_test.wire_reconciliation_matches_typed_oracle_test";
 "mesh_sync_codec_test.malformed_wire_refuses_before_reconciliation_test";
 "mesh_sync_codec_test.exact_byte_decode_boundary_test";
 "mesh_sync_codec_test.exact_byte_encode_boundary_test";
 "mesh_sync_codec_test.depth_checked_before_recursive_parse_test";
 "mesh_sync_codec_test.collection_boundary_and_order_test";
 "mesh_sync_codec_test.utf8_string_byte_boundaries_test";
 "mesh_sync_codec_test.safe_integer_and_negative_boundaries_test";
 "mesh_sync_codec_test.closed_grammar_rejects_ambiguous_and_malformed_inputs_test";
 "mesh_sync_codec_test.duplicate_clock_and_counter_keys_refused_test";
 "mesh_sync_codec_test.duplicate_health_keys_and_mismatched_nodes_refused_test";
 "mesh_sync_codec_test.duplicate_live_tombstone_and_cross_set_dots_refused_test";
 "mesh_sync_codec_test.empty_node_identities_refused_test";
 "mesh_sync_codec_test.physical_and_logical_health_times_survive_independently_test";
 "mesh_sync_codec_test.nonfinite_numeric_literals_are_refused_test";
 "mesh_sync_codec_test.exact_float_extremes_and_escaped_strings_roundtrip_test";
 "mesh_sync_codec_test.every_composite_collection_has_an_encoder_bound_test";
 "mesh_sync_codec_test.malformed_nested_wire_records_refused_test";
 "mesh_sync_codec_test.aggregate_budget_stops_before_invalid_shared_tail_test";
 "mesh_sync_codec_test.deeply_shared_tree_and_escaping_have_aggregate_bounds_test";
]
let sync_cases : string list = []
let cases = baseline_cases @ codec_cases @ sync_cases
let dependencies = ["gleam_stdlib";"gleam_json";"gleeunit"]
let dependency_root = "/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang"
let dependency_files = [
 "gleam_stdlib/_gleam_artefacts/dict.mjs","c4749ecc54d0fc5fbb58989c10bb3d41242d430afbe34a1e343023ba7bd6988d";
 "gleam_stdlib/_gleam_artefacts/gleam@bit_array.cache","6d6a596f334ce650b08051aebff22bbd4013440d4729201f137994f93eee9933";
 "gleam_stdlib/_gleam_artefacts/gleam@bit_array.cache_meta","ff63b4375a0c5db892da31bb2a4815351a21193a57c51dbdcd2264151fd9d71f";
 "gleam_stdlib/_gleam_artefacts/gleam@bit_array.erl","3c6813a23d1a369ca267c80bce5dc5f4f0708f64b1e3f1538ada20a31880d7a4";
 "gleam_stdlib/_gleam_artefacts/gleam@bool.cache","cf681d8633eb1f82d57decb069951fc8c14043c7e7e6b4eecae6a57e2637c45a";
 "gleam_stdlib/_gleam_artefacts/gleam@bool.cache_meta","69567e6fa3ef4c3e0a4e75c6f8e2578f616d65ce31e0ee9ae1817efae9f9b770";
 "gleam_stdlib/_gleam_artefacts/gleam@bool.erl","c7c83dc93288196c058ab902060ebc263959819b5bf07bebbccdc8d07871843e";
 "gleam_stdlib/_gleam_artefacts/gleam@bytes_tree.cache","7092e91e1c65ac5412628d8754048883fcca19a4cc21ebcb5378f0689eef07db";
 "gleam_stdlib/_gleam_artefacts/gleam@bytes_tree.cache_meta","d3098ad8eb26a8cfc50cd2d7e6658d1d2f2ce3ca048b3afbbcb9f7cc6ea21f04";
 "gleam_stdlib/_gleam_artefacts/gleam@bytes_tree.erl","dead93ce8e76c2b65255649cfc0c70edd86ab0d9041344dea1543f0c88d7e7aa";
 "gleam_stdlib/_gleam_artefacts/gleam@dict.cache","7e31194651b411d0a28800295dd365d09810200ac58a90c1c07d014384c79e34";
 "gleam_stdlib/_gleam_artefacts/gleam@dict.cache_meta","b9fef0f3b558840c55b488bc2fab4a0bbe2afd97317896dc84b473eb9881915f";
 "gleam_stdlib/_gleam_artefacts/gleam@dict.erl","7f0d3188508248d89bf44d5d16c9897849c3b5895c138e5c61c6d4b7beacd3aa";
 "gleam_stdlib/_gleam_artefacts/gleam@dynamic.cache","d4d0221ed1f63e8c8f86376fa459c04ff9bbb9309420013a67041ad615c6a180";
 "gleam_stdlib/_gleam_artefacts/gleam@dynamic.cache_meta","8c27d89a250f6de8b645c3b0a42f3d5cca61dd921fc8924f9f28b8e9a124f400";
 "gleam_stdlib/_gleam_artefacts/gleam@dynamic.erl","16a1b47a2ac767b7280552a4b260cbd002f87e98be99e66f8ae6a5d6009ad219";
 "gleam_stdlib/_gleam_artefacts/gleam@dynamic@decode.cache","89a69aa4d3e81b845c91de51af85296b5d80b5045ac74fa0b15cb3c57efe8437";
 "gleam_stdlib/_gleam_artefacts/gleam@dynamic@decode.cache_meta","4045049f39799749df38b14b2b7e5e14b4140a1a97e6f5eaeb16bd6f88a94fd7";
 "gleam_stdlib/_gleam_artefacts/gleam@dynamic@decode.erl","2ad7469835b0f4a0f2ea36662ed5b5397599874ca216911ae8ceac58218bf6db";
 "gleam_stdlib/_gleam_artefacts/gleam@float.cache","07be34794afd8c76c647cf2c82d470c247c58b896e91520ffe2a7cdccf882a8d";
 "gleam_stdlib/_gleam_artefacts/gleam@float.cache_meta","56a4a5ca33140f30240997bf2c0e8a19379a8f7a4bdf5e36afd3e89035fd4b6e";
 "gleam_stdlib/_gleam_artefacts/gleam@float.erl","3445e69f9f547c22e176a91f45c974add8746612dd4154cdd5b82db3eadf1919";
 "gleam_stdlib/_gleam_artefacts/gleam@function.cache","86d3dbcaa4489704abc9870b90a5eab92d6ed29111ecd706f05b5f7c9720ac65";
 "gleam_stdlib/_gleam_artefacts/gleam@function.cache_meta","23df5276a0c09f70e1977651775e0395af989e4b8f66959cd8654b5baa9897cc";
 "gleam_stdlib/_gleam_artefacts/gleam@function.erl","283971c3e1a3d7e520e94b7d1da109176331353dec77b1bc1f6b449c0b2c30de";
 "gleam_stdlib/_gleam_artefacts/gleam@int.cache","470b40bece8b500c729d87ee9082d7d55463af1e7ef1056b52e76c88c09bf453";
 "gleam_stdlib/_gleam_artefacts/gleam@int.cache_meta","f74a9c14fcf9532deb97ce4da96d58f723c226619c797450332311f7d4dbd825";
 "gleam_stdlib/_gleam_artefacts/gleam@int.erl","b550f8cead632c6a3d89f3cb0e73368d77ccf47f9fbd571897c32587fbd72ba0";
 "gleam_stdlib/_gleam_artefacts/gleam@io.cache","5b499e3c8035ff615945af1f6846ac8291dac348ac71e6a50f0e65db2e5b10d1";
 "gleam_stdlib/_gleam_artefacts/gleam@io.cache_meta","10a47d4de1485f14e33e00dab29c58c8a50f11994a7e51ca9f8bee54ea9fc580";
 "gleam_stdlib/_gleam_artefacts/gleam@io.erl","4983172527793d75dfecc32bbb39b6a299b77562783ce1a88df8ae56ab7e8414";
 "gleam_stdlib/_gleam_artefacts/gleam@list.cache","13f83cb2edfc5707905e3b57a8b8691dd130e96cc1dacdeb97509269eaae134b";
 "gleam_stdlib/_gleam_artefacts/gleam@list.cache_meta","2c8e95547dfc317329c594614981c0e7aa04e2ff652fc787cc0bd7bc3f73dcc3";
 "gleam_stdlib/_gleam_artefacts/gleam@list.erl","4339988fd8cd05dc935b9bb32a0f93df98b278eca6f30cd7e1adb8eb62a0ab8b";
 "gleam_stdlib/_gleam_artefacts/gleam@option.cache","ec3b03c706131e8d60a771987266524bf9098ce9b7244ca11a0e9066f2829f7f";
 "gleam_stdlib/_gleam_artefacts/gleam@option.cache_meta","d91b9ea11be6d59eb7060a1e5a9edd896e3dfb2c5b36e2f35c72c3c2e0f3548c";
 "gleam_stdlib/_gleam_artefacts/gleam@option.erl","8f4cf4b16b2bb35a58d2ae78b2c4111a1ed91eb010ebf25946a41821915bd8a7";
 "gleam_stdlib/_gleam_artefacts/gleam@order.cache","4013ef539c9fcc44631aed026eabdd93c39bfbb0f61ed70b234514e7342fdc3a";
 "gleam_stdlib/_gleam_artefacts/gleam@order.cache_meta","300a16d6af9754c3e72df11190b66be15834783902e83e3f473c9131b10bac03";
 "gleam_stdlib/_gleam_artefacts/gleam@order.erl","40293115a54d4b2739517c71fc1cc6f6fba96cdf27c9a88b68ea5f667a9413bc";
 "gleam_stdlib/_gleam_artefacts/gleam@pair.cache","572d6df6140d01d4bc6fdeacfbbff304ec0c8b863350e70adbd788b3a8d7e6bd";
 "gleam_stdlib/_gleam_artefacts/gleam@pair.cache_meta","954841aeba56259339cf5ae017e46a4395e5bd7c3077fe2553770d80eb697007";
 "gleam_stdlib/_gleam_artefacts/gleam@pair.erl","001103121c74817c6a1cbbc35c533ffa0ec3a277bea3b9394c347659dcfe991b";
 "gleam_stdlib/_gleam_artefacts/gleam@result.cache","8e9dd916304f85f1544db742582c22e7ceff6f8e06e3aa76712e24fc53e38453";
 "gleam_stdlib/_gleam_artefacts/gleam@result.cache_meta","f735b47dd67b2da7d3ccd89a66937b5ec675ff118984637dc9a87d3ac7a7a6e1";
 "gleam_stdlib/_gleam_artefacts/gleam@result.erl","15203b0e3d6c0204ab5c8d612777e8f5a358a8a7ea20b16bf0b9491d1b2c8210";
 "gleam_stdlib/_gleam_artefacts/gleam@set.cache","a6d729ba12c93274aee4a5f82cbf2bd2c86131b5866a52fb2aab6e0f05c78611";
 "gleam_stdlib/_gleam_artefacts/gleam@set.cache_meta","b24df616a826c9e6f9eb809a99da09a08fbcc28862acd32381bbf5bcad4dd4b3";
 "gleam_stdlib/_gleam_artefacts/gleam@set.erl","1e479584f2e25267530ff8666b25d735edcc6d150fd1e89568052d3bbe41fbd5";
 "gleam_stdlib/_gleam_artefacts/gleam@string.cache","030fc96a848e73d69f2c87a9db2007a5c786237f0c632dac0fcf681cd982c05b";
 "gleam_stdlib/_gleam_artefacts/gleam@string.cache_meta","ede5ffaa894d38c980ecd5ab9de2441a1228b97067b81f3b102f95ae7e4f51cf";
 "gleam_stdlib/_gleam_artefacts/gleam@string.erl","fc535a2abcde4fdca6ea2932ee52ea1e6dc90410b06ec8bc2776699e83895eec";
 "gleam_stdlib/_gleam_artefacts/gleam@string_tree.cache","99c431d9314b7699de9155c80f3d931674742feba418439d9d14ddd67c9ccadd";
 "gleam_stdlib/_gleam_artefacts/gleam@string_tree.cache_meta","2a5ef7a30b43d1c76f5fbbc00a32d9fcc31c77943667435c8d306a78ab685c8d";
 "gleam_stdlib/_gleam_artefacts/gleam@string_tree.erl","72df078685a1e6d870f5cdce461ccb3e8feefa13cac3b62fcd077c07957b837f";
 "gleam_stdlib/_gleam_artefacts/gleam@uri.cache","27d89d9e6679e0535cfcae1e2c4a46faa33a1486fdb4b1f2ffc86e908b6ddf04";
 "gleam_stdlib/_gleam_artefacts/gleam@uri.cache_meta","7a23f43c52a731978ed10148f636fc4ba0300e2eb1667634a619985a79eef7f1";
 "gleam_stdlib/_gleam_artefacts/gleam@uri.erl","82805757c0e2baaa13c7aaad38821d2f423f113fc9e3b519a084cadc6aa2a430";
 "gleam_stdlib/_gleam_artefacts/gleam_stdlib.erl","05193b8af154d080181fa71c9f72f787ce2b57d6ea41eb10116a427cccd64ec7";
 "gleam_stdlib/_gleam_artefacts/gleam_stdlib.mjs","2d2f61eac84ae0d332df8b4899c22348dcd9e1d67a63fff84aa8a4be86b0559b";
 "gleam_stdlib/ebin/gleam@bit_array.beam","413eb4d4cc94753fbbbdee5755855398f28e8f91b69b24bee1d54263e3f7776f";
 "gleam_stdlib/ebin/gleam@bool.beam","987f282d91b690e0f222bb98d81fc5dbd5b4c93dee9c50a99aa846a57adc02dd";
 "gleam_stdlib/ebin/gleam@bytes_tree.beam","bd40e320272ae902748b9353e2ea2a15a31a406099a8095a0fadab558a360946";
 "gleam_stdlib/ebin/gleam@dict.beam","0572a1ed1d7a91ef94efe0e882da7059cae5d841271eba9e3ca85771876a2f72";
 "gleam_stdlib/ebin/gleam@dynamic.beam","8ccd6fcc552b4d465faa377120d51dfa748fa3a6b1677a0354b6a839884620af";
 "gleam_stdlib/ebin/gleam@dynamic@decode.beam","64f7a71fbfe0ce861e1223e1988c341b5437f7441cbc2f110c2b24dc7d8a0f20";
 "gleam_stdlib/ebin/gleam@float.beam","cc80c9e0ba778cdc113376fd2c221dfdb72b6acaf0db75c7db5d2c8a6514e37e";
 "gleam_stdlib/ebin/gleam@function.beam","ce86b4e773db442aaa9b7d97a79f0de3b5abfd8a52783412fc357f77fee4c9f8";
 "gleam_stdlib/ebin/gleam@int.beam","598affceb0923e42b210d930205e5c0937dc4c40d3f9a381291859b04b8555f4";
 "gleam_stdlib/ebin/gleam@io.beam","8fb8da74b516adacdb3c4034ac2428d4fd0377de75d137b5f441ac479f321021";
 "gleam_stdlib/ebin/gleam@list.beam","2b9b36a5114862c9ac30bbdfa6de633f60478e946f97ddaaa242ebe8e5c8eead";
 "gleam_stdlib/ebin/gleam@option.beam","55bcb69ae73aa6c832f9db686481fc27cf5b928d6279383a9f691a629aaaf38f";
 "gleam_stdlib/ebin/gleam@order.beam","cfb5ca41b13da7eafa05a3765ff280253fe0e8055067f6c87a917283e238cfcf";
 "gleam_stdlib/ebin/gleam@pair.beam","7b949b029e5dec8dff7101c463d81390cada8accd573bb1aa4d4d067f9cb88d4";
 "gleam_stdlib/ebin/gleam@result.beam","a19b70e6cc637f0e88b220d299d6ea86319bec7b78f073b7a106133c328e78b6";
 "gleam_stdlib/ebin/gleam@set.beam","4164f84ff3099becb4bc5accb44204baf97f25f16fd1d376376e3f7f3a225ae4";
 "gleam_stdlib/ebin/gleam@string.beam","d5e55ae2686c0208231956eed3761a99d38394022183733939207983af715d59";
 "gleam_stdlib/ebin/gleam@string_tree.beam","c83a42ab5346f59609e90c77bfb055188d061c67298900617fe599e0d5c0bb16";
 "gleam_stdlib/ebin/gleam@uri.beam","4bd31c68f9028979fd823157f09b76f6561a04aff9ef99b3ebd98b3e5851b644";
 "gleam_stdlib/ebin/gleam_stdlib.app","564f6680ff5714b74a507b0daa249eb12959218a3d409997a1b85b8f71ab9388";
 "gleam_stdlib/ebin/gleam_stdlib.beam","83d52200988a4f8c85c687d25bd4a2ee39683eacb40af526208590a84812bd1c";
 "gleam_stdlib/include/gleam@dynamic@decode_DecodeError.hrl","42fdc2120548b93d0fdf1058454162bf89c75b401841b34bfbdb9a4e9da3429d";
 "gleam_stdlib/include/gleam@dynamic@decode_Decoder.hrl","6e84073ff788225669fee845163a3ebaecd239e47e9fa7468783f4422182dfc2";
 "gleam_stdlib/include/gleam@set_Set.hrl","f4a015505149a51df8cdd189d7e63014497a3b9f172d2500d5cea69fc64b1515";
 "gleam_stdlib/include/gleam@uri_Uri.hrl","dd83aade828a98af66050b5e6b033dfb183c1213841644e5edc245ad66a83c51";
 "gleam_json/_gleam_artefacts/gleam@json.cache","26c2bbe6f03bf1aa2bf11b59165d0076a53a3dc94f0972d7041de7680b73dd71";
 "gleam_json/_gleam_artefacts/gleam@json.cache_meta","dc7ae927a6d57ab08cf28b3a1e3917701c13adb949146aec26988b37c393cbab";
 "gleam_json/_gleam_artefacts/gleam@json.erl","88179752f2d5058bd62e229d2a28a8ec4add00c2ed868e4fd84dbbc507056fa5";
 "gleam_json/_gleam_artefacts/gleam_json_ffi.erl","47e2b22dce43005914eb3c9b50b3cf2556713391f4d2f43f76aff1941b74143d";
 "gleam_json/_gleam_artefacts/gleam_json_ffi.mjs","14fa64bb2f903dfa21f8b185de696232964d1e5c365fc154e4e1a93a412e5186";
 "gleam_json/ebin/gleam@json.beam","9b442352fc5cf41ed33f5427590242303d2277882c261032e4053f67c55606bf";
 "gleam_json/ebin/gleam_json.app","be2ae9395bfc1c1ec09bf9e415b489c5b756e6c02dd6e4a2a04c5b937827e92c";
 "gleam_json/ebin/gleam_json_ffi.beam","25e4709e6f768dad83f70cc1a7a11af7975e472cdeb52fa515234771a690fb60";
 "gleeunit/_gleam_artefacts/gleeunit/internal/gleeunit_gleam_panic_ffi.erl","30ab1da8b8093a61f52aed7ebb9c8dc6544f46b3615e3d136b049529a195a620";
 "gleeunit/_gleam_artefacts/gleeunit/internal/gleeunit_gleam_panic_ffi.mjs","2712de784dfff2e7f67f2d83631c48f6424b2acbf58a0a20b39ffd0f247e61d5";
 "gleeunit/_gleam_artefacts/gleeunit.cache","8abaf39f5cd5b425ddedf6a4e3072e75270a658263c0368cd622c07bc19d7aaf";
 "gleeunit/_gleam_artefacts/gleeunit.cache_meta","3013daaca462ef509ffa64e8b92a33cae152d8296a25e350caddf67a033c66b6";
 "gleeunit/_gleam_artefacts/gleeunit.erl","7b23b188700a40a854b0bb069fe94d1546698be1c7e2968acaeae091ef8dd1e7";
 "gleeunit/_gleam_artefacts/gleeunit@internal@gleam_panic.cache","1ef218bcef5af4bfd26482614eac91f06dbb62054aada885bff7355bffde1e9f";
 "gleeunit/_gleam_artefacts/gleeunit@internal@gleam_panic.cache_meta","a549b963c5f887bb26fb9bf108e5d94c363d91c8f8b5748523f1b5dc5b964673";
 "gleeunit/_gleam_artefacts/gleeunit@internal@gleam_panic.erl","6bd02d8cc12e7e5e192e20be1339c9d3f8a4afcb010d705dc73952685603de64";
 "gleeunit/_gleam_artefacts/gleeunit@internal@reporting.cache","be39e86446fefffe2506c7f83a3e50f0fd14b03a2f6577c896108cc23f61265f";
 "gleeunit/_gleam_artefacts/gleeunit@internal@reporting.cache_meta","1066c9e262bd7c40c1870f7d4c64513e6ce4ca40586e5e003c5d323f783692c6";
 "gleeunit/_gleam_artefacts/gleeunit@internal@reporting.erl","b176bd8926532ccbc4a9b8f0926112c836f43d9f4f77242df61f857ef49825cb";
 "gleeunit/_gleam_artefacts/gleeunit@should.cache","0f50ce4f22557c42bbd1c7e44fe4b0844c778e00e8e795f0fda9bb0a657e99b7";
 "gleeunit/_gleam_artefacts/gleeunit@should.cache_meta","d5e14679a63f3ddec00e6509f192c6a61db94e1072bb63fda95a3ea3db61e857";
 "gleeunit/_gleam_artefacts/gleeunit@should.erl","ddeef6463db97f5501cdd0da259200d412c1d1b29babf99ffb38b011bf7d1c37";
 "gleeunit/_gleam_artefacts/gleeunit_ffi.erl","b8f30b7a76f89d5dec18736fcd7509e079438b756e1fe46b376e55bf81745e8a";
 "gleeunit/_gleam_artefacts/gleeunit_ffi.mjs","4cbdee800ce10cf5c33d34676d72f93b013ee8d0bb25723275f421d0358029e6";
 "gleeunit/_gleam_artefacts/gleeunit_progress.erl","4a0032e820a786dc2fbc0a14b7db9f866ab8b584edd8f7cf419f6298f8eff0a8";
 "gleeunit/ebin/gleeunit.app","2edcb0c547c8cc82edc03e59e8f4adbce7dde35c2a77d8988c5ac3400d026a4c";
 "gleeunit/ebin/gleeunit.beam","76363f17e1a0dfff489cce5331997cf1177c018e739244a40136c70c82ffad92";
 "gleeunit/ebin/gleeunit@internal@gleam_panic.beam","ef72830c038d2160d4046925c5957a01d725351e2a8bee268ab5373db552e331";
 "gleeunit/ebin/gleeunit@internal@reporting.beam","ff5671e402297827d583dfce57a27635ff81c1aaf4abbd7678aa08fad3ae12d3";
 "gleeunit/ebin/gleeunit@should.beam","cf90cb19d4a8c2e9179d277826ee528205f70561a44a5f74ad7eb6781788fe5e";
 "gleeunit/ebin/gleeunit_ffi.beam","c3fd0676542df60b8379e660e58f5548d91f16b3e2e3b3478818f74e259e222e";
 "gleeunit/ebin/gleeunit_gleam_panic_ffi.beam","1d37269c50ce82a5b9704e2fb5307775fc303e809a21128b240979fd978dcaa7";
 "gleeunit/ebin/gleeunit_progress.beam","bb66656921cc87bf04211738fc9ff8ca11b729b56d803967d9570d81d198cf29";
 "gleeunit/include/gleeunit@internal@gleam_panic_Assert.hrl","fd0bc2bcc4faf6c2ee5a26ff18ee53d92d651639b0dd945133740dbdda4fa0d9";
 "gleeunit/include/gleeunit@internal@gleam_panic_AssertedExpression.hrl","599ab9c6951d9721dd8edcf6c428383d1c7017f0116a0a0c3de792754e32e0fa";
 "gleeunit/include/gleeunit@internal@gleam_panic_BinaryOperator.hrl","4a4bb9a878af757df6c959f70b46bb4595ebafac2cbb0afb580ffff330cd7c48";
 "gleeunit/include/gleeunit@internal@gleam_panic_Expression.hrl","70b5115dc20a773eb4a37c7c9d3cabd8d2e1de0124528986157031a60c6ec946";
 "gleeunit/include/gleeunit@internal@gleam_panic_FunctionCall.hrl","f5227ca4466ae1554f9ed6e5ceeeea0e584f13ef7221d7df77de83750d39b1dd";
 "gleeunit/include/gleeunit@internal@gleam_panic_GleamPanic.hrl","6abb45ceb505a6e66875b9e71786edb9d53f1377c4a9bd1fa1e485c7cb2aeea9";
 "gleeunit/include/gleeunit@internal@gleam_panic_LetAssert.hrl","689909fb356db5bb75c7ad711296112fc39ab03ba470a900decc1d0ad2059153";
 "gleeunit/include/gleeunit@internal@gleam_panic_Literal.hrl","1f1db586d94ce287f237aa1cffabea3dc96d5be493f62cbcc99e335ee39412af";
 "gleeunit/include/gleeunit@internal@gleam_panic_OtherExpression.hrl","16620c3aa9d644a92458f6e7282c643b99d0b61f001e1fbe65266b2e11122643";
 "gleeunit/include/gleeunit@internal@reporting_State.hrl","0a97a575b059315e4facc437123674cafb4946698512947787db5a47c433c2f2";
]
let tools = [
 "tput","/usr/bin/tput","568b559c40262dcb851aed26115767ca646b4269118a0c93ded7d2dd5c565ec6";
 "erl_child_setup","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/erts-17.0.5/bin/erl_child_setup","e9a620ec4fcd8fb2ac55dfd9a8b0c59ee52ef363454c6502ff26efa2f5476025";
 "inet_gethost","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/erts-17.0.5/bin/inet_gethost","ca4553748665924716d883b9be80e8a4648565c9108ae22a4e56b9f9467b86e0";
 "gleam","/home/an/NAS-setup/uos/toolchains/gleam-1.16.0/bin/gleam","9d57b042c9f857ed898f4b99116ad8433bed2504619613c97d72a52288bef697";
 "jj","/nix/store/vzrnnii3369cn2a2bgdlkx9gh6m297fj-jujutsu-0.44.0/bin/jj","630fe2c54d0b9f53794aa37c1274a344e6067175ac9e8925087974fb3d0c4966";
 "chronyc","/usr/bin/chronyc","0cd6afd41067d36b080222cfc51517755b8a03496e4c3ef628ec54ee2435531f";
 "erlc","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/bin/erlc","260f026b6746ebcfa99e2568852c3dfda3bcef6227984315f5e5888ff5c9d503";
 "escript","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/bin/escript","985522721e68d744f021d43146a3d3e739d4da039280f03f6763987140774a24";
 "boot","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/bin/no_dot_erlang.boot","70204d7d0754c4d9ae767cd9b014493d895e272f9532532f0bceac728288b4be";
 "erlexec","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/erts-17.0.5/bin/erlexec","bd67dd9a907245330ed2959749d00345b7f9f3cfa7dbb109e970c16168e231a8";
 "beam","/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang/erts-17.0.5/bin/beam.smp","632442f4075f4014172cd95f18151a5b4c048c483a7fb3c10577826cdb3b8966";
]
(* Inspected OTP-29.0.5 erlc/escript native launch controls. No shell wrapper. *)
let otp_root = "/nix/store/96cqahwqjxzx4pywz1bj53apncjmhhdg-erlang-29.0.5/lib/erlang"
let bindir = otp_root ^ "/erts-17.0.5/bin"
let launcher_environment = [
 "ROOTDIR=" ^ otp_root; "ERL_ROOTDIR=" ^ otp_root; "BINDIR=" ^ bindir;
 "EMU=beam"; "PROGNAME=erl";
 "ESCRIPT_EMULATOR=" ^ bindir ^ "/erlexec";
 "ERLC_EMULATOR=" ^ bindir ^ "/erlexec"; "ERLC_USE_SERVER=false";
]
