//// UOS Sūtra Register (सूत्र): a register of terse aphoristic rules that state the system's
//// laws, one per real invariant enforced elsewhere in code (board.gleam signing/chains, coord.gleam
//// leases/epochs, manager.gleam health/andon, holon.gleam holarchy, agent_runtime.gleam grants,
//// tps.gleam jidoka/takt, openrouter_worker.gleam budgets, acl.gleam itself). Chapters (pāda,
//// पाद) 1..7 follow the seven holon planes in order: 1 niyantraṇa (नियन्त्रण, control),
//// 2 saṃracanā (संरचना, structure), 3 pravṛtti (प्रवृत्ति, runtime), 4 datta (दत्त, data plane),
//// 5 sandeśa (सन्देश, messaging), 6 buddhi (बुद्धि, intelligence), 7 bhāṣā (भाषा, language).
//// A sūtra is maximally terse; its English gloss is exact, not decorative. Where a classical
//// verse genuinely grounds the rule (Yoga Sūtra, Bhagavad Gītā) it is cited in `source`.
//// STAMP: SC-TUI-ACL-001, #rocha-semiotics, operator directive "maximize the use of sutras in
//// the system for communication in the system".

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string

// ---------------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------------

pub type Sutra {
  Sutra(
    id: String,
    pada: Int,
    iast: String,
    devanagari: String,
    english: String,
    aspects: List(Int),
    layer: Int,
    kinds: List(String),
    control_actions: List(String),
    source: Option(String),
  )
}

/// The seven holon planes, in pāda order.
pub const padas = [
  #(1, "niyantraṇa", "नियन्त्रण", "control"),
  #(2, "saṃracanā", "संरचना", "structure"),
  #(3, "pravṛtti", "प्रवृत्ति", "runtime"),
  #(4, "datta", "दत्त", "data plane"),
  #(5, "sandeśa", "सन्देश", "messaging"),
  #(6, "buddhi", "बुद्धि", "intelligence"),
  #(7, "bhāṣā", "भाषा", "language"),
]

/// The closed set of board kinds (`uos_swarm/board.Kind`) a sūtra may govern.
pub const allowed_kinds = [
  "Plan", "Dispatch", "Claim", "Progress", "Question", "Answer", "Report",
  "Verdict", "Andon", "Jidoka", "Integrate", "Heartbeat", "Intent", "LeaseGrant",
  "LeaseRelease", "Ack", "DeadLetter",
]

/// The closed set of STPA control action ids (`uos_swarm/stpa.model().control_actions`).
pub const allowed_control_actions = [
  "CA-audit_screen", "CA-emit_intent", "CA-enter_raw", "CA-integrate_slice",
  "CA-paint_frame", "CA-push_confirm_screen", "CA-restore_terminal",
  "CA-verify_slice", "CA-write_owned_file",
]

// ---------------------------------------------------------------------------
// Register
// ---------------------------------------------------------------------------

pub fn register() -> List(Sutra) {
  list.flatten([pada1(), pada2(), pada3(), pada4(), pada5(), pada6(), pada7()])
}

/// Pāda 1: niyantraṇa (नियन्त्रण) — control.
fn pada1() -> List(Sutra) {
  [
    Sutra(
      "S1.1",
      1,
      "saṅkalpa ūrdhvam eva gacchati, na svayaṃ kriyate",
      "सङ्कल्प ऊर्ध्वम् एव गच्छति, न स्वयं क्रियते",
      "Intent goes only upward; it is never itself enacted (the Rocha cut).",
      [3],
      0,
      ["Intent"],
      ["CA-emit_intent"],
      None,
    ),
    Sutra(
      "S1.2",
      1,
      "sandeśaḥ preṣakotpanna-kuñcikayā mudritaḥ",
      "सन्देशः प्रेषकोत्पन्नकुञ्चिकया मुद्रितः",
      "A message is signed by a key derived from its own sender, never the shared master key.",
      [7],
      0,
      [],
      [],
      None,
    ),
    Sutra(
      "S1.3",
      1,
      "paṭṭaḥ krama-vardhamāna-yugena yuktaḥ, avadhiṃ prāpya samāpyate",
      "पट्टः क्रमवर्धमानयुगेन युक्तः, अवधिं प्राप्य समाप्यते",
      "A lease is bound to a monotonically increasing epoch and ends upon reaching its expiry.",
      [9],
      1,
      ["LeaseGrant", "LeaseRelease"],
      [],
      None,
    ),
    Sutra(
      "S1.4",
      1,
      "navīnaḥ samanvayakaḥ sthāyi-lekhāt yugāni bījayati",
      "नवीनः समन्वयकः स्थायिलेखात् युगानि बीजयति",
      "A fresh coordinator seeds its epochs from the durable log, never from zero.",
      [9],
      1,
      ["Heartbeat"],
      [],
      None,
    ),
    Sutra(
      "S1.5",
      1,
      "ajñātam ārogyaṃ sāvadhānam eva",
      "अज्ञातम् आरोग्यं सावधानम् एव",
      "Unknown health is itself an andon; it is never silently treated as green.",
      [2],
      1,
      ["Andon"],
      [],
      None,
    ),
    Sutra(
      "S1.6",
      1,
      "argalā parīkṣyate, na kadāpi kalpyate",
      "अर्गला परीक्ष्यते, न कदापि कल्प्यते",
      "The interlock is examined; it is never merely presumed locked.",
      [7],
      2,
      [],
      [],
      None,
    ),
    Sutra(
      "S1.7",
      1,
      "paryavekṣaṇaṃ satyaṃ jīva-saṅketam eva dadāti",
      "पर्यवेक्षणं सत्यं जीवसङ्केतम् एव ददाति",
      "Supervision gives back the real living pid, nothing else, so it can actually supervise.",
      [1],
      0,
      [],
      [],
      None,
    ),
  ]
}

/// Pāda 2: saṃracanā (संरचना) — structure.
fn pada2() -> List(Sutra) {
  [
    Sutra(
      "S2.1",
      2,
      "racanā-prakārāḥ kevalaṃ racanā-pramāṇāt āyānti",
      "रचनाप्रकाराः केवलं रचनाप्रमाणात् आयान्ति",
      "Design kinds come only from the design authority, never from a runtime tier.",
      [13],
      0,
      ["Plan", "Integrate"],
      ["CA-integrate_slice"],
      Some("BG 18.63"),
    ),
    Sutra(
      "S2.2",
      2,
      "pratyaṃśaḥ pūrṇavat, sarvāsu bhūmiṣu samam eva mukhaṃ darśayati",
      "प्रत्यंशः पूर्णवत्, सर्वासु भूमिषु समम् एव मुखं दर्शयति",
      "Every part is like the whole: at every level it shows the very same interface.",
      [4],
      0,
      [],
      [],
      None,
    ),
    Sutra(
      "S2.3",
      2,
      "pūrṇāṃśa-tantram acakram, bhūmi-krameṇa eva vardhate",
      "पूर्णांशतन्त्रम् अचक्रम्, भूमिक्रमेण एव वर्धते",
      "The whole-part system (holarchy) is acyclic; it grows only in level order.",
      [4],
      0,
      [],
      [],
      None,
    ),
    Sutra(
      "S2.4",
      2,
      "kathitaṃ pramāṇaṃ na grāhyam",
      "कथितं प्रमाणं न ग्राह्यम्",
      "A merely-declared proof is not admissible; declaration is not evidence.",
      [6],
      0,
      ["Verdict", "Report"],
      [],
      Some("BG 2.47"),
    ),
    Sutra(
      "S2.5",
      2,
      "sūcī gaṇyate na, parīkṣyate eva",
      "सूची गण्यते न, परीक्ष्यते एव",
      "The checklist is not counted; it is evaluated, item by item.",
      [8],
      0,
      ["Verdict"],
      [],
      None,
    ),
    Sutra(
      "S2.6",
      2,
      "prativiṣayaṃ sapta-daśa-nirṇayāḥ sarve dīyante",
      "प्रतिविषयं सप्तदशनिर्णयाः सर्वे दीयन्ते",
      "To every subject, all seventeen verdicts are given.",
      [17],
      0,
      ["Verdict"],
      ["CA-audit_screen"],
      None,
    ),
    Sutra(
      "S2.7",
      2,
      "yaḥ viṣayaḥ aparīkṣyaḥ, tasya parīkṣā-sāpekṣa-pakṣāḥ sīdanti",
      "यः विषयः अपरीक्ष्यः, तस्य परीक्षासापेक्षपक्षाः सीदन्ति",
      "A subject that cannot be probed — its probe-dependent aspects fail closed.",
      [8],
      0,
      [],
      [],
      None,
    ),
    Sutra(
      "S2.8",
      2,
      "svatantra eva nikṣepaḥ, sahasthānam eva na",
      "स्वतन्त्र एव निक्षेपः, सहस्थानम् एव न",
      "The repository stands alone; it is never co-located (standalone, non-colocated `.jj/`).",
      [2],
      0,
      [],
      [],
      None,
    ),
    Sutra(
      "S2.9",
      2,
      "mūla-git-vikāraḥ sarvathā vivarjitaḥ",
      "मूलगिट्विकारः सर्वथा विवर्जितः",
      "A native git mutation is barred outright.",
      [2],
      0,
      [],
      [],
      None,
    ),
    Sutra(
      "S2.10",
      2,
      "parivartanaṃ nāma, sthāpanaṃ sāraḥ — na kadāpi samīkriyate",
      "परिवर्तनं नाम, स्थापनं सारः — न कदापि समीक्रियते",
      "The change is the name (identity); the commit is the substance (content) — the two are never equated.",
      [2],
      0,
      [],
      [],
      None,
    ),
    Sutra(
      "S2.11",
      2,
      "paṭhakaḥ sādhāraṇāṃ kārya-pratilipiṃ na kadāpi kṣaṇa-citrayati",
      "पठकः साधारणां कार्यप्रतिलिपिं न कदापि क्षणचित्रयति",
      "A reader never snapshots a shared working copy (`--ignore-working-copy`).",
      [2],
      4,
      [],
      [],
      None,
    ),
    Sutra(
      "S2.12",
      2,
      "mukhya-gamanaṃ jīvat-paṭṭena nirṇaya-lekhena ca eva",
      "मुख्यगमनं जीवत्पट्टेन निर्णयलेखेन च एव",
      "The main bookmark moves only under a live lease, together with a decision record.",
      [2],
      4,
      ["Integrate", "Plan"],
      [],
      Some("BG 18.63"),
    ),
    Sutra(
      "S2.13",
      2,
      "saṃyojanaṃ rekhā-śṛṅkhalayā krameṇa punarādhīyate, virodhe tiṣṭhati",
      "संयोजनं रेखाशृङ्खलया क्रमेण पुनराधीयते, विरोधे तिष्ठति",
      "Integration is a linear chain, rebased in order; a conflict stops it.",
      [2],
      4,
      ["Integrate"],
      [],
      None,
    ),
    Sutra(
      "S2.14",
      2,
      "kriyāḥ punaḥsthāpyante athavā pratyāvartyante, na kadāpi sampādyante",
      "क्रियाः पुनःस्थाप्यन्ते अथवा प्रत्यावर्त्यन्ते, न कदापि सम्पाद्यन्ते",
      "Operations are restored or undone; they are never edited (the operation log is append-only).",
      [2],
      0,
      [],
      [],
      Some("BG 2.40"),
    ),
  ]
}

/// Pāda 3: pravṛtti (प्रवृत्ति) — runtime.
fn pada3() -> List(Sutra) {
  [
    Sutra(
      "S3.1",
      3,
      "pravṛtti-niyantraṇasya mūlyaṃ śūnyāṅkaiḥ eva",
      "प्रवृत्तिनियन्त्रणस्य मूल्यं शून्याङ्कैः एव",
      "The cost of runtime control is zero tokens, nothing more.",
      [10],
      2,
      ["Dispatch"],
      [],
      None,
    ),
    Sutra(
      "S3.2",
      3,
      "cakram avalokana-vicāra-nirṇaya-kriyā-krameṇa niyata-mūlyena baddham",
      "चक्रम् अवलोकनविचारनिर्णयक्रियाक्रमेण नियतमूल्येन बद्धम्",
      "The cycle — observe, orient, decide, act, in that order — is bound to a fixed budget.",
      [10],
      2,
      [],
      ["CA-paint_frame"],
      None,
    ),
    Sutra(
      "S3.3",
      3,
      "asaphalaḥ saṃyoga uttara-cakre sāvadhānaṃ janayati",
      "असफलः संयोग उत्तरचक्रे सावधानं जनयति",
      "A failed reconcile produces an andon on the following cycle.",
      [10],
      2,
      ["Andon"],
      [],
      None,
    ),
    Sutra(
      "S3.4",
      3,
      "prathamāyāṃ anujñā-nirākaraṇāyāṃ sandeśa-preṣaṇaṃ tiṣṭhati",
      "प्रथमायां अनुज्ञानिराकरणायां सन्देशप्रेषणं तिष्ठति",
      "At the first authorization refusal, posting stops.",
      [10],
      2,
      [],
      [],
      None,
    ),
    Sutra(
      "S3.5",
      3,
      "doṣe dṛṣṭe, svataḥ-yantraṃ paṅktim avasthāpayati",
      "दोषे दृष्टे, स्वतःयन्त्रं पङ्क्तिम् अवस्थापयति",
      "When a defect is seen, the self-acting mechanism (jidoka) stops the line.",
      [10],
      2,
      ["Jidoka"],
      ["CA-verify_slice"],
      Some("YS 1.2"),
    ),
    Sutra(
      "S3.6",
      3,
      "pravartamāna-kāryāṇāṃ saṅkhyā kāṣṭha-paṭṭikā-sīmayā baddhā",
      "प्रवर्तमानकार्याणां सङ्ख्या काष्ठपट्टिकासीमया बद्धा",
      "The count of work-in-progress is bound by the kanban board's limit.",
      [10],
      2,
      ["Progress"],
      [],
      None,
    ),
    Sutra(
      "S3.7",
      3,
      "gati-mānaṃ paṅktiṃ niyacchati, na kartuḥ utsāham",
      "गतिमानं पङ्क्तिं नियच्छति, न कर्तुः उत्साहम्",
      "Takt time governs the line's pace, not the worker's ambition.",
      [10],
      2,
      [],
      [],
      None,
    ),
  ]
}

/// Pāda 4: datta (दत्त) — data plane.
fn pada4() -> List(Sutra) {
  [
    Sutra(
      "S4.1",
      4,
      "preṣaka-śṛṅkhalāḥ kevalam āpūryante, na kadāpi luptāḥ",
      "प्रेषकशृङ्खलाः केवलम् आपूर्यन्ते, न कदापि लुप्ताः",
      "Per-sender chains are only ever appended to; they are never truncated.",
      [6],
      3,
      [],
      [],
      None,
    ),
    Sutra(
      "S4.2",
      4,
      "naṣṭa-sandeśasya uttare kāraṇa-vyavadhāna-lekhaḥ āvaśyakaḥ",
      "नष्टसन्देशस्य उत्तरे कारणव्यवधानलेखः आवश्यकः",
      "A reply to a lost message needs an explicit causal-gap record.",
      [6],
      3,
      ["Answer"],
      [],
      None,
    ),
    Sutra(
      "S4.3",
      4,
      "vinā satya-vahana-svīkāreṇa na kiñcit \"prāptam\" iti likhyate",
      "विना सत्यवहनस्वीकारेण न किञ्चित् \"प्राप्तम्\" इति लिख्यते",
      "Without a real transport acknowledgement, nothing is ever written as delivered.",
      [6],
      3,
      ["Ack"],
      [],
      None,
    ),
    Sutra(
      "S4.4",
      4,
      "smṛtiḥ anujñā-dvāreṇa eva, svāminaiva likhyate",
      "स्मृतिः अनुज्ञाद्वारेण एव, स्वामिनैव लिख्यते",
      "Memory is grant-gated: reachable only through a live grant, and written only by its owner.",
      [6],
      3,
      [],
      ["CA-write_owned_file"],
      None,
    ),
    Sutra(
      "S4.5",
      4,
      "sāmarthyānujñā kṣetra-baddhā, avadhim atikramya na tiṣṭhati",
      "सामर्थ्यानुज्ञा क्षेत्रबद्धा, अवधिम् अतिक्रम्य न तिष्ठति",
      "A capability grant is bound to its scope; past its expiry it no longer stands.",
      [6],
      3,
      ["LeaseGrant"],
      [],
      Some("BG 3.35"),
    ),
    Sutra(
      "S4.6",
      4,
      "sādhāraṇaṃ kuñcikā-kṣetraṃ na kadāpi vilupyate",
      "साधारणं कुञ्चिकाक्षेत्रं न कदापि विलुप्यते",
      "A shared key space is never deleted (SYNC-05).",
      [6],
      3,
      [],
      [],
      None,
    ),
    Sutra(
      "S4.7",
      4,
      "lekhasya para-paṅktiḥ pūrvāṃ na hanti, kevalam atikrāmati",
      "लेखस्य परपङ्क्तिः पूर्वां न हन्ति, केवलम् अतिक्रामति",
      "The ledger's later line does not kill the earlier one; it only supersedes it.",
      [6],
      3,
      ["Progress"],
      [],
      None,
    ),
  ]
}

/// Pāda 5: sandeśa (सन्देश) — messaging.
fn pada5() -> List(Sutra) {
  [
    Sutra(
      "S5.1",
      5,
      "mārga-nirṇayaḥ pratyekaṃ phalaka-sandeśaḥ eva",
      "मार्गनिर्णयः प्रत्येकं फलकसन्देशः एव",
      "Every routing decision is itself a board message.",
      [10],
      1,
      ["Dispatch", "Report"],
      [],
      None,
    ),
    Sutra(
      "S5.2",
      5,
      "prathamaṃ niḥśulkaṃ gṛhyate, mūlya-nikṛṣṭaṃ dvi-paisā-mātram",
      "प्रथमं निःशुल्कं गृह्यते, मूल्यनिकृष्टं द्विपैसामात्रम्",
      "The free tier is taken first; the paid floor is at most USD 0.02.",
      [10],
      1,
      ["Dispatch"],
      [],
      None,
    ),
    Sutra(
      "S5.3",
      5,
      "sīmām atikramituṃ pūrvaṃ praśnaḥ śodhana-parīkṣāṃ tarati",
      "सीमाम् अतिक्रमितुं पूर्वं प्रश्नः शोधनपरीक्षां तरति",
      "Before it crosses the boundary, a prompt must pass the sanitize check.",
      [10],
      1,
      ["Question"],
      [],
      None,
    ),
    Sutra(
      "S5.4",
      5,
      "svīkāraḥ nirdeśaḥ vahanaṃ ca kāryaṃ na kadāpi anujānanti",
      "स्वीकारः निर्देशः वहनं च कार्यं न कदापि अनुजानन्ति",
      "An acknowledgement, a reference, or a transport projection never themselves authorize an effect.",
      [10],
      1,
      ["Ack"],
      [],
      None,
    ),
    Sutra(
      "S5.5",
      5,
      "eka-saṅketaḥ ekaṃ karma nirdiśati, viruddhe punaḥ-prayoge doṣaḥ jāyate",
      "एकसङ्केतः एकं कर्म निर्दिशति, विरुद्धे पुनःप्रयोगे दोषः जायते",
      "One operation id names one command; a conflicting reuse of it is an error.",
      [10],
      1,
      ["Claim"],
      [],
      None,
    ),
    Sutra(
      "S5.6",
      5,
      "mṛta-pāṇi-yantraṃ maunaṃ jīrṇam iti lakṣayati, na ārogyam",
      "मृतपाणियन्त्रं मौनं जीर्णम् इति लक्षयति, न आरोग्यम्",
      "The dead-man's-switch marks silence as stale; it never mistakes silence for health.",
      [10],
      1,
      ["Heartbeat"],
      [],
      None,
    ),
    Sutra(
      "S5.7",
      5,
      "eka-yantra-phalaṃ vā sakhi-svīkāro vā svataḥ niyoga-sāmarthyaṃ na dadāti",
      "एकयन्त्रफलं वा सखिस्वीकारो वा स्वतः नियोगसामर्थ्यं न ददाति",
      "Neither one model's result nor a peer's acknowledgement alone grants deployment authority.",
      [10],
      1,
      ["Verdict"],
      [],
      None,
    ),
  ]
}

/// Pāda 6: buddhi (बुद्धि) — intelligence.
fn pada6() -> List(Sutra) {
  [
    Sutra(
      "S6.1",
      6,
      "vikāsaḥ kevalaṃ parīkṣita-yogyatām eva svīkaroti",
      "विकासः केवलं परीक्षितयोग्यताम् एव स्वीकरोति",
      "Evolution adopts only fitness that has been verified, never a self-claimed score.",
      [14],
      6,
      [],
      [],
      None,
    ),
    Sutra(
      "S6.2",
      6,
      "svapna-cakraṃ paṅktau niṣkriyāyām eva pravartate",
      "स्वप्नचक्रं पङ्क्तौ निष्क्रियायाम् एव प्रवर्तते",
      "The dream cycle (svapna) runs only when the line is idle.",
      [14],
      6,
      [],
      [],
      Some("YS 1.38"),
    ),
    Sutra(
      "S6.3",
      6,
      "svapnaḥ vikalpān janayati, na kadāpi siddha-vastūni",
      "स्वप्नः विकल्पान् जनयति, न कदापि सिद्धवस्तूनि",
      "The dream produces hypotheses (vikalpa), never established facts.",
      [14],
      6,
      ["Plan"],
      [],
      Some("YS 1.6"),
    ),
    Sutra(
      "S6.4",
      6,
      "vikalpaḥ śūnyāt ekasmāt madhye niścayena eva gṛhyate, na jñānam iti",
      "विकल्पः शून्यात् एकस्मात् मध्ये निश्चयेन एव गृह्यते, न ज्ञानम् इति",
      "A hypothesis is admitted only with a confidence strictly between zero and one, never as knowledge.",
      [14],
      6,
      ["Plan"],
      [],
      None,
    ),
    Sutra(
      "S6.5",
      6,
      "matam kevalaṃ parīkṣita-phalebhyaḥ vardhate, na svayaṃ-kathanāt",
      "मतम् केवलं परीक्षितफलेभ्यः वर्धते, न स्वयंकथनात्",
      "Belief grows only from verified outcomes, never from self-report.",
      [14],
      6,
      [],
      [],
      None,
    ),
    Sutra(
      "S6.6",
      6,
      "sarvebhyo alpa-mūlyaḥ yogyaḥ stara eva vṛtaḥ, na su-vāgmī",
      "सर्वेभ्यो अल्पमूल्यः योग्यः स्तर एव वृतः, न सुवाग्मी",
      "Of all tiers, the cheapest adequate one alone is chosen, never the most eloquent.",
      [14],
      6,
      [],
      [],
      None,
    ),
    Sutra(
      "S6.7",
      6,
      "unnayanam ekaṃ padam eva, dvitīye vibhrame mūlādhikāriṇe svataḥ-yantra-nirodhaḥ",
      "उन्नयनम् एकं पदम् एव, द्वितीये विभ्रमे मूलाधिकारिणे स्वतःयन्त्रनिरोधः",
      "Escalation is one step only; a second failure is a jidoka stop for the root (L0) authority.",
      [14],
      6,
      ["Jidoka"],
      [],
      None,
    ),
  ]
}

/// Pāda 7: bhāṣā (भाषा) — language.
fn pada7() -> List(Sutra) {
  [
    Sutra(
      "S7.1",
      7,
      "prativākyaṃ sādhāraṇa-śabdakośena badhyate, anyathā svataḥ ruddhyate",
      "प्रतिवाक्यं साधारणशब्दकोशेन बध्यते, अन्यथा स्वतः रुध्यते",
      "Every utterance binds to the shared vocabulary, otherwise it fails closed by itself.",
      [16],
      7,
      [],
      [],
      None,
    ),
    Sutra(
      "S7.2",
      7,
      "prārthanā vā prastāvo vā iṣṭi-vākyaṃ tasmāt-vākyaṃ vā vahati",
      "प्रार्थना वा प्रस्तावो वा इष्टिवाक्यं तस्मात्वाक्यं वा वहति",
      "A REQUEST or a PROPOSE carries an intention clause or a therefore clause.",
      [16],
      7,
      ["Question", "Plan"],
      [],
      None,
    ),
    Sutra(
      "S7.3",
      7,
      "sūcanā vā pratijñā vā jñāna-vākyam eva vahati",
      "सूचना वा प्रतिज्ञा वा ज्ञानवाक्यम् एव वहति",
      "An INFORM or an ASSERT carries only a knowledge clause.",
      [16],
      7,
      ["Report"],
      [],
      None,
    ),
    Sutra(
      "S7.4",
      7,
      "sāvadhānena niyantraṇa-kriyāyāḥ nāma avaśyam eva ucyate",
      "सावधानेन नियन्त्रणक्रियायाः नाम अवश्यम् एव उच्यते",
      "An ANDON must always name the control action it concerns.",
      [16],
      7,
      ["Andon"],
      [],
      None,
    ),
    Sutra(
      "S7.5",
      7,
      "mūla-rūpaṃ dvi-bhāṣam: saṃskṛtaṃ pūrvam, āṅglaṃ prati-paṅkti sahacaram",
      "मूलरूपं द्विभाषम्: संस्कृतं पूर्वम्, आङ्ग्लं प्रतिपङ्क्ति सहचरम्",
      "The canonical form is bilingual: Sanskrit first, English a companion beside every line.",
      [16],
      7,
      [],
      [],
      None,
    ),
    Sutra(
      "S7.6",
      7,
      "āṅglam iyad vā saṃskṛtam vā devanāgarī vā, ekam eva vākyaṃ nirdiśati",
      "आङ्ग्लम् इयद् वा संस्कृतम् वा देवनागरी वा, एकम् एव वाक्यं निर्दिशति",
      "Whether English, IAST, or Devanagari — every surface form parses to the same utterance.",
      [16],
      7,
      [],
      [],
      None,
    ),
    Sutra(
      "S7.7",
      7,
      "lekhanaṃ paṭhanaṃ ca yuktam, mūla-rūpam eva punaḥ dadāti",
      "लेखनं पठनं च युक्तम्, मूलरूपम् एव पुनः ददाति",
      "Writing and reading, composed together, give back only the original form again (roundtrip).",
      [16],
      7,
      [],
      [],
      None,
    ),
  ]
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

pub fn find(id: String) -> Result(Sutra, Nil) {
  register() |> list.find(fn(s) { s.id == id })
}

pub fn by_pada(p: Int) -> List(Sutra) {
  register() |> list.filter(fn(s) { s.pada == p })
}

pub fn for_kind(kind: String) -> List(Sutra) {
  register() |> list.filter(fn(s) { list.contains(s.kinds, kind) })
}

pub fn for_aspect(n: Int) -> List(Sutra) {
  register() |> list.filter(fn(s) { list.contains(s.aspects, n) })
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

pub fn validate_register() -> Result(Nil, String) {
  let all = register()
  use _ <- result_try(check_unique_ids(all))
  use _ <- result_try(check_pada_range(all))
  use _ <- result_try(check_aspect_range(all))
  use _ <- result_try(check_layer_range(all))
  use _ <- result_try(check_nonempty_text(all))
  use _ <- result_try(check_kinds(all))
  use _ <- result_try(check_control_actions(all))
  Ok(Nil)
}

fn result_try(r: Result(a, e), f: fn(a) -> Result(b, e)) -> Result(b, e) {
  case r {
    Ok(a) -> f(a)
    Error(e) -> Error(e)
  }
}

fn check_unique_ids(all: List(Sutra)) -> Result(Nil, String) {
  let ids = list.map(all, fn(s) { s.id })
  case set.size(set.from_list(ids)) == list.length(ids) {
    True -> Ok(Nil)
    False -> Error("duplicate sutra id in register")
  }
}

fn check_pada_range(all: List(Sutra)) -> Result(Nil, String) {
  case list.find(all, fn(s) { s.pada < 1 || s.pada > 7 }) {
    Ok(s) -> Error(s.id <> ": pada out of range 1..7")
    Error(_) -> Ok(Nil)
  }
}

fn check_aspect_range(all: List(Sutra)) -> Result(Nil, String) {
  case
    list.find(all, fn(s) { list.any(s.aspects, fn(a) { a < 1 || a > 17 }) })
  {
    Ok(s) -> Error(s.id <> ": aspect out of range 1..17")
    Error(_) -> Ok(Nil)
  }
}

fn check_layer_range(all: List(Sutra)) -> Result(Nil, String) {
  case list.find(all, fn(s) { s.layer < 0 || s.layer > 9 }) {
    Ok(s) -> Error(s.id <> ": layer out of range 0..9")
    Error(_) -> Ok(Nil)
  }
}

fn check_nonempty_text(all: List(Sutra)) -> Result(Nil, String) {
  case
    list.find(all, fn(s) {
      s.iast == "" || s.devanagari == "" || s.english == ""
    })
  {
    Ok(s) -> Error(s.id <> ": empty text field")
    Error(_) -> Ok(Nil)
  }
}

fn check_kinds(all: List(Sutra)) -> Result(Nil, String) {
  case
    list.find(all, fn(s) {
      list.any(s.kinds, fn(k) { !list.contains(allowed_kinds, k) })
    })
  {
    Ok(s) -> Error(s.id <> ": unknown board kind")
    Error(_) -> Ok(Nil)
  }
}

fn check_control_actions(all: List(Sutra)) -> Result(Nil, String) {
  case
    list.find(all, fn(s) {
      list.any(s.control_actions, fn(c) {
        !list.contains(allowed_control_actions, c)
      })
    })
  {
    Ok(s) -> Error(s.id <> ": unknown control action")
    Error(_) -> Ok(Nil)
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

pub fn to_markdown() -> String {
  let header =
    "| id | pāda | Devanagari | IAST | English | aspects | kinds | source |\n|---|---|---|---|---|---|---|---|"
  let rows =
    list.map(register(), fn(s) {
      "| "
      <> s.id
      <> " | "
      <> int.to_string(s.pada)
      <> " | "
      <> s.devanagari
      <> " | "
      <> s.iast
      <> " | "
      <> s.english
      <> " | "
      <> string.join(list.map(s.aspects, int.to_string), ",")
      <> " | "
      <> string.join(s.kinds, ",")
      <> " | "
      <> option.unwrap(s.source, "")
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

pub fn to_json() -> Json {
  json.array(register(), sutra_to_json)
}

fn sutra_to_json(s: Sutra) -> Json {
  json.object([
    #("id", json.string(s.id)),
    #("pada", json.int(s.pada)),
    #("iast", json.string(s.iast)),
    #("devanagari", json.string(s.devanagari)),
    #("english", json.string(s.english)),
    #("aspects", json.array(s.aspects, json.int)),
    #("layer", json.int(s.layer)),
    #("kinds", json.array(s.kinds, json.string)),
    #("control_actions", json.array(s.control_actions, json.string)),
    #("source", case s.source {
      Some(x) -> json.string(x)
      None -> json.null()
    }),
  ])
}
