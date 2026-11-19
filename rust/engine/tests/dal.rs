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
cards.T_INFO = { -- counts "card:kind" for the target kind g.info gives (Fireball, Arcane Intellect, Wrath, Hex)
  spell = function(g, me)
    for _, c in ipairs({ "VAN_CS2_029", "VAN_CS2_023", "VAN_EX1_154", "VAN_EX1_246" }) do
      g.add_count(g.ctrl(me), c .. ":" .. (g.info(c).target or "none"))
    end
  end,
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
        cards.push(card("T_INFO", "SPELL", 0, json!({})));
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

// --- the pack's player hooks (rules.json `player_hooks`: ["player:boom", "player:dal"]) on the real pack ----------------

fn dal_game(p0: Value, p1: Value) -> Option<T> {
    let rs = dal()?;
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

macro_rules! dal_scene {
    ($p0:tt, $p1:tt) => {
        match dal_game(json!($p0), json!($p1)) {
            Some(t) => t,
            None => {
                eprintln!("no python3: skipped");
                return;
            }
        }
    };
}

const ARCANE_INTELLECT: &str = "VAN_CS2_023";
const FIREBALL: &str = "VAN_CS2_029";

#[test]
fn a_list_of_player_hook_sets_runs_each() {
    let Some(rs) = dal() else { return };
    assert_eq!(rs.player_hooks, ["player:boom", "player:dal"]);
}

#[test]
fn vargoth_recasts_a_spell_cast_before_he_came() {
    let mut t = dal_scene!({"hand": [ARCANE_INTELLECT, "DAL_558"]}, {});
    t.play(ARCANE_INTELLECT, NONE); // draws 2
    t.play("DAL_558", NONE);
    assert_eq!(t.g.players[0].hand.len(), 2);
    t.end_turn(); // Vargoth casts Arcane Intellect again: 2 more
    assert_eq!(t.g.players[0].hand.len(), 4);
}

#[test]
fn kalecgos_keeps_the_free_spell_when_the_first_is_countered() {
    // before patch 14.2 (2019-05-14) a countered first spell left the discount for the next one
    let mut t = dal_scene!({"hand": [FIREBALL, FIREBALL], "board": ["DAL_609"]}, {"secrets": [COUNTERSPELL]});
    let foe = t.g.players[1].hero;
    t.play(FIREBALL, foe);
    assert_eq!(t.g.players[0].mana, 10, "the first spell was free");
    t.play(FIREBALL, foe);
    assert_eq!(t.g.players[0].mana, 10, "the countered one left the discount");
    assert_eq!(t.g.e(foe).damage, 6);
}

#[test]
fn crystal_stag_counts_the_health_restored_this_game() {
    // Holy Light restores 6 to the damaged champion: the count RESTORED is 6 and the Stag summons its copy
    let mut t = dal_scene!({"hand": ["VAN_CS2_089", "DAL_799"], "damage": 10}, {});
    let me = t.g.players[0].hero;
    t.play("VAN_CS2_089", me);
    assert_eq!(t.count(0, "RESTORED"), 6);
    t.play("DAL_799", NONE);
    assert_eq!(t.g.players[0].board.len(), 2);
}

#[test]
fn an_unidentified_contract_in_the_opening_hand_is_identified_when_the_game_starts() {
    let Some(rs) = dal() else { return };
    let contracts: Vec<String> = vec!["DAL_366".to_string(); 30];
    let plain: Vec<String> = vec![YETI.to_string(); 30];
    let mut g = Game::new_in(rs, "HERO_03", &contracts, "HERO_01", &plain, 3, 0, true);
    for p in 0..2 {
        let a = g.legal_actions().into_iter().find(|a| a["type"] == "mulligan" && int(a.get("player")) == p as i64
            && a.get("replace").and_then(Value::as_array).is_some_and(|r| r.is_empty())).expect("keep all");
        assert!(g.apply(&Value::Object(a)).ok);
    }
    assert_eq!(g.script_error.get(), None);
    let hand: Vec<&str> = g.players[0].hand.iter().map(|&e| g.e(e).card_id.as_ref()).collect();
    assert!(!hand.is_empty() && hand.iter().all(|c| c.starts_with("DAL_366t")), "{hand:?}");
}

// --- Swampqueen Hagatha and her Drustvar Horror (g.info(card).target, target.like); Khadgar (DOUBLE_SUMMON) ---------

#[test]
fn info_gives_the_target_kind_a_card_needs() {
    let mut t = scene!({"hand": ["T_INFO"]}, {});
    t.play("T_INFO", NONE);
    for k in ["VAN_CS2_029:any", "VAN_CS2_023:none", "VAN_EX1_154:minion", "VAN_EX1_246:minion"] {
        assert_eq!(t.count(0, k), 1, "{k}");
    }
}

const HAGATHA: &str = "DAL_431";
const HORROR: &str = "DAL_431t";
const BOLT: &str = "VAN_EX1_238"; // Lightning Bolt: 3 damage, Overload (1)
const BLOODLUST: &str = "VAN_CS2_046"; // your minions +3 Attack this turn
const HEX: &str = "VAN_EX1_246";
const KHADGAR: &str = "DAL_575";

impl T {
    /// The Drustvar Horror in p0's hand, taught spells a and b (set-aside cards, as Hagatha's picks are).
    fn teach(&mut self, a: &str, b: &str) -> Id {
        let h = *self.g.players[0].hand.iter().find(|&&e| self.g.e(e).card_id == HORROR).unwrap();
        for (k, c) in [("HORROR_A", a), ("HORROR_B", b)] {
            let s = self.g.new_entity(c, 0);
            self.g.em(s).zone = "SETASIDE";
            self.g.em(h).set_tag(k, s);
        }
        h
    }
    /// The targets e may be played on.
    fn play_targets(&self, e: Id) -> Vec<Id> {
        self.g.legal_actions().iter().filter(|a| a["type"] == "play" && int(a.get("entity")) == e).map(|a| int(a.get("target"))).collect()
    }
    fn casts(&self) -> Vec<String> {
        self.g.history.iter().flat_map(|h| h.events()).filter(|e| e["type"] == "cast").map(|e| e["card"].as_str().unwrap().into()).collect()
    }
    fn choose(&mut self, o: Id) -> &mut Self {
        self.act("choose", |a| a["type"] == "choose" && int(a.get("option")) == o)
    }
}

#[test]
fn drustvar_horror_casts_both_spells_in_order_the_targeted_one_on_its_target() {
    for (a, b) in [(BOLT, BLOODLUST), (BLOODLUST, BOLT)] {
        let mut t = dal_scene!({"hand": [HORROR]}, {"board": [YETI]});
        let h = t.teach(a, b);
        let (yeti, foe) = (t.g.players[1].board[0], t.g.players[1].hero);
        let ts = t.play_targets(h);
        assert!(ts.contains(&yeti) && ts.contains(&foe) && !ts.contains(&NONE), "Lightning Bolt's targets: {ts:?}");
        let text = classichs_engine::api::snapshot(&t.g, 0)["entities"][h.to_string()]["text_args"].clone();
        assert_eq!(text, json!([format!("name:{a}"), format!("name:{b}")]));
        t.play(HORROR, yeti);
        assert_eq!(t.casts(), [a, b]);
        assert_eq!(t.g.e(yeti).damage, 3);
        assert_eq!(t.g.e(h).atk(), 8, "Bloodlust on the Horror");
        assert_eq!(t.g.players[0].mana, 5, "the spells are free");
        assert_eq!(t.g.players[0].mana_lock_owed, 1, "Lightning Bolt's Overload");
    }
}

#[test]
fn drustvar_horror_without_a_valid_target_still_casts_the_other_spell() {
    // Hex has no minion to hit but the Horror itself: it is played without a target, Bloodlust is still cast
    let mut t = dal_scene!({"hand": [HORROR]}, {});
    let h = t.teach(HEX, BLOODLUST);
    assert_eq!(t.play_targets(h), [NONE]);
    t.play(HORROR, NONE);
    assert_eq!(t.casts(), [BLOODLUST]);
    assert_eq!(t.g.e(h).atk(), 8);
}

#[test]
fn hagatha_teaches_two_picks_the_second_untargeted_after_a_targeted_first() {
    let mut t = dal_scene!({"hand": [HAGATHA]}, {});
    let rs = t.g.rs;
    let targeted = |g: &Game, e: Id| rs.card(&g.e(e).card_id).hooks.target.is_some();
    t.play(HAGATHA, NONE);
    let first = t.g.pending_options();
    assert_eq!(first.len(), 3);
    assert!(first.iter().all(|&o| t.g.e(o).kind() == "SPELL" && t.g.e(o).card.card_class == "SHAMAN"));
    let a = *first.iter().find(|&&o| targeted(&t.g, o)).expect("a targeted spell offered (seed 7)");
    t.choose(a);
    let second = t.g.pending_options();
    assert_eq!(second.len(), 3);
    assert!(second.iter().all(|&o| !targeted(&t.g, o)), "only untargeted spells after a targeted one");
    t.choose(second[0]);
    let h = t.g.players[0].hand[0];
    assert_eq!(t.g.e(h).card_id, HORROR);
    assert_eq!((t.g.e(h).tag("HORROR_A"), t.g.e(h).tag("HORROR_B")), (a, second[0]));
}

#[test]
fn hagatha_with_brann_gives_two_horrors_each_with_its_own_picks() {
    let mut t = dal_scene!({"hand": [HAGATHA], "board": ["LOE_077"]}, {});
    t.play(HAGATHA, NONE);
    let mut picked = vec![];
    while let Some(&o) = t.g.pending_options().first() {
        picked.push(o);
        t.choose(o);
    }
    assert_eq!(picked.len(), 4);
    // a second offer's cards carry the first pick they follow (HORROR_FIRST): each Horror has a first pick and its own second
    let seconds: Vec<(i64, i64)> = picked.iter().map(|&o| (t.g.e(o).tag("HORROR_FIRST"), o)).filter(|x| x.0 != 0).collect();
    let pairs: Vec<(i64, i64)> = t.g.players[0].hand.iter().map(|&h| (t.g.e(h).tag("HORROR_A"), t.g.e(h).tag("HORROR_B"))).collect();
    assert_eq!(pairs, seconds);
    assert!(pairs[0].0 != pairs[1].0 && pairs.iter().all(|(a, _)| picked.contains(a)));
}

#[test]
fn khadgar_doubles_what_cards_summon_not_a_minion_played() {
    // Murloc Tidehunter is played (one) and its Battlecry's Murloc Scout comes twice; two Khadgars: four times
    let mut t = dal_scene!({"hand": ["VAN_EX1_506"], "board": [KHADGAR]}, {});
    t.play("VAN_EX1_506", NONE);
    let cards = |t: &T| t.g.players[0].board.iter().map(|&m| t.g.e(m).card_id.to_string()).collect::<Vec<_>>();
    assert_eq!(cards(&t), [KHADGAR, "VAN_EX1_506", "VAN_EX1_506a", "VAN_EX1_506a"]);
    let mut t = dal_scene!({"hand": ["VAN_EX1_506"], "board": [KHADGAR, KHADGAR]}, {});
    t.play("VAN_EX1_506", NONE);
    assert_eq!(cards(&t).iter().filter(|c| *c == "VAN_EX1_506a").count(), 4);
}

#[test]
fn khadgar_doubles_an_opponents_card_summoning_on_his_side_not_the_hero_power() {
    // Dirty Rat (the opponent's) pulls a Yeti from Khadgar's player's hand: a copy comes too
    let mut t = dal_scene!({"board": [KHADGAR], "hand": [YETI]}, {"hand": ["CFM_790"]});
    t.g.current = 1;
    t.play("CFM_790", NONE);
    assert_eq!(t.g.players[0].board.len(), 3);
    // Reinforce (a champion's power, not a card) summons one
    let mut t = dal_scene!({"hero": "HERO_04", "board": [KHADGAR]}, {});
    t.act("hero power", |a| a["type"] == "hero_power");
    assert_eq!(t.g.players[0].board.len(), 2);
}
