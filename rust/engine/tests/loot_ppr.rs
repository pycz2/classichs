//! Kobolds & Catacombs (packs/loot), the Paladin, Priest and Rogue cards of scripts/loot_ppr.lua as on 2017-12-07
//! (build 22611). Needs python3 (skipped without it).

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
        let out = std::env::temp_dir().join(format!("loot-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/loot", "-o"]).arg(&out).output().ok()?;
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


const COIN: &str = "GAME_005";
const MOONFIRE: &str = "VAN_CS2_008";
const RECRUIT: &str = "VAN_CS2_101t";
const HOARDER: &str = "VAN_EX1_096"; // Loot Hoarder: Deathrattle: draw a card
const OOZE: &str = "VAN_EX1_066"; // Acidic Swamp Ooze: destroy the enemy weapon
const DRAKE: &str = "VAN_EX1_284"; // Azure Drake, a Dragon

fn deck_len(t: &T, p: usize) -> usize {
    t.g.players[p].deck.len()
}

// --- Paladin ---

#[test]
fn potion_of_heroism_divine_shield_and_a_draw() {
    let mut t = scene!({"hand": ["LOOT_088"], "board": [YETI]}, {});
    let m = t.nth(0, 0);
    t.play("LOOT_088", m);
    assert!(t.g.e(m).tag("DIVINE_SHIELD") > 0);
    assert_eq!(t.hand(0), vec![WISP]);
}

#[test]
fn call_to_arms_recruits_three_cheap_minions() {
    let mut t = scene!({"hand": ["LOOT_093"], "deck": [YETI, WISP, "VAN_CS2_120", "VAN_EX1_012", YETI]}, {});
    t.play("LOOT_093", NONE);
    let mut b = t.cards(0);
    b.sort();
    assert_eq!(b, vec!["VAN_CS2_120", "VAN_CS2_231", "VAN_EX1_012"]);
    assert_eq!(deck_len(&t, 0), 2, "the two Yetis stay");
}

#[test]
fn lynessa_casts_the_spells_on_your_minions_in_order() {
    // Humility (Attack 1), then Blessing of Might (+3), on her own minion; a Fireball at the enemy does not count
    let mut t = scene!({"hand": ["VAN_EX1_360", "VAN_CS2_087", MOONFIRE, "LOOT_216"], "board": [YETI]}, {"board": [WISP]});
    let y = t.nth(0, 0);
    let w = t.nth(1, 0);
    t.play("VAN_EX1_360", y).play("VAN_CS2_087", y).play(MOONFIRE, w).play("LOOT_216", NONE);
    let l = t.on_board(0, "LOOT_216");
    assert_eq!(t.stats(l), (4, 1), "Humility first, then +3 (a reverse order would give 1)");
    assert_eq!(t.hp(1), 30, "no Moonfire at the enemy");
}

#[test]
fn crystal_lion_costs_less_per_silver_hand_recruit() {
    let t = scene!({"hand": ["LOOT_313"], "board": [RECRUIT, RECRUIT, WISP]}, {"board": [RECRUIT]});
    assert_eq!(t.cost("LOOT_313"), 4);
}

#[test]
fn level_up_buffs_only_silver_hand_recruits() {
    let mut t = scene!({"hand": ["LOOT_333"], "board": [RECRUIT, WISP]}, {"board": [RECRUIT]});
    t.play("LOOT_333", NONE);
    let (r, w, e) = (t.nth(0, 0), t.nth(0, 1), t.nth(1, 0));
    assert_eq!(t.stats(r), (3, 3));
    assert!(t.g.e(r).tag("TAUNT") > 0);
    assert_eq!(t.stats(w), (1, 1));
    assert_eq!(t.stats(e), (1, 1));
}

#[test]
fn drygulch_jailor_gives_three_recruits() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_363"]}, {});
    let j = t.nth(0, 0);
    t.play(FIREBALL, j);
    assert_eq!(t.hand(0), vec![RECRUIT, RECRUIT, RECRUIT]);
}

#[test]
fn benevolent_djinn_heals_at_the_end_of_your_turn() {
    let mut t = scene!({"damage": 10, "board": ["LOOT_398"]}, {"damage": 10, "board": ["LOOT_398"]});
    t.end_turn();
    assert_eq!((t.hp(0), t.hp(1)), (23, 20));
}

#[test]
fn valanyr_goes_to_a_minion_in_the_hand_and_comes_back() {
    let mut t = scene!({"hand": [OOZE, FIREBALL, OOZE]}, {"weapon": "LOOT_500", "hand": [WISP, FIREBALL], "deck": [FIREBALL, FIREBALL]});
    t.play(OOZE, NONE);
    assert_eq!(t.g.players[1].weapon, None);
    let w = t.g.players[1].hand[0];
    assert_eq!(t.stats(w), (5, 3), "+4/+2 in the hand");
    // the minion is played and dies: Val'anyr again
    t.end_turn();
    t.play(WISP, NONE);
    t.end_turn();
    let w = t.on_board(1, WISP);
    t.play(FIREBALL, w);
    let v = t.g.players[1].weapon.expect("Val'anyr re-equipped");
    assert_eq!(card_of(&t, v), "LOOT_500");
    assert_eq!(t.g.e(v).atk(), 4);
    // no minion in the hand now: it is gone for good
    t.play(OOZE, NONE);
    assert_eq!(t.g.players[1].weapon, None);
}

// --- Priest ---

#[test]
fn psychic_scream_shuffles_every_minion_into_the_opponents_deck() {
    let mut t = scene!({"hand": ["LOOT_008"], "board": [HOARDER, YETI]}, {"board": [HOARDER]});
    let y = t.on_board(0, YETI);
    t.g.em(y).damage = 2;
    let (h0, d1) = (t.hand(0).len(), deck_len(&t, 1));
    t.play("LOOT_008", NONE);
    assert!(t.cards(0).is_empty() && t.cards(1).is_empty());
    assert_eq!(deck_len(&t, 1), d1 + 3);
    assert_eq!(t.hand(0).len(), h0 - 1, "no Deathrattle: Loot Hoarders draw nothing");
    assert_eq!(t.hand(1).len(), 0);
    let fresh = t.g.players[1].deck.iter().filter(|&&e| card_of(&t, e) == YETI).count();
    assert_eq!(fresh, 1);
    assert_eq!(t.g.players[1].deck.iter().map(|&e| t.g.e(e).damage).sum::<i64>(), 0, "fresh cards");
}

#[test]
fn twilights_call_needs_a_dead_friend_and_brings_back_deathrattles() {
    let mut t = scene!({"hand": ["LOOT_187", MOONFIRE, MOONFIRE], "board": [HOARDER, WISP]}, {});
    assert!(!t.can_play("LOOT_187"));
    let (a, b) = (t.nth(0, 0), t.nth(0, 1));
    t.play(MOONFIRE, b);
    assert!(t.can_play("LOOT_187"), "a friendly minion died");
    t.play(MOONFIRE, a);
    t.play("LOOT_187", NONE);
    assert_eq!(t.cards(0), vec![HOARDER], "only the Deathrattle minion");
    assert_eq!(t.stats(t.nth(0, 0)), (1, 1));
}

#[test]
fn dragon_soul_every_third_spell_in_a_turn() {
    let mut t = scene!({"weapon": "LOOT_209", "hand": [COIN, COIN, COIN, COIN, COIN, COIN, COIN]}, {});
    t.play(COIN, NONE).play(COIN, NONE);
    assert!(t.cards(0).is_empty());
    t.play(COIN, NONE);
    assert_eq!(t.cards(0), vec!["LOOT_209t"]);
    t.play(COIN, NONE).play(COIN, NONE).play(COIN, NONE);
    assert_eq!(t.cards(0), vec!["LOOT_209t", "LOOT_209t"]);
    t.play(COIN, NONE);
    assert_eq!(t.cards(0).len(), 2);
}

#[test]
fn dragon_soul_starts_again_each_turn() {
    let mut t = scene!({"weapon": "LOOT_209", "hand": [COIN, COIN, COIN, COIN]}, {});
    t.play(COIN, NONE).play(COIN, NONE);
    t.end_turn().end_turn();
    t.play(COIN, NONE);
    assert!(t.cards(0).is_empty());
}

#[test]
fn psionic_probe_copies_a_spell_of_the_enemy_deck() {
    let mut t = scene!({"hand": ["LOOT_353"]}, {"deck": [WISP, FIREBALL, WISP]});
    t.play("LOOT_353", NONE);
    assert_eq!(t.hand(0), vec![FIREBALL]);
    assert_eq!(deck_len(&t, 1), 3, "a copy");
}

#[test]
fn duskbreaker_needs_a_dragon_in_the_hand() {
    let mut t = scene!({"hand": ["LOOT_410", "LOOT_410"], "board": [YETI]}, {"board": [YETI]});
    t.play("LOOT_410", NONE);
    assert_eq!(t.g.e(t.nth(1, 0)).health(), 2, "the other Duskbreaker is a Dragon");
    assert_eq!(t.g.e(t.nth(0, 0)).health(), 2);
    let d = t.on_board(0, "LOOT_410");
    assert_eq!(t.g.e(d).health(), 3, "not itself");
    t.play("LOOT_410", NONE);
    assert_eq!(t.g.e(t.nth(1, 0)).health(), 2, "no Dragon left in the hand");
}

#[test]
fn twilight_acolyte_swaps_attack_if_holding_a_dragon() {
    let mut t = scene!({"hand": ["LOOT_528", DRAKE]}, {"board": [YETI]});
    let y = t.nth(1, 0);
    t.play("LOOT_528", y);
    let a = t.on_board(0, "LOOT_528");
    assert_eq!(t.stats(a), (4, 4));
    assert_eq!(t.stats(y), (2, 5));
    let mut t = scene!({"hand": ["LOOT_528"]}, {"board": [YETI]});
    let y = t.nth(1, 0);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("target")) == y), "no Dragon: no target");
}

#[test]
fn gilded_gargoyle_gives_a_coin() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_534"]}, {});
    let g = t.nth(0, 0);
    t.play(FIREBALL, g);
    assert_eq!(t.hand(0), vec![COIN]);
}

fn turns(t: &mut T, n: usize) -> Vec<usize> {
    (0..n).map(|_| {
        t.end_turn();
        t.g.current
    }).collect()
}

#[test]
fn temporus_two_turns_for_the_opponent_then_two_for_you() {
    let mut t = scene!({"hand": ["LOOT_538"], "deck": FILL}, {"deck": FILL});
    t.play("LOOT_538", NONE);
    assert_eq!(turns(&mut t, 6), vec![1, 1, 0, 0, 1, 0]);
}

#[test]
fn temporus_with_brann_queues_twice() {
    // wiki: (A-)B-B-A-A-B-B-A-A-B-A
    let mut t = scene!({"hand": ["LOOT_538"], "board": ["LOE_077"], "deck": FILL}, {"deck": FILL});
    t.play("LOOT_538", NONE);
    assert_eq!(turns(&mut t, 10), vec![1, 1, 0, 0, 1, 1, 0, 0, 1, 0]);
}

#[test]
fn temporus_its_turns_stay_if_it_dies() {
    let mut t = scene!({"hand": ["LOOT_538", "VAN_EX1_622"], "deck": FILL}, {"deck": FILL});
    t.play("LOOT_538", NONE);
    let m = t.on_board(0, "LOOT_538");
    t.play("VAN_EX1_622", m); // Shadow Word: Death
    assert_eq!(t.cards(0), Vec::<String>::new());
    assert_eq!(turns(&mut t, 6), vec![1, 1, 0, 0, 1, 0]);
}

// --- Rogue ---

#[test]
fn faldorei_strider_ambushes_are_cast_when_drawn() {
    let mut t = scene!({"hand": ["LOOT_026"], "deck": []}, {});
    t.play("LOOT_026", NONE);
    assert_eq!(deck_len(&t, 0), 3);
    assert!(t.g.players[0].deck.iter().all(|&e| card_of(&t, e) == "LOOT_026e"));
    let mut t = scene!({"deck": [WISP, "LOOT_026e"]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.cards(0), vec!["LOOT_026t"]);
    assert_eq!(t.hand(0), vec![WISP], "then a card is drawn");
}

#[test]
fn cavern_shinyfinder_draws_a_weapon() {
    let mut t = scene!({"hand": ["LOOT_033"], "deck": ["VAN_CS2_106", WISP, WISP]}, {});
    t.play("LOOT_033", NONE);
    assert_eq!(t.hand(0), vec!["VAN_CS2_106"]);
}

#[test]
fn sonya_gives_a_one_one_copy_costing_one() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_165", YETI]}, {});
    let y = t.on_board(0, YETI);
    t.play(FIREBALL, y);
    assert_eq!(t.hand(0), vec![YETI]);
    let c = t.hand_id(YETI);
    assert_eq!(t.stats(c), (1, 1));
    assert_eq!(t.cost(YETI), 1);
}

#[test]
fn cheat_death_returns_the_minion_two_cheaper() {
    let mut t = scene!({"secrets": ["LOOT_204"], "board": [YETI]}, {"hand": [FIREBALL]});
    t.g.current = 1;
    let y = t.nth(0, 0);
    t.play(FIREBALL, y);
    assert!(t.g.players[0].secrets.is_empty());
    assert_eq!(t.hand(0), vec![YETI]);
    let c = t.g.players[0].hand[0];
    assert_eq!(t.g.cost(c), 2);
}

#[test]
fn sudden_betrayal_the_attacker_hits_a_neighbour() {
    let mut t = scene!({"secrets": ["LOOT_210"]}, {"board": [YETI, "VAN_CS2_120"]});
    t.end_turn();
    let (y, r) = (t.nth(1, 0), t.nth(1, 1));
    let h = t.hero(0);
    t.attack(r, h);
    assert_eq!(t.hp(0), 30);
    assert_eq!(t.g.e(y).health(), 3);
    assert!(t.g.players[0].secrets.is_empty());
}

#[test]
fn sudden_betrayal_waits_without_a_neighbour() {
    let mut t = scene!({"secrets": ["LOOT_210"]}, {"board": [YETI]});
    t.end_turn();
    let (y, h) = (t.nth(1, 0), t.hero(0));
    t.attack(y, h);
    assert_eq!(t.hp(0), 26);
    assert_eq!(t.g.players[0].secrets.len(), 1);
}

#[test]
fn elven_minstrel_combo_draws_two_minions() {
    let mut t = scene!({"hand": [COIN, "LOOT_211"], "deck": [FIREBALL, YETI, FIREBALL, "VAN_CS2_120", FIREBALL]}, {});
    t.play(COIN, NONE).play("LOOT_211", NONE);
    let mut h = t.hand(0);
    h.sort();
    assert_eq!(h, vec!["VAN_CS2_120", YETI]);
}

#[test]
fn elven_minstrel_without_combo_draws_nothing() {
    let mut t = scene!({"hand": ["LOOT_211"], "deck": [YETI, YETI]}, {});
    t.play("LOOT_211", NONE);
    assert!(t.hand(0).is_empty());
}

#[test]
fn evasion_immune_after_the_first_hit() {
    let mut t = scene!({"secrets": ["LOOT_214"]}, {"hand": [FIREBALL, FIREBALL]});
    t.end_turn();
    let h = t.hero(0);
    t.play(FIREBALL, h);
    assert_eq!(t.hp(0), 24);
    t.play(FIREBALL, h);
    assert_eq!(t.hp(0), 24, "Immune this turn");
    t.end_turn();
    assert_eq!(t.g.e(h).tag("IMMUNE"), 0, "this turn only");
}

#[test]
fn kobold_illusionist_summons_a_one_one_copy_from_the_hand() {
    let mut t = scene!({"hand": [FIREBALL, YETI], "board": ["LOOT_412"]}, {});
    let k = t.nth(0, 0);
    t.play(FIREBALL, k);
    assert_eq!(t.cards(0), vec![YETI]);
    assert_eq!(t.stats(t.nth(0, 0)), (1, 1));
    assert_eq!(t.hand(0), vec![YETI], "the card stays");
}

#[test]
fn kingsbane_returns_to_the_deck_with_its_enchantments() {
    let mut t = scene!({"weapon": {"card": "LOOT_542", "durability": 1}, "hand": ["VAN_CS2_074"], "deck": []}, {});
    t.play("VAN_CS2_074", NONE); // Deadly Poison: +2 Attack
    let h = t.hero(1);
    t.attack(t.hero(0), h);
    assert_eq!(t.hp(1), 27);
    assert_eq!(t.g.players[0].weapon, None);
    assert_eq!(deck_len(&t, 0), 1);
    let k = t.g.players[0].deck[0];
    assert_eq!(card_of(&t, k), "LOOT_542");
    t.end_turn().end_turn();
    t.act("equip Kingsbane", |a| a["type"] == "play" && int(a.get("entity")) == k);
    let w = t.g.players[0].weapon.unwrap();
    assert_eq!(t.g.e(w).atk(), 3, "Deadly Poison kept");
    assert_eq!(t.g.e(w).tag("DURABILITY"), 3, "durability back");
}
