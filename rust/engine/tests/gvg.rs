//! The Goblins vs Gnomes pack (packs/gvg, built by tools/pack.py on Naxxramas and Classic): the cards as on
//! 2014-12-08, the new cards' scripts in small scenarios, the engine features they need (`hand` hooks,
//! `g.add_to_deck`, `g.deathrattle`, `target.when`, a trap changing sides, the `armor` event), and whole bot
//! games with every deck template. Needs python3 (skipped without it).

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
        let out = std::env::temp_dir().join(format!("gvg-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/gvg", "-o"]).arg(&out).output().ok()?;
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
    fn parts(&self, p: usize) -> usize {
        self.hand(p).iter().filter(|c| c.starts_with("PART_")).count()
    }
}

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    // older cards as on 2014-12-08 (patches 1.2.0.6485 and 2.0.0.7234)
    assert_eq!((c("VAN_CS2_237").cost, c("VAN_CS2_237").attack, c("VAN_CS2_237").health), (5, 3, 2), "Starving Buzzard");
    assert_eq!(c("VAN_EX1_116").cost, 5, "Leeroy Jenkins");
    assert_eq!(c("VAN_EX1_095").cost, 6, "Gadgetzan Auctioneer");
    assert_eq!(c("VAN_EX1_308").cost, 1, "Soulfire");
    assert_eq!(c("VAN_EX1_544").cost, 2, "Flare");
    for m in ["VAN_EX1_006", "VAN_EX1_102", "VAN_EX1_556", "VAN_skele21", "EX1_025t", "Mekka1", "Mekka2", "Mekka3", "Mekka4"] {
        assert_eq!(c(m).race, "MECHANICAL", "{m} is a Mech since 2.0.0.7234");
    }
    assert_eq!(c("VAN_EX1_165t1").race, "BEAST");
    assert_eq!(c("FP1_028").race, "", "Undertaker: still +1/+1, no tribe");
    // GvG cards as released (later changes undone)
    assert_eq!((c("GVG_006").cost, c("GVG_006").attack, c("GVG_006").health), (2, 2, 3), "Mechwarper 2/3");
    assert_eq!((c("GVG_109").cost, c("GVG_109").attack), (4, 4), "Mini-Mage 4/1 for 4");
    assert_eq!((c("GVG_046").cost, c("GVG_046").attack, c("GVG_046").health), (5, 2, 6), "King of Beasts");
    assert_eq!((c("GVG_050").cost, c("GVG_053").cost, c("GVG_073").cost, c("GVG_114").cost), (3, 6, 5, 8));
    assert_eq!((c("GVG_009").attack, c("GVG_123").health, c("GVG_042").race.as_str()), (2, 3, ""));
    assert_eq!(rs.collectible.iter().filter(|id| id.starts_with("GVG_")).count(), 123);
    assert!(!rs.collectible.iter().any(|id| id.starts_with("PART_")));
}

#[test]
fn bestial_wrath_only_a_friendly_beast() {
    let t = scene!({"hero": "HERO_05", "hand": ["VAN_EX1_549"], "board": ["VAN_CS2_172"]}, {"board": ["VAN_CS2_172"]});
    let (mine, theirs) = (t.nth(0, 0), t.nth(1, 0));
    assert!(t.can_target("VAN_EX1_549", mine) && !t.can_target("VAN_EX1_549", theirs));
}

#[test]
fn flame_leviathan_burns_when_drawn() {
    let mut t = scene!({"deck": [WISP, "GVG_007"], "hand": ["GVG_007"]}, {"board": [WISP]});
    t.end_turn().end_turn(); // p0 draws the Leviathan at the top
    assert_eq!(t.hand(0).iter().filter(|c| *c == "GVG_007").count(), 2);
    assert_eq!(t.hp(0), 28, "2 damage to all characters, once (the one already in hand does nothing)");
    assert_eq!(t.hp(1), 28);
    assert!(t.cards(1).is_empty(), "the Wisp died");
}

#[test]
fn iron_juggernaut_mine_explodes_when_drawn() {
    let mut t = scene!({"hand": ["GVG_056"]}, {"deck": [WISP, WISP]});
    t.play("GVG_056", NONE);
    assert!(t.deck(1).contains(&"GVG_056t".to_string()));
    assert_eq!(t.deck(1).len(), 3);
    let mut t = scene!({}, {"deck": [WISP, WISP, "GVG_056t"]});
    t.end_turn();
    assert_eq!(t.hp(1), 20, "10 damage");
    assert_eq!(t.hand(1), vec![WISP.to_string()], "the Mine is gone and a card is drawn instead");
}

#[test]
fn bolvar_grows_in_the_hand() {
    let mut t = scene!({"hand": ["GVG_063", FIREBALL], "board": [WISP]}, {});
    let w = t.nth(0, 0);
    t.play(FIREBALL, w);
    let b = t.hand_id("GVG_063");
    assert_eq!(t.g.e(b).atk(), 2);
    t.play("GVG_063", NONE);
    assert_eq!(t.stats(t.on_board(0, "GVG_063")), (2, 7));
}

#[test]
fn recycle_and_malorne_shuffle_into_decks() {
    let mut t = scene!({"hand": ["GVG_031"]}, {"board": [YETI]});
    let y = t.nth(1, 0);
    t.play("GVG_031", y);
    assert!(t.cards(1).is_empty());
    assert_eq!(t.deck(1).iter().filter(|c| *c == YETI).count(), 1);
    let mut t = scene!({"board": ["GVG_035"], "hand": ["VAN_EX1_622"]}, {});
    let m = t.nth(0, 0);
    let deck = t.deck(0).len();
    t.play("VAN_EX1_622", m); // Shadow Word: Death
    assert_eq!(t.deck(0).len(), deck + 1);
    assert!(t.deck(0).contains(&"GVG_035".to_string()));
}

#[test]
fn feign_death_triggers_deathrattles() {
    let mut t = scene!({"hero": "HERO_05", "hand": ["GVG_026"], "board": ["FP1_007", "GVG_076"]}, {"board": [WISP]});
    t.play("GVG_026", NONE);
    // the Egg's Nerubian (4/4), the Sheep's 2 damage to all: the Wisp, the Egg (0/2) and the Sheep die; then
    // their own Deathrattles: a second Nerubian, and 2 more damage that kills the first one (2 + 2)
    assert!(t.cards(1).is_empty());
    assert_eq!(t.cards(0), vec!["FP1_007t".to_string()]);
    assert_eq!(t.stats(t.nth(0, 0)), (4, 2));
}

#[test]
fn steamwheedle_sniper_lets_steady_shot_target_minions() {
    let t = scene!({"hero": "HERO_05"}, {"board": [YETI]});
    assert_eq!(t.power_targets(), vec![NONE], "no target without the Sniper");
    let mut t = scene!({"hero": "HERO_05", "board": ["GVG_087"]}, {"board": [YETI]});
    let (y, foe, me) = (t.nth(1, 0), t.hero(1), t.hero(0));
    let ts = t.power_targets();
    assert!(ts.contains(&y) && ts.contains(&foe) && !ts.contains(&me));
    t.power(y);
    assert_eq!(t.stats(y), (4, 3));
}

#[test]
fn kezan_mystic_steals_a_secret() {
    let mut t = scene!({"hand": ["GVG_074"]}, {"hero": "HERO_08", "secrets": ["VAN_EX1_289"]});
    t.play("GVG_074", NONE);
    assert!(t.g.players[1].secrets.is_empty());
    let s = t.g.players[0].secrets[0];
    assert_eq!((t.g.e(s).card_id, t.g.e(s).controller), ("VAN_EX1_289", 0));
    // a copy of one it already has is destroyed
    let mut t = scene!({"hand": ["GVG_074"], "secrets": ["VAN_EX1_289"]}, {"secrets": ["VAN_EX1_289"]});
    t.play("GVG_074", NONE);
    assert_eq!((t.g.players[0].secrets.len(), t.g.players[1].secrets.len()), (1, 0));
    // five Secrets already: the stolen one is destroyed (the limit is 5)
    let five = ["VAN_EX1_289", "VAN_EX1_294", "VAN_EX1_295", "VAN_EX1_594", "VAN_tt_010"];
    let mut t = scene!({"hand": ["GVG_074"], "secrets": five}, {"secrets": ["VAN_EX1_287"]});
    t.play("GVG_074", NONE);
    assert_eq!((t.g.players[0].secrets.len(), t.g.players[1].secrets.len()), (5, 0));
}

#[test]
fn siege_engine_grows_with_armor() {
    let mut t = scene!({"hero": "HERO_01", "board": ["GVG_086"], "hand": ["GVG_053"]}, {});
    t.power(NONE).play("GVG_053", NONE);
    assert_eq!(t.stats(t.on_board(0, "GVG_086")).0, 7);
}

#[test]
fn v07_attacks_four_times() {
    let mut t = scene!({"board": ["GVG_111t"]}, {});
    let (v, foe) = (t.nth(0, 0), t.hero(1));
    for _ in 0..4 {
        t.attack(v, foe);
    }
    assert_eq!(t.hp(1), 14);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack"));
    t.end_turn().end_turn();
    t.attack(v, foe);
    assert_eq!(t.hp(1), 10);
}

#[test]
fn mimirons_head_forms_v07() {
    let mut t = scene!({"board": ["GVG_111", "GVG_085", "GVG_082"]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.cards(0), vec!["GVG_111t".to_string()]);
    assert_eq!(t.parts(0), 1, "the Gnome's Spare Part");
    // a full board: the Mechs die at once to make room; V-07-TR-0N comes before their Deathrattles, so the
    // Sheep's 2 damage hits it too
    let mut t = scene!({"board": ["GVG_111", "GVG_085", "GVG_076", YETI, YETI, YETI, YETI]}, {});
    t.end_turn().end_turn();
    let v = t.on_board(0, "GVG_111t");
    assert_eq!(t.stats(v), (4, 6));
    assert_eq!(t.cards(0).len(), 5, "the four Yetis (3 Health left) and V-07-TR-0N");
}

#[test]
fn gazlowe_counts_the_cost_when_cast() {
    // Frostbolt (2) with Sorcerer's Apprentice costs 1: a Mech; Arcane Shot (1) under Loatheb costs 6: none
    let mut t = scene!({"board": ["GVG_117", "VAN_EX1_608"], "hand": ["VAN_CS2_024"]}, {});
    let foe = t.hero(1);
    t.play("VAN_CS2_024", foe);
    assert_eq!(t.hand(0).len(), 1);
    assert_eq!(t.g.e(t.g.players[0].hand[0]).race(), "MECHANICAL");
    let mut t = scene!({"board": ["GVG_117"], "hand": ["VAN_DS1_185"]}, {"hand": ["FP1_030"]});
    t.end_turn().play("FP1_030", NONE).end_turn();
    assert_eq!(t.cost("VAN_DS1_185"), 6);
    let foe = t.hero(1);
    t.play("VAN_DS1_185", foe);
    assert!(t.g.players[0].hand.iter().all(|&e| t.g.e(e).race() != "MECHANICAL"), "Loatheb made it a 6-mana spell");
    let mut t = scene!({"board": ["GVG_117"], "hand": ["VAN_DS1_185"]}, {});
    let foe = t.hero(1);
    t.play("VAN_DS1_185", foe);
    assert_eq!(t.hand(0).len(), 1, "a 1-mana spell: a Mech");
}

#[test]
fn ogre_brute_sometimes_attacks_the_wrong_enemy() {
    let Some(rs) = rs() else { return };
    let mut wrong = 0;
    for seed in 0..40 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL, "board": ["GVG_065"]},
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL, "board": [YETI]}]});
        let mut t = T { g: scenario::build_in(rs, &sc).unwrap() };
        let (o, foe) = (t.nth(0, 0), t.hero(1));
        t.attack(o, foe);
        if t.hp(1) == 30 {
            wrong += 1;
            assert_eq!(t.g.e(t.nth(1, 0)).damage, 4);
        }
    }
    assert!((8..=32).contains(&wrong), "about half: {wrong}");
}

#[test]
fn foe_reaper_hits_the_neighbours() {
    let mut t = scene!({"board": ["GVG_113"]}, {"board": [WISP, YETI, WISP]});
    let (f, y) = (t.nth(0, 0), t.nth(1, 1));
    t.attack(f, y);
    assert!(t.cards(1).is_empty(), "the Yeti and both Wisps died");
}

#[test]
fn spare_parts_and_mechs() {
    let mut t = scene!({"board": ["GVG_006"], "hand": ["GVG_085", "GVG_102", "GVG_004"]}, {"board": [YETI]});
    assert_eq!(t.cost("GVG_085"), 1, "Mechwarper: Mechs cost (1) less");
    assert_eq!(t.cost("GVG_102"), 3);
    let tech = t.hand_id("GVG_102");
    assert!(t.g.glows(tech), "Tinkertown Technician glows with a Mech in play");
    t.play("GVG_102", NONE);
    assert_eq!(t.stats(t.on_board(0, "GVG_102")), (4, 4));
    assert_eq!(t.parts(0), 1);
    t.play("GVG_004", NONE);
    let y = t.nth(1, 0);
    assert_eq!(t.hp(1) + t.g.e(y).health(), 30 + 5 - 4, "4 damage split among the enemies");
}

#[test]
fn gallywix_takes_a_copy_and_gives_a_coin() {
    let mut t = scene!({"hand": [FIREBALL]}, {"board": ["GVG_028"]});
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    assert_eq!(t.hand(0), vec!["GVG_028t".to_string()]);
    assert_eq!(t.hand(1), vec![FIREBALL.to_string()]);
    t.play("GVG_028t", NONE);
    assert_eq!(t.hand(1), vec![FIREBALL.to_string()], "Gallywix's Coin is not copied");
}

#[test]
fn bouncing_blade_until_one_dies() {
    let mut t = scene!({"hand": ["GVG_050"], "board": [YETI]}, {"board": [YETI]});
    t.play("GVG_050", NONE);
    assert_eq!(t.g.players.iter().map(|p| p.board.len()).sum::<usize>(), 1);
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/gvg/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30);
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
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
                    if e["type"] == "play" && (card.starts_with("GVG_") || card.starts_with("PART_")) {
                        played.insert(card.to_string());
                    }
                }
            }
        }
    }
    assert!(over >= decks.len(), "most games end");
    // the new cards are really played: Mechs, Spare Parts, Dr. Boom…
    let gvg = played.iter().filter(|c| c.starts_with("GVG_")).count();
    let parts = played.iter().filter(|c| c.starts_with("PART_")).count();
    eprintln!("GvG cards played: {gvg}, Spare Parts played: {parts}: {played:?}");
    assert!(gvg >= 20 && parts >= 1, "{played:?}");
}
