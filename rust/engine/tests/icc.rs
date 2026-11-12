//! The Knights of the Frozen Throne pack (packs/icc, built by tools/pack.py on Journey to Un'Goro and the packs before
//! it): the cards as on 2017-08-10 (build 20457) and the engine features it needs: hero cards (a CHAMPION played from
//! the hand), Lifesteal (LIFESTEAL, Auchenai Soulpriest once), borrowed hooks (`g.set_hooks`: the Zombeast), Drakkari
//! Enchanter (DOUBLE_TURN_END), a replaced weapon dying (`behaviour.replaced_weapon_dies`), the Choose One option a
//! minion was played with (`g.choice`: Fatespinner), the cost order of patch 9.0, the older cards of that day, and whole
//! bot games with every deck template. Needs python3 (skipped without it).

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
        let out = std::env::temp_dir().join(format!("icc-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/icc", "-o"]).arg(&out).output().ok()?;
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

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    let stats = |id: &str| (c(id).cost, c(id).attack, c(id).health);
    assert_eq!(rs.cards.values().filter(|x| x.collectible && x.set == "ICECROWN").count(), 135);
    assert_eq!(c("ICC_054").cost, 5, "Spreading Plague 5 mana until patch 9.1");
    assert_eq!(stats("ICC_210"), (2, 2, 2), "Shadow Ascendant 2/2 until 2023");
    assert_eq!(c("ICC_235").cost, 6, "Shadow Essence 6 mana until 2023");
    assert_eq!(c("ICC_705").cost, 7, "Bonemare 7 mana");
    assert_eq!(c("ICC_221").cost, 2, "Leeching Poison 2 mana");
    assert_eq!(stats("ICC_910"), (6, 5, 5), "Spectral Pillager 6 mana");
    assert_eq!(stats("ICC_075"), (5, 4, 5), "Despicable Dreadlord 4/5");
    for h in ["ICC_827", "ICC_828", "ICC_829", "ICC_830", "ICC_831", "ICC_832", "ICC_833", "ICC_834", "ICC_481"] {
        assert_eq!((c(h).kind.as_str(), c(h).armor, c(h).collectible), ("CHAMPION", 5, true), "{h}: a hero card");
        assert!(!c(h).power.is_empty());
    }
    assert_eq!(c("ICC_419").keywords, vec!["ELUSIVE"], "Bearshark");
    assert!(c("ICC_220").keywords.iter().any(|k| k == "LIFESTEAL"));
    // older cards of that day
    assert!(c("GVG_018").keywords.iter().any(|k| k == "LIFESTEAL") && c("GVG_018").script.is_empty(), "Mistress of Pain");
    assert!(c("CFM_815").keywords.iter().any(|k| k == "LIFESTEAL"), "Wickerflame");
    for id in ["CFM_606", "CFM_606t", "CFM_715", "VAN_TU4e_002t", "LOE_053", "OG_209"] {
        assert_eq!(c(id).race, "ELEMENTAL", "{id}: an Elemental since patch 8.4");
    }
    assert_eq!(c("VAN_CS2_013").cost, 2, "Wild Growth (Innervate and the others: the 9.1 nerfs are later)");
    assert_eq!(c("VAN_CS2_106").cost, 2, "Fiery War Axe 2 mana until 9.1");
}

#[test]
fn random_cards_never_fail() {
    let Some(rs) = rs() else { return };
    let icc: Vec<String> = {
        let mut v: Vec<String> = rs.cards.values().filter(|c| c.set == "ICECROWN" && c.kind != "POWER" && !(c.kind == "CHAMPION" && !c.collectible))
            .map(|c| c.id.clone()).collect();
        v.sort();
        v
    };
    for seed in 0..160 {
        let hand: Vec<&String> = icc.iter().skip((seed * 7) % icc.len()).take(8).collect();
        let hero = ["HERO_01", "HERO_03", "HERO_06", "HERO_08", "HERO_09", "HERO_05", "HERO_07", "HERO_02", "HERO_04"][seed as usize % 9];
        let sc = json!({"current": 0, "seed": seed, "players": [
            {"hero": hero, "mana": 10, "max_mana": 10, "weapon": "VAN_CS2_106",
             "deck": [YETI, "ICC_812", "ICC_065", WISP, "ICC_220", FIREBALL, "VAN_EX1_554", "ICC_838"], "hand": hand,
             "board": [WISP, "VAN_EX1_506", "ICC_029"]},
            {"hero": "HERO_05", "mana": 10, "max_mana": 10, "deck": FILL, "board": [YETI, "ICC_900"]}]});
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

#[test]
fn a_hero_card_keeps_health_adds_armor_and_brings_its_power() {
    let mut t = scene!({"hero": "HERO_06", "mana": 30, "damage": 12, "armor": 2, "weapon": "VAN_CS2_106", "hand": ["ICC_832"]}, {});
    t.power_on(NONE); // Shapeshift: +1 Attack this turn, 1 Armor
    let old = t.hero(0);
    assert!(!t.can_power());
    t.attack(old, t.hero(1)); // the weapon swing is used
    t.g.em(old).set_tag("FROZEN", true);
    t.play_choice("ICC_832", NONE, 0); // Spiders
    let h = t.hero(0);
    assert_ne!(h, old);
    assert_eq!(card_of(&t, h), "ICC_832");
    assert_eq!((t.hp(0), t.g.e(h).max_health()), (18, 30), "Health and maximum Health stay");
    assert_eq!(t.armor(0), 3 + 5, "the Armor adds");
    assert_eq!(t.power(0), "ICC_832p");
    assert!(t.can_power(), "a fresh Hero Power");
    assert!(!t.g.e(h).has("FROZEN"), "a hero card thaws");
    assert_eq!(t.g.e(h).tag("ATTACKS"), 1, "the weapon swing is not refreshed (patch 9.0)");
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "attack" && int(a.get("attacker")) == h));
    assert_eq!(t.cards(0), vec!["ICC_832t3", "ICC_832t3"]);
    assert_eq!(t.g.e(h).card.card_class, "DRUID");
    // Plague Lord: Choose One, the options only its player sees
    t.power_on(NONE);
    assert_eq!(t.options(), vec!["ICC_832pb", "ICC_832pa"]);
    let view = api::snapshot(&t.g, 1);
    for o in t.g.pending_options() {
        let e = &view["entities"][o.to_string()];
        assert!(e.is_null() || e["card"] == "", "hidden from the opponent");
    }
    t.pick_card("ICC_832pa");
    assert_eq!(t.armor(0), 11);
}

#[test]
fn a_hero_card_keeps_lord_jaraxxus_health() {
    let mut t = scene!({"hero": "HERO_07", "mana": 30, "hand": ["VAN_EX1_323", "ICC_831"]}, {});
    t.play("VAN_EX1_323", NONE);
    assert_eq!(t.g.e(t.hero(0)).max_health(), 15);
    t.g.em(t.hero(0)).damage = 4;
    t.play("ICC_831", NONE);
    assert_eq!((t.hp(0), t.g.e(t.hero(0)).max_health(), t.armor(0)), (11, 15, 5));
    assert_eq!(t.power(0), "ICC_831p");
    assert_eq!(t.g.players[0].weapon.map(|w| card_of(&t, w)), Some("EX1_323w".to_string()), "the weapon stays");
}

#[test]
fn malfurion_with_fandral_has_both() {
    let mut t = scene!({"hero": "HERO_06", "mana": 30, "hand": ["ICC_832"], "board": ["OG_044"]}, {});
    t.play_choice("ICC_832", NONE, 2);
    assert_eq!(t.cards(0), vec!["OG_044", "ICC_832t3", "ICC_832t3", "ICC_832t4", "ICC_832t4"]);
    t.power_on(NONE);
    assert!(t.g.pending.is_none(), "both at once");
    assert_eq!(t.armor(0), 8);
    assert_eq!(t.g.e(t.hero(0)).atk(), 3);
}

#[test]
fn lifesteal_heals_its_hero() {
    let mut t = scene!({"hero": "HERO_09", "damage": 10, "board": ["ICC_905"], "hand": ["ICC_802", "ICC_055"]},
        {"armor": 3, "board": [YETI, "VAN_EX1_008"]});
    let worm = t.nth(0, 0);
    t.attack(worm, t.hero(1)); // 4 damage, 3 of it to Armor: 4 healed
    assert_eq!(t.hp(0), 24);
    t.play("ICC_802", NONE); // Spirit Lash: 1 to each minion (the Squire's shield: 0), a heal for each
    assert_eq!(t.hp(0), 26);
    t.play("ICC_055", t.nth(1, 0)); // Drain Soul: 2
    assert_eq!(t.hp(0), 28);
}

#[test]
fn auchenai_turns_a_lifesteal_heal_into_damage_once() {
    let mut t = scene!({"hero": "HERO_09", "hand": ["ICC_055"], "board": ["VAN_EX1_591"]}, {"board": [YETI]});
    t.play("ICC_055", t.nth(1, 0));
    assert_eq!(t.hp(0), 28, "2 damage to its own hero, once");
    assert!(!t.g.game_over);
}

#[test]
fn a_lifesteal_weapon_and_doomerang() {
    let mut t = scene!({"hero": "HERO_03", "damage": 10, "weapon": "VAN_CS2_080", "hand": ["ICC_221", "ICC_233"]}, {"board": [YETI]});
    t.play("ICC_221", NONE);
    t.attack(t.hero(0), t.hero(1)); // Assassin's Blade: 3
    assert_eq!(t.hp(0), 23);
    t.play("ICC_233", t.nth(1, 0)); // Doomerang: the blade hits the Yeti for 3, Lifesteal too, and comes back fresh
    assert_eq!(t.hp(0), 26);
    assert!(t.g.players[0].weapon.is_none());
    assert!(t.hand(0).contains(&"VAN_CS2_080".to_string()));
}

#[test]
fn frost_lich_jaina_gives_elementals_lifesteal() {
    let mut t = scene!({"hero": "HERO_08", "mana": 30, "damage": 10, "hand": ["ICC_833"], "board": ["UNG_809"]}, {"board": [WISP]});
    t.play("ICC_833", NONE);
    assert!(t.cards(0).contains(&"ICC_833t".to_string()));
    let fly = t.on_board(0, "UNG_809");
    assert!(t.g.e(fly).has("LIFESTEAL"));
    t.attack(fly, t.hero(1));
    assert_eq!(t.hp(0), 21);
    // Icy Touch: 1 damage; a Water Elemental when it kills a minion
    t.power_on(t.nth(1, 0));
    assert_eq!(t.cards(0).iter().filter(|c| *c == "ICC_833t").count(), 2);
}

#[test]
fn build_a_beast_makes_a_hidden_zombeast() {
    let mut t = scene!({"hero": "HERO_05", "mana": 30, "hand": ["ICC_828"]}, {"board": [WISP, YETI]});
    t.play("ICC_828", NONE);
    assert_eq!(t.cards(1), vec![YETI], "2 damage to each enemy minion");
    assert_eq!(t.power(0), "ICC_828p");
    t.power_on(NONE);
    let first = t.options();
    assert_eq!(first.len(), 3);
    let rs = rs().unwrap();
    for o in &first {
        assert!(rs.card(o).cost <= 5 && rs.card(o).race == "BEAST", "{o}");
    }
    let a = t.pick_first();
    let second = t.options();
    assert_eq!(second.len(), 3);
    let b = t.pick_first();
    let z = *t.g.players[0].hand.last().unwrap();
    assert_eq!(card_of(&t, z), "ICC_828t");
    let (ca, cb) = (rs.card(&a), rs.card(&b));
    assert_eq!(t.stats(z), (ca.attack + cb.attack, ca.health + cb.health));
    assert_eq!(t.g.cost(z), ca.cost + cb.cost);
    assert_eq!(t.g.e(z).borrowed.map(|c| c.id.as_str()), Some(a.as_str()), "the first Beast's text");
    // only its player sees it; its text names both Beasts
    let mine = api::snapshot(&t.g, 0);
    assert_eq!(mine["entities"][z.to_string()]["text_args"], json!([a, b]));
    let theirs = api::snapshot(&t.g, 1);
    assert_eq!(theirs["entities"][z.to_string()]["card"], "");
    // played: the first Beast's hooks work, Silence keeps its stats
    t.g.players[0].mana = 30;
    let z_cost = t.g.cost(z);
    assert!(z_cost <= 10);
}

#[test]
fn a_zombeast_has_its_first_beasts_battlecry() {
    let Some(rs) = rs() else { return };
    // Ironbeak Owl + Bloodfen Raptor: a 4/3 for 5 that silences
    let sc = json!({"current": 0, "seed": 1, "players": [{"hero": "HERO_05", "mana": 10, "max_mana": 10, "deck": FILL,
        "hand": ["ICC_828t"]}, {"hero": "HERO_01", "deck": FILL, "board": ["VAN_CS2_179"]}]});
    let mut g = scenario::build_in(rs, &sc).unwrap();
    let z = g.players[0].hand[0];
    g.em(z).borrowed = Some(rs.card("VAN_CS2_203"));
    let mut t = T { g };
    let target = t.nth(1, 0);
    t.play("ICC_828t", target);
    assert!(!t.g.e(target).has("TAUNT"), "silenced by the Zombeast's Battlecry");
    let zm = t.nth(0, 0);
    t.g.silence(zm);
    assert!(t.g.e(zm).silenced);
}

#[test]
fn defile_casts_again_while_minions_die() {
    // Wisp 1, Bloodfen Raptor 2, River Crocolisk 3 Health; Abominations 4/4 (Deathrattle: 2 to all), Silverback 4:
    // a death in each cast, the Deathrattles between the casts, nothing left
    let mut t = scene!({"hero": "HERO_07", "hand": ["ICC_041"], "board": [WISP, "VAN_CS2_172", "VAN_CS2_120"]},
        {"board": ["VAN_EX1_097", "VAN_CS2_127"]});
    t.play("ICC_041", NONE);
    assert!(t.cards(0).is_empty() && t.cards(1).is_empty(), "{:?} {:?}", t.cards(0), t.cards(1));
    // a cast that kills nothing is the last
    let mut t = scene!({"hero": "HERO_07", "hand": ["ICC_041"], "board": [WISP, "VAN_CS2_120"]}, {"board": ["VAN_CS2_127"]});
    t.play("ICC_041", NONE);
    assert_eq!(t.stats(t.nth(0, 0)), (2, 1), "two casts: the Wisp died in the first");
}

#[test]
fn defile_stops_after_fourteen_casts() {
    // Grim Patrons of 1, 2 and 3 Health: one dies in every cast and the others call more; the 14th cast is the last
    let mut t = scene!({"hero": "HERO_07", "hand": ["ICC_041"],
        "board": [{"card": "BRM_019", "damage": 2}, {"card": "BRM_019", "damage": 1}, "BRM_019"]}, {});
    t.play("ICC_041", NONE);
    let dead = t.events().iter().filter(|e| e["type"] == "death").count();
    assert!(dead >= 14, "{dead} Patrons died");
    assert!(!t.cards(0).is_empty(), "it stopped with Patrons left");
}

#[test]
fn drakkari_enchanter_doubles_end_of_turn_effects() {
    let mut t = scene!({"board": ["ICC_901", "ICC_075"]}, {"board": [YETI, "VAN_CS2_127"]});
    t.end_turn();
    let yeti = t.nth(1, 0);
    assert_eq!(t.stats(yeti), (4, 3), "Despicable Dreadlord twice: 2 damage");
    // two Enchanters still twice
    let mut t = scene!({"board": ["ICC_901", "ICC_901", "ICC_075"]}, {"board": [YETI]});
    t.end_turn();
    assert_eq!(t.stats(t.nth(1, 0)), (4, 3));
}

#[test]
fn dreadsteed_comes_back_at_the_end_of_the_turn() {
    let mut t = scene!({"hand": [FIREBALL, FIREBALL], "mana": 20}, {"board": ["AT_019"]});
    let d = t.nth(1, 0);
    t.play(FIREBALL, d);
    assert!(t.cards(1).is_empty(), "not at once (patch 9.0)");
    t.end_turn();
    assert_eq!(t.cards(1), vec!["AT_019"]);
}

#[test]
fn fatespinner_keeps_its_choice_secret() {
    let mut t = scene!({"hero": "HERO_06", "mana": 30, "hand": ["ICC_047", FIREBALL]}, {"board": [YETI]});
    t.play_choice("ICC_047", NONE, 0); // +2/+2
    let mine = api::snapshot(&t.g, 0);
    let fs = *t.g.players[0].board.iter().find(|&&m| t.g.e(m).card_id == "ICC_047t").unwrap();
    assert_eq!(mine["entities"][fs.to_string()]["choice"], 0, "its player knows the choice");
    let f = t.on_board(0, "ICC_047t");
    let theirs = api::snapshot(&t.g, 1);
    assert!(!theirs.to_string().contains("ICC_047a") && !theirs.to_string().contains("ICC_047b"), "nothing tells the choice");
    assert!(theirs["entities"][fs.to_string()].get("choice").is_none(), "not its opponent");
    t.play(FIREBALL, f);
    assert_eq!(t.stats(t.nth(1, 0)), (6, 7), "the Yeti +2/+2");
    // damage, and Fandral's both: +2/+2 then 3 damage
    let mut t = scene!({"hero": "HERO_06", "mana": 30, "hand": ["ICC_047", FIREBALL], "board": ["OG_044"]}, {"board": [YETI]});
    t.play_choice("ICC_047", NONE, 2);
    let f = t.on_board(0, "ICC_047t2");
    t.play(FIREBALL, f);
    assert_eq!(t.stats(t.nth(1, 0)), (6, 4));
}

#[test]
fn mindbreaker_disables_hero_powers() {
    let mut t = scene!({"board": ["ICC_902"]}, {});
    assert!(!t.can_power());
    t.end_turn();
    assert!(!t.can_power());
}

#[test]
fn valeera_gets_a_shadow_reflection_each_turn() {
    let mut t = scene!({"hero": "HERO_03", "mana": 30, "hand": ["ICC_827", "VAN_EX1_015"]}, {});
    t.play("ICC_827", NONE);
    assert!(t.g.e(t.hero(0)).has("STEALTH"), "Stealth until your next turn");
    assert!(t.hand(0).contains(&"ICC_827t".to_string()), "a Reflection at once");
    assert!(!t.can_play("ICC_827t"));
    t.play("VAN_EX1_015", NONE); // the Reflection becomes a Novice Engineer
    assert_eq!(t.hand(0).iter().filter(|c| *c == "VAN_EX1_015").count(), 1);
    assert!(!t.hand(0).contains(&"ICC_827t".to_string()));
    t.end_turn();
    assert!(!t.hand(0).contains(&"VAN_EX1_015".to_string()), "the copy leaves at the end of the turn");
    t.end_turn();
    assert!(!t.g.e(t.hero(0)).has("STEALTH"));
    assert!(t.hand(0).contains(&"ICC_827t".to_string()));
}

#[test]
fn a_replaced_weapon_dies() {
    let mut t = scene!({"hero": "HERO_01", "mana": 30, "weapon": "FP1_021", "hand": ["VAN_CS2_106"], "board": ["ICC_097"]},
        {"board": [YETI]});
    t.play("VAN_CS2_106", NONE);
    assert_eq!(t.stats(t.nth(1, 0)), (4, 4), "Death's Bite's Deathrattle: 1 damage to all minions");
    assert_eq!(t.stats(t.nth(0, 0)), (5, 4), "Grave Shambler +1/+1 (and the 1 damage)");
}

#[test]
fn naga_sea_witch_comes_before_other_cost_changes() {
    // patch 9.0: Naga Sea Witch's (5) before the Thaurissan reductions, whenever she came
    let mut t = scene!({"hand": [FIREBALL, "VAN_EX1_620"], "board": ["BRM_028"]}, {});
    t.end_turn().end_turn(); // Thaurissan: -1 on the cards in hand
    t.g.players[0].board.clear();
    let s = scenario::build_in(rs().unwrap(), &json!({"current": 0, "seed": 1, "players": [
        {"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL, "hand": [FIREBALL], "board": ["BRM_028"]},
        {"hero": "HERO_01", "deck": FILL}]})).unwrap();
    let mut t = T { g: s };
    t.end_turn().end_turn();
    assert_eq!(t.cost(FIREBALL), 3);
    let naga = t.g.summon(0, "LOE_038", -1);
    t.g.update_auras();
    assert!(naga > 0);
    assert_eq!(t.cost(FIREBALL), 4, "Naga's 5 first, then Thaurissan's -1");
}

#[test]
fn voidform_is_ready_again_after_a_card() {
    let mut t = scene!({"hero": "HERO_09", "mana": 30, "hand": ["ICC_830", WISP, WISP]}, {"board": ["VAN_CS2_201"]});
    t.play("ICC_830", NONE);
    assert!(t.cards(1).is_empty(), "the 5-Attack Core Hound is destroyed");
    t.power_on(t.hero(1));
    assert!(!t.can_power());
    t.play(WISP, NONE);
    assert!(t.can_power());
    t.power_on(t.hero(1));
    assert_eq!(t.hp(1), 26);
}

#[test]
fn the_four_horsemen_win_the_game() {
    let mut t = scene!({"hero": "HERO_04", "mana": 30, "hand": ["ICC_829"]}, {});
    t.play("ICC_829", NONE);
    assert_eq!(t.g.players[0].weapon.map(|w| card_of(&t, w)), Some("ICC_829t".to_string()));
    for turn in 0..4 {
        t.power_on(NONE);
        if turn < 3 {
            assert!(!t.g.game_over);
            t.end_turn().end_turn();
            t.g.players[0].mana = 10;
        }
    }
    assert!(t.g.game_over && t.g.winner == 0, "the enemy hero is destroyed");
}

#[test]
fn spreading_plague_casts_while_the_opponent_has_more() {
    let mut t = scene!({"hero": "HERO_06", "hand": ["ICC_054"]}, {"board": [WISP, WISP, WISP, WISP]});
    t.play("ICC_054", NONE);
    assert_eq!(t.cards(0).len(), 4);
}

#[test]
fn professor_putricide_puts_a_hunter_secret() {
    let mut t = scene!({"hero": "HERO_05", "mana": 30, "hand": ["VAN_EX1_554"], "board": ["ICC_204"]}, {});
    t.play("VAN_EX1_554", NONE);
    let s = &t.g.players[0].secrets;
    assert_eq!(s.len(), 2);
    assert_ne!(card_of(&t, s[1]), "VAN_EX1_554");
    let theirs = api::snapshot(&t.g, 1);
    assert_eq!(theirs["entities"][s[1].to_string()]["card"], "", "hidden");
}

#[test]
fn moorabi_and_bolvar() {
    let mut t = scene!({"hero": "HERO_02", "mana": 30, "hand": ["ICC_056", "ICC_056"], "board": ["ICC_289", "ICC_858"]}, {"board": [YETI]});
    let yeti = t.nth(1, 0);
    t.play("ICC_056", yeti).play("ICC_056", yeti); // frozen again: a second copy
    assert_eq!(t.hand(0).iter().filter(|c| *c == YETI).count(), 2);
    let bolvar = t.on_board(0, "ICC_858");
    t.end_turn();
    let enemy_yeti = t.nth(1, 0);
    let _ = enemy_yeti;
    t.end_turn();
    t.g.damage(-1, bolvar, 1); // his own shield breaks: +2 Attack
    t.g.resolve();
    assert_eq!(t.stats(bolvar).0, 3);
}

#[test]
fn hero_cards_can_be_discovered_and_burgled() {
    let Some(rs) = rs() else { return };
    let mut heroes = 0;
    for seed in 0..400 {
        let sc = json!({"current": 0, "seed": seed, "players": [{"hero": "HERO_03", "mana": 10, "max_mana": 10, "deck": FILL,
            "hand": ["AT_033"]}, {"hero": "HERO_04", "deck": FILL}]});
        let mut g = scenario::build_in(rs, &sc).unwrap();
        let e = g.players[0].hand[0];
        let a = g.legal_actions().into_iter().find(|a| a["type"] == "play" && int(a.get("entity")) == e).unwrap();
        assert!(g.apply(&Value::Object(a)).ok);
        heroes += g.players[0].hand.iter().filter(|&&c| g.e(c).card_id == "ICC_829").count();
    }
    assert!(heroes > 0, "Burgle can give Uther of the Ebon Blade");
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/icc/decks")).unwrap().map(|f| f.unwrap().path()).collect();
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
    let (mut heroes, mut new_powers, mut lifesteal, mut zombeasts, mut defiles) = (0, 0, 0, 0, 0);
    let mut powers = std::collections::BTreeMap::new();
    for (i, (c0, d0)) in decks.iter().enumerate() {
        let (c1, d1) = &decks[(i + 5) % decks.len()];
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
                let power = h.action.get("type").and_then(Value::as_str) == Some("hero_power");
                for e in h.events() {
                    let card = e.get("card").and_then(Value::as_str).unwrap_or("");
                    if e["type"] == "play" && card.starts_with("ICC") {
                        played.insert(card.to_string());
                    }
                    heroes += (e["type"] == "play" && e["kind"] == "champion") as usize;
                    if power && e["type"] == "hero_power" {
                        let c = g.e(int(e.get("entity"))).card_id;
                        if c.starts_with("ICC_") {
                            new_powers += 1;
                            *powers.entry(c.to_string()).or_insert(0) += 1;
                        }
                    }
                    lifesteal += (e["type"] == "heal" && e.get("source").is_some_and(|s| {
                        let x = g.e(int(Some(s)));
                        x.has("LIFESTEAL") || x.card.keywords.iter().any(|k| k == "LIFESTEAL")
                    })) as usize;
                    zombeasts += (e["type"] == "add_to_hand" && card == "ICC_828t") as usize;
                    defiles += (e["type"] == "play" && card == "ICC_041") as usize;
                }
            }
        }
    }
    assert!(over >= decks.len(), "most games end");
    eprintln!("ICECROWN cards played: {}: {played:?}; hero cards {heroes}, their powers used {new_powers}, Lifesteal heals \
        {lifesteal}, Zombeasts {zombeasts}, Defiles {defiles}, powers {powers:?}", played.len());
    assert!(heroes > 0 && new_powers > 0 && lifesteal > 0 && defiles > 0 && zombeasts > 0);
}

#[test]
fn blood_queen_lanathel_counts_discards_wherever_she_is() {
    let mut t = scene!({"hero": "HERO_07", "mana": 20, "board": ["ICC_841"], "hand": ["VAN_EX1_308", WISP],
        "deck": [WISP, "ICC_841"]}, {"board": [YETI]});
    let yeti = t.nth(1, 0);
    t.play("VAN_EX1_308", yeti); // Soulfire: the Wisp is discarded
    let lana = t.on_board(0, "ICC_841");
    assert_eq!(t.stats(lana), (2, 6));
    t.end_turn().end_turn(); // the one in the deck: drawn with the bonus
    let drawn = *t.g.players[0].hand.iter().find(|&&e| t.g.e(e).card_id == "ICC_841").unwrap();
    assert_eq!(t.g.e(drawn).atk(), 2, "her Attack in the hand counts the discards");
}

#[test]
fn kalimos_invocations_are_no_spells() {
    // patch 9.0: the Invocation of Air with Hallazeal the Ascended heals nothing
    let mut t = scene!({"hero": "HERO_02", "mana": 20, "damage": 10, "hand": ["UNG_211"], "board": ["OG_209"]}, {"board": [YETI]});
    t.g.players[0].counts.insert("ELEM_LAST", 1i64);
    t.play("UNG_211", NONE);
    t.pick_card("UNG_211d");
    assert_eq!(t.stats(t.nth(1, 0)), (4, 2), "3 damage");
    assert_eq!(t.hp(0), 20, "no heal");
}
