//// Distributed Tensor Monoids for Modular MAX / Mojo (SC-FEAT-IMPL-001)
//// #fractal-l1 #fractal-l3 #zero-muda #tailscale-web
////
//// Formalizes tensor spaces as a symmetric monoidal category (Vect, (x), I),
//// providing zero-copy tensor slicing, tensor concatenation, and RDMA memory fence validation.

import gleam/list
import gleam/string

pub type TensorShape {
  TensorShape(dims: List(Int), element_size_bytes: Int)
}

pub type TensorSlice {
  TensorSlice(
    buffer_id: String,
    offset_bytes: Int,
    length_bytes: Int,
    shape: TensorShape,
  )
}

pub type RdmaFenceVerdict {
  FenceGranted(channel_id: String, aligned_bytes: Int)
  FenceDenied(reason: String)
}

/// Computes the total byte footprint of a tensor shape.
pub fn compute_tensor_bytes(shape: TensorShape) -> Int {
  let product = list.fold(shape.dims, 1, fn(acc, dim) { acc * dim })
  product * shape.element_size_bytes
}

/// Evaluates symmetric monoidal tensor concatenation (T1 (x) T2).
pub fn tensor_tensor_product(
  s1: TensorSlice,
  s2: TensorSlice,
) -> Result(TensorSlice, String) {
  case s1.shape.element_size_bytes == s2.shape.element_size_bytes {
    True -> {
      let total_bytes = s1.length_bytes + s2.length_bytes
      let combined_shape =
        TensorShape(
          dims: [s1.length_bytes + s2.length_bytes],
          element_size_bytes: s1.shape.element_size_bytes,
        )
      Ok(TensorSlice(
        buffer_id: s1.buffer_id <> "_x_" <> s2.buffer_id,
        offset_bytes: 0,
        length_bytes: total_bytes,
        shape: combined_shape,
      ))
    }
    False ->
      Error("Incompatible tensor element sizes for monoidal concatenation")
  }
}

/// Validates memory alignment for zero-copy RDMA buffer exchange.
pub fn validate_rdma_fence(
  slice: TensorSlice,
  node_serial: String,
) -> RdmaFenceVerdict {
  let is_host_nvme = string.contains(node_serial, "25503L801736")
  case is_host_nvme {
    True ->
      FenceDenied("Access to root OS NVMe 25503L801736 is strictly barred")
    False -> {
      let is_64byte_aligned = slice.offset_bytes % 64 == 0
      case is_64byte_aligned {
        True ->
          FenceGranted(
            channel_id: "rdma-channel-" <> slice.buffer_id,
            aligned_bytes: slice.length_bytes,
          )
        False ->
          FenceDenied("Buffer offset is not 64-byte aligned for zero-copy RDMA")
      }
    }
  }
}
