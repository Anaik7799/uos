import filepath
import gleam/bit_array
import gleam/list
import gleeunit/should
import simplifile
import uos_planning_ledger/digest
import uos_planning_ledger/prompt.{PartialOrTruncated, Prompt, VerbatimAvailable}

pub fn extracts_labelled_and_latest_prompt_blocks_test() {
  let archive =
    "# Journal\n\n### 3.3 Latest cumulative user prompt, verbatim\n\n```text\nlatest body\n```\n\n```text\n[Prompt 1]\nfirst body\n\n[Continuation 1 / Prompt 2]\nsecond body\n```\n"

  prompt.extract(archive)
  |> should.equal([
    Prompt("Latest cumulative user prompt", "latest body", VerbatimAvailable),
    Prompt("Prompt 1", "first body", VerbatimAvailable),
    Prompt("Continuation 1 / Prompt 2", "second body", VerbatimAvailable),
  ])
}

pub fn ignores_non_text_fences_and_marks_partial_records_test() {
  let archive =
    "```sql\n[Prompt 1]\nnot a prompt\n```\n~~~text\n[Post-handover Prompt 9]\npartial or truncated\n~~~\n"

  prompt.extract(archive)
  |> should.equal([
    Prompt("Post-handover Prompt 9", "partial or truncated", PartialOrTruncated),
  ])
}

pub fn preserves_internal_newlines_but_trims_record_edges_test() {
  let archive = "```text\n[Prompt 1]\n\nalpha  \nbeta\n\n```\n"

  prompt.extract(archive)
  |> should.equal([
    Prompt("Prompt 1", "alpha  \nbeta", VerbatimAvailable),
  ])
}

pub fn accepts_crlf_and_trailing_fence_whitespace_without_normalizing_body_test() {
  let archive =
    "### 3.4 Latest cumulative user prompt, verbatim\r\n\r\n```text   \r\nfirst\r\nsecond\r\n```   \r\n"

  prompt.extract(archive)
  |> should.equal([
    Prompt(
      "Latest cumulative user prompt",
      "first\r\nsecond",
      VerbatimAvailable,
    ),
  ])
}

pub fn requires_unindented_fences_and_standalone_partial_suffix_test() {
  let archive =
    "   ```text\n[Prompt 1]\nignored\n   ```\n```text\n[Prompt 2]\nmenu\n[Prompt 3]\nends in u\n```\n"

  prompt.extract(archive)
  |> should.equal([
    Prompt("Prompt 2", "menu", VerbatimAvailable),
    Prompt("Prompt 3", "ends in u", PartialOrTruncated),
  ])
}

pub fn sha256_is_lowercase_hex_over_exact_bytes_test() {
  digest.sha256_hex(<<"abc":utf8>>)
  |> should.equal(
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

pub fn historical_corpus_count_and_known_hashes_are_stable_test() {
  let assert Ok(workspace_root) = simplifile.resolve("../../..")
  let assert Ok(archive) =
    simplifile.read(filepath.join(
      workspace_root,
      "c3i/docs/journal/20260904-uos-full-history-evidence-review-journal.md",
    ))
  let records = prompt.extract(archive)
  list.length(records) |> should.equal(38)

  let assert [Prompt(_, twentieth, VerbatimAvailable), ..] =
    list.drop(records, 19)
  twentieth
  |> bit_array.from_string
  |> bit_array.byte_size
  |> should.equal(936)
  digest.sha256_hex(bit_array.from_string(twentieth))
  |> should.equal(
    "2b5fbcf97bb6ecb42ff38395197f3604ac1f19364456d535a77e57414ed6ca97",
  )

  let assert [Prompt(_, _, PartialOrTruncated), ..] = list.drop(records, 23)
  records
  |> list.filter(fn(record) {
    case record {
      Prompt(_, _, PartialOrTruncated) -> True
      _ -> False
    }
  })
  |> list.length
  |> should.equal(1)
}
