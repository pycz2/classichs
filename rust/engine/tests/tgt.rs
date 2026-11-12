//! The Grand Tournament pack (packs/tgt, built by tools/pack.py on Blackrock Mountain, Goblins vs Gnomes, Naxxramas
//! and Classic): the cards as on 2015-08-24 (build 9786), Inspire, Joust, the upgraded Hero Powers and the engine
//! features they need (POWER_USES and POWERS_USED, POWER_DAMAGE, CANT_ATTACK_HEROES, Hero Power cost mods,
//! `hand.discard`, `g.create`), and whole bot games with every deck template. Needs python3 (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{bot, pack, scenario, Game};
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
        let out = std::env::temp_dir().join(format!("tgt-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/tgt", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(ruleset::load(&files).expect("the built pack loads"))
    })
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const FIREBALL: &str = "VAN_CS2_029";
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];

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
    fn hero(&self, p: usize) -> Id {
        self.g.players[p].hero
    }
    fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
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
    fn can_target(&self, card: &str, target: Id) -> bool {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target)
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
}

const NONE: Id = -1;

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
    fn power(&mut self, target: Id) -> &mut Self {
        self.act("hero power", |a| a["type"] == "hero_power" && int(a.get("target")) == target)
    }
    fn power_targets(&self) -> Vec<Id> {
        self.g.legal_actions().iter().filter(|a| a["type"] == "hero_power").map(|a| int(a.get("target"))).collect()
    }
    fn deck(&self, p: usize) -> Vec<String> {
        self.g.players[p].deck.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn hp(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).health()
    }
    fn choose_play(&mut self, card: &str, choice: i64) -> &mut Self {
        let e = self.hand_id(card);
        self.act(&format!("play {card} ({choice})"), |a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("choice")) == choice)
    }
}

impl T {
    fn choose(&mut self, card: &str) -> &mut Self {
        let id = self.g.pending_options().into_iter().find(|&o| self.g.e(o).card_id == card).expect("an option");
        self.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == id)
    }
    fn power_card(&self, p: usize) -> &str {
        self.g.e(self.g.players[p].hero_power).card_id
    }
    fn power_cost(&self, p: usize) -> i64 {
        self.g.cost(self.g.players[p].hero_power)
    }
    fn can_power(&self) -> bool {
        !self.power_targets().is_empty()
    }
    fn events(&self, ty: &str) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).filter(|e| e["type"] == ty).collect()
    }
}

const FROSTBOLT: &str = "VAN_CS2_024";
const AZURE_DRAKE: &str = "VAN_EX1_284";
const VELEN: &str = "VAN_EX1_350";
const OGRE: &str = "VAN_CS2_200"; // 6-mana 6/7

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(stats("AT_132"), (6, 6, 3), "Justicar Trueheart 6 mana 6/3 until 2024");
    assert_eq!(stats("AT_008"), (6, 6, 6), "Coldarra Drake 6/6");
    assert_eq!(stats("AT_011"), (4, 3, 5), "Holy Champion before the 2023 rework");
    assert_eq!(stats("AT_012"), (4, 5, 4), "Spawn of Shadows");
    assert_eq!(stats("AT_014"), (3, 3, 3), "Shadowfiend");
    assert_eq!(stats("AT_079"), (6, 6, 6), "Mysterious Challenger");
    assert_eq!(stats("AT_090"), (5, 4, 3), "Mukla's Champion 4/3");
    assert_eq!(stats("AT_075"), (3, 2, 4), "Warhorse Trainer 2/4");
    assert_eq!(stats("AT_047"), (4, 4, 4), "Draenei Totemcarver 4/4");
    assert_eq!((c("AT_034").cost, c("AT_034").durability), (4, 3), "Poisoned Blade 4 mana");
    assert_eq!((c("AT_050").cost, c("AT_050").durability), (4, 4), "Charged Hammer 2/4 for 4");
    assert_eq!((c("AT_051").mana_lock, c("AT_053").mana_lock), (5, 2), "Elemental Destruction and Ancestral Knowledge");
    for (id, cost) in [("AT_015", 2), ("AT_025", 6), ("AT_036", 9), ("AT_043", 4), ("AT_046", 3), ("AT_061", 2), ("AT_062", 6),
        ("AT_063", 7), ("AT_064", 3), ("AT_078", 6), ("AT_035t", 0)] {
        assert_eq!(c(id).cost, cost, "{id}");
    }
    assert_eq!(c("AT_024").race, "", "Demonfuse is no Demon (a mistake of the release data)");
    for id in ["AT_092", "AT_103", "AT_036", "AT_094", "AT_089"] {
        assert_eq!(c(id).race, "", "{id}: no tribe in 2015");
    }
    assert_eq!(rs.collectible.iter().filter(|id| id.starts_with("AT_")).count(), 132);
    assert_eq!(c("AT_132_MAGE").kind, "POWER");
    assert!(c("AT_125").keywords.iter().any(|k| k == "CANNOT_ATTACK_HEROES"));
    // older cards: unchanged numbers, the Murloc token of the data of that day
    assert_eq!((c("VAN_EX1_116").cost, c("BRM_008").cost, c("PRO_001at").cost), (5, 5, 0));
}

#[test]
fn inspire_comes_after_the_hero_power() {
    let mut t = scene!({"hero": "HERO_04", "board": ["AT_082", "AT_099", "AT_100"]}, {});
    t.power(NONE);
    assert_eq!(t.cards(0), vec!["AT_082", "AT_099", "AT_100", "VAN_CS2_101t", "AT_099t", "VAN_CS2_101t"], "the Recruit first");
    assert_eq!(t.stats(t.nth(0, 0)), (2, 2), "Lowly Squire +1 Attack");
    // the opponent's power does not inspire
    let mut t = scene!({"hero": "HERO_01"}, {"board": ["AT_082"]});
    t.power(NONE);
    assert_eq!(t.stats(t.nth(1, 0)), (1, 2));
}

#[test]
fn justicar_upgrades_a_basic_power() {
    for (hero, up) in [("HERO_01", "AT_132_WARRIOR"), ("HERO_02", "AT_132_SHAMAN"), ("HERO_03", "AT_132_ROGUE"),
        ("HERO_04", "AT_132_PALADIN"), ("HERO_05", "AT_132_HUNTER"), ("HERO_06", "AT_132_DRUID"),
        ("HERO_07", "AT_132_WARLOCK"), ("HERO_08", "AT_132_MAGE"), ("HERO_09", "AT_132_PRIEST")] {
        let mut t = scene!({"hero": hero, "hand": ["AT_132"], "hero_power_used": true}, {});
        t.play("AT_132", NONE);
        assert_eq!(t.power_card(0), up, "{hero}");
        assert!(t.can_power(), "{hero}: the new power is unused");
    }
    let mut t = scene!({"hero": "HERO_02", "hero_power": "AT_050t", "hand": ["AT_132"]}, {});
    t.play("AT_132", NONE);
    assert_eq!(t.power_card(0), "AT_050t", "Lightning Jolt is no basic power");
    // a copied basic power is upgraded too
    let mut t = scene!({"hero": "HERO_01", "mana": 20, "hand": ["AT_098", "AT_132"]}, {"hero": "HERO_08"});
    t.play("AT_098", NONE);
    assert_eq!(t.power_card(0), "VAN_HERO_08bp");
    t.play("AT_132", NONE);
    assert_eq!(t.power_card(0), "AT_132_MAGE");
}

#[test]
fn upgraded_powers() {
    let mut t = scene!({"hero": "HERO_01", "hero_power": "AT_132_WARRIOR"}, {});
    t.power(NONE);
    assert_eq!(t.g.e(t.hero(0)).tag(t.g.n().armor), 4);
    let mut t = scene!({"hero": "HERO_06", "hero_power": "AT_132_DRUID"}, {});
    t.power(NONE);
    assert_eq!((t.g.attack_value(t.hero(0)), t.g.e(t.hero(0)).tag(t.g.n().armor)), (2, 2));
    let mut t = scene!({"hero": "HERO_05", "hero_power": "AT_132_HUNTER"}, {});
    t.power(NONE);
    assert_eq!(t.hp(1), 27);
    let mut t = scene!({"hero": "HERO_04", "hero_power": "AT_132_PALADIN"}, {});
    t.power(NONE);
    assert_eq!(t.cards(0), vec!["VAN_CS2_101t", "VAN_CS2_101t"]);
    let mut t = scene!({"hero": "HERO_09", "hero_power": "AT_132_PRIEST", "damage": 10}, {});
    t.power(t.hero(0));
    assert_eq!(t.hp(0), 24);
    let mut t = scene!({"hero": "HERO_03", "hero_power": "AT_132_ROGUE"}, {});
    t.power(NONE);
    let w = t.g.players[0].weapon.unwrap();
    assert_eq!((t.g.e(w).card_id, t.g.e(w).atk(), t.g.e(w).tag(t.g.n().durability)), ("AT_132_ROGUEt", 2, 2));
    let mut t = scene!({"hero": "HERO_07", "hero_power": "AT_132_WARLOCK"}, {});
    t.power(NONE);
    assert_eq!((t.hp(0), t.hand(0).len()), (30, 1), "Soul Tap: a card, no damage");
    let mut t = scene!({"hero": "HERO_08", "hero_power": "AT_132_MAGE"}, {"board": [YETI]});
    t.power(t.nth(1, 0));
    assert_eq!(t.stats(t.nth(1, 0)), (4, 3));
}

#[test]
fn totemic_slam_chooses_a_totem() {
    let mut t = scene!({"hero": "HERO_02", "hero_power": "AT_132_SHAMAN", "board": ["VAN_CS2_050"]}, {});
    t.power(NONE);
    assert_eq!(t.g.pending_options().len(), 4);
    t.choose("AT_132_SHAMANb");
    assert_eq!(t.cards(0), vec!["VAN_CS2_050", "VAN_CS2_050"], "a Searing Totem you already have");
}

#[test]
fn coldarra_drake_and_garrison_commander() {
    let mut t = scene!({"hero": "HERO_08", "board": ["AT_008"]}, {});
    for _ in 0..4 {
        t.power(t.hero(1));
    }
    assert_eq!((t.hp(1), t.g.players[0].mana), (26, 2));
    let mut t = scene!({"hero": "HERO_01", "board": ["AT_080", "AT_080"]}, {});
    t.power(NONE).power(NONE);
    assert!(!t.can_power(), "twice a turn, two Commanders too");
    t.end_turn().end_turn();
    t.power(NONE).power(NONE);
    assert!(!t.can_power());
    // played after the first use: one more
    let mut t = scene!({"hero": "HERO_01", "mana": 20, "hand": ["AT_080", "AT_008"]}, {});
    t.power(NONE);
    assert!(!t.can_power());
    t.play("AT_080", NONE);
    assert!(t.can_power());
    t.power(NONE);
    assert!(!t.can_power());
    t.play("AT_008", NONE);
    assert!(t.can_power(), "Coldarra Drake: any number");
}

#[test]
fn frost_giant_counts_every_power_use() {
    let mut t = scene!({"hero": "HERO_01", "board": ["AT_008"], "deck": [WISP, WISP, WISP, "AT_120"]}, {});
    t.power(NONE).power(NONE).power(NONE);
    t.end_turn().end_turn();
    assert_eq!(t.cost("AT_120"), 7, "three uses before it was drawn");
    t.power(NONE);
    assert_eq!(t.cost("AT_120"), 6);
}

#[test]
fn power_costs() {
    let mut t = scene!({"hero": "HERO_01", "board": ["AT_085"]}, {});
    assert_eq!(t.power_cost(0), 1, "Maiden of the Lake");
    let mut t = scene!({"hand": ["AT_086"]}, {});
    t.play("AT_086", NONE);
    assert_eq!(t.power_cost(1), 2, "not this turn");
    t.end_turn();
    assert_eq!(t.power_cost(1), 7, "Saboteur: next turn");
    t.end_turn().end_turn();
    assert_eq!(t.power_cost(1), 2);
    let mut t = scene!({"hero": "HERO_01", "hand": ["AT_115"]}, {});
    t.play("AT_115", NONE);
    t.end_turn().end_turn();
    assert_eq!(t.power_cost(0), 0, "Fencing Coach: the next use, on a later turn too");
    t.power(NONE);
    t.end_turn().end_turn();
    assert_eq!(t.power_cost(0), 2, "used up");
}

#[test]
fn fallen_hero_adds_before_velen() {
    let mut t = scene!({"board": ["AT_003"]}, {});
    t.power(t.hero(1));
    assert_eq!(t.hp(1), 28);
    let mut t = scene!({"board": ["AT_003", "AT_003", VELEN]}, {});
    t.power(t.hero(1));
    assert_eq!(t.hp(1), 24, "(1 + 2) x 2");
    let mut t = scene!({"hand": [FROSTBOLT], "board": ["AT_003"]}, {});
    t.play(FROSTBOLT, t.hero(1));
    assert_eq!(t.hp(1), 27, "spells are not powers");
}

#[test]
fn wilfred_makes_life_tap_cards_free() {
    let mut t = scene!({"hero": "HERO_07", "board": ["AT_027"], "deck": [OGRE, OGRE]}, {});
    t.power(NONE);
    assert_eq!(t.cost(OGRE), 0);
    let mut t = scene!({"hero": "HERO_07", "board": ["AT_027"], "deck": [OGRE, OGRE]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.cost(OGRE), 6, "a turn's draw is not the power's");
}

#[test]
fn jousts() {
    // won: Elekk draws the revealed minion; the event shows both cards
    let mut t = scene!({"hand": ["AT_058"], "deck": [OGRE, FIREBALL]}, {"deck": [WISP]});
    t.play("AT_058", NONE);
    assert_eq!(t.hand(0), vec![OGRE]);
    let j = t.events("joust");
    assert_eq!((j[0]["card"].as_str(), j[0]["foe_card"].as_str(), j[0]["won"].as_bool()), (Some(OGRE), Some(WISP), Some(true)));
    // a tie is lost
    let mut t = scene!({"hand": ["AT_133"], "deck": [WISP]}, {"deck": [WISP]});
    t.play("AT_133", NONE);
    assert_eq!(t.stats(t.nth(0, 0)), (1, 2));
    // no minion in the other deck: won; none in yours: lost, nothing revealed
    let mut t = scene!({"hand": ["AT_133"], "deck": [WISP]}, {"deck": [FIREBALL]});
    t.play("AT_133", NONE);
    assert_eq!(t.stats(t.nth(0, 0)), (2, 3));
    let mut t = scene!({"hand": ["AT_112"], "deck": [FIREBALL]}, {"deck": [WISP]});
    t.play("AT_112", NONE);
    assert!(!t.g.e(t.nth(0, 0)).has("TAUNT"));
    assert_eq!(t.events("joust")[0]["card"].as_str(), Some(""));
    // the cost of the card, not its cost now
    let mut t = scene!({"hand": ["AT_108"], "deck": [{"card": OGRE, "enchantments": [{"cost": -5}]}]}, {"deck": [YETI]});
    t.play("AT_108", NONE);
    assert!(t.g.e(t.nth(0, 0)).has("CHARGE"), "6 against 4");
    // a weapon's Joust and Healing Wave
    let mut t = scene!({"hero": "HERO_04", "hand": ["AT_077"], "deck": [OGRE]}, {"deck": [WISP]});
    t.play("AT_077", NONE);
    let w = t.g.players[0].weapon.unwrap();
    assert_eq!(t.g.e(w).tag(t.g.n().durability), 3);
    let mut t = scene!({"hero": "HERO_02", "hand": ["AT_048"], "deck": [OGRE], "damage": 20}, {"deck": [WISP]});
    t.play("AT_048", t.hero(0));
    assert_eq!(t.hp(0), 24);
}

#[test]
fn icehowl_cannot_attack_heroes() {
    let mut t = scene!({"hand": ["AT_125"]}, {"board": [WISP]});
    t.play("AT_125", NONE);
    let i = t.on_board(0, "AT_125");
    let targets: Vec<i64> = t.g.legal_actions().iter().filter(|a| a["type"] == "attack" && int(a.get("attacker")) == i).map(|a| int(a.get("defender"))).collect();
    assert_eq!(targets, vec![t.nth(1, 0)], "Charge, but only the minion");
}

#[test]
fn bolf_takes_the_heros_damage() {
    let mut t = scene!({"hand": [FIREBALL]}, {"board": ["AT_124"], "armor": 5});
    t.play(FIREBALL, t.hero(1));
    assert_eq!((t.hp(1), t.stats(t.nth(1, 0)).1, t.g.e(t.hero(1)).tag(t.g.n().armor)), (30, 3, 5), "before Armor");
}

#[test]
fn fist_of_jaraxxus_on_discard() {
    let mut t = scene!({"hero": "HERO_07", "hand": ["VAN_EX1_310", "AT_022"]}, {});
    t.play("VAN_EX1_310", NONE);
    assert_eq!(t.hp(1), 26, "discarded by Doomguard: 4 damage");
    let mut t = scene!({"hero": "HERO_07", "hand": ["AT_022"]}, {});
    t.play("AT_022", NONE);
    assert_eq!(t.hp(1), 26);
    let mut t = scene!({"hero": "HERO_07", "hand": ["VAN_EX1_310", WISP], "board": ["AT_021"]}, {});
    t.play("VAN_EX1_310", NONE);
    assert_eq!(t.stats(t.on_board(0, "AT_021")), (4, 3), "Tiny Knight of Evil: +1/+1 per card");
}

#[test]
fn poisoned_blade_grows_with_the_power() {
    let mut t = scene!({"hero": "HERO_03", "hand": ["AT_034"]}, {});
    t.play("AT_034", NONE);
    t.power(NONE);
    let w = t.g.players[0].weapon.unwrap();
    assert_eq!((t.g.e(w).card_id, t.g.e(w).atk(), t.g.e(w).tag(t.g.n().durability)), ("AT_034", 2, 3));
}

#[test]
fn mysterious_challenger_and_secrets() {
    let deck = json!(["VAN_EX1_130", "VAN_EX1_130", "VAN_EX1_132", "AT_073", "VAN_EX1_136", "VAN_EX1_379", "VAN_EX1_287", WISP]);
    let mut t = scene!({"hero": "HERO_04", "hand": ["AT_079"], "deck": deck, "secrets": ["VAN_EX1_287"]}, {});
    t.play("AT_079", NONE);
    let s: Vec<&str> = t.g.players[0].secrets.iter().map(|&e| t.g.e(e).card_id).collect();
    assert_eq!(s.len(), 5, "{s:?}: at most 5, one Noble Sacrifice, not a second Counterspell");
    // Competitive Spirit goes off when its owner's turn starts
    let mut t = scene!({"hero": "HERO_04", "hand": ["AT_073"], "board": [WISP]}, {});
    t.play("AT_073", NONE);
    t.end_turn();
    assert_eq!(t.g.players[0].secrets.len(), 1, "not on the opponent's turn");
    t.end_turn();
    assert_eq!((t.g.players[0].secrets.len(), t.stats(t.nth(0, 0))), (0, (2, 2)));
    // Bear Trap after the hero is attacked; Effigy
    let mut t = scene!({"hero": "HERO_05", "secrets": ["AT_060", "AT_002"], "board": [WISP]}, {"board": [YETI, YETI]});
    t.end_turn();
    let (y, y2) = (t.nth(1, 0), t.nth(1, 1));
    t.attack(y, t.hero(0));
    assert_eq!(t.cards(0), vec![WISP, "VAN_CS2_125"]);
    let bear = t.nth(0, 1);
    t.attack(y2, bear);
    let c = t.cards(0);
    assert_eq!(c.len(), 2, "{c:?}");
    assert_eq!(rs().unwrap().card(&c[1]).cost, 3, "Effigy: a 3-Cost minion for the Grizzly");
}

#[test]
fn resurrect_needs_a_dead_friend() {
    let t = scene!({"hero": "HERO_09", "hand": ["BRM_017"]}, {});
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play"), "patch 3.0.0.9786");
    let mut t = scene!({"hero": "HERO_09", "hand": [FIREBALL, "BRM_017"], "board": [YETI]}, {});
    let y = t.nth(0, 0);
    t.play(FIREBALL, y).play("BRM_017", NONE);
    assert_eq!(t.cards(0), vec![YETI]);
}

#[test]
fn varian_puts_minions_into_play() {
    let mut t = scene!({"hero": "HERO_01", "hand": ["AT_072"], "deck": [WISP, FIREBALL, YETI]}, {});
    t.play("AT_072", NONE);
    assert_eq!(t.cards(0), vec!["AT_072", YETI, WISP], "the top card first, then the next");
    assert_eq!(t.hand(0), vec![FIREBALL], "a spell is drawn");
}

#[test]
fn mistcaller_and_lock_and_load() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["AT_054", WISP, FIREBALL], "deck": [YETI]}, {});
    t.play("AT_054", NONE);
    let w = t.hand_id(WISP);
    assert_eq!(t.stats(w), (2, 2));
    t.end_turn().end_turn();
    assert_eq!(t.stats(t.hand_id(YETI)), (5, 6), "drawn later: +1/+1 (as in 2015)");
    let Some(rs) = rs() else { return };
    let mut t = scene!({"hero": "HERO_05", "hand": ["AT_061", "VAN_DS1_185", "VAN_DS1_185"]}, {});
    t.play("AT_061", NONE);
    assert_eq!(t.hand(0).len(), 2, "not for itself");
    t.play("VAN_DS1_185", t.hero(1));
    let h = t.hand(0);
    assert_eq!(h.len(), 2);
    assert_eq!(rs.card(&h[1]).card_class, "HUNTER");
    t.end_turn().end_turn();
    let n = t.hand(0).len();
    t.play("VAN_DS1_185", t.hero(1));
    assert_eq!(t.hand(0).len(), n - 1, "this turn only");
}

#[test]
fn mana_cards() {
    let mut t = scene!({"hero": "HERO_06", "mana": 7, "max_mana": 7, "hand": ["AT_043", WISP, FIREBALL]}, {});
    t.play("AT_043", NONE);
    let p = &t.g.players[0];
    assert_eq!((p.mana, p.max_mana, p.hand.len()), (10, 10, 0));
    let mut t = scene!({"hero": "HERO_06", "hand": ["AT_043"]}, {});
    t.play("AT_043", NONE);
    assert_eq!(t.hand(0), vec!["CS2_013t"], "at 10: Excess Mana");
    let mut t = scene!({"hero": "HERO_06", "mana": 5, "max_mana": 5, "hand": ["AT_038", FIREBALL]}, {});
    t.play("AT_038", NONE);
    assert_eq!((t.g.players[0].mana, t.g.players[0].max_mana), (3, 6), "an empty crystal");
    let d = t.nth(0, 0);
    t.g.players[0].mana = 4;
    t.play(FIREBALL, d);
    assert_eq!((t.g.players[0].mana, t.g.players[0].max_mana), (0, 5), "Deathrattle: the empty one goes");
}

#[test]
fn cost_cards() {
    let mut t = scene!({"hero": "HERO_06", "hand": ["AT_045", OGRE, "VAN_CS2_231"]}, {});
    t.play("AT_045", NONE);
    assert_eq!((t.cost(OGRE), t.cost(WISP)), (1, 1), "Aviana: 0-Cost minions cost (1) too");
    let t = scene!({"hand": ["AT_070"], "board": ["VAN_CS2_146", "VAN_CS2_146"]}, {});
    assert_eq!(t.cost("AT_070"), 5, "Kragg: 7 - 2 Pirates");
    let mut t = scene!({"hero": "HERO_06", "hand": ["AT_041", "VAN_CS2_125", "VAN_EX1_165"]}, {});
    t.play("VAN_CS2_125", NONE);
    assert_eq!(t.cost("AT_041"), 6);
    t.choose_play("VAN_EX1_165", 0);
    assert_eq!(t.cost("AT_041"), 5, "Druid of the Claw becomes a Beast");
}

#[test]
fn more_cards() {
    // Acidmaw destroys any damaged minion; Wrathguard passes damage on
    let mut t = scene!({"hand": ["VAN_EX1_400"], "hero": "HERO_01", "board": ["AT_063", "AT_026"]}, {"board": [OGRE]});
    t.play("VAN_EX1_400", NONE);
    assert_eq!((t.cards(0), t.cards(1).len(), t.hp(0)), (vec!["AT_063".to_string()], 0, 29));
    // Confuse
    let mut t = scene!({"hero": "HERO_09", "hand": ["AT_016"]}, {"board": [YETI, {"card": "VAN_CS2_120", "damage": 0}]});
    t.play("AT_016", NONE);
    assert_eq!(t.stats(t.nth(1, 0)), (5, 4));
    // Enter the Coliseum and Eadric
    let mut t = scene!({"hero": "HERO_04", "hand": ["AT_078"], "board": [WISP, YETI]}, {"board": [OGRE, WISP, YETI]});
    t.play("AT_078", NONE);
    assert_eq!((t.cards(0), t.cards(1)), (vec![YETI.to_string()], vec![OGRE.to_string()]));
    let mut t = scene!({"hero": "HERO_04", "hand": ["AT_081"]}, {"board": [OGRE]});
    t.play("AT_081", NONE);
    assert_eq!(t.stats(t.nth(1, 0)), (1, 7));
    // Anub'arak and Dreadsteed come back
    let mut t = scene!({"hand": [FIREBALL, FIREBALL], "board": ["AT_036", "AT_019"]}, {});
    let (a, d) = (t.nth(0, 0), t.nth(0, 1));
    t.play(FIREBALL, a).play(FIREBALL, d);
    assert_eq!(t.cards(0), vec!["AT_036t", "AT_019"]);
    assert_eq!(t.hand(0), vec!["AT_036"]);
    // Arcane Blast: 2 + 2 x Spell Damage
    let mut t = scene!({"hand": ["AT_004"], "board": ["VAN_CS2_142"]}, {"board": [OGRE]});
    t.play("AT_004", t.nth(1, 0));
    assert_eq!(t.stats(t.nth(1, 0)), (6, 3));
    // Crowd Favorite before the Battlecry; Gormok needs 4 other minions
    let mut t = scene!({"hand": ["VAN_CS2_189"], "board": ["AT_121"]}, {});
    t.play("VAN_CS2_189", t.hero(1));
    assert_eq!(t.stats(t.nth(0, 0)), (5, 5));
    let t = scene!({"hand": ["AT_122"], "board": [WISP, WISP, WISP]}, {});
    assert!(!t.g.glows(t.hand_id("AT_122")) && !t.can_target("AT_122", t.hero(1)));
    let mut t = scene!({"hand": ["AT_122"], "board": [WISP, WISP, WISP, WISP]}, {});
    assert!(t.g.glows(t.hand_id("AT_122")));
    t.play("AT_122", t.hero(1));
    assert_eq!(t.hp(1), 26);
    // Chillmaw with a Dragon in the hand
    let mut t = scene!({"hand": [FIREBALL, AZURE_DRAKE], "board": ["AT_123", YETI]}, {"board": [YETI]});
    let c = t.nth(0, 0);
    t.play(FIREBALL, c);
    assert_eq!((t.stats(t.nth(0, 0)), t.stats(t.nth(1, 0))), ((4, 2), (4, 2)));
    // Argent Watchman attacks after the power only
    let mut t = scene!({"hero": "HERO_01", "board": ["AT_109"]}, {});
    let w = t.nth(0, 0);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack"));
    t.power(NONE);
    t.attack(w, t.hero(1));
    t.end_turn().end_turn();
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack"), "Can't attack again");
}

#[test]
fn dark_bargain_needs_two_enemy_minions() {
    let t = scene!({"hero": "HERO_07", "hand": ["AT_025"]}, {"board": [WISP]});
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play"));
    let mut t = scene!({"hero": "HERO_07", "hand": ["AT_025", WISP, FIREBALL, YETI]}, {"board": [WISP, YETI, OGRE]});
    t.play("AT_025", NONE);
    assert_eq!((t.cards(1).len(), t.hand(0).len()), (1, 1));
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/tgt/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30);
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
    assert!(decks.len() >= 8);
    let mut over = 0;
    let mut played = std::collections::BTreeSet::new();
    let (mut jousts, mut inspired, mut upgraded) = (0, 0, 0);
    for (i, (c0, d0)) in decks.iter().enumerate() {
        let (c1, d1) = &decks[(i + 3) % decks.len()];
        for seed in 0..3 {
            let mut g = Game::new_in(rs, c0, d0, c1, d1, seed + 10 * i as i64, -1, true);
            let mut steps = 0;
            while !g.game_over && g.turn < 80 {
                let p = if g.phase == "MULLIGAN" { (0..2).find(|&p| !g.players[p].mulliganed).unwrap() } else { g.current };
                let a = bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(a)).ok);
                assert_eq!(g.script_error.get(), None, "{c0} vs {c1}");
                steps += 1;
                assert!(steps < 4000);
            }
            over += g.game_over as usize;
            for h in &g.history {
                let power = h.action["type"] == "hero_power";
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    if e["type"] == "play" && card.starts_with("AT_") {
                        played.insert(card.to_string());
                    }
                    jousts += (e["type"] == "joust") as usize;
                    upgraded += (e["type"] == "hero_power" && g.e(int(e.get("entity"))).card_id.starts_with("AT_132_")) as usize;
                    inspired += (power && e.get("by").and_then(Value::as_str).is_some_and(|b| b.starts_with("AT_") && !b.starts_with("AT_132"))) as usize;
                }
            }
        }
    }
    assert!(over >= decks.len(), "most games end");
    eprintln!("TGT cards played: {}: {played:?}; jousts {jousts}, inspired events {inspired}, upgraded powers used {upgraded}", played.len());
    assert!(played.len() >= 10, "{played:?}");
    assert!(jousts > 0 && inspired > 0 && upgraded > 0);
}
