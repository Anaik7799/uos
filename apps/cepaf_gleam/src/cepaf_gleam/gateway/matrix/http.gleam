//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/gateway/matrix/http</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-MATRIX-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Matrix HTTP transport layer — pure request/response types.

import gleam/int
import gleam/option.{type Option, None, Some}

pub type HttpMethod {
  Get
  Post
  Put
  Delete
}

pub type MatrixHttpClient {
  MatrixHttpClient(
    base_url: String,
    access_token: Option(String),
    timeout_ms: Int,
  )
}

pub type HttpRequest {
  HttpRequest(
    method: HttpMethod,
    url: String,
    headers: List(#(String, String)),
    body: Option(String),
  )
}

pub type MatrixResponse {
  MatrixResponse(status: Int, body: String)
}

pub type MatrixError {
  HttpError(reason: String)
  ApiError(errcode: String, error: String)
  RateLimited(retry_after_ms: Int)
  Timeout
  NetworkError(reason: String)
}

pub fn new(base_url: String) -> MatrixHttpClient {
  MatrixHttpClient(base_url: base_url, access_token: None, timeout_ms: 30_000)
}

pub fn with_token(client: MatrixHttpClient, token: String) -> MatrixHttpClient {
  MatrixHttpClient(..client, access_token: Some(token))
}

pub fn with_timeout(client: MatrixHttpClient, ms: Int) -> MatrixHttpClient {
  MatrixHttpClient(..client, timeout_ms: ms)
}

pub fn build_request(
  client: MatrixHttpClient,
  method: HttpMethod,
  path: String,
  body: Option(String),
) -> HttpRequest {
  HttpRequest(
    method: method,
    url: build_url(client, path),
    headers: auth_headers(client),
    body: body,
  )
}

pub fn build_url(client: MatrixHttpClient, path: String) -> String {
  client.base_url <> path
}

pub fn auth_headers(client: MatrixHttpClient) -> List(#(String, String)) {
  let base = [#("Content-Type", "application/json")]
  case client.access_token {
    Some(token) -> [#("Authorization", "Bearer " <> token), ..base]
    None -> base
  }
}

pub fn is_success(status: Int) -> Bool {
  status >= 200 && status <= 299
}

pub fn method_to_string(method: HttpMethod) -> String {
  case method {
    Get -> "GET"
    Post -> "POST"
    Put -> "PUT"
    Delete -> "DELETE"
  }
}

pub fn request_summary(req: HttpRequest) -> String {
  method_to_string(req.method) <> " " <> req.url
}

pub fn error_to_string(err: MatrixError) -> String {
  case err {
    HttpError(r) -> "HTTP error: " <> r
    ApiError(code, msg) -> "API error " <> code <> ": " <> msg
    RateLimited(ms) -> "Rate limited, retry after " <> int.to_string(ms) <> "ms"
    Timeout -> "Request timeout"
    NetworkError(r) -> "Network error: " <> r
  }
}
