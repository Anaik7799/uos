import gleam/bit_array
import gleam/crypto
import gleam/string

/// Return the lowercase SHA-256 digest of the exact supplied bytes.
pub fn sha256_hex(bytes: BitArray) -> String {
  crypto.hash(crypto.Sha256, bytes)
  |> bit_array.base16_encode
  |> string.lowercase
}
