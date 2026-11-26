//! Hearthstone 2014–2019 (packs/eras), the versions of Kobolds & Catacombs (22611, 23180, 23576) and The Witchwood
//! (23966, 24377, 24589, 24769, 25252): each version's changed cards played out against the version before, and every
//! card of each of them playing without a script error. Needs python3 (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::pack::{self, Files};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{bot, scenario, Game};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
#[path = "eras_versions/built.rs"]
mod built;

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const NONE: Id = -1;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// packs/eras built once by tools/pack.py; None without python3.
fn eras() -> Option<&'static Files> {
    static F: OnceLock<Option<Files>> = OnceLock::new();
    F.get_or_init(|| built::built("packs/eras")).as_ref()
}

/// The rules of version `vid` (its view, loaded once).
fn rs(vid: &str) -> Option<&'static Ruleset> {
    static R: OnceLock<Mutex<HashMap<String, &'static Ruleset>>> = OnceLock::new();
    let files = eras()?;
    let mut m = R.get_or_init(|| Mutex::new(HashMap::new())).lock().unwrap();
    Some(*m.entry(vid.to_string()).or_insert_with(|| {
        ruleset::load(&pack::version_view(files, vid).unwrap()).unwrap_or_else(|e| panic!("version {vid}: {e}"))
    }))
}

struct T {
    g: Game,
}

fn game(vid: &str, p0: Value, p1: Value) -> Option<T> {
    let rs = rs(vid)?;
    let merge = |base: Value, over: Value| {
        let mut b = base.as_object().unwrap().clone();
        b.extend(over.as_object().unwrap().clone());
        Value::Object(b)
    };
    let fill = json!([WISP, WISP, WISP, WISP, WISP, WISP]);
    let d0 = json!({"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": fill});
    let d1 = json!({"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": fill});
    let sc = json!({"current": 0, "seed": 7, "players": [merge(d0, p0), merge(d1, p1)]});
    Some(T { g: scenario::build_in(rs, &sc).unwrap_or_else(|e| panic!("version {vid}: scenario: {e}")) })
}

macro_rules! scene {
    ($v:expr, $p0:tt, $p1:tt) => {
        match game($v, json!($p0), json!($p1)) {
            Some(t) => t,
            None => {
                eprintln!("no python3: skipped");
                return;
            }
        }
    };
}

impl T {
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
        self.play_choice(card, target, -1)
    }
    fn play_choice(&mut self, card: &str, target: Id, choice: i64) -> &mut Self {
        let e = self.hand_id(card);
        let last = self.g.players[self.g.current].board.len() as i64;
        self.act(&format!("play {card}"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target
                && (int(a.get("pos")) == -1 || int(a.get("pos")) == last) && int(a.get("choice")) == choice
        })
    }
    fn on_board(&self, p: usize, card: &str) -> Id {
        *self.g.players[p].board.iter().find(|&&m| self.g.e(m).card_id == card).unwrap_or_else(|| panic!("{card} not on board {p}"))
    }
    fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
    }
    fn hero(&self, p: usize) -> Id {
        self.g.players[p].hero
    }
    /// The player's count `name` set to the entities of new cards `ids` (NAME = n, NAME_<i> = the i-th), as the player
    /// hooks keep the cards played (packs/gil/scripts/gil.lua's remember()).
    fn remember(&mut self, p: usize, name: &str, ids: &[&str]) {
        let rs = self.g.rs;
        for (i, id) in ids.iter().enumerate() {
            let e = self.g.new_entity(id, p);
            self.g.players[p].counts.insert(rs.intern(&format!("{name}_{}", i + 1)), e);
        }
        self.g.players[p].counts.insert(rs.intern(name), ids.len() as i64);
    }
}

#[test]
fn patch_10_2_raza_the_chained_hero_power_costs_one() {
    for (vid, cost) in [("22611", 0), ("23180", 1), ("23576", 1)] {
        let mut t = scene!(vid, {"hero": "HERO_09", "hand": ["CFM_020"], "deck": [YETI, WISP]}, {});
        t.play("CFM_020", NONE);
        let p = t.g.players[0].hero_power;
        assert_eq!(t.g.cost(p), cost, "version {vid}");
    }
}

#[test]
fn patch_10_2_patches_the_pirate_has_no_charge() {
    for (vid, charge) in [("22611", true), ("23180", false), ("25252", false)] {
        let mut t = scene!(vid, {"hand": ["CFM_637"]}, {});
        t.play("CFM_637", NONE);
        let m = t.on_board(0, "CFM_637");
        let foe = t.hero(1);
        let can = t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == m && int(a.get("defender")) == foe);
        assert_eq!(can, charge, "version {vid}");
    }
}

#[test]
fn patch_11_1_shudderwock_replays_at_most_20_battlecries_until_the_hotfix() {
    // 25 Novice Engineers remembered: each replayed Battlecry draws a card (a full hand burns it: the deck counts)
    for (vid, draws) in [("23966", 25), ("24377", 20), ("24589", 20), ("24769", 25), ("25252", 25)] {
        let deck = vec![WISP; 40];
        let mut t = scene!(vid, {"hand": ["GIL_820"], "deck": deck}, {});
        t.remember(0, "BATTLECRIES", &["VAN_EX1_015"; 25]);
        t.play("GIL_820", NONE);
        assert_eq!(40 - t.g.players[0].deck.len(), draws, "version {vid}");
    }
}

#[test]
fn patch_11_1_1_dark_pact_restores_four() {
    for (vid, hp) in [("24377", 28), ("24589", 24), ("25252", 24)] {
        let mut t = scene!(vid, {"hero": "HERO_07", "hand": ["LOOT_017"], "board": [WISP], "hero_state": {"damage": 10}}, {});
        let w = t.on_board(0, WISP);
        t.play("LOOT_017", w);
        assert_eq!(t.g.e(t.hero(0)).health(), hp, "version {vid}");
    }
}

#[test]
fn patch_11_1_1_crystal_core_makes_minions_four_four() {
    for (vid, n) in [("23966", 5), ("24377", 5), ("24589", 4), ("24769", 4), ("25252", 4)] {
        let mut t = scene!(vid, {"hero": "HERO_03", "hand": ["UNG_067t1", YETI], "board": [WISP], "deck": ["VAN_CS2_189"]}, {});
        t.play("UNG_067t1", NONE);
        let w = t.on_board(0, WISP);
        assert_eq!(t.stats(w), (n, n), "version {vid}: in play");
        t.play(YETI, NONE);
        let y = t.on_board(0, YETI);
        assert_eq!(t.stats(y), (n, n), "version {vid}: from the hand");
        // a minion drawn later (the player hooks' core())
        t.act("end turn", |a| a["type"] == "end_turn").act("end turn", |a| a["type"] == "end_turn");
        let e = t.hand_id("VAN_CS2_189");
        assert_eq!(t.stats(e), (n, n), "version {vid}: drawn later");
    }
}

#[test]
fn patch_11_2_tess_greymane_replays_hero_cards_and_at_most_30() {
    // 40 Arcane Intellects (Mage) for a Rogue: each draws 2
    for (vid, draws) in [("23966", 80), ("24589", 80), ("24769", 60), ("25252", 60)] {
        let deck = vec![WISP; 100];
        let mut t = scene!(vid, {"hero": "HERO_03", "hand": ["GIL_598"], "deck": deck}, {});
        t.remember(0, "OTHER_CARDS", &["VAN_CS2_023"; 40]);
        t.play("GIL_598", NONE);
        assert_eq!(100 - t.g.players[0].deck.len(), draws, "version {vid}");
    }
    // a hero card of another class: the Rogue becomes Frost Lich Jaina since 11.2
    for (vid, hero) in [("24589", "HERO_03"), ("24769", "ICC_833")] {
        let mut t = scene!(vid, {"hero": "HERO_03", "hand": ["GIL_598"]}, {});
        t.remember(0, "OTHER_CARDS", &["ICC_833"]);
        t.play("GIL_598", NONE);
        assert_eq!(t.g.e(t.hero(0)).card_id, hero, "version {vid}");
    }
}

#[test]
fn patch_11_2_lynessa_sunsorrow_casts_choose_one_spells_too() {
    // Mark of Nature (+4 Attack) on a Yeti, then Lynessa (a 1/1): since 11.2 she gets it too
    for (vid, atk) in [("22611", 1), ("24589", 1), ("24769", 5), ("25252", 5)] {
        let mut t = scene!(vid, {"hero": "HERO_04", "hand": ["VAN_EX1_155", "LOOT_216"], "board": [YETI], "mana": 20, "max_mana": 10}, {});
        let y = t.on_board(0, YETI);
        t.play_choice("VAN_EX1_155", y, 0);
        t.play("LOOT_216", NONE);
        let l = t.on_board(0, "LOOT_216");
        assert_eq!(t.stats(l).0, atk, "version {vid}");
    }
}

#[test]
fn patch_11_2_rat_trap_waits_for_room() {
    for (vid, kept) in [("23966", false), ("24589", false), ("24769", true), ("25252", true)] {
        let full = vec![WISP; 7];
        let mut t = scene!(vid, {"hand": [WISP, WISP, WISP]}, {"hero": "HERO_05", "board": full, "secrets": ["GIL_577"]});
        t.play(WISP, NONE).play(WISP, NONE).play(WISP, NONE);
        assert_eq!(t.g.players[1].secrets.len() == 1, kept, "version {vid}");
        assert_eq!(t.g.players[1].board.len(), 7, "version {vid}: no Doom Rat");
    }
}

#[test]
fn patch_11_4_the_tribes() {
    let Some(_) = eras() else { return };
    let race = |vid: &str, id: &str| rs(vid).unwrap().card(id).race.to_string();
    for (id, was, now) in [("VAN_EX1_105", "", "ELEMENTAL"), ("VAN_EX1_620", "", "ELEMENTAL"), ("GIL_584", "", "DEMON"),
        ("AT_103", "", "BEAST"), ("LOE_051", "BEAST", "")] {
        assert_eq!((race("24769", id).as_str(), race("25252", id).as_str()), (was, now), "{id}");
    }
}

/// Every card of version `vid` played (up to 3 ways) and a few bot moves after it, without a script error.
fn every_card_plays_without_a_script_error(vid: &str) {
    let Some(_) = eras() else { return };
    {
        let rs = rs(vid).unwrap();
        let mut ids: Vec<&String> = rs.cards.keys().filter(|k| {
            let c = rs.card(k);
            matches!(c.kind.as_str(), "MINION" | "SPELL" | "WEAPON" | "CHAMPION")
        }).collect();
        ids.sort();
        let mut n = 0;
        for id in ids {
            let deck = json!([WISP, YETI, "VAN_CS2_029", "VAN_EX1_012", WISP, YETI]);
            let Some(t) = game(vid, json!({"hand": [id, YETI, "VAN_CS2_029"], "board": [YETI, WISP], "deck": deck, "weapon": "VAN_CS2_106"}),
                json!({"board": [YETI, WISP], "hand": [WISP], "deck": deck})) else { return };
            let e = *t.g.players[0].hand.iter().find(|&&x| t.g.e(x).card_id == *id).unwrap();
            let plays: Vec<_> = t.g.legal_actions().into_iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).collect();
            for a in plays.into_iter().take(3) {
                let mut g = t.g.clone_state();
                assert!(g.apply(&Value::Object(a.clone())).ok, "version {vid}: {id}");
                for _ in 0..4 {
                    if g.game_over {
                        break;
                    }
                    let p = g.pending.as_ref().map_or(g.current, |c| c.player);
                    let b = bot::choose(&g, p).unwrap();
                    assert!(g.apply(&Value::Object(b)).ok, "version {vid}: {id}");
                }
                assert_eq!(g.script_error.get(), None, "version {vid}: {id} {a:?}");
                n += 1;
            }
        }
        assert!(n > 1500, "version {vid}: {n}");
    }
}

macro_rules! every_card {
    ($($name:ident: $vid:expr),*) => {$(
        #[test]
        fn $name() {
            every_card_plays_without_a_script_error($vid);
        }
    )*};
}
every_card!(every_card_of_22611: "22611", every_card_of_23180: "23180", every_card_of_23576: "23576",
    every_card_of_23966: "23966", every_card_of_24377: "24377", every_card_of_24589: "24589",
    every_card_of_24769: "24769", every_card_of_25252: "25252");
