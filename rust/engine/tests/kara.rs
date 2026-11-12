//! The One Night in Karazhan pack (packs/kara, built by tools/pack.py on Whispers of the Old Gods and the packs before
//! it): the cards as on 2016-08-11 (build 13921), Prince Malchezaar's legendaries "when the game starts" (after the
//! mulligan), Medivh's Atiesh and the portals, Barnes, Moat Lurker, Fool's Bane's unlimited attacks, the cards that
//! glow, the older cards of that day, and whole bot games with every deck template. Needs python3 (skipped without it).


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
        let out = std::env::temp_dir().join(format!("kara-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/kara", "-o"]).arg(&out).output().ok()?;
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

const SECRET: &str = "VAN_EX1_287"; // Counterspell
const KOBOLD: &str = "VAN_CS2_142";
const SOULFIRE: &str = "VAN_EX1_308";
const SWORD: &str = "VAN_EX1_366";

fn card_of(t: &T, e: Id) -> String {
    t.g.e(e).card_id.to_string()
}

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(stats("KAR_114"), (4, 3, 4), "Barnes 4 mana until 2019");
    assert_eq!(stats("KAR_061"), (7, 4, 6), "The Curator 7 mana");
    assert_eq!(stats("KAR_057"), (6, 4, 4), "Ivory Knight 6 mana");
    assert_eq!(c("KAR_076").cost, 7, "Firelands Portal 7 mana, 5 damage");
    assert_eq!(c("KAR_077").cost, 4, "Silvermoon Portal 4 mana");
    assert_eq!(c("KAR_091").cost, 5, "Ironforge Portal 5 mana");
    assert_eq!(stats("KAR_065"), (6, 5, 5), "Menagerie Warden 6 mana 5/5");
    assert_eq!(stats("KAR_069"), (1, 1, 1), "Swashburglar 1/1");
    assert_eq!(stats("KAR_009"), (1, 1, 1), "Babbling Book 1/1");
    assert_eq!(c("KAR_021").cost, 4, "Wicked Witchdoctor 4 mana");
    assert_eq!(c("KAR_089").cost, 1, "Malchezaar's Imp 1 mana");
    assert_eq!(c("KAR_204").cost, 5, "Onyx Bishop 5 mana");
    assert_eq!(stats("KAR_205"), (3, 3, 3), "Silverware Golem 3/3");
    assert_eq!(stats("KAR_062"), (2, 1, 3), "Netherspite Historian 1/3");
    assert_eq!((c("KAR_063").cost, c("KAR_063").attack), (1, 1), "Spirit Claws 1 mana");
    assert_eq!(c("KAR_036").race, "", "Arcane Anomaly: no tribe until 2017");
    assert_eq!(c("KAR_033").race, "DRAGON");
    assert_eq!(c("KAR_028").keywords, vec!["UNLIMITED_ATTACKS", "CANNOT_ATTACK_HEROES"]);
    // older cards of that day: the tokens of patch 6.0.0.13921 and the Silithid Swarmer of 5.2.0.13619
    for (id, cost) in [("VAN_CS2_tk1", 1), ("VAN_EX1_554t", 1), ("VAN_EX1_506a", 1), ("VAN_NEW1_026t", 1), ("VAN_tt_010a", 1),
        ("VAN_EX1_tk9", 2), ("FP1_007t", 4), ("AT_036t", 4), ("OG_202c", 2), ("OG_249a", 2), ("OG_314b", 2), ("VAN_EX1_finkle", 3)] {
        assert_eq!(c(id).cost, cost, "{id}");
    }
    assert_eq!(c("FP1_019t").cost, 1, "Poison Seeds' Treant stayed 1");
    assert_eq!(c("OG_034").race, "BEAST", "Silithid Swarmer");
    let kara: Vec<_> = rs.cards.values().filter(|c| c.set == "KARA").collect();
    assert_eq!(kara.iter().filter(|c| c.collectible).count(), 45);
    assert_eq!(kara.iter().filter(|c| !c.collectible).count(), 12);
}

// --- Prince Malchezaar: the game's start --------------------------------------------------------------------------

fn mulligan_both(g: &mut Game) {
    for p in 0..2 {
        let a = g.legal_actions().into_iter().find(|a| a["type"] == "mulligan" && int(a.get("player")) == p as i64
            && a.get("replace").and_then(Value::as_array).is_some_and(|r| r.is_empty())).expect("keep all");
        assert!(g.apply(&Value::Object(a)).ok);
    }
}

#[test]
fn malchezaar_adds_five_legendaries_after_the_mulligan() {
    let Some(rs) = rs() else { return };
    let mut deck: Vec<String> = vec![YETI.to_string(); 28];
    deck.push("KAR_096".into());
    deck.push("VAN_EX1_116".into()); // Leeroy Jenkins: never a second one
    let plain: Vec<String> = vec![YETI.to_string(); 30];
    let mut seen = std::collections::BTreeSet::new();
    for seed in 0..30 {
        let mut g = Game::new_in(rs, "HERO_08", &deck, "HERO_01", &plain, seed, 0, true);
        let before = g.players[0].deck.len();
        assert_eq!(g.players[1].deck.len(), 26);
        mulligan_both(&mut g);
        assert_eq!(g.script_error.get(), None);
        // after the mulligan, before the first draw: 5 more in the deck (the first player has drawn 1 since)
        let all: Vec<String> = g.players[0].deck.iter().chain(&g.players[0].hand).map(|&e| g.e(e).card_id.to_string()).collect();
        assert_eq!(g.players[0].deck.len() + 1, before + 5, "seed {seed}");
        let added: Vec<&String> = all.iter().filter(|c| c.as_str() != YETI && c.as_str() != "KAR_096" && c.as_str() != "VAN_EX1_116"
            && c.as_str() != "GAME_005").collect();
        assert_eq!(added.len(), 5, "seed {seed}: {all:?}");
        for c in &added {
            let card = rs.card(c);
            assert!(card.collectible && card.rarity == "LEGENDARY" && card.kind == "MINION", "{c}");
            assert!(card.card_class == "MAGE" || card.card_class == "NEUTRAL", "{c}");
            assert_eq!(all.iter().filter(|x| x == c).count(), 1, "one copy of {c}");
            seen.insert(c.to_string());
        }
        assert_eq!(g.players[1].deck.len(), 26, "the other player's deck is as it was");
        // the opponent never sees which
        let h = g.history.iter().find(|h| h.events().iter().any(|e| e["type"] == "game_start")).expect("game_start");
        let theirs = api::events_for(&g, &h.events(), 1);
        for e in theirs.as_array().unwrap().iter().filter(|e| e["type"] == "add_to_deck") {
            assert_eq!(e["card"], "", "hidden from the opponent");
        }
    }
    assert!(seen.len() > 20, "{seen:?}");
    // no Malchezaar: nothing is added
    let mut g = Game::new_in(rs, "HERO_08", &plain, "HERO_01", &plain, 3, 0, true);
    mulligan_both(&mut g);
    assert_eq!(g.players[0].deck.len(), 26);
    assert!(!g.history.iter().flat_map(|h| h.events()).any(|e| e["type"] == "add_to_deck"));
}

// --- Medivh and Atiesh, the portals --------------------------------------------------------------------------------

#[test]
fn atiesh_summons_a_minion_of_the_spells_cost() {
    let mut t = scene!({"hand": ["KAR_097", FIREBALL, "VAN_EX1_608", FIREBALL]}, {});
    t.play("KAR_097", NONE);
    let w = t.g.players[0].weapon.expect("Atiesh");
    assert_eq!(card_of(&t, w), "KAR_097t");
    t.g.players[0].mana = 10;
    let h = t.hero(1);
    t.play(FIREBALL, h);
    let summoned: Vec<Id> = t.g.players[0].board.iter().copied().filter(|&m| card_of(&t, m) != "KAR_097").collect();
    assert_eq!(summoned.len(), 1);
    assert_eq!(t.g.e(summoned[0]).card.cost, 4, "a 4-Cost minion");
    assert_eq!(t.g.e(w).tag("DURABILITY"), 2);
    // a cheaper spell: the cost paid (Sorcerer's Apprentice: Fireball costs 3)
    t.g.players[0].mana = 10;
    t.play("VAN_EX1_608", NONE);
    t.play(FIREBALL, h);
    let last = *t.g.players[0].board.last().unwrap();
    assert_eq!(t.g.e(last).card.cost, 3, "a 3-Cost minion");
    assert_eq!(t.g.e(w).tag("DURABILITY"), 1);
}

#[test]
fn atiesh_with_a_full_board_or_countered() {
    let mut t = scene!({"hand": [FIREBALL], "weapon": "KAR_097t", "board": [WISP, WISP, WISP, WISP, WISP, WISP, WISP]}, {});
    let w = t.g.players[0].weapon.unwrap();
    let h = t.hero(1);
    t.play(FIREBALL, h);
    assert_eq!(t.g.e(w).tag("DURABILITY"), 3, "a full board: no Durability lost");
    let mut t = scene!({"hand": [FIREBALL], "weapon": "KAR_097t"}, {"secrets": [SECRET]});
    let w = t.g.players[0].weapon.unwrap();
    let h = t.hero(1);
    t.play(FIREBALL, h);
    assert!(t.g.players[0].board.is_empty(), "countered: nothing");
    assert_eq!(t.g.e(w).tag("DURABILITY"), 3);
}

#[test]
fn portals_hit_then_summon() {
    let mut t = scene!({"hand": ["KAR_076", "KAR_073", "KAR_091", "KAR_077", "KAR_075"]}, {"board": [YETI, WISP]});
    let y = t.nth(1, 0);
    t.play("KAR_076", y);
    assert_eq!(t.g.e(t.g.players[0].board[0]).card.cost, 5);
    assert!(t.g.players[1].board.iter().all(|&m| m != y), "5 damage killed the Yeti");
    t.g.players[0].mana = 10;
    t.play("KAR_073", NONE);
    assert!(t.g.players[1].board.is_empty(), "Maelstrom Portal: 1 to each enemy minion");
    assert_eq!(t.g.e(t.g.players[0].board[1]).card.cost, 1);
    assert_eq!(t.g.players[0].board.len(), 2, "the summoned minion is not hit");
    t.g.players[0].mana = 10;
    t.play("KAR_091", NONE);
    assert_eq!(t.g.e(t.hero(0)).tag("ARMOR"), 4);
    assert_eq!(t.g.e(t.g.players[0].board[2]).card.cost, 4);
    t.g.players[0].mana = 10;
    let m = t.nth(0, 0);
    let before = t.stats(m);
    t.play("KAR_077", m);
    assert_eq!(t.stats(m), (before.0 + 2, before.1 + 2));
    assert_eq!(t.g.e(t.g.players[0].board[3]).card.cost, 2);
    t.g.players[0].mana = 10;
    let me = t.hero(0);
    t.g.damage(NONE, me, 10);
    t.play("KAR_075", me);
    assert_eq!(t.hp(0), 30, "4 of the 10 damage went to Ironforge Portal's Armor: 24 + 6");
    assert_eq!(t.g.e(t.g.players[0].board[4]).card.cost, 6);
}

#[test]
fn random_cards_never_fail() {
    // portals, Atiesh, Babbling Book, Swashburglar, Barnes and Discover over many seeds
    let Some(rs) = rs() else { return };
    for seed in 0..40 {
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": "HERO_04", "mana": 10, "max_mana": 10, "deck": ["KAR_096", "OG_280", YETI, "VAN_EX1_116"],
             "hand": ["KAR_097", "KAR_076", "KAR_009", "KAR_069", "KAR_114", "KAR_057"], "board": [WISP]},
            {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL, "board": [YETI]}]});
        let mut g = scenario::build_in(rs, &sc).unwrap();
        for _ in 0..12 {
            g.players[0].mana = 10;
            let a = g.legal_actions().into_iter().find(|a| a["type"] == "play" || a["type"] == "choose");
            let Some(a) = a else { break };
            assert!(g.apply(&Value::Object(a)).ok);
            assert_eq!(g.script_error.get(), None, "seed {seed}");
        }
    }
}

// --- the other legendaries ----------------------------------------------------------------------------------------

#[test]
fn barnes_summons_a_1_1_copy_from_the_deck() {
    let mut t = scene!({"hand": ["KAR_114"], "deck": [YETI, FIREBALL, "VAN_EX1_556"], "weapon": SWORD}, {});
    t.play("KAR_114", NONE);
    assert_eq!(t.g.players[0].board.len(), 2);
    let c = t.nth(0, 1);
    assert!(card_of(&t, c) == YETI || card_of(&t, c) == "VAN_EX1_556");
    assert_eq!(t.stats(c), (1, 1), "1/1 after Sword of Justice too (as before patch 7.1)");
    assert_eq!(t.deck(0).len(), 3, "the card stays in the deck");
    // a Harvest Golem copy keeps its Deathrattle
    let mut t = scene!({"hand": ["KAR_114"], "deck": ["VAN_EX1_556"]}, {});
    t.play("KAR_114", NONE);
    let c = t.nth(0, 1);
    t.g.em(c).set_tag("TO_DESTROY", true);
    t.end_turn();
    assert!(t.cards(0).contains(&"VAN_skele21".to_string()), "{:?}", t.cards(0));
}

#[test]
fn moroes_curator_and_onyx_bishop() {
    let mut t = scene!({"hand": ["KAR_044"]}, {});
    t.play("KAR_044", NONE);
    assert!(t.g.e(t.nth(0, 0)).has("STEALTH"));
    t.end_turn();
    assert_eq!(t.cards(0), vec!["KAR_044", "KAR_044a"]);
    // The Curator: a Beast, a Dragon and a Murloc from the deck
    let mut t = scene!({"hand": ["KAR_061"], "deck": [WISP, "VAN_CS2_120", "VAN_EX1_116", "BRM_004", "VAN_EX1_506", "VAN_CS2_172"]}, {});
    t.play("KAR_061", NONE);
    let hand = t.hand(0);
    assert!(hand.contains(&"BRM_004".to_string()), "the Dragon (Twilight Whelp): {hand:?}");
    assert!(hand.contains(&"VAN_EX1_506".to_string()), "the Murloc");
    assert!(hand.iter().any(|c| c == "VAN_CS2_120" || c == "VAN_CS2_172"), "a Beast");
    assert_eq!(hand.len(), 3);
    // Onyx Bishop: a friendly minion that died this game, fresh, at the right end
    let mut t = scene!({"hand": [FIREBALL, "KAR_204"], "board": [YETI, WISP]}, {});
    let y = t.nth(0, 0);
    t.g.buff(y, 5, 5, false);
    t.g.em(y).set_tag("TO_DESTROY", true);
    t.end_turn().end_turn();
    t.g.players[0].mana = 10;
    t.play("KAR_204", NONE);
    let last = *t.g.players[0].board.last().unwrap();
    assert_eq!((card_of(&t, last), t.stats(last)), (YETI.to_string(), (4, 5)));
}

#[test]
fn moat_lurker_resummons_the_minion_on_its_side() {
    let mut t = scene!({"hand": ["KAR_041", FIREBALL]}, {"board": [YETI, WISP]});
    let y = t.nth(1, 0);
    t.play("KAR_041", y);
    assert_eq!(t.cards(1), vec![WISP]);
    let l = t.on_board(0, "KAR_041");
    t.g.em(l).set_tag("TO_DESTROY", true);
    t.end_turn();
    assert!(t.cards(1).contains(&YETI.to_string()), "back for its owner: {:?}", t.cards(1));
    // silenced: nothing comes back
    let mut t = scene!({"hand": ["KAR_041", "VAN_EX1_332"]}, {"board": [YETI]});
    let y = t.nth(1, 0);
    t.play("KAR_041", y);
    let l = t.on_board(0, "KAR_041");
    t.play("VAN_EX1_332", l);
    t.g.em(l).set_tag("TO_DESTROY", true);
    t.end_turn();
    assert!(t.cards(1).is_empty(), "{:?}", t.cards(1));
}

#[test]
fn unearthed_raptor_copies_what_moat_lurker_holds() {
    let mut t = scene!({"hand": ["KAR_041", "LOE_019", SOULFIRE, SOULFIRE]}, {"board": [YETI, WISP]});
    let y = t.nth(1, 0);
    t.play("KAR_041", y);
    let l = t.on_board(0, "KAR_041");
    t.play("LOE_019", l);
    let r = t.on_board(0, "LOE_019");
    t.play(SOULFIRE, r);
    assert!(!t.cards(0).contains(&"LOE_019".to_string()), "the Raptor died");
    assert_eq!(t.cards(1), vec![WISP, YETI], "the Raptor's copy brought the Yeti back for its owner");
    assert!(t.cards(0).contains(&"KAR_041".to_string()), "the Lurker still holds its own");
    // the Raptor's copy of a Deathrattle with nothing stored: nothing
    let mut t = scene!({"hand": ["LOE_019", SOULFIRE], "board": ["KAR_041"]}, {"board": [WISP]});
    let l = t.nth(0, 0);
    t.play("LOE_019", l);
    let r = t.on_board(0, "LOE_019");
    t.play(SOULFIRE, r);
    assert_eq!(t.cards(1), vec![WISP]);
}

// --- weapons ---------------------------------------------------------------------------------------------------------

#[test]
fn fools_bane_attacks_minions_any_number_of_times() {
    let mut t = scene!({"weapon": "KAR_028"}, {"board": [YETI, YETI, YETI]});
    let me = t.hero(0);
    let foe = t.hero(1);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == me && int(a.get("defender")) == foe),
        "can't attack heroes");
    for i in 0..3 {
        let m = t.nth(1, i);
        t.attack(me, m);
    }
    assert_eq!(t.g.e(t.hero(0)).tag("ATTACKS"), 3);
    // another weapon after Fool's Bane's attacks: no more attacks this turn
    let mut t = scene!({"weapon": "KAR_028", "hand": ["VAN_CS2_106"]}, {"board": [YETI]});
    let (me, m) = (t.hero(0), t.nth(1, 0));
    t.attack(me, m);
    t.play("VAN_CS2_106", NONE);
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == me));
}

#[test]
fn spirit_claws_with_spell_damage() {
    let mut t = scene!({"hand": ["KAR_063", KOBOLD]}, {});
    t.play("KAR_063", NONE);
    let w = t.g.players[0].weapon.unwrap();
    assert_eq!(t.g.e(w).atk(), 1);
    t.play(KOBOLD, NONE);
    assert_eq!(t.g.e(w).atk(), 3);
    assert_eq!(t.g.attack_value(t.hero(0)), 3);
}

// --- conditions and counts -------------------------------------------------------------------------------------------

#[test]
fn dragons_and_secrets_light_the_cards() {
    for c in ["KAR_010", "KAR_033", "KAR_062", "KAR_092", "KAR_037"] {
        let t = scene!({"hand": [c, WISP]}, {"board": [WISP, YETI]});
        assert!(!t.g.glows(t.hand_id(c)), "{c}");
    }
    let mut t = scene!({"hand": ["KAR_010", "KAR_033", "KAR_062", "BRM_004"]}, {"board": [WISP, YETI]});
    assert!(t.g.glows(t.hand_id("KAR_010")) && t.g.glows(t.hand_id("KAR_033")) && t.g.glows(t.hand_id("KAR_062")));
    t.play("KAR_010", NONE);
    assert_eq!(t.cards(0), vec!["KAR_010a", "KAR_010", "KAR_010a"]);
    let w = t.nth(1, 0);
    t.play("KAR_033", w);
    assert_eq!(t.cards(1), vec![YETI], "Book Wyrm destroys a minion with 3 or less Attack");
    t.g.players[0].mana = 10;
    t.play("KAR_062", NONE);
    let opts = t.g.pending_options();
    assert_eq!(opts.len(), 3);
    assert!(opts.iter().all(|&o| t.g.e(o).card.race == "DRAGON"));
    t.pick(0);
    // a Secret
    let mut t = scene!({"hand": ["KAR_092", "KAR_037"], "secrets": ["VAN_EX1_287"]}, {});
    assert!(t.g.glows(t.hand_id("KAR_092")) && t.g.glows(t.hand_id("KAR_037")));
    let h = t.hero(1);
    t.play("KAR_092", h);
    assert_eq!(t.hp(1), 27);
    t.play("KAR_037", NONE);
    let a = t.on_board(0, "KAR_037");
    assert_eq!(t.stats(a), (4, 7));
    assert!(t.g.e(a).has("TAUNT"));
}

#[test]
fn arcane_giant_and_spell_triggers() {
    let mut t = scene!({"hand": ["KAR_711", "KAR_036", "KAR_035", "KAR_021", MOONFIRE, MOONFIRE]}, {});
    assert_eq!(t.cost("KAR_711"), 12);
    t.play("KAR_036", NONE).play("KAR_035", NONE);
    t.g.players[0].mana = 10;
    t.play("KAR_021", NONE);
    let me = t.hero(0);
    t.g.damage(NONE, me, 10);
    let h = t.hero(1);
    t.play(MOONFIRE, h);
    assert_eq!(t.cost("KAR_711"), 11);
    assert_eq!(t.stats(t.on_board(0, "KAR_036")), (2, 2), "Arcane Anomaly +1 Health");
    assert_eq!(t.hp(0), 23, "Priest of the Feast restores 3");
    assert_eq!(t.g.players[0].board.len(), 4, "Wicked Witchdoctor: a Totem");
    let totem = t.nth(0, 3);
    assert_eq!(t.g.e(totem).card.race, "TOTEM");
}

#[test]
fn hunter_rogue_and_warlock_cards() {
    // Cloaked Huntress: Secrets cost (0); Cat Trick after the opponent's spell
    let mut t = scene!({"hand": ["KAR_006", "KAR_004"]}, {"hand": [MOONFIRE]});
    t.play("KAR_006", NONE);
    assert_eq!(t.cost("KAR_004"), 0);
    t.play("KAR_004", NONE).end_turn();
    let h = t.hero(0);
    t.play(MOONFIRE, h);
    assert!(t.cards(0).contains(&"KAR_004a".to_string()));
    // Ethereal Peddler: other class cards (not neutral, not Rogue) cost (2) less
    let mut t = scene!({"hero": "HERO_03", "hand": ["KAR_070", FIREBALL, "VAN_CS2_072", YETI]}, {});
    t.play("KAR_070", NONE);
    assert_eq!((t.cost(FIREBALL), t.cost("VAN_CS2_072"), t.cost(YETI)), (2, 0, 4));
    // Swashburglar: a card of the opponent's class
    let mut t = scene!({"hand": ["KAR_069"]}, {"hero": "HERO_02"});
    t.play("KAR_069", NONE);
    let got = t.hand(0)[0].clone();
    assert_eq!(t.g.rs.card(&got).card_class, "SHAMAN");
    // Silverware Golem summons itself when discarded; Malchezaar's Imp draws
    let mut t = scene!({"hero": "HERO_07", "hand": ["KAR_089", SOULFIRE, "KAR_205"], "deck": [WISP, WISP, WISP]}, {});
    t.play("KAR_089", NONE);
    let h = t.hero(1);
    t.play(SOULFIRE, h);
    assert!(t.cards(0).contains(&"KAR_205".to_string()), "{:?}", t.cards(0));
    assert_eq!(t.hand(0), vec![WISP], "the Imp drew a card");
}

#[test]
fn other_cards() {
    // Violet Illusionist: Immune on its owner's turn only
    let mut t = scene!({"hand": ["KAR_712"]}, {});
    t.play("KAR_712", NONE);
    assert!(t.g.e(t.hero(0)).has("IMMUNE"));
    t.end_turn();
    assert!(!t.g.e(t.hero(1)).has("IMMUNE") && !t.g.e(t.hero(0)).has("IMMUNE"));
    // Protect the King!, Kara Kazham!, Menagerie Warden, Zoobot, Purify, Ivory Knight
    let mut t = scene!({"hero": "HERO_01", "hand": ["KAR_026"]}, {"board": [WISP, WISP, WISP]});
    t.play("KAR_026", NONE);
    assert_eq!(t.cards(0), vec!["KAR_026t"; 3]);
    let mut t = scene!({"hero": "HERO_07", "hand": ["KAR_025"]}, {});
    t.play("KAR_025", NONE);
    assert_eq!(t.cards(0), vec!["KAR_025a", "KAR_025b", "KAR_025c"]);
    let mut t = scene!({"hero": "HERO_06", "hand": ["KAR_065", "KAR_095"], "board": ["VAN_CS2_120", "VAN_EX1_506", WISP]}, {});
    let r = t.nth(0, 0);
    t.g.buff(r, 2, 0, false);
    t.play("KAR_065", r);
    let copy = t.nth(0, 4);
    assert_eq!((card_of(&t, copy), t.stats(copy)), ("VAN_CS2_120".to_string(), (4, 3)));
    t.play("KAR_095", NONE);
    let murloc = t.on_board(0, "VAN_EX1_506");
    assert_eq!(t.stats(murloc), (3, 2), "Zoobot: the Murloc +1/+1");
    let mut t = scene!({"hero": "HERO_09", "hand": ["KAR_013"], "board": [YETI]}, {});
    let y = t.nth(0, 0);
    t.play("KAR_013", y);
    assert!(t.g.e(y).silenced);
    assert_eq!(t.hand(0).len(), 1);
    let mut t = scene!({"hero": "HERO_04", "hand": ["KAR_057"]}, {});
    let me = t.hero(0);
    t.g.damage(NONE, me, 20);
    t.play("KAR_057", NONE);
    let opts = t.g.pending_options();
    assert!(opts.iter().all(|&o| t.g.e(o).kind() == "SPELL"));
    let cost = t.g.e(opts[0]).card.cost;
    t.pick(0);
    assert_eq!(t.hp(0), (10 + cost).min(30));
    // Pantry Spider, Arcanosmith, Runic Egg, Deadly Fork, Kindly Grandmother
    let mut t = scene!({"hand": ["KAR_030a", "KAR_710"], "board": ["KAR_029", "KAR_094", "KAR_005"]}, {});
    t.play("KAR_030a", NONE).play("KAR_710", NONE);
    assert!(t.cards(0).contains(&"KAR_030".to_string()) && t.cards(0).contains(&"KAR_710m".to_string()));
    for c in ["KAR_029", "KAR_094", "KAR_005"] {
        let m = t.on_board(0, c);
        t.g.em(m).set_tag("TO_DESTROY", true);
    }
    t.end_turn();
    assert!(t.cards(0).contains(&"KAR_005a".to_string()));
    assert!(t.hand(0).contains(&"KAR_094a".to_string()));
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/kara/decks")).unwrap().map(|f| f.unwrap().path()).collect();
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
    let (mut portals, mut atiesh, mut legendaries, mut barnes) = (0, 0, 0, 0);
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
                    if e["type"] == "play" && card.starts_with("KAR") {
                        played.insert(card.to_string());
                    }
                    let by = e.get("by").and_then(Value::as_str).unwrap_or("");
                    portals += (e["type"] == "summon" && matches!(by, "KAR_073" | "KAR_075" | "KAR_076" | "KAR_077" | "KAR_091")) as usize;
                    atiesh += (e["type"] == "summon" && by == "KAR_097t") as usize;
                    legendaries += (e["type"] == "add_to_deck" && h.events().iter().any(|x| x["type"] == "game_start")) as usize;
                    barnes += (e["type"] == "summon" && by == "KAR_114") as usize;
                }
            }
        }
    }
    assert!(over >= decks.len(), "most games end");
    eprintln!("KARA cards played: {}: {played:?}; portal minions {portals}, Atiesh's {atiesh}, Malchezaar's Legendaries \
        {legendaries}, Barnes's copies {barnes}", played.len());
    assert!(played.len() >= 15, "{played:?}");
    assert!(portals > 0 && atiesh > 0 && barnes > 0);
    assert_eq!(legendaries % 5, 0);
    assert!(legendaries > 0, "the Prince Druid's games");
}
