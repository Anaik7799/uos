import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit/should
import ocaml_counterparts/native
import simplifile

pub fn main() {
  let reply = native.request("vectors", json.object([])) |> should.be_ok
  let decoder = {
    use inputs <- decode.field("inputs", decode.list(decode.string))
    use required <- decode.field("required", decode.bool)
    decode.success(
      json.object([
        #("inputs", json.array(inputs, json.string)),
        #("required", json.bool(required)),
      ]),
    )
  }
  let vectors =
    decode.run(
      reply,
      decode.field("vectors", decode.list(decoder), decode.success),
    )
    |> should.be_ok
  list.length(vectors) |> should.equal(2000)
  simplifile.create_directory_all("fixtures") |> should.be_ok
  simplifile.write(
    "fixtures/20260905-2209-parity-random-vectors.json",
    json.array(vectors, fn(v) { v }) |> json.to_string,
  )
  |> should.be_ok
}
