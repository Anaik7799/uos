#!/usr/bin/env bash
# Run `zig test` on each given .zig file, falling back to the official
# PyPI Zig distribution when no local toolchain exists.
set -u
if command -v zig >/dev/null 2>&1; then
  ZIG=(zig)
elif python3 -c "import ziglang" 2>/dev/null; then
  ZIG=(python3 -m ziglang)
else
  echo "No zig found; installing ziglang from PyPI..." >&2
  pip install ziglang --break-system-packages -q || pip install ziglang -q || {
    echo "FATAL: could not install a Zig toolchain" >&2; exit 1; }
  ZIG=(python3 -m ziglang)
fi
echo "Toolchain: $("${ZIG[@]}" version)"
fail=0
for f in "$@"; do
  echo "== ${f} =="
  "${ZIG[@]}" test "$f" || fail=1
done
exit $fail
