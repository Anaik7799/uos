import gleam/list
import gleeunit/should
import prng
import uos_swarm/clock_contract as clock

fn reading() -> clock.Reading {
  clock.Reading(clock.Domain("nas-1", "boot-a"), 1_000_000_000, 10_000_000)
}

fn evidence() -> clock.Evidence {
  clock.Evidence(reading(), "test:chrony-receipt", True, 215, 934, 50)
}

pub fn measured_fresh_clock_passes_test() {
  clock.validate(evidence(), reading(), clock.strict_policy)
  |> should.equal(Ok(Nil))
  clock.checked_tick(50, evidence(), reading(), clock.strict_policy)
  |> should.equal(Ok(51))
}

pub fn reboot_and_regression_never_alias_test() {
  let r = reading()
  clock.validate(
    evidence(),
    clock.Reading(..r, domain: clock.Domain("nas-1", "boot-b")),
    clock.strict_policy,
  )
  |> should.equal(Error(clock.ClockDomainChanged))
  clock.validate(
    evidence(),
    clock.Reading(..r, utc_us: r.utc_us - 1),
    clock.strict_policy,
  )
  |> should.equal(Error(clock.PhysicalTimeRegressed))
  clock.validate(
    evidence(),
    clock.Reading(..r, boot_us: r.boot_us - 1),
    clock.strict_policy,
  )
  |> should.equal(Error(clock.FutureEvidence))
}

pub fn stale_unsynchronized_or_missing_receipt_fails_test() {
  let e = evidence()
  let r = reading()
  let age = 120_000_001
  clock.validate(
    e,
    clock.Reading(..r, utc_us: r.utc_us + age, boot_us: r.boot_us + age),
    clock.strict_policy,
  )
  |> should.equal(Error(clock.StaleEvidence))
  clock.validate(
    clock.Evidence(..e, synchronized: False),
    r,
    clock.strict_policy,
  )
  |> should.equal(Error(clock.Unsynchronized))
  clock.validate(clock.Evidence(..e, source_ref: ""), r, clock.strict_policy)
  |> should.equal(Error(clock.MissingEvidence))
}

pub fn skew_steps_and_future_messages_fail_test() {
  let e = evidence()
  let r = reading()
  clock.validate(
    clock.Evidence(..e, offset_us: -2_000_001),
    r,
    clock.strict_policy,
  )
  |> should.equal(Error(clock.ExcessiveOffset))
  clock.validate(
    clock.Evidence(..e, uncertainty_us: 500_001),
    r,
    clock.strict_policy,
  )
  |> should.equal(Error(clock.ExcessiveUncertainty))
  clock.continuity(
    r,
    clock.Reading(..r, utc_us: r.utc_us + 2_000_001),
    clock.strict_policy,
  )
  |> should.equal(Error(clock.PhysicalMonotonicDivergence))
  clock.event_time(r.utc_us + 935, r, e, clock.strict_policy)
  |> should.equal(Error(clock.FutureEvent))
}

pub fn lamport_restart_overflow_and_causal_controls_test() {
  clock.checked_tick(49, evidence(), reading(), clock.strict_policy)
  |> should.equal(Error(clock.CounterBelowDurableFloor))
  clock.tick(clock.max_counter) |> should.equal(Error(clock.CounterExhausted))
  clock.receive(-1, 2) |> should.equal(Error(clock.InvalidCounter))
  clock.causal_edge(3, 3) |> should.equal(Error(clock.CausalOrderViolation))
  clock.causal_edge(3, 4) |> should.equal(Ok(Nil))
}

// Independent initial interpretation: N local events and one receive expand
// into a list of known causal counters; the efficient implementation uses max.
pub fn generated_lamport_observation_laws_test() {
  prng.range(0, 120)
  |> list.each(fn(seed) {
    let local = { seed * 7919 } % 1000
    let remote = { seed * 104_729 } % 1000
    let oracle =
      list.fold([local, remote], 0, fn(acc, n) {
        case n >= acc {
          True -> n + 1
          False -> acc
        }
      })
    clock.receive(local, remote) |> should.equal(Ok(oracle))
    clock.receive(remote, local) |> should.equal(clock.receive(local, remote))
    let assert Ok(next) = clock.receive(local, remote)
    { next > local && next > remote } |> should.be_true
  })
}
