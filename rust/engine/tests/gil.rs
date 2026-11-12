//! The Witchwood pack (packs/gil, built by tools/pack.py on Kobolds & Catacombs and the packs before it): the cards as on
//! 2018-04-12 (build 23966) and the engine features it needs: Rush (QUICK), Echo and Start of Game (the player hooks),
//! a card that transforms in the hand keeping its enchantments (`g.transform(e, card, true)`: the worgen, Chameleos),
//! Shudderwock (`g.battlecry`), Glinda Crowskin (an aura in the hand), Nightmare Amalgam (`every_race`), the patches
//! 10.2 and 11.0 (the older cards of that day), and whole bot games with every deck template. Needs python3 (skipped
//! without it).


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
        let out = std::env::temp_dir().join(format!("gil-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/gil", "-o"]).arg(&out).output().ok()?;
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
const NONE: Id = -1;

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
    fn can_play(&self, card: &str) -> bool {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e)
    }
    fn power_on(&mut self, target: Id) -> &mut Self {
        self.act("hero power", |a| a["type"] == "hero_power" && int(a.get("target")) == target)
    }
    fn can_power(&self) -> bool {
        self.g.legal_actions().iter().any(|a| a["type"] == "hero_power")
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
    fn options(&self) -> Vec<String> {
        self.g.pending_options().iter().map(|&o| self.g.e(o).card_id.to_string()).collect()
    }
    fn pick_card(&mut self, card: &str) -> &mut Self {
        let id = *self.g.pending_options().iter().find(|&&o| self.g.e(o).card_id == card).unwrap_or_else(|| panic!("{card} not offered"));
        self.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == id)
    }
    fn pick_first(&mut self) -> String {
        let id = self.g.pending_options()[0];
        let c = self.g.e(id).card_id.to_string();
        self.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == id);
        c
    }
    fn events(&self) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).collect()
    }
}

fn card_of(t: &T, e: Id) -> String {
    t.g.e(e).card_id.to_string()
}


fn mulligan_both(g: &mut Game) {
    for p in 0..2 {
        let a = g.legal_actions().into_iter().find(|a| a["type"] == "mulligan" && int(a.get("player")) == p as i64
            && a.get("replace").and_then(Value::as_array).is_some_and(|r| r.is_empty())).expect("keep all");
        assert!(g.apply(&Value::Object(a)).ok);
    }
}

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(rs.cards.values().filter(|x| x.collectible && x.set == "GILNEAS").count(), 135);
    // the release build (23966), not today's
    assert_eq!(c("GIL_191").cost, 4, "Fiendish Circle 4 until 2021");
    assert_eq!(c("GIL_531").cost, 1, "Witch's Apprentice 1");
    assert_eq!(stats("GIL_547"), (5, 4, 4), "Darius Crowley 4/4");
    assert_eq!(c("GIL_598").cost, 8, "Tess Greymane 8");
    assert_eq!(c("GIL_663").cost, 2, "Witchwood Apple 2");
    assert_eq!(c("GIL_801").cost, 2, "Snap Freeze 2");
    assert_eq!(c("GIL_545").race, "BEAST", "Ghostly Charger a Beast (no Undead tribe in 2018)");
    assert_eq!(c("GIL_534").race, "", "Hench-Clan Thug: no tribe");
    assert_eq!(c("GIL_584").race, "", "Witchwood Piper: no tribe until patch 11.4");
    assert_eq!(c("GIL_681").race, "ALL", "Nightmare Amalgam");
    // the older cards of patches 10.2 and 11.0
    assert_eq!(stats("LOOT_149"), (7, 2, 5), "Corridor Creeper 2/5 (patch 10.2)");
    assert!(!c("CFM_637").keywords.iter().any(|k| k == "CHARGE"), "Patches without Charge (patch 10.2)");
    assert_eq!(c("ICC_705").cost, 8, "Bonemare 8 (patch 10.2)");
    assert_eq!(c("VAN_EX1_620").cost, 20, "Molten Giant 20 again (patch 11.0)");
    assert!(c("KAR_096").keywords.iter().any(|k| k == "START_OF_GAME"), "Prince Malchezaar: Start of Game (patch 11.0)");
    // what came later stays out
    assert_eq!(c("LOOT_539").cost, 6, "Spiteful Summoner 6 until 11.1");
    assert_eq!(c("LOOT_017").cost, 1, "Dark Pact");
    for id in ["ICC_828t4", "ICC_828t5", "ICC_828t6", "ICC_828t7"] {
        assert!(rs.cards.contains_key(id), "{id}: Deathstalker Rexxar's new Zombeast parts");
    }
    assert!(rs.lifesteal_one_heal && !rs.countered_no_after_spell);
}

#[test]
fn raza_makes_the_hero_power_cost_one() {
    let mut t = scene!({"hero": "HERO_09", "hand": ["CFM_020"], "deck": [YETI, WISP]}, {});
    t.play("CFM_020", NONE);
    let p = t.g.players[0].hero_power;
    assert_eq!(t.g.cost(p), 1, "patch 10.2: (1), not (0)");
}

#[test]
fn rush_attacks_minions_not_heroes_the_turn_it_comes() {
    let mut t = scene!({"hand": ["GIL_113"]}, {"board": [WISP]});
    t.play("GIL_113", NONE);
    let w = t.on_board(0, "GIL_113");
    let y = t.on_board(1, WISP);
    let foe = t.hero(1);
    let can = |t: &T, d: Id| t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == w && int(a.get("defender")) == d);
    assert!(can(&t, y), "a minion: yes");
    assert!(!can(&t, foe), "the hero: not this turn");
    t.attack(w, y);
    t.end_turn().end_turn();
    let w = t.on_board(0, "GIL_113");
    assert!(t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == w && int(a.get("defender")) == t.hero(1)), "next turn the hero too");
}

#[test]
fn echo_gives_a_copy_that_goes_at_the_end_of_the_turn() {
    let mut t = scene!({"hand": ["GIL_207"]}, {});
    t.play("GIL_207", NONE);
    assert_eq!(t.hand(0), vec!["GIL_207"], "a copy");
    let copy = t.hand_id("GIL_207");
    assert!(t.g.e(copy).has("GHOSTLY"));
    t.play("GIL_207", NONE);
    assert_eq!(t.cards(0), vec!["GIL_207", "GIL_207"]);
    assert_eq!(t.hand(0), vec!["GIL_207"], "the copy's copy");
    t.end_turn();
    assert!(t.hand(0).is_empty(), "gone at the end of the turn");
    assert!(t.events().iter().any(|e| e["type"] == "faded"));
}

#[test]
fn nightmare_amalgam_is_every_race() {
    // Murloc Warleader (patch 9.1: other Murlocs +2 Attack) counts it as a Murloc
    let t = scene!({"board": ["VAN_EX1_507", "GIL_681"]}, {});
    let a = t.on_board(0, "GIL_681");
    assert_eq!(t.stats(a), (3 + 2, 4));
}

fn start_game(rs: &'static Ruleset, d0: &[String], d1: &[String], seed: i64) -> Game {
    let mut g = Game::new_in(rs, "HERO_08", d0, "HERO_01", d1, seed, 0, true);
    mulligan_both(&mut g);
    assert_eq!(g.script_error.get(), None);
    g
}

#[test]
fn baku_upgrades_the_hero_power_of_an_odd_deck() {
    let Some(rs) = rs() else { return };
    let mut odd: Vec<String> = vec!["VAN_CS2_168".to_string(); 29]; // Murloc Raider (1)
    odd.push("GIL_826".into());
    let plain: Vec<String> = vec![YETI.to_string(); 30];
    let g = start_game(rs, &odd, &plain, 1);
    assert_eq!(g.e(g.players[0].hero_power).card_id, "AT_132_MAGE", "Fireblast Rank 2");
    assert!(g.history.iter().any(|h| h.events().iter().any(|e| e["type"] == "start_of_game" && e["card"] == "GIL_826")));
    assert_eq!(g.e(g.players[1].hero_power).card_id, "VAN_HERO_01bp");
    // one even card anywhere in the starting deck: nothing
    let mut one_even = odd.clone();
    one_even[0] = YETI.into();
    let g = start_game(rs, &one_even, &plain, 1);
    assert_eq!(g.e(g.players[0].hero_power).card_id, "VAN_HERO_08bp");
}

#[test]
fn genn_makes_the_starting_hero_power_cost_one() {
    let Some(rs) = rs() else { return };
    let mut even: Vec<String> = vec![YETI.to_string(); 29];
    even.push("GIL_692".into());
    let plain: Vec<String> = vec![YETI.to_string(); 30];
    let g = start_game(rs, &plain, &even, 2);
    assert_eq!(g.cost(g.players[1].hero_power), 1);
    assert_eq!(g.cost(g.players[0].hero_power), 2, "the other player's: (2)");
}

#[test]
fn stand_against_darkness_needs_room_since_patch_11() {
    let t = scene!({"hand": ["OG_273"], "board": [WISP, WISP, WISP, WISP, WISP, WISP, WISP]}, {});
    assert!(!t.can_play("OG_273"), "a full board: it can't be cast");
    let mut t = scene!({"hand": ["OG_273"], "board": [WISP, WISP, WISP, WISP, WISP, WISP]}, {});
    t.play("OG_273", NONE);
    assert_eq!(t.cards(0).len(), 7);
}

// --- the cards, by group ------------------------------------------------------------------------------------

#[path = "gil/dhm.rs"]
mod dhm;
#[path = "gil/ppr.rs"]
mod ppr;
#[path = "gil/ssw.rs"]
mod ssw;
#[path = "gil/n1.rs"]
mod n1;
#[path = "gil/n2.rs"]
mod n2;
#[path = "gil/decks.rs"]
mod decks;
