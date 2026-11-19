//! The Boomsday Project pack (packs/boom, built by tools/pack.py on The Witchwood and the packs before it): the cards as on
//! 2018-08-07 (build 25770) and the engine features it needs: Magnetic (FUSE: g.fuse, g.fused), Whizbang the Wonderful
//! (rules.json deck_recipes), Crystalsmith Kangor (HEAL_DOUBLE), the player hooks' aura (Dr. Boom's Rush), the 12.0 rules
//! (transform_drops_enchantments, g.copy_enchants), the emitted shuffles (Augmented Elekk), g.hand_slot (Stargazer Luna),
//! g.to_deck at a place (Dr. Morrigan), g.cast with Overload (Electra Stormsurge), the older cards of patches 11.1.1 to 12.0
//! and whole bot games with every deck template. Needs python3 (skipped without it).



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
        let out = std::env::temp_dir().join(format!("boom-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/boom", "-o"]).arg(&out).output().ok()?;
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

const MECH: &str = "BOT_309"; // Upgradeable Framebot, a 1/5 Mech

fn pos_play(t: &mut T, card: &str, pos: i64) {
    let e = t.hand_id(card);
    t.act(&format!("play {card} at {pos}"), |a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("pos")) == pos);
}

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(rs.cards.values().filter(|x| x.collectible && x.set == "BOOMSDAY").count(), 135);
    // the release build (25770), not today's
    assert_eq!(c("BOT_270").cost, 5, "Giggling Inventor 5 (7 from 2018-10-18)");
    assert_eq!(c("BOT_433").cost, 8, "Dr. Morrigan 8");
    assert_eq!(c("BOT_429").cost, 8, "Flark's Boom-Zooka 8");
    assert_eq!(c("BOT_238").cost, 7, "Dr. Boom, Mad Genius 7");
    assert_eq!(c("BOT_238").armor, 7);
    assert_eq!(c("BOT_568").cost, 1, "The Soularium 1");
    assert_eq!(stats("BOT_237"), (7, 3, 8), "Beryllium Nullifier 3/8");
    assert_eq!(stats("BOT_021"), (3, 1, 5), "Bronze Gatekeeper 1/5");
    assert_eq!(c("BOT_604").spell_power, Some(2), "Cosmic Anomaly +2");
    assert_eq!(c("BOT_559").race, "BEAST", "Augmented Elekk only a Beast in 2018");
    assert!(!rs.cards.contains_key("BOT_700"), "SN1P-SN4P came in 2019");
    // the older cards of patches 11.1.1 to 12.0
    assert_eq!(c("LOOT_093").cost, 5, "Call to Arms");
    assert_eq!(c("LOOT_306").cost, 6, "Possessed Lackey");
    assert_eq!(c("LOOT_539").cost, 7, "Spiteful Summoner");
    assert_eq!(c("LOE_038").cost, 8, "Naga Sea Witch");
    for (id, race) in [("VAN_EX1_105", "ELEMENTAL"), ("VAN_EX1_620", "ELEMENTAL"), ("GIL_584", "DEMON"), ("AT_103", "BEAST"),
        ("LOE_051", ""), ("GIL_545", ""), ("LOOT_329", "")] {
        assert_eq!(c(id).race, race, "{id}");
    }
    assert!(rs.transform_drops_enchantments);
    assert_eq!(rs.deck_recipes["BOT_914"].len(), 18);
    assert!(!rs.arena_pool.iter().any(|c| c == "BOT_914"), "Whizbang is never drafted");
}

#[test]
fn every_card_plays_without_a_script_error() {
    let Some(rs) = rs() else { return };
    let mut ids: Vec<&String> = rs.cards.keys().filter(|k| k.starts_with("BOT_")).collect();
    ids.sort();
    let mut n = 0;
    for id in ids {
        let c = rs.card(id);
        if !matches!(c.kind.as_str(), "MINION" | "SPELL" | "WEAPON" | "CHAMPION") || id == "BOT_914h" {
            continue;
        }
        let deck = json!(["BOT_031", YETI, "VAN_CS2_029", "BOT_509", "VAN_EX1_012", MECH, "BOT_908", WISP]);
        let Some(t) = game(json!({"hand": [id, YETI, "VAN_CS2_029", "BOT_537"], "board": [MECH, "BOT_445", WISP], "deck": deck,
            "weapon": "BOT_286"}), json!({"board": [YETI, "BOT_606"], "hand": [WISP, "BOT_312"], "deck": deck})) else { return };
        let e = *t.g.players[0].hand.iter().find(|&&x| t.g.e(x).card_id == id).unwrap();
        let plays: Vec<_> = t.g.legal_actions().into_iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).collect();
        for a in plays.into_iter().take(6) {
            let mut g = t.g.clone_state();
            assert!(g.apply(&Value::Object(a.clone())).ok, "{id}");
            for _ in 0..6 {
                if g.game_over {
                    break;
                }
                let p = g.pending.as_ref().map_or(g.current, |c| c.player);
                let b = bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(b)).ok);
            }
            assert_eq!(g.script_error.get(), None, "{id} {a:?}");
            n += 1;
        }
    }
    assert!(n > 140, "{n}");
}

// --- Magnetic (FUSE) ---------------------------------------------------------------------------------------------------

#[test]
fn magnetic_fuses_into_the_mech_on_its_right_played_not_summoned() {
    let mut t = scene!({"hand": ["BOT_548"], "board": [MECH, "VAN_NEW1_019"]}, {"board": [WISP]});
    // Knife Juggler (a summon trigger) stays quiet; Zilliax goes left of the Framebot (position 0)
    pos_play(&mut t, "BOT_548", 0);
    let m = t.nth(0, 0);
    assert_eq!(t.cards(0), vec![MECH, "VAN_NEW1_019"], "no new minion");
    assert_eq!(t.stats(m), (1 + 3, 5 + 2));
    for k in ["TAUNT", "DIVINE_SHIELD", "LIFESTEAL", "RUSH"] {
        assert!(t.g.e(m).has(k), "{k}");
    }
    assert!(!t.g.e(m).has("MODULAR"));
    assert_eq!(t.hp(1), 30, "no Knife Juggler");
    assert!(t.events().iter().any(|e| e["type"] == "fuse"));
    assert_eq!(t.g.players[0].minions_played_this_turn, 1, "played");
    let fused = t.g.fused(m);
    assert_eq!(fused.len(), 1);
    assert_eq!(t.g.e(fused[0]).zone, "GRAVEYARD");
    // the Framebot came in an earlier turn: Rush or not it may attack the hero
    // Silence takes it all
    let mut t = scene!({"hand": ["BOT_548", "VAN_EX1_332"], "board": [MECH]}, {});
    pos_play(&mut t, "BOT_548", 0);
    let m = t.nth(0, 0);
    t.play("VAN_EX1_332", m);
    assert_eq!(t.stats(m), (1, 5));
    assert!(!t.g.e(m).has("TAUNT") && !t.g.e(m).has("LIFESTEAL"));
    assert!(t.g.fused(m).is_empty());
}

#[test]
fn magnetic_right_of_a_mech_or_next_to_a_non_mech_is_a_minion() {
    let mut t = scene!({"hand": ["BOT_563"], "board": [MECH]}, {});
    pos_play(&mut t, "BOT_563", 1);
    assert_eq!(t.cards(0), vec![MECH, "BOT_563"]);
    let mut t = scene!({"hand": ["BOT_563"], "board": [YETI]}, {});
    pos_play(&mut t, "BOT_563", 0);
    assert_eq!(t.cards(0), vec!["BOT_563", YETI]);
    // a full board: not even to fuse (2018)
    let t = scene!({"hand": ["BOT_563"], "board": [MECH, MECH, MECH, MECH, MECH, MECH, MECH]}, {});
    assert!(!t.can_play("BOT_563"));
}

#[test]
fn a_fused_deathrattle_and_trigger_and_hand_buffs_come_along() {
    // Replicating Menace's Deathrattle on the Framebot; Glowstone Technician's +2/+2 in the hand comes too
    let mut t = scene!({"hand": ["BOT_910", "BOT_312", "VAN_CS2_029", "VAN_CS2_029"], "board": [MECH]}, {});
    t.play("BOT_910", NONE);
    pos_play(&mut t, "BOT_312", 0);
    let m = t.nth(0, 0);
    assert_eq!(t.stats(m), (1 + 5, 5 + 3));
    t.end_turn().end_turn();
    t.play("VAN_CS2_029", m);
    t.play("VAN_CS2_029", m);
    assert_eq!(t.cards(0).iter().filter(|c| *c == "BOT_312t").count(), 3, "{:?}", t.cards(0));
    // Missile Launcher's end of turn on its host: 1 damage to all others
    let mut t = scene!({"hand": ["BOT_107"], "board": [MECH, WISP]}, {"board": [YETI]});
    pos_play(&mut t, "BOT_107", 0);
    let host = t.nth(0, 0);
    t.end_turn();
    assert_eq!(t.stats(host), (5, 9), "the host is spared");
    assert_eq!(t.hp(1), 29);
    assert_eq!(t.hp(0), 29);
    assert_eq!(t.cards(0).len(), 1, "the Wisp died");
}

#[test]
fn kangors_endless_army_brings_mechs_back_with_their_magnetic_upgrades() {
    let mut t = scene!({"hand": ["BOT_563", "VAN_CS2_029", "BOT_912"], "board": [MECH, "BOT_445"]}, {});
    pos_play(&mut t, "BOT_563", 0);
    let m = t.nth(0, 0);
    t.play("VAN_CS2_029", m); // 6 damage to a 6/10
    t.end_turn().end_turn();
    let m = t.nth(0, 0);
    t.g.em(m).damage = 100; // (make it die)
    t.act("end turn", |a| a["type"] == "end_turn");
    t.end_turn();
    assert!(!t.cards(0).contains(&MECH.to_string()));
    t.play("BOT_912", NONE);
    let back = t.on_board(0, MECH);
    assert_eq!(t.stats(back), (6, 10), "Wargear's +5/+5 again");
}

// --- Whizbang the Wonderful (deck_recipes) ----------------------------------------------------------------------------

#[test]
fn whizbang_is_a_whole_deck_that_becomes_a_recipe() {
    let Some(rs) = rs() else { return };
    let whiz = vec!["BOT_914".to_string()];
    let deck = classichs_engine::deck::Deck { hero: "HERO_08".into(), cards: whiz.clone(), arena: false };
    assert_eq!(deck.validate_in(rs), "", "a deck of only Whizbang is legal");
    let mut two = deck.clone();
    two.cards.push(YETI.into());
    assert!(!two.validate_in(rs).is_empty());
    assert!(!deck.can_add_in(rs, YETI).is_empty());
    let plain: Vec<String> = vec![YETI.to_string(); 30];
    let mut classes = std::collections::BTreeSet::new();
    for seed in 0..30 {
        let g = Game::new_in(rs, "HERO_08", &whiz, "HERO_01", &plain, seed, 0, true);
        let n = g.players[0].deck.len() + g.players[0].hand.len();
        assert_eq!(n, 30, "a recipe of 30 cards");
        let hero = g.e(g.players[0].hero).card_id;
        let class = rs.class_of_champion(hero).unwrap().to_string();
        let recipes = &rs.deck_recipes["BOT_914"];
        assert!(recipes.iter().any(|(c, _)| *c == class));
        assert!(g.history[0].events().iter().any(|e| e["type"] == "deck_recipe" && e["card"] == "BOT_914"));
        assert!(!g.players[0].deck.iter().chain(&g.players[0].hand).any(|&e| g.e(e).card_id == "BOT_914"), "Whizbang is not in it");
        classes.insert(class);
    }
    assert!(classes.len() >= 5, "{classes:?}");
}

// --- Dr. Boom, Mad Genius ------------------------------------------------------------------------------------------------

#[test]
fn dr_boom_gives_mechs_rush_for_the_rest_of_the_game_and_swaps_his_power() {
    let mut t = scene!({"hero": "HERO_01", "hand": ["BOT_238", MECH, "BOT_603"], "max_mana": 10, "mana": 10}, {"board": [WISP]});
    t.play("BOT_238", NONE);
    assert_eq!(t.armor(0), 7);
    let p1 = t.power(0);
    assert!(p1.starts_with("BOT_238p") && p1 != "BOT_238p", "{p1}");
    t.play(MECH, NONE);
    let m = t.on_board(0, MECH);
    assert!(t.g.e(m).has("RUSH"), "a Mech has Rush");
    t.end_turn();
    let p2 = t.power(0);
    assert_ne!(p1, p2, "never the same twice");
    t.end_turn();
    assert_eq!(t.power(0), p2, "not on the opponent's turn");
}

// --- Celestial Emissary, Electra Stormsurge, Omega ------------------------------------------------------------------------

#[test]
fn celestial_emissary_gives_the_next_spell_spell_damage_two() {
    let mut t = scene!({"hand": ["BOT_531", "VAN_CS2_029", "VAN_CS2_029"]}, {});
    t.play("BOT_531", NONE);
    let foe = t.hero(1);
    t.play("VAN_CS2_029", foe);
    assert_eq!(t.hp(1), 30 - 8);
    t.play("VAN_CS2_029", foe);
    assert_eq!(t.hp(1), 30 - 8 - 6, "only the next one");
}

#[test]
fn electra_casts_the_next_spell_twice_with_its_overload() {
    let mut t = scene!({"hand": ["BOT_411", "VAN_EX1_238", "VAN_CS2_029"]}, {});
    t.play("BOT_411", NONE);
    let foe = t.hero(1);
    t.play("VAN_EX1_238", foe); // Lightning Bolt: 3, Overload (1)
    assert_eq!(t.hp(1), 30 - 6);
    assert_eq!(t.g.players[0].mana_lock_owed, 2);
    t.play("VAN_CS2_029", foe);
    assert_eq!(t.hp(1), 30 - 6 - 6, "once");
}

#[test]
fn omega_needs_ten_crystals() {
    let mut t = scene!({"hand": ["BOT_296"], "max_mana": 10, "mana": 10}, {});
    t.play("BOT_296", NONE);
    assert_eq!(t.stats(t.on_board(0, "BOT_296")), (12, 6));
    let mut t = scene!({"hand": ["BOT_296"], "max_mana": 9, "mana": 9}, {});
    t.play("BOT_296", NONE);
    assert_eq!(t.stats(t.on_board(0, "BOT_296")), (2, 6));
}

#[test]
fn omega_mind_gives_spells_lifesteal_this_turn() {
    let mut t = scene!({"hand": ["BOT_543", "VAN_CS2_029"], "max_mana": 10, "mana": 10}, {});
    t.g.em(t.hero(0)).damage = 10;
    t.play("BOT_543", NONE);
    let foe = t.hero(1);
    t.play("VAN_CS2_029", foe);
    assert_eq!(t.hp(0), 26);
}

// --- shuffles and the Bomb ------------------------------------------------------------------------------------------------

#[test]
fn seaforium_bomber_shuffles_a_bomb_that_explodes_when_drawn() {
    let mut t = scene!({"hand": ["BOT_511"]}, {"deck": []});
    t.play("BOT_511", NONE);
    assert_eq!(t.g.players[1].deck.len(), 1);
    t.end_turn();
    assert_eq!(t.hp(1), 30 - 5 - 1, "5, then the draw of an empty deck: fatigue");
    assert!(t.events().iter().any(|e| e["type"] == "cast_when_drawn" && e["card"] == "BOT_511t"));
}

#[test]
fn augmented_elekk_shuffles_an_extra_copy() {
    let mut t = scene!({"board": ["BOT_559"], "hand": ["BOT_511", "BOT_288"], "deck": []}, {"deck": []});
    t.play("BOT_511", NONE);
    assert_eq!(t.g.players[1].deck.len(), 2, "two Bombs");
    let b = t.on_board(0, "BOT_511");
    let _ = b;
    t.play("BOT_288", t.on_board(0, "BOT_559"));
    assert_eq!(t.g.players[0].deck.len(), 6, "Lab Recruiter's 3, doubled");
}

#[test]
fn academic_espionage_cards_cost_one() {
    let mut t = scene!({"hand": ["BOT_087"], "deck": []}, {"hero": "HERO_08"});
    t.play("BOT_087", NONE);
    let deck = t.g.players[0].deck.clone();
    assert_eq!(deck.len(), 10);
    for e in deck {
        assert_eq!(t.g.cost(e), 1);
        let c = t.g.e(e).card;
        assert!(c.card_class == "MAGE" || c.classes.iter().any(|x| x == "MAGE"), "{}", c.id);
    }
}

// --- the other engine-deep cards ------------------------------------------------------------------------------------------

#[test]
fn mechathun_destroys_the_enemy_hero_with_nothing_left() {
    let mut t = scene!({"board": ["BOT_424"], "hand": ["VAN_CS2_029"], "deck": []}, {});
    let m = t.on_board(0, "BOT_424");
    t.g.em(m).damage = 4;
    t.play("VAN_CS2_029", m);
    assert!(t.g.game_over);
    assert_eq!(t.g.winner, 0);
    let mut t = scene!({"board": ["BOT_424", WISP], "hand": ["VAN_CS2_029"], "deck": []}, {});
    let m = t.on_board(0, "BOT_424");
    t.g.em(m).damage = 4;
    t.play("VAN_CS2_029", m);
    assert!(!t.g.game_over, "a minion left");
}

#[test]
fn crystalsmith_kangor_doubles_healing() {
    let mut t = scene!({"board": ["BOT_236"], "hand": ["VAN_CS2_007"]}, {});
    t.g.em(t.hero(0)).damage = 20;
    let h = t.hero(0);
    t.play("VAN_CS2_007", h); // Healing Touch: 8
    assert_eq!(t.hp(0), 10 + 16);
}

#[test]
fn flarks_boom_zooka_summons_three_that_attack_then_die() {
    let mut t = scene!({"hand": ["BOT_429"], "deck": [YETI, YETI, YETI, "VAN_CS2_029"]}, {"board": ["VAN_CS2_186"]});
    t.play("BOT_429", NONE);
    assert!(t.cards(0).is_empty(), "they died");
    assert!(t.cards(1).is_empty(), "the 7/5 took three Yetis' attacks");
    assert_eq!(t.g.players[0].deck.len(), 1);
}

#[test]
fn dr_morrigan_swaps_with_a_deck_minion() {
    let mut t = scene!({"board": ["BOT_433"], "hand": ["VAN_CS2_029"], "deck": ["VAN_CS2_029", YETI, "VAN_CS2_029"]}, {});
    let m = t.on_board(0, "BOT_433");
    t.g.em(m).damage = 3;
    t.play("VAN_CS2_029", m);
    assert_eq!(t.cards(0), vec![YETI]);
    let deck: Vec<String> = t.g.players[0].deck.iter().map(|&e| card_of(&t, e)).collect();
    assert_eq!(deck, vec!["VAN_CS2_029", "BOT_433", "VAN_CS2_029"], "in the Yeti's place");
}

#[test]
fn zerek_comes_back_after_a_spell_on_him() {
    let mut t = scene!({"board": ["BOT_258"], "hand": ["BOT_219", "VAN_CS2_029", "VAN_CS2_008"]}, {});
    let z = t.on_board(0, "BOT_258");
    t.play("BOT_219", z);
    t.play("VAN_CS2_029", z);
    t.play("VAN_CS2_008", z);
    let z2 = t.on_board(0, "BOT_258");
    assert_eq!(t.stats(z2), (5, 5), "a fresh Zerek");
}

#[test]
fn test_subject_returns_the_spells_cast_on_it() {
    let mut t = scene!({"board": ["BOT_558"], "hand": ["BOT_219", "VAN_CS2_029"]}, {});
    let s = t.on_board(0, "BOT_558");
    t.play("BOT_219", s);
    t.play("VAN_CS2_029", s);
    assert!(t.hand(0).contains(&"BOT_219".to_string()), "{:?}", t.hand(0));
    assert!(t.hand(0).contains(&"VAN_CS2_029".to_string()));
}

#[test]
fn stargazer_luna_draws_after_the_right_most_card() {
    let mut t = scene!({"board": ["BOT_103"], "hand": [WISP, "VAN_CS2_029"], "deck": [YETI, YETI]}, {});
    let foe = t.hero(1);
    t.play("VAN_CS2_029", foe);
    assert_eq!(t.hand(0), vec![WISP, YETI]);
    t.play(WISP, NONE);
    assert_eq!(t.hand(0), vec![YETI], "the Wisp was not the right-most");
}

#[test]
fn floop_becomes_a_three_four_copy_of_the_last_minion_played() {
    let mut t = scene!({"hand": ["BOT_434", YETI]}, {});
    t.play(YETI, NONE);
    let f = t.g.players[0].hand[0];
    assert_eq!(card_of(&t, f), YETI);
    assert_eq!(t.stats(f), (3, 4));
    assert_eq!(t.g.cost(f), 4);
}

#[test]
fn transforms_drop_enchantments_and_copies_keep_them() {
    // a worgen buffed in the hand loses the buff when it swaps (patch 12.0)
    let mut t = scene!({"hand": ["GIL_201", "BOT_910"]}, {});
    t.play("BOT_910", NONE);
    t.end_turn().end_turn();
    let w = t.g.players[0].hand[0];
    assert_eq!(card_of(&t, w), "GIL_201t");
    assert_eq!(t.stats(w), (4, 2), "no +2/+2 left");
    // Cloning Device: a deck → hand copy keeps the Cost (1) of Luna's Pocket Galaxy
    let mut t = scene!({"hand": ["BOT_435"]}, {"hand": ["BOT_257"], "deck": ["VAN_EX1_620", "VAN_EX1_620", WISP, WISP]});
    t.end_turn();
    t.play("BOT_257", NONE);
    t.end_turn();
    t.play("BOT_435", NONE);
    t.pick_card("VAN_EX1_620");
    let c = t.hand_id("VAN_EX1_620");
    assert_eq!(t.g.cost(c), 1);
}

#[test]
fn dark_pact_heals_four_and_crystal_core_makes_four_fours() {
    let mut t = scene!({"board": [WISP], "hand": ["LOOT_017", "UNG_067t1", YETI]}, {});
    t.g.em(t.hero(0)).damage = 10;
    let w = t.on_board(0, WISP);
    t.play("LOOT_017", w);
    assert_eq!(t.hp(0), 24);
    t.play("UNG_067t1", NONE);
    t.play(YETI, NONE);
    assert_eq!(t.stats(t.on_board(0, YETI)), (4, 4));
}

#[test]
fn shadowboxer_only_on_minion_healing() {
    let mut t = scene!({"board": ["GVG_072", "VAN_CS2_235"], "hand": ["VAN_CS2_007"]}, {"board": []});
    t.g.em(t.hero(0)).damage = 10;
    let h = t.hero(0);
    t.play("VAN_CS2_007", h);
    assert_eq!(t.hp(1), 30, "a hero healed: nothing (patch 12.0)");
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/boom/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(&f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30, "{f:?}");
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
    decks.push(("HERO_08".to_string(), vec!["BOT_914".to_string()])); // Whizbang
    let mut over = 0;
    let mut errors = vec![];
    let mut played = std::collections::BTreeSet::new();
    let mut seen = std::collections::BTreeMap::new();
    for (i, (c0, d0)) in decks.iter().enumerate() {
        let (c1, d1) = &decks[(i + 7) % decks.len()];
        for seed in 0..3 {
            let mut g = Game::new_in(rs, c0, d0, c1, d1, seed + 10 * i as i64, -1, true);
            let mut steps = 0;
            while !g.game_over && g.turn < 80 {
                let p = if g.phase == "MULLIGAN" {
                    (0..2).find(|&p| !g.players[p].mulliganed).unwrap()
                } else {
                    g.pending.as_ref().map_or(g.current, |c| c.player)
                };
                let a = bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(a)).ok);
                steps += 1;
                assert!(steps < 4000);
            }
            if let Some(err) = g.script_error.get() {
                errors.push(format!("deck {i} ({c0}) vs {} ({c1}), seed {seed}: {err}", (i + 7) % decks.len()));
            }
            over += g.game_over as usize;
            for h in &g.history {
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    if e["type"] == "play" && card.starts_with("BOT_") {
                        played.insert(card.to_string());
                    }
                    let t = e["type"].as_str().unwrap_or("");
                    if ["fuse", "deck_recipe", "cast_when_drawn", "start_of_game"].contains(&t) {
                        *seen.entry(t.to_string()).or_insert(0) += 1;
                    }
                }
            }
        }
    }
    eprintln!("The Boomsday Project cards played: {}: {played:?}", played.len());
    eprintln!("new mechanics' events: {seen:?}");
    assert!(errors.is_empty(), "script errors:\n{}", errors.join("\n"));
    assert!(seen.contains_key("deck_recipe") && seen.contains_key("fuse"), "{seen:?}");
    assert!(over >= decks.len() * 2, "most games end");
    assert!(played.len() >= 15, "the decks play the set");
}

// --- the card tests (data/card_tests/boom.json, as game/card_tests.gd plays them) ------------------------------------------

fn ref_id(g: &Game, r: Option<&Value>) -> Id {
    let Some(r) = r.and_then(Value::as_object) else { return NONE };
    let p = &g.players[int(r.get("side")) as usize];
    let i = int(r.get("index")) as usize;
    match r.get("zone").and_then(Value::as_str).unwrap_or("") {
        "hand" => p.hand.get(i).copied().unwrap_or(NONE),
        "board" => p.board.get(i).copied().unwrap_or(NONE),
        "secret" => p.secrets.get(i).copied().unwrap_or(NONE),
        "hero" => p.hero,
        "weapon" => p.weapon.unwrap_or(NONE),
        "power" => p.hero_power,
        _ => NONE,
    }
}

#[test]
fn card_tests_play() {
    let Some(rs) = rs() else { return };
    let tests: Map<String, Value> =
        serde_json::from_str(&std::fs::read_to_string(repo().join("data/card_tests/boom.json")).unwrap()).unwrap();
    let mut bad = vec![];
    for (id, list) in &tests {
        for t in list.as_array().unwrap() {
            if let Some(s) = t.get("script").and_then(Value::as_str) {
                if rs.card(id).script != s {
                    bad.push(format!("{id}: script {s} is not the pack's {}", rs.card(id).script));
                    continue;
                }
            }
            let title = t["title"].as_str().unwrap();
            let mut g = match scenario::build_in(rs, &t["scene"]) {
                Ok(g) => g,
                Err(e) => {
                    bad.push(format!("{title}: scene: {e}"));
                    continue;
                }
            };
            for (i, s) in t["steps"].as_array().unwrap().iter().enumerate() {
                let want: Vec<(&str, Value)> = match s["do"].as_str().unwrap() {
                    "play" => {
                        let mut w = vec![("type", json!("play")), ("entity", json!(ref_id(&g, s.get("card")))),
                            ("target", json!(ref_id(&g, s.get("target")))), ("choice", json!(s.get("choice").map_or(-1, |c| int(Some(c)))))];
                        if let Some(p) = s.get("pos") {
                            w.push(("pos", p.clone()));
                        }
                        w
                    }
                    "attack" => vec![("type", json!("attack")), ("attacker", json!(ref_id(&g, s.get("attacker")))),
                        ("defender", json!(ref_id(&g, s.get("defender"))))],
                    "hero_power" => vec![("type", json!("hero_power")), ("target", json!(ref_id(&g, s.get("target"))))],
                    "end_turn" => vec![("type", json!("end_turn"))],
                    "choose" => {
                        let opts = g.pending_options();
                        let n = int(s.get("option"));
                        let o = if opts.contains(&n) { n } else { opts.get(n as usize).copied().unwrap_or(NONE) };
                        vec![("type", json!("choose")), ("option", json!(o))]
                    }
                    x => panic!("{x}"),
                };
                let a = g.legal_actions().into_iter().find(|a| {
                    want.iter().all(|(k, v)| {
                        if *k == "pos" && int(a.get("pos")) < 0 {
                            return true;
                        }
                        a.get(*k).cloned().unwrap_or(if ["target", "choice"].contains(k) { json!(-1) } else { Value::Null }) == *v
                    })
                });
                let Some(a) = a else {
                    bad.push(format!("{title}: step {i}: not legal: {want:?}"));
                    break;
                };
                assert!(g.apply(&Value::Object(a)).ok);
                if let Some(e) = g.script_error.get() {
                    bad.push(format!("{title}: step {i}: {e}"));
                    break;
                }
            }
        }
    }
    assert!(bad.is_empty(), "{} problems:\n{}", bad.len(), bad.join("\n"));
}
