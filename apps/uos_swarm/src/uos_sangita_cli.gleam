//// Saṅgīta CLI: `gleam run -m uos_sangita_cli -- <command> ...`.
////
//// Commands:
////   sing <ledger.jsonl> [--raga-file <file.json> | raga] [tala] [tempo] [out.wav|out.mid]
////     Compose the board ledger, print its sargam notation, and (when an
////     output path is given) write a WAV (three-voice mix) or, by `.mid`/
////     `.midi` extension, a Standard MIDI File.
////   sing-sargam <notation.txt> [raga] [tala] [tempo] [out.wav|out.mid]
////     Parse a hand-authored sargam-notation composition (one tāla cycle
////     per line; `-` rest, `~` tie) against `raga`, validating every note,
////     then render it the same way as `sing`.
////   sing-state <ledger.jsonl> [tala] [tempo] [out.wav|out.mid]
////     Compose the board ledger with the rāga and mix dynamics chosen by
////     its own current harmony (see `sangita.raga_and_mix_for_state`).
////   harmony <ledger.jsonl>
////     Print the board's harmony measurement as JSON.
////   frequencies [sa_hz]
////     Print a table of every svara/variant over three octaves.
////   raga-for <hour> <mode>
////     Print the name of the rāga selected for UTC hour `hour` under `mode`.
////   raga list
////     Print the full ten-rāga catalogue (thaat, āroha/avaroha, vādi/
////     samvādi, time, mood).
////   raga show <name>
////     Print one catalogue rāga.
////   raga define <file.json>
////     Parse and validate a hand-authored rāga definition, printing it or
////     the exact validation error.
////
//// STAMP: SC-SANGITA-CLI-001.

import argv
import gleam/float
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/raga
import uos_swarm/sangita

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

/// Reuses the board's own `uos_swarm_ffi:file_write/2` (which accepts any
/// binary) under a `BitArray`-typed Gleam signature, so a WAV or MIDI file
/// can be written without adding a new Erlang function to
/// `uos_swarm_ffi.erl`.
@external(erlang, "uos_swarm_ffi", "file_write")
fn file_write_bits(path: String, content: BitArray) -> Result(Nil, String)

fn list_get(xs: List(String), i: Int, default: String) -> String {
  case list.drop(xs, i) {
    [x, ..] -> x
    [] -> default
  }
}

fn list_get_opt(xs: List(String), i: Int) -> Option(String) {
  case list.drop(xs, i) {
    [x, ..] -> Some(x)
    [] -> None
  }
}

/// Pull `flag value` out of `args` wherever it appears, returning the value
/// (if present) and the remaining arguments in order.
fn extract_flag(
  args: List(String),
  flag: String,
) -> #(Option(String), List(String)) {
  case args {
    [] -> #(None, [])
    [a, v, ..rest] ->
      case a == flag {
        True -> #(Some(v), rest)
        False -> {
          let #(found, remaining) = extract_flag([v, ..rest], flag)
          #(found, [a, ..remaining])
        }
      }
    [a, ..rest] -> {
      let #(found, remaining) = extract_flag(rest, flag)
      #(found, [a, ..remaining])
    }
  }
}

fn load_messages(path: String) -> Result(List(board.Message), String) {
  use text <- result.try(board.file_read(path))
  let #(messages, _bad_lines) = board.from_jsonl(text)
  Ok(messages)
}

fn is_midi_path(path: String) -> Bool {
  string.ends_with(path, ".mid") || string.ends_with(path, ".midi")
}

fn render_bytes(
  b: sangita.Bandish,
  path: String,
  mix: sangita.MixLevels,
) -> BitArray {
  case is_midi_path(path) {
    True -> sangita.to_midi(b, 60)
    False -> sangita.to_wav_mixed(b, 22_050, 240.0, mix)
  }
}

fn write_output(
  b: sangita.Bandish,
  out: Option(String),
  mix: sangita.MixLevels,
) -> Result(Nil, String) {
  case out {
    None -> Ok(Nil)
    Some(path) -> {
      let bytes = render_bytes(b, path, mix)
      use _ <- result.try(
        file_write_bits(path, bytes)
        |> result.map_error(fn(e) { "write failed: " <> e }),
      )
      io.println(
        "wrote " <> path <> " (" <> int.to_string(byte_len(bytes)) <> " bytes)",
      )
      Ok(Nil)
    }
  }
}

@external(erlang, "erlang", "byte_size")
fn byte_len(b: BitArray) -> Int

fn cmd_sing(args: List(String)) -> Result(Nil, String) {
  let #(raga_file, rest0) = extract_flag(args, "--raga-file")
  case rest0 {
    [ledger, ..rest] -> {
      use r <- result.try(case raga_file {
        Some(path) -> {
          use text <- result.try(board.file_read(path))
          sangita.parse_raga_json(text)
        }
        None -> Ok(sangita.raga_by_name(list_get(rest, 0, "yaman")))
      })
      let offset = case raga_file {
        Some(_) -> 0
        None -> 1
      }
      let tala = sangita.tala_by_name(list_get(rest, offset, "teentaal"))
      let tempo =
        list_get(rest, offset + 1, "80") |> int.parse |> result.unwrap(80)
      let out = list_get_opt(rest, offset + 2)
      use messages <- result.try(load_messages(ledger))
      let bandish = sangita.compose(messages, r, tala, tempo, 16)
      io.println(sangita.to_sargam(bandish))
      write_output(bandish, out, sangita.default_mix())
    }
    _ ->
      Error(
        "usage: sing <ledger.jsonl> [--raga-file <file.json> | raga] [tala] [tempo] [out.wav|out.mid]",
      )
  }
}

fn cmd_sing_sargam(args: List(String)) -> Result(Nil, String) {
  case args {
    [path, ..rest] -> {
      let r = sangita.raga_by_name(list_get(rest, 0, "yaman"))
      let tala = sangita.tala_by_name(list_get(rest, 1, "teentaal"))
      let tempo = list_get(rest, 2, "80") |> int.parse |> result.unwrap(80)
      let out = list_get_opt(rest, 3)
      use text <- result.try(board.file_read(path))
      use notes <- result.try(sangita.parse_sargam(text, r))
      let bandish =
        sangita.bandish_of_notes(
          r,
          tala,
          tempo,
          notes,
          sangita.neutral_harmony(r),
        )
      io.println(sangita.to_sargam(bandish))
      write_output(bandish, out, sangita.default_mix())
    }
    _ ->
      Error(
        "usage: sing-sargam <notation.txt> [raga] [tala] [tempo] [out.wav|out.mid]",
      )
  }
}

fn cmd_sing_state(args: List(String)) -> Result(Nil, String) {
  case args {
    [ledger, ..rest] -> {
      let tala = sangita.tala_by_name(list_get(rest, 0, "teentaal"))
      let tempo = list_get(rest, 1, "80") |> int.parse |> result.unwrap(80)
      let out = list_get_opt(rest, 2)
      use messages <- result.try(load_messages(ledger))
      let now = list.fold(messages, 0, fn(acc, m) { int.max(acc, m.ts_us) })
      let h = sangita.harmony(messages, now)
      let #(r, mix) = sangita.raga_and_mix_for_state(h)
      let bandish = sangita.compose(messages, r, tala, tempo, 16)
      io.println(sangita.to_sargam(bandish))
      io.println(
        "mix: melody="
        <> float.to_string(mix.melody)
        <> " drone="
        <> float.to_string(mix.drone)
        <> " percussion="
        <> float.to_string(mix.percussion),
      )
      write_output(bandish, out, mix)
    }
    _ ->
      Error("usage: sing-state <ledger.jsonl> [tala] [tempo] [out.wav|out.mid]")
  }
}

fn cmd_harmony(args: List(String)) -> Result(Nil, String) {
  case args {
    [ledger] -> {
      use messages <- result.try(load_messages(ledger))
      let now = list.fold(messages, 0, fn(acc, m) { int.max(acc, m.ts_us) })
      let h = sangita.harmony(messages, now)
      io.println(json.to_string(sangita.harmony_to_json(h)))
      Ok(Nil)
    }
    _ -> Error("usage: harmony <ledger.jsonl>")
  }
}

fn cmd_frequencies(args: List(String)) -> Result(Nil, String) {
  let sa_hz = list_get(args, 0, "240.0") |> float.parse |> result.unwrap(240.0)
  list.each(sangita.all_octaves, fn(oct) {
    list.each(sangita.all_swaras, fn(s) {
      list.each(sangita.all_variants, fn(v) {
        let freq = sangita.frequency(s, v, oct, sa_hz)
        io.println(
          sangita.swara_label(s)
          <> "/"
          <> sangita.variant_label(v)
          <> " oct="
          <> int.to_string(oct)
          <> " hz="
          <> float.to_string(freq),
        )
      })
    })
  })
  Ok(Nil)
}

fn cmd_raga_for(args: List(String)) -> Result(Nil, String) {
  case args {
    [hour_s, mode] -> {
      use hour <- result.try(
        int.parse(hour_s) |> result.replace_error("bad hour: " <> hour_s),
      )
      let h =
        sangita.Harmony(
          1.0,
          [],
          [],
          sangita.prahar_of_hour(hour),
          sangita.raga_name_for_hour(hour),
        )
      io.println(sangita.raga_for_harmony(h, mode).name)
      Ok(Nil)
    }
    _ -> Error("usage: raga-for <hour> <mode>")
  }
}

fn pitch_line(pairs: List(#(sangita.Swara, sangita.Variant))) -> String {
  pairs
  |> list.map(fn(p) {
    sangita.sargam_syllable(sangita.Note(p.0, p.1, 0, 1, 1, ""))
  })
  |> string.join("  ")
}

fn raga_summary(r: sangita.Raga) -> String {
  "== "
  <> r.name
  <> " ==\nthaat:    "
  <> raga.thaat_label(r.thaat)
  <> "\ntime:     "
  <> raga.time_of_day_label(r.time)
  <> "\nmood:     "
  <> r.mood
  <> "\naroha:    "
  <> pitch_line(r.aroha)
  <> "\navaroha:  "
  <> pitch_line(r.avaroha)
  <> "\nvadi:     "
  <> raga.swara_label(r.vadi)
  <> "\nsamvadi:  "
  <> raga.swara_label(r.samvadi)
}

fn cmd_raga(args: List(String)) -> Result(Nil, String) {
  case args {
    ["list"] -> {
      list.each(raga.ragas(), fn(r) {
        io.println(raga_summary(r))
        io.println("")
      })
      Ok(Nil)
    }
    ["show", name] -> {
      use r <- result.try(sangita.raga_by_name_strict(name))
      io.println(raga_summary(r))
      Ok(Nil)
    }
    ["define", path] -> {
      use text <- result.try(board.file_read(path))
      use r <- result.try(sangita.parse_raga_json(text))
      io.println("valid rāga:")
      io.println(raga_summary(r))
      Ok(Nil)
    }
    _ -> Error("usage: raga list | raga show <name> | raga define <file.json>")
  }
}

fn execute(arguments: List(String)) -> Result(Nil, String) {
  case arguments {
    ["sing", ..rest] -> cmd_sing(rest)
    ["sing-sargam", ..rest] -> cmd_sing_sargam(rest)
    ["sing-state", ..rest] -> cmd_sing_state(rest)
    ["harmony", ..rest] -> cmd_harmony(rest)
    ["frequencies", ..rest] -> cmd_frequencies(rest)
    ["raga-for", ..rest] -> cmd_raga_for(rest)
    ["raga", ..rest] -> cmd_raga(rest)
    _ ->
      Error(
        "usage: sing <ledger.jsonl> [--raga-file <file.json> | raga] [tala] [tempo] [out.wav|out.mid]"
        <> " | sing-sargam <notation.txt> [raga] [tala] [tempo] [out.wav|out.mid]"
        <> " | sing-state <ledger.jsonl> [tala] [tempo] [out.wav|out.mid]"
        <> " | harmony <ledger.jsonl> | frequencies [sa_hz] | raga-for <hour> <mode>"
        <> " | raga list | raga show <name> | raga define <file.json>",
      )
  }
}

pub fn main() -> Nil {
  case execute(argv.load().arguments) {
    Ok(_) -> Nil
    Error(reason) -> {
      io.println("error: " <> reason)
      halt(1)
    }
  }
}
