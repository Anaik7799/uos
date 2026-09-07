//// Live peer binding: caller identity is discovered, never taken from an agent label.

import argv
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import uos_swarm/herdr
import uos_swarm/session_binding as binding

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

fn scope(flags: List(String)) -> Result(herdr.Scope, String) {
  case
    list.all(flags, fn(f) {
      list.contains(["--allow-parent", "--allow-agy-runtime"], f)
    })
  {
    True ->
      Ok(herdr.Scope(
        list.contains(flags, "--allow-parent"),
        list.contains(flags, "--allow-agy-runtime"),
      ))
    False -> Error("unknown scope flag")
  }
}

fn refs(raw: String) -> List(String) {
  case raw {
    "-" -> []
    _ -> string.split(raw, ",")
  }
}

pub fn run(args: List(String)) -> Result(String, String) {
  case args {
    ["register-self", root, workspace, revision, metadata, op, ..flags] -> {
      use policy <- result.try(scope(flags))
      binding.register_self(
        root,
        workspace,
        revision,
        refs(metadata),
        op,
        policy,
      )
    }
    ["heartbeat-self", root, revision, metadata, op, ..flags] -> {
      use policy <- result.try(scope(flags))
      binding.heartbeat_self(root, revision, refs(metadata), op, policy)
    }
    ["inspect", root, pane, session, revision, ..flags] -> {
      use policy <- result.try(scope(flags))
      binding.inspect(root, herdr.Target(pane, session), policy, revision)
    }
    ["prompt-advisory", root, pane, session, revision, text, ..flags] -> {
      use policy <- result.try(scope(flags))
      binding.prompt_advisory(
        root,
        herdr.Target(pane, session),
        policy,
        revision,
        text,
      )
    }
    _ ->
      Error(
        "usage: register-self ROOT WORKSPACE REVISION REFS OP | heartbeat-self ROOT REVISION REFS OP | inspect ROOT PANE SESSION REVISION | prompt-advisory ROOT PANE SESSION REVISION TEXT; optional --allow-parent --allow-agy-runtime",
      )
  }
}

pub fn main() -> Nil {
  case run(argv.load().arguments) {
    Ok(value) -> io.println(value)
    Error(reason) -> {
      io.println(
        json.to_string(
          json.object([
            #("ok", json.bool(False)),
            #("error", json.string(reason)),
          ]),
        ),
      )
      halt(1)
    }
  }
}
