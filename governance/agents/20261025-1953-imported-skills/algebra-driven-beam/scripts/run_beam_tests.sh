#!/usr/bin/env bash
# Compile the given .erl files (two-pass so behaviour info resolves cleanly)
# and run their eunit suites. Usage: run_beam_tests.sh file1.erl [file2.erl ...]
set -u
command -v erlc >/dev/null 2>&1 || {
  echo "No Erlang toolchain. Install one, e.g.: apt-get install -y erlang-base erlang-eunit erlang-dev" >&2
  exit 1
}
OUT="$(mktemp -d)"
# Pass 1: get all .beam files in place (behaviour warnings expected, ignored).
erlc -o "$OUT" "$@" 2>/dev/null || erlc -o "$OUT" "$@" || exit 1
# Pass 2: recompile with the output dir on the path -> behaviours verified.
erlc -pa "$OUT" -o "$OUT" "$@" || exit 1
MODS=$(for f in "$@"; do basename "$f" .erl; done | paste -sd, -)
erl -noshell -pa "$OUT" -eval "
  case eunit:test([$MODS], [verbose]) of
    ok -> halt(0);
    _  -> halt(1)
  end."
