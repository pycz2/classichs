//! The Witchwood pack (packs/gil): the first half of the neutral cards (scripts/gil_n1.lua) and the worgen tokens, as on
//! 2018-04-12 (build 23966). Needs python3 (skipped without it).

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

fn hand_of(t: &T, p: usize, card: &str) -> Id {
    *t.g.players[p].hand.iter().find(|&&e| t.g.e(e).card_id == card).unwrap_or_else(|| panic!("{card} not in hand {p}"))
}

#[test]
fn worgen_swap_in_the_hand_on_their_owners_turns_keeping_buffs() {
    let mut t = scene!({"hand": ["GIL_201", "GIL_528", "GIL_529", "CFM_685"]}, {});
    t.end_turn();
    assert_eq!(t.hand(0)[..3], ["GIL_201", "GIL_528", "GIL_529"], "not on the opponent's turn");
    t.end_turn();
    assert_eq!(t.hand(0)[..3], ["GIL_201t", "GIL_528t", "GIL_529t"]);
    assert_eq!(t.stats(hand_of(&t, 0, "GIL_201t")), (4, 2));
    assert_eq!(t.stats(hand_of(&t, 0, "GIL_528t")), (6, 2));
    assert_eq!(t.stats(hand_of(&t, 0, "GIL_529t")), (4, 1));
    t.end_turn().end_turn();
    assert_eq!(t.hand(0)[..3], ["GIL_201", "GIL_528", "GIL_529"], "and back");
    // a buff stays across the swap (before patch 12.0)
    let mut t = scene!({"hand": ["GIL_201", "CFM_685"]}, {});
    t.play("CFM_685", NONE);
    assert_eq!(t.stats(hand_of(&t, 0, "GIL_201")), (7, 9));
    t.end_turn().end_turn();
    assert_eq!(t.stats(hand_of(&t, 0, "GIL_201t")), (9, 7), "4/2 +5/+5");
}

#[test]
fn spellshifter_has_spell_damage_in_both_forms_and_messenger_rush() {
    let mut t = scene!({"board": ["GIL_529t"], "hand": [FIREBALL]}, {});
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    assert_eq!(t.hp(1), 30 - 7);
    let mut t = scene!({"board": ["GIL_529"], "hand": [FIREBALL]}, {});
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    assert_eq!(t.hp(1), 30 - 7);
    let mut t = scene!({"hand": ["GIL_528t"]}, {"board": [WISP]});
    t.play("GIL_528t", NONE);
    let m = t.on_board(0, "GIL_528t");
    let w = t.on_board(1, WISP);
    t.attack(m, w);
    assert_eq!(t.stats(m), (6, 1), "Swift Messenger 6/2: Rush");
}

#[test]
fn swamp_dragon_egg_gives_a_dragon() {
    let mut t = scene!({"board": ["GIL_816"], "hand": [FIREBALL]}, {});
    let egg = t.on_board(0, "GIL_816");
    t.play(FIREBALL, egg);
    assert_eq!(t.hand(0).len(), 1);
    let c = rs().unwrap().card(&card_of(&t, t.g.players[0].hand[0]));
    assert!(c.race == "DRAGON" || c.race == "ALL", "{}", c.race);
    assert!(c.collectible);
}

#[test]
fn lost_spirit_gives_your_minions_attack() {
    let mut t = scene!({"board": ["GIL_513", WISP], "hand": [FIREBALL]}, {"board": [WISP]});
    let s = t.on_board(0, "GIL_513");
    t.play(FIREBALL, s);
    assert_eq!(t.stats(t.on_board(0, WISP)), (2, 1));
    assert_eq!(t.stats(t.on_board(1, WISP)), (1, 1), "not the enemy's");
}

#[test]
fn baleful_banker_shuffles_a_plain_copy() {
    let mut t = scene!({"board": [YETI], "hand": ["GIL_815", "CFM_685"]}, {});
    let y = t.on_board(0, YETI);
    let n = t.g.players[0].deck.len();
    t.play("GIL_815", y);
    assert_eq!(t.g.players[0].deck.len(), n + 1);
    let yetis: Vec<Id> = t.g.players[0].deck.iter().copied().filter(|&e| t.g.e(e).card_id == YETI).collect();
    assert_eq!(yetis.len(), 1);
    assert_eq!(t.stats(yetis[0]), (4, 5));
}

#[test]
fn ravencaller_and_tanglefur_mystic_add_minions() {
    let mut t = scene!({"hand": ["GIL_212"]}, {});
    t.play("GIL_212", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 2);
    for c in &h {
        let c = rs().unwrap().card(c);
        assert!(c.collectible && c.cost == 1 && c.kind == "MINION", "{}", c.id);
    }
    let mut t = scene!({"hand": ["GIL_213"]}, {"hand": []});
    t.play("GIL_213", NONE);
    for p in 0..2 {
        let h = t.hand(p);
        assert_eq!(h.len(), 1, "player {p}");
        let c = rs().unwrap().card(&h[0]);
        assert!(c.collectible && c.cost == 2 && c.kind == "MINION", "{}", c.id);
    }
}

#[test]
fn hench_clan_thug_grows_after_your_hero_attacks() {
    let mut t = scene!({"board": ["GIL_534"], "weapon": "VAN_CS2_106"}, {"weapon": "VAN_CS2_106"});
    let me = t.hero(0);
    let foe = t.hero(1);
    let thug = t.on_board(0, "GIL_534");
    t.attack(me, foe);
    assert_eq!(t.stats(thug), (4, 4));
    t.end_turn();
    let me = t.hero(1);
    let foe = t.hero(0);
    t.attack(me, foe);
    assert_eq!(t.stats(thug), (4, 4), "not the enemy hero's attack");
}

#[test]
fn blackwald_pixie_refreshes_the_hero_power() {
    let mut t = scene!({"hand": ["GIL_561"]}, {});
    let foe = t.hero(1);
    t.power_on(foe);
    assert!(!t.can_power());
    t.play("GIL_561", NONE);
    assert!(t.can_power());
    t.power_on(foe);
    assert_eq!(t.hp(1), 30 - 2);
}

#[test]
fn voodoo_doll_destroys_the_chosen_minion() {
    let mut t = scene!({"hand": ["GIL_614", FIREBALL]}, {"board": [YETI, WISP]});
    let y = t.on_board(1, YETI);
    t.play("GIL_614", y);
    let d = t.on_board(0, "GIL_614");
    t.play(FIREBALL, d);
    assert_eq!(t.cards(1), vec![WISP]);
    // silenced, it destroys nothing
    let mut t = scene!({"hand": ["GIL_614", "VAN_EX1_048", FIREBALL], "mana": 20}, {"board": [YETI]});
    let y = t.on_board(1, YETI);
    t.play("GIL_614", y);
    let d = t.on_board(0, "GIL_614");
    t.play("VAN_EX1_048", d);
    t.play(FIREBALL, d);
    assert_eq!(t.cards(1), vec![YETI]);
    // the chosen minion died first: nothing more
    let mut t = scene!({"hand": ["GIL_614", FIREBALL, FIREBALL], "mana": 20}, {"board": [WISP, YETI]});
    let w = t.on_board(1, WISP);
    t.play("GIL_614", w);
    t.play(FIREBALL, w);
    let d = t.on_board(0, "GIL_614");
    t.play(FIREBALL, d);
    assert_eq!(t.cards(1), vec![YETI]);
}

#[test]
fn marsh_drake_gives_the_opponent_a_drakeslayer() {
    let mut t = scene!({"hand": ["GIL_683"]}, {});
    t.play("GIL_683", NONE);
    assert_eq!(t.cards(1), vec!["GIL_683t"]);
    let d = t.on_board(1, "GIL_683t");
    assert_eq!(t.stats(d), (2, 1));
    assert!(t.g.e(d).has("POISONOUS"));
}

#[test]
fn witchs_cauldron_gives_a_shaman_spell() {
    let mut t = scene!({"board": ["GIL_819", WISP], "hand": [FIREBALL, FIREBALL]}, {"board": [WISP]});
    let w = t.on_board(1, WISP);
    t.play(FIREBALL, w);
    assert_eq!(t.hand(0).len(), 1, "an enemy minion: nothing");
    let w = t.on_board(0, WISP);
    t.play(FIREBALL, w);
    assert_eq!(t.hand(0).len(), 1);
    let c = rs().unwrap().card(&t.hand(0)[0]);
    assert!(c.kind == "SPELL" && c.collectible, "{}", c.id);
    assert!(c.card_class == "SHAMAN" || c.classes.iter().any(|x| x == "SHAMAN"), "{}", c.id);
}

#[test]
fn mad_hatter_tosses_three_hats_to_other_minions() {
    let mut t = scene!({"hand": ["GIL_125"]}, {"board": [WISP]});
    t.play("GIL_125", NONE);
    assert_eq!(t.stats(t.on_board(1, WISP)), (4, 4), "the only other minion gets all three");
    assert_eq!(t.stats(t.on_board(0, "GIL_125")), (3, 2));
    let mut t = scene!({"hand": ["GIL_125"]}, {"board": [WISP, WISP, YETI]});
    t.play("GIL_125", NONE);
    let total: i64 = t.g.players[1].board.iter().map(|&m| t.g.e(m).atk()).sum();
    assert_eq!(total, 1 + 1 + 4 + 3);
}

#[test]
fn lifedrinker_drains_three() {
    let mut t = scene!({"hand": ["GIL_622"], "damage": 5}, {});
    t.play("GIL_622", NONE);
    assert_eq!(t.hp(1), 27);
    assert_eq!(t.hp(0), 28);
}

#[test]
fn night_prowler_alone_gets_three_three() {
    let mut t = scene!({"hand": ["GIL_624"]}, {});
    t.play("GIL_624", NONE);
    assert_eq!(t.stats(t.on_board(0, "GIL_624")), (6, 6));
    let mut t = scene!({"hand": ["GIL_624"]}, {"board": [WISP]});
    t.play("GIL_624", NONE);
    assert_eq!(t.stats(t.on_board(0, "GIL_624")), (3, 3), "an enemy minion counts too");
}

#[test]
fn sandbinder_draws_an_elemental() {
    let mut t = scene!({"hand": ["GIL_581"], "deck": [WISP, "UNG_809", WISP, YETI]}, {});
    t.play("GIL_581", NONE);
    assert_eq!(t.hand(0), vec!["UNG_809"]);
    let mut t = scene!({"hand": ["GIL_581"], "deck": [WISP, "GIL_681", WISP]}, {});
    t.play("GIL_581", NONE);
    assert_eq!(t.hand(0), vec!["GIL_681"], "Nightmare Amalgam is an Elemental");
    let mut t = scene!({"hand": ["GIL_581"], "deck": [WISP, YETI]}, {});
    t.play("GIL_581", NONE);
    assert!(t.hand(0).is_empty());
}

#[test]
fn witchwood_piper_draws_the_cheapest_minion() {
    let mut t = scene!({"hand": ["GIL_584"], "deck": ["VAN_CS2_168", "VAN_EX1_169", WISP, YETI]}, {});
    t.play("GIL_584", NONE);
    assert_eq!(t.hand(0), vec![WISP], "not the 0-Cost spell");
}

#[test]
fn scaleworm_with_a_dragon_in_hand_gets_rush() {
    let mut t = scene!({"hand": ["GIL_601", "VAN_EX1_284"]}, {"board": [WISP]});
    assert!(t.g.glows(t.hand_id("GIL_601")), "it glows");
    t.play("GIL_601", NONE);
    let w = t.on_board(0, "GIL_601");
    assert_eq!(t.stats(w), (5, 4));
    let y = t.on_board(1, WISP);
    t.attack(w, y);
    // Nightmare Amalgam is a Dragon
    let mut t = scene!({"hand": ["GIL_601", "GIL_681"]}, {});
    t.play("GIL_601", NONE);
    assert_eq!(t.stats(t.on_board(0, "GIL_601")), (5, 4));
    // no Dragon: nothing
    let mut t = scene!({"hand": ["GIL_601", YETI]}, {"board": [WISP]});
    assert!(!t.g.glows(t.hand_id("GIL_601")));
    t.play("GIL_601", NONE);
    let w = t.on_board(0, "GIL_601");
    assert_eq!(t.stats(w), (4, 4));
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == w));
}

#[test]
fn nightmare_amalgam_counts_as_pirate_and_beast() {
    // Southsea Captain: your other Pirates +1/+1
    let t = scene!({"board": ["VAN_NEW1_027", "GIL_681"]}, {});
    assert_eq!(t.stats(t.on_board(0, "GIL_681")), (4, 5));
    // Murloc Warleader
    let t = scene!({"board": ["VAN_EX1_507", "GIL_681"]}, {});
    assert_eq!(t.stats(t.on_board(0, "GIL_681")), (5, 4));
}

#[test]
fn echo_and_lifesteal_minions() {
    let mut t = scene!({"hand": ["GIL_680"]}, {});
    t.play("GIL_680", NONE);
    assert_eq!(t.hand(0), vec!["GIL_680"], "Walnut Sprite: an Echo copy");
    let mut t = scene!({"board": ["GIL_558"], "damage": 10}, {});
    let l = t.on_board(0, "GIL_558");
    let foe = t.hero(1);
    t.attack(l, foe);
    assert_eq!(t.hp(0), 22, "Swamp Leech: Lifesteal");
    let mut t = scene!({"hand": ["GIL_143"], "damage": 10}, {"board": [YETI]});
    t.play("GIL_143", NONE);
    let s = t.on_board(0, "GIL_143");
    let y = t.on_board(1, YETI);
    t.attack(s, y);
    assert_eq!(t.hp(0), 21, "Vicious Scalehide: Rush and Lifesteal");
}
