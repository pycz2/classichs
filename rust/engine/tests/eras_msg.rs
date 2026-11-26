//! Hearthstone 2014–2019 (packs/eras): the versions of the Mean Streets of Gadgetzan era (packs/eras/versions/15590,
//! 16214, 17720), each played out against the version before it. Needs python3 (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::pack::{self, Files};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{scenario, Game};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// A pack source built by tools/pack.py, read as the engine reads it; None without python3.
fn built(src: &str) -> Option<Files> {
    let out = std::env::temp_dir().join(format!("eras-msg-{}-{}.cardpack", src.replace('/', "_"), std::process::id()));
    let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", src, "-o"]).arg(&out).output().ok()?;
    assert!(build.status.success(), "pack.py build {src}: {}", String::from_utf8_lossy(&build.stdout));
    let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
    let _ = std::fs::remove_file(&out);
    Some(files)
}

/// The ruleset of an eras version ("msg": the Mean Streets of Gadgetzan pack itself, built as it is), each built once.
fn rs(vid: &str) -> Option<&'static Ruleset> {
    static ERAS: OnceLock<Option<Files>> = OnceLock::new();
    static MSG: OnceLock<Option<&'static Ruleset>> = OnceLock::new();
    static R: OnceLock<Mutex<HashMap<String, &'static Ruleset>>> = OnceLock::new();
    if vid == "msg" {
        return *MSG.get_or_init(|| built("packs/msg").map(|f| ruleset::load(&f).unwrap()));
    }
    let eras = ERAS.get_or_init(|| built("packs/eras")).as_ref()?;
    let mut m = R.get_or_init(Default::default).lock().unwrap();
    Some(*m.entry(vid.to_string()).or_insert_with(|| {
        let view = pack::version_view(eras, vid).unwrap_or_else(|e| panic!("version {vid}: {e}"));
        ruleset::load(&view).unwrap_or_else(|e| panic!("version {vid}: {e}"))
    }))
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];
const NONE: Id = -1;

struct T {
    g: Game,
}

/// A game of version `vid` in a scenario: p0 and p1 are merged over the defaults (10 mana each, decks of Wisps).
fn game(vid: &str, seed: i64, p0: Value, p1: Value) -> Option<T> {
    let rs = rs(vid)?;
    let merge = |base: Value, over: Value| {
        let mut b = base.as_object().unwrap().clone();
        b.extend(over.as_object().unwrap().clone());
        Value::Object(b)
    };
    let d0 = json!({"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL});
    let d1 = json!({"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL});
    let sc = json!({"current": 0, "seed": seed, "players": [merge(d0, p0), merge(d1, p1)]});
    Some(T { g: scenario::build_in(rs, &sc).unwrap() })
}

macro_rules! scene {
    ($vid:expr, $seed:expr, $p0:tt, $p1:tt) => {
        match game($vid, $seed, json!($p0), json!($p1)) {
            Some(t) => t,
            None => {
                eprintln!("no python3: skipped");
                return;
            }
        }
    };
}

impl T {
    fn cards(&self, p: usize) -> Vec<String> {
        self.g.players[p].board.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn hand(&self, p: usize) -> Vec<String> {
        self.g.players[p].hand.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
    }
    fn act(&mut self, what: &str, f: impl Fn(&Map<String, Value>) -> bool) -> &mut Self {
        let a = self.g.legal_actions().into_iter().find(|a| f(a)).unwrap_or_else(|| panic!("no legal action: {what}"));
        let r = self.g.apply(&Value::Object(a));
        assert!(r.ok, "{what}: {}", r.error);
        assert_eq!(self.g.script_error.get(), None, "{what}");
        self
    }
    fn play(&mut self, card: &str, target: Id) -> &mut Self {
        let p = self.g.current;
        let e = *self.g.players[p].hand.iter().find(|&&e| self.g.e(e).card_id == card).unwrap_or_else(|| panic!("{card} not in hand"));
        let last = self.g.players[p].board.len() as i64;
        self.act(&format!("play {card}"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target && (int(a.get("pos")) == -1 || int(a.get("pos")) == last)
        })
    }
    fn end_turn(&mut self) -> &mut Self {
        self.act("end turn", |a| a["type"] == "end_turn")
    }
    /// The stats of p's cards of `card` in `zone` ("hand" or "deck").
    fn stats_in(&self, p: usize, zone: &str, card: &str) -> Vec<(i64, i64)> {
        let z = if zone == "hand" { &self.g.players[p].hand } else { &self.g.players[p].deck };
        z.iter().filter(|&&e| self.g.e(e).card_id == card).map(|&e| self.stats(e)).collect()
    }
}

/// 7.0.0.15590: The Mistcaller gives the minions in the hand and the deck +1/+1, as its text says; before it, the
/// minions in the hand and every minion drawn later that game (the deck was not touched). The msg pack (its release
/// build 15590) and the later ones have it.
#[test]
fn mistcaller_buffs_the_deck_from_15590() {
    for vid in ["msg", "15590", "16214", "17720", "18336", "20022", "20457", "22115"] {
        let mut t = scene!(vid, 7, {"hand": ["AT_054", YETI], "deck": [YETI, YETI]}, {});
        t.play("AT_054", NONE);
        assert_eq!(t.stats_in(0, "hand", YETI), vec![(5, 6)], "{vid}: the hand");
        assert_eq!(t.stats_in(0, "deck", YETI), vec![(5, 6), (5, 6)], "{vid}: the deck");
        // drawn: +1/+1 once either way (by the draw until 15590, in the deck since)
        t.end_turn().end_turn();
        assert_eq!(t.stats_in(0, "hand", YETI), vec![(5, 6), (5, 6)], "{vid}: drawn");
    }
}

/// The 2017-01-24 hotfix (version 16214): Kabal Chemist can make a Dragonfire Potion; until then it could not.
#[test]
fn kabal_chemist_makes_dragonfire_potion_from_16214() {
    for (vid, can) in [("15590", false), ("16214", true), ("17720", true)] {
        let mut made = std::collections::BTreeSet::new();
        for seed in 0..80 {
            let mut t = scene!(vid, seed, {"hand": ["CFM_619"]}, {});
            t.play("CFM_619", NONE);
            made.extend(t.hand(0));
        }
        assert_eq!(made.contains("CFM_662"), can, "{vid}: {made:?}");
        assert_eq!(made.len(), if can { 10 } else { 9 }, "{vid}: {made:?}");
    }
}

/// 7.1.0.17720: Small-Time Buccaneer 1/1 (was 1/2), Spirit Claws costs 2 (was 1).
#[test]
fn patch_17720_nerfs_small_time_buccaneer_and_spirit_claws() {
    for (vid, hp, cost) in [("16214", 2, 1), ("17720", 1, 2)] {
        let Some(rs) = rs(vid) else { return };
        assert_eq!((rs.card("CFM_325").attack, rs.card("CFM_325").health), (1, hp), "{vid}");
        assert_eq!(rs.card("KAR_063").cost, cost, "{vid}");
    }
}

/// 7.1.0.17720: Snipe triggers after Potion of Polymorph (on the Sheep): the After Summon triggers see the Sheep.
#[test]
fn snipe_hits_the_sheep_of_potion_of_polymorph_from_17720() {
    for (vid, fixed) in [("16214", false), ("17720", true), ("18336", true), ("20022", true), ("20457", true), ("22115", true)] {
        let mut t = scene!(vid, 7, {"hero": "HERO_05", "secrets": ["CFM_620", "VAN_EX1_609"]}, {"hand": [YETI]});
        t.end_turn();
        t.play(YETI, NONE);
        if fixed {
            assert!(t.cards(1).is_empty(), "{vid}: Snipe killed the Sheep");
            assert!(t.g.players[0].secrets.is_empty(), "{vid}");
        } else {
            assert_eq!(t.cards(1), vec!["VAN_CS2_tk1"], "{vid}: the Sheep lives");
        }
    }
}
