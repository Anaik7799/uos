import cepaf_gleam/fpp/interp as i
import cepaf_gleam/fpp/release_lifecycle as r
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleeunit/should

const candidate = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const digest = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pub fn print_model_table() {
  let names = list.append(r.stages, ["completed"])
  list.each(list.index_map(names, fn(_, n) { n }), fn(current) {
    list.each(list.index_map(names, fn(s, n) { #(s, n) }), fn(pair) {
      let #(name, incoming) = pair
      list.each([0, 1], fn(valid) {
        let actual =
          r.advance(
            at_stage(current),
            r.Receipt(..receipt(name), passed: valid == 1),
            150,
          )
        let next = case actual {
          Ok(_) -> current + 1
          Error(_) -> -1
        }
        io.println(
          int.to_string(current)
          <> " "
          <> int.to_string(incoming)
          <> " "
          <> int.to_string(valid)
          <> " "
          <> int.to_string(next),
        )
      })
    })
  })
}

fn receipt(stage: String) -> r.Receipt {
  r.Receipt(candidate, stage, True, 100, 200, digest)
}

fn at_stage(index: Int) -> r.Release {
  let assert Ok(start) = r.new(candidate)
  list.fold(list.take(r.stages, index), start, fn(s, stage) {
    let assert Ok(next) = r.advance(s, receipt(stage), 150)
    next
  })
}

pub fn declarative_intent_has_the_same_observation_as_direct_interpreter_test() {
  list.each(list.index_map(r.stages, fn(s, n) { #(s, n) }), fn(pair) {
    let #(stage, index) = pair
    let run = at_stage(index)
    r.interpret(run, r.SubmitEvidence(receipt(stage)), 150)
    |> result.map(r.phase)
    |> should.equal(r.advance(run, receipt(stage), 150) |> result.map(r.phase))
    r.interpret(run, r.ReportFault, 150)
    |> result.map(r.phase)
    |> should.equal(r.fault(run) |> result.map(r.phase))
  })
  let assert Ok(recovering) = r.fault(at_stage(8))
  r.interpret(recovering, r.ReportRestoration(receipt("recover")), 150)
  |> result.map(r.phase)
  |> should.equal(Ok("rolled_back"))
}

pub fn every_transition_matches_prefix_oracle_test() {
  // Independent oracle: a valid receipt increments the completed-prefix index.
  list.each(list.index_map(r.stages, fn(s, n) { #(s, n) }), fn(pair) {
    let #(stage, index) = pair
    let current = at_stage(index)
    list.each(r.stages, fn(incoming) {
      let actual = r.advance(current, receipt(incoming), 150)
      case incoming == stage {
        True ->
          actual
          |> result.map(r.phase)
          |> should.equal(Ok(
            list.drop(r.stages, index + 1)
            |> list.first
            |> result.unwrap("completed"),
          ))
        False -> {
          let _ = actual |> should.be_error()
          Nil
        }
      }
    })
  })
}

pub fn every_stage_rejects_invalid_evidence_test() {
  list.each(list.index_map(r.stages, fn(s, n) { #(s, n) }), fn(pair) {
    let #(stage, index) = pair
    let s = at_stage(index)
    let good = receipt(stage)
    list.each(
      [
        r.Receipt(..good, passed: False),
        r.Receipt(..good, candidate: "foreign"),
        r.Receipt(..good, digest: "missing"),
        r.Receipt(..good, observed_ms: 151),
        r.Receipt(..good, expires_ms: 149),
        r.Receipt(..good, expires_ms: 3_600_101),
      ],
      fn(bad) { r.advance(s, bad, 150) |> should.be_error() },
    )
  })
}

pub fn guards_are_closed_in_the_underlying_fprime_interpreter_test() {
  let assert Ok(s) = i.init_machine(r.machine())
  let assert Ok(next) = i.dispatch_signal(r.machine(), [], s, "pass:intake")
  next.current |> should.equal("intake")
  let assert Ok(denied) =
    i.dispatch_signal(
      r.machine(),
      [#("evidence_valid", False)],
      s,
      "pass:intake",
    )
  denied.current |> should.equal("intake")
}

pub fn all_stages_route_faults_to_a_safe_state_test() {
  list.each(list.index_map(r.stages, fn(s, n) { #(s, n) }), fn(pair) {
    let #(stage, index) = pair
    let assert Ok(stopped) = r.fault(at_stage(index))
    r.phase(stopped)
    |> should.equal(case stage == "deploy" || stage == "observe" {
      True -> "recovering"
      False -> "held"
    })
    r.advance(stopped, receipt(stage), 150) |> should.be_error()
  })
}

pub fn rollback_requires_fresh_evidence_and_is_terminal_test() {
  let assert Ok(recovering) = r.fault(at_stage(8))
  r.restored(recovering, r.Receipt(..receipt("recover"), passed: False), 150)
  |> should.be_error()
  let assert Ok(rolled_back) = r.restored(recovering, receipt("recover"), 150)
  r.phase(rolled_back) |> should.equal("rolled_back")
  r.advance(rolled_back, receipt("close"), 150) |> should.be_error()
}

pub fn replay_is_deterministic_and_chunkable_test() {
  let assert Ok(start) = r.new(candidate)
  let fold = fn(state, seq) {
    list.fold(seq, state, fn(s, name) {
      let assert Ok(next) = r.advance(s, receipt(name), 150)
      next
    })
  }
  let all = fold(start, r.stages)
  r.phase(all) |> should.equal("completed")
  list.each(list.index_map(r.stages, fn(_, n) { n }), fn(n) {
    let partial = fold(start, list.take(r.stages, n))
    fold(partial, list.drop(r.stages, n))
    |> r.phase
    |> should.equal(r.phase(all))
  })
  r.advance(all, receipt("close"), 150) |> should.be_error()
}
