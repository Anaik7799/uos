//// Bounded dialogue selection; no tools, effects, telemetry claims or authority.
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const instruction = "Use Socratic dialogue: ask one to three concise, evidence-seeking questions about the user's topic. Distinguish supplied observations from assumptions, consider alternative hypotheses and what would disconfirm them. Do not invent evidence, telemetry or a confirmed root cause. Do not claim access to other participants or an active multi-party mediation session. Keep the dialogue useful for the user's stated goal."

pub fn topic(raw:String)->Result(String,String) {
 let value=string.trim(raw)
 case value!="" && string.byte_size(raw)<=2048
  && list.all(string.to_utf_codepoints(raw),fn(cp){
   let c=string.utf_codepoint_to_int(cp)
   c==9 || c==10 || {c>=32 && c!=127 && {c<128 || c>159}}
  }) {
  True->Ok(value)
  False->Error("Use /socratic <topic>, with 1 to 2048 UTF-8 bytes and no control characters.")
 }
}
pub fn tool_topic(raw:String)->Result(String,String) {
 use _<-result.try(case string.byte_size(raw)<=4096 {True->Ok(Nil) False->Error("Dialogue arguments exceed bounds.")})
 use fields<-result.try(json.parse(raw,decode.dict(decode.string,decode.string)) |> result.replace_error("Expected only a topic string."))
 case dict.to_list(fields) {
  [#("topic",value)]->topic(value)
  _->Error("Expected exactly one topic field; identity and model overrides refused.")
 }
}
