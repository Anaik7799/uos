pub type HolonLevel {
  Atomic
  Molecular
  Organism
  Ecosystem
}

pub type RhetoricalFunction {
  Axiom
  Hypothesis
  Evidence
}

pub type KnowledgeNode {
  KnowledgeNode(
    id: String,
    title: String,
    level: HolonLevel,
    rhetorical: RhetoricalFunction,
    entropy: Float,
    drift: Float,
    tags: List(String),
  )
}

pub type KnowledgeLink {
  KnowledgeLink(source_id: String, target_id: String, relation_type: String)
}

pub fn level_to_string(level: HolonLevel) -> String {
  case level {
    Atomic -> "atomic"
    Molecular -> "molecular"
    Organism -> "organism"
    Ecosystem -> "ecosystem"
  }
}

pub fn rhetorical_to_string(r: RhetoricalFunction) -> String {
  case r {
    Axiom -> "axiom"
    Hypothesis -> "hypothesis"
    Evidence -> "evidence"
  }
}
