//! The League of Explorers pack (packs/loe, built by tools/pack.py on The Grand Tournament and the packs before it):
//! the cards as on 2015-11-12 (build 10833), Discover, Brann Bronzebeard, Reno Jackson and the engine features they
//! need (offered options only their player sees, a queue of choices, DOUBLE_ON_PLAY, a champion's spell power,
//! `g.cast`, a copied Deathrattle), the older cards of that day, and whole bot games with every deck template.
//! Needs python3 (skipped without it).

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
        let out = std::env::temp_dir().join(format!("loe-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/loe", "-o"]).arg(&out).output().ok()?;
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
}

const ELVEN_ARCHER: &str = "VAN_CS2_189"; // Battlecry: 1 damage
const LOOT_HOARDER: &str = "VAN_EX1_096"; // Deathrattle: draw a card
const PW_SHIELD: &str = "VAN_CS2_004"; // +2 Health, draw a card
const MOLTEN: &str = "VAN_EX1_620";
const KORKRON: &str = "VAN_NEW1_011"; // 4/3 Charge
const RAIDER: &str = "VAN_CS2_168"; // 2/1 Murloc
const BOLT: &str = "VAN_EX1_238"; // 3 damage, Overload (1)
const GRIZZLY: &str = "VAN_CS2_125";
const AUCHENAI: &str = "VAN_EX1_591";

impl T {
    fn options(&self) -> Vec<String> {
        self.g.pending_options().iter().map(|&o| self.g.e(o).card_id.to_string()).collect()
    }
    fn pick(&mut self, i: usize) -> &mut Self {
        let id = self.g.pending_options()[i];
        self.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == id)
    }
}

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(stats("LOE_038"), (5, 5, 5), "Naga Sea Witch 5 mana until 2018");
    assert_eq!(stats("LOE_017"), (4, 3, 4), "Keeper of Uldaman 4 mana");
    assert_eq!(stats("LOE_012"), (4, 5, 4), "Tomb Pillager 5/4");
    assert_eq!(stats("LOE_023"), (2, 2, 2), "Dark Peddler 2/2");
    assert_eq!(stats("LOE_003"), (5, 6, 3), "Ethereal Conjurer 6/3");
    assert_eq!(stats("LOE_039"), (4, 3, 4), "Gorillabot A-3 4 mana");
    assert_eq!(c("LOE_105").cost, 2, "Explorer's Hat 2 mana");
    assert_eq!(c("LOE_110t").cost, 0, "Ancient Curse 0 mana");
    assert_eq!(c("LOE_009t").race, "", "the Scarab became a Beast in 2016");
    assert_eq!(c("LOE_073").race, "", "Fossilized Devilsaur had no tribe");
    assert_eq!(c("LOE_053").race, "", "Djinni of Zephyrs: no Elemental yet");
    assert_eq!(c("LOE_051").race, "", "Jungle Moonkin: no tribe (the release data's Beast was never on the card)");
    assert_eq!(c("LOE_039").race, "MECHANICAL");
    assert_eq!(c("LOEA10_3").cost, 0, "Murloc Tinyfin");
    assert!(c("LOEA10_3").collectible);
    assert!(!c("LOE_019t2").collectible);
    let loe = rs.cards.values().filter(|c| c.set == "LOE" && c.collectible).count();
    assert_eq!(loe, 45);
}

#[test]
fn discover_offers_three_class_or_neutral_cards_only_its_player_sees() {
    let mut t = scene!({"hand": ["LOE_003"]}, {});
    t.play("LOE_003", NONE);
    let opts = t.options();
    assert_eq!(opts.len(), 3, "{opts:?}");
    let mut uniq = opts.clone();
    uniq.sort();
    uniq.dedup();
    assert_eq!(uniq.len(), 3, "three different cards");
    let rs = rs().unwrap();
    for o in &opts {
        assert_eq!(rs.card(o).kind, "SPELL");
        assert_eq!(rs.card(o).card_class, "MAGE", "no neutral spells: Mage spells only");
    }
    // only the chooser sees what is offered
    let ids = t.g.pending_options();
    let mine = classichs_engine::api::snapshot(&t.g, 0);
    let theirs = classichs_engine::api::snapshot(&t.g, 1);
    for id in &ids {
        assert_ne!(mine["entities"][id.to_string()]["card"], "");
        assert_eq!(theirs["entities"][id.to_string()]["card"], "", "the opponent never sees an option");
    }
    let n = t.g.players[0].hand.len();
    let pick = opts[1].clone();
    t.pick(1);
    assert_eq!(t.g.players[0].hand.len(), n + 1);
    assert_eq!(t.hand(0).last().unwrap(), &pick);
    assert!(t.g.pending.is_none());
    let theirs = classichs_engine::api::snapshot(&t.g, 1);
    for id in &ids {
        assert_eq!(theirs["entities"][id.to_string()]["card"], "", "not even after the choice");
    }
}

#[test]
fn discover_weights_class_cards() {
    // Jeweled Scarab as a Warlock: 3-Cost cards, Warlock or neutral; the class ones four times as likely
    let (mut class, mut all) = (0, 0);
    for seed in 0..40 {
        let Some(rs) = rs() else { return };
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_07", "mana": 10, "max_mana": 10, "deck": FILL, "hand": ["LOE_029"]},
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL}]});
        let mut t = T { g: scenario::build_in(rs, &sc).unwrap() };
        t.play("LOE_029", NONE);
        for o in t.options() {
            let c = rs.card(&o);
            assert_eq!(c.cost, 3);
            assert!(c.card_class == "WARLOCK" || c.card_class == "NEUTRAL", "{o}");
            class += (c.card_class == "WARLOCK") as usize;
            all += 1;
        }
    }
    let pool = rs().unwrap().cards.values().filter(|c| c.collectible && c.cost == 3 && c.kind != "CHAMPION");
    let (w, n): (Vec<_>, Vec<_>) = pool.filter(|c| c.card_class == "WARLOCK" || c.card_class == "NEUTRAL").partition(|c| c.card_class == "WARLOCK");
    let expect = 4.0 * w.len() as f64 / (4.0 * w.len() as f64 + n.len() as f64);
    let got = class as f64 / all as f64;
    eprintln!("Warlock options {class}/{all} = {got:.2}, expected about {expect:.2} ({} Warlock, {} neutral)", w.len(), n.len());
    assert!((got - expect).abs() < 0.15);
}

#[test]
fn brann_doubles_battlecries_and_discovers() {
    let mut t = scene!({"board": ["LOE_077"], "hand": [ELVEN_ARCHER, "LOE_023", "LOE_076"]}, {"board": [YETI]});
    let yeti = t.nth(1, 0);
    t.play(ELVEN_ARCHER, yeti);
    assert_eq!(t.stats(yeti), (4, 3), "two Battlecries of 1 damage, same target");
    t.play("LOE_023", NONE);
    assert_eq!(t.options().len(), 3);
    let n = t.g.players[0].hand.len();
    t.pick(0);
    assert_eq!(t.options().len(), 3, "the second Discover comes next");
    t.pick(2);
    assert_eq!(t.g.players[0].hand.len(), n + 2);
    assert!(t.g.pending.is_none());
    // Sir Finley twice: the power changes twice, never to the one it has
    t.play("LOE_076", NONE);
    let opts = t.options();
    assert!(!opts.contains(&"VAN_HERO_08bp".to_string()), "not your own basic power: {opts:?}");
    let first = opts[0].clone();
    t.pick(0);
    assert_eq!(t.power_card(0), first);
    t.pick(0);
    assert!(t.g.pending.is_none());
    // without Brann: once
    let mut t = scene!({"hand": [ELVEN_ARCHER]}, {"board": [YETI]});
    let yeti = t.nth(1, 0);
    t.play(ELVEN_ARCHER, yeti);
    assert_eq!(t.stats(yeti), (4, 4));
}

#[test]
fn reno_jackson_heals_with_no_duplicates() {
    let mut t = scene!({"damage": 20, "hand": ["LOE_011"], "deck": [WISP, YETI, FIREBALL]}, {});
    assert!(t.g.glows(t.hand_id("LOE_011")));
    t.play("LOE_011", NONE);
    assert_eq!(t.hp(0), 30);
    let mut t = scene!({"damage": 20, "hand": ["LOE_011"], "deck": [WISP, WISP, YETI]}, {});
    assert!(!t.g.glows(t.hand_id("LOE_011")));
    t.play("LOE_011", NONE);
    assert_eq!(t.hp(0), 10, "a duplicate: nothing");
    let mut t = scene!({"damage": 5, "hand": ["LOE_011"], "deck": [], "board": [AUCHENAI]}, {});
    t.play("LOE_011", NONE);
    assert!(t.g.game_over, "with Auchenai Soulpriest: 30 damage");
}

#[test]
fn naga_sea_witch_and_giants() {
    let t = scene!({"board": ["LOE_038"], "hand": [MOLTEN, WISP, FIREBALL, "LOE_113"]}, {});
    assert_eq!(t.cost(WISP), 5);
    assert_eq!(t.cost(FIREBALL), 5);
    assert_eq!(t.cost(MOLTEN), 5, "the Giant's own discount comes first, Naga sets 5 (until 2017)");
    assert_eq!(t.cost("LOE_113"), 5);
    let t = scene!({"board": [RAIDER, RAIDER], "hand": ["LOE_113"]}, {});
    assert_eq!(t.cost("LOE_113"), 5, "Everyfin is Awesome: (1) less per Murloc");
}

#[test]
fn jungle_moonkin_gives_both_players_spell_damage() {
    let mut t = scene!({"board": ["LOE_051"], "hand": [FIREBALL]}, {"hand": [FIREBALL]});
    t.play(FIREBALL, t.hero(1));
    assert_eq!(t.hp(1), 22);
    t.end_turn();
    let h = t.hero(0);
    t.play(FIREBALL, h);
    assert_eq!(t.hp(0), 22, "the opponent has Spell Damage +2 too");
}

#[test]
fn djinni_of_zephyrs_copies_spells_on_friends() {
    let mut t = scene!({"board": [YETI, "LOE_053"], "hand": [PW_SHIELD]}, {});
    let (yeti, djinni) = (t.nth(0, 0), t.nth(0, 1));
    let n = t.g.players[0].hand.len();
    t.play(PW_SHIELD, yeti);
    assert_eq!(t.stats(yeti), (4, 7));
    assert_eq!(t.stats(djinni), (4, 8), "the copy on the Djinni");
    assert_eq!(t.g.players[0].hand.len(), n + 1, "two draws, one card played");
    // not on itself, not on an enemy
    let mut t = scene!({"board": ["LOE_053"], "hand": [PW_SHIELD, FIREBALL]}, {"board": [YETI]});
    let djinni = t.nth(0, 0);
    t.play(PW_SHIELD, djinni);
    assert_eq!(t.stats(djinni), (4, 8));
    t.play(FIREBALL, t.nth(1, 0));
    assert_eq!(t.stats(djinni), (4, 8));
}

#[test]
fn unearthed_raptor_copies_a_deathrattle() {
    let mut t = scene!({"board": [LOOT_HOARDER, "LOE_116"], "hand": ["LOE_019"]}, {"hand": [FIREBALL]});
    let hoarder = t.nth(0, 0);
    assert!(!t.can_target("LOE_019", t.nth(0, 1)), "only a minion with a Deathrattle");
    t.play("LOE_019", hoarder);
    let raptor = t.on_board(0, "LOE_019");
    t.end_turn();
    let n = t.g.players[0].hand.len();
    t.play(FIREBALL, raptor);
    assert_eq!(t.g.players[0].hand.len(), n + 1, "the Raptor draws as Loot Hoarder");
}

#[test]
fn cursed_blade_and_animated_armor() {
    let mut t = scene!({"weapon": "LOE_118"}, {"hand": [FIREBALL, FIREBALL]});
    t.end_turn();
    let h = t.hero(0);
    t.play(FIREBALL, h);
    assert_eq!(t.hp(0), 18, "doubled");
    let mut t = scene!({"weapon": "LOE_118", "board": ["LOE_119"]}, {"hand": [FIREBALL]});
    t.end_turn();
    let h = t.hero(0);
    t.play(FIREBALL, h);
    assert_eq!(t.hp(0), 28, "Armor first (1), then the Blade (2)");
    let mut t = scene!({"board": ["LOE_119"]}, {"hand": [FIREBALL]});
    t.end_turn();
    let h = t.hero(0);
    t.play(FIREBALL, h);
    assert_eq!(t.hp(0), 29);
}

#[test]
fn warsong_commander_of_october_2015() {
    let mut t = scene!({"board": ["VAN_EX1_084"], "hand": [KORKRON, WISP]}, {});
    t.play(KORKRON, NONE).play(WISP, NONE);
    assert_eq!(t.stats(t.on_board(0, KORKRON)).0, 5, "a Charge minion +1 Attack");
    let wisp = t.on_board(0, WISP);
    assert_eq!(t.stats(wisp).0, 1);
    assert!(!t.g.e(wisp).has("CHARGE"), "no Charge for small minions any more");
}

#[test]
fn traps_with_a_full_board_or_hand_stay() {
    let full: Vec<&str> = vec![WISP; 7];
    let mut t = scene!({"board": [YETI]}, {"secrets": ["AT_060"], "board": full});
    let y = t.nth(0, 0);
    t.attack(y, t.hero(1));
    assert_eq!(t.g.players[1].secrets.len(), 1, "Bear Trap stays with a full board");
    let mut t = scene!({"board": [YETI]}, {"secrets": ["AT_060"]});
    let y = t.nth(0, 0);
    t.attack(y, t.hero(1));
    assert_eq!(t.cards(1), vec![GRIZZLY]);
    let hand: Vec<&str> = vec![WISP; 10];
    let mut t = scene!({"hand": [FIREBALL]}, {"secrets": ["FP1_018"], "board": [WISP], "hand": hand});
    let w = t.nth(1, 0);
    t.play(FIREBALL, w);
    assert_eq!(t.g.players[1].secrets.len(), 1, "Duplicate stays with a full hand");
}

#[test]
fn secrets_of_the_explorers() {
    // Sacred Trial: the fourth minion dies
    let mut t = scene!({"hand": [WISP, WISP]}, {"secrets": ["LOE_027"]});
    t.play(WISP, NONE).play(WISP, NONE);
    assert_eq!(t.cards(0).len(), 2);
    let mut t = scene!({"board": [WISP, WISP, WISP], "hand": [YETI]}, {"secrets": ["LOE_027"]});
    t.play(YETI, NONE);
    assert_eq!(t.cards(0).len(), 3, "the Yeti is destroyed");
    // Dart Trap: after the opposing Hero Power, 5 damage to a random enemy (here: the hero)
    let mut t = scene!({}, {"secrets": ["LOE_021"]});
    let h = t.hero(1);
    t.power(h);
    assert_eq!(t.hp(1), 29);
    assert_eq!(t.hp(0), 25);
}

#[test]
fn more_cards() {
    // Anyfin Can Happen: both sides' dead Murlocs
    let mut t = scene!({"board": [RAIDER], "hand": [FIREBALL, FIREBALL, "LOE_026"]}, {"board": [RAIDER]});
    let (a, b) = (t.nth(0, 0), t.nth(1, 0));
    t.play(FIREBALL, a).play(FIREBALL, b);
    t.g.players[0].mana = 10;
    t.play("LOE_026", NONE);
    assert_eq!(t.cards(0), vec![RAIDER, RAIDER]);
    // Entomb: the enemy minion into your deck, no death
    let mut t = scene!({"hand": ["LOE_104"]}, {"board": [LOOT_HOARDER]});
    let n = t.g.players[1].hand.len();
    t.play("LOE_104", t.nth(1, 0));
    assert!(t.cards(1).is_empty());
    assert!(t.deck(0).contains(&LOOT_HOARDER.to_string()));
    assert_eq!(t.g.players[1].hand.len(), n, "no Deathrattle");
    // Excavated Evil: into the opponent's deck
    let mut t = scene!({"hand": ["LOE_111"]}, {"board": [YETI]});
    t.play("LOE_111", NONE);
    assert_eq!(t.stats(t.nth(1, 0)), (4, 2));
    assert!(t.deck(1).contains(&"LOE_111".to_string()));
    // Forgotten Torch
    let mut t = scene!({"hand": ["LOE_002"]}, {});
    t.play("LOE_002", t.hero(1));
    assert_eq!(t.hp(1), 27);
    assert!(t.deck(0).contains(&"LOE_002t".to_string()));
    // Curse of Rafaam: 2 damage at the start of their turn
    let mut t = scene!({"hand": ["LOE_007"]}, {});
    t.play("LOE_007", NONE);
    assert!(t.hand(1).contains(&"LOE_007t".to_string()));
    t.end_turn();
    assert_eq!(t.hp(1), 28);
    // Ancient Curse: drawn, 7 damage, another card
    let mut t = scene!({"hand": ["LOE_110"], "deck": [WISP, WISP]}, {});
    t.play("LOE_110", NONE);
    assert!(t.deck(0).contains(&"LOE_110t".to_string()));
    let mut t = scene!({"deck": [WISP, "LOE_110t"]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.hp(0), 23);
    assert!(t.hand(0).contains(&WISP.to_string()) && !t.hand(0).contains(&"LOE_110t".to_string()));
    // Tunnel Trogg: +1 Attack per locked crystal
    let mut t = scene!({"board": ["LOE_018"], "hand": [BOLT]}, {});
    t.play(BOLT, t.hero(1));
    assert_eq!(t.stats(t.nth(0, 0)).0, 2);
    // Reliquary Seeker with six others
    let six: Vec<&str> = vec![WISP; 6];
    let mut t = scene!({"board": six, "hand": ["LOE_116"]}, {});
    assert!(t.g.glows(t.hand_id("LOE_116")));
    t.play("LOE_116", NONE);
    assert_eq!(t.stats(t.on_board(0, "LOE_116")), (5, 5));
    // Eerie Statue attacks only alone
    let t = scene!({"board": ["LOE_107"]}, {"board": [WISP]});
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack"));
    let mut t = scene!({"board": ["LOE_107"]}, {});
    let s = t.nth(0, 0);
    t.attack(s, t.hero(1));
    // Explorer's Hat comes back
    let mut t = scene!({"board": [WISP], "hand": ["LOE_105", FIREBALL]}, {});
    let w = t.nth(0, 0);
    t.play("LOE_105", w).play(FIREBALL, w);
    assert!(t.hand(0).contains(&"LOE_105".to_string()));
    // Fossilized Devilsaur with a Beast
    let mut t = scene!({"board": [GRIZZLY], "hand": ["LOE_073"]}, {});
    assert!(t.g.glows(t.hand_id("LOE_073")));
    t.play("LOE_073", NONE);
    assert!(t.g.e(t.on_board(0, "LOE_073")).has("TAUNT"));
    // Desert Camel: a 1-Cost minion of each deck
    let mut t = scene!({"hand": ["LOE_020"], "deck": [YETI, "LOE_010"]}, {"deck": [YETI, "VAN_CS2_168", YETI]});
    t.play("LOE_020", NONE);
    assert_eq!(t.cards(0), vec!["LOE_020", "LOE_010"]);
    assert_eq!(t.cards(1), vec![RAIDER]);
    // Golden Monkey: Legendary minions only
    let mut t = scene!({"hand": ["LOE_019t2", WISP, FIREBALL], "deck": [WISP, WISP, WISP]}, {});
    t.play("LOE_019t2", NONE);
    let rs = rs().unwrap();
    for c in t.hand(0).iter().chain(t.deck(0).iter()) {
        assert_eq!(rs.card(c).rarity, "LEGENDARY", "{c}");
        assert_eq!(rs.card(c).kind, "MINION");
    }
    assert_eq!((t.hand(0).len(), t.deck(0).len()), (2, 3));
    // Arch-Thief Rafaam: the three Artifacts
    let mut t = scene!({"hand": ["LOE_092"]}, {});
    t.play("LOE_092", NONE);
    assert_eq!(t.options(), vec!["LOEA16_3", "LOEA16_4", "LOEA16_5"]);
    t.choose("LOEA16_5");
    t.g.players[0].mana = 10;
    t.play("LOEA16_5", NONE);
    assert_eq!(t.cards(0).len(), 7);
    // Raven Idol: Choose One, then Discover
    let mut t = scene!({"hand": ["LOE_115"]}, {});
    t.choose_play("LOE_115", 1);
    for o in t.options() {
        assert_eq!(rs.card(&o).kind, "SPELL");
    }
    t.pick(0);
    // Summoning Stone: a minion of the Cost paid
    let mut t = scene!({"board": ["LOE_086"], "hand": [FIREBALL]}, {});
    t.play(FIREBALL, t.hero(1));
    assert_eq!(t.cards(0).len(), 2);
    assert_eq!(rs.card(&t.cards(0)[1]).cost, 4);
    // Obsidian Destroyer
    let mut t = scene!({"board": ["LOE_009"]}, {});
    t.end_turn();
    assert_eq!(t.cards(0), vec!["LOE_009", "LOE_009t"]);
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/loe/decks")).unwrap().map(|f| f.unwrap().path()).collect();
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
    let (mut discovered, mut renos, mut doubled) = (0, 0, 0);
    for (i, (c0, d0)) in decks.iter().enumerate() {
        let (c1, d1) = &decks[(i + 3) % decks.len()];
        for seed in 0..3 {
            let mut g = Game::new_in(rs, c0, d0, c1, d1, seed + 10 * i as i64, -1, true);
            let mut steps = 0;
            while !g.game_over && g.turn < 80 {
                let p = if g.phase == "MULLIGAN" {
                    (0..2).find(|&p| !g.players[p].mulliganed).unwrap()
                } else {
                    g.pending.as_ref().map_or(g.current, |c| c.player)
                };
                let brann = g.e(g.players[p].hero).aura.tags.contains_key("DOUBLE_BATTLECRY");
                let a = bot::choose(&g, p).unwrap();
                let battlecry = a["type"] == "play" && rs.card(g.e(int(a.get("entity"))).card_id).hooks.on_play.is_some();
                assert!(g.apply(&Value::Object(a)).ok);
                assert_eq!(g.script_error.get(), None, "{c0} vs {c1}");
                doubled += (brann && battlecry) as usize;
                steps += 1;
                assert!(steps < 4000);
            }
            over += g.game_over as usize;
            for h in &g.history {
                discovered += (h.action["type"] == "choose") as usize;
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    if e["type"] == "play" && card.starts_with("LOE") {
                        played.insert(card.to_string());
                    }
                    renos += (e["type"] == "heal" && e.get("by").and_then(Value::as_str) == Some("LOE_011")) as usize;
                }
            }
        }
    }
    assert!(over >= decks.len(), "most games end");
    eprintln!("LoE cards played: {}: {played:?}; choices made {discovered}, Reno heals {renos}, doubled Battlecries {doubled}", played.len());
    assert!(played.len() >= 10, "{played:?}");
    assert!(discovered > 0 && renos > 0);
}
