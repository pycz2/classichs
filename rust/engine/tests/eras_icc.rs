//! Hearthstone 2014–2019 (packs/eras): the Knights of the Frozen Throne versions on the icc pack, 9.0.0.20457 (the
//! release), 9.1.0.20970 (Innervate, Murloc Warleader…), 9.2.0.21517 (the mechanics update: Unlicensed Apothecary,
//! Counterspell, Wild Pyromancer, Lord Jaraxxus and the Secrets, the cost-reduction order) and 9.4.0.22115 (Marin the
//! Fox, Crush's cost order). Each behaviour change is played in its version and in the one before. Needs python3
//! (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{pack, scenario, Game};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::OnceLock;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The rulesets of the four versions, the pack built once; None without python3.
fn versions() -> Option<&'static HashMap<&'static str, &'static Ruleset>> {
    static R: OnceLock<Option<HashMap<&'static str, &'static Ruleset>>> = OnceLock::new();
    R.get_or_init(|| {
        let out = std::env::temp_dir().join(format!("eras-icc-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/eras", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(["20457", "20970", "21517", "22115"].into_iter().map(|v| {
            (v, ruleset::load(&pack::version_view(&files, v).unwrap()).unwrap_or_else(|e| panic!("version {v}: {e}")))
        }).collect())
    })
    .as_ref()
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const RAIDER: &str = "VAN_CS2_168"; // Murloc Raider 2/1
const NAGA: &str = "LOE_038"; // Naga Sea Witch: your cards cost (5)
const PYROMANCER: &str = "VAN_NEW1_020";
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];

struct T {
    g: Game,
}

/// A game of version `v`: p0 and p1 are merged over the defaults (10 mana each, decks of Wisps); p0's turn.
fn game(v: &str, p0: Value, p1: Value) -> Option<T> {
    let rs = versions()?[v];
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
    ($v:expr, $p0:tt, $p1:tt) => {
        match game($v, json!($p0), json!($p1)) {
            Some(t) => t,
            None => {
                eprintln!("no python3: skipped");
                return;
            }
        }
    };
}

impl T {
    fn on_board(&self, p: usize, card: &str) -> Id {
        *self.g.players[p].board.iter().find(|&&m| self.g.e(m).card_id == card).unwrap_or_else(|| panic!("{card} not on board {p}"))
    }
    fn cards(&self, ids: &[Id]) -> Vec<String> {
        ids.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
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
    fn attack(&mut self, a: Id, d: Id) -> &mut Self {
        self.act("attack", |x| x["type"] == "attack" && int(x.get("attacker")) == a && int(x.get("defender")) == d)
    }
    fn cost(&self, card: &str) -> i64 {
        self.g.cost(self.hand_id(card))
    }
}

// --- 9.1.0.20970 ----------------------------------------------------------------------------------------------------

#[test]
fn innervate_gives_one_crystal_from_20970() {
    for (v, mana) in [("20457", 7), ("20970", 6), ("22115", 6)] {
        let mut t = scene!(v, {"mana": 5, "max_mana": 5, "hand": ["VAN_EX1_169"]}, {});
        t.play("VAN_EX1_169", -1);
        assert_eq!(t.g.players[0].mana, mana, "version {v}");
    }
}

#[test]
fn murloc_warleader_gives_attack_only_from_20970() {
    for (v, raider) in [("20457", (4, 2)), ("20970", (4, 1)), ("21517", (4, 1))] {
        let t = scene!(v, {"board": ["VAN_EX1_507", RAIDER]}, {});
        assert_eq!(t.stats(t.on_board(0, RAIDER)), raider, "version {v}");
    }
}

#[test]
fn the_nerfed_costs() {
    let Some(vs) = versions() else { return };
    for (id, old, new) in [("ICC_054", 5, 6), ("VAN_CS2_106", 2, 3), ("VAN_EX1_246", 3, 4)] {
        assert_eq!(vs["20457"].card(id).cost, old, "{id}");
        for v in ["20970", "21517", "22115"] {
            assert_eq!(vs[v].card(id).cost, new, "{id} in {v}");
        }
    }
}

// --- 9.2.0.21517 ----------------------------------------------------------------------------------------------------

/// "After you summon a minion": the summoned minion's Battlecry comes first (Earthen Ring Farcaster heals before the 5
/// damage, so it heals nothing at full Health); before, the damage came on the summon and the Battlecry healed it.
#[test]
fn unlicensed_apothecary_hits_after_the_battlecry_from_21517() {
    for (v, hp) in [("20970", 28), ("21517", 25), ("22115", 25)] {
        let mut t = scene!(v, {"board": ["CFM_900"], "hand": ["VAN_CS2_117"]}, {});
        let me = t.hero(0);
        t.play("VAN_CS2_117", me);
        assert_eq!(t.hp(0), hp, "version {v}");
    }
}

/// A countered spell is cast for "after you cast a spell" (Wild Pyromancer) from 9.2.
#[test]
fn a_countered_spell_sets_off_wild_pyromancer_from_21517() {
    for (v, fired) in [("20970", false), ("21517", true), ("22115", true)] {
        let mut t = scene!(v, {"board": [PYROMANCER], "hand": ["VAN_CS2_025"]}, {"board": [YETI], "secrets": ["VAN_EX1_287"]});
        t.play("VAN_CS2_025", -1);
        assert!(t.g.players[1].secrets.is_empty(), "Counterspell went off in {v}");
        let yeti = t.on_board(1, YETI);
        assert_eq!(t.stats(yeti), if fired { (4, 4) } else { (4, 5) }, "version {v}");
    }
}

/// "Wild Pyromancer no longer triggers when summoned by effects such as Mindgames" (9.2).
#[test]
fn a_pyromancer_from_mindgames_does_not_hear_it_from_21517() {
    for (v, health) in [("20970", 1), ("21517", 2), ("22115", 2)] {
        let mut t = scene!(v, {"hero": "HERO_09", "hand": ["VAN_EX1_345"]}, {"deck": [PYROMANCER, PYROMANCER, PYROMANCER]});
        t.play("VAN_EX1_345", -1);
        let pyro = t.on_board(0, PYROMANCER);
        assert_eq!(t.stats(pyro), (3, health), "version {v}");
    }
}

/// Everyfin is Awesome's own discount comes after Naga Sea Witch's (5) from 9.2 (Dragon's Breath, Solemn Vigil and
/// Obsidian Shard too): 7 - 3 Murlocs, then (5) before; (5), then - 3 after.
#[test]
fn everyfin_is_awesome_discount_comes_last_from_21517() {
    for (v, cost) in [("20970", 5), ("21517", 2), ("22115", 2)] {
        let t = scene!(v, {"board": [NAGA, RAIDER, RAIDER, RAIDER], "hand": ["LOE_113"]}, {});
        assert_eq!(t.cost("LOE_113"), cost, "version {v}");
    }
}

// --- 9.4.0.22115 ----------------------------------------------------------------------------------------------------

/// Crush's own discount (4 with a damaged friendly minion) comes after Naga Sea Witch's (5) from 9.4.
#[test]
fn crush_discount_comes_last_from_22115() {
    for (v, cost) in [("21517", 5), ("22115", 1)] {
        let t = scene!(v, {"board": [NAGA, {"card": YETI, "damage": 1}], "hand": ["GVG_052"]}, {});
        assert_eq!(t.cost("GVG_052"), cost, "version {v}");
    }
}

/// Marin the Fox (given before Kobolds & Catacombs came out): a 0/8 Master Chest for the opponent; broken, it gives
/// Marin's player one of the four treasures.
#[test]
fn marin_the_fox_from_22115() {
    let Some(vs) = versions() else { return };
    assert!(!vs["21517"].cards.contains_key("LOOT_357"));
    let mut t = scene!("22115", {"hand": ["LOOT_357"], "board": ["VAN_CS2_201"]}, {});
    t.play("LOOT_357", -1);
    let chest = t.on_board(1, "LOOT_357l");
    assert_eq!(t.stats(chest), (0, 8));
    let hand = t.g.players[0].hand.len();
    let hound = t.on_board(0, "VAN_CS2_201"); // Core Hound 9/5
    t.attack(hound, chest);
    assert!(!t.g.players[1].board.contains(&chest));
    let got = t.cards(&t.g.players[0].hand[hand..]);
    assert!(matches!(got.as_slice(), [c] if ["LOOT_998h", "LOOT_998j", "LOOT_998k", "LOOT_998l"].contains(&c.as_str())), "{got:?}");
    // the treasures play
    for treasure in ["LOOT_998h", "LOOT_998k", "LOOT_998l"] {
        let mut t = scene!("22115", {"hand": [treasure]}, {});
        t.play(treasure, -1);
    }
    let mut t = scene!("22115", {"hand": ["LOOT_998j"]}, {}); // Zarog's Crown: Discover a Legendary minion, two of it
    t.play("LOOT_998j", -1);
    let opts = t.g.pending_options();
    assert_eq!(opts.len(), 3);
    let card = t.g.e(opts[0]).card_id.to_string();
    t.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == opts[0]);
    assert_eq!(t.cards(&t.g.players[0].board), [card.clone(), card]);
}
