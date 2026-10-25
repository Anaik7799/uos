import cepaf_gleam/harness/telegram_conversation_model as adapter
import telegram_conversation_store_test as fixture
import gleam/erlang/process
import gleam/option.{None, Some}
import gleeunit/should
import uos_swarm/openrouter_worker as model

const prices = "{\"data\":[{\"id\":\"openrouter/free\",\"pricing\":{\"prompt\":\"0\",\"completion\":\"0\"}}]}"
const reply = "{\"model\":\"fixture/free\",\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":\"Hello there\"}}],\"usage\":{\"prompt_tokens\":20,\"completion_tokens\":4,\"total_tokens\":24,\"cost\":0}}"

fn io() -> model.Io {
  model.Io(
    credential: fn() { Some("fixture") },
    fetch_prices: fn(t) { assert t <= 1000 Ok(#(200,prices)) },
    post: fn(_,_,t) { assert t <= 1000 Ok(#(200,reply)) },
    now_ms: fn() { 1000 },
  )
}
fn allowed() { Ok(1000) }

pub fn reserved_success_returns_validated_text_test() {
  use r <- fixture.with_reserved_for_model_test()
  adapter.run(r,io(),allowed,1000) |> should.equal(Ok(adapter.Execution("Hello there")))
}

pub fn denied_authority_never_fetches_or_posts_test() {
  use r <- fixture.with_reserved_for_model_test()
  let no_network = model.Io(..io(),
    fetch_prices: fn(_) { panic as "unauthorized GET" },
    post: fn(_,_,_) { panic as "unauthorized POST" },
  )
  adapter.run(r,no_network,fn() { Error("private authority detail") },1000)
    |> should.equal(Error("conversation_authority_refused"))
}

pub fn missing_credential_never_fetches_test() {
  use r <- fixture.with_reserved_for_model_test()
  let absent = model.Io(..io(), credential: fn() { None },
    fetch_prices: fn(_) { panic as "GET despite absent credential" })
  adapter.run(r,absent,allowed,1000) |> should.equal(Error("conversation_model_request_failed"))
}

pub fn transport_error_does_not_disclose_body_test() {
  use r <- fixture.with_reserved_for_model_test()
  let failed = model.Io(..io(), post: fn(_,_,_) { Error("PRIVATE provider and key details") })
  adapter.run(r,failed,allowed,1000) |> should.equal(Error("conversation_model_request_failed"))
}

pub fn changed_authority_after_prices_prevents_post_test() {
  use r <- fixture.with_reserved_for_model_test()
  let changed = process.new_subject()
  let altered = model.Io(..io(),
    fetch_prices: fn(_) { process.send(changed,Nil) Ok(#(200,prices)) },
    post: fn(_,_,_) { panic as "POST after revoked authority" })
  let authorize = fn() {
    case process.receive(changed,0) {
      Ok(_) -> Error("revoked")
      Error(_) -> Ok(1000)
    }
  }
  adapter.run(r,altered,authorize,1000) |> should.equal(Error("conversation_model_request_failed"))
}

pub fn deadline_after_prices_prevents_post_test() {
  use r <- fixture.with_reserved_for_model_test()
  let elapsed = process.new_subject()
  let late = model.Io(..io(),
    fetch_prices: fn(_) { process.send(elapsed,Nil) Ok(#(200,prices)) },
    now_ms: fn() { case process.receive(elapsed,0) { Ok(_) -> 2000 Error(_) -> 1000 } },
    post: fn(_,_,_) { panic as "POST after deadline" })
  adapter.run(r,late,allowed,1000) |> should.equal(Error("conversation_model_request_failed"))
}

pub fn backwards_clock_after_prices_prevents_post_test() {
  use r <- fixture.with_reserved_for_model_test()
  let backwards = process.new_subject()
  let skew = model.Io(..io(),
    fetch_prices: fn(_) { process.send(backwards,Nil) Ok(#(200,prices)) },
    now_ms: fn() { case process.receive(backwards,0) { Ok(_) -> 999 Error(_) -> 1000 } },
    post: fn(_,_,_) { panic as "POST after backwards clock" })
  adapter.run(r,skew,allowed,1000) |> should.equal(Error("conversation_model_request_failed"))
}

pub fn paid_price_refuses_before_post_test() {
  use r <- fixture.with_reserved_for_model_test()
  let paid = model.Io(..io(),
    fetch_prices: fn(_) { Ok(#(200,"{\"data\":[{\"id\":\"openrouter/free\",\"pricing\":{\"prompt\":\"0.1\",\"completion\":\"0.1\"}}]}")) },
    post: fn(_,_,_) { panic as "paid POST" })
  adapter.run(r,paid,allowed,1000) |> should.equal(Error("conversation_model_request_failed"))
}
