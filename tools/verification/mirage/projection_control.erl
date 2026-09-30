%% Calls the compiled candidate's actual disk reader and serializer.
%% No web listener is started or modified by this independent control.
-module(projection_control).
-export([run/1]).

run(Root) ->
    ReceiptPath = filename:join(Root, "var/mirage/receipts/hypervisors_probe.json"),
    ok = filelib:ensure_dir(ReceiptPath),
    Forged = <<"{\"schema\":\"uos-mirage-hypervisor-probe/v1\","
               "\"timestamp_utc\":\"2000-01-01T00:00:00Z\",\"host\":\"wrong-host\","
               "\"overall_readiness\":\"solo5_hardware_virtualized_and_spt_verified\","
               "\"execution_policy\":\"two_key_receipt_required_before_admission\","
               "\"evidence_scope\":\"host_hypervisor_hardware_probe\","
               "\"deployment_admission\":\"TENDERS_VERIFIED_PHYSICAL_EXECUTION\","
               "\"kvm\":{\"dev_kvm_present\":false,\"dev_kvm_rw_accessible\":false},"
               "\"qemu\":{\"microvm_supported\":false,\"kvm_accel_supported\":false},"
               "\"solo5\":{}}">>,
    ok = file:write_file(ReceiptPath, Forged),
    ok = file:set_cwd(Root),
    Report = 'cepaf_gleam@services@mirage_hypervisor':read_probe_receipt(),
    Json = 'cepaf_gleam@services@mirage_hypervisor':probe_report_to_json(Report),
    Serialized = 'gleam@json':to_string(Json),
    io:put_chars(Serialized),
    io:nl(),
    case binary:match(Serialized, <<"TENDERS_VERIFIED_PHYSICAL_EXECUTION">>) of
        nomatch -> 0;
        _ -> 1
    end.
