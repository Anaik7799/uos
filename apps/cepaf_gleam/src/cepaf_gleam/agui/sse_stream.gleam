//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/agui/sse_stream</module>
////     <fsharp-lineage>N/A — new Gleam-first module</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-AGUI-002, SC-GLM-UI-010, SC-GLM-UI-003</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Ring buffer modelled as pure Gleam List + Int counter.
////       No mutable state — all operations return new RingBuffer values.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// SSE Ring Buffer — event ring buffer for Server-Sent Events streaming.
////
//// Provides:
////   - SSEEvent — typed SSE event record (id, event_type, data, retry_ms)
////   - RingBuffer — bounded FIFO of SSEEvents with sequential ID assignment
////   - push_event/3 — append an event, evict oldest when full
////   - events_since/2 — replay events for reconnecting clients (Last-Event-ID)
////   - format_sse_event/1 — RFC 8895 wire format
////   - format_heartbeat/0 — SSE comment heartbeat
////   - format_retry_hint/0 — retry directive for clients
////
//// STAMP: SC-AGUI-002, SC-GLM-UI-010, SC-GLM-UI-003

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A single Server-Sent Event.
///
/// Fields follow RFC 8895 §9.2:
///   id         — event identifier (for Last-Event-ID reconnection)
///   event_type — `event:` field (omit = "message" by convention)
///   data       — `data:` field (the payload)
///   retry_ms   — optional `retry:` directive overriding client reconnect delay
pub type SSEEvent {
  SSEEvent(id: String, event_type: String, data: String, retry_ms: Option(Int))
}

/// Bounded ring buffer for SSEEvents.
///
/// Fields:
///   events   — most-recent events, newest last; bounded to max_size
///   max_size — maximum number of events retained (oldest are evicted)
///   next_id  — monotonically increasing integer assigned to the next push
pub type RingBuffer {
  RingBuffer(events: List(SSEEvent), max_size: Int, next_id: Int)
}

// ---------------------------------------------------------------------------
// Constants (T014)
// ---------------------------------------------------------------------------

/// Recommended client heartbeat interval (ms).
/// Clients should expect a comment frame this often when the stream is idle.
pub const heartbeat_interval_ms = 5000

/// Reconnect delay hint sent to clients via the `retry:` field (ms).
pub const reconnect_hint_ms = 3000

// ---------------------------------------------------------------------------
// Buffer operations
// ---------------------------------------------------------------------------

/// Create a new empty ring buffer with the given maximum capacity.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="isomorphic">Pure constructor, no side effects.</morphism>
///   <formal-proof>
///     <P>max_size > 0</P>
///     <C>new_buffer(max_size)</C>
///     <Q>Result is empty buffer; next_id = 0; capacity = max_size.</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn new_buffer(max_size: Int) -> RingBuffer {
  RingBuffer(events: [], max_size: max_size, next_id: 0)
}

/// Append a new event to the buffer.
///
/// Assigns the next sequential ID to the event, then evicts the oldest event
/// if the buffer has reached max_size.  Pure — returns a new RingBuffer.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P>buffer is a valid RingBuffer; event_type and data are non-empty.</P>
///     <C>push_event(buffer, event_type, data)</C>
///     <Q>
///       Returned buffer has list length <= max_size.
///       New event has id = string of previous next_id.
///       next_id is incremented by 1.
///     </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn push_event(
  buffer: RingBuffer,
  event_type: String,
  data: String,
) -> RingBuffer {
  let event =
    SSEEvent(
      id: int.to_string(buffer.next_id),
      event_type: event_type,
      data: data,
      retry_ms: None,
    )
  let updated = list.append(buffer.events, [event])
  let bounded = case list.length(updated) > buffer.max_size {
    True ->
      case updated {
        [_, ..rest] -> rest
        [] -> []
      }
    False -> updated
  }
  RingBuffer(
    events: bounded,
    max_size: buffer.max_size,
    next_id: buffer.next_id + 1,
  )
}

/// Return all events whose numeric ID is strictly greater than last_id.
///
/// Used by reconnecting SSE clients that send `Last-Event-ID`.
/// Clients that have never connected pass -1 to receive all buffered events.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P>buffer is valid; last_id is the integer from Last-Event-ID header.</P>
///     <C>events_since(buffer, last_id)</C>
///     <Q>
///       Result contains only events with numeric id > last_id.
///       Events are in ascending id order (buffer insertion order).
///     </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn events_since(buffer: RingBuffer, last_id: Int) -> List(SSEEvent) {
  list.filter(buffer.events, fn(ev) {
    case int.parse(ev.id) {
      Ok(n) -> n > last_id
      Error(_) -> False
    }
  })
}

// ---------------------------------------------------------------------------
// Wire-format helpers
// ---------------------------------------------------------------------------

/// Format a single SSEEvent as an RFC 8895 wire-format string.
///
/// Output (all fields present):
///   id: {id}\n
///   event: {event_type}\n
///   data: {data}\n
///   retry: {retry_ms}\n
///   \n
///
/// The trailing double newline signals end-of-event to the client.
pub fn format_sse_event(event: SSEEvent) -> String {
  let id_line = "id: " <> event.id <> "\n"
  let event_line = "event: " <> event.event_type <> "\n"
  let data_line = "data: " <> event.data <> "\n"
  let retry_line = case event.retry_ms {
    None -> ""
    Some(ms) -> "retry: " <> int.to_string(ms) <> "\n"
  }
  string.concat([id_line, event_line, data_line, retry_line, "\n"])
}

/// Emit an SSE comment heartbeat frame.
///
/// SSE comment lines (starting with `:`) are ignored by the browser EventSource
/// but keep the TCP connection alive through proxies and load balancers.
///
/// Format: ": heartbeat\n\n"
pub fn format_heartbeat() -> String {
  ": heartbeat\n\n"
}

/// Emit the SSE retry directive as a standalone frame.
///
/// Instructs the client to wait reconnect_hint_ms milliseconds before
/// attempting a reconnection after the stream closes or errors.
///
/// Format: "retry: 3000\n\n"
pub fn format_retry_hint() -> String {
  "retry: " <> int.to_string(reconnect_hint_ms) <> "\n\n"
}
