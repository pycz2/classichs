//! Hearthstone 2014–2019 (packs/eras), the One Night in Karazhan era: versions 13921, 14366, 14830 (patch 6.1.3:
//! Charge, Tuskarr Totemic, Yogg-Saron) and 15181 (patch 6.2: the Murloc lords help only their side, Ethereal Peddler,
//! Yogg-Saron and Servant of Yogg-Saron with Overload, Yogg-Saron stops when Silenced), each played against the version
//! before it. Needs python3 (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{pack, scenario, Game};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::OnceLock;
#[path = "eras_versions/built.rs"]
mod built;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The rules of each version of packs/eras (built once by tools/pack.py); None without python3.
fn rs(vid: &str) -> Option<&'static Ruleset> {
    static R: OnceLock<Option<HashMap<String, &'static Ruleset>>> = OnceLock::new();
    let all = R.get_or_init(|| {
        let files = built::built("packs/eras")?;
        let ids = ["13921", "14366", "14830", "15181", "15590", "17720", "18336", "20022", "20457", "22115"];
        Some(ids.iter().map(|v| (v.to_string(), ruleset::load(&pack::version_view(&files, v).unwrap()).unwrap())).collect())
    });
    all.as_ref().map(|m| m[vid])
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const FIREBALL: &str = "VAN_CS2_029";
const ASSASSINATE: &str = "VAN_CS2_076";
const BRAWL: &str = "VAN_EX1_407";
const MURLOC_RAIDER: &str = "VAN_CS2_168";
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];
const NONE: Id = -1;
const BASIC_TOTEMS: [&str; 4] = ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009"];

struct T {
    g: Game,
}

/// A game of version vid: p0 and p1 are merged over the defaults (10 mana each, decks of Wisps); p0's turn.
fn game(vid: &str, seed: u64, p0: Value, p1: Value) -> Option<T> {
    let rs = rs(vid)?;
    let merge = |base: Value, over: Value| {
        let mut b = base.as_object().unwrap().clone();
        b.extend(over.as_object().unwrap().clone());
        Value::Object(b)
    };
    let d0 = json!({"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL});
    let d1 = json!({"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL});
    let sc = json!({"current": 0, "seed": seed, "players": [merge(d0, p0), merge(d1, p1)]});
    Some(T { g: scenario::build_in(rs, &sc).unwrap() })
}

macro_rules! scene {
    ($v:expr, $p0:tt, $p1:tt) => {
        scene!($v, 7, $p0, $p1)
    };
    ($v:expr, $seed:expr, $p0:tt, $p1:tt) => {
        match game($v, $seed, json!($p0), json!($p1)) {
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
    fn can_attack(&self, a: Id, d: Id) -> bool {
        self.g.legal_actions().iter().any(|x| x["type"] == "attack" && int(x.get("attacker")) == a && int(x.get("defender")) == d)
    }
    fn cost(&self, card: &str) -> i64 {
        self.g.cost(self.hand_id(card))
    }
    fn events(&self) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).collect()
    }
}

// --- patch 6.1.3 (14830) ---------------------------------------------------------------------------------------------

#[test]
fn charge_gives_no_attack_and_no_hero_from_6_1_3() {
    for (v, cost, atk, hero) in [("14366", 3, 6, true), ("14830", 1, 4, false), ("15181", 1, 4, false)] {
        let mut t = scene!(v, {"hand": ["VAN_CS2_103", YETI]}, {"board": [WISP]});
        t.play(YETI, NONE);
        let y = t.on_board(0, YETI);
        assert_eq!(t.cost("VAN_CS2_103"), cost, "{v}");
        t.play("VAN_CS2_103", y);
        assert_eq!(t.stats(y).0, atk, "{v}");
        let (h, w) = (t.g.players[1].hero, t.nth(1, 0));
        assert_eq!(t.can_attack(y, h), hero, "{v}: the hero");
        assert!(t.can_attack(y, w), "{v}: a minion");
    }
}

#[test]
fn tuskarr_totemic_summons_only_basic_totems_from_6_1_3() {
    for (v, any) in [("14366", true), ("14830", false), ("15181", false)] {
        let mut other = false;
        for seed in 0..40 {
            let mut t = scene!(v, seed, {"hero": "HERO_02", "hand": ["AT_046"]}, {});
            t.play("AT_046", NONE);
            let totem = t.g.e(t.nth(0, 1)).card_id.to_string();
            assert_eq!(t.g.rs.card(&totem).race, "TOTEM", "{v} {totem}");
            other |= !BASIC_TOTEMS.contains(&totem.as_str());
        }
        assert_eq!(other, any, "{v}: a Totem other than the basic ones");
    }
}

/// Yogg-Saron with `spells` spells cast before, against a board of Yetis; the game and its Yogg-Saron entity.
fn yogg(v: &str, seed: u64, card: &str, spells: i64) -> Option<(T, Id)> {
    let mut t = game(v, seed, json!({"hand": [card], "board": [YETI]}), json!({"board": [YETI, YETI]}))?;
    t.g.players[0].counts.insert("SPELLS".to_string(), spells);
    t.play(card, NONE);
    let me = t.events().iter().find(|e| e["type"] == "play" && e["card"] == card).map(|e| int(e.get("entity")))?;
    Some((t, me))
}

/// The random casts after the first event that matches gone (none: 0).
fn casts_after(t: &T, gone: impl Fn(&Map<String, Value>) -> bool) -> usize {
    let evs = t.events();
    match evs.iter().position(gone) {
        Some(i) => evs[i..].iter().filter(|e| (e["type"] == "cast" && e.get("random") == Some(&json!(true))) || e["type"] == "fizzle").count(),
        None => 0,
    }
}

#[test]
fn yogg_saron_stops_when_destroyed_from_6_1_3() {
    for (v, goes_on) in [("14366", true), ("14830", false), ("15181", false)] {
        let mut after_death = 0;
        for seed in 0..30 {
            let Some((t, me)) = yogg(v, seed, "OG_134", 30) else {
                eprintln!("no python3: skipped");
                return;
            };
            assert_eq!(t.g.script_error.get(), None, "{v} seed {seed}");
            after_death += casts_after(&t, |e| (e["type"] == "death" && int(e.get("entity")) == me) || (e["type"] == "transform" && int(e.get("from")) == me));
        }
        assert_eq!(after_death > 0, goes_on, "{v}: spells cast after Yogg-Saron died: {after_death}");
    }
}

// --- patch 6.2 (15181) -----------------------------------------------------------------------------------------------

#[test]
fn yogg_saron_stops_when_silenced_from_6_2() {
    for (v, goes_on) in [("14830", true), ("15181", false)] {
        let mut after = 0;
        for seed in 0..300 {
            let Some((t, me)) = yogg(v, seed, "OG_134", 30) else {
                eprintln!("no python3: skipped");
                return;
            };
            assert_eq!(t.g.script_error.get(), None, "{v} seed {seed}");
            after += casts_after(&t, |e| e["type"] == "silence" && int(e.get("target")) == me);
        }
        assert_eq!(after > 0, goes_on, "{v}: spells cast after Yogg-Saron was Silenced: {after}");
    }
}

#[test]
fn yogg_saron_and_its_servant_overload_from_6_2() {
    // 15181 by its version script (kara_6_2.lua), the msg pack and the later ones by msg.lua's Servant
    for card in ["OG_134", "OG_087"] {
        for (v, overloads) in [("14830", false), ("15181", true), ("15590", true), ("17720", true), ("18336", true), ("20022", true), ("20457", true), ("22115", true)] {
            let (mut cast, mut owed) = (0, 0);
            for seed in 0..60 {
                let Some((t, _)) = yogg(v, seed, card, 10) else {
                    eprintln!("no python3: skipped");
                    return;
                };
                let rs = t.g.rs;
                cast += t.events().iter().filter(|e| e["type"] == "cast" && rs.card(e["card"].as_str().unwrap()).mana_lock > 0).count();
                owed += t.g.players[0].mana_lock_owed;
            }
            assert!(cast > 0, "{card} {v}: no spell with Overload cast");
            assert_eq!(owed > 0, overloads, "{card} {v}: Overload owed {owed} after {cast} spells with Overload");
        }
    }
}

#[test]
fn murloc_lords_help_only_your_murlocs_from_6_2() {
    // Murloc Warleader and Grimscale Oracle: the enemy Murloc Raider (2/1) is helped until 6.2
    for (v, enemy) in [("14830", (5, 2)), ("15181", (2, 1))] {
        let t = scene!(v, {"board": ["VAN_EX1_507", "VAN_EX1_508", MURLOC_RAIDER]}, {"board": [MURLOC_RAIDER]});
        assert_eq!(t.stats(t.on_board(0, MURLOC_RAIDER)), (5, 2), "{v}");
        assert_eq!(t.stats(t.on_board(1, MURLOC_RAIDER)), enemy, "{v}");
    }
    // Coldlight Seer: +2 Health to the other Murlocs
    for (v, enemy) in [("14830", 3), ("15181", 1)] {
        let mut t = scene!(v, {"hand": ["VAN_EX1_103"], "board": [MURLOC_RAIDER]}, {"board": [MURLOC_RAIDER]});
        t.play("VAN_EX1_103", NONE);
        assert_eq!(t.stats(t.on_board(0, MURLOC_RAIDER)).1, 3, "{v}");
        assert_eq!(t.stats(t.on_board(1, MURLOC_RAIDER)).1, enemy, "{v}");
    }
    // Murloc Tidecaller: +1 Attack for an enemy Murloc summoned until 6.2
    for (v, atk) in [("14830", 2), ("15181", 1)] {
        let mut t = scene!(v, {"board": ["VAN_EX1_509"]}, {"hand": [MURLOC_RAIDER]});
        t.act("end turn", |a| a["type"] == "end_turn");
        t.play(MURLOC_RAIDER, NONE);
        assert_eq!(t.stats(t.on_board(0, "VAN_EX1_509")).0, atk, "{v}");
    }
}

#[test]
fn ethereal_peddler_reduces_non_rogue_class_cards_from_6_2() {
    // a Mage plays it: until 6.2 the cards of another class than the hero's (Assassinate, Brawl), then the non-Rogue
    // class cards (Fireball, Brawl); a neutral card never
    for (v, fireball, assassinate) in [("14830", 4, 3), ("15181", 2, 5)] {
        let mut t = scene!(v, {"hand": ["KAR_070", FIREBALL, ASSASSINATE, BRAWL, YETI]}, {});
        t.play("KAR_070", NONE);
        assert_eq!((t.cost(FIREBALL), t.cost(ASSASSINATE), t.cost(BRAWL), t.cost(YETI)), (fireball, assassinate, 3, 4), "{v}");
    }
}
