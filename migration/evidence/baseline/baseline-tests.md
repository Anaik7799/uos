# Baseline Test Matrix Before UOS Migration

| System | Test Command | Declared Tests | Pass Count | Status | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `c3i` (Gleam) | `gleam test` | 9,762 | 9,762 | PASS (Historical) | Isolated OTP 29 profile required |
| `zigvm` (Zig) | `zig build test` | 1,420 | 1,420 | PASS (Historical) | Separately built runtime |
| `harness-bionic` | `dune runtest` | 380 | 380 | PASS (Historical) | Hermes evidence harness |
| `planning_checks` | `gleam run -m planning_checks` | 31 | 31 | PASS (Observed) | Pre-read hold active |
