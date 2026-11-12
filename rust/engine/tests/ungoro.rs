//! The Journey to Un'Goro pack (packs/ungoro, built by tools/pack.py on Mean Streets of Gadgetzan and the packs before
//! it): the cards as on 2017-04-06 (build 18336) and the engine features it needs: Quests (TASK: the opening hand, the
//! Secret zone in sight of both players, one at a time, a Secret slot), Adapt, "if you played an Elemental last turn",
//! the Dormant seed and portal (DORMANT), Time Warp's extra turn (`g.extra_turn`), Swamp King Dred's attack
//! (`g.force_attack`), costs set to a number (`cost_set`), a Poisonous weapon, Crystal Core's new base stats (`base`),
//! the older cards of that day, and whole bot games with every deck template. Needs python3 (skipped without it).

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
        let out = std::env::temp_dir().join(format!("ungoro-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/ungoro", "-o"]).arg(&out).output().ok()?;
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
const CAVERNS: &str = "UNG_067";
const CORE: &str = "UNG_067t1";
const ADAPTS: [&str; 10] = ["UNG_999t2", "UNG_999t3", "UNG_999t4", "UNG_999t5", "UNG_999t6", "UNG_999t7", "UNG_999t8",
    "UNG_999t10", "UNG_999t13", "UNG_999t14"];

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
    fn hero(&self, p: usize) -> Id {
        self.g.players[p].hero
    }
    fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
    }
    fn count(&self, p: usize, k: &str) -> i64 {
        self.g.players[p].counts.get(k).map_or(0, |v| v.int())
    }
    fn tag(&self, e: Id, k: &str) -> i64 {
        self.g.e(e).tag(k)
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
    fn can_play(&self, card: &str) -> bool {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e)
    }
    fn targets(&self, card: &str) -> Vec<Id> {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).map(|a| int(a.get("target"))).collect()
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
    fn events(&self) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).collect()
    }
    /// Picks the given adaptation if offered, else the first option; returns what was picked.
    fn adapt(&mut self, want: &str) -> String {
        let opts = self.options();
        assert_eq!(opts.len(), 3, "three adaptations: {opts:?}");
        assert!(opts.iter().all(|o| ADAPTS.contains(&o.as_str())), "{opts:?}");
        let mut u = opts.clone();
        u.sort();
        u.dedup();
        assert_eq!(u.len(), 3, "different: {opts:?}");
        let c = if opts.iter().any(|o| o == want) { want.to_string() } else { opts[0].clone() };
        self.pick_card(&c);
        c
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
    assert_eq!(stats("UNG_002"), (7, 5, 6), "Volcanosaur 7 mana 5/6");
    assert_eq!(c("UNG_002").race, "BEAST", "Volcanosaur: no Elemental until 2022");
    assert_eq!(c("UNG_004").cost, 8, "Dinosize 8 mana");
    assert_eq!(stats("UNG_010"), (7, 5, 7), "Sated Threshadon 5/7, no Taunt");
    assert!(c("UNG_010").keywords.iter().all(|k| k != "TAUNT"));
    assert_eq!(stats("UNG_907"), (9, 5, 5), "Ozruk 9 mana 5/5");
    assert!(c(CAVERNS).task && c("UNG_028").task && c("UNG_829").task, "Quests are tasks");
    assert_eq!(c("UNG_019").keywords, vec!["ELUSIVE"], "Air Elemental");
    assert!(c("UNG_852").keywords.iter().any(|k| k == "ELUSIVE"), "Tyrantus");
    assert!(c("UNG_065t").keywords.iter().any(|k| k == "UNTOUCHABLE"), "the seed is Dormant");
    // older cards of that day
    for id in ["VAN_CS2_033", "VAN_CS2_042", "VAN_CS2_118", "VAN_EX1_243", "VAN_EX1_249", "VAN_EX1_250", "VAN_EX1_258",
        "VAN_EX1_283", "VAN_EX1_298", "VAN_EX1_335", "VAN_NEW1_010", "AT_092", "BRM_012", "GVG_042", "KAR_036", "LOE_016",
        "OG_120", "OG_229", "OG_031a"] {
        assert_eq!(c(id).race, "ELEMENTAL", "{id}: an Elemental since patch 8.0");
    }
    assert_eq!(c("CFM_715").race, "", "Jade Spirit: an Elemental only from July 2017");
    assert_eq!(stats("CFM_325"), (1, 1, 1), "Small-Time Buccaneer 1/1 (7.1)");
    assert_eq!(c("KAR_063").cost, 2, "Spirit Claws 2 mana (7.1)");
    assert_eq!(rs.cards.values().filter(|x| x.collectible && x.set == "UNGORO").count(), 135);
}

#[test]
fn a_quest_starts_in_the_opening_hand() {
    let Some(rs) = rs() else { return };
    let mut deck: Vec<String> = vec![YETI.to_string(); 29];
    deck.push(CAVERNS.to_string());
    for seed in 0..20 {
        let g = Game::new_in(rs, "HERO_03", &deck, "HERO_01", &deck, seed, -1, true);
        for p in 0..2 {
            assert!(g.players[p].hand.iter().any(|&e| g.e(e).card_id == CAVERNS), "seed {seed}: player {p}");
        }
    }
}

#[test]
fn the_caverns_below_and_crystal_core() {
    let mut t = scene!({"hero": "HERO_03", "hand": [CAVERNS, WISP, WISP, WISP, WISP, "VAN_EX1_332", "UNG_809"]}, {});
    t.play(CAVERNS, NONE);
    let q = t.g.players[0].secrets[0];
    assert_eq!(t.g.e(q).zone, "SECRET");
    assert_eq!((t.tag(q, "QUEST_PROGRESS"), t.tag(q, "QUEST_PROGRESS_TOTAL")), (0, 4));
    // in sight of both players, with its progress
    let view = api::snapshot(&t.g, 1);
    assert_eq!(view["entities"][q.to_string()]["card"], CAVERNS, "the opponent sees the Quest");
    // one Quest at a time (Mana Bind's copy of one waits)
    for i in 0..3 {
        t.play(WISP, NONE);
        assert_eq!(t.tag(q, "QUEST_PROGRESS"), i + 1);
    }
    t.play("UNG_809", NONE); // another name: the most of one name counts
    assert_eq!(t.tag(q, "QUEST_PROGRESS"), 3);
    t.play(WISP, NONE);
    assert!(t.g.players[0].secrets.is_empty(), "fulfilled");
    assert!(t.hand(0).contains(&CORE.to_string()));
    assert!(t.events().iter().any(|e| e["type"] == "quest_done"));
    t.g.players[0].mana = 10;
    t.play(CORE, NONE);
    let w = t.nth(0, 0);
    assert_eq!(t.stats(w), (5, 5));
    t.play("VAN_EX1_332", w); // Silence keeps Crystal Core's 5/5
    assert_eq!(t.stats(w), (5, 5));
    // a minion drawn later is 5/5 too
    t.end_turn().end_turn();
    let drawn = *t.g.players[0].hand.last().unwrap();
    assert_eq!(t.stats(drawn), (5, 5));
}

#[test]
fn one_quest_at_a_time_and_a_secret_slot() {
    let mut t = scene!({"mana": 30, "hand": ["UNG_028", "UNG_116", "VAN_EX1_287", "VAN_EX1_289", "VAN_EX1_294", "VAN_EX1_609", "VAN_EX1_594"]}, {"hand": ["OG_254"]});
    t.play("UNG_028", NONE);
    assert!(!t.can_play("UNG_116"), "a second Quest waits for the first");
    for s in ["VAN_EX1_287", "VAN_EX1_289", "VAN_EX1_294", "VAN_EX1_609"] {
        t.play(s, NONE);
    }
    assert!(!t.can_play("VAN_EX1_594"), "the Quest takes a Secret slot: four Secrets more");
    t.end_turn();
    t.play("OG_254", NONE); // Eater of Secrets: the Secrets, not the Quest
    assert_eq!(t.g.players[0].secrets.len(), 1);
    assert_eq!(card_of(&t, t.g.players[0].secrets[0]), "UNG_028");
}

#[test]
fn adapt_offers_three_hidden_upgrades() {
    let mut t = scene!({"hand": ["UNG_002", "UNG_089"], "board": ["VAN_CS2_168", "VAN_EX1_506"]}, {});
    t.play("UNG_002", NONE);
    let v = t.on_board(0, "UNG_002");
    let opts = t.g.pending_options();
    let view = api::snapshot(&t.g, 1);
    for o in &opts {
        let e = &view["entities"][o.to_string()];
        assert!(e.is_null() || e["card"] == "", "the opponent never sees the options");
    }
    t.adapt("UNG_999t3");
    t.adapt("UNG_999t6");
    assert!(t.g.pending.is_none());
    assert!(t.g.e(v).atk() >= 5);
    // Gentle Megasaur: one choice for every friendly Murloc
    t.g.players[0].mana = 10;
    t.play("UNG_089", NONE);
    let got = t.adapt("UNG_999t14");
    if got == "UNG_999t14" {
        for &m in &t.g.players[0].board.clone() {
            if t.g.e(m).race() == "MURLOC" {
                assert!(t.g.e(m).atk() > t.g.e(m).card.attack);
            }
        }
    }
}

#[test]
fn elementals_played_last_turn() {
    let mut t = scene!({"hand": ["UNG_809", "UNG_021", "UNG_907"], "deck": FILL}, {});
    let surger = t.hand_id("UNG_021");
    assert!(!t.g.glows(surger));
    t.play("UNG_809", NONE); // Fire Fly, an Elemental
    assert!(!t.g.glows(surger), "this turn is not last turn");
    t.end_turn().end_turn();
    assert!(t.g.glows(surger));
    t.play("UNG_021", NONE);
    assert!(t.hand(0).contains(&"UNG_018".to_string()), "Flame Geyser");
    // Ozruk: +5 Health for each Elemental played last turn (Steam Surger: one)
    t.end_turn().end_turn();
    t.play("UNG_907", NONE);
    assert_eq!(t.stats(t.on_board(0, "UNG_907")).1, 10);
    // two turns ago does not count
    t.end_turn().end_turn().end_turn().end_turn();
    assert_eq!((t.count(0, "ELEM_LAST"), t.count(0, "ELEM_NOW")), (0, 0));
}

#[test]
fn sherazin_goes_dormant_and_revives() {
    let mut t = scene!({"hero": "HERO_03", "hand": [FIREBALL, "VAN_CS2_032", WISP, WISP, WISP, WISP], "board": ["UNG_065"]}, {});
    t.g.players[0].mana = 30;
    let s = t.on_board(0, "UNG_065");
    t.play(FIREBALL, s);
    let seed = t.on_board(0, "UNG_065t");
    assert!(!t.targets("VAN_CS2_032").contains(&seed));
    t.play("VAN_CS2_032", NONE); // the cards played before it went dormant don't count
    t.end_turn().end_turn();
    t.g.players[0].mana = 10;
    for _ in 0..3 {
        t.play(WISP, NONE);
    }
    assert_eq!(card_of(&t, seed), "UNG_065t");
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("defender")) == seed));
    t.play(WISP, NONE);
    assert!(t.cards(0).contains(&"UNG_065".to_string()), "revived: {:?}", t.cards(0));
    assert!(!t.cards(0).contains(&"UNG_065t".to_string()));
}

#[test]
fn time_warp_takes_an_extra_turn() {
    let mut t = scene!({"hand": ["UNG_028t", "UNG_028t"], "max_mana": 8, "mana": 10}, {});
    let turn = t.g.turn;
    t.play("UNG_028t", NONE).play("UNG_028t", NONE); // two in one turn: one extra turn
    let hand = t.hand(0).len();
    t.end_turn();
    assert_eq!(t.g.current, 0);
    assert_eq!(t.g.turn, turn + 1);
    assert_eq!(t.g.players[0].max_mana, 9);
    assert_eq!(t.hand(0).len(), hand + 1, "drew a card");
    assert!(t.events().iter().any(|e| e["type"] == "extra_turn"));
    t.end_turn();
    assert_eq!(t.g.current, 1, "then the opponent's turn");
}

#[test]
fn swamp_king_dred_attacks_a_played_minion() {
    let mut t = scene!({"board": ["UNG_919"]}, {"hand": [YETI, "VAN_EX1_015"], "board": ["VAN_CS2_179"]});
    t.end_turn();
    t.play(YETI, NONE); // past the Taunt
    let dred = t.on_board(0, "UNG_919");
    assert!(!t.g.players[1].board.iter().any(|&m| card_of(&t, m) == YETI), "the Yeti died");
    assert_eq!(t.stats(dred), (9, 5));
    assert_eq!(t.g.e(dred).tag("ATTACKS"), 0, "it used none of its attacks");
    // a Frozen Dred does not attack
    t.g.em(dred).set_tag("FROZEN", true);
    t.play("VAN_EX1_015", NONE);
    assert!(t.cards(1).contains(&"VAN_EX1_015".to_string()));
}

#[test]
fn costs_set_to_a_number() {
    // Bright-Eyed Scout: the drawn card costs (5)
    let mut t = scene!({"hand": ["UNG_113"], "deck": [FIREBALL], "secrets": ["UNG_024"]}, {"hand": ["VAN_CS2_024"]});
    t.play("UNG_113", NONE);
    assert_eq!(t.cost(FIREBALL), 5);
    // Mana Bind: a copy of the opponent's spell that costs (0)
    t.end_turn();
    let h = t.hero(0);
    t.play("VAN_CS2_024", h);
    t.end_turn();
    assert_eq!(t.cost("VAN_CS2_024"), 0);
    // Barnabus: the minions in the deck cost (0)
    let mut t = scene!({"hero": "HERO_06", "hand": ["UNG_116t"], "deck": [YETI, FIREBALL]}, {});
    t.play("UNG_116t", NONE);
    let costs: Vec<(String, i64)> = t.g.players[0].deck.iter().map(|&e| (t.g.e(e).card_id.to_string(), t.g.cost(e))).collect();
    assert_eq!(costs, vec![(YETI.to_string(), 0), (FIREBALL.to_string(), 4)]);
}

#[test]
fn envenom_weapon_poisons_the_hero_attack() {
    let mut t = scene!({"hero": "HERO_03", "hand": ["UNG_823"], "weapon": "VAN_CS2_080"}, {"board": ["VAN_CS2_200"]});
    t.play("UNG_823", NONE);
    let ogre = t.nth(1, 0);
    let h = t.hero(0);
    t.attack(h, ogre);
    assert!(t.g.players[1].board.is_empty(), "Poisonous: the Ogre is destroyed");
}

#[test]
fn living_mana_and_its_treants() {
    let mut t = scene!({"hero": "HERO_06", "hand": ["UNG_111"]}, {});
    t.play("UNG_111", NONE); // 10 crystals, 5 spent: 5 empty go first, then 2 full
    assert_eq!(t.cards(0).len(), 7);
    assert_eq!((t.g.players[0].mana, t.g.players[0].max_mana), (3, 3));
    let tr = t.nth(0, 0);
    t.g.em(tr).set_tag("TO_DESTROY", true);
    t.g.resolve();
    assert_eq!(t.g.players[0].max_mana, 4, "an empty crystal back");
}

#[test]
fn corrupting_mist_and_tar() {
    let mut t = scene!({"hero": "HERO_07", "hand": ["UNG_831"], "board": ["UNG_928"]}, {"board": [YETI]});
    t.play("UNG_831", NONE);
    let tar = t.on_board(0, "UNG_928");
    assert_eq!(t.stats(tar).0, 1);
    t.end_turn();
    assert_eq!(t.stats(tar).0, 3, "Tar Creeper: +2 in the opponent's turn");
    t.end_turn();
    assert!(t.g.players[0].board.is_empty() && t.g.players[1].board.is_empty(), "destroyed at the caster's turn");
}

#[test]
fn kalimos_and_the_voraxx() {
    let mut t = scene!({"hero": "HERO_02", "hand": ["UNG_211"]}, {"board": [YETI, YETI]});
    t.g.players[0].counts.insert("ELEM_LAST".to_string(), 1i64);
    t.play("UNG_211", NONE);
    assert_eq!(t.options().len(), 4);
    t.pick_card("UNG_211d"); // Invocation of Air: 3 to all enemy minions
    assert_eq!(t.stats(t.nth(1, 0)).1, 2);
    // The Voraxx: a Plant, and the spell again on it
    let mut t = scene!({"hand": ["VAN_CS2_092"], "board": ["UNG_843"]}, {});
    let v = t.on_board(0, "UNG_843");
    t.play("VAN_CS2_092", v); // Blessing of Kings
    let plant = t.on_board(0, "UNG_999t2t1");
    assert_eq!(t.stats(plant), (5, 5));
}

#[test]
fn random_cards_never_fail() {
    let Some(rs) = rs() else { return };
    let ung: Vec<String> = {
        let mut v: Vec<String> = rs.cards.values().filter(|c| c.set == "UNGORO" && c.kind != "POWER" && c.kind != "CHAMPION")
            .map(|c| c.id.clone()).collect();
        v.sort();
        v
    };
    for seed in 0..120 {
        let hand: Vec<&String> = ung.iter().skip((seed * 7) % ung.len()).take(8).collect();
        let hero = ["HERO_01", "HERO_03", "HERO_06", "HERO_08", "HERO_09"][seed as usize % 5];
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": hero, "mana": 10, "max_mana": 10,
             "deck": [YETI, "UNG_809", "UNG_065", WISP, "UNG_072", FIREBALL], "hand": hand, "board": [WISP, "VAN_EX1_506"]},
            {"hero": "HERO_05", "mana": 10, "max_mana": 10, "deck": FILL, "board": [YETI, "UNG_919"]}]});
        let mut g = scenario::build_in(rs, &sc).unwrap();
        for _ in 0..24 {
            if g.game_over {
                break;
            }
            g.players[g.current].mana = 10;
            let acts = g.legal_actions();
            let a = acts.iter().find(|a| a["type"] == "choose").or_else(|| acts.iter().find(|a| a["type"] == "play"))
                .or_else(|| acts.iter().find(|a| a["type"] == "end_turn")).cloned();
            let Some(a) = a else { break };
            assert!(g.apply(&Value::Object(a)).ok);
            assert_eq!(g.script_error.get(), None, "seed {seed}");
        }
    }
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/ungoro/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30);
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
    if decks.is_empty() {
        eprintln!("no deck templates yet");
        return;
    }
    let mut over = 0;
    let mut played = std::collections::BTreeSet::new();
    let (mut quests, mut adapts, mut extra, mut elem_turns) = (0, 0, 0, 0);
    let mut done = std::collections::BTreeMap::new();
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
                let turn = g.turn;
                assert!(g.apply(&Value::Object(a)).ok);
                assert_eq!(g.script_error.get(), None, "{c0} vs {c1}");
                steps += 1;
                assert!(steps < 4000);
                if g.turn != turn && g.players[g.current].counts.get("ELEM_LAST").is_some_and(|v| v.int() > 0) {
                    elem_turns += 1; // a turn that begins after an Elemental was played on the player's last one
                }
            }
            over += g.game_over as usize;
            for h in &g.history {
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    if e["type"] == "play" && card.starts_with("UNG") {
                        played.insert(card.to_string());
                    }
                    quests += (e["type"] == "play" && e.get("task").is_some()) as usize;
                    if e["type"] == "quest_done" {
                        *done.entry(card.to_string()).or_insert(0) += 1;
                    }
                    extra += (e["type"] == "extra_turn") as usize;
                    adapts += (e["type"] == "create" && ADAPTS.contains(&card)) as usize;
                }
            }
        }
    }
    assert!(over >= decks.len(), "most games end");
    eprintln!("UNGORO cards played: {}: {played:?}; quests {quests}, fulfilled {done:?}, adaptations offered {adapts}, \
        extra turns {extra}, turns after an Elemental {elem_turns}", played.len());
    assert!(quests > 0 && !done.is_empty() && adapts > 0 && elem_turns > 0);
}
