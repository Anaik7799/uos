//// Private HTTP harness for the same typed music handler used by Indrajaal.
//// Requires explicit UOS_MUSIC_ROOT and UOS_MUSIC_TEST_PORT; no ecology/runtime start.

import gleam/bytes_tree
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist.{type Charlist}
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/int
import gleam/io
import indrajaal/music_files as music
import mist

@external(erlang, "application", "ensure_all_started")
fn start_application(name: Atom) -> Result(List(Atom), Dynamic)

@external(erlang, "os", "getenv")
fn getenv(name: Charlist, default: Charlist) -> Charlist

pub fn main() {
  let assert Ok(_) = music.configured_root()
  let assert Ok(port) =
    getenv(
      charlist.from_string("UOS_MUSIC_TEST_PORT"),
      charlist.from_string(""),
    )
    |> charlist.to_string
    |> int.parse
  let assert True = port >= 1024 && port <= 65_535
  let assert Ok(_) = start_application(atom.create("mist"))
  let handler = fn(req: Request(mist.Connection)) {
    let reply = case music.handles(req.path) {
      True -> music.handle(music.configured_root(), req.method, req.path)
      False ->
        response.new(404) |> response.set_body(<<"No private harness route">>)
    }
    response.set_body(reply, mist.Bytes(bytes_tree.from_bit_array(reply.body)))
  }
  let assert Ok(_) =
    mist.new(handler) |> mist.port(port) |> mist.bind("127.0.0.1") |> mist.start
  io.println("EV86_PRIVATE_HTTP_READY " <> int.to_string(port))
  process.sleep(60_000)
}
