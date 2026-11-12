//! The Blackrock Mountain pack (packs/brm, built by tools/pack.py on Goblins vs Gnomes, Naxxramas and Classic): the
//! cards as on 2015-04-02 (build 8311), the new cards' scripts in small scenarios, the engine features they need
//! (lasting cost mods for a race: Dragon Consort; g.unlock_mana: Lava Shock), and whole bot games with every deck
//! template. Needs python3 (skipped without it).

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
        let out = std::env::temp_dir().join(format!("brm-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/brm", "-o"]).arg(&out).output().ok()?;
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

const WHIRLWIND: &str = "VAN_EX1_400";
const FROSTBOLT: &str = "VAN_CS2_024";
const AZURE_DRAKE: &str = "VAN_EX1_284";
const MALYGOS: &str = "VAN_EX1_563";

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    assert_eq!(c("BRM_008").cost, 5, "Dark Iron Skulker cost 5 until 2023");
    assert_eq!(c("BRM_016").health, 5, "Axe Flinger 2/5 until 2023");
    assert_eq!((c("BRM_028").cost, c("BRM_028").attack, c("BRM_028").health), (6, 5, 5), "Emperor Thaurissan 6 mana 5/5");
    assert_eq!(c("BRM_012").race, "", "Fireguard Destroyer: no tribe in 2015");
    assert_eq!(c("BRM_012").mana_lock, 1);
    assert_eq!((c("BRM_010a").kind.as_str(), c("BRM_010a").cost), ("SPELL", 0), "Druid of the Flame's options are spells");
    assert_eq!((c("BRM_027h").health, c("BRM_027h").power.as_str()), (8, "BRM_027p"));
    assert_eq!(rs.collectible.iter().filter(|id| id.starts_with("BRM_")).count(), 31);
    // the older cards keep their December 2014 numbers
    assert_eq!((c("VAN_EX1_116").cost, c("VAN_EX1_095").cost, c("GVG_006").health), (5, 6, 3));
    for d in ["VAN_EX1_284", "VAN_EX1_563", "VAN_EX1_572", "VAN_EX1_561", "VAN_EX1_043", "EX1_116t", "VAN_NEW1_023"] {
        assert_eq!(c(d).race, "DRAGON", "{d}");
    }
}

#[test]
fn undertaker_gains_only_attack() {
    let mut t = scene!({"hand": ["FP1_001"], "board": ["FP1_028"]}, {});
    t.play("FP1_001", NONE);
    assert_eq!(t.stats(t.on_board(0, "FP1_028")), (2, 2), "patch 2.1.0.7628: +1 Attack");
}

#[test]
fn grim_patron_multiplies() {
    let mut t = scene!({"hero": "HERO_01", "hand": [WHIRLWIND, WHIRLWIND], "board": ["BRM_019"]}, {});
    t.play(WHIRLWIND, NONE);
    assert_eq!(t.cards(0), vec!["BRM_019", "BRM_019"], "it survives: another one, right of it");
    t.play(WHIRLWIND, NONE);
    assert_eq!(t.cards(0).len(), 4, "both survive (3/1 and 3/2): two more");
    let mut t = scene!({"hero": "HERO_01", "hand": [WHIRLWIND], "board": [{"card": "BRM_019", "damage": 2}]}, {});
    t.play(WHIRLWIND, NONE);
    assert!(t.cards(0).is_empty(), "a Patron that dies calls none");
}

#[test]
fn hurt_triggers_imp_egg_axe() {
    let mut t = scene!({"hero": "HERO_01", "hand": [WHIRLWIND], "board": ["BRM_006", "BRM_022", "BRM_016"]}, {"board": [{"card": "VAN_EX1_032", "damage": 0}]});
    t.play(WHIRLWIND, NONE);
    assert_eq!(t.cards(0), vec!["BRM_006", "BRM_006t", "BRM_022", "BRM_022t", "BRM_016"]);
    assert_eq!(t.hp(1), 28, "Axe Flinger: 2 to the enemy hero");
    // a Divine Shield takes no damage: no Imp
    let mut t = scene!({"hero": "HERO_01", "hand": [WHIRLWIND], "board": [{"card": "BRM_006", "tags": ["DIVINE_SHIELD"]}]}, {});
    t.play(WHIRLWIND, NONE);
    assert_eq!(t.cards(0).len(), 1);
}

#[test]
fn costs_less_for_each_minion_that_died_this_turn() {
    let mut t = scene!({"hero": "HERO_01", "hand": [WHIRLWIND, "BRM_001", "BRM_025", "BRM_009", "BRM_003"], "board": [WISP]}, {"board": [WISP]});
    assert_eq!((t.cost("BRM_001"), t.cost("BRM_025"), t.cost("BRM_009"), t.cost("BRM_003")), (5, 6, 9, 5));
    t.play(WHIRLWIND, NONE);
    assert_eq!((t.cost("BRM_001"), t.cost("BRM_025"), t.cost("BRM_009"), t.cost("BRM_003")), (3, 4, 7, 3));
    t.end_turn();
    t.end_turn();
    assert_eq!(t.cost("BRM_001"), 5, "a new turn: no deaths yet");
}

#[test]
fn dragon_consort_lasts_until_a_dragon_is_played() {
    let mut t = scene!({"hand": ["BRM_018", AZURE_DRAKE, "BRM_020", YETI]}, {});
    t.play("BRM_018", NONE);
    assert_eq!((t.cost(AZURE_DRAKE), t.cost("BRM_020"), t.cost(YETI)), (3, 2, 4));
    t.end_turn().end_turn();
    assert_eq!(t.cost(AZURE_DRAKE), 3, "still next turn");
    t.play(AZURE_DRAKE, NONE);
    assert_eq!(t.cost("BRM_020"), 4, "used by the first Dragon");
}

#[test]
fn lava_shock_unlocks_overload() {
    let mut t = scene!({"hero": "HERO_02", "mana": 8, "overload_locked": 2, "overload_owed": 3, "hand": ["BRM_011"]}, {});
    t.play("BRM_011", t.hero(1));
    assert_eq!(t.hp(1), 28);
    let p = &t.g.players[0];
    assert_eq!((p.mana, p.mana_locked, p.mana_lock_owed), (8, 0, 0), "8 - 2 + the 2 locked; nothing owed");
}

#[test]
fn fireguard_destroyer_overloads() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["BRM_012"]}, {});
    t.play("BRM_012", NONE);
    let (a, h) = t.stats(t.on_board(0, "BRM_012"));
    assert!((4..=7).contains(&a) && h == 6, "{a}/{h}");
    assert_eq!(t.g.players[0].mana_lock_owed, 1);
}

#[test]
fn holding_a_dragon() {
    let mut t = scene!({"hand": ["BRM_004", "BRM_033", AZURE_DRAKE]}, {});
    assert!(t.g.glows(t.hand_id("BRM_004")) && t.g.glows(t.hand_id("BRM_033")));
    t.play("BRM_004", NONE).play("BRM_033", NONE);
    assert_eq!(t.stats(t.on_board(0, "BRM_004")), (2, 3));
    assert_eq!(t.stats(t.on_board(0, "BRM_033")), (3, 5));
    let t = scene!({"hand": ["BRM_034", YETI]}, {"board": [YETI]});
    assert!(!t.can_target("BRM_034", t.nth(1, 0)), "Blackwing Corruptor: no target without a Dragon");
    let mut t = scene!({"hand": ["BRM_004"]}, {});
    assert!(!t.g.glows(t.hand_id("BRM_004")), "a Twilight Whelp is no Dragon in the hand for itself");
    t.play("BRM_004", NONE);
    assert_eq!(t.stats(t.on_board(0, "BRM_004")), (2, 1));
    let mut t = scene!({"hand": ["BRM_034", AZURE_DRAKE]}, {"board": [YETI]});
    let y = t.nth(1, 0);
    t.play("BRM_034", y);
    assert_eq!(t.stats(y), (4, 2));
}

#[test]
fn rend_blackhand_destroys_a_legendary() {
    let mut t = scene!({"hand": ["BRM_029", AZURE_DRAKE]}, {"board": [MALYGOS, YETI]});
    let (m, y) = (t.nth(1, 0), t.nth(1, 1));
    assert!(t.g.glows(t.hand_id("BRM_029")));
    assert!(!t.can_target("BRM_029", y));
    t.play("BRM_029", m);
    assert_eq!(t.cards(1), vec![YETI]);
    let t = scene!({"hand": ["BRM_029"]}, {"board": [MALYGOS]});
    assert!(!t.can_target("BRM_029", t.nth(1, 0)), "no Dragon in the hand: no target");
}

#[test]
fn majordomo_turns_you_into_ragnaros() {
    let mut t = scene!({"hand": [FIREBALL, FIREBALL], "armor": 5, "weapon": "VAN_CS2_106", "board": [{"card": "BRM_027", "damage": 1}]}, {"board": [YETI]});
    let d = t.nth(0, 0);
    t.play(FIREBALL, d);
    let h = t.hero(0);
    assert_eq!(t.g.e(h).card_id, "BRM_027h");
    assert_eq!((t.hp(0), t.g.e(h).tag(t.g.n().armor)), (8, 0), "8 Health, the Armor is gone");
    assert!(t.g.players[0].weapon.is_some(), "the weapon stays");
    assert_eq!(t.g.e(t.g.players[0].hero_power).card_id, "BRM_027p");
    t.power(NONE);
    let hit = t.hp(1) == 22 || t.cards(1).is_empty();
    assert!(hit, "DIE, INSECT!: 8 damage to a random enemy");
}

#[test]
fn emperor_thaurissan_discounts_the_hand() {
    let mut t = scene!({"hand": [FIREBALL, YETI], "board": ["BRM_028"]}, {});
    t.end_turn();
    t.end_turn();
    assert_eq!((t.cost(FIREBALL), t.cost(YETI)), (3, 3), "4 - 1 each; the drawn Wisp came after");
}

#[test]
fn chromaggus_copies_draws() {
    let mut t = scene!({"board": ["BRM_031"], "deck": [WISP, FIREBALL]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.hand(0), vec![FIREBALL, FIREBALL]);
}

#[test]
fn nefarian_takes_the_opponents_class_spells() {
    let Some(rs) = rs() else { return };
    let mut t = scene!({"hand": ["BRM_030"]}, {"hero": "HERO_08"});
    t.play("BRM_030", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 2);
    for c in &h {
        assert_eq!((rs.card(c).kind.as_str(), rs.card(c).card_class.as_str()), ("SPELL", "MAGE"), "{c}");
    }
    let mut t = scene!({"hand": ["BRM_030"]}, {});
    t.g.replace_hero(1, "BRM_027h");
    t.play("BRM_030", NONE);
    assert_eq!(t.hand(0), vec!["BRM_030t", "BRM_030t"], "Ragnaros has no class: Tail Swipes");
}

#[test]
fn resurrect_gang_up_and_skulker() {
    let mut t = scene!({"hero": "HERO_09", "hand": [FIREBALL, "BRM_017"], "board": [YETI]}, {});
    let y = t.nth(0, 0);
    t.play(FIREBALL, y).play("BRM_017", NONE);
    assert_eq!(t.cards(0), vec![YETI], "the Yeti is back");
    let mut t = scene!({"hero": "HERO_03", "hand": ["BRM_007"]}, {"board": [YETI]});
    let y = t.nth(1, 0);
    t.play("BRM_007", y);
    assert_eq!(t.deck(0).iter().filter(|c| *c == YETI).count(), 3);
    let mut t = scene!({"hero": "HERO_03", "hand": ["BRM_008"]}, {"board": [YETI, {"card": YETI, "damage": 1}]});
    t.play("BRM_008", NONE);
    let (a, b) = (t.nth(1, 0), t.nth(1, 1));
    assert_eq!((t.stats(a), t.stats(b)), ((4, 3), (4, 4)), "only the undamaged one");
}

#[test]
fn dragonkin_and_flamewaker() {
    let mut t = scene!({"hand": [FROSTBOLT], "board": ["BRM_020"]}, {});
    let d = t.nth(0, 0);
    t.play(FROSTBOLT, d);
    assert_eq!(t.stats(d), (4, 3), "+1/+1 before the 3 damage");
    let mut t = scene!({"hand": [FROSTBOLT], "board": ["BRM_002"]}, {});
    t.play(FROSTBOLT, t.hero(1));
    assert_eq!(t.hp(1), 25, "3 + the 2 missiles (no minions to hit)");
}

#[test]
fn hunter_and_warrior_conditions() {
    let mut t = scene!({"hero": "HERO_05", "hand": ["BRM_013"]}, {});
    assert!(t.g.glows(t.hand_id("BRM_013")));
    t.play("BRM_013", t.hero(1));
    assert_eq!((t.hp(1), t.hand(0).len()), (27, 1), "hand empty: a card");
    let mut t = scene!({"hero": "HERO_05", "hand": ["BRM_014"]}, {});
    t.play("BRM_014", NONE);
    assert_eq!(t.stats(t.on_board(0, "BRM_014")), (7, 7));
    let mut t = scene!({"hero": "HERO_01", "hand": ["BRM_015"], "damage": 18}, {"board": [YETI]});
    assert!(t.g.glows(t.hand_id("BRM_015")));
    t.play("BRM_015", NONE);
    assert_eq!(t.stats(t.nth(1, 0)), (4, 2));
    let mut t = scene!({"hand": ["BRM_024"]}, {"damage": 15});
    t.play("BRM_024", NONE);
    assert_eq!(t.stats(t.on_board(0, "BRM_024")), (9, 9));
}

#[test]
fn warlock_and_druid_and_hungry_dragon() {
    let Some(rs) = rs() else { return };
    let mut t = scene!({"hero": "HERO_07", "hand": ["BRM_005"], "board": ["BRM_006t", YETI]}, {"board": [YETI]});
    t.play("BRM_005", NONE);
    assert_eq!(t.cards(0), vec!["BRM_006t", YETI], "the Imp is a Demon");
    assert_eq!(t.stats(t.nth(1, 0)), (4, 3));
    let mut t = scene!({"hero": "HERO_06", "hand": ["BRM_010"]}, {});
    t.choose_play("BRM_010", 1);
    assert_eq!(t.cards(0), vec!["BRM_010t2"]);
    let mut t = scene!({"hand": ["BRM_026"]}, {});
    t.play("BRM_026", NONE);
    let c = t.cards(1);
    assert_eq!(c.len(), 1);
    assert_eq!(rs.card(&c[0]).cost, 1);
    let mut t = scene!({"hero": "HERO_07", "hand": ["VAN_EX1_320"]}, {"board": [WISP]});
    let w = t.nth(1, 0);
    t.play("VAN_EX1_320", w);
    assert_eq!(rs.card(&t.cards(0)[0]).race, "DEMON");
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/brm/decks")).unwrap().map(|f| f.unwrap().path()).collect();
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
    for (i, (c0, d0)) in decks.iter().enumerate() {
        let (c1, d1) = &decks[(i + 3) % decks.len()];
        for seed in 0..2 {
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
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    if e["type"] == "play" && card.starts_with("BRM_") {
                        played.insert(card.to_string());
                    }
                }
            }
        }
    }
    assert!(over >= decks.len(), "most games end");
    let brm = played.iter().filter(|c| c.starts_with("BRM_")).count();
    eprintln!("BRM cards played: {brm}: {played:?}");
    assert!(brm >= 15, "{played:?}");
}
