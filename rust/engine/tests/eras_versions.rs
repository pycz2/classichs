//! Hearthstone 2014–2019 (packs/eras): every version's cards play without a script error, and each version patch's
//! changes as the engine plays them (one file per era in eras_versions/: the card values of that version against the
//! version before, the behaviour changes played out). The pack is built once by tools/pack.py; a version's view is
//! loaded as a one-version pack. Needs python3 (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::pack::{self, Files};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{bot, scenario, Game};
use serde_json::{json, Map, Value};
use std::collections::{BTreeSet, HashMap};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// packs/eras built once; None without python3.
fn eras() -> Option<&'static Files> {
    static F: OnceLock<Option<Files>> = OnceLock::new();
    F.get_or_init(|| {
        let out = std::env::temp_dir().join(format!("eras-versions-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/eras", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build packs/eras: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(files)
    })
    .as_ref()
}

/// A version's rules (its view loaded as a one-version pack), loaded once; None without python3.
fn version(vid: &str) -> Option<&'static Ruleset> {
    static R: OnceLock<Mutex<HashMap<String, &'static Ruleset>>> = OnceLock::new();
    let files = eras()?;
    let m = R.get_or_init(Default::default);
    if let Some(rs) = m.lock().unwrap().get(vid) {
        return Some(*rs);
    }
    let view = pack::version_view(files, vid).unwrap_or_else(|e| panic!("version {vid}: {e}"));
    let rs = ruleset::load(&view).unwrap_or_else(|e| panic!("version {vid}: {e}"));
    Some(*m.lock().unwrap().entry(vid.to_string()).or_insert(rs))
}

#[allow(dead_code)]
const WISP: &str = "VAN_CS2_231";
#[allow(dead_code)]
const YETI: &str = "VAN_CS2_182";
#[allow(dead_code)]
const FIREBALL: &str = "VAN_CS2_029";
#[allow(dead_code)]
const FROSTBOLT: &str = "VAN_CS2_024";
#[allow(dead_code)]
const RAPTOR: &str = "VAN_CS2_172"; // Bloodfen Raptor, a 3/2 Beast
#[allow(dead_code)]
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];
#[allow(dead_code)]
const NONE: Id = -1;

struct T {
    g: Game,
}

/// A scenario in version `vid`: player 0 (a Mage) to act with 10 mana against a Warrior.
fn game(vid: &str, p0: Value, p1: Value) -> Option<T> {
    let rs = version(vid)?;
    let merge = |base: Value, over: Value| {
        let mut b = base.as_object().unwrap().clone();
        b.extend(over.as_object().unwrap().clone());
        Value::Object(b)
    };
    let d0 = json!({"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL});
    let d1 = json!({"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL});
    let sc = json!({"current": 0, "seed": 7, "players": [merge(d0, p0), merge(d1, p1)]});
    Some(T { g: scenario::build_in(rs, &sc).unwrap_or_else(|e| panic!("version {vid}: scenario: {e}")) })
}

/// `scene!("31761", {player 0}, {player 1})`: a scenario in that version (the test returns without python3).
#[allow(unused_macros)]
macro_rules! scene {
    ($vid:expr, $p0:tt, $p1:tt) => {
        match game($vid, json!($p0), json!($p1)) {
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
        let e = self.hand_id(card);
        let last = self.g.players[self.g.current].board.len() as i64;
        self.act(&format!("play {card}"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target
                && (int(a.get("pos")) == -1 || int(a.get("pos")) == last) && int(a.get("choice")) == -1
        })
    }
    fn can_play(&self, card: &str) -> bool {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e)
    }
    fn power_on(&mut self, target: Id) -> &mut Self {
        self.act("hero power", |a| a["type"] == "hero_power" && int(a.get("target")) == target)
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
    fn events(&self) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).collect()
    }
    fn has(&self, p: usize, card: &str) -> bool {
        self.cards(p).iter().any(|c| c == card)
    }
}

/// A card's (cost, attack, health) in a version.
#[allow(dead_code)]
fn stats(vid: &str, id: &str) -> Option<(i64, i64, i64)> {
    let c = version(vid)?.card(id);
    Some((c.cost, c.attack, c.health))
}

/// The card ids a version's patch names (`cards`, `add`) and its own scripts define.
fn patched(vid: &str) -> BTreeSet<String> {
    let dir = repo().join("packs/eras/versions").join(vid);
    let p: Value = serde_json::from_str(&std::fs::read_to_string(dir.join("patch.json")).unwrap()).unwrap();
    let mut ids: BTreeSet<String> = p["cards"].as_object().map(|m| m.keys().cloned().collect()).unwrap_or_default();
    ids.extend(p["add"].as_array().into_iter().flatten().filter_map(|c| c["id"].as_str().map(String::from)));
    if let Ok(dir) = std::fs::read_dir(dir.join("scripts")) {
        for f in dir {
            let lua = std::fs::read_to_string(f.unwrap().path()).unwrap();
            // `cards.<ID> = {` / `cards["<ID>"] = {`
            for line in lua.lines() {
                let l = line.trim_start();
                if let Some(rest) = l.strip_prefix("cards.").or_else(|| l.strip_prefix("cards[\"")) {
                    let id: String = rest.chars().take_while(|c| c.is_ascii_alphanumeric() || *c == '_').collect();
                    if !id.is_empty() && l.contains('=') {
                        ids.insert(id);
                    }
                }
            }
        }
    }
    ids
}

/// Every collectible card of every version (and every card its patch or scripts change, collectible or not) is played
/// in a small scenario, each of its plays (up to 3; 6 for a changed card) followed by a few bot moves: no script error.
/// Versions with the same rules are played once, several at a time.
#[test]
fn every_card_of_every_version_plays_without_a_script_error() {
    let Some(files) = eras() else { return };
    let mut seen = BTreeSet::new();
    let vids: Vec<String> = pack::versions(files).into_iter().filter(|v| seen.insert(v.rules_hash.clone())).map(|v| v.id).collect();
    let threads = std::thread::available_parallelism().map_or(4, |n| n.get());
    let bad: Vec<String> = std::thread::scope(|s| {
        let hs: Vec<_> = vids.chunks(vids.len().div_ceil(threads)).map(|part| s.spawn(move || part.iter().flat_map(|v| plays(v)).collect::<Vec<_>>())).collect();
        hs.into_iter().flat_map(|h| h.join().unwrap()).collect()
    });
    assert!(bad.is_empty(), "{} problems:\n{}", bad.len(), bad.join("\n"));
}

/// The problems of one version's every-card run.
fn plays(vid: &str) -> Vec<String> {
    let rs = version(vid).unwrap();
    let changed = patched(vid);
    let mut ids: Vec<&String> = rs.cards.keys().filter(|k| rs.card(k).collectible || changed.contains(*k)).collect();
    ids.sort();
    let (mut n, mut bad) = (0, vec![]);
    for id in ids {
        let c = rs.card(id);
        if !matches!(c.kind.as_str(), "MINION" | "SPELL" | "WEAPON" | "CHAMPION") {
            continue;
        }
        let deck = json!([RAPTOR, YETI, FIREBALL, "VAN_CS2_008", "VAN_EX1_012", WISP, RAPTOR, YETI]);
        let t = game(vid, json!({"hand": [id, YETI, FIREBALL, RAPTOR], "board": [RAPTOR, "VAN_CS2_146", WISP], "deck": deck,
            "weapon": "VAN_CS2_106"}), json!({"board": [YETI, "VAN_CS2_125"], "hand": [WISP, FROSTBOLT], "deck": deck})).unwrap();
        let e = *t.g.players[0].hand.iter().find(|&&x| t.g.e(x).card_id == *id).unwrap();
        let plays: Vec<_> = t.g.legal_actions().into_iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).collect();
        for a in plays.into_iter().take(if changed.contains(id) { 6 } else { 3 }) {
            let mut g = t.g.clone_state();
            if !g.apply(&Value::Object(a.clone())).ok {
                bad.push(format!("version {vid}: {id}: {a:?} not applied"));
                break;
            }
            for _ in 0..4 {
                if g.game_over || g.script_error.get().is_some() {
                    break;
                }
                let p = g.pending.as_ref().map_or(g.current, |c| c.player);
                let b = bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(b)).ok);
            }
            if let Some(err) = g.script_error.get() {
                bad.push(format!("version {vid}: {id} {a:?}: {err}"));
                break;
            }
            n += 1;
        }
    }
    if n < 300 {
        bad.push(format!("version {vid}: only {n} plays"));
    }
    bad
}
