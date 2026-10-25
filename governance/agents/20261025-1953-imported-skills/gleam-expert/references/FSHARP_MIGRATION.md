# F# to Gleam Migration Guide
# Type Mapping
| F# Pattern | Gleam Pattern |
|:---|:---|
| `type Status = Ok \| Error of string` | `pub type Status { Ok Error(String) }` |
| `type User = { Id: int; Name: string }` | `pub type User { User(id: Int, name: String) }` |
| `Option<'a>` | `Option(a)` (from `gleam/option`) |
| `Result<'a, 'b>` | `Result(a, b)` |
| `Map<string, string>` | `Dict(String, String)` (from `gleam/dict`) |
| `list<'a>` | `List(a)` |
# Workflow Mapping
# Async Workflows
F# `async { ... }` is replaced by BEAM processes and tasks.
**F#**:
```fsharp
let fetchUser id = async {
let! json = httpClient.Get (sprintf "/users/%d" id)
return decode json
}
```
**Gleam**:
```gleam
pub fn fetch_user(id: Int) {
use json <- result.try(http_client.get("/users/" <> int.to_string(id)))
decode(json)
}
```
# MailboxProcessor
F# `MailboxProcessor` is replaced by Gleam `actor`.
**F#**:
```fsharp
let agent = MailboxProcessor.Start(fun inbox ->
let rec loop state = async {
let! msg = inbox.Receive()
return! loop (update state msg)
}
loop initial_state)
```
**Gleam**:
```gleam
pub fn start() {
actor.start(initial_state, loop)
}
fn loop(msg, state) {
actor.continue(update(state, msg))
}
```
# Units of Measure
Gleam does not have native Units of Measure. Use opaque types for high-assurance unit safety.
```gleam
pub opaque type Seconds {
Seconds(Int)
}
```