//// Wave 6r: the durable passphrase-sealed secret store used by the Telegram
//// staging service for its bot token. Laws: a put survives a fresh read from
//// disk; a wrong passphrase fails closed on the MAC before decryption; a
//// tampered byte fails closed; the file is mode 0600 and starts with the
//// magic; a short or empty passphrase and an empty secret are refused; the
//// name's slashes never become directories.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/string
import gleeunit/should
import simplifile

@external(erlang, "uos_vault_file", "put")
fn vault_put(
  store: String,
  name: String,
  secret: BitArray,
  pass_file: String,
) -> Result(Nil, Dynamic)

@external(erlang, "uos_vault_file", "get")
fn vault_get(
  store: String,
  name: String,
  pass_file: String,
) -> Result(BitArray, Dynamic)

@external(erlang, "uos_vault_file", "secret_path")
fn secret_path(store: String, name: String) -> String

@external(erlang, "uos_vault_file", "exists")
fn exists(store: String, name: String) -> Bool

@external(erlang, "erlang", "unique_integer")
fn unique_integer() -> Int

fn fresh_store() -> #(String, String) {
  let root =
    "/tmp/uos-vault-file-test-"
    <> int.to_string(int.absolute_value(unique_integer()))
  let assert Ok(_) = simplifile.create_directory_all(root)
  let pass = root <> "/passphrase"
  let assert Ok(_) = simplifile.write(pass, "correct horse battery staple\n")
  #(root <> "/store", pass)
}

const name = "telegram/staging/bot_token"

pub fn put_then_get_round_trips_from_disk_test() {
  let #(store, pass) = fresh_store()
  let secret = <<"123456:ABC-sentinel-token-bytes":utf8>>
  vault_put(store, name, secret, pass) |> should.be_ok
  exists(store, name) |> should.be_true
  vault_get(store, name, pass) |> should.equal(Ok(secret))
  // The file is the only durable copy and it is not plaintext.
  let path = secret_path(store, name)
  let assert Ok(bytes) = simplifile.read_bits(path)
  bit_array.slice(bytes, 0, 5) |> should.equal(Ok(<<"UOSV1":utf8>>))
  let assert Ok(text) =
    simplifile.read(path)
    |> fn(r) {
      case r {
        Ok(t) -> Ok(t)
        Error(_) -> Ok("")
      }
    }
  string.contains(text, "sentinel") |> should.be_false
  let assert Ok(info) = simplifile.file_info(path)
  { info.mode % 0o1000 } |> should.equal(0o600)
  // No directory was created from the name's slashes.
  string.contains(path, "/telegram/") |> should.be_false
}

pub fn wrong_passphrase_fails_closed_on_the_mac_test() {
  let #(store, pass) = fresh_store()
  vault_put(store, name, <<"secret-one":utf8>>, pass) |> should.be_ok
  let wrong = store <> "-wrong-pass"
  let assert Ok(_) = simplifile.write(wrong, "a different long passphrase\n")
  case vault_get(store, name, wrong) {
    Error(reason) ->
      string.contains(string.lowercase(string.inspect(reason)), "mac")
      |> should.be_true
    Ok(_) -> should.fail()
  }
}

pub fn tampered_byte_fails_closed_test() {
  let #(store, pass) = fresh_store()
  vault_put(store, name, <<"secret-two":utf8>>, pass) |> should.be_ok
  let path = secret_path(store, name)
  let assert Ok(bytes) = simplifile.read_bits(path)
  let size = bit_array.byte_size(bytes)
  let assert Ok(head) = bit_array.slice(bytes, 0, size - 1)
  let assert Ok(last) = bit_array.slice(bytes, size - 1, 1)
  let flipped = case last {
    <<b>> -> {
      let v = { b + 1 } % 256
      <<v>>
    }
    _ -> <<0>>
  }
  let assert Ok(_) =
    simplifile.write_bits(path, bit_array.append(head, flipped))
  case vault_get(store, name, pass) {
    Error(reason) ->
      string.contains(string.lowercase(string.inspect(reason)), "mac")
      |> should.be_true
    Ok(_) -> should.fail()
  }
}

pub fn empty_or_short_inputs_are_refused_test() {
  let #(store, pass) = fresh_store()
  vault_put(store, name, <<>>, pass) |> should.be_error
  let short = store <> "-short"
  let assert Ok(_) = simplifile.write(short, "short\n")
  vault_put(store, name, <<"x":utf8>>, short) |> should.be_error
  vault_get(store, "telegram/staging/missing", pass) |> should.be_error
}
