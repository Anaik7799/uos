# BEAM Integration Guide
# Erlang FFI Rules
# Mapping Enums
Gleam custom types without fields are atoms in Erlang.
Custom types with fields are tuples.
**Gleam**:
```gleam
pub type Status {
Ok
Error(String)
}
```
**Erlang Representation**:
- `Ok` -> `'ok'`
- `Error("msg")` -> `{'error', <<"msg">>}`
# String vs BitArray
Gleam `String` is UTF-8 encoded `BitArray`. In Erlang FFI, always use `binary` for strings.
# Function Naming
Erlang functions should be exported and namespaced properly to avoid conflicts.
# OTP Actors in Gleam
Use `gleam/otp/actor` for managed state.
```gleam
import gleam/otp/actor
import gleam/erlang/process
pub type State {
State(count: Int)
}
pub type Message {
Increment
GetCount(reply_to: process.Subject(Int))
}
pub fn start() {
actor.start(State(0), handle_message)
}
fn handle_message(msg: Message, state: State) {
case msg {
Increment -> actor.continue(State(state.count + 1))
GetCount(subject) -> {
process.send(subject, state.count)
actor.continue(state)
}
}
}
```
# Low-Level Networking
For TCP/UDS, use Erlang's `gen_tcp` or `hackney` via FFI.
```erlang
-module(my_ffi).
-export([connect_uds/1]).
connect_uds(Path) ->
gen_tcp:connect({local, Path}, 0, [binary, {active, false}]).
```