import cepaf_gleam/harness/telegram_service as service
import gleam/list
import gleam/string
import gleeunit/should

fn bounded(parts:List(String),bytes:Int,count:Int) {
 assert list.length(parts)<=count
 assert list.all(parts,fn(p){string.byte_size(p)<=bytes && string.trim(p)!=""})
}
pub fn exact_final_slot_preserves_all_bytes_test(){
 list.each([1,2,16],fn(n){
 let input=string.repeat("a",4096*n)
 let parts=service.chunk_payload_utf8_bounded(input,4096,n)
 bounded(parts,4096,n)
 assert string.join(parts,"")==input
 })
}
pub fn oversized_grapheme_preserves_unicode_test(){
 let input="a"<>string.repeat("\u{301}",3000)
 let parts=service.chunk_payload_utf8(input)
 bounded(parts,4096,16)
 assert list.length(parts)==2
 assert string.join(parts,"")==input
}
pub fn truncation_only_on_real_overflow_test(){
 let input=string.repeat("a",4097)
 let parts=service.chunk_payload_utf8_bounded(input,4096,1)
 bounded(parts,4096,1)
 assert string.ends_with(string.join(parts,""),"\n... [truncated]")
 assert string.byte_size(string.join(parts,""))==4096
}
pub fn whole_graphemes_retained_when_they_fit_test(){
 let family="👩‍👩‍👧‍👦"
 let input=string.repeat(family,400)
 let parts=service.chunk_payload_utf8(input)
 bounded(parts,4096,16)
 assert string.join(parts,"")==input
 assert list.all(parts,fn(p){string.to_graphemes(p) |> list.all(fn(g){g==family})})
}
pub fn scalar_bound_matrix_test(){
 list.each(["x","é","界","😀","a\u{301}"],fn(unit){
 list.each([16,17,32,64,4096],fn(limit){
 let input=string.repeat(unit,100)
 let parts=service.chunk_payload_utf8_bounded(input,limit,16)
 bounded(parts,limit,16)
 case string.byte_size(input)<=16*{limit-4} {
 True->{ assert string.join(parts,"")==input }
 False->Nil
 }
 })
 })
}
pub fn invalid_limits_fail_closed_test(){
 list.each([#(0,1),#(15,1),#(4097,1),#(4096,0),#(4096,17),#(-1,-1)],fn(x){
 service.chunk_payload_utf8_bounded("x",x.0,x.1) |> should.equal([])
 })
}
pub fn empty_and_nul_compatibility_test(){
 service.chunk_payload_utf8("  \n ") |> should.equal(["(empty)"])
 service.chunk_payload_utf8("before\u{0}after") |> should.equal(["before[NUL]after"])
}

pub fn truncated_large_grapheme_retains_scalar_prefix_test(){
 let input="a"<>string.repeat("\u{301}",2047)<>"bb"
 let parts=service.chunk_payload_utf8_bounded(input,4096,1)
 bounded(parts,4096,1)
 let output=string.join(parts,"")
 assert string.byte_size(output)>16
 assert string.ends_with(output,"\n... [truncated]")
}
