//// Hindustani classical music building blocks (svara, thāṭ, rāga, tāla, mātrā/beat) mapped onto
//// the core holon base layer: the seven planes as the seven svara-s, the ten fractal layers
//// (L0..L9) as the ten canonical thāṭ-s, the OODA controller's mode as a rāga chosen by mood and
//// time of day, the F´ manager's cycle counter as a tāla's beat cycle, and the swarm's own
//// plan/dispatch/verify/integrate steps as the alap/jor/jhala/bandish arc of a performance.
//// Sanskrit/Hindustani: svara = स्वर (note), thāṭ = थाट (parent scale), rāga = राग (melodic mode),
//// tāla = ताल (rhythmic cycle), mātrā = मात्रा (beat), vādī = वादी (sonant, most important note),
//// samvādī = सम्वादी (consonant, second most important note).
////
//// Deliberate one-way dependency: this module never imports `uos_swarm/holon`. `holon.gleam`
//// imports `raga` (for `Swara` in `holon.swara_of`/`holon.dharma_of` and base rule B8), so the
//// reverse import would form a cycle that Gleam's compiler rejects outright (verified: `gleam
//// build` reports "Import cycle" for any two modules that import each other). The
//// plane<->svara pairing therefore lives as the authoritative typed function
//// `holon.swara_of_plane` in `holon.gleam`; the `swara_planes` table below is a plain-string
//// mirror of that same pairing, kept only for this module's own `to_markdown`/`to_json` display
//// and documented here so the two never drift silently.
//// STAMP: SC-TUI-RAGA-001, #fractal-l0.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string
import uos_swarm/ooda

// ---------------------------------------------------------------------------
// Svara: the seven notes.
// ---------------------------------------------------------------------------

pub type Swara {
  Sa
  Re
  Ga
  Ma
  Pa
  Dha
  Ni
}

/// All seven svara-s, Sa..Ni, in their canonical order.
pub const swaras = [Sa, Re, Ga, Ma, Pa, Dha, Ni]

pub fn all_swaras() -> List(Swara) {
  swaras
}

/// IAST + Devanagari label, e.g. `"sa · स"`.
pub fn swara_label(s: Swara) -> String {
  case s {
    Sa -> "sa · स"
    Re -> "re · रे"
    Ga -> "ga · ग"
    Ma -> "ma · म"
    Pa -> "pa · प"
    Dha -> "dha · ध"
    Ni -> "ni · नि"
  }
}

/// Sa and Pa are the two *achala* (immovable) svara-s: every thāṭ carries them shuddha, only
/// Re/Ga/Ma/Dha/Ni ever take a komal or tivra variant.
pub type Variant {
  Shuddha
  Komal
  Tivra
}

pub fn variant_label(v: Variant) -> String {
  case v {
    Shuddha -> "shuddha · शुद्ध"
    Komal -> "komal · कोमल"
    Tivra -> "tivra · तीव्र"
  }
}

/// `"re (komal · कोमल)"`; shuddha notes render as the bare svara label.
pub fn swara_variant_label(pair: #(Swara, Variant)) -> String {
  let #(s, v) = pair
  case v {
    Shuddha -> swara_label(s)
    _ -> swara_label(s) <> " (" <> variant_label(v) <> ")"
  }
}

fn swara_variant_sequence_label(pairs: List(#(Swara, Variant))) -> String {
  string.join(list.map(pairs, swara_variant_label), " ")
}

// ---------------------------------------------------------------------------
// Thāṭ: the ten parent scales (Bhatkhande's system).
// ---------------------------------------------------------------------------

pub type Thaat {
  Bilawal
  Kalyan
  Khamaj
  Bhairav
  Poorvi
  Marwa
  Kafi
  Asavari
  Bhairavi
  Todi
}

/// The ten thāṭ-s in the canonical order used to index the fractal layers L0..L9.
pub const thaats = [
  Bilawal,
  Kalyan,
  Khamaj,
  Bhairav,
  Poorvi,
  Marwa,
  Kafi,
  Asavari,
  Bhairavi,
  Todi,
]

pub fn thaat_label(t: Thaat) -> String {
  case t {
    Bilawal -> "Bilawal · बिलावल"
    Kalyan -> "Kalyan · कल्याण"
    Khamaj -> "Khamaj · खमाज"
    Bhairav -> "Bhairav · भैरव"
    Poorvi -> "Poorvi · पूर्वी"
    Marwa -> "Marwa · मारवा"
    Kafi -> "Kafi · काफी"
    Asavari -> "Asavari · आसावरी"
    Bhairavi -> "Bhairavi · भैरवी"
    Todi -> "Todi · तोड़ी"
  }
}

/// The seven svara-s of a thāṭ, always Sa..Ni in order, each paired with its variant.
pub fn thaat_swaras(t: Thaat) -> List(#(Swara, Variant)) {
  case t {
    Bilawal -> [
      #(Sa, Shuddha),
      #(Re, Shuddha),
      #(Ga, Shuddha),
      #(Ma, Shuddha),
      #(Pa, Shuddha),
      #(Dha, Shuddha),
      #(Ni, Shuddha),
    ]
    Kalyan -> [
      #(Sa, Shuddha),
      #(Re, Shuddha),
      #(Ga, Shuddha),
      #(Ma, Tivra),
      #(Pa, Shuddha),
      #(Dha, Shuddha),
      #(Ni, Shuddha),
    ]
    Khamaj -> [
      #(Sa, Shuddha),
      #(Re, Shuddha),
      #(Ga, Shuddha),
      #(Ma, Shuddha),
      #(Pa, Shuddha),
      #(Dha, Shuddha),
      #(Ni, Komal),
    ]
    Bhairav -> [
      #(Sa, Shuddha),
      #(Re, Komal),
      #(Ga, Shuddha),
      #(Ma, Shuddha),
      #(Pa, Shuddha),
      #(Dha, Komal),
      #(Ni, Shuddha),
    ]
    Poorvi -> [
      #(Sa, Shuddha),
      #(Re, Komal),
      #(Ga, Shuddha),
      #(Ma, Tivra),
      #(Pa, Shuddha),
      #(Dha, Komal),
      #(Ni, Shuddha),
    ]
    Marwa -> [
      #(Sa, Shuddha),
      #(Re, Komal),
      #(Ga, Shuddha),
      #(Ma, Tivra),
      #(Pa, Shuddha),
      #(Dha, Shuddha),
      #(Ni, Shuddha),
    ]
    Kafi -> [
      #(Sa, Shuddha),
      #(Re, Shuddha),
      #(Ga, Komal),
      #(Ma, Shuddha),
      #(Pa, Shuddha),
      #(Dha, Shuddha),
      #(Ni, Komal),
    ]
    Asavari -> [
      #(Sa, Shuddha),
      #(Re, Shuddha),
      #(Ga, Komal),
      #(Ma, Shuddha),
      #(Pa, Shuddha),
      #(Dha, Komal),
      #(Ni, Komal),
    ]
    Bhairavi -> [
      #(Sa, Shuddha),
      #(Re, Komal),
      #(Ga, Komal),
      #(Ma, Shuddha),
      #(Pa, Shuddha),
      #(Dha, Komal),
      #(Ni, Komal),
    ]
    Todi -> [
      #(Sa, Shuddha),
      #(Re, Komal),
      #(Ga, Komal),
      #(Ma, Tivra),
      #(Pa, Shuddha),
      #(Dha, Komal),
      #(Ni, Shuddha),
    ]
  }
}

/// `thaat_of_layer`: the ten fractal layers L0..L9 indexed onto the ten thāṭ-s in the order
/// listed above (Bilawal=L0 .. Todi=L9). Out-of-range layers (negative, or >9) fail closed onto
/// Todi (the last, most altered thāṭ) rather than crashing.
pub fn thaat_of_layer(layer: Int) -> Thaat {
  case layer {
    0 -> Bilawal
    1 -> Kalyan
    2 -> Khamaj
    3 -> Bhairav
    4 -> Poorvi
    5 -> Marwa
    6 -> Kafi
    7 -> Asavari
    8 -> Bhairavi
    _ -> Todi
  }
}

// ---------------------------------------------------------------------------
// Rāga: melodic modes, at least one drawn from each of eight thāṭ-s below.
// ---------------------------------------------------------------------------

pub type TimeOfDay {
  EarlyMorning
  Morning
  Afternoon
  Evening
  Night
  LateNight
  AnyTime
}

pub fn time_of_day_label(t: TimeOfDay) -> String {
  case t {
    EarlyMorning -> "early morning (pratah-kāl)"
    Morning -> "morning (pūrvāhna)"
    Afternoon -> "afternoon (madhyāhna)"
    Evening -> "evening (sāyaṃkāl)"
    Night -> "night (rātri)"
    LateNight -> "late night (madhyarātri)"
    AnyTime -> "any time (sarvakāl)"
  }
}

pub type Raga {
  Raga(
    name: String,
    thaat: Thaat,
    aroha: List(#(Swara, Variant)),
    avaroha: List(#(Swara, Variant)),
    vadi: Swara,
    samvadi: Swara,
    time: TimeOfDay,
    mood: String,
  )
}

pub fn yaman() -> Raga {
  let full = thaat_swaras(Kalyan)
  Raga(
    "Yaman · यमन",
    Kalyan,
    full,
    list.reverse(full),
    Ga,
    Ni,
    Evening,
    "serene, devotional twilight raga; the classic first raga taught, all shuddha but a tivra Ma",
  )
}

pub fn bhairav() -> Raga {
  let full = thaat_swaras(Bhairav)
  Raga(
    "Bhairav · भैरव",
    Bhairav,
    full,
    list.reverse(full),
    Dha,
    Re,
    EarlyMorning,
    "solemn, devotional dawn raga invoking Shiva; komal Re and Dha against an otherwise shuddha scale",
  )
}

pub fn bhairavi() -> Raga {
  let full = thaat_swaras(Bhairavi)
  Raga(
    "Bhairavi · भैरवी",
    Bhairavi,
    full,
    list.reverse(full),
    Ma,
    Sa,
    Morning,
    "all-komal scale traditionally closing a concert; grave and consoling",
  )
}

pub fn malkauns() -> Raga {
  let aroha = [
    #(Sa, Shuddha),
    #(Ga, Komal),
    #(Ma, Shuddha),
    #(Dha, Komal),
    #(Ni, Komal),
  ]
  Raga(
    "Malkauns · मालकौंस",
    Bhairavi,
    aroha,
    list.reverse(aroha),
    Ma,
    Sa,
    LateNight,
    "pentatonic (no Re, no Pa), deep and meditative; a late-night raga of introspection",
  )
}

pub fn bilawal() -> Raga {
  let full = thaat_swaras(Bilawal)
  Raga(
    "Bilawal · बिलावल",
    Bilawal,
    full,
    list.reverse(full),
    Dha,
    Ga,
    Morning,
    "bright, all-shuddha morning raga; the natural (major-scale-like) parent of its own thaat",
  )
}

pub fn durga() -> Raga {
  let aroha = [
    #(Sa, Shuddha),
    #(Re, Shuddha),
    #(Ma, Shuddha),
    #(Pa, Shuddha),
    #(Dha, Shuddha),
  ]
  Raga(
    "Durga · दुर्गा",
    Bilawal,
    aroha,
    list.reverse(aroha),
    Ma,
    Sa,
    Evening,
    "pentatonic (no Ga, no Ni), simple and uplifting evening raga",
  )
}

pub fn kafi() -> Raga {
  let full = thaat_swaras(Kafi)
  Raga(
    "Kafi · काफी",
    Kafi,
    full,
    list.reverse(full),
    Pa,
    Sa,
    Night,
    "romantic, playful night raga associated with the Holi season; komal Ga and Ni",
  )
}

pub fn todi() -> Raga {
  let full = thaat_swaras(Todi)
  Raga(
    "Todi · तोड़ी",
    Todi,
    full,
    list.reverse(full),
    Dha,
    Ga,
    Morning,
    "late-morning raga of striking pathos; komal Re/Ga/Dha against a tivra Ma",
  )
}

pub fn marwa() -> Raga {
  let aroha = [
    #(Sa, Shuddha),
    #(Re, Komal),
    #(Ga, Shuddha),
    #(Ma, Tivra),
    #(Dha, Shuddha),
    #(Ni, Shuddha),
  ]
  Raga(
    "Marwa · मारवा",
    Marwa,
    aroha,
    list.reverse(aroha),
    Re,
    Dha,
    Evening,
    "intense, restless sunset raga; Pa is characteristically varjit (dropped)",
  )
}

pub fn darbari() -> Raga {
  let full = thaat_swaras(Asavari)
  Raga(
    "Darbari · दरबारी (Kanada)",
    Asavari,
    full,
    list.reverse(full),
    Re,
    Pa,
    Night,
    "grave, majestic deep-night raga of the Mughal court; heavy gamak on komal Ga and Dha",
  )
}

/// All ten defined ragas.
pub fn ragas() -> List(Raga) {
  [
    yaman(),
    bhairav(),
    bhairavi(),
    malkauns(),
    bilawal(),
    durga(),
    kafi(),
    todi(),
    marwa(),
    darbari(),
  ]
}

/// `raga_of_mode`: pick the cycle's raga from the OODA mode and the UTC hour (0..23) of
/// `now_us`. Dark -> Malkauns (deep, quiet), Dim -> Bhairav (dawn, low light), Normal -> Yaman
/// (the everyday evening raga), Bright -> Bilawal by day / Durga by night, Emergency -> Bhairavi
/// (the grave, all-hands raga).
pub fn raga_of_mode(mode: ooda.Mode, hour: Int) -> Raga {
  case mode {
    ooda.Dark -> malkauns()
    ooda.Dim -> bhairav()
    ooda.Normal -> yaman()
    ooda.Bright ->
      case hour >= 6 && hour < 18 {
        True -> bilawal()
        False -> durga()
      }
    ooda.Emergency -> bhairavi()
  }
}

// ---------------------------------------------------------------------------
// Tāla: rhythmic cycles.
// ---------------------------------------------------------------------------

pub type Tala {
  Tala(
    name: String,
    matras: Int,
    vibhags: List(Int),
    sam: Int,
    khali: List(Int),
    tali: List(Int),
  )
}

pub fn teentaal() -> Tala {
  Tala("Teentaal · तीनताल", 16, [4, 4, 4, 4], 1, [9], [1, 5, 13])
}

pub fn jhaptaal() -> Tala {
  Tala("Jhaptaal · झपताल", 10, [2, 3, 2, 3], 1, [6], [1, 3, 8])
}

/// Rupak's sam coincides with its khali (the cycle opens on a wave, not a clap).
pub fn rupak() -> Tala {
  Tala("Rupak · रूपक", 7, [3, 2, 2], 1, [1], [3, 5])
}

pub fn ektaal() -> Tala {
  Tala("Ektaal · एकताल", 12, [2, 2, 2, 2, 2, 2], 1, [3, 7], [1, 5, 9, 11])
}

pub fn keherwa() -> Tala {
  Tala("Keherwa · कहरवा", 8, [4, 4], 1, [5], [])
}

pub fn dadra() -> Tala {
  Tala("Dadra · दादरा", 6, [3, 3], 1, [4], [])
}

/// All six defined talas.
pub fn talas() -> List(Tala) {
  [teentaal(), jhaptaal(), rupak(), ektaal(), keherwa(), dadra()]
}

pub type BeatKind {
  Sam
  Tali
  Khali
  Ordinary
}

pub fn beat_kind_label(k: BeatKind) -> String {
  case k {
    Sam -> "sam"
    Tali -> "tali"
    Khali -> "khali"
    Ordinary -> "ordinary"
  }
}

pub type Beat {
  Beat(matra: Int, vibhag: Int, kind: BeatKind)
}

fn vibhag_of_matra(vibhags: List(Int), remaining: Int, idx: Int) -> Int {
  case vibhags {
    [] -> idx
    [v, ..rest] ->
      case remaining <= v {
        True -> idx
        False -> vibhag_of_matra(rest, remaining - v, idx + 1)
      }
  }
}

/// `beat_of_cycle`: the 1-based mātrā (beat), its 1-based vibhāg (section) and its `BeatKind`
/// for a 1-based swarm `cycle` against `t`. `cycle` is folded into `1..t.matras` first (so cycle
/// 0 or negative cycles never crash: they land on a well-defined beat of the previous lap), then
/// classified `Sam` (the tāla's single downbeat) before `Khali` (the "empty"/wave section) before
/// `Tali` (a clap) before `Ordinary` — matching the real convention that the sam beat is also
/// listed as the first tali in a tāla's clap pattern (e.g. Teentaal's tali 1, 5, 13 includes its
/// own sam at 1).
pub fn beat_of_cycle(t: Tala, cycle: Int) -> Beat {
  let matra = { { cycle - 1 } % t.matras + t.matras } % t.matras + 1
  let vibhag = vibhag_of_matra(t.vibhags, matra, 1)
  let kind = case matra == t.sam {
    True -> Sam
    False ->
      case list.contains(t.khali, matra) {
        True -> Khali
        False ->
          case list.contains(t.tali, matra) {
            True -> Tali
            False -> Ordinary
          }
      }
  }
  Beat(matra, vibhag, kind)
}

// ---------------------------------------------------------------------------
// Swarm-step phase and provider gharānā labels.
// ---------------------------------------------------------------------------

/// `phase_of_swarm`: maps a swarm step name to its Hindustani performance-arc phase, with a
/// one-line explanation of the parallel. Unknown steps fail closed with a labelled message
/// rather than a lookup crash.
pub fn phase_of_swarm(step: String) -> String {
  case step {
    "plan" ->
      "alap · आलाप — unmetered exploration of the raga's shape before rhythm enters: "
      <> "planning surveys the holarchy and intent before any cycle is committed to."
    "dispatch" ->
      "jor · जोड़ — a pulse enters without percussion, building momentum: "
      <> "dispatch assigns work and starts the beat before it is yet audited."
    "verify" ->
      "jhala · झाला — a fast, driving climax with strummed drone strings: "
      <> "verification runs the tight, fast audit pass against evidence."
    "integrate" ->
      "bandish · बंदिश — the fixed, composed piece with tabla in full tala: "
      <> "integration is the disciplined, tala-bound merge back into the whole."
    other -> "unknown swarm step: " <> other
  }
}

/// `gharana_of_provider`: names each dispatch-tier provider's lineage without inventing any
/// claim about a real musical gharānā, grounded only in this system's own
/// `SC-INTEL-ROUTING-001` routing tiers (R0..R6).
pub fn gharana_of_provider(provider: String) -> String {
  case provider {
    "claude" ->
      "gharānā: claude — R4 bounded implementation lineage (default coding tier)"
    "codex" ->
      "gharānā: codex — R5 sovereign security/architecture review lineage (Codex Astra)"
    "agy" ->
      "gharānā: agy — R5/R6 design-authority and architecture review lineage (Antigravity)"
    "openrouter" ->
      "gharānā: openrouter — R2/R3 cheapest-tier docs and advisory lineage (free-first nano tier)"
    other -> "gharānā: " <> other <> " — unclassified lineage"
  }
}

// ---------------------------------------------------------------------------
// Validation.
// ---------------------------------------------------------------------------

fn validate_one_raga(r: Raga) -> Result(Nil, String) {
  let set = thaat_swaras(r.thaat)
  case r.aroha, r.avaroha {
    [], _ -> Error(r.name <> ": empty aroha")
    _, [] -> Error(r.name <> ": empty avaroha")
    _, _ ->
      case
        list.all(r.aroha, fn(p) { list.contains(set, p) }),
        list.all(r.avaroha, fn(p) { list.contains(set, p) })
      {
        False, _ | _, False ->
          Error(
            r.name
            <> ": aroha/avaroha draws a note outside "
            <> thaat_label(r.thaat),
          )
        True, True ->
          case
            list.any(list.append(r.aroha, r.avaroha), fn(p) { p.0 == r.vadi }),
            list.any(list.append(r.aroha, r.avaroha), fn(p) { p.0 == r.samvadi })
          {
            False, _ -> Error(r.name <> ": vadi is not one of its own notes")
            _, False -> Error(r.name <> ": samvadi is not one of its own notes")
            True, True -> Ok(Nil)
          }
      }
  }
}

fn validate_one_tala(t: Tala) -> Result(Nil, String) {
  case list.fold(t.vibhags, 0, fn(acc, v) { acc + v }) == t.matras {
    False -> Error(t.name <> ": vibhags do not sum to matras")
    True ->
      case
        t.sam >= 1
        && t.sam <= t.matras
        && list.all(list.append(t.khali, t.tali), fn(m) {
          m >= 1 && m <= t.matras
        })
      {
        False -> Error(t.name <> ": sam/khali/tali out of 1..matras range")
        True -> Ok(Nil)
      }
  }
}

/// Validates every shipped raga (non-empty aroha/avaroha drawn from its own thaat's swara set,
/// vadi/samvadi among its own notes) and every shipped tala (vibhags sum to matras, sam/khali/
/// tali within 1..matras).
pub fn validate_register() -> Result(Nil, String) {
  use _ <- result.try(list.try_each(ragas(), validate_one_raga))
  list.try_each(talas(), validate_one_tala)
}

// ---------------------------------------------------------------------------
// Rendering.
// ---------------------------------------------------------------------------

/// Plane label mirrored from `holon.plane_label` (see the module doc: this module cannot import
/// `holon` without creating an import cycle, so the seven strings are duplicated here and kept
/// in the same Sa..Ni / Control..Language order as `holon.swara_of_plane`).
const swara_planes = [
  #(Sa, "control · niyantraṇa (नियन्त्रण)"),
  #(Re, "structure · saṃracanā (संरचना)"),
  #(Ga, "runtime · pravartana (प्रवर्तन)"),
  #(Ma, "data plane · dattāṃśa (दत्तांश)"),
  #(Pa, "messaging · sandeśa (सन्देश)"),
  #(Dha, "intelligence · buddhi (बुद्धि)"),
  #(Ni, "language · bhāṣā (भाषा)"),
]

const layers = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

fn swaras_table() -> String {
  let header = "| svara | plane |\n|---|---|"
  let rows =
    list.map(swara_planes, fn(p) {
      "| " <> swara_label(p.0) <> " | " <> p.1 <> " |"
    })
  string.join([header, ..rows], "\n")
}

fn thaats_table() -> String {
  let header = "| layer | thaat | svara-s |\n|---|---|---|"
  let rows =
    list.map(layers, fn(l) {
      let t = thaat_of_layer(l)
      "| L"
      <> int.to_string(l)
      <> " | "
      <> thaat_label(t)
      <> " | "
      <> swara_variant_sequence_label(thaat_swaras(t))
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

fn ragas_table() -> String {
  let header =
    "| raga | thaat | aroha | avaroha | vadi | samvadi | time | mood |\n|---|---|---|---|---|---|---|---|"
  let rows =
    list.map(ragas(), fn(r) {
      "| "
      <> r.name
      <> " | "
      <> thaat_label(r.thaat)
      <> " | "
      <> swara_variant_sequence_label(r.aroha)
      <> " | "
      <> swara_variant_sequence_label(r.avaroha)
      <> " | "
      <> swara_label(r.vadi)
      <> " | "
      <> swara_label(r.samvadi)
      <> " | "
      <> time_of_day_label(r.time)
      <> " | "
      <> r.mood
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

fn talas_table() -> String {
  let header =
    "| tala | matras | vibhags | sam | khali | tali |\n|---|---|---|---|---|---|"
  let rows =
    list.map(talas(), fn(t) {
      "| "
      <> t.name
      <> " | "
      <> int.to_string(t.matras)
      <> " | "
      <> string.join(list.map(t.vibhags, int.to_string), "|")
      <> " | "
      <> int.to_string(t.sam)
      <> " | "
      <> string.join(list.map(t.khali, int.to_string), ",")
      <> " | "
      <> string.join(list.map(t.tali, int.to_string), ",")
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

pub fn to_markdown() -> String {
  swaras_table()
  <> "\n\n"
  <> thaats_table()
  <> "\n\n"
  <> ragas_table()
  <> "\n\n"
  <> talas_table()
}

fn swara_variant_json(pair: #(Swara, Variant)) -> Json {
  json.string(swara_variant_label(pair))
}

pub fn to_json() -> Json {
  json.object([
    #(
      "swaras",
      json.array(swara_planes, fn(p) {
        json.object([
          #("svara", json.string(swara_label(p.0))),
          #("plane", json.string(p.1)),
        ])
      }),
    ),
    #(
      "thaats",
      json.array(layers, fn(l) {
        let t = thaat_of_layer(l)
        json.object([
          #("layer", json.string("L" <> int.to_string(l))),
          #("thaat", json.string(thaat_label(t))),
          #("svaras", json.array(thaat_swaras(t), swara_variant_json)),
        ])
      }),
    ),
    #(
      "ragas",
      json.array(ragas(), fn(r) {
        json.object([
          #("name", json.string(r.name)),
          #("thaat", json.string(thaat_label(r.thaat))),
          #("aroha", json.array(r.aroha, swara_variant_json)),
          #("avaroha", json.array(r.avaroha, swara_variant_json)),
          #("vadi", json.string(swara_label(r.vadi))),
          #("samvadi", json.string(swara_label(r.samvadi))),
          #("time", json.string(time_of_day_label(r.time))),
          #("mood", json.string(r.mood)),
        ])
      }),
    ),
    #(
      "talas",
      json.array(talas(), fn(t) {
        json.object([
          #("name", json.string(t.name)),
          #("matras", json.int(t.matras)),
          #("vibhags", json.array(t.vibhags, json.int)),
          #("sam", json.int(t.sam)),
          #("khali", json.array(t.khali, json.int)),
          #("tali", json.array(t.tali, json.int)),
        ])
      }),
    ),
  ])
}
