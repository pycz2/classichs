//! The Kobolds & Catacombs pack (packs/loot, built by tools/pack.py on Knights of the Frozen Throne and the packs before
//! it): the cards as on 2017-12-07 (build 22611) and the engine features it needs: Recruit (`g.summon_entity` from the
//! deck), Spellstones and Unidentified items (a card that transforms itself in the hand), "Cast this when drawn",
//! Kingsbane and King Togwaggle (`g.to_deck`: a card keeps its enchantments in a deck), Murmuring Elemental (the
//! champion's own DOUBLE_ON_PLAY), Shimmering Courser (FOE_SPELLPROOF), the patches 9.1–10.0 (Lifesteal heals once for an
//! effect: `behaviour.lifesteal_one_heal`; a countered spell is still cast; Dragon's Breath's own cost change last:
//! `cost_last`), the older cards of that day, and whole bot games with every deck template. Needs python3 (skipped
//! without it).


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


#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(rs.cards.values().filter(|x| x.collectible && x.set == "LOOTAPALOOZA").count(), 135);
    assert!(!rs.cards.contains_key("LOOT_500d"), "Val'anyr's dummy is no card");
    assert_eq!(stats("LOOT_149"), (7, 5, 5), "Corridor Creeper 5/5 until patch 10.2");
    assert_eq!(c("LOOT_017").cost, 1, "Dark Pact");
    assert_eq!(c("LOOT_093").cost, 4, "Call to Arms 4 until 11.1.1");
    assert_eq!(c("LOOT_306").cost, 5, "Possessed Lackey 5");
    assert_eq!(c("LOOT_539").cost, 6, "Spiteful Summoner 6");
    assert_eq!(c("LOOT_412").cost, 4, "Kobold Illusionist 4");
    assert_eq!(c("LOOT_417").cost, 4, "Cataclysm 4");
    assert_eq!(stats("LOOT_137"), (9, 4, 12), "Sleepy Dragon 4/12");
    assert_eq!(stats("LOOT_211"), (4, 3, 2), "Elven Minstrel 3/2");
    assert_eq!(stats("LOOT_231"), (1, 1, 2), "Arcane Artificer 1/2");
    assert_eq!(c("LOOT_329").race, "ELEMENTAL", "Ixlid an Elemental at the release");
    for id in ["LOOT_056", "LOOT_313", "LOOT_375", "LOOT_516", "LOOT_534"] {
        assert_eq!(c(id).race, "", "{id}: no tribe in 2017");
    }
    assert_eq!(c("LOOT_111").race, "MECHANICAL");
    // the older cards of patch 9.1 (2017-09-18)
    assert_eq!(c("VAN_CS2_106").cost, 3, "Fiery War Axe");
    assert_eq!(c("VAN_EX1_246").cost, 4, "Hex");
    assert_eq!(c("ICC_054").cost, 6, "Spreading Plague");
    // what came after the release stays out
    assert_eq!(c("CFM_637").keywords.iter().any(|k| k == "CHARGE"), true, "Patches keeps Charge until 10.2");
    assert_eq!(c("ICC_705").cost, 7, "Bonemare 7");
    // the build's export quirks: Elemental Destruction keeps Overload (5)
    assert_eq!(c("AT_051").mana_lock, 5);
    assert!(rs.lifesteal_one_heal && !rs.countered_no_after_spell);
}

#[test]
fn innervate_and_murloc_warleader_of_patch_9_1() {
    let mut t = scene!({"mana": 3, "hand": ["VAN_EX1_169"], "board": ["VAN_EX1_507", "VAN_CS2_168"]}, {});
    t.play("VAN_EX1_169", NONE);
    assert_eq!(t.g.players[0].mana, 4, "one crystal");
    let m = t.on_board(0, "VAN_CS2_168");
    assert_eq!(t.stats(m), (2 + 2, 1), "Murloc Raider: +2 Attack only");
}

#[test]
fn unlicensed_apothecary_after_you_summon() {
    let mut t = scene!({"hand": [WISP], "board": ["CFM_900"]}, {});
    t.play(WISP, NONE);
    assert_eq!(t.hp(0), 25);
}

#[test]
fn dragons_breath_costs_less_after_naga_sea_witch() {
    // patch 9.2: its own cost change after all the others: Naga Sea Witch's 5, then 2 less for two deaths
    let mut t = scene!({"hand": ["BRM_003", FIREBALL, FIREBALL], "board": ["LOE_038"]}, {"board": [WISP, WISP]});
    let (a, b) = (t.nth(1, 0), t.nth(1, 1));
    t.play(FIREBALL, a).play(FIREBALL, b);
    assert_eq!(t.cost("BRM_003"), 3);
}

#[test]
fn a_spellstone_upgrades_in_the_hand() {
    let mut t = scene!({"hand": ["LOOT_051", "VAN_EX1_606", "VAN_EX1_606"]}, {"board": [YETI]});
    t.play("VAN_EX1_606", NONE); // Shield Block: 5 Armor, one step
    assert_eq!(t.hand(0)[0], "LOOT_051t1", "Jasper Spellstone");
    t.play("VAN_EX1_606", NONE);
    assert_eq!(t.hand(0)[0], "LOOT_051t2");
    let e = t.nth(1, 0);
    t.play("LOOT_051t2", e);
    assert!(t.g.e(e).health() <= 0 || t.g.e(e).zone != "PLAY");
}

#[test]
fn an_amethyst_spellstone_upgrades_when_your_cards_hurt_you() {
    let mut t = scene!({"hero": "HERO_07", "damage": 10, "hand": ["LOOT_043", "LOOT_013"]}, {"board": ["VAN_CS2_186"]});
    t.play("LOOT_013", NONE); // Vulgar Homunculus: 2 damage to your hero
    assert_eq!(t.hand(0), vec!["LOOT_043t2"]);
    t.power_on(NONE); // Life Tap
    assert_eq!(t.hand(0)[0], "LOOT_043t3");
    let hp = t.hp(0);
    let e = t.nth(1, 0);
    t.play("LOOT_043t3", e);
    assert_eq!(t.hp(0), hp + 7, "Lifesteal");
}

#[test]
fn an_unidentified_item_is_identified_in_the_hand() {
    let mut t = scene!({"deck": ["LOOT_285", "LOOT_278", "LOOT_286"]}, {});
    t.end_turn().end_turn();
    let h = t.hand(0);
    assert!(h.iter().any(|c| c.starts_with("LOOT_286t")), "{h:?}");
    // the opponent sees a card back only
    let e = t.g.players[0].hand[0];
    let view = api::snapshot(&t.g, 1);
    assert_eq!(view["entities"][e.to_string()]["card"], "", "hidden from the opponent");
}

#[test]
fn lifesteal_heals_once_for_an_effect() {
    // patch 10.0: Spirit Lash (1 to every minion, Lifesteal) heals once for all it dealt
    let mut t = scene!({"hero": "HERO_09", "damage": 10, "hand": ["ICC_802"], "board": [WISP]}, {"board": [WISP, YETI]});
    t.play("ICC_802", NONE);
    let heals: Vec<_> = t.events().into_iter().filter(|e| e["type"] == "heal").collect();
    assert_eq!(heals.len(), 1, "{heals:?}");
    assert_eq!(t.hp(0), 23);
}

#[test]
fn murmuring_elemental_doubles_the_next_battlecry() {
    let mut t = scene!({"hand": ["LOOT_517", "VAN_CS2_189", "VAN_CS2_189"]}, {});
    t.play("LOOT_517", NONE);
    t.play("VAN_CS2_189", t.hero(1)); // Elven Archer: twice
    assert_eq!(t.hp(1), 28);
    t.play("VAN_CS2_189", t.hero(1)); // once
    assert_eq!(t.hp(1), 27);
}

#[test]
fn shimmering_courser_only_its_player_targets_it_with_spells() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_193"]}, {"hand": [FIREBALL], "board": [WISP]});
    let c = t.nth(0, 0);
    assert!(t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("target")) == c), "its own player can");
    t.end_turn();
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("target")) == c), "the opponent cannot");
}

#[test]
fn wild_pyromancer_summoned_by_mindgames_does_not_hear_it() {
    // patch 9.2.0.21517
    let mut t = scene!({"hero": "HERO_09", "hand": ["VAN_EX1_345"], "board": [YETI]}, {"deck": ["VAN_NEW1_020"]});
    t.play("VAN_EX1_345", NONE);
    assert_eq!(t.cards(0), vec![YETI.to_string(), "VAN_NEW1_020".to_string()]);
    let y = t.nth(0, 0);
    assert_eq!(t.stats(y), (4, 5), "no 1 damage to all minions");
}

#[test]
fn lord_jaraxxus_does_not_set_off_repentance() {
    // patch 9.2.0.21517
    let mut t = scene!({"hero": "HERO_07", "hand": ["VAN_EX1_323"]}, {"secrets": ["VAN_EX1_379"]});
    t.play("VAN_EX1_323", NONE);
    assert_eq!(t.g.players[1].secrets.len(), 1, "Repentance stays");
    assert_eq!(t.hp(0), 15);
}

#[test]
fn a_countered_spell_is_still_cast() {
    // patch 9.2.0.21517: Counterspell's spell still triggers "after you cast a spell"
    let mut t = scene!({"hand": [FIREBALL], "board": ["VAN_NEW1_020"]}, {"secrets": ["VAN_EX1_287"], "board": [YETI]});
    let h = t.hero(1);
    t.play(FIREBALL, h);
    assert_eq!(t.hp(1), 30, "countered");
    let y = t.nth(1, 0);
    assert_eq!(t.stats(y).1, 4, "Wild Pyromancer still went off");
}

// --- neutral ---------------------------------------------------------------------------------------

const FLAMESTRIKE: &str = "VAN_CS2_032";
const AXE: &str = "VAN_CS2_106";
const EXECUTE: &str = "VAN_CS2_108";
const RAPTOR: &str = "VAN_CS2_172";
const CROC: &str = "VAN_CS2_120";
const RAGNAROS: &str = "VAN_EX1_298";
const AZURE: &str = "VAN_EX1_284";

impl T {
    fn deck(&self, p: usize) -> Vec<String> {
        self.g.players[p].deck.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn board_ids(&self, p: usize) -> Vec<Id> {
        self.g.players[p].board.clone()
    }
}

#[test]
fn the_darkness_sleeps_until_its_three_candles_are_drawn() {
    let mut t = scene!({"hand": ["LOOT_526"]}, {"deck": []});
    t.play("LOOT_526", NONE);
    let d = t.on_board(0, "LOOT_526");
    assert!(!t.g.awake(d), "it starts Dormant");
    assert_eq!(t.deck(1), vec!["LOOT_526t"; 3]);
    // the opponent draws a candle: it is cast (snuff, draw), the next one too… the third wakes The Darkness
    t.end_turn();
    assert!(t.g.awake(d), "awake after three candles");
    assert!(t.deck(1).is_empty() && t.hand(1).is_empty(), "{:?} {:?}", t.deck(1), t.hand(1));
    assert_eq!(t.stats(d), (20, 20));
}

#[test]
fn a_darkness_summoned_without_its_battlecry_sleeps_for_good() {
    // Guild Recruiter recruits it (Cost 4): Dormant, no candles
    let mut t = scene!({"hand": ["LOOT_375"], "deck": ["LOOT_526"]}, {});
    t.play("LOOT_375", NONE);
    let d = t.on_board(0, "LOOT_526");
    assert!(!t.g.awake(d));
    assert!(!t.deck(1).iter().any(|c| c == "LOOT_526t"));
}

#[test]
fn a_candle_of_ones_own_snuffs_nothing_but_draws() {
    // a Darkness candle cast for the Darkness's own player (Psionic Probe's copy) only draws
    let mut t = scene!({"hand": ["LOOT_526", "LOOT_526t"]}, {});
    t.play("LOOT_526", NONE);
    let d = t.on_board(0, "LOOT_526");
    let n = t.hand(0).len();
    t.play("LOOT_526t", NONE);
    assert!(!t.g.awake(d));
    assert_eq!(t.hand(0).len(), n, "played one, drew one");
}

#[test]
fn corridor_creeper_costs_less_for_each_death_while_in_hand() {
    let mut t = scene!({"hand": ["LOOT_149", FIREBALL, FIREBALL]}, {"board": [WISP, WISP]});
    assert_eq!(t.cost("LOOT_149"), 7);
    let (a, b) = (t.nth(1, 0), t.nth(1, 1));
    t.play(FIREBALL, a).play(FIREBALL, b);
    assert_eq!(t.cost("LOOT_149"), 5);
}

#[test]
fn arcane_tyrant_costs_nothing_after_a_big_spell() {
    let mut t = scene!({"hand": ["LOOT_130", FLAMESTRIKE, "VAN_CS2_023"]}, {"board": [WISP]});
    t.play("VAN_CS2_023", NONE);
    assert_eq!(t.cost("LOOT_130"), 5, "a 3-Cost spell does not count");
    t.play(FLAMESTRIKE, NONE);
    assert_eq!(t.cost("LOOT_130"), 0);
    t.end_turn().end_turn();
    assert_eq!(t.cost("LOOT_130"), 5, "this turn only");
}

#[test]
fn carnivorous_cube_eats_a_minion_and_gives_two_back() {
    let mut t = scene!({"hand": ["LOOT_161"], "board": [YETI]}, {"hand": [FIREBALL]});
    let y = t.nth(0, 0);
    t.play("LOOT_161", y);
    assert_eq!(t.cards(0), vec!["LOOT_161"]);
    let c = t.nth(0, 0);
    t.end_turn();
    t.play(FIREBALL, c);
    assert_eq!(t.cards(0), vec![YETI, YETI]);
    for m in t.board_ids(0) {
        assert_eq!(t.stats(m), (4, 5), "plain copies");
    }
}

#[test]
fn marins_chest_gives_marins_player_a_treasure() {
    let mut t = scene!({"hand": ["LOOT_357"]}, {});
    t.play("LOOT_357", NONE);
    assert_eq!(t.cards(1), vec!["LOOT_357l"]);
    let mut t = scene!({"hand": [FIREBALL, FIREBALL]}, {"board": ["LOOT_357l"]});
    let c = t.nth(1, 0);
    t.play(FIREBALL, c).play(FIREBALL, c);
    let h = t.hand(0);
    assert_eq!(h.len(), 1);
    assert!(["LOOT_998h", "LOOT_998j", "LOOT_998k", "LOOT_998l"].contains(&h[0].as_str()), "{h:?}");
}

#[test]
fn the_treasures() {
    // Tolin's Goblet: draw a card, fill the hand with copies of it
    let mut t = scene!({"hand": ["LOOT_998h"], "deck": [YETI]}, {});
    t.play("LOOT_998h", NONE);
    assert_eq!(t.hand(0), vec![YETI; 10]);
    // Wondrous Wand: three cards that cost (0)
    let mut t = scene!({"hand": ["LOOT_998l"], "deck": [YETI, RAGNAROS, FIREBALL]}, {});
    t.play("LOOT_998l", NONE);
    assert_eq!(t.hand(0).len(), 3);
    for c in [YETI, RAGNAROS, FIREBALL] {
        assert_eq!(t.cost(c), 0, "{c}");
    }
    // Golden Kobold: the rest of the hand becomes Legendary minions
    let mut t = scene!({"hand": ["LOOT_998k", WISP, FIREBALL]}, {});
    t.play("LOOT_998k", NONE);
    let rs = rs().unwrap();
    let h = t.hand(0);
    assert_eq!(h.len(), 2);
    for c in &h {
        assert!(rs.card(c).rarity == "LEGENDARY" && rs.card(c).kind == "MINION", "{c}");
    }
    // Zarog's Crown: Discover a Legendary minion, two of it
    let mut t = scene!({"hand": ["LOOT_998j"]}, {});
    t.play("LOOT_998j", NONE);
    let c = t.pick_first();
    assert_eq!(rs.card(&c).rarity, "LEGENDARY");
    assert_eq!(t.cards(0), vec![c.clone(), c]);
}

#[test]
fn king_togwaggle_swaps_the_decks_and_gives_a_ransom() {
    let mut t = scene!({"hand": ["LOOT_541"], "deck": [WISP, WISP]}, {"deck": [YETI, YETI, YETI]});
    t.play("LOOT_541", NONE);
    assert_eq!(t.deck(0), vec![YETI; 3]);
    assert_eq!(t.deck(1), vec![WISP; 2]);
    assert_eq!(t.hand(1), vec!["LOOT_541t"]);
    t.end_turn(); // the opponent draws a Wisp and swaps back
    t.play("LOOT_541t", NONE);
    assert_eq!(t.deck(1), vec![YETI; 3]);
    assert_eq!(t.deck(0), vec![WISP]);
}

#[test]
fn grand_archivist_casts_a_spell_of_the_deck() {
    // Execute has no target (no damaged enemy): it stays; the Fireball is cast from the deck
    let mut t = scene!({"board": ["LOOT_414"], "deck": [EXECUTE, FIREBALL, WISP]}, {"deck": FILL});
    let hp = t.hp(1) + t.hp(0) + t.g.e(t.nth(0, 0)).health();
    t.end_turn();
    let d = t.deck(0);
    assert!(d.contains(&EXECUTE.to_string()) && !d.contains(&FIREBALL.to_string()), "{d:?}");
    let after = t.hp(1) + t.hp(0) + t.g.players[0].board.first().map_or(0, |&m| t.g.e(m).health());
    assert!(after <= hp - 6 || t.g.players[0].board.is_empty(), "6 damage somewhere");
}

#[test]
fn spiteful_summoner_reveals_a_spell_and_summons_a_minion_of_its_cost() {
    let mut t = scene!({"hand": ["LOOT_539"], "deck": [FIREBALL, WISP]}, {});
    t.play("LOOT_539", NONE);
    let rs = rs().unwrap();
    assert_eq!(t.cards(0).len(), 2);
    assert_eq!(rs.card(&t.cards(0)[1]).cost, 4);
    assert!(t.events().iter().any(|e| e["type"] == "reveal" && e["card"] == FIREBALL));
    assert_eq!(t.deck(0).len(), 2, "the spell stays");
}

#[test]
fn kobold_monk_shields_its_champion_from_spells() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_382"]}, {"hand": [FIREBALL]});
    let h0 = t.hero(0);
    let targets_h0 = |t: &T| t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("target")) == h0);
    assert!(!targets_h0(&t), "not even its own player");
    t.end_turn();
    assert!(!targets_h0(&t));
}

#[test]
fn rummaging_kobold_returns_a_destroyed_weapon() {
    let mut t = scene!({"weapon": "VAN_CS2_106", "hand": ["LOOT_389"]}, {"hand": ["LOOT_122"]});
    t.end_turn();
    t.play("LOOT_122", NONE); // Corrosive Sludge
    assert!(t.g.players[0].weapon.is_none());
    t.end_turn();
    t.play("LOOT_389", NONE);
    assert!(t.hand(0).contains(&AXE.to_string()), "{:?}", t.hand(0));
}

#[test]
fn void_ripper_swaps_attack_and_health() {
    let mut t = scene!({"hand": ["LOOT_529"], "board": [YETI, "LOOT_117"]}, {"board": [RAPTOR]});
    t.play("LOOT_529", NONE);
    assert_eq!(t.cards(0), vec![YETI, "LOOT_529"], "the 0/2 Wax Elemental dies");
    assert_eq!(t.stats(t.nth(0, 0)), (5, 4));
    assert_eq!(t.stats(t.nth(1, 0)), (2, 3));
    assert_eq!(t.stats(t.nth(0, 1)), (3, 3), "not itself");
}

#[test]
fn master_oakheart_recruits_a_1_2_and_3_attack_minion() {
    let mut t = scene!({"hand": ["LOOT_521"], "deck": [YETI, RAPTOR, CROC, WISP, YETI]}, {});
    t.play("LOOT_521", NONE);
    assert_eq!(t.cards(0), vec!["LOOT_521", WISP, CROC, RAPTOR]);
    assert_eq!(t.deck(0), vec![YETI, YETI]);
}

#[test]
fn recruits_on_death_and_at_end_of_turn() {
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_184", "LOOT_540"], "deck": [RAGNAROS, YETI, "LOOT_137"]}, {});
    let v = t.nth(0, 0);
    t.play(FIREBALL, v);
    assert!(t.cards(0).contains(&RAGNAROS.to_string()), "Silver Vanguard: an 8-Cost minion");
    t.end_turn();
    assert!(t.cards(0).contains(&"LOOT_137".to_string()), "Dragonhatcher: a Dragon");
}

#[test]
fn toothy_chest_has_4_attack_from_its_turn_start() {
    let mut t = scene!({"board": ["LOOT_134"]}, {});
    let c = t.nth(0, 0);
    t.end_turn();
    assert_eq!(t.stats(c).0, 0);
    t.end_turn();
    assert_eq!(t.stats(c).0, 4);
}

#[test]
fn feral_gibberer_copies_itself_after_hitting_a_hero() {
    let mut t = scene!({"board": ["LOOT_218"]}, {});
    let (m, h) = (t.nth(0, 0), t.hero(1));
    t.attack(m, h);
    assert_eq!(t.hand(0), vec!["LOOT_218"]);
}

#[test]
fn small_battlecries() {
    // Kobold Apprentice: 3 damage split among the enemies
    let mut t = scene!({"hand": ["LOOT_347"]}, {"board": [YETI]});
    t.play("LOOT_347", NONE);
    let y = t.nth(1, 0);
    assert_eq!(30 - t.hp(1) + t.g.e(y).damage, 3);
    // Lone Champion alone: Taunt and Divine Shield; not alone: nothing
    let mut t = scene!({"hand": ["LOOT_124", "LOOT_124"]}, {});
    t.play("LOOT_124", NONE).play("LOOT_124", NONE);
    let (a, b) = (t.nth(0, 0), t.nth(0, 1));
    assert!(t.g.e(a).has("TAUNT") && t.g.e(a).has("DIVINE_SHIELD"));
    assert!(!t.g.e(b).has("TAUNT"));
    // Scorp-o-matic only on a minion with 1 or less Attack; Dragonslayer only on a Dragon
    let mut t = scene!({"hand": ["LOOT_111", "LOOT_132"]}, {"board": [WISP, YETI, AZURE]});
    let (w, y, d) = (t.nth(1, 0), t.nth(1, 1), t.nth(1, 2));
    let targets = |t: &T, card: &str| {
        let e = t.hand_id(card);
        t.g.legal_actions().iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).map(|a| int(a.get("target"))).collect::<Vec<_>>()
    };
    let s = targets(&t, "LOOT_111");
    assert!(s.contains(&w) && !s.contains(&y));
    let s = targets(&t, "LOOT_132");
    assert!(s.contains(&d) && !s.contains(&y));
    t.play("LOOT_111", w).play("LOOT_132", d);
    assert_eq!(t.cards(1), vec![YETI]);
    // Ebon Dragonsmith: a weapon in the hand costs (2) less
    let mut t = scene!({"hand": ["LOOT_118", AXE]}, {});
    t.play("LOOT_118", NONE);
    assert_eq!(t.cost(AXE), 1);
    // Hoarding Dragon: two Coins for the opponent
    let mut t = scene!({"hand": [FIREBALL], "board": ["LOOT_144"]}, {});
    let d = t.nth(0, 0);
    t.play(FIREBALL, d);
    assert_eq!(t.hand(1), vec!["GAME_005", "GAME_005"]);
    // Violet Wurm: seven Grubs
    let mut t = scene!({"hand": [FIREBALL, FIREBALL], "board": ["LOOT_153"]}, {});
    let d = t.nth(0, 0);
    t.play(FIREBALL, d).play(FIREBALL, d);
    assert_eq!(t.cards(0), vec!["LOOT_153t1"; 7]);
    // Gravelsnout Knight and Hungry Ettin: a random 1- / 2-Cost minion for the opponent
    let mut t = scene!({"hand": ["LOOT_154", "LOOT_383"]}, {});
    t.play("LOOT_154", NONE).play("LOOT_383", NONE);
    let rs = rs().unwrap();
    let c: Vec<i64> = t.cards(1).iter().map(|c| rs.card(c).cost).collect();
    assert_eq!(c, vec![1, 2]);
    // Furbolg Mossbinder and Zola
    let mut t = scene!({"hand": ["LOOT_150", "LOOT_516"], "board": [WISP, YETI]}, {});
    let (w, y) = (t.nth(0, 0), t.nth(0, 1));
    t.play("LOOT_150", w).play("LOOT_516", y);
    assert_eq!(t.cards(0)[0], "LOOT_150t1");
    assert_eq!(t.hand(0), vec![YETI]);
}

#[test]
fn end_of_turn_summons() {
    let mut t = scene!({"board": ["LOOT_131", "LOOT_394"]}, {});
    t.end_turn();
    let rs = rs().unwrap();
    let c = t.cards(0);
    assert_eq!(c.len(), 4, "{c:?}");
    assert!(c.contains(&"LOOT_131t1".to_string()));
    assert!(c.iter().any(|x| x != "LOOT_131t1" && x != "LOOT_131" && x != "LOOT_394" && rs.card(x).cost == 1));
}

// --- dhm ---------------------------------------------------------------------------------------

// Kobolds & Catacombs: the Druid, Hunter and Mage cards (packs/loot/scripts/loot_dhm.lua).

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

// --- ppr ---------------------------------------------------------------------------------------


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
    let t = scene!({"hand": ["LOOT_528"]}, {"board": [YETI]});
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

// --- ssw ---------------------------------------------------------------------------------------

const DEMON: &str = "VAN_CS2_065"; // Voidwalker
const TOTEMS: [&str; 4] = ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009"];

// --- Shaman ---------------------------------------------------------------------------------------------------------------

#[test]
fn crushing_hand_deals_8_and_overloads_3() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_060"]}, {"board": ["VAN_CS2_200"]});
    let e = t.nth(1, 0);
    t.play("LOOT_060", e);
    assert!(t.g.players[1].board.is_empty(), "Boulderfist Ogre 6/7 dies");
    assert_eq!(t.g.players[0].mana_lock_owed, 3);
}

#[test]
fn kobold_hermit_summons_the_chosen_totem_right_of_it() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_062"], "board": [WISP]}, {});
    t.play("LOOT_062", NONE);
    let mut o = t.options();
    o.sort();
    assert_eq!(o, TOTEMS.to_vec());
    t.pick_card("VAN_CS2_051");
    assert_eq!(t.cards(0), vec![WISP, "LOOT_062", "VAN_CS2_051"]);
}

#[test]
fn primal_talismans_gives_a_totem_deathrattle() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_344", FIREBALL], "board": [WISP, YETI]}, {});
    t.play("LOOT_344", NONE);
    let w = t.nth(0, 0);
    t.play(FIREBALL, w);
    let b = t.cards(0);
    assert_eq!(b.len(), 2, "{b:?}");
    assert!(TOTEMS.contains(&b[0].as_str()), "a totem where the Wisp was: {b:?}");
    assert_eq!(b[1], YETI);
}

#[test]
fn grumble_returns_your_other_minions_costing_1() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_358"], "board": [YETI, "VAN_CS2_200"]}, {"board": [WISP]});
    t.play("LOOT_358", NONE);
    assert_eq!(t.cards(0), vec!["LOOT_358"]);
    assert_eq!(t.cards(1), vec![WISP], "the enemy's stay");
    assert_eq!(t.hand(0), vec![YETI, "VAN_CS2_200"]);
    assert_eq!(t.cost(YETI), 1);
    assert_eq!(t.cost("VAN_CS2_200"), 1);
}

#[test]
fn healing_rain_heals_only_damaged_friends() {
    // 3 damage on the hero, 2 on the Yeti, none on the Wisp: 5 of the 12 are used, the rest is lost
    let mut t = scene!({"hero": "HERO_02", "damage": 3, "hand": ["LOOT_373"], "board": [WISP, {"card": YETI, "damage": 2}]}, {"board": [{"card": YETI, "damage": 2}]});
    t.play("LOOT_373", NONE);
    assert_eq!(t.hp(0), 30);
    assert_eq!(t.stats(t.nth(0, 1)), (4, 5));
    assert_eq!(t.stats(t.nth(1, 0)), (4, 3), "the enemy's not");
    let heals: Vec<_> = t.events().into_iter().filter(|e| e["type"] == "heal").collect();
    assert_eq!(heals.len(), 5, "one at a time: {heals:?}");
    // much damage: all 12
    let mut t = scene!({"hero": "HERO_02", "damage": 20, "hand": ["LOOT_373", "VAN_CS2_045"]}, {});
    t.play("LOOT_373", NONE);
    assert_eq!(t.hp(0), 22);
}

#[test]
fn unstable_evolution_repeats_this_turn() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_504"], "board": [WISP]}, {});
    let m = t.nth(0, 0);
    t.play("LOOT_504", m);
    let m = t.nth(0, 0);
    assert_eq!(rs().unwrap().card(&card_of(&t, m)).cost, 1, "{}", card_of(&t, m));
    assert_eq!(t.hand(0), vec!["LOOT_504t"]);
    t.play("LOOT_504t", m);
    let m = t.nth(0, 0);
    assert_eq!(rs().unwrap().card(&card_of(&t, m)).cost, 2, "{}", card_of(&t, m));
    assert_eq!(t.hand(0), vec!["LOOT_504t"], "the copy repeats too");
    t.end_turn();
    assert!(t.hand(0).is_empty(), "gone at the end of the turn");
    assert!(!t.events().iter().any(|e| e["type"] == "discard"), "removed, not discarded");
}

#[test]
fn the_runespear_discovers_a_spell_and_casts_it() {
    let mut t = scene!({"hero": "HERO_02", "weapon": "LOOT_506"}, {"board": [YETI]});
    let (h, e) = (t.hero(0), t.nth(1, 0));
    t.attack(h, e);
    let o = t.options();
    assert_eq!(o.len(), 3, "{o:?}");
    let rs = rs().unwrap();
    assert!(o.iter().all(|c| rs.card(c).kind == "SPELL"), "{o:?}");
    let c = t.pick_first();
    assert!(t.events().iter().any(|e| e["type"] == "cast" || e["type"] == "fizzle"), "{c} cast");
    // its last swing too
    let mut t = scene!({"hero": "HERO_02", "weapon": {"card": "LOOT_506", "durability": 1}}, {"board": [YETI]});
    let (h, e) = (t.hero(0), t.nth(1, 0));
    t.attack(h, e);
    assert!(t.g.players[0].weapon.is_none());
    assert_eq!(t.options().len(), 3);
    t.pick_first();
}

#[test]
fn windshear_stormcaller_needs_the_four_totems() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_518"], "board": TOTEMS}, {});
    t.play("LOOT_518", NONE);
    assert_eq!(t.cards(0)[5], "VAN_NEW1_010");
    let mut t = scene!({"hero": "HERO_02", "hand": ["LOOT_518"], "board": ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052"]}, {});
    t.play("LOOT_518", NONE);
    assert_eq!(t.cards(0).len(), 4);
}

// --- Warlock --------------------------------------------------------------------------------------------------------------

#[test]
fn kobold_librarian_and_vulgar_homunculus_hurt_your_hero() {
    let mut t = scene!({"hero": "HERO_07", "hand": ["LOOT_014", "LOOT_013"], "deck": [YETI]}, {});
    t.play("LOOT_014", NONE);
    assert_eq!(t.hand(0), vec!["LOOT_013", YETI]);
    assert_eq!(t.hp(0), 28);
    t.play("LOOT_013", NONE);
    assert_eq!(t.hp(0), 26);
}

#[test]
fn dark_pact_destroys_a_friend_and_heals_8() {
    let mut t = scene!({"hero": "HERO_07", "damage": 10, "hand": ["LOOT_017"], "board": [YETI]}, {"board": [WISP]});
    let m = t.nth(0, 0);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("target")) == t.nth(1, 0)), "a friendly minion only");
    t.play("LOOT_017", m);
    assert!(t.g.players[0].board.is_empty());
    assert_eq!(t.hp(0), 28);
}

#[test]
fn hooked_reaver_at_15_health_or_less() {
    let mut t = scene!({"hero": "HERO_07", "damage": 15, "hand": ["LOOT_018"]}, {});
    t.play("LOOT_018", NONE);
    let m = t.nth(0, 0);
    assert_eq!(t.stats(m), (7, 7));
    assert!(t.g.e(m).has("TAUNT"));
    let mut t = scene!({"hero": "HERO_07", "damage": 14, "hand": ["LOOT_018"]}, {});
    t.play("LOOT_018", NONE);
    let m = t.nth(0, 0);
    assert_eq!(t.stats(m), (4, 4));
    assert!(!t.g.e(m).has("TAUNT"));
}

#[test]
fn possessed_lackey_recruits_a_demon() {
    let mut t = scene!({"hero": "HERO_07", "hand": [FIREBALL], "board": ["LOOT_306"], "deck": [WISP, DEMON, WISP]}, {});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    assert_eq!(t.cards(0), vec![DEMON]);
    assert_eq!(t.g.players[0].deck.len(), 2);
}

#[test]
fn voidlord_leaves_three_voidwalkers() {
    let mut t = scene!({"hero": "HERO_07", "hand": ["VAN_EX1_308"], "board": [WISP, "LOOT_368", YETI]}, {});
    let m = t.nth(0, 1);
    t.g.em(m).damage = 6;
    t.play("VAN_EX1_308", m); // Soulfire: 4
    assert_eq!(t.cards(0), vec![WISP, DEMON, DEMON, DEMON, YETI]);
}

#[test]
fn rin_and_her_seals_up_to_azari() {
    let mut t = scene!({"hero": "HERO_07", "hand": [FIREBALL], "board": [{"card": "LOOT_415", "damage": 3}]}, {"deck": [WISP, WISP, YETI]});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    assert_eq!(t.hand(0), vec!["LOOT_415t1"]);
    for n in 1..=5 {
        t.g.players[0].mana = 10;
        t.play(&format!("LOOT_415t{n}"), NONE);
        let f = t.on_board(0, &format!("LOOT_415t{n}t"));
        assert_eq!(t.stats(f), (n + 1, n + 1));
    }
    assert_eq!(t.hand(0), vec!["LOOT_415t6"]);
    t.g.players[0].mana = 10;
    t.play("LOOT_415t6", NONE);
    assert!(t.g.players[1].deck.is_empty(), "the opponent's deck is gone");
    assert!(t.g.players[1].hand.is_empty(), "not drawn");
}

#[test]
fn cataclysm_discards_before_the_deathrattles() {
    // Voidcaller's Deathrattle finds no Demon: the hand was discarded first
    let mut t = scene!({"hero": "HERO_07", "hand": ["LOOT_417", DEMON, WISP], "board": ["FP1_022"]}, {"board": [YETI]});
    t.play("LOOT_417", NONE);
    assert!(t.g.players[0].board.is_empty() && t.g.players[1].board.is_empty());
    assert!(t.hand(0).is_empty());
    assert_eq!(t.events().iter().filter(|e| e["type"] == "discard").count(), 2);
}

#[test]
fn skull_of_the_manari_summons_a_demon_before_the_draw() {
    let mut t = scene!({"hero": "HERO_07", "weapon": "LOOT_420", "hand": ["LOOT_013", WISP], "deck": ["VAN_CS2_059"]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.cards(0), vec!["LOOT_013"]);
    assert_eq!(t.hp(0), 30, "no Battlecry");
    assert_eq!(t.hand(0), vec![WISP, "VAN_CS2_059"], "the drawn Demon (Blood Imp) came after");
}

// --- Warrior --------------------------------------------------------------------------------------------------------------

#[test]
fn kobold_barbarian_attacks_a_random_enemy_at_the_start_of_your_turn() {
    let mut t = scene!({"board": ["LOOT_041"]}, {"board": [WISP]});
    let wisp = t.nth(1, 0);
    t.end_turn().end_turn();
    let hit = t.hp(1) == 26 || !t.g.players[1].board.contains(&wisp);
    assert!(hit, "it attacked");
    let b = t.on_board(0, "LOOT_041");
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == b), "its attack of the turn (2017)");
}

#[test]
fn bladed_gauntlet_attack_is_your_armor_and_no_heroes() {
    let mut t = scene!({"armor": 5, "hand": ["LOOT_044", "VAN_EX1_606"]}, {"board": ["VAN_CS2_200"]});
    t.play("LOOT_044", NONE);
    let w = t.g.players[0].weapon.unwrap();
    assert_eq!(t.g.e(w).atk(), 5);
    t.play("VAN_EX1_606", NONE); // Shield Block: +5 Armor
    assert_eq!(t.g.e(w).atk(), 10);
    let h = t.hero(0);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == h && int(a.get("defender")) == t.hero(1)));
    let ogre = t.nth(1, 0);
    t.attack(h, ogre);
    assert_eq!(t.armor(0), 4, "the Ogre's 6 came off the Armor");
    assert_eq!(t.g.e(w).atk(), 4);
}

#[test]
fn gemstudded_golem_attacks_only_with_5_armor() {
    let mut t = scene!({"armor": 4, "board": ["LOOT_365"]}, {});
    let m = t.nth(0, 0);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == m));
    t.g.em(t.hero(0)).set_tag("ARMOR", 5i64);
    t.g.update_auras();
    let e = t.hero(1);
    t.attack(m, e);
    assert_eq!(t.hp(1), 25);
}

#[test]
fn reckless_flurry_spends_the_armor() {
    let mut t = scene!({"armor": 3, "hand": ["LOOT_364"], "board": [YETI]}, {"board": [YETI, "VAN_CS2_200"]});
    t.play("LOOT_364", NONE);
    assert_eq!(t.armor(0), 0);
    assert_eq!(t.stats(t.nth(0, 0)), (4, 2));
    assert_eq!(t.stats(t.nth(1, 1)), (6, 4));
}

#[test]
fn drywhisker_armorer_2_armor_per_enemy_minion() {
    let mut t = scene!({"hand": ["LOOT_367"], "board": [WISP]}, {"board": [WISP, WISP, YETI]});
    t.play("LOOT_367", NONE);
    assert_eq!(t.armor(0), 6);
}

#[test]
fn gather_your_party_and_woecleaver_recruit() {
    let mut t = scene!({"hand": ["LOOT_370"], "deck": [FIREBALL, YETI, FIREBALL]}, {});
    t.play("LOOT_370", NONE);
    assert_eq!(t.cards(0), vec![YETI]);
    let mut t = scene!({"weapon": "LOOT_380", "deck": [FIREBALL, "VAN_CS2_200"]}, {});
    let (h, e) = (t.hero(0), t.hero(1));
    t.attack(h, e);
    assert_eq!(t.cards(0), vec!["VAN_CS2_200"]);
}

#[test]
fn geosculptor_yip_summons_a_minion_of_your_armor_cost() {
    let mut t = scene!({"armor": 3, "board": ["LOOT_519", WISP]}, {});
    t.end_turn();
    let b = t.cards(0);
    assert_eq!(b.len(), 3, "{b:?}");
    assert_eq!(rs().unwrap().card(&b[1]).cost, 3, "{b:?}: right of Yip");
    let mut t = scene!({"armor": 25, "board": ["LOOT_519"]}, {});
    t.end_turn();
    let b = t.cards(0);
    assert_eq!(rs().unwrap().card(&b[1]).cost, 10, "{b:?}");
}

// --- whole games ----------------------------------------------------------------------------------------------------

const RECRUITS: [&str; 11] = ["LOOT_309", "LOOT_314", "LOOT_511", "LOOT_093", "LOOT_306", "LOOT_370", "LOOT_380", "LOOT_375",
    "LOOT_184", "LOOT_540", "LOOT_521"];
const STONES: [&str; 9] = ["LOOT_051", "LOOT_080", "LOOT_103", "LOOT_091", "LOOT_507", "LOOT_503", "LOOT_064", "LOOT_043", "LOOT_203"];

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/loot/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30);
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
    assert!(decks.len() >= 12);
    let mut over = 0;
    let mut played = std::collections::BTreeSet::new();
    let mut seen = std::collections::BTreeMap::new();
    let mut count = |k: &str| *seen.entry(k.to_string()).or_insert(0) += 1;
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
                assert_eq!(g.script_error.get(), None, "{c0} vs {c1}");
                steps += 1;
                assert!(steps < 4000);
            }
            over += g.game_over as usize;
            for h in &g.history {
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    let ty = e["type"].as_str().unwrap_or("");
                    if ty == "play" && card.starts_with("LOOT") {
                        played.insert(card.to_string());
                        if RECRUITS.contains(&card) {
                            count("recruit cards played");
                        }
                        if rs.card(card).kind == "WEAPON" && rs.card(card).rarity == "LEGENDARY" {
                            count("legendary weapons played");
                        }
                    }
                    if ty == "transform" && e.get("entity").is_some() {
                        let stone = STONES.iter().any(|s| card.starts_with(s) && card.len() > s.len() && !card.ends_with("t4"));
                        let n = if stone { "spellstone upgrades" } else if card.starts_with("LOOT_2") { "identified items" } else { "other transforms" };
                        count(n);
                    }
                    if ty == "cast_when_drawn" {
                        count("cast when drawn");
                    }
                    if ty == "to_deck" {
                        count("to_deck");
                    }
                }
            }
        }
    }
    eprintln!("LOOTAPALOOZA cards played: {}: {played:?}; {seen:?}", played.len());
    assert!(over >= decks.len(), "most games end");
    assert!(played.len() >= 40, "the decks play the set");
    assert!(seen.get("spellstone upgrades").is_some_and(|&n| n > 0), "{seen:?}");
}

#[test]
fn random_cards_never_fail() {
    let Some(rs) = rs() else { return };
    let loot: Vec<String> = {
        let mut v: Vec<String> = rs.cards.values().filter(|c| c.set == "LOOTAPALOOZA" && c.kind != "POWER").map(|c| c.id.clone()).collect();
        v.sort();
        v
    };
    for seed in 0..160 {
        let hand: Vec<&String> = loot.iter().skip((seed * 7) % loot.len()).take(8).collect();
        let hero = ["HERO_01", "HERO_03", "HERO_06", "HERO_08", "HERO_09", "HERO_05", "HERO_07", "HERO_02", "HERO_04"][seed as usize % 9];
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": hero, "mana": 10, "max_mana": 10, "weapon": "VAN_CS2_106",
             "deck": [YETI, "LOOT_285", "LOOT_278", WISP, "LOOT_026e", FIREBALL, "VAN_EX1_554", "LOOT_309"], "hand": hand,
             "board": [WISP, "VAN_EX1_506", "LOOT_131"]},
            {"hero": "HERO_05", "mana": 10, "max_mana": 10, "deck": [WISP, "LOOT_526t", YETI, "LOOT_106t"], "board": [YETI, "LOOT_134"]}]});
        let mut g = scenario::build_in(rs, &sc).unwrap();
        for _ in 0..30 {
            if g.game_over {
                break;
            }
            g.players[g.current].mana = 10;
            let acts = g.legal_actions();
            let n = (seed as usize + g.turn as usize) % 3;
            let a = acts.iter().find(|a| a["type"] == "choose")
                .or_else(|| acts.iter().filter(|a| a["type"] == "play").nth(n).or_else(|| acts.iter().find(|a| a["type"] == "play")))
                .or_else(|| acts.iter().find(|a| a["type"] == "hero_power"))
                .or_else(|| acts.iter().find(|a| a["type"] == "attack"))
                .or_else(|| acts.iter().find(|a| a["type"] == "end_turn")).cloned();
            let Some(a) = a else { break };
            assert!(g.apply(&Value::Object(a.clone())).ok, "{a:?}");
            assert_eq!(g.script_error.get(), None, "seed {seed}");
        }
    }
}
