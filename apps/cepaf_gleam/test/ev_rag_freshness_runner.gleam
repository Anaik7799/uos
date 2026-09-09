import rag_cache_mesh_test

pub fn main() {
  rag_cache_mesh_test.new_cache_mesh_test()
  rag_cache_mesh_test.dot_product_and_norm_test()
  rag_cache_mesh_test.cosine_similarity_test()
  rag_cache_mesh_test.exact_and_semantic_lookup_test()
  rag_cache_mesh_test.record_hit_and_miss_test()
  rag_cache_mesh_test.lru_capacity_and_expiry_test()
  rag_cache_mesh_test.vector_refresh_test()
  rag_cache_mesh_test.expired_lookup_is_not_returned_as_a_hit_test()
  rag_cache_mesh_test.put_refuses_negative_counts_and_oversize_vectors_test()
  rag_cache_mesh_test.refresh_updates_the_freshness_observation_test()
  rag_cache_mesh_test.refresh_refuses_an_empty_vector_test()
}
