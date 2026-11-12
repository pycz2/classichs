//! The Witchwood pack, neutral cards group n2 (packs/gil/scripts/gil_n2.lua, data/card_tests/gil_n2.json): Dollmaster
//! Dorian, Witchwood Grizzly, Clockwork Automaton, Chief Inspector, Rotten Applebaum, Muck Hunter, Mossy Horror, Worgen
//! Abomination, Azalina Soulthief, Wyrmguard, Countess Ashmore, Deranged Doctor, Cauldron Elemental, Gilnean Royal Guard,
//! Splitting Festeroot, Darkmire Moonkin, Furious Ettin, and Baku the Mooneater and Genn Greymane (Start of Game: gil.lua's
//! player hooks). Needs python3 (skipped without it).



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


fn mulligan_both(g: &mut Game) {
    for p in 0..2 {
        let a = g.legal_actions().into_iter().find(|a| a["type"] == "mulligan" && int(a.get("player")) == p as i64
            && a.get("replace").and_then(Value::as_array).is_some_and(|r| r.is_empty())).expect("keep all");
        assert!(g.apply(&Value::Object(a)).ok);
    }
}

fn start_game_as(rs: &'static Ruleset, h0: &str, d0: &[String], h1: &str, d1: &[String], seed: i64) -> Game {
    let mut g = Game::new_in(rs, h0, d0, h1, d1, seed, 0, true);
    mulligan_both(&mut g);
    assert_eq!(g.script_error.get(), None);
    g
}

fn deck(fill: &str, extra: &[&str]) -> Vec<String> {
    let mut d: Vec<String> = vec![fill.to_string(); 30 - extra.len()];
    d.extend(extra.iter().map(|s| s.to_string()));
    d
}

const RAIDER: &str = "VAN_CS2_168"; // Murloc Raider (1), odd
const ARCANE_INTELLECT: &str = "VAN_CS2_023";
const SPELLBREAKER: &str = "VAN_EX1_048";
const AZURE_DRAKE: &str = "VAN_EX1_284";
const FIRE_ELEMENTAL: &str = "VAN_CS2_042";

// --- Dollmaster Dorian ---

#[test]
fn dorian_summons_a_base_one_one_copy_of_each_drawn_minion() {
    let mut t = scene!({"board": ["GIL_620"], "hand": [ARCANE_INTELLECT, SPELLBREAKER], "deck": [YETI, FIREBALL, YETI]}, {});
    t.play(ARCANE_INTELLECT, NONE);
    assert_eq!(t.cards(0), vec!["GIL_620", YETI], "the Yeti drawn: a copy; the Fireball: none");
    let copy = t.on_board(0, YETI);
    assert_eq!(t.stats(copy), (1, 1));
    // the 1/1 is an enchantment (GIL_620e): Silence gives the Yeti back its 4/5
    t.play(SPELLBREAKER, copy);
    assert_eq!(t.stats(copy), (4, 5));
    // the turn's draw too; the opponent's draws not
    t.end_turn();
    assert_eq!(t.cards(0), vec!["GIL_620", YETI, SPELLBREAKER], "not the opponent's draw");
    t.end_turn();
    assert_eq!(t.cards(0), vec!["GIL_620", YETI, YETI, SPELLBREAKER], "the turn's draw too");
}

#[test]
fn dorian_copy_has_no_battlecry_and_needs_room() {
    // the drawn Spellbreaker's copy silences nothing (a summon)
    let mut t = scene!({"board": ["GIL_620", WISP, WISP, WISP, WISP, WISP], "hand": [ARCANE_INTELLECT], "deck": [SPELLBREAKER, YETI, SPELLBREAKER]}, {"board": ["GIL_667"]});
    t.play(ARCANE_INTELLECT, NONE);
    assert_eq!(t.g.players[0].board.len(), 7, "one copy fits, the second not");
    let c = t.g.players[0].board[1];
    assert_eq!(card_of(&t, c), SPELLBREAKER, "right of Dorian");
    assert!(!t.g.e(t.nth(1, 0)).silenced, "no Battlecry");
}

// --- Witchwood Grizzly ---

#[test]
fn grizzly_loses_health_per_card_in_the_opponents_hand() {
    let mut t = scene!({"hand": ["GIL_623"]}, {"hand": [WISP, WISP, YETI, FIREBALL]});
    t.play("GIL_623", NONE);
    let g = t.on_board(0, "GIL_623");
    assert_eq!(t.stats(g), (3, 8));
    assert_eq!(t.g.e(g).max_health(), 8, "max Health too");
    assert!(t.g.e(g).has("TAUNT"));
    let mut t = scene!({"hand": ["GIL_623"]}, {});
    t.play("GIL_623", NONE);
    assert_eq!(t.stats(t.on_board(0, "GIL_623")), (3, 12));
}

// --- Clockwork Automaton ---

#[test]
fn automaton_doubles_hero_power_damage_and_healing() {
    // Mage: Fireblast 1 -> 2 -> 4 with two; a spell not
    let mut t = scene!({"board": ["GIL_646"], "hand": [FIREBALL]}, {});
    let foe = t.hero(1);
    t.power_on(foe);
    assert_eq!(t.hp(1), 30 - 2);
    t.play(FIREBALL, foe);
    assert_eq!(t.hp(1), 30 - 2 - 6, "spells not doubled");
    let mut t = scene!({"board": ["GIL_646", "GIL_646"]}, {});
    let foe = t.hero(1);
    t.power_on(foe);
    assert_eq!(t.hp(1), 30 - 4, "two: x4");
    // the enemy's Automaton does nothing for me
    let mut t = scene!({}, {"board": ["GIL_646"]});
    let foe = t.hero(1);
    t.power_on(foe);
    assert_eq!(t.hp(1), 29);
    // Priest: Lesser Heal 2 -> 4
    let mut t = scene!({"hero": "HERO_09", "damage": 10, "board": ["GIL_646"]}, {});
    let me = t.hero(0);
    t.power_on(me);
    assert_eq!(t.hp(0), 30 - 10 + 4);
    // Warlock: Life Tap's own damage 2 -> 4 (DOUBT: it is Hero Power damage)
    let mut t = scene!({"hero": "HERO_07", "board": ["GIL_646"]}, {});
    t.act("life tap", |a| a["type"] == "hero_power");
    assert_eq!(t.hp(0), 30 - 4);
}

// --- Chief Inspector ---

#[test]
fn chief_inspector_destroys_the_enemy_secrets_only() {
    let mut t = scene!({"hand": ["GIL_648"], "secrets": ["VAN_EX1_609"]}, {"hero": "HERO_04", "secrets": ["VAN_EX1_130", "VAN_EX1_554"]});
    t.play("GIL_648", NONE);
    assert!(t.g.players[1].secrets.is_empty());
    assert_eq!(t.g.players[0].secrets.len(), 1, "mine stay");
    assert!(!t.events().iter().any(|e| e["type"] == "secret_revealed"), "none triggers");
}

// --- Rotten Applebaum, Deranged Doctor ---

#[test]
fn applebaum_and_doctor_restore_their_heros_health() {
    let mut t = scene!({"damage": 20, "mana": 20, "board": ["GIL_667", "GIL_118"], "hand": [FIREBALL, FIREBALL, FIREBALL]}, {});
    assert!(t.g.e(t.on_board(0, "GIL_667")).has("TAUNT"));
    assert_eq!(t.stats(t.on_board(0, "GIL_667")), (4, 5), "4/5 at the release");
    let a = t.on_board(0, "GIL_667");
    t.play(FIREBALL, a);
    assert_eq!(t.hp(0), 10 + 4);
    let d = t.on_board(0, "GIL_118");
    t.play(FIREBALL, d).play(FIREBALL, d);
    assert_eq!(t.hp(0), 14 + 8);
}

// --- Muck Hunter ---

#[test]
fn muck_hunter_gives_two_mucklings_and_has_rush() {
    let mut t = scene!({"hand": ["GIL_682"]}, {"board": [YETI]});
    t.play("GIL_682", NONE);
    assert_eq!(t.cards(1), vec![YETI, "GIL_682t", "GIL_682t"]);
    assert_eq!(t.stats(t.nth(1, 1)), (2, 1));
    let h = t.on_board(0, "GIL_682");
    let y = t.nth(1, 0);
    t.attack(h, y);
    // a full board but one slot: one Muckling
    let mut t = scene!({"hand": ["GIL_682"]}, {"board": [WISP, WISP, WISP, WISP, WISP, WISP]});
    t.play("GIL_682", NONE);
    assert_eq!(t.g.players[1].board.len(), 7);
}

// --- Mossy Horror ---

#[test]
fn mossy_horror_destroys_the_other_minions_with_two_attack_or_less() {
    let mut t = scene!({"hand": ["GIL_124"], "board": [WISP, YETI]}, {"board": [RAIDER, YETI, "GIL_646"]});
    t.play("GIL_124", NONE);
    assert_eq!(t.cards(0), vec![YETI, "GIL_124"]);
    assert_eq!(t.cards(1), vec![YETI, "GIL_646"]);
}

// --- Worgen Abomination ---

#[test]
fn worgen_abomination_hits_the_other_damaged_minions_at_the_end_of_my_turn() {
    let mut t = scene!({"board": [{"card": "GIL_117", "damage": 1}, {"card": YETI, "damage": 1}, YETI]},
                       {"board": [{"card": YETI, "damage": 3}, WISP]});
    t.end_turn();
    let mine: Vec<(i64, i64)> = t.g.players[0].board.iter().map(|&m| t.stats(m)).collect();
    assert_eq!(mine, vec![(6, 5), (4, 2), (4, 5)], "itself and the undamaged not");
    assert_eq!(t.cards(1), vec![WISP], "the damaged Yeti died (2 Health left)");
    // not at the end of the enemy's turn
    let y = t.nth(0, 1);
    t.end_turn();
    assert_eq!(t.stats(y), (4, 2));
}

// --- Azalina Soulthief ---

#[test]
fn azalina_replaces_my_hand_with_base_copies_of_theirs() {
    let mut t = scene!({"hand": [FIREBALL, "GIL_198", WISP]}, {"hand": ["GIL_202", "VAN_CS2_024", YETI]});
    t.play("GIL_198", NONE);
    assert_eq!(t.hand(0), vec!["GIL_202", "VAN_CS2_024", YETI]);
    assert_eq!(t.hand(1), vec!["GIL_202", "VAN_CS2_024", YETI], "theirs stay");
    assert!(!t.events().iter().any(|e| e["type"] == "discard"), "not a discard");
    // base copies: no cost change the original had (Emperor Thaurissan's -1 on the enemy's hand)
    let mut t = scene!({"hand": ["GIL_198"]}, {"hand": [YETI], "board": ["BRM_028"]});
    t.end_turn().end_turn();
    let y = t.g.players[1].hand[0];
    assert_eq!(t.g.cost(y), 3, "Thaurissan at the end of their turn");
    t.play("GIL_198", NONE);
    assert_eq!(t.cost(YETI), 4, "a base copy");
}

// --- Wyrmguard ---

#[test]
fn wyrmguard_gains_attack_and_taunt_when_holding_a_dragon() {
    let mut t = scene!({"hand": ["GIL_526", AZURE_DRAKE]}, {});
    assert!(t.g.glows(t.hand_id("GIL_526")));
    t.play("GIL_526", NONE);
    let w = t.on_board(0, "GIL_526");
    assert_eq!(t.stats(w), (4, 11));
    assert!(t.g.e(w).has("TAUNT"));
    let t = scene!({"hand": ["GIL_526", "GIL_681"]}, {});
    assert!(t.g.glows(t.hand_id("GIL_526")), "Nightmare Amalgam is a Dragon");
    let mut t = scene!({"hand": ["GIL_526", YETI]}, {});
    assert!(!t.g.glows(t.hand_id("GIL_526")));
    t.play("GIL_526", NONE);
    let w = t.on_board(0, "GIL_526");
    assert_eq!(t.stats(w), (3, 11));
    assert!(!t.g.e(w).has("TAUNT"));
}

// --- Countess Ashmore ---

#[test]
fn countess_draws_a_rush_a_lifesteal_and_a_deathrattle_card() {
    let mut t = scene!({"hand": ["GIL_578"], "deck": [YETI, "VAN_EX1_096", YETI, "GIL_558", "GIL_113", YETI]}, {});
    t.play("GIL_578", NONE);
    assert_eq!(t.hand(0), vec!["GIL_113", "GIL_558", "VAN_EX1_096"], "in that order");
    assert_eq!(t.g.players[0].deck.len(), 3);
    // a card of two kinds taken by the first step leaves the second empty (the 2018 ordered draw)
    let mut t = scene!({"hand": ["GIL_578"], "deck": [YETI, "GIL_143", YETI]}, {});
    t.play("GIL_578", NONE);
    assert_eq!(t.hand(0), vec!["GIL_143"]);
    // none: nothing
    let mut t = scene!({"hand": ["GIL_578"], "deck": [YETI, YETI]}, {});
    t.play("GIL_578", NONE);
    assert!(t.hand(0).is_empty());
}

// --- Cauldron Elemental ---

#[test]
fn cauldron_elemental_gives_the_other_elementals_two_attack() {
    let t = scene!({"board": ["GIL_119", FIRE_ELEMENTAL, YETI, "GIL_681"]}, {"board": [FIRE_ELEMENTAL]});
    assert_eq!(t.stats(t.nth(0, 0)), (7, 7));
    assert_eq!(t.stats(t.nth(0, 1)), (8, 5));
    assert_eq!(t.stats(t.nth(0, 2)), (4, 5));
    assert_eq!(t.stats(t.nth(0, 3)), (5, 4), "Nightmare Amalgam is an Elemental");
    assert_eq!(t.stats(t.nth(1, 0)), (6, 5), "not the enemy's");
}

// --- Gilnean Royal Guard ---

#[test]
fn royal_guard_swaps_each_of_my_turns_in_the_hand_keeping_buffs() {
    let mut t = scene!({"hand": ["GIL_202", "CFM_753"]}, {});
    t.play("CFM_753", NONE); // Grimestreet Outfitter: +1/+1 to the minions in my hand
    let e = t.hand_id("GIL_202");
    assert_eq!(t.stats(e), (4, 9));
    t.end_turn();
    assert_eq!(t.hand(0), vec!["GIL_202"], "not on the enemy's turn");
    t.end_turn();
    assert_eq!(t.hand(0)[0], "GIL_202t");
    let e = t.g.players[0].hand[0];
    assert_eq!(t.stats(e), (9, 4), "8/3 and the +1/+1 kept (2018)");
    t.end_turn().end_turn();
    let e = t.g.players[0].hand[0];
    assert_eq!(card_of(&t, e), "GIL_202");
    assert_eq!(t.stats(e), (4, 9));
    t.play("GIL_202", NONE);
    let m = t.on_board(0, "GIL_202");
    assert!(t.g.e(m).has("DIVINE_SHIELD"));
}

#[test]
fn royal_guard_drawn_at_the_turn_start_keeps_its_form_that_turn() {
    let mut t = scene!({}, {"deck": [WISP, "GIL_202"]});
    t.end_turn();
    assert_eq!(t.hand(1), vec!["GIL_202"]);
    t.end_turn().end_turn();
    assert_eq!(t.hand(1)[0], "GIL_202t");
}

// --- Splitting Festeroot ---

#[test]
fn festeroot_splits_into_saplings_and_woodchips() {
    let mut t = scene!({"board": [WISP, "GIL_616", YETI], "hand": [FIREBALL, FIREBALL]}, {});
    let f = t.on_board(0, "GIL_616");
    t.play(FIREBALL, f);
    assert_eq!(t.cards(0), vec![WISP, "GIL_616t", "GIL_616t", YETI]);
    let s = t.nth(0, 1);
    assert_eq!(t.stats(s), (2, 2));
    t.play(FIREBALL, s);
    assert_eq!(t.cards(0), vec![WISP, "GIL_616t2", "GIL_616t2", "GIL_616t", YETI]);
    assert_eq!(t.stats(t.nth(0, 1)), (1, 1));
}

// --- Darkmire Moonkin, Furious Ettin ---

#[test]
fn moonkin_has_spell_damage_two_and_ettin_taunt() {
    let mut t = scene!({"board": ["GIL_121", "GIL_120"], "hand": [FIREBALL]}, {});
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    assert_eq!(t.hp(1), 30 - 8, "Spell Damage +2 (the release value)");
    let e = t.on_board(0, "GIL_120");
    assert_eq!(t.stats(e), (5, 9));
    assert!(t.g.e(e).has("TAUNT"));
}

// --- Baku the Mooneater, Genn Greymane (Start of Game, gil.lua's player hooks) ---

const HEROES: [(&str, &str); 9] = [
    ("HERO_01", "AT_132_WARRIOR"), ("HERO_02", "AT_132_SHAMAN"), ("HERO_03", "AT_132_ROGUE"),
    ("HERO_04", "AT_132_PALADIN"), ("HERO_05", "AT_132_HUNTER"), ("HERO_06", "AT_132_DRUID"),
    ("HERO_07", "AT_132_WARLOCK"), ("HERO_08", "AT_132_MAGE"), ("HERO_09", "AT_132_PRIEST"),
];

#[test]
fn baku_upgrades_every_class_hero_power_for_both_players() {
    let Some(rs) = rs() else { return };
    let odd = deck(RAIDER, &["GIL_826"]);
    for (i, (hero, up)) in HEROES.iter().enumerate() {
        let (other, other_up) = HEROES[(i + 1) % 9];
        let g = start_game_as(rs, hero, &odd, other, &odd, 3 + i as i64);
        assert_eq!(g.e(g.players[0].hero_power).card_id, *up, "{hero}");
        assert_eq!(g.e(g.players[1].hero_power).card_id, other_up, "{other}, the second player");
    }
}

#[test]
fn baku_checks_before_malchezaars_legendaries_come() {
    let Some(rs) = rs() else { return };
    let odd = deck(RAIDER, &["GIL_826", "KAR_096"]);
    let plain = deck(YETI, &[]);
    let mut even_added = false;
    for seed in 1..8 {
        let g = start_game_as(rs, "HERO_08", &odd, "HERO_01", &plain, seed);
        assert_eq!(g.e(g.players[0].hero_power).card_id, "AT_132_MAGE", "seed {seed}");
        let added: Vec<String> = g.history.iter().flat_map(|h| h.events()).filter(|e| e["type"] == "add_to_deck" && int(e.get("player")) == 0)
            .map(|e| e["card"].as_str().unwrap_or("").to_string()).collect();
        assert_eq!(added.len(), 5, "five Legendaries");
        even_added |= added.iter().any(|c| rs.card(c).cost % 2 == 0);
    }
    assert!(even_added, "some even Legendaries came, and Baku still upgraded");
}

#[test]
fn baku_needs_the_whole_starting_deck_odd() {
    let Some(rs) = rs() else { return };
    // an even card (the Yeti, 4) anywhere, the opening hand too: nothing
    for seed in 1..5 {
        let g = start_game_as(rs, "HERO_08", &deck(RAIDER, &["GIL_826", YETI]), "HERO_01", &deck(YETI, &[]), seed);
        assert_eq!(g.e(g.players[0].hero_power).card_id, "VAN_HERO_08bp");
    }
    // a 0-Cost card is even
    let g = start_game_as(rs, "HERO_08", &deck(RAIDER, &["GIL_826", WISP]), "HERO_01", &deck(YETI, &[]), 1);
    assert_eq!(g.e(g.players[0].hero_power).card_id, "VAN_HERO_08bp");
}

#[test]
fn genn_reads_printed_costs_and_only_the_starting_power() {
    let Some(rs) = rs() else { return };
    // Clockwork Giant (12; cheaper in the hand) does not stop him (the patch 11.4 fix, printed Cost)
    let even = deck(YETI, &["GIL_692", "GVG_121", "GVG_121", "GVG_121", "GVG_121"]);
    for seed in 1..4 {
        let g = start_game_as(rs, "HERO_08", &even, "HERO_01", &even, seed);
        assert_eq!(g.cost(g.players[0].hero_power), 1, "seed {seed}");
        assert_eq!(g.cost(g.players[1].hero_power), 1, "both players");
    }
    // an odd card: (2)
    let g = start_game_as(rs, "HERO_08", &deck(YETI, &["GIL_692", RAIDER]), "HERO_01", &even, 1);
    assert_eq!(g.cost(g.players[0].hero_power), 2);
    // Justicar Trueheart's new power is not cheaper
    let g = start_game_as(rs, "HERO_08", &deck("AT_132", &["GIL_692"]), "HERO_01", &even, 1);
    let mut t = T { g };
    t.g.players[0].mana = 10;
    t.g.players[0].max_mana = 10;
    t.play("AT_132", NONE);
    assert_eq!(t.power(0), "AT_132_MAGE");
    assert_eq!(t.g.cost(t.g.players[0].hero_power), 2);
}
