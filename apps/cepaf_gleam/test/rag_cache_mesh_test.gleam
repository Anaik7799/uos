import cepaf_gleam/knowledge/rag_cache_mesh
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn new_cache_mesh_test() {
  let mesh = rag_cache_mesh.new(50, 0.88)
  mesh.max_capacity |> should.equal(50)
  mesh.similarity_threshold |> should.equal(0.88)
  mesh.total_hits |> should.equal(0)
  mesh.total_misses |> should.equal(0)
  mesh.total_tokens_saved |> should.equal(0)
  rag_cache_mesh.calculate_hit_ratio(mesh) |> should.equal(0.0)
}

pub fn dot_product_and_norm_test() {
  let v1 = [1.0, 2.0, 3.0]
  let v2 = [4.0, 5.0, 6.0]
  // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32.0
  rag_cache_mesh.dot_product(v1, v2) |> should.equal(32.0)

  let v_unit = [3.0, 4.0]
  // norm = sqrt(9 + 16) = 5.0
  let norm = rag_cache_mesh.vector_norm(v_unit)
  should.be_true(norm >=. 4.99 && norm <=. 5.01)
}

pub fn cosine_similarity_test() {
  let v1 = [1.0, 0.0, 0.0]
  let v2 = [1.0, 0.0, 0.0]
  let v_orth = [0.0, 1.0, 0.0]

  // Identical vectors should have similarity ~1.0
  let sim_same = rag_cache_mesh.cosine_similarity(v1, v2)
  should.be_true(sim_same >=. 0.99 && sim_same <=. 1.01)

  // Orthogonal vectors should have similarity ~0.0
  let sim_orth = rag_cache_mesh.cosine_similarity(v1, v_orth)
  should.be_true(sim_orth >=. -0.01 && sim_orth <=. 0.01)
}

pub fn exact_and_semantic_lookup_test() {
  let mesh = rag_cache_mesh.new(10, 0.85)
  let v_doc = [0.8, 0.6, 0.0]
  let mesh =
    rag_cache_mesh.put(
      mesh,
      "entry-1",
      "What is Zero-Muda architecture?",
      v_doc,
      "Zero-Muda eliminates unnecessary memory allocations and foreign NIF overhead.",
      ["chunk-1", "chunk-2"],
      500,
      1000,
      3600,
    )

  // Exact lookup
  let exact_res =
    rag_cache_mesh.lookup_exact(mesh, "what is zero-muda architecture? ", 1100)
  case exact_res {
    rag_cache_mesh.CacheFresh(_, 1.0) -> Nil
    _ -> should.fail()
  }

  // Semantic lookup with close vector
  let v_query_close = [0.79, 0.61, 0.0]
  let semantic_res =
    rag_cache_mesh.lookup_semantic(
      mesh,
      "explain zero-muda design",
      v_query_close,
      1100,
    )
  case semantic_res {
    rag_cache_mesh.CacheFresh(_, _) -> Nil
    _ -> should.fail()
  }

  // Semantic lookup with distant vector should miss
  let v_query_distant = [0.0, 0.0, 1.0]
  let distant_res =
    rag_cache_mesh.lookup_semantic(
      mesh,
      "unrelated cooking query",
      v_query_distant,
      1100,
    )
  distant_res |> should.equal(rag_cache_mesh.CacheMissing)
}

pub fn record_hit_and_miss_test() {
  let mesh = rag_cache_mesh.new(10, 0.85)
  let mesh =
    rag_cache_mesh.put(
      mesh,
      "entry-1",
      "Explain Lyapunov trend detection",
      [1.0, 0.0],
      "Lyapunov proofs detect windowed stability.",
      ["chunk-3"],
      1000,
      1000,
      3600,
    )

  let mesh = rag_cache_mesh.record_hit(mesh, "entry-1", 1050)
  mesh.total_hits |> should.equal(1)
  mesh.total_tokens_saved |> should.equal(1000)
  should.be_true(mesh.total_cost_saved_usd >. 0.0)

  let mesh = rag_cache_mesh.record_miss(mesh)
  mesh.total_misses |> should.equal(1)
  rag_cache_mesh.calculate_hit_ratio(mesh) |> should.equal(0.5)
}

pub fn lru_capacity_and_expiry_test() {
  let mesh = rag_cache_mesh.new(2, 0.85)
  let mesh =
    rag_cache_mesh.put(mesh, "e1", "q1", [1.0, 0.0], "r1", [], 100, 1000, 100)
  let mesh =
    rag_cache_mesh.put(mesh, "e2", "q2", [0.0, 1.0], "r2", [], 200, 1100, 500)
  let mesh =
    rag_cache_mesh.put(mesh, "e3", "q3", [0.5, 0.5], "r3", [], 300, 1200, 500)

  // Cap should be 2
  let metrics = rag_cache_mesh.to_summary_metrics(mesh)
  metrics.entry_count |> should.equal(2)

  // Expiry check: e1 was evicted or if present at ts 1150 is expired
  let active = rag_cache_mesh.evict_expired(mesh, 1300)
  should.be_true(list_length_helper(active.entries) <= 2)
}

fn list_length_helper(l: List(a)) -> Int {
  case l {
    [] -> 0
    [_, ..rest] -> 1 + list_length_helper(rest)
  }
}

pub fn vector_refresh_test() {
  let mesh = rag_cache_mesh.new(5, 0.85)
  let mesh =
    rag_cache_mesh.put(
      mesh,
      "e-refresh",
      "Dynamic schema query",
      [1.0, 0.0],
      "Initial response",
      [],
      400,
      1000,
      3600,
    )

  let mesh = rag_cache_mesh.refresh_vector(mesh, "e-refresh", [0.0, 1.0], 1500)
  let entry_res =
    rag_cache_mesh.lookup_exact(mesh, "Dynamic schema query", 1500)
  case entry_res {
    rag_cache_mesh.CacheFresh(e, _) -> {
      e.embedding |> should.equal([0.0, 1.0])
      e.last_accessed_ts |> should.equal(1500)
    }
    _ -> should.fail()
  }
}

pub fn expired_lookup_is_not_returned_as_a_hit_test() {
  let mesh = rag_cache_mesh.new(5, 0.85)
  let mesh =
    rag_cache_mesh.put(
      mesh,
      "expired",
      "freshness query",
      [1.0, 0.0],
      "old response",
      [],
      10,
      1000,
      10,
    )

  rag_cache_mesh.lookup_exact(mesh, "freshness query", 1010)
  |> should.equal(
    rag_cache_mesh.CacheStale(rag_cache_mesh.CacheEntry(
      "expired",
      "freshness query",
      [1.0, 0.0],
      "old response",
      [],
      10,
      0.0,
      1,
      1000,
      1000,
      1000,
      10,
    )),
  )
}

pub fn put_refuses_negative_counts_and_oversize_vectors_test() {
  let mesh = rag_cache_mesh.new(5, 0.85)
  let negative =
    rag_cache_mesh.put(
      mesh,
      "negative",
      "negative token query",
      [1.0],
      "response",
      [],
      -1,
      1000,
      60,
    )
  list_length_helper(negative.entries) |> should.equal(0)

  let oversize =
    rag_cache_mesh.put(
      mesh,
      "oversize",
      "oversize vector query",
      repeated_vector(1025),
      "response",
      [],
      1,
      1000,
      60,
    )
  list_length_helper(oversize.entries) |> should.equal(0)
}

pub fn refresh_updates_the_freshness_observation_test() {
  let mesh = rag_cache_mesh.new(5, 0.85)
  let mesh =
    rag_cache_mesh.put(
      mesh,
      "refresh-ttl",
      "refresh freshness query",
      [1.0, 0.0],
      "response",
      [],
      10,
      1000,
      100,
    )
  let refreshed =
    rag_cache_mesh.refresh_vector(mesh, "refresh-ttl", [0.0, 1.0], 1200)

  // A refresh must renew the observation used for TTL, not only last-accessed state.
  let active = rag_cache_mesh.evict_expired(refreshed, 1250)
  list_length_helper(active.entries) |> should.equal(1)
}

pub fn refresh_refuses_an_empty_vector_test() {
  let mesh = rag_cache_mesh.new(5, 0.85)
  let mesh =
    rag_cache_mesh.put(
      mesh,
      "refresh-invalid",
      "refresh invalid query",
      [1.0, 0.0],
      "response",
      [],
      10,
      1000,
      60,
    )
  let refreshed =
    rag_cache_mesh.refresh_vector(mesh, "refresh-invalid", [], 1100)
  case rag_cache_mesh.lookup_exact(refreshed, "refresh invalid query", 1050) {
    rag_cache_mesh.CacheFresh(entry, _) ->
      entry.embedding |> should.equal([1.0, 0.0])
    _ -> should.fail()
  }
}

fn repeated_vector(remaining: Int) -> List(Float) {
  case remaining <= 0 {
    True -> []
    False -> [1.0, ..repeated_vector(remaining - 1)]
  }
}
