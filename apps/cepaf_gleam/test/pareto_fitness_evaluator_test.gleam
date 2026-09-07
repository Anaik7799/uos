import cepaf_gleam/ha/pareto_fitness_evaluator.{
  default_evolution_candidates, default_weights, dominates, evaluate_candidate,
  get_pareto_optimal_set, normalize_error_rate, normalize_latency,
  normalize_resource, normalize_throughput,
}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn normalization_bounds_test() {
  // Latency
  normalize_latency(10.0) |> should.equal(1.0)
  normalize_latency(600.0) |> should.equal(0.0)

  // Throughput
  normalize_throughput(50.0) |> should.equal(0.0)
  normalize_throughput(12_000.0) |> should.equal(1.0)

  // Error rate
  normalize_error_rate(0.005) |> should.equal(1.0)
  normalize_error_rate(6.0) |> should.equal(0.0)

  // Resource
  normalize_resource(20.0) |> should.equal(1.0)
  normalize_resource(98.0) |> should.equal(0.0)
}

pub fn pareto_dominance_test() {
  let w = default_weights()
  // c_superior has better latency, throughput, error, and resource than c_inferior
  let c_superior =
    evaluate_candidate("c-sup", "Superior", 20.0, 9000.0, 0.01, 35.0, w)
  let c_inferior =
    evaluate_candidate("c-inf", "Inferior", 200.0, 2000.0, 1.0, 80.0, w)

  dominates(c_superior, c_inferior) |> should.equal(True)
  dominates(c_inferior, c_superior) |> should.equal(False)
}

pub fn pareto_frontier_computation_test() {
  let candidates = default_evolution_candidates()
  list.length(candidates) |> should.equal(4)

  let optimal = get_pareto_optimal_set(candidates)
  // At least the top 3 specialized candidates should be non-dominated
  { list.length(optimal) >= 3 } |> should.equal(True)

  // The suboptimal candidate should be dominated
  let assert Ok(suboptimal) =
    list.find(candidates, fn(c) { c.candidate_id == "cand-04-suboptimal" })
  suboptimal.is_pareto_optimal |> should.equal(False)
}
