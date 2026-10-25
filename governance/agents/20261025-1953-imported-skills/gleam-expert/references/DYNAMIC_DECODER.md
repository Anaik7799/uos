# Dynamic Decoder Patterns
Gleam 1.0+ uses a monadic-style decoder API.
# Decoding Records
```gleam
import gleam/dynamic/decode
pub type User {
User(id: Int, name: String, email: String)
}
pub fn user_decoder() {
use id <- decode.field("id", decode.int)
use name <- decode.field("name", decode.string)
use email <- decode.field("email", decode.string)
decode.success(User(id, name, email))
}
```
# Optional Fields
Use `decode.optional_field` which returns the value or a default.
```gleam
use bio <- decode.optional_field("bio", option.None, decode.string |> decode.map(option.Some))
```
# Nested Objects
Use `decode.at` for deep indexing.
```gleam
use city <- decode.at(["address", "city"], decode.string)
```
# Custom Decoders
Use `decode.then` for conditional decoding or manual validation.
```gleam
let status_decoder = {
use s <- decode.then(decode.string)
case s {
"active" -> decode.success(Active)
_ -> decode.failure(Active, "valid status")
}
}
```