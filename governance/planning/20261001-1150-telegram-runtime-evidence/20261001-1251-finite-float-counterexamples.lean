-- Pinned Float search across the actual ten chart indices.
#eval Id.run do
 let mut found : List (Nat × Nat × Nat × UInt64 × UInt64 × UInt64) := []
 for i in List.range 10 do
  for j in List.range 10 do
   for k in List.range 10 do
    let scale (a b : Nat) : Float := (Float.ofNat b + 1.0) / (Float.ofNat a + 1.0)
    let lhs := ((0.1 : Float) * scale i j) * scale j k
    let rhs := (0.1 : Float) * scale i k
    if lhs.toBits != rhs.toBits then
     found := found ++ [(i,j,k,lhs.toBits,rhs.toBits,(lhs-rhs).toBits)]
 return found.take 8
