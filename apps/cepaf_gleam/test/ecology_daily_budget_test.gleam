import cepaf_gleam/ecology/daily_budget as budget
import gleam/list
import gleam/string
import gleeunit/should

fn input(bytes: Int) {
  string.repeat("a", bytes)
}

fn admitted() {
  let assert Ok(r) =
    budget.admit(
      "paid:1",
      "moonshotai/kimi-k3",
      4096,
      input(16_384),
      input(20_000),
      budget.Price(3000, 15_000, 0),
    )
  r
}

pub fn worst_provider_and_maximum_request_fit_fixed_reservation_test() {
  budget.worst_case_nanodollars(admitted()) |> should.equal(116_736_000)
  budget.daily_limit_nanodollars / budget.reservation_nanodollars
  |> should.equal(40)
  budget.validate_usage(admitted(), 18_432, 4096, 250_000_000)
  |> should.equal(Ok(Nil))
}

pub fn provider_ceilings_are_exact_and_free_route_is_separate_test() {
  budget.provider_ceiling("deepseek/deepseek-v4-pro-0813")
  |> should.equal(Ok(budget.Price(1320, 3960, 0)))
  budget.provider_ceiling("deepseek/deepseek-v4-flash-0731")
  |> should.equal(Ok(budget.Price(65, 180, 0)))
  budget.provider_ceiling("google/gemma-4-31b-it")
  |> should.equal(Ok(budget.Price(90, 340, 0)))
  budget.provider_ceiling("google/gemma-4-26b-a4b-it")
  |> should.equal(Ok(budget.Price(90, 340, 0)))
  budget.provider_ceiling("inclusionai/ling-3.0-flash-fin:free")
  |> should.be_error
  budget.provider_ceiling("unknown") |> should.be_error
}

pub fn live_price_must_be_nonnegative_within_provider_ceiling_and_no_fee_test() {
  list.each(
    [
      budget.Price(-1, 1, 0),
      budget.Price(1401, 1, 0),
      budget.Price(1, 4401, 0),
      budget.Price(1, -1, 0),
      budget.Price(1, 1, 1),
      budget.Price(1, 1, -1),
    ],
    fn(p) {
      budget.admit("p", "z-ai/glm-5.3", 512, "input", "serialized input", p)
      |> should.be_error
    },
  )
  let assert Ok(r) =
    budget.admit(
      "p",
      "z-ai/glm-5.3",
      512,
      "input",
      "serialized input",
      budget.Price(0, 0, 0),
    )
  // Bound uses the configured ceiling, even when a live quote is cheaper.
  budget.worst_case_nanodollars(r) |> should.equal(5_127_000)
}

pub fn byte_count_is_utf8_and_caller_cannot_assert_smaller_size_test() {
  let assert Ok(r) =
    budget.admit("utf8", "z-ai/glm-5.3", 1, "é", "{é}", budget.Price(1, 1, 0))
  string.contains(budget.ledger_request_json(r), "\"input_bytes\":2")
  |> should.be_true
  string.contains(budget.ledger_request_json(r), "\"body_bytes\":4")
  |> should.be_true
  budget.admit(
    "utf8",
    "z-ai/glm-5.3",
    1,
    string.repeat("é", 524_289),
    input(1_050_000),
    budget.Price(1, 1, 0),
  )
  |> should.be_error
}

pub fn invalid_identity_token_and_body_bounds_reject_test() {
  list.each(["", "bad/id", "a b", "é", input(129)], fn(id) {
    budget.admit(id, "z-ai/glm-5.3", 1, "", "x", budget.Price(1, 1, 0))
    |> should.be_error
  })
  list.each([-1, 0, 4097], fn(tokens) {
    budget.admit(
      "valid",
      "z-ai/glm-5.3",
      tokens,
      "",
      "x",
      budget.Price(1, 1, 0),
    )
    |> should.be_error
  })
  list.each(["", "x", input(4_194_305)], fn(body) {
    budget.admit("valid", "z-ai/glm-5.3", 1, "xx", body, budget.Price(1, 1, 0))
    |> should.be_error
  })
  budget.admit(
    input(128),
    "z-ai/glm-5.3",
    1,
    "",
    input(65_536),
    budget.Price(1, 1, 0),
  )
  |> should.be_ok
}

pub fn usage_outside_original_admission_rejects_without_refund_test() {
  list.each(
    [
      #(-1, 1, 1),
      #(18_433, 1, 1),
      #(1, -1, 1),
      #(1, 4097, 1),
      #(1, 1, -1),
      #(1, 1, 250_000_001),
    ],
    fn(usage) {
      budget.validate_usage(admitted(), usage.0, usage.1, usage.2)
      |> should.be_error
    },
  )
  let assert Ok(small) =
    budget.admit(
      "small",
      "google/gemma-4-31b-it",
      1,
      "",
      "{}",
      budget.Price(90, 340, 0),
    )
  budget.validate_usage(small, 2049, 1, 1) |> should.be_error
  budget.validate_usage(small, 2048, 2, 1) |> should.be_error
}
