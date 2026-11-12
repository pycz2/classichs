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

// Kobolds & Catacombs: the Druid, Hunter and Mage cards (packs/loot/scripts/loot_dhm.lua).

const CROC: &str = "VAN_CS2_120"; // a Beast
const GOLEM: &str = "VAN_CS2_186"; // War Golem, 7 Cost
const MISSILES: &str = "VAN_EX1_277"; // 1 Cost

fn can_attack(t: &T, a: Id) -> bool {
    t.g.legal_actions().iter().any(|x| x["type"] == "attack" && int(x.get("attacker")) == a)
}

fn deck(t: &T, p: usize) -> Vec<String> {
    t.g.players[p].deck.iter().map(|&e| t.g.e(e).card_id.to_string()).collect()
}

#[test]
fn barkskin_health_and_armor() {
    let mut t = scene!({"hand": ["LOOT_047"], "board": [WISP]}, {});
    let w = t.nth(0, 0);
    t.play("LOOT_047", w);
    assert_eq!(t.stats(w), (1, 4));
    assert_eq!(t.armor(0), 3);
}

#[test]
fn ironwood_golem_attacks_only_with_3_armor() {
    let t = scene!({"armor": 2, "board": ["LOOT_048"]}, {});
    assert!(!can_attack(&t, t.nth(0, 0)));
    let t = scene!({"armor": 3, "board": ["LOOT_048"]}, {});
    assert!(can_attack(&t, t.nth(0, 0)));
}

#[test]
fn branching_paths_chooses_twice_the_same_path_too() {
    // Fandral Staghelm does not make it a double choice: it is no Choose One
    let mut t = scene!({"hand": ["LOOT_054"], "board": [WISP, "OG_044"]}, {});
    t.play("LOOT_054", NONE);
    assert_eq!(t.options(), vec!["LOOT_054d", "LOOT_054b", "LOOT_054c"]);
    t.pick_card("LOOT_054c");
    assert_eq!(t.armor(0), 6);
    assert_eq!(t.options(), vec!["LOOT_054d", "LOOT_054b", "LOOT_054c"]);
    t.pick_card("LOOT_054c");
    assert_eq!(t.armor(0), 12);
    assert!(t.options().is_empty());
    let mut t = scene!({"hand": ["LOOT_054"], "board": [WISP]}, {});
    t.play("LOOT_054", NONE).pick_card("LOOT_054b").pick_card("LOOT_054d");
    assert_eq!(t.stats(t.nth(0, 0)), (2, 1));
    assert_eq!(t.hand(0), vec![WISP]);
}

#[test]
fn astral_tiger_shuffles_a_copy_into_the_deck() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_056"]}, {});
    let tiger = t.nth(0, 0);
    t.play(FIREBALL, tiger);
    assert!(t.cards(0).is_empty());
    assert_eq!(deck(&t, 0).iter().filter(|c| *c == "LOOT_056").count(), 1);
}

#[test]
fn oaken_summons_armor_and_a_recruit_of_cost_4_or_less() {
    let mut t = scene!({"hand": ["LOOT_309"], "deck": [GOLEM, YETI, GOLEM]}, {});
    t.play("LOOT_309", NONE);
    assert_eq!(t.armor(0), 6);
    assert_eq!(t.cards(0), vec![YETI]);
    assert_eq!(deck(&t, 0), vec![GOLEM, GOLEM]);
}

#[test]
fn grizzled_guardian_recruits_two() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_314"], "deck": [YETI, GOLEM, CROC]}, {});
    let gg = t.nth(0, 0);
    t.play(FIREBALL, gg);
    let mut b = t.cards(0);
    b.sort();
    assert_eq!(b, vec![CROC, YETI]);
}

#[test]
fn ixlid_copies_a_played_minion_without_its_battlecry() {
    let mut t = scene!({"hand": ["VAN_CS2_189", "LOOT_309"], "board": ["LOOT_329"], "deck": [YETI]}, {});
    let foe = t.hero(1);
    t.play("VAN_CS2_189", foe);
    assert_eq!(t.cards(0), vec!["LOOT_329", "VAN_CS2_189", "VAN_CS2_189"]);
    assert_eq!(t.hp(1), 29, "one Battlecry");
    t.play("LOOT_309", NONE); // a Recruit is no play
    assert_eq!(t.cards(0).len(), 4);
}

#[test]
fn greedy_sprite_gives_an_empty_crystal() {
    let mut t = scene!({"mana": 5, "max_mana": 5, "hand": [FIREBALL], "board": ["LOOT_351"]}, {});
    let s = t.nth(0, 0);
    t.play(FIREBALL, s);
    assert_eq!((t.g.players[0].mana, t.g.players[0].max_mana), (1, 6));
}

#[test]
fn twig_of_the_world_tree_gives_10_full_crystals() {
    let mut t = scene!({"mana": 0, "max_mana": 7, "weapon": {"card": "LOOT_392", "durability": 1}}, {});
    let (h, foe) = (t.hero(0), t.hero(1));
    t.attack(h, foe);
    assert!(t.g.players[0].weapon.is_none());
    assert_eq!((t.g.players[0].mana, t.g.players[0].max_mana), (10, 10));
}

#[test]
fn flanking_strike_damage_and_a_wolf() {
    let mut t = scene!({"hand": ["LOOT_077"]}, {"board": [YETI]});
    let y = t.nth(1, 0);
    t.play("LOOT_077", y);
    assert_eq!(t.stats(y), (4, 2));
    assert_eq!(t.cards(0), vec!["LOOT_077t"]);
}

#[test]
fn cave_hydra_hits_the_neighbours() {
    let mut t = scene!({"board": ["LOOT_078"]}, {"board": [WISP, YETI, WISP]});
    let (h, y) = (t.nth(0, 0), t.nth(1, 1));
    t.attack(h, y);
    assert_eq!(t.cards(1), vec![YETI]);
    assert_eq!(t.stats(y), (4, 3));
}

#[test]
fn wandering_monster_summons_a_3_cost_minion_as_the_new_target() {
    let mut t = scene!({"board": [YETI]}, {"secrets": ["LOOT_079"]});
    let (y, foe) = (t.nth(0, 0), t.hero(1));
    t.attack(y, foe);
    assert_eq!(t.hp(1), 30);
    assert!(t.g.players[1].secrets.is_empty());
    let rs = rs().unwrap();
    let ev: Vec<_> = t.events().into_iter().filter(|e| e["type"] == "summon").collect();
    assert_eq!(ev.len(), 1);
    assert_eq!(rs.card(ev[0]["card"].as_str().unwrap()).cost, 3);
    assert_eq!(ev[0]["player"], 1);
}

fn of_class(rs: &Ruleset, c: &str, cls: &str) -> bool {
    let k = rs.card(c);
    k.kind == "SPELL" && (k.card_class == cls || k.classes.iter().any(|x| x == cls))
}

#[test]
fn rhokdelar_fills_the_hand_with_hunter_spells_only_without_minions_in_the_deck() {
    let rs = rs().unwrap_or_else(|| panic!());
    let mut t = scene!({"hero": "HERO_05", "hand": ["LOOT_085"], "deck": [FIREBALL, FIREBALL]}, {});
    t.play("LOOT_085", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 10);
    assert!(h.iter().all(|c| of_class(rs, c, "HUNTER")), "{h:?}");
    let mut t = scene!({"hero": "HERO_05", "hand": ["LOOT_085"], "deck": [FIREBALL, WISP]}, {});
    t.play("LOOT_085", NONE);
    assert!(t.hand(0).is_empty());
}

#[test]
fn to_my_side_two_different_companions_without_minions_in_the_deck() {
    let mut t = scene!({"hand": ["LOOT_217"], "deck": [FIREBALL]}, {});
    t.play("LOOT_217", NONE);
    let b = t.cards(0);
    assert_eq!(b.len(), 2);
    assert_ne!(b[0], b[1]);
    let mut t = scene!({"hand": ["LOOT_217"], "deck": [WISP]}, {});
    t.play("LOOT_217", NONE);
    assert_eq!(t.cards(0).len(), 1);
    let t = scene!({"hand": ["LOOT_217"], "board": [WISP, WISP, WISP, WISP, WISP, WISP, WISP]}, {});
    assert!(!t.can_play("LOOT_217"), "no room");
}

#[test]
fn candleshot_hero_is_immune_while_attacking() {
    let mut t = scene!({"weapon": "LOOT_222"}, {"board": [YETI]});
    let (h, y) = (t.hero(0), t.nth(1, 0));
    t.attack(h, y);
    assert_eq!(t.hp(0), 30);
    assert_eq!(t.stats(y), (4, 4));
}

#[test]
fn kathrena_recruits_a_beast_twice() {
    let mut t = scene!({"mana": 12, "hand": ["LOOT_511", FIREBALL], "deck": [YETI, CROC, CROC]}, {});
    t.play("LOOT_511", NONE);
    assert_eq!(t.cards(0), vec!["LOOT_511", CROC]);
    let k = t.nth(0, 0);
    t.play(FIREBALL, k);
    assert_eq!(t.cards(0), vec![CROC, CROC]);
    assert_eq!(deck(&t, 0), vec![YETI]);
}

#[test]
fn seeping_oozeling_gains_a_deck_minions_deathrattle() {
    let mut t = scene!({"hand": ["LOOT_520", FIREBALL], "deck": [YETI, "VAN_EX1_029"]}, {});
    t.play("LOOT_520", NONE);
    let o = t.nth(0, 0);
    t.play(FIREBALL, o);
    assert_eq!(t.hp(1), 28, "Leper Gnome's Deathrattle");
    assert_eq!(deck(&t, 0).len(), 2, "the minion stays in the deck");
}

#[test]
fn crushing_walls_destroys_both_ends() {
    let mut t = scene!({"hand": ["LOOT_522"]}, {"board": [WISP, YETI, CROC]});
    t.play("LOOT_522", NONE);
    assert_eq!(t.cards(1), vec![YETI]);
    let mut t = scene!({"hand": ["LOOT_522"]}, {"board": [YETI]});
    t.play("LOOT_522", NONE);
    assert!(t.cards(1).is_empty());
}

#[test]
fn explosive_runes_excess_to_the_hero_but_not_through_divine_shield() {
    let mut t = scene!({"hand": [YETI]}, {"board": ["VAN_CS2_142"], "secrets": ["LOOT_101"]});
    t.play(YETI, NONE);
    assert_eq!(t.hp(0), 29, "6 - 5 Health, no Spell Damage");
    assert!(t.cards(0).is_empty());
    let mut t = scene!({"hand": ["VAN_EX1_008"]}, {"secrets": ["LOOT_101"]});
    t.play("VAN_EX1_008", NONE);
    assert_eq!(t.hp(0), 30, "Divine Shield takes it all");
    assert_eq!(t.cards(0), vec!["VAN_EX1_008"]);
}

#[test]
fn shifting_scroll_shifts_each_turn_and_cannot_be_played() {
    let rs = rs().unwrap_or_else(|| panic!());
    let mut t = scene!({"hand": [{"card": "LOOT_104", "tags": ["STARTED_IN_DECK"]}]}, {});
    assert!(!t.can_play("LOOT_104"));
    let mut seen = vec![];
    for _ in 0..3 {
        t.end_turn().end_turn();
        let e = t.g.players[0].hand[0];
        let c = card_of(&t, e);
        assert!(of_class(rs, &c, "MAGE"), "{c}");
        assert!(t.g.e(e).has("STARTED_IN_DECK"), "a card that transforms itself");
        seen.push((e, c));
    }
    assert!(seen[0].0 != seen[1].0 && seen[1].0 != seen[2].0, "a new card each turn: {seen:?}");
}

#[test]
fn deck_of_wonders_and_scroll_of_wonder_cast_when_drawn() {
    let mut t = scene!({"hand": ["LOOT_106"], "deck": [WISP]}, {});
    t.play("LOOT_106", NONE);
    assert_eq!(deck(&t, 0).iter().filter(|c| *c == "LOOT_106t").count(), 5);
    let mut t = scene!({"deck": [WISP, WISP, "LOOT_106t"]}, {"board": [YETI]});
    t.end_turn().end_turn();
    assert!(!t.hand(0).iter().any(|c| c == "LOOT_106t"));
    let ev = t.events();
    assert!(ev.iter().any(|e| e["type"] == "draw" && e.get("by").is_some_and(|b| b == "LOOT_106t")), "the Scroll draws a card: {ev:?}");
    assert!(t.events().iter().any(|e| e["type"] == "cast"), "a random spell");
}

#[test]
fn aluneth_draws_3_at_the_end_of_your_turn() {
    let mut t = scene!({"weapon": "LOOT_108"}, {});
    t.end_turn();
    assert_eq!(t.hand(0).len(), 3);
}

#[test]
fn raven_familiar_a_joust_of_spells() {
    let mut t = scene!({"hand": ["LOOT_170"], "deck": [WISP, FIREBALL]}, {"deck": [WISP, MISSILES]});
    t.play("LOOT_170", NONE);
    assert_eq!(t.hand(0), vec![FIREBALL]);
    let mut t = scene!({"hand": ["LOOT_170"], "deck": [MISSILES]}, {"deck": [MISSILES]});
    t.play("LOOT_170", NONE);
    assert!(t.hand(0).is_empty(), "a tie loses");
    let mut t = scene!({"hand": ["LOOT_170"], "deck": [MISSILES]}, {"deck": [WISP]});
    t.play("LOOT_170", NONE);
    assert_eq!(t.hand(0), vec![MISSILES], "no spell in theirs: won");
}

#[test]
fn dragons_fury_deals_the_revealed_spells_cost() {
    let mut t = scene!({"hand": ["LOOT_172"], "board": [YETI], "deck": [WISP, FIREBALL]}, {"board": [WISP]});
    let y = t.nth(0, 0);
    t.play("LOOT_172", NONE);
    assert_eq!(t.stats(y), (4, 1));
    assert!(t.cards(1).is_empty());
    assert_eq!(deck(&t, 0), vec![WISP, FIREBALL], "it stays in the deck");
}

#[test]
fn arcane_artificer_armor_equal_to_the_cost() {
    let mut t = scene!({"hand": [FIREBALL, "LOOT_537"], "board": ["LOOT_231"]}, {});
    t.play("LOOT_537", NONE); // Fireball (not from the deck): costs 2
    let foe = t.hero(1);
    t.play(FIREBALL, foe);
    assert_eq!(t.armor(0), 2, "the Cost paid");
}

#[test]
fn dragoncaller_alanna_a_dragon_per_5_cost_spell() {
    let mut t = scene!({"hand": ["VAN_CS2_032", MISSILES, "LOOT_535"], "deck": [WISP, WISP]}, {});
    t.play("VAN_CS2_032", NONE).play(MISSILES, NONE);
    t.end_turn().end_turn();
    t.play("LOOT_535", NONE);
    assert_eq!(t.cards(0), vec!["LOOT_535", "LOOT_535t"]);
}

#[test]
fn leyline_manipulator_only_the_cards_that_did_not_start_in_the_deck() {
    let mut t = scene!({"hand": [{"card": YETI, "tags": ["STARTED_IN_DECK"]}, FIREBALL, "LOOT_537"]}, {});
    t.play("LOOT_537", NONE);
    assert_eq!(t.cost(YETI), 4);
    assert_eq!(t.cost(FIREBALL), 2);
}
