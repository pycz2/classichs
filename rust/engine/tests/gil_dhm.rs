//! The Witchwood's Druid, Hunter and Mage cards (packs/gil/scripts/gil_dhm.lua) as on 2018-04-12 (build 23966). Needs
//! python3 (skipped without it).



use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{pack, scenario, Game};
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



const CROC: &str = "VAN_CS2_120"; // River Crocolisk, a 2/3 Beast (2)
const RAIDER: &str = "VAN_CS2_168"; // Murloc Raider, a 2/1 (1)
const ODD: [&str; 4] = [RAIDER, RAIDER, RAIDER, RAIDER];

// --- Druid ---

#[test]
fn witchwood_apple_adds_three_treants() {
    let mut t = scene!({"hand": ["GIL_663"]}, {});
    t.play("GIL_663", NONE);
    assert_eq!(t.hand(0), vec!["GIL_663t", "GIL_663t", "GIL_663t"]);
}

#[test]
fn druid_of_the_scythe_transforms() {
    let mut t = scene!({"hero": "HERO_06", "hand": ["GIL_188"]}, {"board": [WISP]});
    t.play_choice("GIL_188", NONE, 0);
    let d = t.on_board(0, "GIL_188t");
    assert_eq!(t.stats(d), (4, 2));
    let w = t.on_board(1, WISP);
    let attacks = |t: &T, d2: Id| t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == d && int(a.get("defender")) == d2);
    assert!(attacks(&t, w), "Rush: a minion");
    assert!(!attacks(&t, t.hero(1)), "Rush: not the hero");
    let mut t = scene!({"hero": "HERO_06", "hand": ["GIL_188"]}, {});
    t.play_choice("GIL_188", NONE, 1);
    let d = t.on_board(0, "GIL_188t2");
    assert_eq!(t.stats(d), (2, 4));
    assert!(t.g.e(d).has("TAUNT"));
    let mut t = scene!({"hero": "HERO_06", "hand": ["GIL_188"], "board": ["OG_044"]}, {});
    t.play_choice("GIL_188", NONE, 2);
    let d = t.on_board(0, "GIL_188t3");
    assert_eq!(t.stats(d), (4, 4), "Fandral: both");
}

#[test]
fn ferocious_howl_draws_then_armor_per_card() {
    let mut t = scene!({"hand": ["GIL_637", YETI, YETI]}, {});
    t.play("GIL_637", NONE);
    assert_eq!(t.hand(0).len(), 3);
    assert_eq!(t.armor(0), 3);
}

#[test]
fn witching_hour_summons_a_dead_friendly_beast() {
    let mut t = scene!({"hand": ["GIL_571", "GIL_571"], "board": [CROC, WISP]}, {"board": [YETI]});
    t.play("GIL_571", NONE);
    assert_eq!(t.cards(0), vec![CROC, WISP], "no Beast died: nothing");
    let (c, w, y) = (t.on_board(0, CROC), t.on_board(0, WISP), t.on_board(1, YETI));
    t.attack(c, y).attack(w, y);
    assert!(t.cards(0).is_empty());
    t.play("GIL_571", NONE);
    assert_eq!(t.cards(0), vec![CROC], "the Crocolisk, not the Wisp");
    assert_eq!(t.stats(t.nth(0, 0)), (2, 3), "a fresh copy");
}

#[test]
fn forest_guide_both_players_draw_at_the_end_of_your_turn() {
    let mut t = scene!({"board": ["GIL_833"]}, {});
    t.end_turn();
    assert_eq!(t.hand(0).len(), 1);
    assert_eq!(t.hand(1).len(), 2, "its draw and its turn's");
    t.end_turn();
    assert_eq!(t.hand(0).len(), 2, "not at the end of the opponent's turn: only the turn's draw");
    assert_eq!(t.hand(1).len(), 2);
}

#[test]
fn wispering_woods_a_wisp_per_card_in_hand() {
    let mut t = scene!({"hand": ["GIL_553", YETI, YETI, YETI]}, {});
    t.play("GIL_553", NONE);
    assert_eq!(t.cards(0), vec!["GIL_553t"; 3]);
    let mut t = scene!({"hand": ["GIL_553", YETI, YETI, YETI], "board": [WISP, WISP, WISP, WISP, WISP]}, {});
    t.play("GIL_553", NONE);
    assert_eq!(t.cards(0).len(), 7, "as many as there is room");
}

#[test]
fn bewitched_guardian_health_per_card_in_hand() {
    let mut t = scene!({"hand": ["GIL_507", YETI, YETI, YETI]}, {});
    t.play("GIL_507", NONE);
    let b = t.on_board(0, "GIL_507");
    assert_eq!(t.stats(b), (4, 4));
}

#[test]
fn duskfallen_aviana_first_card_each_turn_costs_zero() {
    let mut t = scene!({"board": ["GIL_800"], "hand": [YETI, FIREBALL]}, {"hand": [YETI]});
    assert_eq!(t.cost(YETI), 0);
    assert_eq!(t.cost(FIREBALL), 0);
    t.play(YETI, NONE);
    assert_eq!(t.cost(FIREBALL), 4, "only the first");
    t.end_turn();
    assert_eq!(t.cost(YETI), 0, "the opponent's first card too");
    let mut t = scene!({"hand": ["GIL_800", YETI]}, {});
    t.play("GIL_800", NONE);
    assert_eq!(t.cost(YETI), 4, "Aviana was the first card");
}

#[test]
fn gloom_stag_odd_deck() {
    let mut t = scene!({"hand": ["GIL_130"], "deck": ODD}, {});
    t.play("GIL_130", NONE);
    assert_eq!(t.stats(t.on_board(0, "GIL_130")), (4, 8));
    let mut t = scene!({"hand": ["GIL_130"], "deck": [RAIDER, YETI]}, {});
    t.play("GIL_130", NONE);
    assert_eq!(t.stats(t.on_board(0, "GIL_130")), (2, 6));
}

#[test]
fn splintergraft_adds_a_ten_ten_copy() {
    let mut t = scene!({"hand": ["GIL_658"], "board": [YETI]}, {});
    let y = t.on_board(0, YETI);
    t.play("GIL_658", y);
    let c = t.hand_id(YETI);
    assert_eq!(t.stats(c), (10, 10));
    assert_eq!(t.g.cost(c), 10);
}

// --- Hunter ---

#[test]
fn rat_trap_after_the_third_card() {
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_577"]}, {"hand": [WISP, WISP, FIREBALL]});
    t.play("GIL_577", NONE).end_turn();
    t.play(WISP, NONE).play(WISP, NONE);
    assert!(t.cards(0).is_empty(), "two cards: nothing");
    let foe = t.hero(0);
    t.play(FIREBALL, foe);
    assert_eq!(t.cards(0), vec!["GIL_577t"]);
    assert!(t.g.players[0].secrets.is_empty());
    assert!(t.events().iter().any(|e| e["type"] == "secret_revealed" && e["card"] == "GIL_577"));
    // a full board: it goes off all the same (2018)
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_577"], "board": [WISP, WISP, WISP, WISP, WISP, WISP, WISP]},
        {"hand": [WISP, WISP, WISP]});
    t.play("GIL_577", NONE).end_turn();
    t.play(WISP, NONE).play(WISP, NONE).play(WISP, NONE);
    assert!(t.g.players[0].secrets.is_empty(), "used up");
    // the cards played before it came count
    let mut t = scene!({"hero": "HERO_05", "secrets": ["GIL_577"]}, {"hand": [WISP]});
    t.end_turn();
    t.g.players[1].cards_played_this_turn = 2;
    t.play(WISP, NONE);
    assert_eq!(t.cards(0), vec!["GIL_577t"]);
}

#[test]
fn duskhaven_hunter_swaps_each_turn_keeping_buffs() {
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_200"]}, {});
    t.end_turn();
    assert_eq!(t.hand(0), vec!["GIL_200"], "not on the opponent's turn");
    t.end_turn();
    assert_eq!(t.hand(0)[0], "GIL_200t");
    let h = t.hand_id("GIL_200t");
    assert_eq!(t.stats(h), (5, 2));
    assert!(t.g.e(h).has("STEALTH"));
    t.end_turn().end_turn();
    assert_eq!(t.hand(0)[0], "GIL_200");
    // Emeriss's doubling stays (2018: a transform in the hand keeps enchantments)
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_128", "GIL_200"]}, {});
    t.play("GIL_128", NONE);
    assert_eq!(t.stats(t.hand_id("GIL_200")), (4, 10));
    t.end_turn().end_turn();
    let h = t.hand_id("GIL_200t");
    assert_eq!(t.stats(h), (7, 7), "5/2 with +2/+5");
}

#[test]
fn dire_frenzy_buffs_and_shuffles_three_buffed_copies() {
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_828", "GIL_828"]}, {"board": [CROC, YETI]});
    let c = t.on_board(1, CROC);
    let e = t.hand_id("GIL_828");
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == t.on_board(1, YETI)), "a Beast only");
    t.play("GIL_828", c);
    assert_eq!(t.stats(c), (5, 6));
    let copies: Vec<Id> = t.g.players[0].deck.iter().copied().filter(|&d| t.g.e(d).card_id == CROC).collect();
    assert_eq!(copies.len(), 3, "into my deck");
    for d in copies {
        assert_eq!(t.stats(d), (5, 6));
    }
}

#[test]
fn houndmaster_shaw_gives_rush() {
    let mut t = scene!({"hero": "HERO_05", "board": ["GIL_650"], "hand": [YETI]}, {"board": [WISP]});
    t.play(YETI, NONE);
    let y = t.on_board(0, YETI);
    let w = t.on_board(1, WISP);
    let can = |t: &T, d: Id| t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == y && int(a.get("defender")) == d);
    assert!(can(&t, w));
    assert!(!can(&t, t.hero(1)));
}

#[test]
fn toxmonger_poisons_one_cost_minions() {
    let mut t = scene!({"hero": "HERO_05", "board": ["GIL_607"], "hand": [RAIDER, YETI]}, {});
    t.play(RAIDER, NONE).play(YETI, NONE);
    assert!(t.g.e(t.on_board(0, RAIDER)).has("POISONOUS"));
    assert!(!t.g.e(t.on_board(0, YETI)).has("POISONOUS"));
    // a Battlecry of a 1-Cost minion is Poisonous already: Elven Archer kills the Yeti
    let mut t = scene!({"hero": "HERO_05", "board": ["GIL_607"], "hand": ["VAN_CS2_189"]}, {"board": [YETI]});
    let y = t.on_board(1, YETI);
    t.play("VAN_CS2_189", y);
    assert!(t.cards(1).is_empty());
}

#[test]
fn wing_blast_costs_one_after_a_death() {
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_518"], "board": [WISP]}, {"board": [YETI]});
    assert_eq!(t.cost("GIL_518"), 4);
    let (w, y) = (t.on_board(0, WISP), t.on_board(1, YETI));
    t.attack(w, y);
    assert_eq!(t.cost("GIL_518"), 1);
    t.play("GIL_518", y);
    assert_eq!(t.g.e(y).health(), 0);
    t.end_turn();
    let mut t2 = scene!({"hero": "HERO_05", "hand": ["GIL_518"]}, {});
    t2.end_turn().end_turn();
    assert_eq!(t2.cost("GIL_518"), 4);
}

#[test]
fn carrion_drake_poisonous_if_a_minion_died() {
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_905"]}, {});
    t.play("GIL_905", NONE);
    assert!(!t.g.e(t.on_board(0, "GIL_905")).has("POISONOUS"));
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_905"], "board": [WISP]}, {"board": [YETI]});
    let (w, y) = (t.on_board(0, WISP), t.on_board(1, YETI));
    t.attack(w, y);
    t.play("GIL_905", NONE);
    assert!(t.g.e(t.on_board(0, "GIL_905")).has("POISONOUS"));
}

#[test]
fn emeriss_doubles_the_minions_in_hand() {
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_128", YETI, FIREBALL]}, {});
    let y = t.hand_id(YETI);
    t.play("GIL_128", NONE);
    assert_eq!(t.stats(y), (8, 10), "4/5 doubled");
}

// --- Mage ---

#[test]
fn archmage_arugal_copies_drawn_minions() {
    let mut t = scene!({"board": ["GIL_691"], "deck": [FIREBALL, YETI]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.hand(0), vec![YETI, YETI]);
    t.end_turn().end_turn();
    assert_eq!(t.hand(0), vec![YETI, YETI, FIREBALL], "a spell: no copy");
}

#[test]
fn book_of_specters_discards_the_spells_drawn() {
    let mut t = scene!({"hand": ["GIL_548"], "deck": [WISP, FIREBALL, YETI, FIREBALL]}, {});
    t.play("GIL_548", NONE);
    assert_eq!(t.hand(0), vec![YETI]);
    assert_eq!(t.events().iter().filter(|e| e["type"] == "discard").count(), 2);
    assert_eq!(t.g.players[0].deck.len(), 1);
}

#[test]
fn snap_freeze_freezes_then_destroys() {
    let mut t = scene!({"hand": ["GIL_801", "GIL_801"]}, {"board": [YETI]});
    let y = t.on_board(1, YETI);
    t.play("GIL_801", y);
    assert!(t.g.e(y).has("FROZEN"));
    assert_eq!(t.cards(1), vec![YETI]);
    t.play("GIL_801", y);
    assert!(t.cards(1).is_empty());
}

#[test]
fn black_cat_draws_with_an_odd_deck() {
    let mut t = scene!({"hand": ["GIL_838"], "deck": ODD}, {});
    t.play("GIL_838", NONE);
    assert_eq!(t.hand(0), vec![RAIDER]);
    let mut t = scene!({"hand": ["GIL_838"]}, {});
    t.play("GIL_838", NONE);
    assert!(t.hand(0).is_empty(), "Wisps cost (0): even");
}

#[test]
fn cinderstorm_five_hits_plus_spell_damage() {
    let mut t = scene!({"hand": ["GIL_147"]}, {});
    t.play("GIL_147", NONE);
    assert_eq!(t.hp(1), 25);
    assert_eq!(t.hp(0), 30, "enemies only");
    let mut t = scene!({"hand": ["GIL_147"], "board": ["VAN_CS2_142"]}, {});
    t.play("GIL_147", NONE);
    assert_eq!(t.hp(1), 24, "Spell Damage +1: a sixth hit");
}

#[test]
fn arcane_keysmith_discovers_a_secret_into_play() {
    let mut t = scene!({"hand": ["GIL_116"], "secrets": ["VAN_EX1_287"]}, {});
    t.play("GIL_116", NONE);
    let opts = t.options();
    assert_eq!(opts.len(), 3);
    let rs = rs().unwrap();
    for o in &opts {
        let c = rs.card(o);
        assert!(c.trap, "{o} a Secret");
        assert_ne!(o, "VAN_EX1_287", "not one in play");
    }
    let c = t.pick_first();
    assert_eq!(t.g.players[0].secrets.len(), 2);
    assert_eq!(t.g.e(t.g.players[0].secrets[1]).card_id, c);
    assert!(t.hand(0).is_empty());
}

#[test]
fn vex_crow_summons_a_two_cost_minion_per_spell() {
    let mut t = scene!({"board": ["GIL_664"], "hand": [FIREBALL]}, {});
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    assert_eq!(t.cards(0).len(), 2);
    let m = t.nth(0, 1);
    let rs = rs().unwrap();
    assert_eq!(rs.card(&card_of(&t, m)).cost, 2);
    // before the spell resolves: Hellfire (3 to all) hits it too
    let mut t = scene!({"board": ["GIL_664"], "hand": ["VAN_CS2_062"]}, {});
    let before = t.events().len();
    t.play("VAN_CS2_062", NONE);
    let ev = t.events();
    let summon = ev[before..].iter().position(|e| e["type"] == "summon").expect("a summon");
    let hit = ev[before..].iter().position(|e| e["type"] == "damage").expect("damage");
    assert!(summon < hit);
}

#[test]
fn bonfire_elemental_draws_after_an_elemental_last_turn() {
    let mut t = scene!({"hand": ["UNG_809", "GIL_645", "GIL_645"]}, {});
    t.play("UNG_809", NONE);
    let n = t.hand(0).len();
    t.play("GIL_645", NONE);
    assert_eq!(t.hand(0).len(), n - 1, "this turn: no draw");
    t.end_turn().end_turn();
    let n = t.hand(0).len();
    t.play("GIL_645", NONE);
    assert_eq!(t.hand(0).len(), n, "played one, drew one");
}

#[test]
fn curio_collector_grows_on_each_draw() {
    let mut t = scene!({"board": ["GIL_640"], "hand": ["VAN_CS2_023"]}, {}); // Arcane Intellect
    let c = t.on_board(0, "GIL_640");
    t.play("VAN_CS2_023", NONE);
    assert_eq!(t.stats(c), (6, 6));
    t.end_turn();
    assert_eq!(t.stats(c), (6, 6), "the opponent's draw: no");
}

#[test]
fn toki_adds_a_legendary_from_the_past() {
    let rs = match rs() {
        Some(r) => r,
        None => return,
    };
    let past = ["NAXX", "GVG", "BRM", "TGT", "LOE", "OG", "KARA", "GANGS"];
    let mut t = scene!({"hand": ["GIL_549", "GIL_549", "GIL_549", "GIL_549", "GIL_549"]}, {});
    for _ in 0..5 {
        t.g.players[0].mana = 10;
        t.play("GIL_549", NONE);
    }
    let h = t.hand(0);
    assert_eq!(h.len(), 5);
    for id in &h {
        let c = rs.card(id);
        assert!(c.kind == "MINION" && c.rarity == "LEGENDARY", "{id}");
        assert!(past.contains(&c.set.as_str()) || id == "VAN_EX1_016" || id == "VAN_EX1_298", "{id} of {}", c.set);
    }
}

// --- tokens and vanilla cards ---

#[test]
fn tokens_and_keyword_cards() {
    let Some(rs) = rs() else { return };
    let st = |id: &str| (rs.card(id).cost, rs.card(id).attack, rs.card(id).health);
    assert_eq!(st("GIL_663t"), (2, 2, 2));
    assert_eq!(st("GIL_553t"), (0, 1, 1));
    assert_eq!(st("GIL_577t"), (6, 6, 6));
    assert_eq!(st("GIL_200t"), (3, 5, 2));
    assert_eq!(st("GIL_188t3"), (3, 4, 4));
    // Rush and Echo are data: Hunting Mastiff
    let mut t = scene!({"hero": "HERO_05", "hand": ["GIL_607t"]}, {"board": [WISP]});
    t.play("GIL_607t", NONE);
    assert_eq!(t.hand(0), vec!["GIL_607t"], "Echo");
    let m = t.on_board(0, "GIL_607t");
    let w = t.on_board(1, WISP);
    t.attack(m, w);
    for id in ["GIL_562", "ICC_828t4", "ICC_828t5", "ICC_828t6", "ICC_828t7"] {
        let mut t = scene!({"hero": "HERO_05", "hand": [id]}, {});
        t.play(id, NONE);
        t.on_board(0, id);
    }
}
