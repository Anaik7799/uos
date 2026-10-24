import cepaf_gleam/harness/telegram_action_proposal as proposal
//// Test-only signed service fixture. No live recipient or production keys.

import cepaf_gleam/harness/clock
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_action_packet as packet
import cepaf_gleam/harness/telegram_action_profile as profile
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_bridge as bridge
import cepaf_gleam/harness/telegram_cancellation as cancel
import cepaf_gleam/harness/telegram_cancellation_record as record
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_http_client as http
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_service as service
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile
import uos_swarm/session_store as coord
import uos_swarm/session_sync as sync

@external(erlang, "telegram_approval_test_crypto", "public_key")
fn public_key(role: String) -> String

@external(erlang, "telegram_approval_test_crypto", "sign")
fn sign(role: String, payload: String) -> String

const reason = "Operator requested cancellation"

const text = "/tool cancel_job_lease cancel-plan/job1 -- Operator requested cancellation"

fn profile_raw(
  c: profile.Context,
  mapping,
  expiry,
  g,
  gsha,
  w,
  wsha,
  database,
  created,
) {
  let assert Ok(r) =
    bridge.new(
      mapping,
      c.plan,
      c.task,
      c.worker,
      c.attempt,
      "control-lease",
      expiry,
    )
  let signers =
    list.map(["codex", "agy", "operator"], fn(role) {
      json.array(
        [
          json.string(role),
          json.string(role <> "-subject"),
          json.string(role <> "-key"),
          json.string(public_key(role)),
        ],
        fn(x) { x },
      )
    })
  json.object([
    #("schema", json.string("uos.telegram.action-profile.v2")),
    #(
      "context",
      json.array(
        [
          json.int(c.bot),
          json.string(c.plan),
          json.string(c.task),
          json.string(c.worker),
          json.int(c.attempt),
          json.int(c.epoch),
          json.int(c.service_epoch),
          json.string(c.candidate),
          json.string(c.host),
          json.string(c.boot),
          json.string(c.machine_id),
        ],
        fn(x) { x },
      ),
    ),
    #("provision_json", json.string(bridge.request_json(r))),
    #("transport", json.array([g, gsha, w, wsha, database], json.string)),
    #(
      "roster",
      json.array(
        [
          json.int(created - 1),
          json.int(created + 120_000),
          json.array(signers, fn(x) { x }),
        ],
        fn(x) { x },
      ),
    ),
  ])
  |> json.to_string
}

fn packet_raw(p: profile.Profile, mapping, fence, target_lease, now, boot) {
  let c = profile.context(p)
  let b =
    action.Binding(
      c.bot,
      100,
      200,
      10,
      c.plan,
      c.task,
      c.worker,
      c.attempt,
      c.epoch,
      c.candidate,
      c.host,
      c.boot,
      action.Execution(mapping, "control-lease", fence, profile.digest(p)),
    )
  let t = action.Target("cancel-plan/job1", "job-worker", 1, target_lease)
  let assert Ok(i) =
    action.new(
      b,
      t,
      action.Window(now, boot, now + 60_000, boot + 60_000),
      reason,
      string.repeat("b", 64),
    )
  let receipts =
    list.map([approval.Codex, approval.Agy, approval.Operator], fn(role) {
      let n = approval.role_name(role)
      let token =
        sign(
          n,
          json.object([
            #("version", json.string("uos.telegram.approval.v1")),
            #("purpose", json.string("cancel_job_lease")),
            #("role", json.string(n)),
            #("subject", json.string(n <> "-subject")),
            #("decision", json.string("approve")),
            #("intent_digest", json.string(action.digest(i))),
            #("effect_id", json.string(action.effect_id(i))),
            #("iat_ms", json.int(now)),
            #("nbf_ms", json.int(now)),
            #("exp_ms", json.int(now + 30_000)),
            #(
              "roster_digest",
              json.string(approval.roster_digest(profile.roster(p))),
            ),
          ])
            |> json.to_string,
        )
      approval.Receipt(role, token)
    })
  let o = cancel.Observation(c.host, c.boot, now, boot)
  let assert Ok(e) =
    approval.verify(profile.roster(p), i, c.host, c.boot, now, boot, receipts)
  let assert Ok(prepared) = cancel.prepare(i, e, profile.roster(p), b, t, o)
  let raw =
    json.object([
      #("schema", json.string("uos.telegram.action-packet.v1")),
      #(
        "recovery_json",
        json.string(record.encode(cancel.recovery_record(prepared))),
      ),
      #(
        "receipts",
        json.array(receipts, fn(r) {
          json.array([approval.role_name(r.role), r.token], json.string)
        }),
      ),
    ])
    |> json.to_string
  #(raw, prepared, o)
}

fn row(c, key) {
  let assert Ok(#(_, [r])) = store.read_keys(c, [key])
  r
}

fn expect_error(result, expected) {
  let assert Error(service.ServiceError(_, reason)) = result
  reason |> should.equal(expected)
}

pub fn run_native(
  root,
  database,
  g,
  gsha,
  w,
  wsha,
  mapping,
  fence,
  bridge_expiry,
  target_lease,
  mode,
) {
  let assert Ok(observed) = clock.observe()
  let now = observed.sample.observed.utc_us / 1000
  let boot = observed.sample.observed.boot_us / 1000
  let c =
    profile.Context(
      333_444,
      "cancel-plan",
      "controller",
      "controller",
      1,
      1,
      1,
      wsha,
      "nas-1.tail55d152.ts.net",
      observed.sample.observed.domain.boot_id,
      observed.sample.observed.domain.host_id,
    )
  let raw =
    profile_raw(c, mapping, bridge_expiry, g, gsha, w, wsha, database, now)
  let assert Ok(p) =
    profile.persist(root, "profile.json", raw, files.digest(raw), c)
  let #(packet_text, prepared, o) =
    packet_raw(p, mapping, fence, target_lease, now, boot)
  let assert Ok(_) = files.create(root, "packet.json", packet_text)
  let assert Ok(decoded) = packet.load(p, root, "packet.json", o)
  cancel.request_json(decoded) |> should.equal(cancel.request_json(prepared))
  // Exact packet, signature, expiry and schema denial coverage.
  let bads = [
    string.replace(packet_text, "action-packet.v1", "action-packet.future"),
    string.replace(packet_text, "\"schema\":", "\"extra\":true,\"schema\":"),
    string.replace(packet_text, "\"schema\":", "\"schema\":null,\"schema\":"),
    string.replace(packet_text, "\"operator\"", "\"claude\""),
    string.replace(packet_text, "eyJ", "ayJ"),
    "{}",
    string.repeat("x", 65_537),
  ]
  list.index_map(bads, fn(raw, index) {
    let name = "bad-" <> int.to_string(index) <> ".json"
    let assert Ok(_) = files.create(root, name, raw)
    packet.load(p, root, name, o)
    |> should.equal(Error("action_packet_invalid"))
  })
  packet.load(
    p,
    root,
    "packet.json",
    cancel.Observation(..o, utc_ms: now + 30_000, boot_ms: boot + 30_000),
  )
  |> should.equal(Error("action_packet_invalid"))
  let tg =
    transport.reviewed_local_configuration(
      "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe",
      "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab",
      "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe",
      "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e",
      root <> "/telegram.sqlite3",
    )
  let assert Ok(_) = store.initialize_store(tg, c.bot)
  let coord_path = root <> "/coord.sqlite3"
  let assert Ok(co) = coord.open(coord_path)
  let assert Ok(_) =
    coord.append(
      co,
      sync.Register("controller", "codex", root, "candidate", []),
      "register",
    )
  let assert Ok(_) =
    coord.append(
      co,
      sync.Claim("controller", "runtime:telegram-bridge", 120_000_000),
      "claim",
    )
  let assert Ok(_) = coord.close(co)
  let config =
    service.operational_service_configuration(
      tg,
      http.default_configuration(
        "http://nas-1.tail55d152.ts.net:1",
        "TEST_ONLY",
      ),
      c.bot,
      [#(100, 200)],
      c.plan,
      c.task,
      c.worker,
      "controller",
      1,
      1,
      1,
    )
  let config =
    service.ServiceConfiguration(
      ..config,
      authority_paths: service.IsolatedTestPaths(database, coord_path),
    )
  let assert Ok(#(initial, _)) = service.init_service(config, None)
  let assert Ok(#(wm, v, h)) = store.read_watermark(tg)
  let verdict =
    guard.AcceptedEnvelope(
      10,
      11,
      100,
      200,
      files.digest(text),
      text,
      guard.classify_directive(text),
      c.bot,
      None,
    )
  let assert Ok(prefix) =
    store.commit_prefix(
      tg,
      c.bot,
      "prefix",
      initial.expected_generation,
      wm,
      v,
      h,
      [verdict],
      now,
    )
  let assert [inbox] = prefix.admitted_records
  case mode {
    "approval_status" | "approval_foreign" -> approval_status_fixture(initial,prefix,inbox,p,root,bridge_expiry,now,mode)
    "proposal_flow" -> proposal_flow_fixture(initial,prefix,inbox,p,root,bridge_expiry,now)
    "proposal_collect" -> proposal_collect_fixture(initial,prefix,inbox,p,bridge_expiry)
    "proposal" -> proposal_fixture(initial,prefix,inbox,p,bridge_expiry,target_lease)
    "dispatch" -> dispatch_fixture(initial,prefix,inbox,p,root,packet_text,bridge_expiry,now)
    _ -> {
  let assert Ok(#(receipt, inbox)) =
    store.claim_task_processing(
      tg,
      c.bot,
      "claim",
      prefix.receipt.generation,
      inbox,
      1,
      files.digest(codec.encode_inbox_record(inbox)),
      c.worker,
      1,
      now,
    )
  let v = 2
  let h = files.digest(codec.encode_inbox_record(inbox))
  let assert Ok(worker) = service.start_store_worker(tg, c.bot)
  let state =
    service.ServiceState(
      ..initial,
      expected_generation: receipt.generation,
      store_worker: Some(worker.data),
    )
  let state =
    service.set_authority(
      state,
      service.AuthorityLease("service-test", 1, 1, bridge_expiry / 1000),
    )
  let run = fn(state, p, name) {
    service.execute_approved_cancellation(state, p, root, name, inbox, v, h)
  }
  run(service.revoke_authority(state), p, "packet.json")
  |> expect_error("action_authority_refused")
  run(state, p, "missing.json") |> expect_error("action_packet_invalid")
  run(state, p, "bad-4.json") |> expect_error("action_packet_invalid")
  let denied = service.ServiceConfiguration(..config, allowed_pairs: [])
  run(service.ServiceState(..state, config: denied), p, "packet.json")
  |> expect_error("action_recipient_refused")
  let changed = profile.Context(..c, machine_id: string.repeat("0", 64))
  let altered =
    profile_raw(
      changed,
      mapping,
      bridge_expiry,
      g,
      gsha,
      w,
      wsha,
      database,
      now,
    )
  let assert Ok(other) =
    profile.persist(
      root,
      "other-profile.json",
      altered,
      files.digest(altered),
      changed,
    )
  let #(other_packet, _, _) =
    packet_raw(other, mapping, fence, target_lease, now, boot)
  let assert Ok(_) = files.create(root, "other-packet.json", other_packet)
  run(state, other, "other-packet.json")
  |> expect_error("action_host_boot_refused")
  let assert Ok(_) = simplifile.write(root <> "/profile.json", raw <> " ")
  run(state, p, "packet.json") |> expect_error("action_profile_refused")
  let assert Ok(_) = simplifile.write(root <> "/profile.json", raw)
  let expired =
    profile_raw(
      c,
      mapping,
      now * 1_000_000 - 1,
      g,
      gsha,
      w,
      wsha,
      database,
      now,
    )
  let assert Ok(expired_profile) =
    profile.persist(
      root,
      "expired-profile.json",
      expired,
      files.digest(expired),
      c,
    )
  run(state, expired_profile, "packet.json")
  |> expect_error("action_profile_refused")
  let bad_config =
    service.ServiceConfiguration(..config, expected_task_attempt: 2)
  let bad_state =
    service.set_authority(
      service.ServiceState(..state, config: bad_config),
      service.AuthorityLease("service-test", 2, 1, bridge_expiry / 1000),
    )
  run(bad_state, p, "packet.json") |> expect_error("action_authority_refused")
  row(tg, store.cancellation_key(inbox.request_id)).exists |> should.be_false
  row(tg, codec.result_key(inbox.request_id)).exists |> should.be_false
  case mode {

    "recover" | "recover_absent" | "recover_dispatch" -> {
      let assert Ok(res)=store.persist_cancellation(tg,state.expected_generation,inbox,v,h,c.worker,1,prepared)
      let recovering=service.ServiceState(..state,
        config:service.ServiceConfiguration(..state.config,service_epoch:2),
        expected_generation:store.cancellation_generation(res))
      case mode {
        "recover_absent" -> {
          service.recover_cancellation(recovering,p,inbox,v,h)
            |> expect_error("action_store_refused")
          row(tg,codec.result_key(inbox.request_id)).exists |> should.be_false
          "service_recovery_absent_not_reexecuted"
        }
        _ -> {
          let assert Ok(raw_effect)=transport.exchange(profile.transport(p),cancel.envelope(prepared,cancel.Cancel))
          let assert Ok(observed_after)=clock.observe()
          let now=observed_after.sample.observed.utc_us / 1000
          let assert Ok(cancel.LeaseRevoked(_,_,False))=cancel.decode_response(prepared,cancel.Cancel,raw_effect,now)
          // Same epoch cannot transfer to a different owner; malformed history is no result.
          let assert Ok(history)=transport.exchange(profile.transport(p),cancel.recovery_envelope(cancel.recovery_record(prepared)))
          store.commit_cancellation_lookup_for(res,history,now,"other",1) |> should.be_error
          store.commit_cancellation_lookup_for(res,"{}",now,c.worker,2) |> should.be_error
          service.recover_cancellation(service.revoke_authority(recovering),p,inbox,v,h)
            |> expect_error("action_authority_refused")
          let assert Ok(_)=simplifile.write(root <> "/profile.json",raw <> " ")
          service.recover_cancellation(recovering,p,inbox,v,h) |> expect_error("action_profile_refused")
          let assert Ok(_)=simplifile.write(root <> "/profile.json",raw)
          // No packet is loaded in recovery and no fresh signatures are requested.
          let assert Ok(_)=simplifile.write(root <> "/packet.json","{}")
          case mode {
            "recover_dispatch" -> recovery_dispatch_fixture(recovering,p,root,now)
            _ -> {
          let assert Ok(#(after,committed))=service.recover_cancellation(recovering,p,inbox,v,h)
          let assert [chunk]=committed.chunks
          let a=row(tg,codec.authority_key(inbox.request_id))
          let assert Ok(a)=codec.decode_row_value(a)
          let assert Ok(a)=codec.decode_authority_value(a)
          a.epoch |> should.equal(2)
          a.worker |> should.equal(c.worker)
          let assert Ok(#(_,chunk))=store.commit_sending(tg,c.bot,"recovered-send",
            after.expected_generation,committed.inbox_record,v+1,
            files.digest(codec.encode_inbox_record(committed.inbox_record)),chunk,1,
            files.digest(codec.encode_chunk_value(chunk)),c.worker,2)
          let assert ledger.OutboxSending(_,2)=chunk.status
          "service_recovery_new_epoch_outbox_sendable"
            }
          }
        }
      }
    }
    "revoked_coordinator" -> {
      let assert Ok(co) = coord.open(coord_path)
      let assert Ok(_) =
        coord.append(
          co,
          sync.Release("controller", "runtime:telegram-bridge", 1),
          "release",
        )
      let assert Ok(_) = coord.close(co)
      run(state, p, "packet.json") |> expect_error("action_authority_refused")
      row(tg, store.cancellation_key(inbox.request_id)).exists
      |> should.be_false
      "revoked_coordinator_no_effect"
    }
    "wrong_fence" -> {
      run(state, p, "packet.json") |> expect_error("action_bridge_not_current")
      row(tg, codec.result_key(inbox.request_id)).exists |> should.be_false
      "changed_bridge_fence_refused"
    }
    "existing_absent" -> {
      let assert Ok(res) =
        store.persist_cancellation(
          tg,
          state.expected_generation,
          inbox,
          v,
          h,
          c.worker,
          1,
          prepared,
        )
      let state =
        service.ServiceState(
          ..state,
          expected_generation: store.cancellation_generation(res),
        )
      run(state, p, "packet.json") |> expect_error("action_outcome_unresolved")
      row(tg, codec.result_key(inbox.request_id)).exists |> should.be_false
      "persisted_absent_not_reexecuted"
    }
    _ -> {
      let assert Ok(#(state, done)) = run(state, p, "packet.json")
      let assert ledger.InboxResultReady(_) = done.inbox_record.status
      state.expected_generation |> should.equal(done.receipt.generation)
      let assert [chunk] = done.chunks
      chunk.status |> should.equal(ledger.OutboxPending)
      chunk.payload
      |> should.equal(
        "Cancellation recorded: the job lease was revoked. Worker termination is not confirmed.",
      )
      "service_signed_cancel_outbox"
    }
  }
}
  }
}

@external(erlang, "telegram_http_test_fixture", "start")
fn fixture_start() -> Result(#(process.Pid, Int, String), Dynamic)
@external(erlang, "telegram_http_test_fixture", "stop")
fn fixture_stop(pid: process.Pid) -> Dynamic
@external(erlang, "telegram_http_test_fixture", "get_requests")
fn fixture_requests(pid: process.Pid) -> List(#(String,String,String,String))

fn dispatch_fixture(initial:service.ServiceState,prefix:store.CommitPrefixResult,
  inbox:ledger.InboxRecord,p:profile.Profile,root:String,packet_text:String,
  bridge_expiry:Int,now:Int) -> String {
  let assert Ok(#(pid,_,url))=fixture_start()
  let assert Ok(cfg)=service.configure_actions(initial.config,root,"profile.json",
    profile.digest(p),profile.context(p),root)
  let cfg=service.ServiceConfiguration(..cfg,http_config:http.default_configuration(url,"TEST_ONLY"))
  let state=service.set_authority(service.ServiceState(..initial,config:cfg,
    expected_generation:prefix.receipt.generation),
    service.AuthorityLease("service-test",1,1,bridge_expiry / 1000))
  // Missing approvals stay pending without claiming processing or making requests.
  let assert Ok(#(same,service.DispatchCycleResult(0,0)))=service.dispatch_cycle(state,now*1000)
  same.expected_generation |> should.equal(prefix.receipt.generation)
  let ir=row(cfg.storage_config,codec.inbox_key(inbox.request_id))
  let assert Ok(raw)=codec.decode_row_value(ir)
  let assert Ok(pending)=codec.decode_inbox_record(raw)
  pending.status |> should.equal(ledger.InboxPending)
  fixture_requests(pid) |> should.equal([])
  let assert Ok(_)=files.create(root,service.action_packet_filename(inbox.request_id),packet_text)
  let assert Ok(#(done,service.DispatchCycleResult(1,1)))=service.dispatch_cycle(same,now*1000)
  let assert Ok(#(_,service.DispatchCycleResult(0,0)))=service.dispatch_cycle(done,now*1000)
  let requests=fixture_requests(pid)
  let _=fixture_stop(pid)
  list.filter(requests,fn(r){let #(_,path,_,_)=r string.contains(path,"/sendMessage")})
    |> list.length |> should.equal(1)
  "service_command_dispatched_delivered_once"
}

fn recovery_dispatch_fixture(state:service.ServiceState,p:profile.Profile,root:String,now:Int) -> String {
 let assert Ok(#(pid,_,url))=fixture_start()
 let assert Ok(cfg)=service.configure_action_recovery(state.config,root,"profile.json",profile.digest(p),profile.context(p))
 let cfg=service.ServiceConfiguration(..cfg,http_config:http.default_configuration(url,"TEST_ONLY"))
 let assert Ok(#(done,service.DispatchCycleResult(1,1)))=service.dispatch_cycle(service.ServiceState(..state,config:cfg),now*1000)
 let assert Ok(#(_,service.DispatchCycleResult(0,0)))=service.dispatch_cycle(done,now*1000)
 let requests=fixture_requests(pid)
 let _=fixture_stop(pid)
 list.filter(requests,fn(r){let #(_,path,_,_)=r string.contains(path,"/sendMessage")}) |> list.length |> should.equal(1)
 "service_recovery_dispatched_delivered_once"
}

fn proposal_fixture(initial:service.ServiceState,prefix:store.CommitPrefixResult,
  inbox:ledger.InboxRecord,p:profile.Profile,bridge_expiry:Int,target_lease:Int) {
 let state=service.set_authority(service.ServiceState(..initial,expected_generation:prefix.receipt.generation),
   service.AuthorityLease("service-test",1,1,bridge_expiry / 1000))
 service.propose_cancellation(service.revoke_authority(state),p,inbox)
   |> should.be_error
 service.propose_cancellation(state,p,ledger.InboxRecord(..inbox,user_id:201))
   |> should.be_error
 service.propose_cancellation(state,p,ledger.InboxRecord(..inbox,message_id:999))
   |> should.be_error
 let assert Ok(proposed)=service.propose_cancellation(state,p,inbox)
 let c=profile.context(p)
 let expected=action.Binding(c.bot,inbox.chat_id,inbox.user_id,inbox.update_id,
   c.plan,c.task,c.worker,c.attempt,c.epoch,c.candidate,c.host,c.boot,
   action.Execution(bridge.mapping_id(profile.request(p)),"control-lease",1,profile.digest(p)))
 action.matches_binding(proposed,expected) |> should.be_true
 action.matches_target(proposed,action.Target("cancel-plan/job1","job-worker",1,target_lease)) |> should.be_true
 action.command_args(proposed) |> should.equal("cancel_job_lease cancel-plan/job1 -- Operator requested cancellation")
 let assert Ok(current)=clock.observe()
 action.valid_at(proposed,c.host,c.boot,current.sample.observed.utc_us / 1000,
   current.sample.observed.boot_us / 1000) |> should.be_true
 let assert Ok(second)=service.propose_cancellation(state,p,inbox)
 action.effect_id(proposed) |> should.equal(action.effect_id(second))
 { action.digest(proposed)==action.digest(second) } |> should.be_false
 let assert Ok(#(gen,rows))=store.read_keys(state.config.storage_config,
   [codec.inbox_key(inbox.request_id),store.cancellation_key(inbox.request_id),codec.result_key(inbox.request_id)])
 gen |> should.equal(prefix.receipt.generation)
 let assert [_,cancel,result]=rows
 cancel.exists |> should.be_false
 result.exists |> should.be_false
 "service_proposal_exact_target_no_effect"
}

fn approval_status_fixture(initial:service.ServiceState,prefix:store.CommitPrefixResult,
  inbox:ledger.InboxRecord,p:profile.Profile,root:String,bridge_expiry:Int,
  now:Int,mode:String) {
 let assert Ok(#(pid,_,url))=fixture_start()
 let assert Ok(cfg)=service.configure_actions(initial.config,root,"profile.json",
   profile.digest(p),profile.context(p),root)
 let cfg=service.ServiceConfiguration(..cfg,http_config:http.default_configuration(url,"TEST_ONLY"),
   allowed_pairs:[#(100,200),#(100,201)])
 let user=case mode { "approval_foreign" -> 201 _ -> 200 }
 let text="/approval " <> inbox.request_id
 let verdict=guard.AcceptedEnvelope(20,21,100,user,files.digest(text),text,
   guard.classify_directive(text),inbox.bot_id,None)
 let assert Ok(#(wm,v,h))=store.read_watermark(cfg.storage_config)
 let assert Ok(next)=store.commit_prefix(cfg.storage_config,inbox.bot_id,"approval-prefix",
   prefix.receipt.generation,wm,v,h,[verdict],now)
 let assert [query]=next.admitted_records
 let state=service.set_authority(service.ServiceState(..initial,config:cfg,
   expected_generation:next.receipt.generation),
   service.AuthorityLease("service-test",1,1,bridge_expiry / 1000))
 let assert Ok(#(_,service.DispatchCycleResult(1,1)))=service.dispatch_cycle(state,now*1000)
 let chunk=row(cfg.storage_config,codec.chunk_key(query.request_id,0))
 let assert Ok(raw)=codec.decode_row_value(chunk)
 let assert Ok(chunk)=codec.decode_chunk_value(raw)
 let requests=fixture_requests(pid)
 let _=fixture_stop(pid)
 list.length(requests) |> should.equal(1)
 let assert ledger.OutboxDelivered(_)=chunk.status
 case mode {
  "approval_foreign" -> {
   string.contains(chunk.payload,inbox.request_id) |> should.be_false
   chunk.payload |> should.equal("No controlled action requests found for this chat and user.")
  }
  _ -> {
   string.contains(chunk.payload,inbox.request_id) |> should.be_true
   string.contains(chunk.payload,"signed approval and execution are not confirmed") |> should.be_true
  }
 }
 row(cfg.storage_config,store.cancellation_key(inbox.request_id)).exists |> should.be_false
 let assert Ok(raw)=codec.decode_row_value(row(cfg.storage_config,codec.inbox_key(inbox.request_id)))
 let assert Ok(original)=codec.decode_inbox_record(raw)
 original.status |> should.equal(ledger.InboxPending)
 "approval_status_scoped_delivered_no_effect"
}

fn proposal_receipt(p:profile.Profile,value:proposal.Proposal,role:approval.Role,now:Int) {
 let n=approval.role_name(role)
 approval.Receipt(role,sign(n,json.object([
   #("version",json.string("uos.telegram.approval.v1")),
   #("purpose",json.string("cancel_job_lease")),#("role",json.string(n)),
   #("subject",json.string(n<>"-subject")),#("decision",json.string("approve")),
   #("intent_digest",json.string(action.digest(proposal.intent(value)))),
   #("effect_id",json.string(action.effect_id(proposal.intent(value)))),
   #("iat_ms",json.int(now)),#("nbf_ms",json.int(now)),#("exp_ms",json.int(now+15_000)),
   #("roster_digest",json.string(approval.roster_digest(profile.roster(p))))
 ]) |> json.to_string))
}
fn proposal_collect_fixture(initial:service.ServiceState,prefix:store.CommitPrefixResult,
 inbox:ledger.InboxRecord,p:profile.Profile,bridge_expiry:Int) {
 let assert Ok(actor)=service.start_store_worker(initial.config.storage_config,inbox.bot_id)
 let state=service.set_authority(service.ServiceState(..initial,
   store_worker:Some(actor.data),expected_generation:prefix.receipt.generation),
   service.AuthorityLease("service-test",1,1,bridge_expiry / 1000))
 let assert Ok(#(s1,value))=service.begin_cancellation_proposal(state,p,inbox)
 let assert Ok(#(same,again))=service.begin_cancellation_proposal(s1,p,inbox)
 same.expected_generation |> should.equal(s1.expected_generation)
 proposal.encode(again) |> should.equal(proposal.encode(value))
 let assert Ok(observed)=clock.observe()
 let now=observed.sample.observed.utc_us / 1000
 let first=proposal_receipt(p,value,approval.Codex,now)
 service.collect_cancellation_receipt(service.revoke_authority(s1),p,inbox,first)
   |> should.be_error
 service.collect_cancellation_receipt(s1,p,ledger.InboxRecord(..inbox,user_id:201),first)
   |> should.be_error
 service.collect_cancellation_receipt(s1,p,inbox,approval.Receipt(approval.Codex,first.token<>"A"))
   |> should.be_error
 let assert Ok(#(s2,v2))=service.collect_cancellation_receipt(s1,p,inbox,first)
 let assert Ok(#(replay,_))=service.collect_cancellation_receipt(s2,p,inbox,first)
 replay.expected_generation |> should.equal(s2.expected_generation)
 list.length(proposal.receipts(v2)) |> should.equal(1)
 service.execute_collected_cancellation(s2,p,inbox,1,
   files.digest(codec.encode_inbox_record(inbox))) |> should.be_error
 row(state.config.storage_config,store.cancellation_key(inbox.request_id)).exists |> should.be_false
 let assert Ok(#(s3,v3))=service.collect_cancellation_receipt(s2,p,inbox,
   proposal_receipt(p,value,approval.Agy,now))
 list.length(proposal.receipts(v3)) |> should.equal(2)
 service.execute_collected_cancellation(s3,p,inbox,1,
   files.digest(codec.encode_inbox_record(inbox))) |> should.be_error
 let assert Ok(#(s4,v4))=service.collect_cancellation_receipt(s3,p,inbox,
   proposal_receipt(p,value,approval.Operator,now))
 list.length(proposal.receipts(v4)) |> should.equal(3)
 // A fresh read from a separately invoked native worker restores the exact proposal.
 let assert Ok(raw)=codec.decode_row_value(row(state.config.storage_config,store.proposal_key(inbox.request_id)))
 let assert Ok(restored)=proposal.decode(raw)
 proposal.encode(restored) |> should.equal(proposal.encode(v4))
 let assert Ok(#(claimed,processing))=store.claim_task_processing(state.config.storage_config,
   inbox.bot_id,"proposal-claimed",s4.expected_generation,inbox,1,
   files.digest(codec.encode_inbox_record(inbox)),state.config.worker_id,1,now)
 let current=service.ServiceState(..s4,expected_generation:claimed.generation)
 let assert Ok(#(_,result))=service.execute_collected_cancellation(current,p,processing,2,
   files.digest(codec.encode_inbox_record(processing)))
 result.receipt.generation |> should.equal(claimed.generation+2)
 row(state.config.storage_config,codec.result_key(inbox.request_id)).exists |> should.be_true
 "durable_partial_receipts_quorum_executes_once"
}

fn approval_query(state:service.ServiceState,text:String,update:Int,user:Int,now:Int) {
 let c=state.config.storage_config
 let assert Ok(#(wm,v,h))=store.read_watermark(c)
 let verdict=guard.AcceptedEnvelope(update,update+1,100,user,files.digest(text),text,
   guard.classify_directive(text),state.config.bot_id,None)
 let assert Ok(prefix)=store.commit_prefix(c,state.config.bot_id,"approval-query-"<>int.to_string(update),
   state.expected_generation,wm,v,h,[verdict],now)
 let assert [query]=prefix.admitted_records
 let assert Ok(#(next,_))=service.dispatch_cycle(
   service.ServiceState(..state,expected_generation:prefix.receipt.generation),now*1000)
 let assert Ok(raw)=codec.decode_row_value(row(c,codec.chunk_key(query.request_id,0)))
 let assert Ok(chunk)=codec.decode_chunk_value(raw)
 let assert ledger.OutboxDelivered(_)=chunk.status
 #(next,chunk.payload)
}
fn proposal_flow_fixture(initial:service.ServiceState,prefix:store.CommitPrefixResult,
 inbox:ledger.InboxRecord,p:profile.Profile,root:String,bridge_expiry:Int,now:Int) {
 let assert Ok(#(pid,_,url))=fixture_start()
 let assert Ok(cfg)=service.configure_actions(initial.config,root,"profile.json",
   profile.digest(p),profile.context(p),root)
 let cfg=service.ServiceConfiguration(..cfg,http_config:http.default_configuration(url,"TEST_ONLY"),
   allowed_pairs:[#(100,200),#(100,201)])
 let bad_text="/tool cancel_job_lease foreign-plan/job1 -- invalid target"
 let bad_verdict=guard.AcceptedEnvelope(11,12,100,200,files.digest(bad_text),bad_text,
   guard.classify_directive(bad_text),inbox.bot_id,None)
 let assert Ok(#(wm,wv,wh))=store.read_watermark(cfg.storage_config)
 let assert Ok(bad_prefix)=store.commit_prefix(cfg.storage_config,inbox.bot_id,"bad-target-prefix",
   prefix.receipt.generation,wm,wv,wh,[bad_verdict],now)
 let assert [bad_inbox]=bad_prefix.admitted_records
 let state=service.set_authority(service.ServiceState(..initial,config:cfg,
   expected_generation:bad_prefix.receipt.generation),
   service.AuthorityLease("service-test",1,1,bridge_expiry / 1000))
 let #(after_bad,bad_reply)=approval_query(state,"/approval propose "<>bad_inbox.request_id,18,200,now)
 string.contains(bad_reply,"invalid") |> should.be_true
 row(cfg.storage_config,store.proposal_key(bad_inbox.request_id)).exists |> should.be_false
 row(cfg.storage_config,store.cancellation_key(bad_inbox.request_id)).exists |> should.be_false
 let plain=service.ServiceState(..after_bad,config:service.ServiceConfiguration(..cfg,actions:Some(service.RecoveryActions(p))))
 let #(plain_after,unconfigured)=approval_query(plain,"/approval propose "<>inbox.request_id,19,200,now)
 string.contains(unconfigured,"not configured") |> should.be_true
 let configured=service.ServiceState(..plain_after,config:cfg)
 let #(s1,denied)=approval_query(configured,"/approval propose "<>inbox.request_id,20,201,now)
 denied |> should.equal("No pending controlled action request found for this chat and user.")
 row(cfg.storage_config,store.proposal_key(inbox.request_id)).exists |> should.be_false
 let #(before_proposal,missing)=approval_query(s1,"/approval submit "<>inbox.request_id<>" codex invalid",21,200,now)
 string.contains(missing,"missing") |> should.be_true
 row(cfg.storage_config,store.proposal_key(inbox.request_id)).exists |> should.be_false
 let #(s2,challenge)=approval_query(before_proposal,"/approval propose "<>inbox.request_id,22,200,now)
 let assert Ok(raw)=codec.decode_row_value(row(cfg.storage_config,store.proposal_key(inbox.request_id)))
 let assert Ok(value)=proposal.decode(raw)
 string.contains(challenge,action.digest(proposal.intent(value))) |> should.be_true
 string.contains(challenge,action.canonical_json(proposal.intent(value))) |> should.be_true
 let #(s3,rejected)=approval_query(s2,"/approval submit "<>inbox.request_id<>" codex invalid",23,200,now)
 string.contains(rejected,"invalid") |> should.be_true
 row(cfg.storage_config,store.cancellation_key(inbox.request_id)).exists |> should.be_false
 let assert Ok(observed)=clock.observe()
 let stamp=observed.sample.observed.utc_us / 1000
 let r1=proposal_receipt(p,value,approval.Codex,stamp)
 let #(s4,_)=approval_query(s3,"/approval submit "<>inbox.request_id<>" codex "<>r1.token,24,200,now)
 row(cfg.storage_config,store.cancellation_key(inbox.request_id)).exists |> should.be_false
 let r2=proposal_receipt(p,value,approval.Agy,stamp)
 let #(s5,_)=approval_query(s4,"/approval submit "<>inbox.request_id<>" agy "<>r2.token,25,200,now)
 row(cfg.storage_config,store.cancellation_key(inbox.request_id)).exists |> should.be_false
 let r3=proposal_receipt(p,value,approval.Operator,stamp)
 let #(s6,_)=approval_query(s5,"/approval submit "<>inbox.request_id<>" operator "<>r3.token,26,200,now)
 let assert Ok(#(s7,_))=service.dispatch_cycle(s6,now*1000)
 let assert Ok(#(_,service.DispatchCycleResult(0,0)))=service.dispatch_cycle(s7,now*1000)
 let assert Ok(raw)=codec.decode_row_value(row(cfg.storage_config,codec.inbox_key(inbox.request_id)))
 let assert Ok(done)=codec.decode_inbox_record(raw)
 let assert ledger.InboxCompleted(_)=done.status
 let assert Ok(raw)=codec.decode_row_value(row(cfg.storage_config,codec.chunk_key(inbox.request_id,0)))
 let assert Ok(chunk)=codec.decode_chunk_value(raw)
 let assert ledger.OutboxDelivered(_)=chunk.status
 string.contains(chunk.payload,"revoked") |> should.be_true
 let requests=fixture_requests(pid)
 let _=fixture_stop(pid)
 list.length(requests) |> should.equal(10)
 "approval_commands_to_quorum_native_and_http_once"
}
