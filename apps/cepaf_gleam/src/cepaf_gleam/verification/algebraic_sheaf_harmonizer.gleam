//// Algebraic Sheaf Harmonizer for Unified Web & Site Verification
////
//// Formulates multi-page UI state verification as sheaf gluing conditions over
//// open route topologies. Local sections agree on boundaries when their shared
//// state digests match.

import gleam/list

pub type LocalSection {
  LocalSection(page_route: String, shared_state_digest: String)
}

pub type SheafGluingVerdict {
  GluingSuccess(canonical_digest: String)
  GluingInconsistency(message: String)
}

pub fn check_pairwise_agreement(s1: LocalSection, s2: LocalSection) -> Bool {
  s1.shared_state_digest == s2.shared_state_digest
}

pub fn glue_sections(sections: List(LocalSection)) -> SheafGluingVerdict {
  case sections {
    [] -> GluingInconsistency("Empty section list")
    [first, ..rest] -> {
      let all_agree =
        list.all(rest, fn(section) { check_pairwise_agreement(first, section) })
      case all_agree {
        True -> GluingSuccess(first.shared_state_digest)
        False -> GluingInconsistency("Sections disagree on mutual boundary")
      }
    }
  }
}
