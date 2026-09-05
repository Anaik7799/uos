// STAMP: SC-PLAN-003
// AOR: AOR-PLAN-003
// Criticality: Level 1 (CRITICAL) - Foundation
//
// This module provides supplementary helper functions for the built-in `gleam/result`
// module, following Railway-Oriented Programming patterns. These functions are
// ported from the F# CEPAF codebase.

import gleam/list
import gleam/result

// the first `Error` is returned.
/// Applies a function of two arguments over two Results. If both are `Ok`,
/// applies the function to the unwrapped values. If either is an `Error`,
pub fn lift2(
  fun: fn(a, b) -> c,
  res_a: Result(a, e),
  res_b: Result(b, e),
) -> Result(c, e) {
  case res_a {
    Ok(val_a) -> result.map(res_b, fn(val_b) { fun(val_a, val_b) })
    Error(e) -> Error(e)
  }
}

/// Applies a function of three arguments over three Results.
pub fn lift3(
  fun: fn(a, b, c) -> d,
  res_a: Result(a, e),
  res_b: Result(b, e),
  res_c: Result(c, e),
) -> Result(d, e) {
  res_a
  |> result.try(fn(a) {
    res_b
    |> result.try(fn(b) {
      res_c
      |> result.map(fn(c) { fun(a, b, c) })
    })
  })
}

/// Maps a function that returns a Result over a list of items, and returns
/// a single Result with a list of all successful values, or the first error.
pub fn traverse(
  over list: List(a),
  with fun: fn(a) -> Result(b, e),
) -> Result(List(b), e) {
  list
  |> list.map(fun)
  |> result.all()
}

/// Partitions a list of Results into a tuple of two lists:
/// one for `Ok` values and one for `Error` values.
pub fn partition(results: List(Result(a, e))) -> #(List(a), List(e)) {
  let initial = #([], [])
  list.fold(results, initial, fn(acc, r) {
    let #(oks, errs) = acc
    case r {
      Ok(x) -> #(list.append(oks, [x]), errs)
      Error(e) -> #(oks, list.append(errs, [e]))
    }
  })
}

/// Unwraps a Result, returning the `Ok` value or computing a default
/// value from the `Error` value.
pub fn default_with(result: Result(a, e), defaulter: fn(e) -> a) -> a {
  case result {
    Ok(value) -> value
    Error(e) -> defaulter(e)
  }
}

/// Executes a side-effecting function with the success value if the Result is `Ok`.
pub fn iter(result: Result(a, e), for fun: fn(a) -> Nil) -> Nil {
  case result {
    Ok(value) -> fun(value)
    Error(_) -> Nil
  }
}

/// Executes a side-effecting function with the error value if the Result is `Error`.
pub fn iter_error(result: Result(a, e), for fun: fn(e) -> Nil) -> Nil {
  case result {
    Ok(_) -> Nil
    Error(e) -> fun(e)
  }
}

/// Executes a side-effecting function with the success value if the Result is `Ok`,
/// then returns the original Result. Useful for debugging.
pub fn tap(result: Result(a, e), for fun: fn(a) -> Nil) -> Result(a, e) {
  case result {
    Ok(value) -> {
      fun(value)
      Ok(value)
    }
    Error(e) -> Error(e)
  }
}

/// Returns `Ok(Nil)` if the condition is true, otherwise returns the given error.
pub fn require(condition: Bool, if_false error: e) -> Result(Nil, e) {
  case condition {
    True -> Ok(Nil)
    False -> Error(error)
  }
}

/// Maps the `Ok` value of a Result to `Nil`, preserving the `Error` value.
pub fn ignore_ok(result: Result(a, e)) -> Result(Nil, e) {
  result.map(result, fn(_) { Nil })
}
