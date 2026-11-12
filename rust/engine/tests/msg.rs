//! The Mean Streets of Gadgetzan pack (packs/msg, built by tools/pack.py on One Night in Karazhan and the packs before
//! it): the cards as on 2016-12-01 (build 15590), the tri-class cards (deckbuilding, the Arena, Discover), Jade Golems,
//! the Grimy Goons' hand buffs, Kazakus's potions, Patches the Pirate, Mayor Noggenfogger's random targets, the cards
//! that glow, the older cards of that day (patches 6.1.3 and 6.2), and whole bot games with every deck template. Needs
//! python3 (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{api, bot, pack, scenario, Game};
use serde_json::{json, Map, Value};
use std::path::PathBuf;
use std::sync::OnceLock;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The pack, built once (its recipe needs tools/pack.py); None without python3.
fn rs() -> Option<&'static Ruleset> {
    static R: OnceLock<Option<&'static Ruleset>> = OnceLock::new();
    *R.get_or_init(|| {
        let out = std::env::temp_dir().join(format!("msg-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/msg", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(ruleset::load(&files).expect("the built pack loads"))
    })
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const FIREBALL: &str = "VAN_CS2_029";
const MOONFIRE: &str = "VAN_CS2_008";
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];
const NONE: Id = -1;

struct T {
    g: Game,
}

/// A game in a scenario: p0 and p1 are merged over the defaults (10 mana each, decks of Wisps); p0's turn.
fn game(p0: Value, p1: Value) -> Option<T> {
    let rs = rs()?;
    let merge = |base: Value, over: Value| {
        let mut b = base.as_object().unwrap().clone();
        b.extend(over.as_object().unwrap().clone());
        Value::Object(b)
    };
    let d0 = json!({"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL});
    let d1 = json!({"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL});
    let sc = json!({"current": 0, "seed": 7, "players": [merge(d0, p0), merge(d1, p1)]});
    Some(T { g: scenario::build_in(rs, &sc).unwrap() })
}

macro_rules! scene {
    ($p0:tt, $p1:tt) => {
        match game(json!($p0), json!($p1)) {
            Some(t) => t,
            None => {
                eprintln!("no python3: skipped");
                return;
            }
        }
    };
}

impl T {
    fn nth(&self, p: usize, i: usize) -> Id {
        self.g.players[p].board[i]
    }
    fn on_board(&self, p: usize, card: &str) -> Id {
        *self.g.players[p].board.iter().find(|&&m| self.g.e(m).card_id == card).unwrap_or_else(|| panic!("{card} not on board {p}"))
    }
    fn cards(&self, p: usize) -> Vec<String> {
        self.g.players[p].board.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn hand(&self, p: usize) -> Vec<String> {
        self.g.players[p].hand.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn deck(&self, p: usize) -> Vec<String> {
        self.g.players[p].deck.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn hero(&self, p: usize) -> Id {
        self.g.players[p].hero
    }
    fn hp(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).health()
    }
    fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
    }
    fn count(&self, p: usize, k: &str) -> i64 {
        self.g.players[p].counts.get(k).map_or(0, |v| v.int())
    }
    fn act(&mut self, what: &str, f: impl Fn(&Map<String, Value>) -> bool) -> &mut Self {
        let a = self.g.legal_actions().into_iter().find(|a| f(a)).unwrap_or_else(|| panic!("no legal action: {what}"));
        let r = self.g.apply(&Value::Object(a));
        assert!(r.ok, "{what}: {}", r.error);
        assert_eq!(self.g.script_error.get(), None, "{what}");
        self
    }
    fn hand_id(&self, card: &str) -> Id {
        let p = self.g.current;
        *self.g.players[p].hand.iter().find(|&&e| self.g.e(e).card_id == card).unwrap_or_else(|| panic!("{card} not in hand"))
    }
    fn play(&mut self, card: &str, target: Id) -> &mut Self {
        let e = self.hand_id(card);
        let last = self.g.players[self.g.current].board.len() as i64;
        self.act(&format!("play {card}"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target && (int(a.get("pos")) == -1 || int(a.get("pos")) == last)
        })
    }
    fn choose_play(&mut self, card: &str, choice: i64, target: Id) -> &mut Self {
        let e = self.hand_id(card);
        let last = self.g.players[self.g.current].board.len() as i64;
        self.act(&format!("play {card} ({choice})"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("choice")) == choice && int(a.get("target")) == target
                && (int(a.get("pos")) == -1 || int(a.get("pos")) == last)
        })
    }
    fn can_play(&self, card: &str) -> bool {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e)
    }
    fn attack(&mut self, a: Id, d: Id) -> &mut Self {
        self.act("attack", |x| x["type"] == "attack" && int(x.get("attacker")) == a && int(x.get("defender")) == d)
    }
    fn end_turn(&mut self) -> &mut Self {
        self.act("end turn", |a| a["type"] == "end_turn")
    }
    fn cost(&self, card: &str) -> i64 {
        self.g.cost(self.hand_id(card))
    }
    fn pick(&mut self, i: usize) -> &mut Self {
        let id = self.g.pending_options()[i];
        self.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == id)
    }
    fn events(&self) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).collect()
    }
}

fn card_of(t: &T, e: Id) -> String {
    t.g.e(e).card_id.to_string()
}

const KAZAKUS: &str = "CFM_621";
const JADE_SPIRIT: &str = "CFM_715";

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(stats("CFM_637"), (1, 1, 1), "Patches the Pirate");
    assert!(c("CFM_637").keywords.iter().any(|k| k == "CHARGE"), "Patches had Charge until 2018");
    assert_eq!(stats("CFM_325"), (1, 1, 2), "Small-Time Buccaneer 1/2 until 7.1");
    assert_eq!(stats("CFM_715"), (4, 2, 3), "Jade Spirit 2/3");
    assert_eq!(c("CFM_715").race, "", "Jade Spirit: no tribe until 2017");
    assert_eq!(stats("CFM_902"), (6, 5, 3), "Aya Blackpaw 5/3");
    assert_eq!(stats("CFM_685"), (7, 5, 6), "Don Han'Cho 7 mana");
    assert_eq!(stats("CFM_321"), (2, 1, 1), "Grimestreet Informant 1/1");
    assert_eq!(c("CFM_649").cost, 3, "Kabal Courier 3 mana");
    assert_eq!(stats("CFM_852"), (5, 5, 3), "Lotus Agents 5 mana");
    assert_eq!(stats("CFM_605"), (5, 5, 6), "Drakonid Operative 5/6");
    assert_eq!(stats("CFM_750"), (9, 7, 9), "Krul 7/9");
    assert_eq!(stats("CFM_781"), (3, 2, 3), "Shaku 2/3");
    assert_eq!(stats("CFM_815"), (3, 2, 2), "Wickerflame 2/2");
    assert_eq!(c("CFM_343").cost, 6, "Jade Behemoth 6 mana");
    assert_eq!(c("CFM_312").cost, 7, "Jade Chieftain 7 mana");
    assert_eq!(c("CFM_707").cost, 4, "Jade Lightning 4 mana");
    assert_eq!(c("CFM_691").cost, 2, "Jade Swarmer 2 mana");
    assert_eq!(c("CFM_310").cost, 4, "Call in the Finishers 4 mana");
    assert_eq!(c("CFM_662").cost, 6, "Dragonfire Potion 6 mana");
    assert_eq!(stats("CFM_816"), (5, 4, 5), "Virmen Sensei 5 mana 4/5");
    // the tri-class cards
    for (id, classes) in [("CFM_621", ["MAGE", "PRIEST", "WARLOCK"]), ("CFM_715", ["DRUID", "ROGUE", "SHAMAN"]),
        ("CFM_685", ["HUNTER", "PALADIN", "WARRIOR"])] {
        assert_eq!(c(id).classes, classes.map(String::from).to_vec(), "{id}");
        assert_eq!(c(id).card_class, "NEUTRAL");
    }
    let gangs: Vec<_> = rs.cards.values().filter(|c| c.set == "GANGS").collect();
    assert_eq!(gangs.iter().filter(|c| c.collectible).count(), 132);
    assert_eq!(gangs.iter().filter(|c| !c.classes.is_empty()).count(), 9);
    // older cards of that day: patch 6.1.3 of 2016-10-03
    assert_eq!(c("VAN_CS2_103").cost, 1, "Charge");
    assert_eq!(c("VAN_CS2_108").cost, 2, "Execute");
    assert_eq!(c("VAN_CS2_045").cost, 2, "Rockbiter Weapon");
    assert_eq!((c("VAN_CS2_188").attack, c("VAN_CS2_188").health), (1, 1), "Abusive Sergeant");
    assert_eq!(c("OG_211").cost, 9, "Call of the Wild");
}

// --- multi-class cards: decks, the Arena, Discover -----------------------------------------------------------------

#[test]
fn tri_class_cards_go_into_their_classes_decks_only() {
    use classichs_engine::deck::Deck;
    let Some(rs) = rs() else { return };
    let deck = |hero: &str, card: &str| {
        let mut cards = vec![card.to_string()];
        cards.extend(std::iter::repeat_n(YETI.to_string(), 29).collect::<Vec<_>>());
        cards.truncate(30);
        let mut d = Deck { hero: hero.into(), cards: vec![], arena: false };
        let why = d.can_add_in(rs, card);
        d.cards = cards;
        (why, d)
    };
    for (hero, ok) in [("HERO_08", true), ("HERO_09", true), ("HERO_07", true), ("HERO_01", false), ("HERO_03", false)] {
        let (why, _) = deck(hero, KAZAKUS);
        assert_eq!(why.is_empty(), ok, "Kazakus for {hero}: {why}");
    }
    for (hero, ok) in [("HERO_06", true), ("HERO_03", true), ("HERO_02", true), ("HERO_08", false)] {
        let (why, _) = deck(hero, JADE_SPIRIT);
        assert_eq!(why.is_empty(), ok, "Jade Spirit for {hero}: {why}");
    }
    // the Arena offers it to each of its classes, as a class card
    let in_pool = |class: &str| classichs_engine::arena_draft::pool(rs, class, "legendary").into_iter().find(|(id, _)| id == KAZAKUS);
    let neutral_w = classichs_engine::arena_draft::pool(rs, "MAGE", "legendary").into_iter().find(|(id, _)| id == "VAN_EX1_116").unwrap().1;
    for class in ["MAGE", "PRIEST", "WARLOCK"] {
        let (_, w) = in_pool(class).unwrap_or_else(|| panic!("Kazakus in a {class} Arena"));
        assert!(w > neutral_w, "a class card's weight");
    }
    assert!(in_pool("WARRIOR").is_none() && in_pool("DRUID").is_none());
}

#[test]
fn tri_class_discover_offers_one_card_of_each_class() {
    let Some(rs) = rs() else { return };
    let mut kabal = std::collections::BTreeSet::new();
    for seed in 0..40 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL, "hand": ["CFM_649"]},
            {"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL}]});
        let mut g = scenario::build_in(rs, &sc).unwrap();
        let a = g.legal_actions().into_iter().find(|a| a["type"] == "play").unwrap();
        assert!(g.apply(&Value::Object(a)).ok);
        let opts = g.pending_options();
        assert_eq!(opts.len(), 3);
        for (o, class) in opts.iter().zip(["MAGE", "PRIEST", "WARLOCK"]) {
            let c = &g.e(*o).card;
            assert!(c.card_class == class || c.classes.iter().any(|k| k == class), "{} for {class}", c.id);
            if !c.classes.is_empty() {
                kabal.insert(c.id.clone());
            }
        }
        // only the player who discovers sees the options
        let theirs = api::snapshot(&g, 1);
        for o in &opts {
            assert_eq!(theirs["entities"][o.to_string()]["card"], "", "hidden from the opponent");
        }
    }
    assert!(!kabal.is_empty(), "a tri-class card can be one of the options");
    // a Warrior's Jeweled Scarab never offers Kabal Courier (a Mage, Priest and Warlock card)
    for seed in 0..40 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL, "hand": ["LOE_029"]},
            {"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL}]});
        let mut g = scenario::build_in(rs, &sc).unwrap();
        let a = g.legal_actions().into_iter().find(|a| a["type"] == "play").unwrap();
        assert!(g.apply(&Value::Object(a)).ok);
        for o in g.pending_options() {
            assert_ne!(g.e(o).card_id, "CFM_649", "seed {seed}");
        }
    }
}

// --- Jade Golems -----------------------------------------------------------------------------------------------------

#[test]
fn jade_golems_grow_for_each_player() {
    let mut t = scene!({"hand": [JADE_SPIRIT, "CFM_707", "CFM_713", "CFM_602", JADE_SPIRIT]}, {"hand": [JADE_SPIRIT]});
    let args = |t: &T, card: &str| api::snapshot(&t.g, 0)["entities"][t.hand_id(card).to_string()]["text_args"].clone();
    assert_eq!(args(&t, JADE_SPIRIT), json!(["1/1", ""]));
    t.play(JADE_SPIRIT, NONE);
    assert_eq!(t.cards(0), vec![JADE_SPIRIT, "CFM_712_t01"]);
    let h = t.hero(1);
    t.play("CFM_707", h);
    assert_eq!(t.hp(1), 26, "Jade Lightning: 4 damage");
    assert_eq!(t.cards(0).last().unwrap(), "CFM_712_t02");
    t.g.players[0].mana = 10;
    t.play("CFM_713", NONE);
    assert_eq!(t.cards(0).last().unwrap(), "CFM_712_t03");
    assert_eq!(t.g.players[0].max_mana, 10);
    t.choose_play("CFM_602", 1, NONE);
    assert_eq!(t.deck(0).iter().filter(|c| c.as_str() == "CFM_602").count(), 3, "Jade Idol: 3 copies shuffled in");
    assert_eq!(t.count(0, "JADE"), 3);
    assert_eq!(args(&t, JADE_SPIRIT), json!(["4/4", ""]));
    // the other player's count is their own
    t.end_turn();
    assert_eq!(args_of(&t, 1, JADE_SPIRIT), json!(["1/1", ""]));
    t.play(JADE_SPIRIT, NONE);
    assert_eq!(t.cards(1).last().unwrap(), "CFM_712_t01");
    // a full board: the count still grows
    let mut t = scene!({"hand": [JADE_SPIRIT], "board": [WISP, WISP, WISP, WISP, WISP, WISP]}, {});
    t.play(JADE_SPIRIT, NONE);
    assert_eq!(t.g.players[0].board.len(), 7);
    assert_eq!(t.count(0, "JADE"), 1);
    // "an 8/8" in English; at most 30/30, which costs 10
    let mut t = scene!({"hand": [JADE_SPIRIT]}, {});
    t.g.players[0].counts.insert("JADE".to_string(), 7i64);
    assert_eq!(args(&t, JADE_SPIRIT), json!(["8/8", "n"]));
    t.g.players[0].counts.insert("JADE".to_string(), 40i64);
    t.play(JADE_SPIRIT, NONE);
    let golem = *t.g.players[0].board.last().unwrap();
    assert_eq!((card_of(&t, golem), t.stats(golem), t.g.e(golem).card.cost), ("CFM_712_t30".into(), (30, 30), 10));
}

fn args_of(t: &T, p: usize, card: &str) -> Value {
    let e = *t.g.players[p].hand.iter().find(|&&e| t.g.e(e).card_id == card).unwrap();
    api::snapshot(&t.g, p as i64)["entities"][e.to_string()]["text_args"].clone()
}

#[test]
fn aya_brann_and_jade_deathrattles() {
    let mut t = scene!({"hand": ["CFM_902", "CFM_691"], "board": ["LOE_077"]}, {"hand": [FIREBALL]});
    t.play("CFM_902", NONE);
    assert_eq!(t.count(0, "JADE"), 2, "Brann: two Golems, 1/1 and 2/2");
    assert!(t.cards(0).contains(&"CFM_712_t01".to_string()) && t.cards(0).contains(&"CFM_712_t02".to_string()));
    let aya = t.on_board(0, "CFM_902");
    t.g.destroy(aya);
    t.g.resolve();
    assert!(t.cards(0).contains(&"CFM_712_t03".to_string()), "Aya's Deathrattle");
}

// --- the Grimy Goons -------------------------------------------------------------------------------------------------

#[test]
fn hand_buffs_stay_when_the_minion_is_played() {
    let mut t = scene!({"hand": ["CFM_753", YETI, WISP, FIREBALL, "CFM_685"]}, {});
    t.play("CFM_753", NONE);
    let y = t.hand_id(YETI);
    assert_eq!(t.stats(y), (5, 6), "Grimestreet Outfitter: +1/+1 in the hand");
    assert_eq!(t.stats(t.hand_id(WISP)), (2, 2));
    t.play(YETI, NONE);
    assert_eq!(t.stats(t.on_board(0, YETI)), (5, 6), "kept on the board");
    t.g.players[0].mana = 10;
    t.play("CFM_685", NONE);
    assert_eq!(t.stats(t.hand_id(WISP)), (7, 7), "Don Han'Cho: +5/+5 to the only minion left");
}

#[test]
fn grimy_triggers_and_hand_minions() {
    let mut t = scene!({"board": ["CFM_639", "CFM_754"], "hand": [WISP], "weapon": "CFM_631"}, {"board": [YETI]});
    let y = t.nth(1, 0);
    let h = t.hero(0);
    t.attack(h, y);
    assert_eq!(t.stats(t.hand_id(WISP)), (2, 2), "Brass Knuckles");
    t.end_turn();
    let w = *t.g.players[0].hand.iter().find(|&&e| t.g.e(e).card_id == WISP).unwrap();
    assert_eq!(t.stats(w), (5, 5), "Grimestreet Enforcer +1/+1, Grimy Gadgeteer +2/+2");
}

// --- Kazakus ---------------------------------------------------------------------------------------------------------

#[test]
fn kazakus_makes_a_potion_of_two_effects() {
    let Some(rs) = rs() else { return };
    let mut made = std::collections::BTreeSet::new();
    for seed in 0..30 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": [YETI, WISP, FIREBALL], "hand": [KAZAKUS],
             "board": [WISP]},
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL, "board": [YETI, WISP]}]});
        let mut t = T { g: scenario::build_in(rs, &sc).unwrap() };
        assert!(t.g.glows(t.hand_id(KAZAKUS)));
        t.play(KAZAKUS, NONE);
        let costs: Vec<String> = t.g.pending_options().iter().map(|&o| card_of(&t, o)).collect();
        assert_eq!(costs, vec!["CFM_621t11", "CFM_621t12", "CFM_621t13"]);
        let pick = (seed % 3) as usize;
        t.pick(pick);
        let first: Vec<String> = t.g.pending_options().iter().map(|&o| card_of(&t, o)).collect();
        assert_eq!(first.len(), 3);
        // the opponent sees none of the choices
        let theirs = api::snapshot(&t.g, 1);
        for o in t.g.pending_options() {
            assert_eq!(theirs["entities"][o.to_string()]["card"], "");
        }
        let a = first[0].clone();
        t.pick(0);
        let second: Vec<String> = t.g.pending_options().iter().map(|&o| card_of(&t, o)).collect();
        assert_eq!(second.len(), 3);
        assert!(!second.contains(&a), "the first effect is out of the second offer");
        let b = second[1].clone();
        t.pick(1);
        let potion = ["CFM_621t", "CFM_621t14", "CFM_621t15"][pick];
        let p = t.hand_id(potion);
        let args = api::snapshot(&t.g, 0)["entities"][p.to_string()]["text_args"].clone();
        let mut got: Vec<String> = args.as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_string()).collect();
        got.sort();
        let mut want = vec![a.clone(), b.clone()];
        want.sort();
        assert_eq!(got, want, "seed {seed}");
        made.insert(got.join("+"));
        // cast it (a target if one of them deals damage to one)
        t.g.players[0].mana = 10;
        let e = t.hand_id(potion);
        let act = t.g.legal_actions().into_iter().find(|x| x["type"] == "play" && int(x.get("entity")) == e);
        let act = act.unwrap_or_else(|| panic!("seed {seed}: the potion {got:?} can be cast"));
        assert!(t.g.apply(&Value::Object(act)).ok);
        assert_eq!(t.g.script_error.get(), None, "seed {seed}: {got:?}");
    }
    assert!(made.len() > 10, "{made:?}");
    // a deck with duplicates: nothing
    let mut t = scene!({"hand": [KAZAKUS], "deck": [YETI, YETI]}, {});
    assert!(!t.g.glows(t.hand_id(KAZAKUS)));
    t.play(KAZAKUS, NONE);
    assert!(t.g.pending_options().is_empty());
}

// --- Patches, Mayor Noggenfogger, Raza and the rest ------------------------------------------------------------------

#[test]
fn patches_comes_from_the_deck_after_a_pirate_is_played() {
    let mut t = scene!({"hand": ["VAN_CS2_146", "VAN_CS2_146"], "deck": [YETI, "CFM_637", WISP]}, {});
    t.play("VAN_CS2_146", NONE);
    assert_eq!(t.cards(0), vec!["VAN_CS2_146", "CFM_637"], "Southsea Deckhand, then Patches from the deck");
    assert!(!t.deck(0).contains(&"CFM_637".to_string()));
    t.play("VAN_CS2_146", NONE);
    assert_eq!(t.g.players[0].board.len(), 3, "only one Patches");
}

#[test]
fn noggenfogger_chooses_targets_at_random() {
    let Some(rs) = rs() else { return };
    let (mut astray, mut hits) = (0, 0);
    for seed in 0..30 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL, "hand": [MOONFIRE], "board": ["CFM_670", YETI]},
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL, "board": [{"card": WISP}, {"card": "VAN_CS2_179"}]}]});
        let mut t = T { g: scenario::build_in(rs, &sc).unwrap() };
        let h = t.hero(1);
        t.play(MOONFIRE, h);
        astray += (t.hp(1) == 30) as usize;
        // an attack on the hero past the Taunt? the Yeti attacks the Taunt minion; it may go anywhere among the enemies
        let y = t.on_board(0, YETI);
        let taunt = t.on_board(1, "VAN_CS2_179");
        t.attack(y, taunt);
        hits += (t.hp(1) < 30 && t.hp(1) != 29) as usize;
        assert_eq!(t.g.script_error.get(), None);
    }
    assert!(astray > 0, "Moonfire went astray sometimes");
    assert!(hits > 0, "an attack on the Taunt minion sometimes hit the hero");
}

#[test]
fn raza_makes_the_hero_power_free_for_the_game() {
    let mut t = scene!({"hero": "HERO_09", "hand": ["CFM_020"], "deck": [YETI, WISP]}, {});
    t.play("CFM_020", NONE);
    let hp = t.g.players[0].hero_power;
    assert_eq!(t.g.cost(hp), 0);
    t.end_turn().end_turn();
    assert_eq!(t.g.cost(hp), 0, "the next turns too");
    let mut t = scene!({"hero": "HERO_09", "hand": ["CFM_020"], "deck": [YETI, YETI]}, {});
    t.play("CFM_020", NONE);
    assert_eq!(t.g.cost(t.g.players[0].hero_power), 2);
}

#[test]
fn hidden_information_cards() {
    // Drakonid Operative: copies of three different cards of the opponent's deck, which the opponent never sees
    let mut t = scene!({"hero": "HERO_09", "hand": ["CFM_605", "BRM_004"]}, {"deck": [YETI, FIREBALL, WISP, WISP, "VAN_EX1_116"]});
    assert!(t.g.glows(t.hand_id("CFM_605")));
    t.play("CFM_605", NONE);
    let opts = t.g.pending_options();
    assert_eq!(opts.len(), 3);
    let mut ids: Vec<String> = opts.iter().map(|&o| card_of(&t, o)).collect();
    ids.dedup();
    assert_eq!(ids.len(), 3);
    let theirs = api::snapshot(&t.g, 1);
    for o in &opts {
        assert_eq!(theirs["entities"][o.to_string()]["card"], "");
    }
    t.pick(0);
    assert_eq!(t.g.players[1].deck.len(), 5, "the opponent's deck is as it was");
    // Dirty Rat: a minion of the opponent's hand onto their board
    let mut t = scene!({"hand": ["CFM_790"]}, {"hand": [FIREBALL, YETI]});
    t.play("CFM_790", NONE);
    assert_eq!(t.cards(1), vec![YETI]);
    assert_eq!(t.hand(1), vec![FIREBALL]);
}

#[test]
fn class_card_cards() {
    let mut t = scene!({"hand": ["CFM_066", "VAN_EX1_287", "CFM_687", "CFM_699", "VAN_EX1_506"], "deck": [YETI]}, {});
    t.play("CFM_066", NONE);
    assert_eq!(t.cost("VAN_EX1_287"), 0, "Kabal Lackey");
    t.play("VAN_EX1_287", NONE);
    t.play("CFM_687", NONE);
    let mut t2 = scene!({"hand": ["CFM_687", FIREBALL], "deck": [YETI, WISP]}, {});
    t2.play("CFM_687", NONE);
    assert_eq!(t2.cost(FIREBALL), 0, "Inkmaster Solia");
    t.g.players[0].mana = 10;
    t.play("CFM_699", NONE);
    let before = t.hp(0);
    t.g.players[0].mana = 0;
    assert!(t.can_play("VAN_EX1_506"), "Seadevil Stinger: the Murloc costs Health");
    t.play("VAN_EX1_506", NONE);
    assert_eq!(t.hp(0), before - 2);
    // Kabal Crystal Runner: (2) less for each Secret played
    let mut t = scene!({"hand": ["CFM_760", "VAN_EX1_287", "VAN_EX1_289"]}, {});
    t.play("VAN_EX1_287", NONE).play("VAN_EX1_289", NONE);
    assert_eq!(t.cost("CFM_760"), 2);
}

#[test]
fn kun_refreshes_the_crystals() {
    let mut t = scene!({"hand": ["CFM_308"]}, {});
    t.choose_play("CFM_308", 1, NONE);
    assert_eq!(t.g.players[0].mana, 10);
    let mut t = scene!({"hand": ["CFM_308"]}, {});
    t.choose_play("CFM_308", 0, NONE);
    assert_eq!(t.g.e(t.hero(0)).tag("ARMOR"), 10);
}

#[test]
fn attack_triggers() {
    // Knuckles hits the hero too; Wind-up Burglebot draws; Finja summons Murlocs from the deck
    let mut t = scene!({"board": ["CFM_333", "CFM_025", "CFM_344"], "deck": ["VAN_EX1_506", "VAN_EX1_506", YETI]},
        {"board": [WISP, WISP, WISP]});
    let (k, b, f) = (t.on_board(0, "CFM_333"), t.on_board(0, "CFM_025"), t.on_board(0, "CFM_344"));
    let w = t.nth(1, 0);
    t.attack(k, w);
    assert_eq!(t.hp(1), 27, "Knuckles");
    let w = t.nth(1, 0);
    let hand = t.g.players[0].hand.len();
    t.attack(b, w);
    assert_eq!(t.g.players[0].hand.len(), hand + 1, "Burglebot");
    let w = t.nth(1, 0);
    t.attack(f, w);
    assert_eq!(t.cards(0).iter().filter(|c| c.as_str() == "VAN_EX1_506").count(), 2, "Finja");
}

// --- older cards of that day -----------------------------------------------------------------------------------------

#[test]
fn older_cards_of_october_2016() {
    // Charge: Charge, but no hero this turn
    let mut t = scene!({"hand": ["VAN_CS2_103", YETI]}, {"board": [WISP]});
    t.play(YETI, NONE);
    let y = t.on_board(0, YETI);
    t.play("VAN_CS2_103", y);
    let h = t.hero(1);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("defender")) == h), "no hero this turn");
    let w = t.nth(1, 0);
    t.attack(y, w);
    // the Murloc lords help only their side
    let mut t = scene!({"hand": ["VAN_EX1_507"], "board": ["VAN_EX1_506"]}, {"board": ["VAN_EX1_506"]});
    t.play("VAN_EX1_507", NONE);
    assert_eq!(t.stats(t.on_board(0, "VAN_EX1_506")), (4, 2));
    assert_eq!(t.stats(t.on_board(1, "VAN_EX1_506")), (2, 1));
    // Tuskarr Totemic: a basic Totem
    let Some(rs) = rs() else { return };
    for seed in 0..20 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_02", "mana": 10, "max_mana": 10, "deck": FILL, "hand": ["AT_046"]},
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL}]});
        let mut t = T { g: scenario::build_in(rs, &sc).unwrap() };
        t.play("AT_046", NONE);
        let totem = card_of(&t, t.nth(0, 1));
        assert!(["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009"].contains(&totem.as_str()), "{totem}");
    }
    // Yogg-Saron stops once it dies
    for seed in 0..20 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL, "hand": ["OG_134"]},
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL, "board": [YETI, YETI]}]});
        let mut t = T { g: scenario::build_in(rs, &sc).unwrap() };
        t.g.players[0].counts.insert("SPELLS".to_string(), 25i64);
        t.play("OG_134", NONE);
        assert_eq!(t.g.script_error.get(), None);
        let casts = t.events().iter().filter(|e| e["type"] == "cast" || e["type"] == "fizzle").count();
        let alive = t.g.players[0].board.iter().any(|&m| card_of(&t, m) == "OG_134");
        assert!(alive || casts <= 25, "seed {seed}");
    }
    // Ethereal Peddler: the non-Rogue class cards; a tri-class card without Rogue too
    let mut t = scene!({"hero": "HERO_03", "hand": ["KAR_070", FIREBALL, KAZAKUS, JADE_SPIRIT, YETI]}, {});
    t.play("KAR_070", NONE);
    assert_eq!((t.cost(FIREBALL), t.cost(KAZAKUS), t.cost(JADE_SPIRIT), t.cost(YETI)), (2, 2, 4, 4));
}

#[test]
fn random_cards_never_fail() {
    let Some(rs) = rs() else { return };
    let hand = ["CFM_619", "CFM_663", "CFM_696", "CFM_852", "CFM_321", "CFM_940", "CFM_313", "CFM_781", "CFM_672",
        "CFM_806", "CFM_905", "CFM_811", "CFM_668", "AT_033", "KAR_069", "OG_118", "LOE_029"];
    for seed in 0..30 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_07", "mana": 10, "max_mana": 10, "deck": ["CFM_637", YETI, "VAN_EX1_116", "VAN_EX1_506", "CFM_621",
                "CFM_646", "CFM_659", "CFM_321"],
             "hand": hand[(seed as usize % 3)..].iter().take(9).collect::<Vec<_>>(), "board": [WISP]},
            {"hero": "HERO_03", "mana": 10, "max_mana": 10, "deck": FILL, "board": [YETI, "CFM_324"]}]});
        let mut g = scenario::build_in(rs, &sc).unwrap();
        for _ in 0..16 {
            g.players[0].mana = 10;
            let a = g.legal_actions().into_iter().find(|a| a["type"] == "play" || a["type"] == "choose");
            let Some(a) = a else { break };
            assert!(g.apply(&Value::Object(a)).ok);
            assert_eq!(g.script_error.get(), None, "seed {seed}");
        }
    }
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/msg/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30);
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
    assert!(decks.len() >= 10);
    let mut over = 0;
    let mut played = std::collections::BTreeSet::new();
    let (mut golems, mut potions, mut patches) = (0, 0, 0);
    for (i, (c0, d0)) in decks.iter().enumerate() {
        let (c1, d1) = &decks[(i + 3) % decks.len()];
        for seed in 0..3 {
            let mut g = Game::new_in(rs, c0, d0, c1, d1, seed + 10 * i as i64, -1, true);
            let mut steps = 0;
            while !g.game_over && g.turn < 80 {
                let p = if g.phase == "MULLIGAN" {
                    (0..2).find(|&p| !g.players[p].mulliganed).unwrap()
                } else {
                    g.pending.as_ref().map_or(g.current, |c| c.player)
                };
                let a = bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(a)).ok);
                assert_eq!(g.script_error.get(), None, "{c0} vs {c1}");
                steps += 1;
                assert!(steps < 4000);
            }
            over += g.game_over as usize;
            for h in &g.history {
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    if e["type"] == "play" && card.starts_with("CFM") {
                        played.insert(card.to_string());
                    }
                    golems += (e["type"] == "summon" && card.starts_with("CFM_712_t")) as usize;
                    potions += (e["type"] == "play" && matches!(card, "CFM_621t" | "CFM_621t14" | "CFM_621t15")) as usize;
                    patches += (e["type"] == "summon" && card == "CFM_637") as usize;
                }
            }
        }
    }
    assert!(over >= decks.len(), "most games end");
    eprintln!("GANGS cards played: {}: {played:?}; Jade Golems {golems}, Kazakus Potions {potions}, Patches {patches}",
        played.len());
    assert!(played.len() >= 30, "{played:?}");
    assert!(golems > 0 && patches > 0);
}

#[test]
fn secrets_of_the_gangs() {
    // Hidden Cache: the opponent plays a minion, a minion of your hand +2/+2
    let mut t = scene!({"hero": "HERO_05", "secrets": ["CFM_026"], "hand": [YETI]}, {"hand": [WISP]});
    t.end_turn();
    t.play(WISP, NONE);
    let y = *t.g.players[0].hand.iter().find(|&&e| t.g.e(e).card_id == YETI).unwrap();
    assert_eq!(t.stats(y), (6, 7), "Hidden Cache");
    assert!(t.g.players[0].secrets.is_empty());
    // no minion in your hand: it waits
    let mut t = scene!({"hero": "HERO_05", "secrets": ["CFM_026"]}, {"hand": [WISP]});
    t.end_turn();
    t.play(WISP, NONE);
    assert_eq!(t.g.players[0].secrets.len(), 1, "Hidden Cache waits for a minion in the hand");
    // Potion of Polymorph: the minion becomes a Sheep after its Battlecry
    let mut t = scene!({"secrets": ["CFM_620"]}, {"hand": [YETI]});
    t.end_turn();
    t.play(YETI, NONE);
    assert_eq!(t.cards(1), vec!["VAN_CS2_tk1"]);
    // Getaway Kodo: a friendly minion dies on the opponent's turn, back to the hand
    let mut t = scene!({"hero": "HERO_04", "secrets": ["CFM_800"], "board": [YETI]}, {"hand": [FIREBALL]});
    t.end_turn();
    let y = t.nth(0, 0);
    t.play(FIREBALL, y);
    assert!(t.g.players[0].board.is_empty());
    assert!(t.hand(0).contains(&YETI.to_string()), "{:?}", t.hand(0));
}

#[test]
fn deathrattles_by_attack_and_more() {
    // Meanstreet Marshal with 2 Attack (Abusive Sergeant this turn) draws when it dies
    let mut t = scene!({"board": ["CFM_759"], "hand": ["VAN_CS2_188", FIREBALL]}, {});
    let m = t.nth(0, 0);
    t.play("VAN_CS2_188", m);
    let n = t.g.players[0].hand.len();
    t.play(FIREBALL, m);
    assert_eq!(t.g.players[0].hand.len(), n, "Fireball out, a card in");
    // Rat Pack with 3 Attack: three Rats
    let mut t = scene!({"board": ["CFM_316"], "hand": ["VAN_CS2_087", FIREBALL]}, {});
    let m = t.nth(0, 0);
    t.play("VAN_CS2_087", m);
    t.play(FIREBALL, m);
    assert_eq!(t.cards(0), vec!["CFM_316t", "CFM_316t", "CFM_316t", "CFM_316t", "CFM_316t"], "2 + 3 Attack");
    // Weasel Tunneler goes into the opponent's deck
    let mut t = scene!({"board": ["CFM_095"], "hand": [MOONFIRE]}, {});
    let m = t.nth(0, 0);
    t.play(MOONFIRE, m);
    assert!(t.deck(1).contains(&"CFM_095".to_string()));
    // Sergeant Sally: her Attack to every enemy minion
    let mut t = scene!({"board": ["CFM_341"], "hand": [MOONFIRE]}, {"board": [WISP, YETI]});
    let m = t.nth(0, 0);
    t.play(MOONFIRE, m);
    assert_eq!(t.cards(1), vec![YETI]);
}

#[test]
fn heal_and_damage_triggers() {
    // Mana Geode healed: a 2/2 Crystal
    let mut t = scene!({"hero": "HERO_09", "board": [{"card": "CFM_606", "damage": 1}]}, {});
    let g = t.nth(0, 0);
    t.act("power", |a| a["type"] == "hero_power" && int(a.get("target")) == g);
    assert_eq!(t.cards(0), vec!["CFM_606", "CFM_606t"]);
    // Wickerflame Burnbristle heals your hero for its damage; with Auchenai Soulpriest it ends when the hero dies
    let mut t = scene!({"hero": "HERO_04", "board": ["CFM_815"], "damage": 10}, {"board": [YETI]});
    let (w, y) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(w, y);
    assert_eq!(t.hp(0), 22);
    let mut t = scene!({"hero": "HERO_04", "board": ["CFM_815", "VAN_EX1_591"], "damage": 20}, {"board": [YETI]});
    let (w, y) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(w, y);
    assert!(t.g.game_over, "the loop of 2016 kills the hero");
    // Alley Armorsmith: Armor as its damage
    let mut t = scene!({"board": ["CFM_756"]}, {"board": [YETI]});
    let (a, y) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(a, y);
    assert_eq!(t.g.e(t.hero(0)).tag("ARMOR"), 2);
    // Knuckles dies attacking a big minion: it still hits the enemy hero
    let mut t = scene!({"board": ["CFM_333"]}, {"board": ["VAN_NEW1_030"]});
    let (k, y) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(k, y);
    assert!(t.g.players[0].board.is_empty(), "Knuckles died");
    assert_eq!(t.hp(1), 27, "and hit the hero");
}

#[test]
fn deck_and_board_swaps() {
    // Madam Goya: the Wisp into the deck, a minion of the deck in its place
    let mut t = scene!({"hand": ["CFM_672"], "board": [WISP], "deck": [YETI, FIREBALL]}, {});
    let w = t.nth(0, 0);
    t.play("CFM_672", w);
    assert_eq!(t.cards(0), vec![YETI, "CFM_672"]);
    assert!(t.deck(0).contains(&WISP.to_string()) && !t.deck(0).contains(&YETI.to_string()));
    // Doppelgangster: three on the board, each a copy (a buff in the hand comes along)
    let mut t = scene!({"hand": ["CFM_753", "CFM_668"]}, {});
    t.play("CFM_753", NONE);
    t.play("CFM_668", NONE);
    let gs: Vec<Id> = t.g.players[0].board.iter().copied().filter(|&m| card_of(&t, m).starts_with("CFM_668")).collect();
    assert_eq!(gs.len(), 3);
    assert!(gs.iter().all(|&m| t.stats(m) == (3, 3)), "{:?}", gs.iter().map(|&m| t.stats(m)).collect::<Vec<_>>());
    // Small-Time Recruits: the 1-Cost minions of the deck
    let mut t = scene!({"hand": ["CFM_905"], "deck": [YETI, WISP, "VAN_CS2_168", YETI, "VAN_EX1_008"]}, {});
    t.play("CFM_905", NONE);
    let mut h = t.hand(0);
    h.sort();
    assert_eq!(h, vec!["VAN_CS2_168", "VAN_EX1_008"], "only two in the deck: two (Wisp costs 0)");
    // Devolve: each enemy minion one Cost less
    let mut t = scene!({"hero": "HERO_02", "hand": ["CFM_696"]}, {"board": [YETI, "VAN_CS2_168"]});
    t.play("CFM_696", NONE);
    let costs: Vec<i64> = t.g.players[1].board.iter().map(|&m| t.g.e(m).card.cost).collect();
    assert_eq!(costs, vec![3, 0]);
    // Pilfered Power: an empty crystal for each minion; at 10, Excess Mana
    let mut t = scene!({"hero": "HERO_06", "hand": ["CFM_616"], "board": [WISP, WISP], "mana": 5, "max_mana": 5}, {});
    t.play("CFM_616", NONE);
    assert_eq!((t.g.players[0].mana, t.g.players[0].max_mana), (2, 7));
    let mut t = scene!({"hero": "HERO_06", "hand": ["CFM_616"], "board": [WISP]}, {});
    t.play("CFM_616", NONE);
    assert_eq!(t.hand(0), vec!["CS2_013t"]);
}

#[test]
fn kazakus_with_brann_makes_two_potions() {
    let mut t = scene!({"hand": [KAZAKUS], "board": ["LOE_077"], "deck": [YETI, WISP]}, {});
    t.play(KAZAKUS, NONE);
    for _ in 0..6 {
        t.pick(0);
    }
    assert!(t.g.pending_options().is_empty());
    let potions = t.hand(0).iter().filter(|c| c.starts_with("CFM_621t")).count();
    assert_eq!(potions, 2, "{:?}", t.hand(0));
}
