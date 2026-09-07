//// UOS Gītā Register (गीता): a register of Bhagavad Gītā verses used as higher-order
//// thinking rules — each verse grounds a real system rule with its classical `principle`
//// (a named thinking-discipline) and names which module or decision it applies to.
//// Operator directive (verbatim): "use gita as much as possible for higher order thinking".
//// Only verses whose exact text the author is confident of are admitted; each was checked
//// against the well-attested standard readings. STAMP: SC-TUI-ACL-001, #rocha-semiotics.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/set
import gleam/string

// ---------------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------------

pub type Verse {
  Verse(
    chapter: Int,
    verse: Int,
    iast: String,
    devanagari: String,
    english: String,
    principle: String,
    rule: String,
    applies_to: List(String),
  )
}

// ---------------------------------------------------------------------------
// Register
// ---------------------------------------------------------------------------

pub fn register() -> List(Verse) {
  [
    Verse(
      2,
      47,
      "karmaṇy evādhikāras te mā phaleṣu kadācana\nmā karma-phala-hetur bhūr mā te saṅgo 'stv akarmaṇi",
      "कर्मण्येवाधिकारस्ते मा फलेषु कदाचन।\nमा कर्मफलहेतुर्भूर्मा ते सङ्गोऽस्त्वकर्मणि॥",
      "You have a right to the action alone, never to its fruits; let not the fruit of action be your motive, nor attach yourself to inaction.",
      "niṣkāma karma",
      "An agent has authority over its own action, never over the verdict on it: agents never manufacture their own admission evidence.",
      ["aspects.admissible", "coord.authorize", "acl.validate"],
    ),
    Verse(
      2,
      50,
      "buddhi-yukto jahātīha ubhe sukṛta-duṣkṛte\ntasmād yogāya yujyasva yogaḥ karmasu kauśalam",
      "बुद्धियुक्तो जहातीह उभे सुकृतदुष्कृते।\nतस्माद्योगाय युज्यस्व योगः कर्मसु कौशलम्॥",
      "United with discipline, one abandons here both good and bad deeds; therefore devote yourself to yoga — yoga is skill in action.",
      "yogaḥ karmasu kauśalam",
      "Jidoka: quality is built into the doing, not inspected in afterward.",
      ["tps.jidoka", "manager.step"],
    ),
    Verse(
      3,
      35,
      "śreyān sva-dharmo viguṇaḥ para-dharmāt sv-anuṣṭhitāt\nsva-dharme nidhanaṃ śreyaḥ para-dharmo bhayāvahaḥ",
      "श्रेयान्स्वधर्मो विगुणः परधर्मात्स्वनुष्ठितात्।\nस्वधर्मे निधनं श्रेयः परधर्मो भयावहः॥",
      "Better one's own duty, imperfectly done, than another's duty well performed; better death in one's own duty — another's duty is fraught with fear.",
      "svadharma",
      "Disjoint ownership: each agent stays in its own declared scope, even imperfectly, rather than reaching into another's.",
      ["coord.authorize", "session_sync.claim", "agent_runtime.grant"],
    ),
    Verse(
      4,
      34,
      "tad viddhi praṇipātena paripraśnena sevayā\nupadekṣyanti te jñānaṃ jñāninas tattva-darśinaḥ",
      "तद्विद्धि प्रणिपातेन परिप्रश्नेन सेवया।\nउपदेक्ष्यन्ति ते ज्ञानं ज्ञानिनस्तत्त्वदर्शिनः॥",
      "Know that by prostration, by inquiry, and by service; the knowers who have seen the truth will instruct you in knowledge.",
      "praṇipāta-paripraśna-sevā",
      "The QUERY/QUESTION and INFORM/ANSWER performatives are exactly how a lesser-informed agent learns from a more-informed one.",
      ["acl Question/Answer"],
    ),
    Verse(
      6,
      5,
      "uddhared ātmanātmānaṃ nātmānam avasādayet\nātmaiva hy ātmano bandhur ātmaiva ripur ātmanaḥ",
      "उद्धरेदात्मनात्मानं नात्मानमवसादयेत्।\nआत्मैव ह्यात्मनो बन्धुरात्मैव रिपुरात्मनः॥",
      "Let a person raise the self by the self; let him not degrade himself; for the self alone is the friend of the self, and the self alone is its enemy.",
      "ātma-uddharaṇa",
      "Self-supervision: an agent's own liveness raises it back up; the dead-man's-switch is the failure mode when the self stops raising itself.",
      ["manager.health_status", "coord.freshness"],
    ),
    Verse(
      6,
      16,
      "nātyaśnatas tu yogo 'sti na caikāntam anaśnataḥ\nna cāti-svapna-śīlasya jāgrato naiva cārjuna",
      "नात्यश्नतस्तु योगोऽस्ति न चैकान्तमनश्नतः।\nन चातिस्वप्नशीलस्य जाग्रतो नैव चार्जुन॥",
      "Yoga is not for one who eats too much, nor for one who eats too little; nor for one given to too much sleep, nor for the one who is too wakeful, Arjuna.",
      "yukta-āhāra-vihāra",
      "Moderation: neither starve the line nor glut it — budgets and takt bound consumption.",
      ["tps.takt", "openrouter_worker.admit"],
    ),
    Verse(
      6,
      17,
      "yuktāhāra-vihārasya yukta-ceṣṭasya karmasu\nyukta-svapnāvabodhasya yogo bhavati duḥkha-hā",
      "युक्ताहारविहारस्य युक्तचेष्टस्य कर्मसु।\nयुक्तस्वप्नावबोधस्य योगो भवति दुःखहा॥",
      "For one moderate in food and recreation, moderate in effort in actions, moderate in sleep and wakefulness, yoga becomes the destroyer of sorrow.",
      "yukta-svapnāvabodha",
      "Even the dream cycle (svapna) is measured: bounded, not continuous — moderation applies to idle-time cognition too.",
      ["dream.svapna", "manager.health_status"],
    ),
    Verse(
      18,
      63,
      "iti te jñānam ākhyātaṃ guhyād guhyataraṃ mayā\nvimṛśyaitad aśeṣeṇa yathecchasi tathā kuru",
      "इति ते ज्ञानमाख्यातं गुह्याद्गुह्यतरं मया।\nविमृश्यैतदशेषेण यथेच्छसि तथा कुरु॥",
      "Thus this knowledge, more secret than all secrets, has been declared to you by Me; reflect on it fully, then act as you choose.",
      "vimarśa-svātantrya",
      "The operator's final authority: full analysis is offered, the choice to act remains the human's alone.",
      ["coord.authorize", "manager.step"],
    ),
    Verse(
      2,
      14,
      "mātrā-sparśās tu kaunteya śītoṣṇa-sukha-duḥkha-dāḥ\nāgamāpāyino 'nityās tāṃs titikṣasva bhārata",
      "मात्रास्पर्शास्तु कौन्तेय शीतोष्णसुखदुःखदाः।\nआगमापायिनोऽनित्यास्तांस्तितिक्षस्व भारत॥",
      "The contacts of the senses, Kaunteya, giving cold and heat, pleasure and pain, come and go and are impermanent; endure them, Bhārata.",
      "dvandva-sahiṣṇutā",
      "Transient dualities are endured: retry bounded failures rather than treating a passing fault as permanent.",
      ["herdr", "coord.freshness", "openrouter_worker.admit"],
    ),
    Verse(
      3,
      21,
      "yad yad ācarati śreṣṭhas tat tad evetaro janaḥ\nsa yat pramāṇaṃ kurute lokas tad anuvartate",
      "यद्यदाचरति श्रेष्ठस्तत्तदेवेतरो जनः।\nस यत्प्रमाणं कुरुते लोकस्तदनुवर्तते॥",
      "Whatever the best person does, that alone other people also do; whatever standard he sets, the world follows.",
      "pramāṇa-ācāra",
      "What the design authority (Fable) does becomes the standard the rest of the swarm follows.",
      ["coord.authorize", "holon"],
    ),
    Verse(
      4,
      18,
      "karmaṇy akarma yaḥ paśyed akarmaṇi ca karma yaḥ\nsa buddhimān manuṣyeṣu sa yuktaḥ kṛtsna-karma-kṛt",
      "कर्मण्यकर्म यः पश्येदकर्मणि च कर्म यः।\nस बुद्धिमान्मनुष्येषु स युक्तः कृत्स्नकर्मकृत्॥",
      "One who sees inaction in action, and action in inaction, is wise among men; he is disciplined, having accomplished all action.",
      "karmaṇy akarma",
      "The idle dream cycle is action-in-inaction: the line looks idle, yet hypothesis-generation is at work.",
      ["dream.svapna"],
    ),
    Verse(
      12,
      15,
      "yasmān nodvijate loko lokān nodvijate ca yaḥ\nharṣāmarṣa-bhayodvegair mukto yaḥ sa ca me priyaḥ",
      "यस्मान्नोद्विजते लोको लोकान्नोद्विजते च यः।\nहर्षामर्षभयोद्वेगैर्मुक्तो यः स च मे प्रियः॥",
      "He by whom the world is not agitated, and who is not agitated by the world, who is freed from joy, envy, fear and anxiety, is dear to Me.",
      "sama-citta",
      "Steady under andon: neither elated by a single green nor thrown by a single red.",
      ["manager.health_status", "tps.andon"],
    ),
    Verse(
      17,
      15,
      "anudvega-karaṃ vākyaṃ satyaṃ priya-hitaṃ ca yat\nsvādhyāyābhyasanaṃ caiva vāṅ-mayaṃ tapa ucyate",
      "अनुद्वेगकरं वाक्यं सत्यं प्रियहितं च यत्।\nस्वाध्यायाभ्यसनं चैव वाङ्मयं तप उच्यते॥",
      "Speech that causes no distress, that is truthful, pleasant and beneficial, and regular recitation — this is called the austerity of speech.",
      "satya-priya-hita vāc",
      "Honest reports: no inflation, no comfortable omission — a Report is truthful and useful, not merely pleasant.",
      ["acl Inform/Assert", "swarm.report"],
    ),
    Verse(
      16,
      1,
      "abhayaṃ sattva-saṃśuddhir jñāna-yoga-vyavasthitiḥ\ndānaṃ damaś ca yajñaś ca svādhyāyas tapa ārjavam",
      "अभयं सत्त्वसंशुद्धिर्ज्ञानयोगव्यवस्थितिः।\nदानं दमश्च यज्ञश्च स्वाध्यायस्तप आर्जवम्॥",
      "Fearlessness, purity of being, steadfastness in knowledge and yoga; charity, self-control, sacrifice, study, austerity, uprightness.",
      "daivī sampad (i)",
      "The first controls a trustworthy agent must carry: fearlessness to report bad news, purity of process, steadiness in method.",
      ["stpa.constraints"],
    ),
    Verse(
      16,
      2,
      "ahiṃsā satyam akrodhas tyāgaḥ śāntir apaiśunam\ndayā bhūteṣv aloluptvaṃ mārdavaṃ hrīr acāpalam",
      "अहिंसा सत्यमक्रोधस्त्यागः शान्तिरपैशुनम्।\nदया भूतेष्वलोलुप्त्वं मार्दवं ह्रीरचापलम्॥",
      "Non-harm, truthfulness, freedom from anger, renunciation, peace, absence of slander, compassion for beings, freedom from greed, gentleness, modesty, steadiness.",
      "daivī sampad (ii)",
      "The negative controls: what a trustworthy agent must not do — no forged evidence, no destructive action, no gaming the ledger.",
      ["stpa.constraints"],
    ),
    Verse(
      16,
      3,
      "tejaḥ kṣamā dhṛtiḥ śaucam adroho nāti-mānitā\nbhavanti sampadaṃ daivīm abhijātasya bhārata",
      "तेजः क्षमा धृतिः शौचमद्रोहो नातिमानिता।\nभवन्ति सम्पदं दैवीमभिजातस्य भारत॥",
      "Vigor, forgiveness, fortitude, purity, freedom from hatred, absence of excessive pride — these belong to one born to the divine endowment.",
      "daivī sampad (iii)",
      "Completing the control set: resilience under retry, tolerance of a peer's fault, and no status-seeking in the ledger.",
      ["stpa.constraints"],
    ),
    Verse(
      9,
      22,
      "ananyāś cintayanto māṃ ye janāḥ paryupāsate\nteṣāṃ nityābhiyuktānāṃ yoga-kṣemaṃ vahāmy aham",
      "अनन्याश्चिन्तयन्तो मां ये जनाः पर्युपासते।\nतेषां नित्याभियुक्तानां योगक्षेमं वहाम्यहम्॥",
      "To those who worship Me alone, ever disciplined, I carry what they lack and preserve what they have.",
      "yoga-kṣema",
      "The hive provides for its agents: memory and capability grants are acquired for an agent, and preserved across its lifecycle.",
      ["agent_runtime.grant", "agent_runtime.memory"],
    ),
    Verse(
      2,
      40,
      "nehābhikrama-nāśo 'sti pratyavāyo na vidyate\nsv-alpam apy asya dharmasya trāyate mahato bhayāt",
      "नेहाभिक्रमनाशोऽस्ति प्रत्यवायो न विद्यते।\nस्वल्पमप्यस्य धर्मस्य त्रायते महतो भयात्॥",
      "Here no effort is lost, nor is there any adverse result; even a little of this discipline protects one from great fear.",
      "abhikrama-anāśa",
      "The append-only ledger: no message, no attempt, is ever discarded — even a small record protects against a great loss.",
      ["board.append", "board.causal_gaps"],
    ),
    Verse(
      15,
      15,
      "sarvasya cāhaṃ hṛdi sanniviṣṭo mattaḥ smṛtir jñānam apohanaṃ ca\nvedaiś ca sarvair aham eva vedyo vedānta-kṛd veda-vid eva cāham",
      "सर्वस्य चाहं हृदि सन्निविष्टो मत्तः स्मृतिर्ज्ञानमपोहनं च।\nवेदैश्च सर्वैरहमेव वेद्यो वेदान्तकृद्वेदविदेव चाहम्॥",
      "I am seated in the hearts of all; from Me come memory, knowledge, and their loss; I alone am that which is to be known by all the Vedas.",
      "smṛti-jñāna-utpatti",
      "Memory (smṛti) is the seat of what an agent knows; it can also be lost (apohana), so it must be tended, not assumed permanent.",
      ["agent_runtime.memory"],
    ),
    Verse(
      13,
      1,
      "idaṃ śarīraṃ kaunteya kṣetram ity abhidhīyate\netad yo vetti taṃ prāhuḥ kṣetra-jña iti tad-vidaḥ",
      "इदं शरीरं कौन्तेय क्षेत्रमित्यभिधीयते।\nएतद्यो वेत्ति तं प्राहुः क्षेत्रज्ञ इति तद्विदः॥",
      "This body, Kaunteya, is called the field; the one who knows it, those who know call the knower of the field.",
      "kṣetra",
      "The data plane (kṣetra): the given, observed state that a controller comes to know.",
      ["board", "coord"],
    ),
    Verse(
      13,
      2,
      "kṣetra-jñaṃ cāpi māṃ viddhi sarva-kṣetreṣu bhārata\nkṣetra-kṣetrajñayor jñānaṃ yat taj jñānaṃ mataṃ mama",
      "क्षेत्रज्ञं चापि मां विद्धि सर्वक्षेत्रेषु भारत।\nक्षेत्रक्षेत्रज्ञयोर्ज्ञानं यत्तज्ज्ञानं मतं मम॥",
      "Know Me also as the knower of the field in all fields, Bhārata; the knowledge of the field and its knower — that I hold to be knowledge.",
      "kṣetra-jña",
      "The controller (kṣetra-jña): what observes and knows the data plane it is not identical to.",
      ["manager", "ooda"],
    ),
    Verse(
      18,
      14,
      "adhiṣṭhānaṃ tathā kartā karaṇaṃ ca pṛthag-vidham\nvividhāś ca pṛthak ceṣṭā daivaṃ caivātra pañcamam",
      "अधिष्ठानं तथा कर्ता करणं च पृथग्विधम्।\nविविधाश्च पृथक्चेष्टा दैवं चैवात्र पञ्चमम्॥",
      "The seat of action, the doer, the instruments of many kinds, the manifold distinct efforts, and providence — this is the fifth.",
      "pañcāṅga karma-kāraṇa",
      "Five factors of action: the OODA loop's seat (board), the agent (doer), its means (instruments), its effort, and the uncertainty of outcome.",
      ["ooda", "manager.step"],
    ),
    Verse(
      7,
      16,
      "catur-vidhā bhajante māṃ janāḥ su-kṛtino 'rjuna\nārto jijñāsur arthārthī jñānī ca bharatarṣabha",
      "चतुर्विधा भजन्ते मां जनाः सुकृतिनोऽर्जुन।\nआर्तो जिज्ञासुरर्थार्थी ज्ञानी च भरतर्षभ॥",
      "Four kinds of virtuous people worship Me, Arjuna: the distressed, the seeker of knowledge, the seeker of wealth, and the wise.",
      "catur-vidha bhakta",
      "Four agent roles: the andon-raiser (distressed), the worker (seeker of knowledge), the dispatcher (seeker of resource), and the design authority (the wise).",
      ["holon", "swarm"],
    ),
    Verse(
      11,
      33,
      "tasmāt tvam uttiṣṭha yaśo labhasva jitvā śatrūn bhuṅkṣva rājyaṃ samṛddham\nmayaivaite nihatāḥ pūrvam eva nimitta-mātraṃ bhava savyasācin",
      "तस्मात्त्वमुत्तिष्ठ यशो लभस्व जित्वा शत्रून्भुङ्क्ष्व राज्यं समृद्धम्।\nमयैवैते निहताः पूर्वमेव निमित्तमात्रं भव सव्यसाचिन्॥",
      "Therefore arise, win glory, conquer your enemies and enjoy a prosperous kingdom; by Me alone they are already slain; be merely the instrument, Savyasācin.",
      "nimitta-mātra",
      "The manager is a deterministic instrument, not the author of its outcomes: it executes the tracked act, it does not decide the world's result.",
      ["manager.step"],
    ),
    Verse(
      3,
      8,
      "niyataṃ kuru karma tvaṃ karma jyāyo hy akarmaṇaḥ\nśarīra-yātrāpi ca te na prasidhyed akarmaṇaḥ",
      "नियतं कुरु कर्म त्वं कर्म ज्यायो ह्यकर्मणः।\nशरीरयात्रापि च ते न प्रसिध्येदकर्मणः॥",
      "Perform your prescribed duty, for action is better than inaction; even the maintenance of your body would not succeed without action.",
      "niyata-karma",
      "Heartbeats and takt: perform the regular prescribed duty; even mere upkeep fails without it.",
      ["coord.freshness", "tps.takt"],
    ),
    Verse(
      2,
      48,
      "yogasthaḥ kuru karmāṇi saṅgaṃ tyaktvā dhanañjaya\nsiddhy-asiddhyoḥ samo bhūtvā samatvaṃ yoga ucyate",
      "योगस्थः कुरु कर्माणि सङ्गं त्यक्त्वा धनञ्जय।\nसिद्ध्यसिद्ध्योः समो भूत्वा समत्वं योग उच्यते॥",
      "Steadfast in yoga, perform actions, having abandoned attachment, Dhanañjaya, being even-minded in success and failure; evenness of mind is called yoga.",
      "samatvaṃ yoga",
      "Evenness of mind under variable outcomes reinforces equanimity: PASS and FAIL are handled by the same disciplined procedure.",
      ["manager.health_status"],
    ),
    Verse(
      3,
      19,
      "tasmād asaktaḥ satataṃ kāryaṃ karma samācara\nasakto hy ācaran karma param āpnoti pūruṣaḥ",
      "तस्मादसक्तः सततं कार्यं कर्म समाचर।\nअसक्तो ह्याचरन्कर्म परमाप्नोति पूरुषः॥",
      "Therefore, unattached, always perform the action that must be done; a person who acts without attachment attains the highest.",
      "asakta karma",
      "Act constantly, without attachment to being credited: the manager posts every tracked act whether or not it is noticed.",
      ["manager.step"],
    ),
  ]
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

pub fn find(ch: Int, v: Int) -> Result(Verse, Nil) {
  register() |> list.find(fn(x) { x.chapter == ch && x.verse == v })
}

pub fn for_module(name: String) -> List(Verse) {
  register() |> list.filter(fn(x) { list.contains(x.applies_to, name) })
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

pub fn validate_register() -> Result(Nil, String) {
  let all = register()
  use _ <- try_then(check_unique(all))
  use _ <- try_then(check_chapter_range(all))
  use _ <- try_then(check_verse_positive(all))
  use _ <- try_then(check_nonempty(all))
  Ok(Nil)
}

fn try_then(r: Result(a, e), f: fn(a) -> Result(b, e)) -> Result(b, e) {
  case r {
    Ok(a) -> f(a)
    Error(e) -> Error(e)
  }
}

fn check_unique(all: List(Verse)) -> Result(Nil, String) {
  let keys =
    list.map(all, fn(v) {
      int.to_string(v.chapter) <> "." <> int.to_string(v.verse)
    })
  case set.size(set.from_list(keys)) == list.length(keys) {
    True -> Ok(Nil)
    False -> Error("duplicate chapter.verse in gita register")
  }
}

fn check_chapter_range(all: List(Verse)) -> Result(Nil, String) {
  case list.find(all, fn(v) { v.chapter < 1 || v.chapter > 18 }) {
    Ok(v) ->
      Error(
        "BG "
        <> int.to_string(v.chapter)
        <> "."
        <> int.to_string(v.verse)
        <> ": chapter out of range 1..18",
      )
    Error(_) -> Ok(Nil)
  }
}

fn check_verse_positive(all: List(Verse)) -> Result(Nil, String) {
  case list.find(all, fn(v) { v.verse < 1 }) {
    Ok(v) ->
      Error(
        "BG "
        <> int.to_string(v.chapter)
        <> "."
        <> int.to_string(v.verse)
        <> ": verse must be >= 1",
      )
    Error(_) -> Ok(Nil)
  }
}

fn check_nonempty(all: List(Verse)) -> Result(Nil, String) {
  case
    list.find(all, fn(v) {
      v.iast == ""
      || v.devanagari == ""
      || v.english == ""
      || v.principle == ""
      || v.rule == ""
    })
  {
    Ok(v) ->
      Error(
        "BG "
        <> int.to_string(v.chapter)
        <> "."
        <> int.to_string(v.verse)
        <> ": empty required field",
      )
    Error(_) -> Ok(Nil)
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

pub fn to_markdown() -> String {
  let header =
    "| BG | Devanagari | IAST | English | principle | rule | applies_to |\n|---|---|---|---|---|---|---|"
  let rows =
    list.map(register(), fn(v) {
      "| "
      <> int.to_string(v.chapter)
      <> "."
      <> int.to_string(v.verse)
      <> " | "
      <> v.devanagari
      <> " | "
      <> v.iast
      <> " | "
      <> v.english
      <> " | "
      <> v.principle
      <> " | "
      <> v.rule
      <> " | "
      <> string.join(v.applies_to, ",")
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

pub fn to_json() -> Json {
  json.array(register(), verse_to_json)
}

fn verse_to_json(v: Verse) -> Json {
  json.object([
    #("chapter", json.int(v.chapter)),
    #("verse", json.int(v.verse)),
    #("iast", json.string(v.iast)),
    #("devanagari", json.string(v.devanagari)),
    #("english", json.string(v.english)),
    #("principle", json.string(v.principle)),
    #("rule", json.string(v.rule)),
    #("applies_to", json.array(v.applies_to, json.string)),
  ])
}

/// `BG <ch>.<v> · <iast first pada> ; en: <english head>`.
pub fn cite(ch: Int, v: Int) -> String {
  let head = "BG " <> int.to_string(ch) <> "." <> int.to_string(v)
  case find(ch, v) {
    Ok(verse) -> {
      let first_pada =
        verse.iast
        |> string.split("\n")
        |> list.first
        |> result.unwrap(verse.iast)
      let en_head =
        verse.english
        |> string.split(".")
        |> list.first
        |> result.unwrap(verse.english)
        |> string.trim
      head <> " · " <> first_pada <> " ; en: " <> en_head
    }
    Error(_) -> head <> " · unknown ; en: unknown"
  }
}
