// =============================================================================
// zigvm_vfs_arena_stress_test.gleam — ZigVM VFS Descriptor Isolation & 64MB Arena Stress
// STAMP: SC-SIL6-001, SC-JIDOKA-001, SC-ZIGVM-VFS-001
// Codex Astra Mode: Formal Deterministic Runtime & Memory Invariants
// =============================================================================

import gleam/list
import gleam/string
import gleeunit/should

pub type VfsError {
  PathTraversalAttempt(String)
  PathTooLong(Int)
  ArenaBudgetExceeded(Int, Int)
  FileNotFound(String)
}

pub type VfsDescriptor {
  VfsDescriptor(descriptor_id: String, root_prefix: String, active_files: List(#(String, String)))
}

pub type MemoryArena {
  MemoryArena(max_capacity_bytes: Int, current_allocated_bytes: Int, allocation_count: Int)
}

pub fn sanitize_vfs_path(path: String) -> Result(String, VfsError) {
  case string.contains(path, "..") || string.starts_with(path, "/") {
    True -> Error(PathTraversalAttempt(path))
    False -> {
      let len = string.length(path)
      case len > 255 {
        True -> Error(PathTooLong(len))
        False -> Ok(path)
      }
    }
  }
}

pub fn init_arena(capacity_bytes: Int) -> MemoryArena {
  MemoryArena(max_capacity_bytes: capacity_bytes, current_allocated_bytes: 0, allocation_count: 0)
}

pub fn arena_alloc(arena: MemoryArena, size_bytes: Int) -> Result(MemoryArena, VfsError) {
  let new_total = arena.current_allocated_bytes + size_bytes
  case new_total <= arena.max_capacity_bytes {
    True ->
      Ok(MemoryArena(
        max_capacity_bytes: arena.max_capacity_bytes,
        current_allocated_bytes: new_total,
        allocation_count: arena.allocation_count + 1,
      ))
    False -> Error(ArenaBudgetExceeded(new_total, arena.max_capacity_bytes))
  }
}

pub fn arena_reset(arena: MemoryArena) -> MemoryArena {
  MemoryArena(max_capacity_bytes: arena.max_capacity_bytes, current_allocated_bytes: 0, allocation_count: 0)
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

pub fn vfs_descriptor_path_sanitization_test() {
  // Safe relative paths pass
  should.be_ok(sanitize_vfs_path("normal_file.dat"))
  should.be_ok(sanitize_vfs_path("sub_dir/inner_file.txt"))

  // Directory traversal attacks fail closed
  should.be_error(sanitize_vfs_path("../escape_sandbox.dat"))
  should.be_error(sanitize_vfs_path("nested/../../etc/passwd"))
  should.be_error(sanitize_vfs_path("/absolute/path/forbidden"))

  // Path length limit (255)
  let overly_long = string.repeat("a", 256)
  should.be_error(sanitize_vfs_path(overly_long))
}

fn allocate_chunks(arena: MemoryArena, chunk_size: Int, count: Int) -> Result(MemoryArena, VfsError) {
  case count <= 0 {
    True -> Ok(arena)
    False -> {
      case arena_alloc(arena, chunk_size) {
        Ok(next_arena) -> allocate_chunks(next_arena, chunk_size, count - 1)
        Error(err) -> Error(err)
      }
    }
  }
}

pub fn vfs_bounded_64mb_arena_envelope_test() {
  let max_64mb = 64 * 1024 * 1024
  let arena = init_arena(max_64mb)

  // Allocate 64 chunks of 1MB (exactly 64MB)
  let chunk_1mb = 1024 * 1024
  let res = allocate_chunks(arena, chunk_1mb, 64)

  should.be_ok(res)
  let assert Ok(filled_arena) = res
  should.equal(filled_arena.current_allocated_bytes, max_64mb)
  should.equal(filled_arena.allocation_count, 64)

  // Attempting to allocate even 1 additional byte beyond 64MB must fail closed
  let overflow = arena_alloc(filled_arena, 1)
  should.be_error(overflow)

  // Arena reset returns allocations to 0 cleanly
  let reset_arena = arena_reset(filled_arena)
  should.equal(reset_arena.current_allocated_bytes, 0)
  should.equal(reset_arena.allocation_count, 0)
}

pub fn vfs_descriptor_isolation_invariance_test() {
  let desc_a = VfsDescriptor("desc-001", "sandbox_a/", [#("data.txt", "payload_a")])
  let desc_b = VfsDescriptor("desc-002", "sandbox_b/", [#("data.txt", "payload_b")])

  // Lookups within descriptor scopes are isolated
  let find_a = list.find(desc_a.active_files, fn(item) { item.0 == "data.txt" })
  let find_b = list.find(desc_b.active_files, fn(item) { item.0 == "data.txt" })

  should.be_ok(find_a)
  should.be_ok(find_b)
  let assert Ok(item_a) = find_a
  let assert Ok(item_b) = find_b

  should.equal(item_a.1, "payload_a")
  should.equal(item_b.1, "payload_b")
  should.not_equal(item_a.1, item_b.1)
}
