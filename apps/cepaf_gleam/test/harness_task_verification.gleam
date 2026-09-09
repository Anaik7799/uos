//// Executes only the finite test module manifest supplied by the harness.
import gleam/erlang/atom
import gleam/io
import gleam/list
import gleam/string
@external(erlang, "cepaf_gleam_ffi", "get_arguments")
fn get_arguments() -> List(String)
type Option { Verbose }
@external(erlang, "eunit", "test")
fn eunit(modules: List(atom.Atom), options: List(Option)) -> atom.Atom
@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil
pub fn main() {
  let modules = get_arguments()
  let valid = modules != [] && list.length(modules) <= 32
    && list.all(modules, fn(name) { string.ends_with(name, "_test")
      && string.byte_size(name) <= 120 && list.all(string.to_graphemes(name), fn(c) {
        string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", c)
      }) })
  case valid {
    False -> { io.println_error("invalid finite test manifest") halt(1) }
    True -> {
      let outcome = eunit(list.map(modules, atom.create), [Verbose]) |> atom.to_string
      io.println("successor verification: " <> outcome)
      case outcome { "ok" -> Nil _ -> halt(1) }
    }
  }
}
