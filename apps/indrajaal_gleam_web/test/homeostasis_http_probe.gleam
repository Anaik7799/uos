//// Private, read-only HTTP fixture. It never invokes the UOS root supervisor.
import gleam/erlang/process
import indrajaal/homeostasis_http
import mist

pub fn serve(port: Int) -> Nil {
  let assert True = port >= 49152 && port <= 65535
  let assert Ok(_) = mist.new(homeostasis_http.handle)
    |> mist.bind("127.0.0.1")
    |> mist.port(port)
    |> mist.start()
  process.sleep(600_000)
}
