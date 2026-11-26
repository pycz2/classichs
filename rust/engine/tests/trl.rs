//! The Rastakhan's Rumble pack (packs/trl, built by tools/pack.py on The Boomsday Project and the packs before it): the
//! cards as on 2018-12-04 (build 27845) and what they need: Overkill (on a minion and on a hero: Health + Armor, only on
//! its controller's turn), the Loa and their Spirits ("Stealth for 1 turn"), Zul'jin, Hakkar's Corrupted Blood, Krag'wa,
//! Shirvallah, Jan'alai, Spirit of the Dragonhawk (the engine's POWER_ADJACENT), the older cards of patch 12.2 and whole
//! bot games with every deck template. Needs python3
//! (skipped without it).

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
        let out = std::env::temp_dir().join(format!("trl-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/trl", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(ruleset::load(&files).expect("the built pack loads"))
    })
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const FIREBALL: &str = "VAN_CS2_029";
const FROSTBOLT: &str = "VAN_CS2_024";
const MOONFIRE: &str = "VAN_CS2_008";
const RAPTOR: &str = "VAN_CS2_172"; // Bloodfen Raptor, a 3/2 Beast
const GOLEM: &str = "VAN_CS2_186"; // War Golem, 7/7
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];
const NONE: Id = -1;

const DIREHORN: &str = "TRL_232";
const RUNT: &str = "TRL_232t";
const ARROW: &str = "TRL_347";
const DEVILSAUR: &str = "TRL_347t";
const BLOOD: &str = "TRL_541t";

struct T {
    g: Game,
}

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
    Some(T { g: scenario::build_in(rs, &sc).unwrap_or_else(|e| panic!("scenario: {e}")) })
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

#[allow(dead_code)]
impl T {
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
    fn power(&self, p: usize) -> String {
        self.g.e(self.g.players[p].hero_power).card_id.to_string()
    }
    fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
    }
    fn armor(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).tag("ARMOR")
    }
    fn hp(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).health()
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
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target
                && (int(a.get("pos")) == -1 || int(a.get("pos")) == last) && int(a.get("choice")) == -1
        })
    }
    fn power_on(&mut self, target: Id) -> &mut Self {
        self.act("hero power", |a| a["type"] == "hero_power" && int(a.get("target")) == target)
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
    fn events(&self) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).collect()
    }
    fn has(&self, p: usize, card: &str) -> bool {
        self.cards(p).iter().any(|c| c == card)
    }
}

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    assert_eq!(rs.cards.values().filter(|x| x.collectible && x.set == "TROLL").count(), 135);
    // the older cards of patch 12.2 (2018-10-18) as this pack has them
    assert_eq!(c("VAN_NEW1_012").cost, 2, "Mana Wyrm 2");
    assert_eq!(c("BOT_270").cost, 7, "Giggling Inventor 7");
    assert_eq!(c("AT_045").cost, 10, "Aviana 10");
    // the 4 Classic cards of 2018-11-05
    for id in ["EX1_179", "EX1_180", "EX1_181", "EX1_182"] {
        assert!(c(id).collectible, "{id}");
        assert_eq!(c(id).set, "VANILLA", "{id}");
    }
    assert_eq!(c("TRL_300").cost, 25, "Shirvallah");
    assert_eq!(c("TRL_065").armor, 5, "Zul'jin");
}

#[test]
fn every_card_plays_without_a_script_error() {
    let Some(rs) = rs() else { return };
    let mut ids: Vec<&String> = rs.cards.keys().filter(|k| k.starts_with("TRL_") || k.starts_with("EX1_18") || *k == "EX1_179").collect();
    ids.sort();
    let mut n = 0;
    for id in ids {
        let c = rs.card(id);
        if !matches!(c.kind.as_str(), "MINION" | "SPELL" | "WEAPON" | "CHAMPION") {
            continue;
        }
        let deck = json!([RAPTOR, YETI, FIREBALL, "TRL_507t", MOONFIRE, "VAN_EX1_012", "TRL_309", WISP]);
        let Some(t) = game(json!({"hand": [id, YETI, FIREBALL, RAPTOR], "board": [RAPTOR, "VAN_CS2_146", WISP], "deck": deck,
            "weapon": "VAN_CS2_106"}), json!({"board": [YETI, "VAN_CS2_125"], "hand": [WISP, FROSTBOLT], "deck": deck})) else { return };
        let e = *t.g.players[0].hand.iter().find(|&&x| t.g.e(x).card_id == id).unwrap();
        let plays: Vec<_> = t.g.legal_actions().into_iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).collect();
        for a in plays.into_iter().take(6) {
            let mut g = t.g.clone_state();
            assert!(g.apply(&Value::Object(a.clone())).ok, "{id}");
            for _ in 0..6 {
                if g.game_over {
                    break;
                }
                let p = g.pending.as_ref().map_or(g.current, |c| c.player);
                let b = bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(b)).ok);
            }
            assert_eq!(g.script_error.get(), None, "{id} {a:?}");
            n += 1;
        }
    }
    assert!(n > 140, "{n}");
}

// --- Overkill ---------------------------------------------------------------------------------------------------------

#[test]
fn overkill_on_a_minion_by_an_attack_on_your_turn_only() {
    // Ironhide Direhorn (7/7) into a Yeti (5 Health): a 5/5 Runt
    let mut t = scene!({"board": [DIREHORN]}, {"board": [YETI]});
    let (d, y) = (t.on_board(0, DIREHORN), t.on_board(1, YETI));
    t.attack(d, y);
    assert_eq!(t.cards(0), vec![DIREHORN, RUNT]);
    assert_eq!(t.stats(t.on_board(0, RUNT)), (5, 5));
    // exactly the Health (War Golem 7/7): no Overkill
    let mut t = scene!({"board": [DIREHORN]}, {"board": [GOLEM]});
    let (d, w) = (t.on_board(0, DIREHORN), t.on_board(1, GOLEM));
    t.attack(d, w);
    assert!(!t.has(0, RUNT), "{:?}", t.cards(0));
    // attacked on the opponent's turn: its 7 damage to a Yeti is no Overkill
    let mut t = scene!({"board": [DIREHORN]}, {"board": [YETI]});
    t.end_turn();
    let (d, y) = (t.on_board(0, DIREHORN), t.on_board(1, YETI));
    t.attack(y, d);
    assert!(t.cards(1).is_empty(), "the Yeti died");
    assert_eq!(t.cards(0), vec![DIREHORN], "no Runt");
}

#[test]
fn overkill_by_a_spell_on_a_minion() {
    // Baited Arrow: 3 damage; a Wisp (1 Health): a 5/5 Devilsaur
    let mut t = scene!({"hand": [ARROW]}, {"board": [WISP]});
    let w = t.on_board(1, WISP);
    t.play(ARROW, w);
    assert_eq!(t.cards(0), vec![DEVILSAUR]);
    // 3 damage to a 3 Health minion: none
    let mut t = scene!({"hand": [ARROW]}, {"board": [{"card": YETI, "damage": 2}]});
    let y = t.on_board(1, YETI);
    t.play(ARROW, y);
    assert!(t.cards(0).is_empty());
    assert!(t.cards(1).is_empty(), "the Yeti died");
    // Spell Damage +1 (Kobold Geomancer) makes it 4: Overkill on the 3 Health Yeti
    let mut t = scene!({"hand": [ARROW], "board": ["VAN_CS2_142"]}, {"board": [{"card": YETI, "damage": 2}]});
    let y = t.on_board(1, YETI);
    t.play(ARROW, y);
    assert!(t.has(0, DEVILSAUR), "{:?}", t.cards(0));
}

#[test]
fn overkill_on_a_hero_counts_health_and_armor() {
    // Baited Arrow (3) on a hero with 1 Health and 1 Armor: 1 excess
    let mut t = scene!({"hand": [ARROW]}, {"damage": 29, "armor": 1});
    let foe = t.hero(1);
    t.play(ARROW, foe);
    assert!(t.has(0, DEVILSAUR), "{:?}", t.cards(0));
    // 1 Health and 2 Armor: exactly enough, no Overkill
    let mut t = scene!({"hand": [ARROW]}, {"damage": 29, "armor": 2});
    let foe = t.hero(1);
    t.play(ARROW, foe);
    assert_eq!(t.hp(1), 0);
    assert!(!t.has(0, DEVILSAUR), "{:?}", t.cards(0));
    // an attack: Ironhide Direhorn (7) on a hero with 5 Health and 1 Armor; 6 Health and 1 Armor: none
    let mut t = scene!({"board": [DIREHORN]}, {"damage": 25, "armor": 1});
    let (d, foe) = (t.on_board(0, DIREHORN), t.hero(1));
    t.attack(d, foe);
    assert!(t.has(0, RUNT), "{:?}", t.cards(0));
    let mut t = scene!({"board": [DIREHORN]}, {"damage": 24, "armor": 1});
    let (d, foe) = (t.on_board(0, DIREHORN), t.hero(1));
    t.attack(d, foe);
    assert!(!t.has(0, RUNT), "{:?}", t.cards(0));
    // a neutral one (trl_n): Half-Time Scavenger (3 Attack, Overkill: 3 Armor) on 1 Health and 1 Armor
    let mut t = scene!({"board": ["TRL_010"]}, {"damage": 29, "armor": 1});
    let (s, foe) = (t.on_board(0, "TRL_010"), t.hero(1));
    t.attack(s, foe);
    assert_eq!(t.armor(0), 3);
}

// --- the Loa and their Spirits ----------------------------------------------------------------------------------------

#[test]
fn a_spirit_has_stealth_until_the_start_of_your_next_turn() {
    // Spirit of the Lynx (trl_a) and Spirit of the Frog (trl_b)
    let mut t = scene!({"hand": ["TRL_901", "TRL_060", RAPTOR]}, {});
    t.play("TRL_901", NONE).play("TRL_060", NONE);
    let (lynx, frog) = (t.on_board(0, "TRL_901"), t.on_board(0, "TRL_060"));
    for s in [lynx, frog] {
        assert!(t.g.e(s).has("STEALTH"));
    }
    // Spirit of the Lynx: a Beast summoned gets +1/+1
    t.play(RAPTOR, NONE);
    assert_eq!(t.stats(t.on_board(0, RAPTOR)), (4, 3));
    t.end_turn();
    for s in [lynx, frog] {
        assert!(t.g.e(s).has("STEALTH"), "still on the opponent's turn");
    }
    t.end_turn();
    for s in [lynx, frog] {
        assert!(!t.g.e(s).has("STEALTH"), "gone at the start of your turn");
    }
    // summoned, not played (Resurrect): the same
    let mut t = scene!({"board": ["TRL_901", "TRL_060"], "hand": ["VAN_CS2_062", "BRM_017", "BRM_017"]}, {});
    t.play("VAN_CS2_062", NONE); // Hellfire: 3 damage to all
    t.play("BRM_017", NONE).play("BRM_017", NONE);
    assert_eq!(t.cards(0).len(), 2);
    let back = t.g.players[0].board.clone();
    for &s in &back {
        assert!(t.g.e(s).has("STEALTH"), "{}", card_of(&t, s));
    }
    t.end_turn().end_turn();
    for &s in &back {
        assert!(!t.g.e(s).has("STEALTH"), "{}", card_of(&t, s));
    }
}

// Spirit of the Dragonhawk: POWER_ADJACENT (the engine's do_hero_power): the minions next to a minion target, taken
// before the effect, are hit too; a hero target hits nothing more.
// Spirit of the Shark: DOUBLE_COMBO (a minion's Combo twice) besides DOUBLE_BATTLECRY.
#[test]
fn spirit_of_the_shark_doubles_a_minions_combo() {
    let mut t = scene!({"board": ["TRL_092"], "hand": [WISP, "VAN_EX1_134"]}, {});
    let (foe, hp) = (t.hero(1), t.hp(1));
    t.play(WISP, NONE).play("VAN_EX1_134", foe);
    assert_eq!(t.hp(1), hp - 4, "SI:7 Agent's Combo (2 damage) twice");
}

// Likkim: Overloaded crystals = locked this turn or owed for the next (g.owed), an Overload played before it too.
#[test]
fn likkim_sees_overload_played_before_it() {
    let mut t = scene!({"hand": ["VAN_EX1_238", "TRL_352"]}, {});
    let foe = t.hero(1);
    t.play("VAN_EX1_238", foe).play("TRL_352", NONE);
    let w = t.g.players[0].weapon.expect("Likkim");
    assert_eq!(t.g.e(w).atk(), 3, "1 + 2 while Lightning Bolt's Overload is owed");
    t.end_turn().end_turn();
    assert_eq!(t.g.e(w).atk(), 3, "the crystal is locked this turn");
    t.end_turn().end_turn();
    assert_eq!(t.g.e(w).atk(), 1);
}

// Spirit of the Rhino: a Rush minion summoned before the Spirit this turn is Immune too (SUMMONED_TURN).
#[test]
fn spirit_of_the_rhino_covers_rush_minions_summoned_before_it() {
    let mut t = scene!({"hand": ["TRL_550", "TRL_327"]}, {});
    t.play("TRL_550", NONE).play("TRL_327", NONE);
    let bear = t.on_board(0, "TRL_550");
    assert!(t.g.e(bear).has("IMMUNE"), "the turn it was summoned");
    t.end_turn();
    assert!(!t.g.e(bear).has("IMMUNE"), "not after that turn");
}

// Wardruid Loti: Choose One of four (choices 0, 1, 3, 4: 2 is both), each form at once; with Fandral the combined one.
#[test]
fn wardruid_loti_chooses_one_of_four_forms() {
    let mut t = scene!({"hero": "HERO_06", "hand": ["TRL_343"]}, {});
    let e = t.hand_id("TRL_343");
    let mut choices: Vec<i64> = t.g.legal_actions().iter()
        .filter(|a| a["type"] == "play" && int(a.get("entity")) == e).map(|a| int(a.get("choice"))).collect();
    choices.sort();
    choices.dedup();
    assert_eq!(choices, vec![0, 1, 3, 4]);
    t.act("Loti, the third form", |a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("choice")) == 3);
    assert_eq!(t.cards(0), vec!["TRL_343ct2"]);
    let mut t = scene!({"hero": "HERO_06", "board": ["OG_044"], "hand": ["TRL_343"]}, {});
    let e = t.hand_id("TRL_343");
    t.act("Loti with Fandral", |a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("choice")) == 2);
    assert!(t.cards(0).contains(&"TRL_343et1".to_string()));
}

#[test]
fn spirit_of_the_dragonhawk_powers_hit_the_targets_neighbours() {
    let mut t = scene!({"board": ["TRL_319"]}, {"board": [WISP, YETI, WISP, WISP]});
    let y = t.on_board(1, YETI);
    t.power_on(y);
    assert_eq!(t.cards(1), vec![YETI, WISP], "Fireblast on the Yeti kills the Wisps next to it, not the far one");
    let y = t.on_board(1, YETI);
    assert_eq!(t.stats(y), (4, 4));
    t.end_turn().end_turn();
    let foe = t.hero(1);
    let (hp, armor) = (t.hp(1), t.armor(1));
    t.power_on(foe);
    assert_eq!((t.hp(1) + t.armor(1), t.cards(1).len()), (hp + armor - 1, 2), "a hero target: no neighbours");
    // without the Spirit, Fireblast hits only its target
    let mut t = scene!({}, {"board": [WISP, YETI, WISP]});
    let y = t.on_board(1, YETI);
    t.power_on(y);
    assert_eq!(t.cards(1), vec![WISP, YETI, WISP]);
}

#[test]
fn halazzi_fills_the_hand_with_lynxes() {
    let mut t = scene!({"hand": ["TRL_900", WISP]}, {});
    t.play("TRL_900", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 10);
    assert_eq!(h.iter().filter(|c| *c == "TRL_348t").count(), 9);
}

#[test]
fn krag_wa_returns_the_spells_you_played_last_turn() {
    let mut t = scene!({"hand": [FIREBALL, FROSTBOLT, MOONFIRE, "TRL_345"]}, {});
    let foe = t.hero(1);
    t.play(FIREBALL, foe).play(FROSTBOLT, foe);
    t.end_turn().end_turn();
    t.play(MOONFIRE, foe); // this turn: not returned
    t.play("TRL_345", NONE);
    let h = t.hand(0);
    assert!(h.contains(&FIREBALL.to_string()) && h.contains(&FROSTBOLT.to_string()), "{h:?}");
    assert!(!h.contains(&MOONFIRE.to_string()), "{h:?}");
    // the turn after: the spells of two turns ago are not "last turn"
    let mut t = scene!({"hand": [FIREBALL, "TRL_345"]}, {});
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    t.end_turn().end_turn().end_turn().end_turn();
    t.play("TRL_345", NONE);
    assert!(!t.hand(0).contains(&FIREBALL.to_string()));
}

#[test]
fn shirvallah_costs_one_less_per_mana_spent_on_spells() {
    let mut t = scene!({"hand": ["TRL_300", FIREBALL, FROSTBOLT, MOONFIRE]}, {});
    assert_eq!(t.cost("TRL_300"), 25);
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    assert_eq!(t.cost("TRL_300"), 21);
    t.play(FROSTBOLT, foe);
    assert_eq!(t.cost("TRL_300"), 19);
    // the mana spent, not the printed Cost: Sorcerer's Apprentice makes Moonfire (0)
    let mut t = scene!({"hand": ["TRL_300", FIREBALL, MOONFIRE], "board": ["VAN_EX1_608"]}, {});
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    assert_eq!(t.cost("TRL_300"), 22);
    t.play(MOONFIRE, foe);
    assert_eq!(t.cost("TRL_300"), 22);
}

#[test]
fn janalai_summons_ragnaros_after_eight_hero_power_damage() {
    // Berserker Throw (2 damage) four times: 8
    let mut t = scene!({"hero_power": "TRL_065h", "hand": ["TRL_316", "TRL_316"]}, {});
    let foe = t.hero(1);
    for _ in 0..3 {
        t.power_on(foe).end_turn().end_turn();
    }
    t.play("TRL_316", NONE);
    assert_eq!(t.cards(0), vec!["TRL_316"], "6: not yet");
    t.end_turn().end_turn();
    t.power_on(foe);
    t.play("TRL_316", NONE);
    assert_eq!(t.cards(0), vec!["TRL_316", "TRL_316", "TRL_316t"]);
    let r = t.on_board(0, "TRL_316t");
    assert_eq!(t.stats(r), (8, 8));
    let before = t.hp(1);
    t.end_turn();
    assert_eq!(t.hp(1), before - 8, "8 damage at the end of the turn (no enemy minion)");
}

// --- Zul'jin and Hakkar -----------------------------------------------------------------------------------------------

#[test]
fn zuljin_casts_the_spells_you_played_with_random_targets() {
    // Fireball (any target), Icicle (a minion: none left, skipped), Arcane Intellect (draw 2)
    let mut t = scene!({"hand": [FIREBALL, "EX1_179", "VAN_CS2_023", "TRL_065"], "deck": [WISP, WISP, WISP, WISP, WISP, WISP, WISP, WISP]},
        {"board": [WISP]});
    let foe = t.hero(1);
    let w = t.on_board(1, WISP);
    t.play(FIREBALL, foe).play("EX1_179", w).play("VAN_CS2_023", NONE);
    t.end_turn().end_turn();
    let hand = t.g.players[0].hand.len();
    let total = |t: &T| t.hp(0) + t.armor(0) + t.hp(1) + t.armor(1);
    let before = total(&t);
    t.play("TRL_065", NONE);
    assert_eq!(card_of(&t, t.hero(0)), "TRL_065");
    assert_eq!(t.power(0), "TRL_065h");
    assert_eq!(t.g.players[0].hand.len(), hand - 1 + 2, "Arcane Intellect again");
    assert_eq!(total(&t), before + 5 - 6, "5 Armor, then Fireball's 6 on one of the heroes");
    assert!(t.cards(0).is_empty() && t.cards(1).is_empty());
}

#[test]
fn hakkar_shuffles_corrupted_blood_into_both_decks() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["TRL_541"]}, {"deck": []});
    let h = t.on_board(0, "TRL_541");
    t.g.em(h).damage = 1;
    t.play(FIREBALL, h);
    assert_eq!(t.deck(0).iter().filter(|c| *c == BLOOD).count(), 1);
    assert_eq!(t.deck(1), vec![BLOOD]);
    t.end_turn();
    // drawn: 3 damage, then a draw (an empty deck: fatigue 1), then two copies
    assert_eq!(t.hp(1), 30 - 3 - 1);
    assert!(!t.hand(1).contains(&BLOOD.to_string()));
    assert_eq!(t.deck(1), vec![BLOOD, BLOOD]);
    assert!(t.events().iter().any(|e| e["type"] == "cast_when_drawn" && e["card"] == BLOOD));
}

#[test]
fn corrupted_blood_draws_on_and_chains() {
    // the Blood on top: 3 damage, the Yeti under it is drawn, two Bloods go in
    let mut t = scene!({}, {"deck": [YETI, BLOOD]});
    t.end_turn();
    assert_eq!(t.hp(1), 27);
    assert_eq!(t.hand(1), vec![YETI]);
    assert_eq!(t.deck(1), vec![BLOOD, BLOOD]);
    // two Bloods in a row: 6 damage, fatigue 1, four copies
    let mut t = scene!({}, {"deck": [BLOOD, BLOOD]});
    t.end_turn();
    assert_eq!(t.hp(1), 30 - 6 - 1);
    assert_eq!(t.deck(1), vec![BLOOD; 4]);
    assert!(t.hand(1).is_empty());
}

fn card_of(t: &T, e: Id) -> String {
    t.g.e(e).card_id.to_string()
}

// --- bot games ----------------------------------------------------------------------------------------------------------

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/trl/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(&f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30, "{f:?}");
        let deck = classichs_engine::deck::Deck { hero: d["champion"].as_str().unwrap().into(), cards: cards.clone(), arena: false };
        assert_eq!(deck.validate_in(rs), "", "{f:?}");
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
    assert_eq!(decks.len(), 16);
    let mut over = 0;
    let mut errors = vec![];
    let mut played = std::collections::BTreeSet::new();
    for (i, (c0, d0)) in decks.iter().enumerate() {
        let (c1, d1) = &decks[(i + 7) % decks.len()];
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
                steps += 1;
                assert!(steps < 4000);
            }
            if let Some(err) = g.script_error.get() {
                errors.push(format!("deck {i} ({c0}) vs {} ({c1}), seed {seed}: {err}", (i + 7) % decks.len()));
            }
            over += g.game_over as usize;
            for h in &g.history {
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    if e["type"] == "play" && card.starts_with("TRL_") {
                        played.insert(card.to_string());
                    }
                }
            }
        }
    }
    eprintln!("Rastakhan's Rumble cards played: {}: {played:?}", played.len());
    assert!(errors.is_empty(), "script errors:\n{}", errors.join("\n"));
    assert!(over >= decks.len() * 2, "most games end");
    assert!(played.len() >= 15, "the decks play the set");
}

// --- the card tests (data/card_tests/trl.json, as game/card_tests.gd plays them) ------------------------------------------

fn ref_id(g: &Game, r: Option<&Value>) -> Id {
    let Some(r) = r.and_then(Value::as_object) else { return NONE };
    let p = &g.players[int(r.get("side")) as usize];
    let i = int(r.get("index")) as usize;
    match r.get("zone").and_then(Value::as_str).unwrap_or("") {
        "hand" => p.hand.get(i).copied().unwrap_or(NONE),
        "board" => p.board.get(i).copied().unwrap_or(NONE),
        "secret" => p.secrets.get(i).copied().unwrap_or(NONE),
        "hero" => p.hero,
        "weapon" => p.weapon.unwrap_or(NONE),
        "power" => p.hero_power,
        _ => NONE,
    }
}

#[test]
fn card_tests_play() {
    let Some(rs) = rs() else { return };
    let tests: Map<String, Value> =
        serde_json::from_str(&std::fs::read_to_string(repo().join("data/card_tests/trl.json")).unwrap()).unwrap();
    let mut bad = vec![];
    for (id, list) in &tests {
        for t in list.as_array().unwrap() {
            if let Some(s) = t.get("script").and_then(Value::as_str) {
                if rs.card(id).script != s {
                    bad.push(format!("{id}: script {s} is not the pack's {}", rs.card(id).script));
                    continue;
                }
            }
            let title = t["title"].as_str().unwrap();
            let mut g = match scenario::build_in(rs, &t["scene"]) {
                Ok(g) => g,
                Err(e) => {
                    bad.push(format!("{title}: scene: {e}"));
                    continue;
                }
            };
            for (i, s) in t["steps"].as_array().unwrap().iter().enumerate() {
                let want: Vec<(&str, Value)> = match s["do"].as_str().unwrap() {
                    "play" => {
                        let mut w = vec![("type", json!("play")), ("entity", json!(ref_id(&g, s.get("card")))),
                            ("target", json!(ref_id(&g, s.get("target")))), ("choice", json!(s.get("choice").map_or(-1, |c| int(Some(c)))))];
                        if let Some(p) = s.get("pos") {
                            w.push(("pos", p.clone()));
                        }
                        w
                    }
                    "attack" => vec![("type", json!("attack")), ("attacker", json!(ref_id(&g, s.get("attacker")))),
                        ("defender", json!(ref_id(&g, s.get("defender"))))],
                    "hero_power" => vec![("type", json!("hero_power")), ("target", json!(ref_id(&g, s.get("target"))))],
                    "end_turn" => vec![("type", json!("end_turn"))],
                    "choose" => {
                        let opts = g.pending_options();
                        let n = int(s.get("option"));
                        let o = if opts.contains(&n) { n } else { opts.get(n as usize).copied().unwrap_or(NONE) };
                        vec![("type", json!("choose")), ("option", json!(o))]
                    }
                    x => panic!("{x}"),
                };
                let a = g.legal_actions().into_iter().find(|a| {
                    want.iter().all(|(k, v)| {
                        if *k == "pos" && int(a.get("pos")) < 0 {
                            return true;
                        }
                        a.get(*k).cloned().unwrap_or(if ["target", "choice"].contains(k) { json!(-1) } else { Value::Null }) == *v
                    })
                });
                let Some(a) = a else {
                    bad.push(format!("{title}: step {i}: not legal: {want:?}"));
                    break;
                };
                assert!(g.apply(&Value::Object(a)).ok);
                if let Some(e) = g.script_error.get() {
                    bad.push(format!("{title}: step {i}: {e}"));
                    break;
                }
            }
        }
    }
    assert!(bad.is_empty(), "{} problems:\n{}", bad.len(), bad.join("\n"));
}

#[test]
fn mass_hysteria_friendly_minions_attack_each_other() {
    let mut t = scene!({"hand": ["TRL_258"], "board": [YETI, YETI]}, {});
    t.play("TRL_258", NONE);
    let attacks = t.events().iter().filter(|e| e["type"] == "attack").count();
    assert_eq!(attacks, 2, "each Yeti attacks the other: real attacks, which fire attack triggers");
    assert!(t.g.players[0].board.is_empty(), "both died");
}

/// Jungle Giants: The Darkness does not advance it (12.2.0.26996, before the release build 27845).
#[test]
fn the_darkness_does_not_advance_jungle_giants() {
    let mut t = scene!({"hand": ["UNG_116", "LOOT_526", "VAN_EX1_028"]}, {});
    t.play("UNG_116", NONE).play("LOOT_526", NONE);
    let q = t.g.players[0].secrets[0];
    assert_eq!(t.g.e(q).tag("QUEST_PROGRESS"), 0);
    t.play("VAN_EX1_028", NONE);
    assert_eq!(t.g.e(q).tag("QUEST_PROGRESS"), 1);
}
