//! The JSON API for every host (game server, Godot GDExtension, WASM): an
//! `Engine` holds many games by id; `call` takes one JSON request and returns
//! one JSON reply. Ops and fields: README.md.

use crate::arena_draft::ArenaDraft;
use crate::bot;
use crate::card_db;
use crate::deck::Deck;
use crate::entity::{int, Id};
use crate::json::stringify;
use crate::missions;
use crate::scenario;
use crate::state::{Ev, Game};
use serde_json::{json, Map, Value};
use std::collections::HashMap;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

struct Slot {
    game: Game,
    /// The tutorial mission this game plays (1-6), if any.
    mission: Option<usize>,
}

#[derive(Default)]
pub struct Engine {
    games: HashMap<String, Slot>,
}

fn err(msg: impl Into<String>) -> Value {
    json!({"ok": false, "error": msg.into()})
}

/// An int from a JSON number (whole or not), None otherwise.
fn number(v: Option<&Value>) -> Option<i64> {
    v.filter(|x| x.is_number()).map(|x| int(Some(x)))
}

impl Engine {
    pub fn new() -> Engine {
        Engine::default()
    }

    /// One JSON request in, one JSON reply out. A panic (an engine bug) gives
    /// {"ok": false, "error": "internal error"} and drops the game it hit, whose
    /// state may be half-changed (where panics unwind; WASM aborts).
    pub fn call(&mut self, req: &str) -> String {
        let reply = match serde_json::from_str::<Value>(req) {
            Ok(v) => match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| self.handle(&v))) {
                Ok(r) => r,
                Err(_) => {
                    if let Some(id) = v.get("game").and_then(Value::as_str) {
                        self.games.remove(id);
                    }
                    err("internal error")
                }
            },
            Err(e) => err(format!("bad json: {e}")),
        };
        stringify(&reply)
    }

    /// A game, for hosts that use the Rust types directly.
    pub fn game(&self, id: &str) -> Option<&Game> {
        self.games.get(id).map(|s| &s.game)
    }

    pub fn game_mut(&mut self, id: &str) -> Option<&mut Game> {
        self.games.get_mut(id).map(|s| &mut s.game)
    }

    /// Adds a game built by the host.
    pub fn insert(&mut self, id: &str, game: Game) {
        self.games.insert(id.to_string(), Slot { game, mission: None });
    }

    pub fn handle(&mut self, req: &Value) -> Value {
        if !req.is_object() {
            return err("not an object");
        }
        let id = match req.get("game") {
            Some(Value::String(s)) => s.clone(),
            Some(v) if !v.is_null() => v.to_string(),
            _ => String::new(),
        };
        let view = number(req.get("view")).unwrap_or(-1);
        let op = req.get("op").and_then(Value::as_str).unwrap_or("");
        match op {
            "ping" => json!({"ok": true, "version": VERSION, "engine": "classichs-engine", "data": card_db::data_hash()}),
            "data_hash" => json!({"ok": true, "hash": card_db::data_hash()}),
            "hooks" => {
                let all: Map<String, Value> =
                    crate::cards::all_ids().into_iter().map(|id| (id.to_string(), crate::cards::summary(id))).collect();
                json!({"ok": true, "hooks": all})
            }
            "validate" => match Deck::from_value(req.get("deck").unwrap_or(&Value::Null)) {
                None => err("not a deck"),
                Some(d) => {
                    let why = d.validate();
                    if why.is_empty() { json!({"ok": true}) } else { err(why) }
                }
            },
            "draft" => draft(req),
            "new" => self.new_game(&id, req, view),
            "drop" => {
                self.games.remove(&id);
                json!({"ok": true, "game": id})
            }
            "act" | "legal" | "snapshot" | "hash" | "bot" | "history" | "dump" | "end_turn_block" => {
                let Some(slot) = self.games.get_mut(&id) else {
                    return json!({"ok": false, "game": id, "error": "no such game"});
                };
                game_op(op, &id, slot, req, view)
            }
            _ => err("unknown op"),
        }
    }

    fn new_game(&mut self, id: &str, req: &Value, view: i64) -> Value {
        let fail = |e: &str| json!({"ok": false, "game": id, "error": e});
        if id.is_empty() {
            return fail("bad new request");
        }
        let mut mission = None;
        let game = if let Some(sc) = req.get("scenario") {
            match scenario::build(sc) {
                Ok(g) => g,
                Err(e) => return fail(&format!("scenario: {e}")),
            }
        } else if let Some(n) = number(req.get("mission")) {
            match missions::start(n as usize) {
                Ok(g) => {
                    mission = Some(n as usize);
                    g
                }
                Err(e) => return fail(&e),
            }
        } else {
            let Some(seed) = number(req.get("seed")) else { return fail("bad new request") };
            let first = number(req.get("first")).filter(|f| (0..=1).contains(f)).unwrap_or(-1);
            let check = req.get("check") != Some(&Value::Bool(false));
            let Some(decks) = req.get("decks").and_then(Value::as_array).filter(|d| d.len() == 2) else {
                return fail("bad new request");
            };
            let mut pair = vec![];
            for d in decks {
                match Deck::from_value(d) {
                    Some(deck) if !check || deck.validate().is_empty() => pair.push(deck),
                    _ => return fail("bad deck"),
                }
            }
            Game::new(&pair[0].hero, &pair[0].cards, &pair[1].hero, &pair[1].cards, seed, first, true)
        };
        let mut reply = state(id, &game);
        let start: Vec<Ev> = game.history[0]["events"]
            .as_array()
            .map(|a| a.iter().filter_map(|e| e.as_object().cloned()).collect())
            .unwrap_or_default();
        reply["events"] = events_for(&game, &start, view);
        self.games.insert(id.to_string(), Slot { game, mission });
        reply
    }
}

fn game_op(op: &str, id: &str, slot: &mut Slot, req: &Value, view: i64) -> Value {
    let g = &mut slot.game;
    let player = number(req.get("player")).unwrap_or(-1);
    match op {
        "act" => {
            let Some(action) = req.get("action").filter(|a| a.is_object()) else {
                return json!({"ok": false, "game": id, "error": "not an action"});
            };
            if g.game_over {
                // a move that crossed the end: nothing changes
                let mut r = state(id, g);
                r["events"] = json!([]);
                return r;
            }
            let res = g.apply(action);
            let mut r = state(id, g);
            r["ok"] = json!(res.ok);
            r["events"] = events_for(g, &res.events, view);
            if !res.ok {
                r["error"] = json!(res.error);
            }
            r
        }
        "legal" => {
            let actions: Vec<Value> = g
                .legal_actions()
                .into_iter()
                .filter(|a| player < 0 || int(a.get("player")) == player)
                .map(Value::Object)
                .collect();
            json!({"ok": true, "game": id, "actions": actions})
        }
        "snapshot" => json!({"ok": true, "game": id, "state": snapshot(g, view)}),
        "hash" => json!({"ok": true, "game": id, "hash": g.state_hash()}),
        "bot" => {
            if !(0..=1).contains(&player) {
                return json!({"ok": false, "game": id, "error": "bad player"});
            }
            let a = bot::choose(g, player as usize).map_or(Value::Null, Value::Object);
            json!({"ok": true, "game": id, "action": a})
        }
        "history" => {
            let from = number(req.get("from")).unwrap_or(0).max(0) as usize;
            let entries: Vec<Value> = g
                .history
                .iter()
                .skip(from)
                .map(|h| {
                    let mut h = h.clone();
                    let evs: Vec<Ev> =
                        h["events"].as_array().map(|a| a.iter().filter_map(|e| e.as_object().cloned()).collect()).unwrap_or_default();
                    h["events"] = events_for(g, &evs, view);
                    h
                })
                .collect();
            json!({"ok": true, "game": id, "history": entries, "start_decks": g.start_decks})
        }
        "dump" => json!({"ok": true, "game": id, "scenario": scenario::dump(g)}),
        _ => {
            // end_turn_block
            let block = match slot.mission.and_then(missions::get) {
                Some(m) if (0..=1).contains(&player) => missions::end_turn_block(m, g, player as usize),
                _ => "",
            };
            json!({"ok": true, "game": id, "block": block, "mission": slot.mission})
        }
    }
}

/// The referee's state reply.
fn state(id: &str, g: &Game) -> Value {
    json!({"ok": true, "game": id, "hash": g.state_hash(), "over": g.game_over, "winner": g.winner, "turn": g.turn,
        "current": g.current, "phase": g.phase})
}

/// The Arena draft from its seed and picks (stateless: the caller keeps them).
fn draft(req: &Value) -> Value {
    let Some(seed) = number(req.get("seed")) else { return err("no seed") };
    let mut d = ArenaDraft::new(seed);
    if let Some(h) = number(req.get("hero")).filter(|h| (0..3).contains(h)) {
        d.choose_hero(h as usize);
        if let Some(picks) = req.get("picks").and_then(Value::as_array) {
            for p in picks {
                match number(Some(p)) {
                    Some(i) if (0..=2).contains(&i) => d.pick(i as usize),
                    _ => return err("bad pick"),
                }
            }
        }
    }
    json!({"ok": true, "heroes": d.heroes, "hero": d.hero, "cards": d.cards, "offer": d.offer, "done": d.done()})
}

/// Whether viewer (0 or 1) may see which card entity id is.
fn visible(g: &Game, id: Id, viewer: i64) -> bool {
    let Some(e) = g.ent(id) else { return true };
    if viewer < 0 {
        return true;
    }
    let mine = e.controller as i64 == viewer;
    let chooser = g.pending.as_ref().is_some_and(|p| p.player as i64 == viewer && p.options.contains(&id));
    match e.zone {
        "DECK" => chooser,
        "HAND" | "SECRET" => mine,
        _ => true,
    }
}

/// Events as viewer may see them: the card of an entity still hidden from them is "".
pub fn events_for(g: &Game, events: &[Ev], viewer: i64) -> Value {
    Value::Array(
        events
            .iter()
            .map(|ev| {
                let mut ev = ev.clone();
                if let Some(e) = ev.get("entity").and_then(Value::as_i64) {
                    if ev.contains_key("card") && !visible(g, e, viewer) {
                        ev.insert("card".into(), json!(""));
                    }
                }
                Value::Object(ev)
            })
            .collect(),
    )
}

/// Everything a client needs to draw the table. view -1: the full state
/// (GDScript to_dict() plus computed stats); view 0/1: that player's view
/// (no RNG state, no deck contents, the opponent's hand and secrets hidden).
pub fn snapshot(g: &Game, view: i64) -> Value {
    let mut d = g.to_dict();
    let mut ents = Map::new();
    for e in &g.entities {
        if !visible(g, e.id, view) {
            if e.zone == "DECK" {
                continue;
            }
            ents.insert(e.id.to_string(), json!({"card": "", "ctrl": e.controller, "zone": e.zone, "order": e.play_order}));
            continue;
        }
        let mut s = e.snapshot();
        s["type"] = json!(e.kind());
        s["atk"] = json!(if e.is_hero() { g.hero_atk(e.id) } else { e.atk() });
        s["health"] = json!(e.health());
        s["max_health"] = json!(e.max_health());
        s["cost"] = json!(g.cost(e.id));
        s["aura"] = json!({"atk": e.aura.atk, "hp": e.aura.hp, "tags": e.aura.tags, "src": e.aura.src});
        ents.insert(e.id.to_string(), s);
    }
    d["entities"] = Value::Object(ents);
    for (i, p) in g.players.iter().enumerate() {
        let pd = &mut d["players"][i];
        pd["deck_count"] = json!(p.deck.len());
        pd["spell_damage"] = json!(p.board.iter().map(|&m| g.e(m).spellpower()).sum::<i64>());
        if view >= 0 {
            pd["deck"] = json!([]);
        }
    }
    if view >= 0 {
        d.as_object_mut().unwrap().remove("rng");
    } else {
        d["start_decks"] = json!(g.start_decks);
    }
    d["view"] = json!(view);
    d["history_len"] = json!(g.history.len());
    d
}
