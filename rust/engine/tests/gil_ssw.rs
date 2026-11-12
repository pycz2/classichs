//! The Witchwood pack: the Shaman, Warlock and Warrior cards (packs/gil/scripts/gil_ssw.lua) as on 2018-04-12 (build
//! 23966). Needs python3 (skipped without it).
#![allow(unused_imports, dead_code)]

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


const ARCHER: &str = "VAN_CS2_189"; // Elven Archer: Battlecry 1 damage
const CROC: &str = "VAN_CS2_120"; // 2/3
const OGRE: &str = "VAN_CS2_200"; // 6/7
const RAIDER: &str = "VAN_CS2_168"; // 1 Cost
const AXE: &str = "VAN_CS2_106"; // Fiery War Axe 3/2
const FIRE_FLY: &str = "UNG_809"; // an Elemental

fn info(_t: &T, card: &str) -> &'static ruleset::Card {
    rs().unwrap().card(card)
}

fn is_shaman_spell(t: &T, card: &str) -> bool {
    let c = info(t, card);
    c.kind == "SPELL" && c.card_class == "SHAMAN"
}

fn battlecry_events(t: &T, src: Id) -> Vec<String> {
    t.events().iter().filter(|e| e["type"] == "battlecry" && int(e.get("entity")) == src)
        .map(|e| e["card"].as_str().unwrap_or("").to_string()).collect()
}

// --- Shaman ------------------------------------------------------------------------------------------------------

#[test]
fn zap_deals_two_to_a_minion_and_overloads() {
    let mut t = scene!({"hand": ["GIL_600"]}, {"board": [YETI]});
    let y = t.on_board(1, YETI);
    t.play("GIL_600", y);
    assert_eq!(t.stats(y), (4, 3));
    t.end_turn().end_turn();
    assert_eq!(t.g.players[0].mana, 9, "Overload (1)");
}

#[test]
fn blazing_invocation_discovers_a_battlecry_minion() {
    let mut t = scene!({"hand": ["GIL_836"]}, {});
    t.play("GIL_836", NONE);
    let opts = t.options();
    assert_eq!(opts.len(), 3);
    for o in &opts {
        let c = info(&t, o);
        assert!(c.kind == "MINION" && c.keywords.iter().any(|k| k == "BATTLECRY"), "{o}");
    }
    let c = t.pick_first();
    assert_eq!(t.hand(0), vec![c]);
}

#[test]
fn witchs_apprentice_adds_a_shaman_spell() {
    let mut t = scene!({"hand": ["GIL_531"]}, {});
    t.play("GIL_531", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 1);
    assert!(is_shaman_spell(&t, &h[0]), "{}", h[0]);
}

#[test]
fn earthen_might_buffs_and_an_elemental_gives_an_elemental() {
    let mut t = scene!({"hand": ["GIL_586", "GIL_586"], "board": [YETI, FIRE_FLY]}, {});
    let (y, f) = (t.on_board(0, YETI), t.on_board(0, FIRE_FLY));
    t.play("GIL_586", y);
    assert_eq!(t.stats(y), (6, 7));
    assert_eq!(t.hand(0), vec!["GIL_586"], "no Elemental for a Yeti");
    t.play("GIL_586", f);
    assert_eq!(t.stats(f), (3, 4));
    let h = t.hand(0);
    assert_eq!(h.len(), 1);
    assert_eq!(info(&t, &h[0]).race, "ELEMENTAL");
}

#[test]
fn ghost_light_angler_has_echo() {
    let mut t = scene!({"hand": ["GIL_678"]}, {});
    t.play("GIL_678", NONE);
    assert_eq!(t.hand(0), vec!["GIL_678"]);
}

#[test]
fn murkspark_eel_needs_an_even_deck() {
    // FILL: Wisps (0): even
    let mut t = scene!({"hand": ["GIL_530"]}, {});
    let foe = t.hero(1);
    t.play("GIL_530", foe);
    assert_eq!(t.hp(1), 28);
    let mut t = scene!({"hand": ["GIL_530"], "deck": [WISP, RAIDER, WISP]}, {});
    let foe = t.hero(1);
    let e = t.hand_id("GIL_530");
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == foe));
    t.play("GIL_530", NONE);
    assert_eq!(t.hp(1), 30);
}

#[test]
fn totem_cruncher_eats_your_totems() {
    let mut t = scene!({"hand": ["GIL_583"], "board": ["VAN_CS2_050", WISP, "VAN_CS2_051"]}, {"board": ["VAN_CS2_050"]});
    t.play("GIL_583", NONE);
    assert_eq!(t.cards(0), vec![WISP, "GIL_583"]);
    assert_eq!(t.cards(1), vec!["VAN_CS2_050"], "not the enemy's");
    let c = t.on_board(0, "GIL_583");
    assert_eq!(t.stats(c), (2 + 4, 3 + 4));
}

#[test]
fn bogshaper_draws_a_minion_when_you_cast_a_spell() {
    let mut t = scene!({"hand": ["GIL_600"], "board": ["GIL_807"], "deck": [FIREBALL, YETI, FIREBALL]}, {"board": [WISP]});
    let w = t.on_board(1, WISP);
    t.play("GIL_600", w);
    assert_eq!(t.hand(0), vec![YETI]);
    assert_eq!(t.g.players[0].deck.len(), 2);
}

#[test]
fn hagatha_hits_all_minions_and_bewitch_gives_shaman_spells() {
    let mut t = scene!({"hand": ["GIL_504", WISP], "board": [YETI]}, {"board": [YETI]});
    t.play("GIL_504", NONE);
    assert_eq!(t.armor(0), 5);
    assert_eq!(t.power(0), "GIL_504h");
    assert_eq!(t.stats(t.nth(0, 0)), (4, 2));
    assert_eq!(t.stats(t.nth(1, 0)), (4, 2));
    assert!(!t.can_power(), "a passive Hero Power");
    t.play(WISP, NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 1);
    assert!(is_shaman_spell(&t, &h[0]), "{}", h[0]);
}

#[test]
fn bewitch_only_after_your_own_played_minions() {
    let mut t = scene!({"hand": ["GIL_504", "GIL_191"]}, {"hand": [WISP]});
    t.play("GIL_504", NONE);
    t.end_turn();
    t.play(WISP, NONE);
    t.end_turn();
    let before = t.hand(0).len();
    t.play("GIL_191", NONE);
    assert_eq!(t.hand(0).len(), before - 1, "summoned Imps are not played");
}

#[test]
fn shudderwock_repeats_the_battlecries_you_played() {
    let mut t = scene!({"hand": [ARCHER, "GIL_531", "GIL_820"], "max_mana": 10}, {});
    let foe = t.hero(1);
    t.play(ARCHER, foe);
    t.play("GIL_531", NONE);
    let n = t.hand(0).len();
    t.end_turn().end_turn();
    t.play("GIL_820", NONE);
    let s = t.on_board(0, "GIL_820");
    let mut b = battlecry_events(&t, s);
    b.sort();
    assert_eq!(b, vec!["GIL_531".to_string(), ARCHER.to_string()]);
    // the Archer's 1 damage went to a random character other than Shudderwock; the Apprentice's spell came
    assert_eq!(t.hand(0).len(), n - 1 + 1 + 1, "+1 drawn, +1 Shaman spell");
    assert_eq!(t.stats(s), (6, 6), "never itself");
}

#[test]
fn shudderwock_stops_when_it_dies() {
    // two Hagatha Battlecries (3 damage to all minions each) kill it: nothing after the second
    let mut t = scene!({"hand": ["GIL_504", "GIL_504", ARCHER, "GIL_820"]}, {});
    let foe = t.hero(1);
    t.play(ARCHER, foe);
    t.play("GIL_504", NONE);
    t.end_turn().end_turn();
    t.play("GIL_504", NONE);
    t.end_turn().end_turn();
    t.play("GIL_820", NONE);
    let src = t.events().iter().filter(|e| e["type"] == "battlecry").map(|e| int(e.get("entity"))).last().unwrap();
    let b = battlecry_events(&t, src);
    assert_eq!(b.iter().filter(|c| *c == "GIL_504").count(), 2);
    assert_eq!(b.last().unwrap(), "GIL_504", "it died with the second: {b:?}");
    assert!(!t.cards(0).contains(&"GIL_820".to_string()));
}

// --- Warlock -----------------------------------------------------------------------------------------------------

#[test]
fn dark_possession_hits_a_friend_and_discovers_a_demon() {
    let mut t = scene!({"hand": ["GIL_543"]}, {});
    let me = t.hero(0);
    t.play("GIL_543", me);
    assert_eq!(t.hp(0), 28);
    for o in t.options() {
        assert_eq!(info(&t, &o).race, "DEMON", "{o}");
    }
    let c = t.pick_first();
    assert_eq!(t.hand(0), vec![c]);
    // an enemy can't be the target
    let t = scene!({"hand": ["GIL_543"]}, {});
    let e = t.hand_id("GIL_543");
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == t.hero(1)));
}

#[test]
fn witchwood_imp_gives_two_health_when_it_dies() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["GIL_608", YETI]}, {});
    let imp = t.on_board(0, "GIL_608");
    t.play(FIREBALL, imp);
    assert_eq!(t.cards(0), vec![YETI]);
    assert_eq!(t.stats(t.nth(0, 0)), (4, 7));
}

#[test]
fn curse_of_weakness_lasts_until_your_next_turn() {
    let mut t = scene!({"hand": ["GIL_665"]}, {"board": [YETI, OGRE]});
    t.play("GIL_665", NONE);
    let (y, o) = (t.nth(1, 0), t.nth(1, 1));
    assert_eq!((t.stats(y).0, t.stats(o).0), (2, 4));
    assert_eq!(t.hand(0), vec!["GIL_665"], "Echo");
    t.play("GIL_665", NONE);
    assert_eq!(t.stats(y).0, 0, "twice");
    t.end_turn();
    assert_eq!(t.stats(y).0, 0, "on the enemy's turn too");
    t.end_turn();
    assert_eq!((t.stats(y).0, t.stats(o).0), (4, 6), "gone at the start of your turn");
}

#[test]
fn duskbat_summons_bats_if_your_hero_took_damage() {
    let mut t = scene!({"hand": ["GIL_508"]}, {});
    t.play("GIL_508", NONE);
    assert_eq!(t.cards(0), vec!["GIL_508"]);
    let mut t = scene!({"hand": [FIREBALL, "GIL_508"]}, {});
    let me = t.hero(0);
    t.play(FIREBALL, me);
    t.play("GIL_508", NONE);
    assert_eq!(t.cards(0), vec!["GIL_508", "GIL_508t", "GIL_508t"]);
    // Armor that took it all: no damage
    let mut t = scene!({"hand": [FIREBALL, "GIL_508"], "armor": 10}, {});
    let me = t.hero(0);
    t.play(FIREBALL, me);
    t.play("GIL_508", NONE);
    assert_eq!(t.cards(0), vec!["GIL_508"]);
}

#[test]
fn duskbat_needs_damage_this_turn() {
    let mut t = scene!({"hand": [FIREBALL, "GIL_508"]}, {});
    let me = t.hero(0);
    t.play(FIREBALL, me);
    t.end_turn().end_turn();
    t.play("GIL_508", NONE);
    assert_eq!(t.cards(0), vec!["GIL_508"]);
}

#[test]
fn ratcatcher_eats_a_friendly_minion() {
    let mut t = scene!({"hand": ["GIL_515"], "board": [{"card": YETI, "damage": 1}]}, {});
    let y = t.nth(0, 0);
    t.play("GIL_515", y);
    assert_eq!(t.cards(0), vec!["GIL_515"]);
    assert_eq!(t.stats(t.nth(0, 0)), (2 + 4, 2 + 4));
}

#[test]
fn blood_witch_hurts_your_hero_each_turn() {
    let mut t = scene!({"board": ["GIL_693"]}, {});
    t.end_turn();
    assert_eq!(t.hp(0), 30, "not on the enemy's turn");
    t.end_turn();
    assert_eq!(t.hp(0), 29);
}

#[test]
fn fiendish_circle_summons_four_imps() {
    let mut t = scene!({"hand": ["GIL_191"], "board": [YETI, YETI, YETI, YETI]}, {});
    t.play("GIL_191", NONE);
    assert_eq!(t.cards(0).iter().filter(|c| *c == "GIL_191t").count(), 3, "board full at 7");
    let mut t = scene!({"hand": ["GIL_191"]}, {});
    t.play("GIL_191", NONE);
    assert_eq!(t.cards(0), vec!["GIL_191t"; 4]);
    assert_eq!(t.stats(t.nth(0, 0)), (1, 1));
}

#[test]
fn deathweb_spider_gets_lifesteal_if_your_hero_took_damage() {
    let mut t = scene!({"hand": ["GIL_565"]}, {});
    t.play("GIL_565", NONE);
    assert!(!t.g.e(t.nth(0, 0)).has("LIFESTEAL"));
    let mut t = scene!({"hand": [FIREBALL, "GIL_565"]}, {});
    let me = t.hero(0);
    t.play(FIREBALL, me);
    t.play("GIL_565", NONE);
    assert!(t.g.e(t.nth(0, 0)).has("LIFESTEAL"));
}

#[test]
fn glinda_gives_echo_to_minions_in_your_hand() {
    let mut t = scene!({"hand": [YETI, FIREBALL], "board": ["GIL_618"]}, {});
    let y = t.hand_id(YETI);
    assert!(t.g.e(y).has("ECHO") || t.g.e(y).has("REPEATABLE"), "the aura shows it");
    t.play(YETI, NONE);
    assert_eq!(t.hand(0), vec![FIREBALL, YETI], "an Echo copy");
    t.play(FIREBALL, t.hero(1));
    assert_eq!(t.hand(0), vec![YETI], "a spell: no copy");
    t.end_turn();
    assert!(t.hand(0).is_empty(), "the copy goes");
}

#[test]
fn lord_godfrey_repeats_while_minions_die() {
    let mut t = scene!({"hand": ["GIL_825"], "board": [YETI]}, {"board": [WISP, CROC, OGRE]});
    t.play("GIL_825", NONE);
    // round 1: Wisp dies; 2: Crocolisk; 3: Yeti; 4: Ogre (7 Health); 5: none left
    assert!(t.cards(1).is_empty());
    assert_eq!(t.cards(0), vec!["GIL_825"]);
    assert_eq!(t.stats(t.nth(0, 0)), (4, 4), "not himself");
    let mut t = scene!({"hand": ["GIL_825"]}, {"board": [YETI]});
    t.play("GIL_825", NONE);
    assert_eq!(t.stats(t.nth(1, 0)), (4, 3), "nothing died: once");
}

// --- Warrior -----------------------------------------------------------------------------------------------------

#[test]
fn town_crier_draws_a_rush_minion() {
    let mut t = scene!({"hand": ["GIL_580"], "deck": [YETI, "GIL_113", WISP]}, {});
    t.play("GIL_580", NONE);
    assert_eq!(t.hand(0), vec!["GIL_113"]);
    let mut t = scene!({"hand": ["GIL_580"], "deck": [YETI, WISP]}, {});
    t.play("GIL_580", NONE);
    assert!(t.hand(0).is_empty());
}

#[test]
fn redband_wasp_has_three_more_attack_while_damaged() {
    let mut t = scene!({"hand": ["GIL_600"], "board": ["GIL_155"]}, {});
    let w = t.nth(0, 0);
    assert_eq!(t.stats(w), (1, 3));
    t.play("GIL_600", w);
    assert_eq!(t.stats(w), (4, 1));
}

#[test]
fn warpath_hits_all_minions_with_echo() {
    let mut t = scene!({"hand": ["GIL_654"], "board": [WISP]}, {"board": [WISP, YETI]});
    t.play("GIL_654", NONE);
    assert!(t.cards(0).is_empty());
    assert_eq!(t.cards(1), vec![YETI]);
    assert_eq!(t.stats(t.nth(1, 0)), (4, 4));
    assert_eq!(t.hand(0), vec!["GIL_654"]);
}

#[test]
fn woodcutters_axe_buffs_a_rush_minion_when_it_breaks() {
    let mut t = scene!({"weapon": "GIL_653", "board": [YETI, "GIL_113"]}, {});
    let (h, foe) = (t.hero(0), t.hero(1));
    t.attack(h, foe).end_turn().end_turn();
    let foe = t.hero(1);
    t.attack(h, foe);
    assert!(t.g.players[0].weapon.is_none());
    let (y, w) = (t.on_board(0, YETI), t.on_board(0, "GIL_113"));
    assert_eq!(t.stats(y), (4, 5));
    assert_eq!(t.stats(w), (5, 4));
}

#[test]
fn militia_commander_has_three_more_attack_this_turn() {
    let mut t = scene!({"hand": ["GIL_803"]}, {});
    t.play("GIL_803", NONE);
    let m = t.nth(0, 0);
    assert_eq!(t.stats(m), (5, 5));
    t.end_turn();
    assert_eq!(t.stats(m), (2, 5));
}

#[test]
fn darius_grows_after_killing_a_minion() {
    let mut t = scene!({"board": ["GIL_547"]}, {"board": [WISP, OGRE]});
    let d = t.nth(0, 0);
    let w = t.on_board(1, WISP);
    t.attack(d, w);
    assert_eq!(t.stats(d), (6, 5), "4/4, 1 damage, +2/+2");
    // killed in the same fight: the +2/+2 does not bring it back
    let mut t = scene!({"board": [{"card": "GIL_547", "damage": 2}]}, {"board": [CROC]});
    let (d, c) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(d, c);
    assert!(t.cards(0).is_empty() && t.cards(1).is_empty());
}

#[test]
fn darius_no_buff_without_a_kill() {
    // Argent Squire: its Divine Shield takes the hit
    let mut t = scene!({"board": ["GIL_547"]}, {"board": ["VAN_EX1_008"]});
    let d = t.nth(0, 0);
    let s = t.nth(1, 0);
    t.attack(d, s);
    assert_eq!(t.stats(d), (4, 3));
}

#[test]
fn festeroot_hulk_grows_after_friendly_attacks() {
    let mut t = scene!({"board": ["GIL_655", WISP]}, {});
    let (h, w, foe) = (t.nth(0, 0), t.nth(0, 1), t.hero(1));
    t.attack(w, foe);
    assert_eq!(t.stats(h), (3, 7));
    t.attack(h, foe);
    assert_eq!(t.stats(h), (4, 7), "its own attack too");
}

#[test]
fn deadly_arsenal_reveals_a_weapon_and_deals_its_attack() {
    let mut t = scene!({"hand": ["GIL_537"], "deck": [WISP, AXE, WISP], "board": [YETI]}, {"board": [OGRE, CROC]});
    t.play("GIL_537", NONE);
    assert_eq!(t.stats(t.nth(0, 0)), (4, 2));
    assert_eq!(t.cards(1), vec![OGRE]);
    assert_eq!(t.stats(t.nth(1, 0)), (6, 4));
    assert_eq!(t.g.players[0].deck.len(), 3, "it stays in the deck");
    assert!(t.events().iter().any(|e| e["type"] == "reveal" && e["card"] == AXE));
    let mut t = scene!({"hand": ["GIL_537"], "deck": [WISP, YETI]}, {"board": [OGRE]});
    t.play("GIL_537", NONE);
    assert_eq!(t.stats(t.nth(1, 0)), (6, 7), "no weapon: nothing");
}

#[test]
fn blackhowl_gunspire_shoots_when_damaged() {
    let mut t = scene!({"hand": ["GIL_600"], "board": ["GIL_152"]}, {});
    let g = t.nth(0, 0);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == g), "can't attack");
    t.play("GIL_600", g);
    assert_eq!(t.hp(1), 27);
    // each damage event; the hit that kills it too (Fireball: 6 on 6 Health left)
    let mut t = scene!({"hand": [FIREBALL], "board": [{"card": "GIL_152", "damage": 2}]}, {});
    let g = t.nth(0, 0);
    t.play(FIREBALL, g);
    assert!(t.cards(0).is_empty());
    assert_eq!(t.hp(1), 27);
}

#[test]
fn tokens_are_plain() {
    let Some(rs) = rs() else { return };
    for (id, race) in [("GIL_191t", "DEMON"), ("GIL_508t", "BEAST")] {
        let c = rs.card(id);
        assert_eq!((c.cost, c.attack, c.health, c.race.as_str()), (1, 1, 1, race), "{id}");
    }
    let h = rs.card("GIL_504");
    assert_eq!(h.kind, "CHAMPION");
}
