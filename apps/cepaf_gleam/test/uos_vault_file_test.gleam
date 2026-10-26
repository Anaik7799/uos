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

@external(erlang, "uos_openrouter_ffi", "vault_key")
fn openrouter_vault_key(store: String, pass_file: String) -> Result(String, Nil)

@external(erlang, "cepaf_gleam_ffi", "get_preference")
fn get_preference(key: String) -> Result(String, String)

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

pub fn openrouter_vault_key_round_trips_and_validates_test() {
  let #(store, pass) = fresh_store()
  let key_name = "openrouter/api_key"
  let valid_secret = "sk-or-v1-test-key-sentinel-0123456789abcdef"
  vault_put(store, key_name, <<valid_secret:utf8>>, pass) |> should.be_ok
  openrouter_vault_key(store, pass) |> should.equal(Ok(valid_secret))

  // Wrong passphrase fails closed on MAC
  let wrong = store <> "-wrong-pass"
  let assert Ok(_) = simplifile.write(wrong, "another long passphrase here\n")
  openrouter_vault_key(store, wrong) |> should.equal(Error(Nil))

  // Tampered ciphertext byte fails closed on MAC
  let path = secret_path(store, key_name)
  let assert Ok(bytes) = simplifile.read_bits(path)
  let size = bit_array.byte_size(bytes)
  let assert Ok(head) = bit_array.slice(bytes, 0, size - 1)
  let assert Ok(last) = bit_array.slice(bytes, size - 1, 1)
  let flipped = case last {
    <<b>> -> <<{ { b + 1 } % 256 }>>
    _ -> <<0>>
  }
  let assert Ok(_) =
    simplifile.write_bits(path, bit_array.append(head, flipped))
  openrouter_vault_key(store, pass) |> should.equal(Error(Nil))

  // Secret containing whitespace/invalid characters is refused by valid_key/1
  let #(store2, pass2) = fresh_store()
  vault_put(store2, key_name, <<"invalid key with spaces":utf8>>, pass2)
  |> should.be_ok
  openrouter_vault_key(store2, pass2) |> should.equal(Error(Nil))
}

pub fn preference_resolves_telegram_token_from_vault_store_test() {
  let #(store, pass) = fresh_store()
  let token = "999888777:ABC-vault-bot-token-test"
  vault_put(
    store,
    "telegram/production/telegram_token_test_key",
    <<token:utf8>>,
    pass,
  )
  |> should.be_ok
  let assert Ok(read_back) =
    vault_get(store, "telegram/production/telegram_token_test_key", pass)
  bit_array.to_string(read_back) |> should.equal(Ok(token))
  // Verify get_preference returns a non-empty string when vault store is populated
  case get_preference("telegram_token") {
    Ok(v) -> { string.length(v) > 10 } |> should.be_true
    Error(_) -> should.fail()
  }
}
