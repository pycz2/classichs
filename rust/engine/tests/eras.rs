//! Hearthstone 2014–2019 (packs/eras, docs/packs/format.md §13): a pack with versions, built by tools/pack.py from
//! version patches; each version's view plays as a one-version pack. Needs python3 (skipped without it).

use classichs_engine::pack::{self, Files};
use classichs_engine::{ruleset, Engine};
use serde_json::{json, Value};
use std::path::PathBuf;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// A pack source built by tools/pack.py, read as the engine reads it; None without python3. Built once per test
/// run (the tests run in parallel and would share the output file).
fn built(src: &str) -> Option<Files> {
    static BUILT: std::sync::Mutex<Vec<(String, Option<Files>)>> = std::sync::Mutex::new(Vec::new());
    let mut done = BUILT.lock().unwrap_or_else(|e| e.into_inner());
    if let Some((_, f)) = done.iter().find(|(s, _)| s == src) {
        return f.clone();
    }
    let out = std::env::temp_dir().join(format!("eras-test-{}-{}.cardpack", src.replace('/', "_"), std::process::id()));
    let files = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", src, "-o"]).arg(&out).output().ok().map(|build| {
        assert!(build.status.success(), "pack.py build {src}: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        files
    });
    done.push((src.to_string(), files.clone()));
    files
}

#[test]
fn every_version_is_a_pack_of_its_own() {
    let (Some(eras), Some(naxx)) = (built("packs/eras"), built("packs/naxx")) else {
        eprintln!("no python3: skipped");
        return;
    };
    let vs = pack::versions(&eras);
    assert!(vs.windows(2).all(|w| w[0].date <= w[1].date), "oldest first");
    assert!(["6024", "6485"].iter().all(|id| vs.iter().any(|v| v.id == *id)));
    assert!(pack::versions(&naxx).is_empty());
    for v in &vs {
        let view = pack::version_view(&eras, &v.id).unwrap();
        assert_eq!(pack::rules_hash(&view).unwrap(), v.rules_hash, "version {}", v.id);
        assert!(!view.keys().any(|p| p.starts_with("versions/")));
        ruleset::load(&view).unwrap_or_else(|e| panic!("version {}: {e}", v.id));
    }
    // 6024 is the Naxxramas pack's cards, with the formats and the Arena bans of its time (packs/eras/formats.json)
    // and Swipe and Explosive Shot of before 9166
    let v6024 = pack::version_view(&eras, "6024").unwrap();
    assert!(v6024.contains_key("scripts/version/swipe_explosive_shot.lua"));
    assert_eq!(v6024["cards.json"], naxx["cards.json"]);
    let (rs, naxx_rs) = (ruleset::load(&v6024).unwrap(), ruleset::load(&naxx).unwrap());
    assert_eq!(rs.pool("standard"), &naxx_rs.collectible[..], "one format: every card");
    assert!(!rs.arena_pool.iter().any(|c| c == "VAN_EX1_112") && naxx_rs.arena_pool.iter().any(|c| c == "VAN_EX1_112"),
        "Gelbin Mekkatorque, a Promo card, was never drafted");
    // the top is the default version (a client that knows no versions plays it)
    let man: Value = serde_json::from_slice(&eras["manifest.json"]).unwrap();
    let default = man["default_version"].as_str().unwrap();
    assert_eq!(pack::rules_hash(&eras).unwrap(), pack::rules_hash(&pack::version_view(&eras, default).unwrap()).unwrap());
    assert_eq!(man["rules_hash"].as_str(), Some(pack::rules_hash(&eras).unwrap().as_str()));
}

#[test]
fn patch_6485_nerfs_leeroy_jenkins_and_starving_buzzard() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    let stats = |vid: &str, id: &str| {
        let rs = ruleset::load(&pack::version_view(&eras, vid).unwrap()).unwrap();
        let c = rs.card(id);
        (c.cost, c.attack, c.health)
    };
    assert_eq!(stats("6024", "VAN_EX1_116"), (4, 6, 2));
    assert_eq!(stats("6485", "VAN_EX1_116"), (5, 6, 2));
    assert_eq!(stats("6024", "VAN_CS2_237"), (2, 2, 1));
    assert_eq!(stats("6485", "VAN_CS2_237"), (5, 3, 2));
}

#[test]
fn patch_9786_sense_demons_draws_demonfuse_until_10357() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    // Demonfuse carried the Demon race in 9786 (fixed in 10357): Sense Demons drew it; else a Worthless Demon
    for (vid, drawn) in [("9786", "AT_024"), ("10357", "EX1_317t"), ("10604", "EX1_317t")] {
        let mut g = brm_era_game(&eras, vid, json!({"hero": "HERO_07", "hand": ["VAN_EX1_317"], "deck": ["AT_024"]}), json!({}));
        brm_era_play(&mut g, "VAN_EX1_317", -1);
        let hand: Vec<String> = g.players[0].hand.iter().map(|&x| g.e(x).card_id.to_string()).collect();
        assert!(hand.iter().any(|c| c == drawn), "version {vid}: {hand:?}");
    }
}

#[test]
fn patch_10604_warsong_commander_gives_charge_minions_1_attack() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    const RAPTOR: &str = "VAN_CS2_172"; // 3/2
    const WOLFRIDER: &str = "VAN_CS2_124"; // 3/1 Charge
    // before 10604: a summoned minion with 3 or less Attack gets Charge; from 10604: Charge minions have +1 Attack
    for (vid, charge, atk) in [("10357", true, 3), ("10604", false, 4)] {
        let mut g = brm_era_game(&eras, vid, json!({"hero": "HERO_01", "board": ["VAN_EX1_084"], "hand": [RAPTOR, WOLFRIDER]}), json!({}));
        brm_era_play(&mut g, RAPTOR, -1);
        brm_era_play(&mut g, WOLFRIDER, -1);
        let on_board = |id: &str| *g.players[0].board.iter().find(|&&m| g.e(m).card_id == id).unwrap();
        let (raptor, wolf) = (on_board(RAPTOR), on_board(WOLFRIDER));
        assert_eq!(g.e(raptor).has("CHARGE"), charge, "version {vid}");
        assert_eq!((g.attack_value(raptor), g.attack_value(wolf)), (3, atk), "version {vid}");
    }
}

/// The loe era: a game of version `vid` in a scenario (p0 a Priest, p1 a Warrior, 10 mana each, decks of Wisps,
/// both heroes 10 damage down; p0's turn; p0 and p1 merged over that).
fn loe_era_game(eras: &Files, vid: &str, p0: Value, p1: Value) -> classichs_engine::Game {
    let rs: &'static ruleset::Ruleset = Box::leak(Box::new(ruleset::load(&pack::version_view(eras, vid).unwrap()).unwrap()));
    let side = |hero: &str, over: Value| {
        let mut b = json!({"hero": hero, "damage": 10, "mana": 10, "max_mana": 10, "deck": ["VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231"]});
        b.as_object_mut().unwrap().extend(over.as_object().unwrap().clone());
        b
    };
    let sc = json!({"current": 0, "seed": 7, "players": [side("HERO_09", p0), side("HERO_01", p1)]});
    classichs_engine::scenario::build_in(rs, &sc).unwrap()
}

/// The loe era: the current player plays `card` from the hand at `target` (-1: none), without a script error.
fn loe_era_play(g: &mut classichs_engine::Game, card: &str, target: i64) {
    let int = |v: Option<&Value>| classichs_engine::entity::int(v);
    let e = *g.players[g.current].hand.iter().find(|&&x| g.e(x).card_id == card).unwrap();
    let a = g.legal_actions().into_iter().find(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target);
    let r = g.apply(&Value::Object(a.unwrap_or_else(|| panic!("no legal play of {card} at {target}"))));
    assert!(r.ok, "{card}: {}", r.error);
    assert_eq!(g.script_error.get(), None, "{card}");
}

/// The loe era: the current player ends the turn.
fn loe_era_end_turn(g: &mut classichs_engine::Game) {
    let p = g.current;
    assert!(g.apply(&json!({"type": "end_turn", "player": p})).ok);
}

/// Ship's Cannon hits after the Pirate's Battlecry (versions/*/scripts/ships_cannon.lua; the gvg pack hit on summon,
/// before it): Bloodsail Raider's Battlecry and its after_summon come first.
#[test]
fn patch_7234_ships_cannon_fires_after_the_battlecry() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    let ids: Vec<String> = pack::versions(&eras).into_iter().map(|v| v.id).filter(|id| id.parse::<i64>().unwrap() >= 7234).collect();
    assert!(ids.len() >= 16);
    for vid in &ids {
        let mut g = loe_era_game(&eras, vid, json!({"hand": ["VAN_NEW1_018"], "board": ["GVG_075"]}), json!({}));
        let before = g.history.len();
        loe_era_play(&mut g, "VAN_NEW1_018", -1);
        let evs: Vec<_> = g.history[before..].iter().flat_map(|h| h.events()).collect();
        let at = |t: &str| evs.iter().position(|e| e["type"] == t).unwrap_or_else(|| panic!("version {vid}: no {t}: {evs:?}"));
        assert!(at("after_summon") < at("damage"), "version {vid}: {evs:?}");
    }
}

#[test]
fn patch_10956_power_word_glory_heals_its_caster_after_a_control_change() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    const YETI: &str = "VAN_CS2_182"; // 4/5
    let damage = |g: &classichs_engine::Game| (g.e(g.hero(0)).damage, g.e(g.hero(1)).damage);
    // cast on an enemy minion: its attacks heal the caster in every version ("your hero"; the tgt pack heals the
    // minion's controller, versions/9786-10833/scripts/power_word_glory.lua)
    for vid in ["9786", "10357", "10604", "10833", "10956", "12051", "12266", "12574", "13714"] {
        let mut g = loe_era_game(&eras, vid, json!({"hand": ["AT_013"]}), json!({"board": [YETI]}));
        let yeti = g.players[1].board[0];
        loe_era_play(&mut g, "AT_013", yeti);
        loe_era_end_turn(&mut g);
        let h0 = g.hero(0);
        assert!(g.apply(&json!({"type": "attack", "player": 1, "attacker": yeti, "defender": h0})).ok, "version {vid}");
        assert_eq!(g.script_error.get(), None, "version {vid}");
        assert_eq!(damage(&g), (10, 10), "version {vid}: 4 damage, 4 healed");
    }
    // cast on your own minion, then the opponent takes it: until 10956 the enchantment goes over to them
    for (vid, want) in [("9786", (14, 6)), ("10604", (14, 6)), ("10833", (14, 6)), ("10956", (10, 10)), ("12051", (10, 10)), ("12266", (10, 10)), ("12574", (10, 10)), ("13714", (10, 10))] {
        let mut g = loe_era_game(&eras, vid, json!({"hand": ["AT_013"], "board": [YETI]}), json!({"hand": ["VAN_CS1_113"]}));
        let yeti = g.players[0].board[0];
        loe_era_play(&mut g, "AT_013", yeti);
        loe_era_end_turn(&mut g);
        loe_era_play(&mut g, "VAN_CS1_113", yeti);
        loe_era_end_turn(&mut g);
        loe_era_end_turn(&mut g);
        let h0 = g.hero(0);
        assert!(g.apply(&json!({"type": "attack", "player": 1, "attacker": yeti, "defender": h0})).ok, "version {vid}");
        assert_eq!(g.script_error.get(), None, "version {vid}");
        assert_eq!(damage(&g), want, "version {vid}");
    }
}

#[test]
fn patch_12051_cabal_shadow_priest_works_with_a_full_board() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    const WISP: &str = "VAN_CS2_231";
    // six minions and the Priest: no room for the stolen one; from 12051 it is taken and destroyed
    for (vid, takes) in [("10956", false), ("12051", true), ("12266", true)] {
        let mut g = loe_era_game(&eras, vid, json!({"hand": ["VAN_EX1_091"], "board": [WISP, WISP, WISP, WISP, WISP, WISP]}), json!({"board": [WISP]}));
        let theirs = g.players[1].board[0];
        loe_era_play(&mut g, "VAN_EX1_091", if takes { theirs } else { -1 });
        assert_eq!(g.players[0].board.len(), 7, "version {vid}");
        assert_eq!(g.players[1].board.len(), if takes { 0 } else { 1 }, "version {vid}");
    }
    // with room it takes the minion in every version
    for vid in ["10956", "12051"] {
        let mut g = loe_era_game(&eras, vid, json!({"hand": ["VAN_EX1_091"]}), json!({"board": [WISP]}));
        let theirs = g.players[1].board[0];
        loe_era_play(&mut g, "VAN_EX1_091", theirs);
        assert_eq!(g.players[0].board.len(), 2, "version {vid}");
    }
}

#[test]
fn patch_10833_shadow_of_nothing_stays_and_the_scarab_is_a_beast_from_12051() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    // Mindgames against an empty deck: Shadow of Nothing stays (9166's fix, which the loe pack lacks)
    for vid in ["10833", "10956", "12051", "12266"] {
        let mut g = loe_era_game(&eras, vid, json!({"hand": ["VAN_EX1_345"]}), json!({"deck": []}));
        loe_era_play(&mut g, "VAN_EX1_345", -1);
        loe_era_end_turn(&mut g);
        assert_eq!(g.players[0].board.iter().map(|&m| g.e(m).card_id.to_string()).collect::<Vec<_>>(), vec!["VAN_EX1_345t"], "version {vid}");
    }
    let race = |vid: &str| ruleset::load(&pack::version_view(&eras, vid).unwrap()).unwrap().card("LOE_009t").race.clone();
    assert_eq!((race("10956").as_str(), race("12051").as_str()), ("", "BEAST"));
}

#[test]
fn patch_4944_unleash_the_hounds_costs_2() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    // a Hunter with 2 Mana against two Yetis: launch's Unleash the Hounds (2) makes two Hounds, 5314's (3) can't be played
    for (vid, hounds) in [("4944", 2), ("5314", 0)] {
        let rs: &'static ruleset::Ruleset = Box::leak(Box::new(ruleset::load(&pack::version_view(&eras, vid).unwrap()).unwrap()));
        let deck = json!(["VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231"]);
        let sc = json!({"current": 0, "seed": 7, "players": [
            {"hero": "HERO_05", "mana": 2, "max_mana": 2, "deck": deck, "hand": ["VAN_EX1_538"]},
            {"hero": "HERO_01", "mana": 2, "max_mana": 2, "deck": deck, "board": ["VAN_CS2_182", "VAN_CS2_182"]}]});
        let mut g = classichs_engine::scenario::build_in(rs, &sc).unwrap();
        if let Some(a) = g.legal_actions().into_iter().find(|a| a["type"] == "play") {
            assert!(g.apply(&Value::Object(a)).ok, "version {vid}");
        }
        assert_eq!(g.script_error.get(), None, "version {vid}");
        assert_eq!(g.players[0].board.iter().filter(|&&m| g.e(m).card_id == "EX1_538t").count(), hounds, "version {vid}");
    }
}

/// brm era: a game of version `vid` in a scenario (p0 and p1 over 10 mana and decks of Wisps; p0's turn).
fn brm_era_game(eras: &Files, vid: &str, p0: Value, p1: Value) -> classichs_engine::Game {
    let rs: &'static ruleset::Ruleset = Box::leak(Box::new(ruleset::load(&pack::version_view(eras, vid).unwrap()).unwrap()));
    let side = |hero: &str, over: Value| {
        let mut b = json!({"hero": hero, "mana": 10, "max_mana": 10, "deck": ["VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231"]});
        b.as_object_mut().unwrap().extend(over.as_object().unwrap().clone());
        b
    };
    let sc = json!({"current": 0, "seed": 7, "players": [side("HERO_06", p0), side("HERO_01", p1)]});
    classichs_engine::scenario::build_in(rs, &sc).unwrap()
}

/// brm era: the current player plays `card` from the hand at `target` (-1: none), without a script error; returns
/// the targets of the damage it dealt, in order.
fn brm_era_play(g: &mut classichs_engine::Game, card: &str, target: i64) -> Vec<i64> {
    let e = *g.players[g.current].hand.iter().find(|&&x| g.e(x).card_id == card).unwrap();
    let int = |v: Option<&Value>| classichs_engine::entity::int(v);
    let a = g.legal_actions().into_iter().find(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target);
    let r = g.apply(&Value::Object(a.unwrap_or_else(|| panic!("play {card}"))));
    assert!(r.ok, "play {card}");
    assert_eq!(g.script_error.get(), None, "play {card}");
    g.history.last().unwrap().events.iter().map(|e| e.to_value()).filter(|e| e["type"] == "damage").map(|e| e["target"].as_i64().unwrap()).collect()
}

fn brm_era_board(g: &classichs_engine::Game, p: usize) -> Vec<String> {
    g.players[p].board.iter().map(|&m| g.e(m).card_id.to_string()).collect()
}

#[test]
fn patch_9166_swipe_and_explosive_shot_deal_all_their_damage_first() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    const SWIPE: &str = "VAN_CS2_012";
    const SHOT: &str = "VAN_EX1_537";
    const YETI: &str = "VAN_CS2_182";
    // Swipe on an Imp Gang Boss (2/4): its Imp comes after the 1 damage to the others (9166) or before it (8311)
    for (vid, left) in [("8311", vec![]), ("9166", vec!["BRM_006t"])] {
        let mut g = brm_era_game(&eras, vid, json!({"hand": [SWIPE]}), json!({"board": ["BRM_006"]}));
        let boss = g.players[1].board[0];
        brm_era_play(&mut g, SWIPE, boss);
        assert_eq!(brm_era_board(&g, 1), left, "version {vid}");
    }
    // Explosive Shot on a Dragon Egg between two Yetis: its Whelp is hit too before 9166
    for (vid, left) in [("8311", vec![YETI, YETI]), ("9166", vec![YETI, "BRM_022t", YETI])] {
        let mut g = brm_era_game(&eras, vid, json!({"hand": [SHOT]}), json!({"board": [YETI, "BRM_022", YETI]}));
        let (y0, egg) = (g.players[1].board[0], g.players[1].board[1]);
        brm_era_play(&mut g, SHOT, egg);
        assert_eq!(brm_era_board(&g, 1), left, "version {vid}");
        assert_eq!(g.e(y0).health(), 3, "version {vid}: the left Yeti is hit");
    }
    // 9166: the hits (and so the triggers) in the wiki's order: Explosive Shot middle, right, left; Swipe the target,
    // then the other enemies newest first
    for (card, more) in [(SHOT, 0), (SWIPE, 1)] {
        let mut g = brm_era_game(&eras, "9166", json!({"hand": [card]}), json!({"board": [YETI, YETI, YETI]}));
        let b = g.players[1].board.clone();
        let hits = brm_era_play(&mut g, card, b[1]);
        assert_eq!(hits, [vec![b[1], b[2], b[0]], vec![g.players[1].hero; more]].concat(), "{card}");
    }
}

#[test]
fn patch_9166_shadow_of_nothing_stays_and_the_murloc_costs_0() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    // Mindgames against an empty deck: a 0/1 Shadow of Nothing, gone at the end of the turn before 9166
    for (vid, left) in [("8311", 0), ("9166", 1)] {
        let mut g = brm_era_game(&eras, vid, json!({"hero": "HERO_09", "hand": ["VAN_EX1_345"]}), json!({"deck": []}));
        brm_era_play(&mut g, "VAN_EX1_345", -1);
        assert_eq!(brm_era_board(&g, 0), vec!["VAN_EX1_345t"], "version {vid}");
        assert!(g.apply(&json!({"type": "end_turn", "player": 0})).ok);
        assert_eq!(g.players[0].board.len(), left, "version {vid}");
    }
    // I Am Murloc's Murloc (Elite Tauren Chieftain)
    let cost = |vid: &str| ruleset::load(&pack::version_view(&eras, vid).unwrap()).unwrap().card("PRO_001at").cost;
    assert_eq!((cost("8311"), cost("9166")), (1, 0));
}

/// The gvg era: a game of version `vid` in a scenario (p0's turn, 10 mana each, decks of Wisps; p0 and p1 merged
/// over that).
fn gvg_era_game(eras: &Files, vid: &str, p0: Value, p1: Value) -> classichs_engine::Game {
    let rs: &'static ruleset::Ruleset = Box::leak(Box::new(ruleset::load(&pack::version_view(eras, vid).unwrap()).unwrap()));
    let side = |hero: &str, over: Value| {
        let mut b = json!({"hero": hero, "mana": 10, "max_mana": 10, "deck": ["VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231"]});
        b.as_object_mut().unwrap().extend(over.as_object().unwrap().clone());
        b
    };
    let sc = json!({"current": 0, "seed": 7, "players": [side("HERO_08", p0), side("HERO_01", p1)]});
    classichs_engine::scenario::build_in(rs, &sc).unwrap()
}

/// The gvg era: the current player plays `card` from the hand at `target` (-1: none).
fn gvg_era_play(g: &mut classichs_engine::Game, card: &str, target: i64) {
    use classichs_engine::entity::int;
    let e = *g.players[g.current].hand.iter().find(|&&x| g.e(x).card_id == card).unwrap();
    let a = g.legal_actions().into_iter().find(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target);
    let r = g.apply(&Value::Object(a.unwrap_or_else(|| panic!("no legal play of {card}"))));
    assert!(r.ok, "{card}: {}", r.error);
    assert_eq!(g.script_error.get(), None, "{card}");
}

#[test]
fn patch_7628_nerfs_undertaker() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    for (vid, want) in [("7234", (2, 3)), ("7628", (2, 2)), ("7835", (2, 2))] {
        let mut g = gvg_era_game(&eras, vid, json!({"board": ["FP1_028"], "hand": ["VAN_EX1_029", "VAN_CS2_231"]}), json!({}));
        let u = g.players[0].board[0];
        gvg_era_play(&mut g, "VAN_EX1_029", -1);
        gvg_era_play(&mut g, "VAN_CS2_231", -1);
        assert_eq!((g.e(u).atk(), g.e(u).health()), want, "version {vid}: Leper Gnome counts, the Wisp does not");
    }
}

#[test]
fn patch_7835_fixes_cogmaster_after_a_swap() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    // Cogmaster (1/2) next to a Mech: 3/2; Crazed Alchemist swaps it to 2/3, and the Mech gives +2 again only from 7835
    for (vid, want) in [("7234", (2, 3)), ("7628", (2, 3)), ("7835", (4, 3))] {
        let mut g = gvg_era_game(&eras, vid, json!({"board": ["GVG_013", "GVG_006"], "hand": ["VAN_EX1_059"]}), json!({}));
        let cog = g.players[0].board[0];
        assert_eq!((g.e(cog).atk(), g.e(cog).health()), (3, 2), "version {vid}");
        gvg_era_play(&mut g, "VAN_EX1_059", cog);
        assert_eq!((g.e(cog).atk(), g.e(cog).health()), want, "version {vid}");
    }
    // without the swap every version gives the bonus
    let mut g = gvg_era_game(&eras, "7234", json!({"board": ["GVG_013"], "hand": ["GVG_006"]}), json!({}));
    let cog = g.players[0].board[0];
    assert_eq!(g.e(cog).atk(), 1);
    gvg_era_play(&mut g, "GVG_006", -1);
    assert_eq!(g.e(cog).atk(), 3);
}

/// The og era: version `vid`'s rules (loaded once by each caller).
fn og_era_rules(eras: &Files, vid: &str) -> &'static ruleset::Ruleset {
    Box::leak(Box::new(ruleset::load(&pack::version_view(eras, vid).unwrap()).unwrap()))
}

/// The og era: a game in a scenario (p0's turn, 10 mana each, decks of Wisps; p0 and p1 merged over that).
fn og_era_game(rs: &'static ruleset::Ruleset, seed: i64, p0: Value, p1: Value) -> classichs_engine::Game {
    let side = |hero: &str, over: Value| {
        let mut b = json!({"hero": hero, "mana": 10, "max_mana": 10, "deck": ["VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231"]});
        b.as_object_mut().unwrap().extend(over.as_object().unwrap().clone());
        b
    };
    let sc = json!({"current": 0, "seed": seed, "players": [side("HERO_04", p0), side("HERO_01", p1)]});
    classichs_engine::scenario::build_in(rs, &sc).unwrap()
}

#[test]
fn patch_13030_shifter_zerus_never_becomes_a_choose_one_minion() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    // Shifter Zerus (alone in an empty-deck hand) shifts at the start of p0's next turn, over 150 seeds: into Druid of
    // the Claw, Ancient of Lore… only in 12574
    for (vid, fixed) in [("12574", false), ("13030", true), ("13619", true), ("13714", true)] {
        let rs = og_era_rules(&eras, vid);
        let (mut choose_one, mut shifted) = (0, 0);
        for seed in 1..=150 {
            let mut g = og_era_game(rs, seed, json!({"hand": ["OG_123"], "deck": []}), json!({}));
            for p in [0, 1] {
                assert!(g.apply(&json!({"type": "end_turn", "player": p})).ok, "version {vid}");
            }
            assert_eq!(g.script_error.get(), None, "version {vid}");
            let now = g.e(g.players[0].hand[0]).card_id.to_string(); // Shifter Zerus itself now and then
            shifted += usize::from(now != "OG_123");
            if rs.card(&now).keywords.iter().any(|k| k == "CHOOSE_ONE") {
                choose_one += 1;
            }
        }
        assert!(shifted > 140, "version {vid}: {shifted} shifted");
        assert_eq!(choose_one == 0, fixed, "version {vid}: {choose_one} Choose One minions");
    }
}

#[test]
fn patch_12574_shadow_of_nothing_stays_as_since_9166() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    // Mindgames against an empty deck: the 0/1 Shadow of Nothing stays at the end of the turn (the og pack's
    // Classic script destroyed it)
    for vid in ["12574", "13030", "13619", "13714"] {
        let mut g = og_era_game(og_era_rules(&eras, vid), 1, json!({"hero": "HERO_09", "hand": ["VAN_EX1_345"]}), json!({"deck": []}));
        let a = g.legal_actions().into_iter().find(|a| a["type"] == "play").unwrap();
        assert!(g.apply(&Value::Object(a)).ok, "version {vid}");
        assert!(g.apply(&json!({"type": "end_turn", "player": 0})).ok, "version {vid}");
        assert_eq!(g.script_error.get(), None, "version {vid}");
        assert_eq!(g.players[0].board.iter().map(|&m| g.e(m).card_id.to_string()).collect::<Vec<_>>(), vec!["VAN_EX1_345t"], "version {vid}");
    }
}

#[test]
fn patch_13619_the_tidal_hand_needs_a_free_board_slot() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    let full = json!(["VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231"]);
    for (vid, usable) in [("13030", true), ("13619", false), ("13714", false)] {
        let rs = og_era_rules(&eras, vid);
        let g = og_era_game(rs, 1, json!({"hero_power": "OG_006b", "board": full}), json!({}));
        assert_eq!(g.legal_actions().iter().any(|a| a["type"] == "hero_power"), usable, "version {vid}: a full board");
        // with room it summons a 1/1 Silver Hand Murloc in every version
        let mut g = og_era_game(rs, 1, json!({"hero_power": "OG_006b"}), json!({}));
        let a = g.legal_actions().into_iter().find(|a| a["type"] == "hero_power").unwrap();
        assert!(g.apply(&Value::Object(a)).ok, "version {vid}");
        assert_eq!(g.players[0].board.iter().map(|&m| g.e(m).card_id.to_string()).collect::<Vec<_>>(), vec!["OG_006a"]);
    }
}

/// Every card of every version (collectible or not: tokens, the cards powers make) played from the hand into a
/// busy board, a few bot moves after, and every hero's power used: no script error.
#[test]
#[ignore = "slow (every card, tokens too: 6 min); eras_versions.rs covers every version in the usual run: cargo test --release --test eras -- --ignored"]
fn every_card_of_every_version_plays_without_a_script_error() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    const WISP: &str = "VAN_CS2_231";
    const YETI: &str = "VAN_CS2_182";
    const RAPTOR: &str = "VAN_CS2_172";
    for v in pack::versions(&eras) {
        let rs: &'static ruleset::Ruleset = Box::leak(Box::new(ruleset::load(&pack::version_view(&eras, &v.id).unwrap()).unwrap()));
        let deck = json!([RAPTOR, YETI, "VAN_CS2_029", WISP, "VAN_CS2_008", "VAN_EX1_012", WISP, YETI]);
        let game = |hero: &str, hand: Value| {
            let sc = json!({"current": 0, "seed": 7, "players": [
                {"hero": hero, "mana": 10, "max_mana": 10, "deck": deck, "hand": hand, "board": [RAPTOR, "VAN_CS2_146", WISP], "weapon": "VAN_CS2_106"},
                {"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": deck, "board": [YETI, "VAN_CS2_125"], "hand": [WISP, "VAN_CS2_024"]}]});
            classichs_engine::scenario::build_in(rs, &sc).unwrap()
        };
        let run = |mut g: classichs_engine::Game, a: &serde_json::Map<String, Value>, what: &str| {
            assert!(g.apply(&Value::Object(a.clone())).ok, "version {} {what}", v.id);
            for _ in 0..4 {
                if g.game_over {
                    break;
                }
                let p = g.pending.as_ref().map_or(g.current, |c| c.player);
                let b = classichs_engine::bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(b)).ok, "version {} {what}", v.id);
            }
            assert_eq!(g.script_error.get(), None, "version {} {what} {a:?}", v.id);
        };
        let mut ids: Vec<&String> = rs.cards.keys().collect();
        ids.sort();
        let mut n = 0;
        for id in ids {
            let c = rs.card(id);
            if !matches!(c.kind.as_str(), "MINION" | "SPELL" | "WEAPON" | "CHAMPION") || c.script.is_empty() || c.set == "MISSIONS" {
                continue;
            }
            let g = game("HERO_08", json!([id, YETI]));
            let e = *g.players[0].hand.iter().find(|&&x| g.e(x).card_id == *id).unwrap();
            for a in g.legal_actions().into_iter().filter(|a| a["type"] == "play" && classichs_engine::entity::int(a.get("entity")) == e).take(3) {
                run(g.clone_state(), &a, id);
                n += 1;
            }
        }
        for hero in ["HERO_01", "HERO_02", "HERO_03", "HERO_04", "HERO_05", "HERO_06", "HERO_07", "HERO_08", "HERO_09"] {
            let g = game(hero, json!([]));
            for a in g.legal_actions().into_iter().filter(|a| a["type"] == "hero_power").take(3) {
                run(g.clone_state(), &a, hero);
            }
        }
        eprintln!("version {}: {n} plays", v.id);
        assert!(n > 300, "version {}: {n}", v.id);
    }
}

/// The client hands the engine a version's view as a pack of its own (game/rules.gd): load_pack takes it and plays
/// by that version's rules.
#[test]
fn load_pack_takes_a_version_view() {
    let Some(eras) = built("packs/eras") else {
        eprintln!("no python3: skipped");
        return;
    };
    let view = pack::version_view(&eras, "6485").unwrap();
    let dir = std::env::temp_dir().join(format!("eras-view-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    for (p, d) in &view {
        std::fs::create_dir_all(dir.join(p).parent().unwrap()).unwrap();
        std::fs::write(dir.join(p), d).unwrap();
    }
    let mut e = Engine::new();
    let r: Value = serde_json::from_str(&e.call(&json!({"op": "load_pack", "path": dir}).to_string())).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(r["ok"], true, "{r}");
    assert_eq!(r["pack"].as_str(), pack::versions(&eras).iter().find(|v| v.id == "6485").map(|v| v.rules_hash.as_str()));
    let d = json!({"hero": "HERO_08", "cards": classichs_engine::deck::basic("MAGE")});
    let r: Value = serde_json::from_str(&e.call(&json!({"op": "new", "game": "v", "pack": r["pack"], "decks": [d, d], "seed": 1}).to_string())).unwrap();
    assert_eq!(r["ok"], true, "{r}");
}
