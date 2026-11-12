//! The Whispers of the Old Gods pack (packs/og, built by tools/pack.py on The League of Explorers and the packs before
//! it): the cards as on 2016-04-26 (build 12574), C'Thun and its rituals, N'Zoth, Yogg-Saron, Fandral Staghelm and the
//! engine features they need (the game's counts and player hooks, a cast with random choices, both Choose One options,
//! a cost in Health, cards transformed in the hand and the deck, cost changes in the order they came), the older cards
//! of that day, and whole bot games with every deck template. Needs python3 (skipped without it).

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
        let out = std::env::temp_dir().join(format!("og-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/og", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(ruleset::load(&files).expect("the built pack loads"))
    })
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const FIREBALL: &str = "VAN_CS2_029";
const MOONFIRE: &str = "VAN_CS2_008";
const LOOT_HOARDER: &str = "VAN_EX1_096";
const HARVEST_GOLEM: &str = "VAN_EX1_556";
const SEARING: &str = "VAN_CS2_050";
const CTHUN: &str = "OG_280";
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];
const NONE: Id = -1;

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
    fn deck(&self, p: usize) -> Vec<String> {
        self.g.players[p].deck.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn hero(&self, p: usize) -> Id {
        self.g.players[p].hero
    }
    fn hp(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).health()
    }
    fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
    }
    fn count(&self, p: usize, k: &str) -> i64 {
        self.g.players[p].counts.get(k).map_or(0, |v| v.int())
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
    fn choose_play(&mut self, card: &str, choice: i64, target: Id) -> &mut Self {
        let e = self.hand_id(card);
        let last = self.g.players[self.g.current].board.len() as i64;
        self.act(&format!("play {card} ({choice})"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("choice")) == choice && int(a.get("target")) == target
                && (int(a.get("pos")) == -1 || int(a.get("pos")) == last)
        })
    }
    fn can_play(&self, card: &str) -> bool {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e)
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
    fn pick(&mut self, i: usize) -> &mut Self {
        let id = self.g.pending_options()[i];
        self.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == id)
    }
    fn events(&self) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).collect()
    }
}

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(stats(CTHUN), (10, 6, 6), "C'Thun 10 mana until 2023");
    assert_eq!(stats("OG_131"), (7, 4, 6), "Twin Emperor Vek'lor 4/6");
    assert_eq!(stats("OG_302"), (5, 5, 6), "Usher of Souls 5 mana 5/6");
    assert_eq!(stats("OG_121"), (7, 7, 7), "Cho'gall 7 mana");
    assert_eq!(stats("OG_162"), (3, 2, 1), "Disciple of C'Thun 2/1");
    assert_eq!(stats("OG_313"), (3, 2, 2), "Addled Grizzly 3 mana 2/2");
    assert_eq!(c("OG_211").cost, 8, "Call of the Wild 8 mana");
    assert_eq!(c("OG_090").cost, 5, "Cabalist's Tome 5 mana");
    assert_eq!(c("OG_282").cost, 9, "Blade of C'Thun 9 mana");
    assert_eq!(c("OG_034").race, "", "Silithid Swarmer: no tribe until 5.2");
    assert_eq!(c("OG_340").keywords, vec!["TAUNT", "ELUSIVE"]);
    assert_eq!(c("OG_082").spell_power, Some(2));
    assert_eq!(c("OG_024").mana_lock, 2, "Flamewreathed Faceless: Overload (2)");
    // the Classic cards changed by patch 5.0.0.12574, and the Scarab (4.2.0.12051)
    assert_eq!(c("VAN_CS2_084").cost, 1, "Hunter's Mark");
    assert_eq!(c("VAN_CS2_203").cost, 3, "Ironbeak Owl");
    assert_eq!(c("VAN_EX1_005").cost, 5, "Big Game Hunter");
    assert_eq!(stats("VAN_EX1_029"), (1, 1, 1), "Leper Gnome");
    assert_eq!(stats("VAN_NEW1_019"), (2, 2, 2), "Knife Juggler");
    assert_eq!(stats("VAN_EX1_166"), (4, 2, 2), "Keeper of the Grove");
    assert_eq!(c("VAN_EX1_620").cost, 25, "Molten Giant");
    assert_eq!(c("VAN_CS2_233").cost, 4, "Blade Flurry");
    assert_eq!(stats("VAN_EX1_089"), (3, 4, 4), "Arcane Golem");
    assert!(!c("VAN_EX1_089").keywords.contains(&"CHARGE".to_string()));
    assert_eq!(c("VAN_EX1_571").cost, 5, "Force of Nature");
    assert_eq!(c("LOE_009t").race, "BEAST", "the Scarab");
    let og = rs.cards.values().filter(|c| c.set == "OG" && c.collectible).count();
    assert_eq!(og, 134);
}

// --- C'Thun -----------------------------------------------------------------------------------------------------

#[test]
fn rituals_buff_cthun_wherever_it_is() {
    let mut t = scene!({"hand": ["OG_281", CTHUN, "OG_283"], "deck": [WISP, CTHUN]}, {});
    t.play("OG_281", NONE);
    let in_hand = t.hand_id(CTHUN);
    assert_eq!(t.stats(in_hand), (8, 8));
    let in_deck = t.g.players[0].deck[1];
    assert_eq!(t.stats(in_deck), (8, 8), "the deck's C'Thun too");
    assert_eq!(t.count(0, "CTHUN_ATK"), 2);
    t.play("OG_283", NONE);
    assert_eq!(t.stats(in_hand), (10, 10));
    assert!(t.events().iter().any(|e| e["type"] == "cthun" && e["atk"] == 10), "the stats for the pop-up");
    // with 10 Attack the conditional cards glow
    let mut t = scene!({"hand": ["OG_301"]}, {});
    assert!(!t.g.glows(t.hand_id("OG_301")));
    t.g.players[0].counts.insert("CTHUN_ATK", 4i64);
    assert!(t.g.glows(t.hand_id("OG_301")));
    t.play("OG_301", NONE);
    assert_eq!(t.g.e(t.hero(0)).tag("ARMOR"), 10, "Ancient Shieldbearer");
}

#[test]
fn cthun_battlecry_deals_its_attack_one_at_a_time() {
    let mut t = scene!({"hand": [CTHUN]}, {"board": [YETI, YETI]});
    t.g.players[0].counts.insert("CTHUN_ATK", 4i64);
    let c = t.hand_id(CTHUN);
    t.g.buff(c, 4, 4, false);
    t.play(CTHUN, NONE);
    let hits: i64 = t.events().iter().filter(|e| e["type"] == "damage" && e.get("by").and_then(Value::as_str) == Some(CTHUN)).map(|e| int(e.get("amount"))).sum();
    assert_eq!(hits, 10, "10 damage in all");
    assert_eq!(t.stats(t.on_board(0, CTHUN)), (10, 10));
}

#[test]
fn doomcaller_and_geomancer_and_blade() {
    // Doomcaller: a C'Thun that died: a new one with every ritual into the deck
    let mut t = scene!({"board": [CTHUN], "hand": ["OG_255", "OG_284", FIREBALL]}, {});
    t.play("OG_284", NONE);
    assert!(t.g.e(t.on_board(0, CTHUN)).has("TAUNT"), "Twilight Geomancer: Taunt");
    let c = t.on_board(0, CTHUN);
    t.g.em(c).set_tag("TO_DESTROY", true);
    t.end_turn().end_turn();
    let before = t.deck(0).iter().filter(|c| c == &CTHUN).count();
    t.g.players[0].mana = 10;
    t.play("OG_255", NONE);
    assert_eq!(t.deck(0).iter().filter(|c| c == &CTHUN).count(), before + 1);
    let new = *t.g.players[0].deck.iter().find(|&&e| t.g.e(e).card_id == CTHUN).unwrap();
    assert_eq!(t.stats(new), (8, 8));
    assert!(t.g.e(new).has("TAUNT"));
    // Blade of C'Thun: a minion's stats go to C'Thun
    let mut t = scene!({"hand": ["OG_282", CTHUN]}, {"board": [YETI]});
    let y = t.nth(1, 0);
    t.play("OG_282", y);
    assert_eq!(t.stats(t.hand_id(CTHUN)), (10, 11));
}

// --- N'Zoth, Yogg-Saron, Y'Shaarj -----------------------------------------------------------------------------------

#[test]
fn nzoth_brings_back_deathrattle_minions_in_death_order() {
    let mut t = scene!({"board": [LOOT_HOARDER, HARVEST_GOLEM, YETI], "hand": ["OG_133", FIREBALL, FIREBALL, "VAN_CS2_008"]}, {});
    let (golem, hoarder, yeti) = (t.nth(0, 1), t.nth(0, 0), t.nth(0, 2));
    t.play(FIREBALL, golem);
    t.play(FIREBALL, hoarder);
    t.play("VAN_CS2_008", yeti); // a Yeti hurt, not dead
    t.end_turn().end_turn();
    t.g.players[0].mana = 10;
    // the Golem's Damaged Golem has a Deathrattle of its card: none; the Golem and the Hoarder come back in that order
    t.play("OG_133", NONE);
    let b = t.cards(0);
    let i = b.iter().position(|c| c == "OG_133").unwrap();
    assert_eq!(&b[i + 1..], &[HARVEST_GOLEM.to_string(), LOOT_HOARDER.to_string()], "{b:?}");
}

#[test]
fn yogg_saron_casts_a_spell_for_each_spell_cast() {
    let mut t = scene!({"hand": [MOONFIRE, MOONFIRE, MOONFIRE, "OG_134"], "board": [], "deck": FILL}, {"board": [YETI]});
    let y = t.nth(1, 0);
    for _ in 0..3 {
        t.play(MOONFIRE, y);
    }
    assert_eq!(t.count(0, "SPELLS"), 3);
    t.play("OG_134", NONE);
    let casts = t.events().iter().filter(|e| (e["type"] == "cast" && e.get("random") == Some(&json!(true))) || e["type"] == "fizzle").count();
    assert_eq!(casts, 3);
    assert_eq!(t.count(0, "SPELLS"), 3, "Yogg-Saron's spells do not count");
    // a countered spell does not count
    let mut t = scene!({"hand": [MOONFIRE]}, {"secrets": ["VAN_EX1_287"]});
    t.end_turn();
    t.g.players[1].mana = 10;
    let _ = t; // (the opponent's Counterspell fires on our turn only)
    let mut t = scene!({"hand": [MOONFIRE]}, {"secrets": ["VAN_EX1_287"]});
    let h = t.hero(1);
    t.play(MOONFIRE, h);
    assert_eq!(t.count(0, "SPELLS"), 0, "countered");
}

#[test]
fn yogg_saron_many_games_never_fail() {
    // Yogg-Saron with 30 spells cast, over many seeds: every spell of the pool cast at random, no script error
    let Some(rs) = rs() else { return };
    let mut casts = 0;
    for seed in 0..40 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL, "hand": ["OG_134", "OG_087"], "board": [YETI, WISP], "weapon": "VAN_CS2_106"},
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL, "board": [YETI, LOOT_HOARDER, WISP]}]});
        let mut g = scenario::build_in(rs, &sc).unwrap();
        g.players[0].counts.insert("SPELLS", 30i64);
        for card in ["OG_134", "OG_087"] {
            let Some(&e) = g.players[0].hand.iter().find(|&&e| g.e(e).card_id == card) else { continue };
            g.players[0].mana = 10;
            let Some(a) = g.legal_actions().into_iter().find(|a| a["type"] == "play" && int(a.get("entity")) == e) else { continue };
            assert!(g.apply(&Value::Object(a)).ok);
            assert_eq!(g.script_error.get(), None, "seed {seed}");
            if g.game_over {
                break;
            }
        }
        casts += g.history.iter().flat_map(|h| h.events()).filter(|e| e["type"] == "cast" || e["type"] == "fizzle").count();
        // the choices it asked for were made at once
        assert!(g.pending.is_none() || g.game_over, "seed {seed}");
    }
    assert!(casts > 400, "{casts}");
}

#[test]
fn yshaarj_pulls_a_minion_from_the_deck() {
    let mut t = scene!({"board": ["OG_042"], "deck": [YETI, FIREBALL]}, {});
    t.end_turn();
    assert_eq!(t.cards(0), vec!["OG_042", YETI]);
}

// --- Fandral Staghelm, Cho'gall, Shifter Zerus, Renounce Darkness -----------------------------------------------------

#[test]
fn fandral_staghelm_gives_both_choices() {
    let mut t = scene!({"board": ["OG_044"], "hand": ["VAN_EX1_154", "VAN_EX1_165", "VAN_EX1_166"]}, {"board": [YETI, YETI]});
    let e = t.hand_id("VAN_EX1_154");
    let choices: Vec<i64> = t.g.legal_actions().iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).map(|a| int(a.get("choice"))).collect();
    assert!(!choices.is_empty() && choices.iter().all(|&c| c == 2), "{choices:?}");
    let y = t.nth(1, 0);
    let hand = t.hand(0).len();
    t.choose_play("VAN_EX1_154", 2, y); // Wrath: 3 damage, then 1 damage and a card
    assert_eq!(t.g.e(y).health(), 1);
    assert_eq!(t.hand(0).len(), hand, "one card played, one drawn");
    t.choose_play("VAN_EX1_165", 2, NONE);
    assert_eq!(t.cards(0)[1], "OG_044a", "Druid of the Claw: the 4/6 Charge Taunt form");
    let y2 = t.nth(1, 1);
    t.g.give_tag(y2, "DIVINE_SHIELD", false);
    t.g.players[0].mana = 10;
    t.choose_play("VAN_EX1_166", 2, y2);
    assert_eq!(t.g.e(y2).health(), 3, "Keeper of the Grove: Silence first, then 2 damage");
    // without Fandral: two options
    let t = scene!({"hand": ["VAN_EX1_154"]}, {"board": [YETI]});
    let e = t.hand_id("VAN_EX1_154");
    assert!(t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("choice")) == 0));
}

trait GiveTag {
    fn give_tag(&mut self, e: Id, tag: &str, eot: bool);
}
impl GiveTag for Game {
    fn give_tag(&mut self, e: Id, tag: &str, eot: bool) {
        self.em(e).give_tag(tag.to_string(), eot);
    }
}

#[test]
fn chogall_spell_costs_health() {
    let mut t = scene!({"hand": ["OG_121", FIREBALL, "VAN_CS2_032"], "mana": 7}, {});
    t.play("OG_121", NONE);
    assert_eq!(t.g.players[0].mana, 0);
    assert!(t.can_play(FIREBALL));
    let h = t.hero(1);
    t.play(FIREBALL, h);
    assert_eq!(t.hp(0), 26, "4 Health paid");
    assert_eq!(t.hp(1), 24);
    assert!(!t.can_play("VAN_CS2_032"), "only the next spell");
    // Armor first; not playable unless Health and Armor are more than its cost
    let mut t = scene!({"hand": ["OG_121", "VAN_CS2_032"], "mana": 7, "damage": 23, "armor": 0}, {});
    t.play("OG_121", NONE);
    assert!(!t.can_play("VAN_CS2_032"), "7 Health, Flamestrike costs 7");
    t.g.em(t.hero(0)).set_tag("ARMOR", 2i64);
    assert!(t.can_play("VAN_CS2_032"));
    t.play("VAN_CS2_032", NONE);
    assert_eq!((t.hp(0), t.g.e(t.hero(0)).tag("ARMOR")), (2, 0));
}

#[test]
fn shifter_zerus_shifts_in_the_hand() {
    let mut t = scene!({"hand": ["OG_123"]}, {});
    t.end_turn();
    assert_eq!(t.hand(0), vec!["OG_123"], "not on the opponent's turn");
    // the opponent does not see what it became, nor what it was
    let zerus = t.g.players[0].hand[0];
    t.end_turn();
    assert_eq!(api::snapshot(&t.g, 1)["entities"][zerus.to_string()]["card"], "");
    assert_eq!(api::snapshot(&t.g, 0)["entities"][zerus.to_string()]["card"], "OG_123");
    let first = t.hand(0)[0].clone();
    assert_ne!(first, "OG_123");
    let ev: Vec<_> = t.g.history.last().unwrap().events().into_iter().filter(|e| e["type"] == "transform").collect();
    let seen = api::events_for(&t.g, &ev, 1);
    assert_eq!(seen[0]["card"], "", "{seen}");
    t.end_turn().end_turn();
    assert_ne!(t.hand(0)[0], "OG_123");
    assert!(t.g.e(t.g.players[0].hand[0]).enchantments.iter().any(|x| x.get("hooks").and_then(|v| v.as_str()) == Some("ench:zerus")));
}

#[test]
fn renounce_darkness_changes_class() {
    let mut t = scene!({"hero": "HERO_07", "hand": ["OG_118", "VAN_EX1_308", "VAN_CS2_061", YETI], "deck": ["VAN_EX1_310", WISP]}, {});
    t.play("OG_118", NONE);
    let power = t.g.e(t.g.players[0].hero_power).card_id;
    assert_ne!(power, "VAN_HERO_07bp");
    let class = t.g.e(t.g.players[0].hero_power).card.card_class.clone();
    for &e in &t.g.players[0].hand[..2] {
        assert_eq!(t.g.e(e).card.card_class, class);
        assert_eq!(t.g.cost(e), (t.g.e(e).card.cost - 1).max(0));
    }
    assert_eq!(t.hand(0)[2], YETI);
    assert_eq!(t.g.e(t.g.players[0].deck[0]).card.card_class, class);
}

// --- more cards ---------------------------------------------------------------------------------------------------

#[test]
fn forbidden_spells_spend_all_mana() {
    let mut t = scene!({"hand": ["OG_114"], "mana": 6}, {});
    t.play("OG_114", NONE);
    assert_eq!(t.cards(0).len(), 6);
    assert_eq!(t.g.players[0].mana, 0);
    let mut t = scene!({"hand": ["OG_086"], "mana": 5}, {"board": [YETI]});
    let y = t.nth(1, 0);
    t.play("OG_086", y);
    assert_eq!(t.g.e(y).health(), 0);
    let mut t = scene!({"hand": ["OG_051"], "mana": 5}, {});
    t.play("OG_051", NONE);
    assert_eq!(t.stats(t.nth(0, 0)), (5, 5));
}

#[test]
fn thing_from_below_and_evolve_and_hallazeal() {
    let mut t = scene!({"hand": ["OG_028", SEARING, SEARING], "hero": "HERO_02"}, {});
    assert_eq!(t.cost("OG_028"), 6);
    t.play(SEARING, NONE).play(SEARING, NONE);
    assert_eq!(t.cost("OG_028"), 4);
    t.act("hero power", |a| a["type"] == "hero_power");
    assert_eq!(t.cost("OG_028"), 3, "a Totem of the Hero Power counts");
    // Evolve: (1) more
    let mut t = scene!({"hand": ["OG_027"], "board": [YETI, WISP]}, {});
    t.play("OG_027", NONE);
    let rs = rs().unwrap();
    assert_eq!(rs.card(&t.cards(0)[0]).cost, 5);
    assert_eq!(rs.card(&t.cards(0)[1]).cost, 1);
    // Hallazeal: your spells' damage heals your hero
    let mut t = scene!({"board": ["OG_209"], "hand": ["VAN_CS2_032"], "damage": 10}, {"board": [YETI, YETI]});
    t.play("VAN_CS2_032", NONE);
    assert_eq!(t.hp(0), 28, "4 damage to two minions: 8 Health back");
}

#[test]
fn older_cards_of_april_2016() {
    // Master of Disguise: Stealth until your next turn
    let mut t = scene!({"board": [YETI], "hand": ["VAN_NEW1_014"]}, {});
    let y = t.nth(0, 0);
    t.play("VAN_NEW1_014", y);
    assert!(t.g.e(y).has("STEALTH"));
    t.end_turn();
    assert!(t.g.e(y).has("STEALTH"));
    t.end_turn();
    assert!(!t.g.e(y).has("STEALTH"));
    // Blade Flurry: enemy minions only
    let mut t = scene!({"hand": ["VAN_CS2_233"], "weapon": "VAN_CS2_106"}, {"board": [YETI]});
    t.play("VAN_CS2_233", NONE);
    assert_eq!(t.hp(1), 30);
    assert_eq!(t.g.e(t.nth(1, 0)).health(), 2);
    // Force of Nature: three plain 2/2 Treants that stay
    let mut t = scene!({"hand": ["VAN_EX1_571"]}, {});
    t.play("VAN_EX1_571", NONE);
    assert_eq!(t.cards(0), vec!["VAN_EX1_tk9"; 3]);
    t.end_turn();
    assert_eq!(t.cards(0).len(), 3);
    // Ancient of Lore: one card
    let mut t = scene!({"hand": ["VAN_NEW1_008"]}, {});
    t.choose_play("VAN_NEW1_008", 0, NONE);
    assert_eq!(t.hand(0).len(), 1);
    // Cabal Shadow Priest with a full board: the minion is destroyed
    let mut t = scene!({"board": [WISP, WISP, WISP, WISP, WISP, WISP], "hand": ["VAN_EX1_091"]}, {"board": [WISP]});
    let w = t.nth(1, 0);
    t.play("VAN_EX1_091", w);
    assert_eq!(t.cards(1).len(), 0);
}

#[test]
fn cost_changes_in_the_order_they_came() {
    let mut t = scene!({"board": ["LOE_038", "BRM_028"], "hand": [YETI, WISP]}, {});
    let yeti = t.hand_id(YETI);
    t.end_turn();
    assert_eq!(t.g.cost(yeti), 4, "Naga sets 5, then Thaurissan's -1");
}

#[test]
fn more_cards() {
    let rs = match rs() {
        Some(r) => r,
        None => return,
    };
    // Call of the Wild
    let mut t = scene!({"hand": ["OG_211"]}, {});
    t.play("OG_211", NONE);
    assert_eq!(t.cards(0), vec!["VAN_NEW1_034", "VAN_NEW1_033", "VAN_NEW1_032"]);
    // Herald Volazj: 1/1 copies
    let mut t = scene!({"board": [YETI, WISP], "hand": ["OG_316"]}, {});
    t.play("OG_316", NONE);
    assert_eq!(t.cards(0), vec![YETI, WISP, "OG_316", YETI, WISP]);
    assert_eq!(t.stats(t.nth(0, 3)), (1, 1));
    // Blood of the Ancient One: two merge
    let mut t = scene!({"board": ["OG_173", "OG_173"]}, {});
    t.end_turn();
    assert_eq!(t.cards(0), vec!["OG_173a"]);
    // Twin Emperor Vek'lor with 10 Attack
    let mut t = scene!({"hand": ["OG_131"]}, {});
    t.g.players[0].counts.insert("CTHUN_ATK", 4i64);
    t.play("OG_131", NONE);
    assert_eq!(t.cards(0), vec!["OG_131", "OG_319"]);
    // Deathwing, Dragonlord
    let mut t = scene!({"board": ["OG_317"], "hand": [FIREBALL, "VAN_EX1_043", "VAN_NEW1_023"]}, {});
    let d = t.nth(0, 0);
    t.g.em(d).set_tag("TO_DESTROY", true);
    t.play(FIREBALL, t.hero(1));
    assert_eq!(t.cards(0), vec!["VAN_EX1_043", "VAN_NEW1_023"]);
    // Ancient Harbinger: a 10-Cost minion into the hand, not a draw
    let mut t = scene!({"board": ["OG_290"], "deck": [WISP, "OG_141", WISP, WISP]}, {});
    t.end_turn().end_turn();
    assert!(t.hand(0).contains(&"OG_141".to_string()));
    assert!(t.events().iter().any(|e| e["type"] == "to_hand"));
    // Nerubian Prophet: (1) less each turn in the hand
    let mut t = scene!({"hand": ["OG_138"]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.cost("OG_138"), 5);
    // Steward of Darkshire, Darkshire Councilman, Addled Grizzly
    let mut t = scene!({"board": ["OG_310", "OG_113", "OG_313"], "hand": [WISP]}, {});
    t.play(WISP, NONE);
    let w = t.nth(0, 3);
    assert!(t.g.e(w).has("DIVINE_SHIELD"));
    assert_eq!(t.stats(w), (2, 2));
    assert_eq!(t.stats(t.nth(0, 1)), (2, 5));
    // Infest: N'Zoth does not count it; the Beast comes
    let mut t = scene!({"board": [WISP], "hand": ["OG_045", MOONFIRE]}, {});
    t.play("OG_045", NONE);
    let w = t.nth(0, 0);
    t.play(MOONFIRE, w);
    let beast = &t.hand(0)[0];
    assert_eq!(rs.card(beast).race, "BEAST");
    // Shadowcaster: a 1/1 copy that costs (1)
    let mut t = scene!({"board": [YETI], "hand": ["OG_291"]}, {});
    let y = t.nth(0, 0);
    t.play("OG_291", y);
    let c = t.g.players[0].hand[0];
    assert_eq!((t.stats(c), t.g.cost(c)), ((1, 1), 1));
    // Spreading Madness: 9 damage among all characters
    let mut t = scene!({"hand": ["OG_116"]}, {});
    t.play("OG_116", NONE);
    assert_eq!(t.hp(0) + t.hp(1), 51);
    // Embrace the Shadow
    let mut t = scene!({"hand": ["OG_104"]}, {});
    t.play("OG_104", NONE);
    t.act("hero power", |a| a["type"] == "hero_power" && int(a.get("target")) != NONE);
    // Validated Doomsayer, Scaled Nightmare
    let mut t = scene!({"board": ["OG_200", "OG_271"]}, {});
    t.end_turn().end_turn();
    assert_eq!(t.stats(t.nth(0, 0)).0, 7);
    assert_eq!(t.stats(t.nth(0, 1)).0, 4);
    // Giant Sand Worm: attacks again after a kill
    let mut t = scene!({"board": ["OG_308"]}, {"board": [WISP, WISP]});
    let (worm, w1) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(worm, w1);
    let w2 = t.nth(1, 0);
    t.attack(worm, w2);
    assert!(t.cards(1).is_empty());
    // A Light in the Darkness: the Discovered minion +1/+1
    let mut t = scene!({"hero": "HERO_04", "hand": ["OG_311"]}, {});
    t.play("OG_311", NONE).pick(0);
    let m = t.g.players[0].hand[0];
    assert_eq!(t.stats(m), (rs.card(t.g.e(m).card_id).attack + 1, rs.card(t.g.e(m).card_id).health + 1));
    // Eater of Secrets
    let mut t = scene!({"hand": ["OG_254"]}, {"secrets": ["VAN_EX1_287", "VAN_EX1_289"]});
    t.play("OG_254", NONE);
    assert_eq!(t.stats(t.nth(0, 0)), (4, 6));
    assert!(t.g.players[1].secrets.is_empty());
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/og/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30);
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
    assert!(decks.len() >= 10);
    let mut over = 0;
    let mut played = std::collections::BTreeSet::new();
    let (mut rituals, mut yogg, mut nzoth, mut evolved) = (0, 0, 0, 0);
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
                    if e["type"] == "play" && card.starts_with("OG") {
                        played.insert(card.to_string());
                    }
                    rituals += (e["type"] == "cthun") as usize;
                    yogg += (e["type"] == "cast" && e.get("by").and_then(Value::as_str) == Some("OG_134")) as usize;
                    nzoth += (e["type"] == "summon" && e.get("by").and_then(Value::as_str) == Some("OG_133")) as usize;
                    evolved += (e["type"] == "transform" && matches!(e.get("by").and_then(Value::as_str), Some("OG_027" | "OG_328"))) as usize;
                }
            }
        }
    }
    assert!(over >= decks.len(), "most games end");
    eprintln!("OG cards played: {}: {played:?}; C'Thun rituals {rituals}, Yogg-Saron's spells {yogg}, N'Zoth's minions {nzoth}, evolved {evolved}", played.len());
    assert!(played.len() >= 25, "{played:?}");
    assert!(rituals > 0);
}
