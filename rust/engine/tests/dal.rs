//! The engine features of Rise of Shadows (packs/dal), on The Boomsday Project pack (built by tools/pack.py) with a few
//! inline test cards: Twinspell (TWINSPELL: the `<id>ts` copy to the hand slot, before "whenever you cast a spell", even
//! countered, from casts by effects too), Commander Rhyssa (DOUBLE_TRAP), a Scheme's counter (pure Lua: a `hand`
//! turn_start hook, a tag and the `text` hook) and the 14.0 keyword rule (Poisonous applies as the damage is dealt).
//! Needs python3 (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{pack, scenario, Game};
use serde_json::{json, Map, Value};
use std::path::PathBuf;
use std::sync::OnceLock;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

const LUA: &str = r#"
local cards = {}
cards.T_TWIN = { spell = function(g, me) g.add_count(g.ctrl(me), "twin") end }
cards.T_TWINts = { spell = function(g, me) g.add_count(g.ctrl(me), "twin") end }
cards.T_RHYSSA = { aura = function(g, me) g.aura_add(g.hero(g.ctrl(me)), 0, 0, { DOUBLE_SECRET = 1 }) end }
cards.T_SCHEME = {
  hand = { turn_start = function(g, me, ev) if ev.player == g.ctrl(me) then g.add_tag(me, "SCHEME", 1) end end },
  text = function(g, me) return 1 + g.tag(me, "SCHEME") end,
  spell = function(g, me) g.gain_armor(g.ctrl(me), 1 + g.tag(me, "SCHEME")) end,
}
cards.T_SILENCER = { -- after it is damaged, silence every minion (a keyword lost between the damage and its effect)
  on = { damage = function(g, me, ev) if ev.target == me then for _, m in ipairs(g.all_minions()) do g.silence(m) end end end },
}
return cards
"#;

/// The Boomsday pack, its rules naming TWINSPELL and DOUBLE_TRAP, and the test cards; None without python3.
fn rs() -> Option<&'static Ruleset> {
    static R: OnceLock<Option<&'static Ruleset>> = OnceLock::new();
    *R.get_or_init(|| {
        let out = std::env::temp_dir().join(format!("dal-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/boom", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let mut files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        let mut rules: Value = serde_json::from_slice(&files["rules.json"]).unwrap();
        rules["mechanics"]["TWINSPELL"] = json!({"engine": "TWINSPELL"});
        rules["mechanics"]["DOUBLE_SECRET"] = json!({"engine": "DOUBLE_TRAP"});
        files.insert("rules.json".into(), serde_json::to_vec(&rules).unwrap());
        let mut cards: Vec<Value> = serde_json::from_slice(&files["cards.json"]).unwrap();
        let card = |id: &str, kind: &str, cost: i64, extra: Value| {
            let mut c = json!({"id": id, "type": kind, "class": "NEUTRAL", "rarity": "COMMON", "set": "BOOMSDAY",
                "collectible": false, "cost": cost, "script": format!("scripts/dal_test.lua#{id}")});
            c.as_object_mut().unwrap().extend(extra.as_object().unwrap().clone());
            c
        };
        cards.push(card("T_TWIN", "SPELL", 3, json!({"keywords": ["TWINSPELL"]})));
        cards.push(card("T_TWINts", "SPELL", 3, json!({})));
        cards.push(card("T_RHYSSA", "MINION", 3, json!({"attack": 4, "health": 3})));
        cards.push(card("T_SCHEME", "SPELL", 4, json!({})));
        cards.push(card("T_SILENCER", "MINION", 1, json!({"attack": 1, "health": 9})));
        files.insert("cards.json".into(), serde_json::to_vec(&cards).unwrap());
        files.insert("scripts/dal_test.lua".into(), LUA.as_bytes().to_vec());
        Some(ruleset::load(&files).expect("the test pack loads"))
    })
}

/// The Rise of Shadows pack itself (packs/dal), built once; None without python3.
fn dal() -> Option<&'static Ruleset> {
    static R: OnceLock<Option<&'static Ruleset>> = OnceLock::new();
    *R.get_or_init(|| {
        let out = std::env::temp_dir().join(format!("dal-pack-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/dal", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(ruleset::load(&files).expect("the built pack loads"))
    })
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const AUCTIONEER: &str = "VAN_EX1_095";
const SNIPE: &str = "VAN_EX1_609";
const COUNTERSPELL: &str = "VAN_EX1_287";
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
    fn hand(&self, p: usize) -> Vec<String> {
        self.g.players[p].hand.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
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
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target
                && (int(a.get("pos")) == -1 || int(a.get("pos")) == last)
        })
    }
    fn end_turn(&mut self) -> &mut Self {
        self.act("end turn", |a| a["type"] == "end_turn")
    }
    fn count(&self, p: usize, name: &str) -> i64 {
        classichs_engine::entity::vint(self.g.players[p].counts.get(name))
    }
}

#[test]
fn twinspell_copy_goes_to_the_slot_it_was_cast_from() {
    let mut t = scene!({"hand": [WISP, "T_TWIN", YETI]}, {});
    t.play("T_TWIN", NONE);
    assert_eq!(t.hand(0), [WISP, "T_TWINts", YETI]);
    assert_eq!(t.count(0, "twin"), 1);
    // the copy has no Twinspell: cast, it gives nothing
    t.play("T_TWINts", NONE);
    assert_eq!(t.hand(0), [WISP, YETI]);
    assert_eq!(t.count(0, "twin"), 2);
}

#[test]
fn twinspell_copy_comes_before_whenever_you_cast_a_spell() {
    // a full hand: the copy takes the slot, Gadgetzan Auctioneer's draw then burns
    let hand = [WISP, WISP, WISP, WISP, "T_TWIN", WISP, WISP, WISP, WISP, WISP];
    let mut t = scene!({"hand": hand, "board": [AUCTIONEER]}, {});
    t.play("T_TWIN", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 10);
    assert_eq!(h[4], "T_TWINts");
}

#[test]
fn twinspell_copy_comes_even_when_countered() {
    let mut t = scene!({"hand": ["T_TWIN"]}, {"secrets": [COUNTERSPELL]});
    t.play("T_TWIN", NONE);
    assert_eq!(t.hand(0), ["T_TWINts"]);
    assert_eq!(t.count(0, "twin"), 0, "countered");
}

#[test]
fn twinspell_cast_by_an_effect_gives_the_copy_at_the_right_end() {
    let mut t = scene!({"hand": [WISP]}, {});
    let me = t.g.players[0].hero;
    t.g.cast_random(me, "T_TWIN");
    assert_eq!(t.hand(0), [WISP, "T_TWINts"]);
}

#[test]
fn double_trap_runs_a_secret_twice() {
    // Snipe deals 4 to the Yeti (4/5): it lives; with a DOUBLE_TRAP aura on its champion (Rhyssa), 8: it dies
    let mut t = scene!({"hand": [YETI]}, {"secrets": [SNIPE]});
    t.play(YETI, NONE);
    assert_eq!(t.g.players[0].board.len(), 1);
    let mut t = scene!({"hand": [YETI]}, {"secrets": [SNIPE], "board": ["T_RHYSSA"]});
    t.play(YETI, NONE);
    assert_eq!(t.g.players[0].board.len(), 0);
}

#[test]
fn a_scheme_counter_grows_in_the_hand_on_its_owners_turns() {
    let mut t = scene!({"hand": ["T_SCHEME"]}, {});
    let s = t.g.players[0].hand[0];
    t.end_turn().end_turn(); // p0's next turn: +1
    assert_eq!(t.g.e(s).tag("SCHEME"), 1);
    t.end_turn().end_turn();
    assert_eq!(t.g.e(s).tag("SCHEME"), 2);
    let st = classichs_engine::api::snapshot(&t.g, 0);
    assert_eq!(st["entities"][s.to_string()]["text_args"], json!(["3"]), "the text's {{0}}");
    t.play("T_SCHEME", NONE);
    assert_eq!(t.g.e(t.g.players[0].hero).tag("ARMOR"), 3);
}

#[test]
fn poisonous_applies_when_the_source_loses_it_right_after_the_damage() {
    // the 14.0 rule: a Poisonous minion hits T_SILENCER, whose damage trigger silences everyone; the poison still kills
    let mut t = scene!({"board": ["VAN_EX1_170"]}, {"board": ["T_SILENCER"]}); // Emperor Cobra 2/3 Poisonous
    let (a, d) = (t.g.players[0].board[0], t.g.players[1].board[0]);
    t.act("attack", |x| x["type"] == "attack" && int(x.get("attacker")) == a && int(x.get("defender")) == d);
    assert!(t.g.players[1].board.is_empty(), "the poisoned minion died");
}

// --- the card tests (data/card_tests/dal.json, as game/card_tests.gd plays them) ------------------------------------------

fn ref_id(g: &Game, r: Option<&Value>) -> Id {
    let Some(r) = r.and_then(Value::as_object) else { return NONE };
    let p = &g.players[int(r.get("side")) as usize];
    let i = int(r.get("index")) as usize;
    match r.get("zone").and_then(Value::as_str).unwrap_or("") {
        "hand" => p.hand.get(i).copied().unwrap_or(NONE),
        "board" => p.board.get(i).copied().unwrap_or(NONE),
        "secret" => p.secrets.get(i).copied().unwrap_or(NONE),
        "hero" => p.hero,
        "weapon" => p.weapon.unwrap_or(NONE),
        "power" => p.hero_power,
        _ => NONE,
    }
}

#[test]
fn card_tests_play() {
    let Some(rs) = dal() else { return };
    let tests: Map<String, Value> =
        serde_json::from_str(&std::fs::read_to_string(repo().join("data/card_tests/dal.json")).unwrap()).unwrap();
    let mut bad = vec![];
    for (id, list) in &tests {
        for t in list.as_array().unwrap() {
            if let Some(s) = t.get("script").and_then(Value::as_str) {
                if rs.card(id).script != s {
                    bad.push(format!("{id}: script {s} is not the pack's {}", rs.card(id).script));
                    continue;
                }
            }
            let title = t["title"].as_str().unwrap();
            let mut g = match scenario::build_in(rs, &t["scene"]) {
                Ok(g) => g,
                Err(e) => {
                    bad.push(format!("{title}: scene: {e}"));
                    continue;
                }
            };
            for (i, s) in t["steps"].as_array().unwrap().iter().enumerate() {
                let want: Vec<(&str, Value)> = match s["do"].as_str().unwrap() {
                    "play" => {
                        let mut w = vec![("type", json!("play")), ("entity", json!(ref_id(&g, s.get("card")))),
                            ("target", json!(ref_id(&g, s.get("target")))), ("choice", json!(s.get("choice").map_or(-1, |c| int(Some(c)))))];
                        if let Some(p) = s.get("pos") {
                            w.push(("pos", p.clone()));
                        }
                        w
                    }
                    "attack" => vec![("type", json!("attack")), ("attacker", json!(ref_id(&g, s.get("attacker")))),
                        ("defender", json!(ref_id(&g, s.get("defender"))))],
                    "hero_power" => vec![("type", json!("hero_power")), ("target", json!(ref_id(&g, s.get("target"))))],
                    "end_turn" => vec![("type", json!("end_turn"))],
                    "choose" => {
                        let opts = g.pending_options();
                        let n = int(s.get("option"));
                        let o = if opts.contains(&n) { n } else { opts.get(n as usize).copied().unwrap_or(NONE) };
                        vec![("type", json!("choose")), ("option", json!(o))]
                    }
                    x => panic!("{x}"),
                };
                let a = g.legal_actions().into_iter().find(|a| {
                    want.iter().all(|(k, v)| {
                        if *k == "pos" && int(a.get("pos")) < 0 {
                            return true;
                        }
                        a.get(*k).cloned().unwrap_or(if ["target", "choice"].contains(k) { json!(-1) } else { Value::Null }) == *v
                    })
                });
                let Some(a) = a else {
                    bad.push(format!("{title}: step {i}: not legal: {want:?}"));
                    break;
                };
                assert!(g.apply(&Value::Object(a)).ok);
                if let Some(e) = g.script_error.get() {
                    bad.push(format!("{title}: step {i}: {e}"));
                    break;
                }
            }
        }
    }
    assert!(bad.is_empty(), "{} problems:\n{}", bad.len(), bad.join("\n"));
}
