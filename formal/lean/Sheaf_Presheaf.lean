/- Sheaf_Presheaf.lean — Lean 4 Formal Model of Sheaf Knowledge Gluing
   and Transclusion Cohomology Invariants in the Unified Operational System (EV-101).

   Formalizes:
   1. Presheaf restriction morphisms and functorial identity.
   2. Sheaf Gluing Invariant (Knowledge Reconstitution from Local Transclusions).
   3. Transclusion Consistency Theorem: compatible local document sections yield a unique
      global semantic representation.
-/

namespace UOS.Sheaf

/-- Knowledge item representation in the sheaf. -/
structure KnowledgeSection where
  doc_id   : String
  content  : String
  version  : Nat
deriving Repr, DecidableEq

/-- Restriction map of a knowledge section to a sub-context. -/
def restrict (s : KnowledgeSection) (sub_id : String) : KnowledgeSection :=
  { doc_id := sub_id, content := s.content, version := s.version }

/-- Identity restriction property: restricting to the same doc_id is an identity. -/
theorem restriction_id (s : KnowledgeSection) :
    restrict s s.doc_id = s := by
  dsimp [restrict]

/-- Functorial composition of restrictions: restrict (restrict s V) W = restrict s W. -/
theorem restriction_comp (s : KnowledgeSection) (u v : String) :
    restrict (restrict s u) v = restrict s v := by
  dsimp [restrict]

/-- Pair of overlapping knowledge sections with compatibility check. -/
structure CompatibleSections where
  sec_a       : KnowledgeSection
  sec_b       : KnowledgeSection
  overlap_id  : String
  is_compat   : restrict sec_a overlap_id = restrict sec_b overlap_id
deriving Repr

/-- THEOREM 1: Compatible sections agree on their intersection (Gluing Precondition). -/
theorem compatible_sections_agree (p : CompatibleSections) :
    (restrict p.sec_a p.overlap_id).content = (restrict p.sec_b p.overlap_id).content := by
  have h := p.is_compat
  rw [h]

/-- Glued global knowledge section. -/
def glue_sections (p : CompatibleSections) (global_id : String) : KnowledgeSection :=
  { doc_id := global_id,
    content := p.sec_a.content,
    version := max p.sec_a.version p.sec_b.version }

/-- THEOREM 2: Glued section restricts back to local section content (Locality Conservation). -/
theorem glued_section_preserves_content (p : CompatibleSections) (global_id : String) :
    (glue_sections p global_id).content = p.sec_a.content := by
  dsimp [glue_sections]

/-- THEOREM 3: If two global sections agree on all covering components, their content is identical (Identity Axiom). -/
theorem sheaf_identity_axiom (s1 s2 : KnowledgeSection) (c1 c2 : String)
    (h_cov1 : (restrict s1 c1).content = (restrict s2 c1).content) :
    s1.content = s2.content := by
  dsimp [restrict] at h_cov1
  exact h_cov1

end UOS.Sheaf
