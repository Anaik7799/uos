/* One C stub between the harness and the vendored zenoh-c (1.x API):
   open a client session to the given endpoint, put one payload at one key,
   drop the session. Every failure returns an "error: ..." string -- the OCaml
   side turns it into (unit, string) result; nothing here exits or raises.

   OCaml strings are copied into local buffers BEFORE any zenoh call: zenoh
   may allocate/thread internally, and the OCaml GC must never be able to
   move a value we still point at. */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/threads.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "zenoh.h"

#define HZ_BUF 1024

CAMLprim value caml_hz_publish(value v_endpoint, value v_key, value v_payload)
{
  CAMLparam3(v_endpoint, v_key, v_payload);
  CAMLlocal1(result);

  char endpoint[HZ_BUF], key[HZ_BUF];
  char *payload = NULL;
  char detail[HZ_BUF];

  if (caml_string_length(v_endpoint) >= HZ_BUF || caml_string_length(v_key) >= HZ_BUF) {
    result = caml_copy_string("error: endpoint or key too long");
    CAMLreturn(result);
  }
  snprintf(endpoint, sizeof endpoint, "%s", String_val(v_endpoint));
  snprintf(key, sizeof key, "%s", String_val(v_key));
  size_t payload_length = caml_string_length(v_payload);
  payload = malloc(payload_length + 1);
  if (payload == NULL) {
    result = caml_copy_string("error: out of memory copying payload");
    CAMLreturn(result);
  }
  memcpy(payload, String_val(v_payload), payload_length);
  payload[payload_length] = '\0';

  /* One JSON config string, exactly the header's documented idiom:
     '{mode:"client",connect:{endpoints:["tcp/127.0.0.1:7447"]}}'. Client mode
     means: connect ONLY to the named router -- an unreachable router fails
     z_open fast instead of drifting into peer scouting. */
  char config_json[HZ_BUF + 64];
  snprintf(config_json, sizeof config_json,
           "{mode:\"client\",connect:{endpoints:[\"%s\"]}}", endpoint);
  z_owned_config_t config;
  if (zc_config_from_str(&config, config_json) < 0) {
    free(payload);
    result = caml_copy_string("error: zenoh config rejected mode/endpoint");
    CAMLreturn(result);
  }

  z_owned_session_t session;
  if (z_open(&session, z_move(config), NULL) < 0) {
    free(payload);
    snprintf(detail, sizeof detail, "error: cannot open zenoh session to %.900s", endpoint);
    result = caml_copy_string(detail);
    CAMLreturn(result);
  }

  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0) {
    z_session_drop(z_move(session));
    free(payload);
    result = caml_copy_string("error: zenoh rejected the key expression");
    CAMLreturn(result);
  }

  z_owned_bytes_t bytes;
  z_bytes_copy_from_str(&bytes, payload);
  int rc = z_put(z_loan(session), z_loan(keyexpr), z_move(bytes), NULL);
  z_session_drop(z_move(session));
  free(payload);

  if (rc < 0) {
    snprintf(detail, sizeof detail, "error: z_put returned %d", rc);
    result = caml_copy_string(detail);
    CAMLreturn(result);
  }
  result = caml_copy_string("ok");
  CAMLreturn(result);
}

static void hz_reply_text(z_loaned_query_t *query, const char *key, const char *text)
{
  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0) return;
  z_owned_bytes_t bytes;
  z_bytes_copy_from_str(&bytes, text);
  z_query_reply(query, z_loan(keyexpr), z_move(bytes), NULL);
}

static void hz_query_callback(z_loaned_query_t *query, void *context)
{
  (void)context;
  z_view_string_t key_view;
  z_keyexpr_as_view_string(z_query_keyexpr(query), &key_view);
  const z_loaned_string_t *key_string = z_view_string_loan(&key_view);
  size_t key_length = z_string_len(key_string);
  const char *key_data = z_string_data(key_string);

  char *key = malloc(key_length + 1);
  if (key == NULL) {
    hz_reply_text(query, "hermes/control/completion/error", "{\"error\":\"out of memory copying key\"}");
    return;
  }
  memcpy(key, key_data, key_length);
  key[key_length] = '\0';

  const z_loaned_bytes_t *payload_bytes = z_query_payload(query);
  z_owned_string_t payload_owned;
  if (payload_bytes == NULL || z_bytes_to_string(payload_bytes, &payload_owned) < 0) {
    hz_reply_text(query, key, "{\"error\":\"query payload is required\"}");
    free(key);
    return;
  }
  const z_loaned_string_t *payload_string = z_string_loan(&payload_owned);
  size_t payload_length = z_string_len(payload_string);
  const char *payload_data = z_string_data(payload_string);
  char *payload = malloc(payload_length + 1);
  if (payload == NULL) {
    z_string_drop(z_move(payload_owned));
    hz_reply_text(query, key, "{\"error\":\"out of memory copying payload\"}");
    free(key);
    return;
  }
  memcpy(payload, payload_data, payload_length);
  payload[payload_length] = '\0';
  z_string_drop(z_move(payload_owned));

  int registered = caml_c_thread_register();
  caml_acquire_runtime_system();
  CAMLparam0();
  CAMLlocal3(v_key, v_payload, v_reply);
  const value *callback = caml_named_value("hermes_zenoh_command");
  char *reply = NULL;
  if (callback == NULL) {
    reply = strdup("{\"error\":\"OCaml Zenoh command callback is not registered\"}");
  } else {
    v_key = caml_copy_string(key);
    v_payload = caml_copy_string(payload);
    v_reply = caml_callback2_exn(*callback, v_key, v_payload);
    if (Is_exception_result(v_reply)) {
      reply = strdup("{\"error\":\"OCaml Zenoh command callback raised\"}");
    } else {
      size_t reply_length = caml_string_length(v_reply);
      reply = malloc(reply_length + 1);
      if (reply != NULL) {
        memcpy(reply, String_val(v_reply), reply_length);
        reply[reply_length] = '\0';
      }
    }
  }
  CAMLdrop;
  caml_release_runtime_system();
  if (registered) caml_c_thread_unregister();

  if (reply == NULL) reply = strdup("{\"error\":\"out of memory copying reply\"}");
  hz_reply_text(query, key, reply);
  free(reply);
  free(payload);
  free(key);
}

CAMLprim value caml_hz_serve_queryable(value v_endpoint, value v_keyexpr)
{
  CAMLparam2(v_endpoint, v_keyexpr);
  CAMLlocal1(result);
  char endpoint[HZ_BUF], keyexpr[HZ_BUF], detail[HZ_BUF];

  if (caml_string_length(v_endpoint) >= HZ_BUF || caml_string_length(v_keyexpr) >= HZ_BUF) {
    result = caml_copy_string("error: endpoint or key expression too long");
    CAMLreturn(result);
  }
  snprintf(endpoint, sizeof endpoint, "%s", String_val(v_endpoint));
  snprintf(keyexpr, sizeof keyexpr, "%s", String_val(v_keyexpr));

  char config_json[HZ_BUF + 64];
  snprintf(config_json, sizeof config_json,
           "{mode:\"client\",connect:{endpoints:[\"%s\"]}}", endpoint);
  z_owned_config_t config;
  if (zc_config_from_str(&config, config_json) < 0) {
    result = caml_copy_string("error: zenoh config rejected mode/endpoint");
    CAMLreturn(result);
  }
  z_owned_session_t session;
  if (z_open(&session, z_move(config), NULL) < 0) {
    snprintf(detail, sizeof detail, "error: cannot open zenoh session to %.900s", endpoint);
    result = caml_copy_string(detail);
    CAMLreturn(result);
  }
  z_view_keyexpr_t key_view;
  if (z_view_keyexpr_from_str(&key_view, keyexpr) < 0) {
    z_session_drop(z_move(session));
    result = caml_copy_string("error: zenoh rejected the queryable key expression");
    CAMLreturn(result);
  }
  z_owned_closure_query_t closure;
  z_closure_query(&closure, hz_query_callback, NULL, NULL);
  z_owned_queryable_t queryable;
  z_queryable_options_t options;
  z_queryable_options_default(&options);
  int rc = z_declare_queryable(z_loan(session), &queryable, z_loan(key_view),
                               z_move(closure), &options);
  if (rc < 0) {
    z_session_drop(z_move(session));
    snprintf(detail, sizeof detail, "error: z_declare_queryable returned %d", rc);
    result = caml_copy_string(detail);
    CAMLreturn(result);
  }

  caml_enter_blocking_section();
  for (;;) sleep(3600);
  caml_leave_blocking_section();
  z_queryable_drop(z_move(queryable));
  z_session_drop(z_move(session));
  result = caml_copy_string("ok");
  CAMLreturn(result);
}

CAMLprim value caml_hz_query(value v_endpoint, value v_key, value v_payload)
{
  CAMLparam3(v_endpoint, v_key, v_payload);
  CAMLlocal1(result);
  char endpoint[HZ_BUF], key[HZ_BUF], detail[HZ_BUF];
  char *payload = NULL;

  if (caml_string_length(v_endpoint) >= HZ_BUF || caml_string_length(v_key) >= HZ_BUF) {
    result = caml_copy_string("error: endpoint or key too long");
    CAMLreturn(result);
  }
  snprintf(endpoint, sizeof endpoint, "%s", String_val(v_endpoint));
  snprintf(key, sizeof key, "%s", String_val(v_key));
  size_t payload_length = caml_string_length(v_payload);
  payload = malloc(payload_length + 1);
  if (payload == NULL) {
    result = caml_copy_string("error: out of memory copying payload");
    CAMLreturn(result);
  }
  memcpy(payload, String_val(v_payload), payload_length);
  payload[payload_length] = '\0';

  char config_json[HZ_BUF + 64];
  snprintf(config_json, sizeof config_json,
           "{mode:\"client\",connect:{endpoints:[\"%s\"]}}", endpoint);
  z_owned_config_t config;
  if (zc_config_from_str(&config, config_json) < 0) {
    free(payload);
    result = caml_copy_string("error: zenoh config rejected mode/endpoint");
    CAMLreturn(result);
  }
  z_owned_session_t session;
  if (z_open(&session, z_move(config), NULL) < 0) {
    free(payload);
    snprintf(detail, sizeof detail, "error: cannot open zenoh session to %.900s", endpoint);
    result = caml_copy_string(detail);
    CAMLreturn(result);
  }
  z_view_keyexpr_t keyexpr;
  if (z_view_keyexpr_from_str(&keyexpr, key) < 0) {
    z_session_drop(z_move(session));
    free(payload);
    result = caml_copy_string("error: zenoh rejected the command key");
    CAMLreturn(result);
  }

  z_owned_closure_reply_t closure;
  z_owned_fifo_handler_reply_t handler;
  z_fifo_channel_reply_new(&closure, &handler, 4);
  z_owned_bytes_t payload_bytes;
  z_bytes_copy_from_str(&payload_bytes, payload);
  z_get_options_t options;
  z_get_options_default(&options);
  options.payload = z_move(payload_bytes);
  options.timeout_ms = 5000;
  int rc = z_get(z_loan(session), z_loan(keyexpr), "", z_move(closure), &options);
  free(payload);
  if (rc < 0) {
    z_fifo_handler_reply_drop(z_move(handler));
    z_session_drop(z_move(session));
    snprintf(detail, sizeof detail, "error: z_get returned %d", rc);
    result = caml_copy_string(detail);
    CAMLreturn(result);
  }

  z_owned_reply_t reply;
  caml_enter_blocking_section();
  rc = z_fifo_handler_reply_recv(z_loan(handler), &reply);
  caml_leave_blocking_section();
  if (rc < 0) {
    z_fifo_handler_reply_drop(z_move(handler));
    z_session_drop(z_move(session));
    result = caml_copy_string("error: no Zenoh command reply before timeout");
    CAMLreturn(result);
  }

  const z_loaned_reply_t *loaned_reply = z_loan(reply);
  const z_loaned_bytes_t *reply_payload = NULL;
  if (z_reply_is_ok(loaned_reply)) {
    const z_loaned_sample_t *sample = z_reply_ok(loaned_reply);
    reply_payload = z_sample_payload(sample);
  } else {
    const z_loaned_reply_err_t *reply_error = z_reply_err(loaned_reply);
    reply_payload = z_reply_err_payload(reply_error);
  }
  z_owned_string_t reply_string;
  if (reply_payload == NULL || z_bytes_to_string(reply_payload, &reply_string) < 0) {
    z_reply_drop(z_move(reply));
    z_fifo_handler_reply_drop(z_move(handler));
    z_session_drop(z_move(session));
    result = caml_copy_string("error: Zenoh command reply had no readable payload");
    CAMLreturn(result);
  }
  const z_loaned_string_t *loaned_string = z_string_loan(&reply_string);
  size_t reply_length = z_string_len(loaned_string);
  const char *reply_data = z_string_data(loaned_string);
  result = caml_alloc_initialized_string(reply_length, reply_data);
  z_string_drop(z_move(reply_string));
  z_reply_drop(z_move(reply));
  z_fifo_handler_reply_drop(z_move(handler));
  z_session_drop(z_move(session));
  CAMLreturn(result);
}
