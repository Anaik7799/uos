type digest = string
type digest_error = Invalid_digest

let is_lower_hex = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let digest value =
  if String.length value = 64 && String.for_all is_lower_hex value then Ok value
  else Error Invalid_digest

let digest_to_hex value = value

type detector_authority = {
  identity : Jj_id.Executable.t;
  ruleset : digest;
}

let detector_authority ~identity ~ruleset = { identity; ruleset }

type category =
  | Credential
  | Authentication_header
  | Private_key
  | Access_token
  | Session_material
  | Credential_bearing_remote
  | Other_sensitive

type confidence = Possible | Probable | Certain

type location_scope =
  | Source_object
  | Patch_payload
  | Description_payload
  | Operation_log_payload
  | Remote_payload

type redacted_location = { scope : location_scope; ordinal : int }
type location_error = Negative_ordinal | Ordinal_limit_exceeded

let maximum_location_ordinal = 1_000_000

let redacted_location ~scope ~ordinal =
  if ordinal < 0 then Error Negative_ordinal
  else if ordinal > maximum_location_ordinal then Error Ordinal_limit_exceeded
  else Ok { scope; ordinal }

type finding = {
  detector : detector_authority;
  category : category;
  location : redacted_location;
  confidence : confidence;
  evidence : digest;
}

let finding ~detector ~category ~location ~confidence ~evidence =
  { detector; category; location; confidence; evidence }

let category_key = function
  | Credential -> "credential"
  | Authentication_header -> "authentication-header"
  | Private_key -> "private-key"
  | Access_token -> "access-token"
  | Session_material -> "session-material"
  | Credential_bearing_remote -> "credential-bearing-remote"
  | Other_sensitive -> "other-sensitive"

let confidence_key = function
  | Possible -> "possible"
  | Probable -> "probable"
  | Certain -> "certain"

let location_scope_key = function
  | Source_object -> "source-object"
  | Patch_payload -> "patch-payload"
  | Description_payload -> "description-payload"
  | Operation_log_payload -> "operation-log-payload"
  | Remote_payload -> "remote-payload"

let finding_fields finding =
  [ Jj_id.Executable.to_string finding.detector.identity;
    finding.detector.ruleset;
    category_key finding.category;
    location_scope_key finding.location.scope;
    string_of_int finding.location.ordinal;
    confidence_key finding.confidence;
    finding.evidence ]

let sha256 fields =
  Jj_id.length_frame fields
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let finding_key finding = Jj_id.length_frame (finding_fields finding)

type scan = { findings : finding list; digest : digest }
type scan_error = Too_many_findings | Duplicate_finding

let maximum_findings = 1024

let rec has_adjacent_duplicate = function
  | left :: (right :: _ as rest) ->
      String.equal (finding_key left) (finding_key right)
      || has_adjacent_duplicate rest
  | _ -> false

let scan ~findings =
  if List.length findings > maximum_findings then Error Too_many_findings
  else
    let findings = List.sort (fun left right ->
      String.compare (finding_key left) (finding_key right)) findings in
    if has_adjacent_duplicate findings then Error Duplicate_finding
    else
      let framed = List.map finding_key findings in
      Ok { findings; digest = sha256 ("jj-secret-scan-v1" :: framed) }

let finding_count scan = List.length scan.findings
let canonical_digest scan = scan.digest

let safe_summary scan =
  Jj_id.length_frame
    [ "secret-scan"; string_of_int (finding_count scan); scan.digest ]

let source_digest =
  sha256
    [ "jj-secret-scan-authority-v1";
      "detector-identity"; "detector-ruleset"; "category";
      "structured-redacted-location"; "confidence"; "evidence-digest";
      "maximum-findings=1024"; "input-order-independent";
      "duplicate-refusal"; "no-secret-input-surface" ]

module For_test = struct
  type mutation =
    | Detector_identity
    | Detector_ruleset
    | Category
    | Location_scope
    | Location_ordinal
    | Confidence
    | Evidence_digest

  let finding_digest finding = sha256 (finding_fields finding)

  let finding_digest_with_mutation finding mutation =
    let fields = finding_fields finding in
    let index = match mutation with
      | Detector_identity -> 0
      | Detector_ruleset -> 1
      | Category -> 2
      | Location_scope -> 3
      | Location_ordinal -> 4
      | Confidence -> 5
      | Evidence_digest -> 6
    in
    fields
    |> List.mapi (fun current value ->
         if current = index then "mutated:" ^ value else value)
    |> sha256
end
