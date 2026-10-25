import cepaf_gleam/telegram/mini_history as h
import cepaf_gleam/telegram/mini_api as api
import cepaf_gleam/harness/telegram_conversation as conv
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/files
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import mini_test_vectors as vectors

fn present(key: String, value: String) -> codec.RowResult {
  codec.RowResult(key, True, 1, codec.encode_canonical_base64(value), files.digest(value))
}
fn scope() { conv.Scope(333444, 42, 42) }
fn rows(context: conv.Context) {
  let assert Ok(raw) = conv.encode_context(context)
  let assert Ok(key) = conv.context_key(context.scope)
  [present(codec.bot_identity_key(), codec.encode_bot_identity_value(context.scope.bot_id)), present(key, raw)]
}
fn sample() { conv.Context(scope(), [conv.Turn(1, "hello", "reply")]) }

pub fn explicit_private_or_signed_group_grants_test() {
  let assert Ok(c) = h.configuration("333444:synthetic", [h.Grant(42,42),h.Grant(42,-100123)])
  h.resolve_scope(c,42,None) |> should.equal(Ok(scope()))
  h.resolve_scope(c,42,Some(-100123)) |> should.equal(Ok(conv.Scope(333444,-100123,42)))
  h.resolve_scope(c,99,None) |> should.be_error
  h.resolve_scope(c,42,Some(-100124)) |> should.be_error
  let assert Ok(group_only) = h.configuration("333444:synthetic", [h.Grant(42,-100123)])
  h.resolve_scope(group_only,42,None) |> should.be_error
}

pub fn token_and_grants_configuration_refusal_test() {
  list.each(["synthetic","0:x","-1:x","0333444:x","333444:","333444:x:y","9007199254740992:x"], fn(t) {
    h.configuration(t,[h.Grant(42,42)]) |> should.be_error
  })
  h.configuration("333444:x",[]) |> should.be_error
  h.configuration("333444:x",[h.Grant(42,42),h.Grant(42,42)]) |> should.be_error
  h.configuration("333444:x",[h.Grant(0,42)]) |> should.be_error
  h.configuration("333444:x",[h.Grant(42,0)]) |> should.be_error
}

pub fn complete_history_projection_test() {
  let assert Ok(api.Observed(1000,"durable_telegram_conversation",fields)) = h.from_rows(scope(),3,rows(sample()),1000)
  dict.get(fields,"Stored exchanges") |> should.equal(Ok("1"))
  dict.get(fields,"Runtime admission") |> should.equal(Ok("NOT_GRANTED"))
  dict.get(fields,"Exchange 01 update 1 · 1 You · 01") |> should.equal(Ok("hello"))
  dict.get(fields,"Exchange 01 update 1 · 2 Assistant · 01") |> should.equal(Ok("reply"))
}

pub fn absent_history_requires_valid_bot_and_absence_shape_test() {
  let assert Ok(key) = conv.context_key(scope())
  let bot = present(codec.bot_identity_key(),codec.encode_bot_identity_value(333444))
  let absent = codec.RowResult(key,False,0,"","")
  let assert Ok(api.Observed(_,_,fields)) = h.from_rows(scope(),1,[bot,absent],1000)
  dict.get(fields,"Stored exchanges") |> should.equal(Ok("0"))
  h.from_rows(scope(),1,[bot,codec.RowResult(..absent,version:1)],1000) |> should.be_error
  h.from_rows(scope(),1,[codec.RowResult(codec.bot_identity_key(),False,0,"",""),absent],1000) |> should.be_error
}

pub fn bot_user_chat_isolation_test() {
  list.each([conv.Scope(333445,42,42),conv.Scope(333444,43,42),conv.Scope(333444,42,43)], fn(other) {
    h.from_rows(other,3,rows(sample()),1000) |> should.be_error
  })
  let assert Ok(key) = conv.context_key(scope())
  let assert Ok(foreign) = conv.encode_context(conv.Context(conv.Scope(333444,42,43),[conv.Turn(1,"secret","other")]))
  h.from_rows(scope(),3,[present(codec.bot_identity_key(),codec.encode_bot_identity_value(333444)),present(key,foreign)],1000) |> should.be_error
}

pub fn database_bot_binding_is_mandatory_test() {
  let assert [_,ctx] = rows(sample())
  h.from_rows(scope(),1,[present(codec.bot_identity_key(),codec.encode_bot_identity_value(333445)),ctx],1000) |> should.be_error
}

pub fn corrupt_rows_and_duplicate_keys_refused_test() {
  let assert [bot,ctx] = rows(sample())
  h.from_rows(scope(),1,[bot,codec.RowResult(..ctx,sha256:files.digest("wrong"))],1000) |> should.be_error
  h.from_rows(scope(),1,[bot,bot],1000) |> should.be_error
  h.from_rows(scope(),1,[bot],1000) |> should.be_error
  h.from_rows(scope(),1,[bot,ctx,ctx],1000) |> should.be_error
  h.from_rows(scope(),0,[bot,ctx],1000) |> should.be_error
  h.from_rows(scope(),1,[bot,ctx],0) |> should.be_error
}

pub fn malformed_context_refused_test() {
  let assert [bot,ctx] = rows(sample())
  list.each(["{}","not-json","[]"],fn(raw) {
    h.from_rows(scope(),1,[bot,present(ctx.key,raw)],1000) |> should.be_error
  })
}

pub fn unicode_chunks_preserve_every_byte_test() {
  list.each(["hello",string.repeat("🧪",2048),string.repeat("é",2500),string.repeat("<script>&",900)],fn(raw) {
    let parts=h.chunks(raw)
    string.join(parts,"") |> should.equal(raw)
    list.all(parts,fn(p) { string.byte_size(p)>0 && string.byte_size(p)<=2048 }) |> should.be_true
  })
  h.chunks("") |> should.equal([])
}

pub fn maximal_history_stays_within_api_bounds_test() {
  let context=conv.Context(scope(),[
    conv.Turn(1,string.repeat("a",4096),string.repeat("🧪",2048)),
    conv.Turn(2,string.repeat("b",4096),string.repeat("z",8192)),
  ])
  let assert Ok(api.Observed(_,_,fields))=h.from_rows(scope(),1,rows(context),1000)
  { dict.size(fields) <= 100 } |> should.be_true
  list.all(dict.to_list(fields),fn(p) { string.byte_size(p.0)<=128 && string.byte_size(p.1)<=2048 }) |> should.be_true
  let details=dict.to_list(fields) |> list.filter(fn(p) { string.starts_with(p.0,"Exchange ") })
  list.fold(details,0,fn(n,p) { n+string.byte_size(p.1) }) |> should.equal(24576)
}

pub fn denied_history_grant_never_calls_backend_test() {
  let assert Ok(auth)=api.configuration("synthetic-mini-test-token",[api.AllowedIdentity(42,None)],300)
  let body=json.object([#("init_data",json.string(vectors.valid)),#("path",json.string("/mini-app/chat"))]) |> json.to_string
  let assert Ok(read)=api.authorize(body,auth,1000)
  let assert Ok(config)=h.configuration("333444:x",[h.Grant(99,99)])
  h.observe(config,read,fn(_) { panic as "unauthorized backend called" },fn(){1000}) |> should.be_error
}

pub fn backend_failure_is_not_empty_history_test() {
  let assert Ok(auth)=api.configuration("synthetic-mini-test-token",[api.AllowedIdentity(42,None)],300)
  let body=json.object([#("init_data",json.string(vectors.valid)),#("path",json.string("/mini-app/chat"))]) |> json.to_string
  let assert Ok(read)=api.authorize(body,auth,1000)
  let assert Ok(config)=h.configuration("333444:x",[h.Grant(42,42)])
  h.observe(config,read,fn(_) { Error("backend failed") },fn(){1000}) |> should.equal(Error("backend failed"))
}
