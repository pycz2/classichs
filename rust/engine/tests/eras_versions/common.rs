//! What the tests of packs/eras share (rust/engine/tests/eras_versions.rs and eras_<era>.rs): the pack built once,
//! a version's rules, a scenario in a version (`scene!`) and its helpers.

#![allow(dead_code, unused_imports)]

pub use classichs_engine::entity::{int, Id};
pub use classichs_engine::pack::{self, Files};
pub use classichs_engine::ruleset::{self, Ruleset};
pub use classichs_engine::{bot, scenario, Game};
pub use serde_json::{json, Map, Value};
pub use std::collections::{BTreeSet, HashMap};
pub use std::path::PathBuf;
pub use std::sync::{Mutex, OnceLock};

pub fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// packs/eras built once; None without python3.
pub fn eras() -> Option<&'static Files> {
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
pub fn version(vid: &str) -> Option<&'static Ruleset> {
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
pub const WISP: &str = "VAN_CS2_231";
#[allow(dead_code)]
pub const YETI: &str = "VAN_CS2_182";
#[allow(dead_code)]
pub const FIREBALL: &str = "VAN_CS2_029";
#[allow(dead_code)]
pub const FROSTBOLT: &str = "VAN_CS2_024";
#[allow(dead_code)]
pub const RAPTOR: &str = "VAN_CS2_172"; // Bloodfen Raptor, a 3/2 Beast
#[allow(dead_code)]
pub const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];
#[allow(dead_code)]
pub const NONE: Id = -1;

pub struct T {
    pub g: Game,
}

/// A scenario in version `vid`: player 0 (a Mage) to act with 10 mana against a Warrior.
pub fn game(vid: &str, p0: Value, p1: Value) -> Option<T> {
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
    pub fn on_board(&self, p: usize, card: &str) -> Id {
        *self.g.players[p].board.iter().find(|&&m| self.g.e(m).card_id == card).unwrap_or_else(|| panic!("{card} not on board {p}"))
    }
    pub fn cards(&self, p: usize) -> Vec<String> {
        self.g.players[p].board.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    pub fn hand(&self, p: usize) -> Vec<String> {
        self.g.players[p].hand.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    pub fn deck(&self, p: usize) -> Vec<String> {
        self.g.players[p].deck.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    pub fn hero(&self, p: usize) -> Id {
        self.g.players[p].hero
    }
    pub fn power(&self, p: usize) -> String {
        self.g.e(self.g.players[p].hero_power).card_id.to_string()
    }
    pub fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
    }
    pub fn armor(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).tag("ARMOR")
    }
    pub fn hp(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).health()
    }
    pub fn act(&mut self, what: &str, f: impl Fn(&Map<String, Value>) -> bool) -> &mut Self {
        let a = self.g.legal_actions().into_iter().find(|a| f(a)).unwrap_or_else(|| panic!("no legal action: {what}"));
        let r = self.g.apply(&Value::Object(a));
        assert!(r.ok, "{what}: {}", r.error);
        assert_eq!(self.g.script_error.get(), None, "{what}");
        self
    }
    pub fn hand_id(&self, card: &str) -> Id {
        let p = self.g.current;
        *self.g.players[p].hand.iter().find(|&&e| self.g.e(e).card_id == card).unwrap_or_else(|| panic!("{card} not in hand"))
    }
    pub fn play(&mut self, card: &str, target: Id) -> &mut Self {
        let e = self.hand_id(card);
        let last = self.g.players[self.g.current].board.len() as i64;
        self.act(&format!("play {card}"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target
                && (int(a.get("pos")) == -1 || int(a.get("pos")) == last) && int(a.get("choice")) == -1
        })
    }
    pub fn can_play(&self, card: &str) -> bool {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e)
    }
    pub fn power_on(&mut self, target: Id) -> &mut Self {
        self.act("hero power", |a| a["type"] == "hero_power" && int(a.get("target")) == target)
    }
    pub fn attack(&mut self, a: Id, d: Id) -> &mut Self {
        self.act("attack", |x| x["type"] == "attack" && int(x.get("attacker")) == a && int(x.get("defender")) == d)
    }
    pub fn end_turn(&mut self) -> &mut Self {
        self.act("end turn", |a| a["type"] == "end_turn")
    }
    pub fn cost(&self, card: &str) -> i64 {
        self.g.cost(self.hand_id(card))
    }
    pub fn events(&self) -> Vec<Map<String, Value>> {
        self.g.history.iter().flat_map(|h| h.events()).collect()
    }
    pub fn has(&self, p: usize, card: &str) -> bool {
        self.cards(p).iter().any(|c| c == card)
    }
}

/// A card's (cost, attack, health) in a version.
#[allow(dead_code)]
pub fn stats(vid: &str, id: &str) -> Option<(i64, i64, i64)> {
    let c = version(vid)?.card(id);
    Some((c.cost, c.attack, c.health))
}

