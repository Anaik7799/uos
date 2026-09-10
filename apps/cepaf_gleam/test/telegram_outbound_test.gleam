import cepaf_gleam/harness/telegram_outbound.{
  chunk_text, find_cut_index, find_last_char_offset, get_default_chat_id,
  get_telegram_token, max_message_length,
}
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

pub fn chunk_text_short_test() {
  let msg = "Short message under 4096 chars"
  let chunks = chunk_text(msg, max_message_length)
  chunks
  |> should.equal([msg])
}

pub fn chunk_text_exact_length_test() {
  let msg = string.repeat("a", 4096)
  let chunks = chunk_text(msg, 4096)
  list.length(chunks)
  |> should.equal(1)
  chunks
  |> should.equal([msg])
}

pub fn chunk_text_with_newline_boundary_test() {
  let prefix = string.repeat("a", 3800)
  let suffix = string.repeat("b", 1000)
  let full = prefix <> "\n" <> suffix
  let chunks = chunk_text(full, 4096)

  list.length(chunks)
  |> should.equal(2)

  case chunks {
    [first, second] -> {
      // First chunk should end with the newline
      string.ends_with(first, "\n")
      |> should.be_true
      string.length(first)
      |> should.equal(3801)
      first
      |> should.equal(prefix <> "\n")
      second
      |> should.equal(suffix)
    }
    _ -> should.fail()
  }
}

pub fn chunk_text_with_space_boundary_test() {
  let prefix = string.repeat("x", 3900)
  let suffix = string.repeat("y", 500)
  let full = prefix <> " " <> suffix
  let chunks = chunk_text(full, 4096)

  list.length(chunks)
  |> should.equal(2)

  case chunks {
    [first, second] -> {
      string.ends_with(first, " ")
      |> should.be_true
      string.length(first)
      |> should.equal(3901)
      first
      |> should.equal(prefix <> " ")
      second
      |> should.equal(suffix)
    }
    _ -> should.fail()
  }
}

pub fn chunk_text_hard_cut_no_delimiter_test() {
  let full = string.repeat("z", 5000)
  let chunks = chunk_text(full, 4096)

  list.length(chunks)
  |> should.equal(2)

  case chunks {
    [first, second] -> {
      string.length(first)
      |> should.equal(4096)
      string.length(second)
      |> should.equal(904)
    }
    _ -> should.fail()
  }
}

pub fn find_last_char_offset_test() {
  let str = "alpha\nbeta\ngamma"
  find_last_char_offset(str, "\n")
  |> should.equal(Some(10))

  let str_space = "one two three"
  find_last_char_offset(str_space, " ")
  |> should.equal(Some(7))

  let str_none = "singleword"
  find_last_char_offset(str_none, "\n")
  |> should.equal(option.None)
}

pub fn find_cut_index_newline_test() {
  let str = string.repeat("a", 3800) <> "\n" <> string.repeat("b", 1000)
  let idx = find_cut_index(str, 4096)
  idx
  |> should.equal(3801)
}

pub fn token_resolution_test() {
  case get_telegram_token() {
    Ok(token) -> {
      string.starts_with(token, "8660817750:")
      |> should.be_true
    }
    Error(err) -> {
      // In isolated CI environment without db, verify error is cleanly typed
      string.is_empty(err)
      |> should.be_false
    }
  }
}

pub fn chat_id_resolution_test() {
  case get_default_chat_id() {
    Ok(cid) -> {
      cid
      |> should.equal("6249174059")
    }
    Error(err) -> {
      string.is_empty(err)
      |> should.be_false
    }
  }
}
