//// Shared homeostasis transport adapter. Gleam owns routing and evidence policy.
import cepaf_gleam/web/homeostasis_http as shared
import cepaf_gleam/ui/homeostasis_data as data
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist.{type Connection, type ResponseData}

@external(erlang, "indrajaal_web_ffi", "listen_port")
fn listen_port(default: Int) -> Int

pub fn document() -> String { shared.document() }
pub fn selected_document(selection: data.Selection, component: String) -> String {
  shared.selected_document(selection, component)
}
pub fn selected_document_on_port(selection: data.Selection, component: String, port: Int) -> String {
  shared.selected_document_on_port(selection, component, port)
}
pub fn snapshot_response() -> Response(ResponseData) { shared.snapshot_response() }
pub fn page_response() -> Response(ResponseData) { shared.page_response() }
pub fn handle(req: Request(Connection)) -> Response(ResponseData) {
  shared.handle_on_port(req, listen_port(4100))
}
