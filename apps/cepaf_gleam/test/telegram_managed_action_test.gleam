//// Test-only managed restart fixture. No live recipient or production keys.
import cepaf_gleam/harness/clock
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_action_profile as profile
import cepaf_gleam/harness/telegram_action_proposal as proposal
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_service as service
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleeunit/should
import telegram_action_service_test as signed

const native_guardian = "/home/an/NAS-setup/uos/var/recovery-runtime/20261024-2217-action-proposal/transport/guardian.exe"
const native_guardian_sha = "bd418aa04b1a591256ef47f2abf48529a548f077d3fedf59075d4b894c28d11d"
const native_worker = "/home/an/NAS-setup/uos/var/recovery-runtime/20261024-2217-action-proposal/transport/worker.exe"
const native_worker_sha = "b800eff783cf78a643f39f3445f73a8068cae5ed4bd7047c272070cfabc1fdc0"

fn context(bot,host,boot) {
 profile.Context(bot,"plan-e2e","lease-e2e-01","worker-e2e-01",1,1,1,
   native_worker_sha,"nas-1.tail55d152.ts.net",boot,host)
}

pub fn seed_pending(c,db,root,bot) {
 let assert Ok(o)=clock.observe()
 let now=o.sample.observed.utc_us / 1000
 let boot=o.sample.observed.boot_us / 1000
 let assert True=boot>180_000
 let ctx=context(bot,o.sample.observed.domain.host_id,o.sample.observed.domain.boot_id)
 let raw=signed.profile_raw(ctx,"managed-expired-mapping",now*1_000_000-1,
   native_guardian,native_guardian_sha,native_worker,native_worker_sha,db,now-180_000)
 let sha=files.digest(raw)
 let assert Ok(p)=profile.persist(root,"historical-profile.json",raw,sha,ctx)
 profile.active_at(p,ctx,now*1_000_000) |> should.be_false
 let text="/tool cancel_job_lease plan-e2e/job1 -- Withdraw after restart"
 let id=ledger.make_request_id(bot,9000)
 let verdict=guard.AcceptedEnvelope(9000,9001,100,200,files.digest(text),text,
   guard.classify_directive(text),bot,None)
 let assert Ok(#(gen,_))=store.read_keys(c,[codec.watermark_key()])
 let assert Ok(#(wm,wv,wh))=store.read_watermark(c)
 let assert Ok(prefix)=store.commit_prefix(c,bot,"managed-expired-prefix",gen,wm,wv,wh,[verdict],now)
 let assert [inbox]=prefix.admitted_records
 let binding=action.Binding(bot,100,200,9000,ctx.plan,ctx.task,ctx.worker,1,1,
   ctx.candidate,ctx.host,ctx.boot,action.Execution("managed-expired-mapping","control-lease",1,sha))
 let target=action.Target("plan-e2e/job1","job-worker",1,{now+30_000}*1_000_000)
 let assert Ok(intent)=action.new(binding,target,
   action.Window(now-120_000,boot-120_000,now-60_000,boot-60_000),
   "Withdraw after restart",string.repeat("b",64))
 let assert Ok(value)=proposal.new(id,intent,approval.roster_digest(profile.roster(p)))
 let assert Ok(generation)=store.save_proposal(c,prefix.receipt.generation,inbox,value)
 let receipts=list.map([approval.Codex,approval.Agy,approval.Operator],
   fn(role){signed.proposal_receipt(p,value,role,now-120_000)})
 approval.verify(profile.roster(p),intent,ctx.host,ctx.boot,now-120_000,boot-120_000,receipts)
   |> should.be_ok
 approval.verify(profile.roster(p),intent,ctx.host,ctx.boot,now,boot,receipts)
   |> should.be_error
 let assert Ok(signed_value)=proposal.with_receipts(value,receipts)
 let assert Ok(_)=store.save_proposal(c,generation,inbox,signed_value)
 #(sha,id,proposal.encode(signed_value),raw)
}

// Only the fixture runner calls this; production configuration remains typed.
pub fn configure(config:service.ServiceConfiguration,root:String,sha:String)
  -> Result(service.ServiceConfiguration,String) {
 use o <- result.try(clock.observe())
 let ctx=context(config.bot_id,o.sample.observed.domain.host_id,o.sample.observed.domain.boot_id)
 service.configure_action_recovery(config,root,"historical-profile.json",sha,ctx)
}
