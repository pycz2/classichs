//! Builds a Game in PLAY phase from a position description, and back
//! (engine/scenario.gd). Used by the debug table, card tests and bug reports.

use crate::entity::{int, Entity, Id};
use crate::ruleset::{self, Names, Ruleset};
use crate::state::Game;
use serde_json::{json, Map, Value};

const NUMBER_FIELDS: [&str; 10] = ["damage", "armor", "hero_attacks", "mana", "max_mana", "overload_owed",
    "overload_locked", "fatigue", "cards_played", "minions_played"];
const SPEC_LISTS: [&str; 3] = ["tags", "eot_tags", "enchantments"];

/// A position of the built-in Classic ruleset.
pub fn build(sc: &Value) -> Result<Game, String> {
    build_in(ruleset::classic(), sc)
}

pub fn build_in(rs: &'static Ruleset, sc: &Value) -> Result<Game, String> {
    validate_in(rs, sc)?;
    let ps = sc["players"].as_array().unwrap();
    let hero = |i: usize| ps[i]["hero"].as_str().unwrap();
    let get = |k: &str, def: i64| sc.get(k).map_or(def, |v| int(Some(v)));
    let mut g = Game::new_in(rs, hero(0), &[], hero(1), &[], get("seed", 1), get("current", 0), false);
    g.phase = "PLAY";
    g.turn = get("turn", 1);
    for (i, d) in ps.iter().enumerate() {
        fill_player(&mut g, i, d);
    }
    g.queue.clear();
    g.event_log.clear();
    g.update_auras();
    Ok(g)
}

fn num(d: &Value, k: &str) -> i64 {
    int(d.get(k))
}

fn fill_player(g: &mut Game, i: usize, d: &Value) {
    g.players[i].mulliganed = true;
    if let Some(hp) = d.get("hero_power").and_then(Value::as_str) {
        if hp != g.e(g.players[i].hero_power).card_id {
            let old = g.players[i].hero_power;
            g.em(old).zone = "SETASIDE";
            let n = g.new_entity(hp, i);
            g.players[i].hero_power = n;
            g.enter_play(n);
        }
    }
    let hero = g.players[i].hero;
    let n = g.n();
    g.em(hero).damage = num(d, "damage");
    g.em(hero).set_tag(n.armor, json!(num(d, "armor")));
    g.em(hero).set_tag(n.attacks, json!(num(d, "hero_attacks")));
    let p = &mut g.players[i];
    p.mana = num(d, "mana");
    p.max_mana = num(d, "max_mana");
    p.overload_owed = num(d, "overload_owed");
    p.overload_locked = num(d, "overload_locked");
    p.fatigue = num(d, "fatigue");
    p.cards_played_this_turn = num(d, "cards_played");
    p.minions_played_this_turn = num(d, "minions_played");
    p.cost_mods = list(d, "cost_mods").iter().filter_map(|m| ints(m).as_object().cloned()).collect();
    let hp = p.hero_power;
    if crate::entity::truthy(d.get("hero_power_used")) {
        g.em(hp).give_tag(n.used, false);
    }
    if crate::entity::truthy(d.get("hero_power_locked")) {
        g.em(hp).give_tag(n.locked, false); // tutorial: no hero power yet
    }
    for item in list(d, "deck") {
        let s = spec(item);
        let e = g.new_entity(card_of(&s), i);
        g.em(e).zone = "DECK";
        apply_spec(g.em(e), &s, n);
        g.players[i].deck.push(e);
    }
    for item in list(d, "hand") {
        let s = spec(item);
        let e = g.new_entity(card_of(&s), i);
        g.em(e).zone = "HAND";
        apply_spec(g.em(e), &s, n);
        g.players[i].hand.push(e);
    }
    for item in list(d, "board") {
        let s = spec(item);
        let e = g.new_entity(card_of(&s), i);
        g.place_on_board(e, -1);
        apply_spec(g.em(e), &s, n);
        if s.get("exhausted").is_some_and(|v| crate::entity::truthy(Some(v))) {
            g.em(e).give_tag(n.exhausted, false);
        }
    }
    if let Some(w) = d.get("weapon").filter(|w| !w.is_null()) {
        let s = spec(w);
        let e = g.new_entity(card_of(&s), i);
        g.players[i].weapon = Some(e);
        g.enter_play(e);
        if let Some(dur) = s.get("durability") {
            g.em(e).set_tag(n.durability, json!(int(Some(dur))));
        }
        apply_spec(g.em(e), &s, n);
    }
    if let Some(hs) = d.get("hero_state") {
        apply_spec(g.em(hero), hs, n);
    }
    for item in list(d, "secrets") {
        let e = g.new_entity(card_of(&spec(item)), i);
        g.enter_play(e);
        g.em(e).zone = n.trap;
        g.players[i].secrets.push(e);
    }
}

fn list<'a>(d: &'a Value, k: &str) -> &'a [Value] {
    d.get(k).and_then(Value::as_array).map_or(&[], |v| v.as_slice())
}

fn spec(v: &Value) -> Value {
    if v.is_string() { json!({"card": v}) } else { v.clone() }
}

fn card_of(s: &Value) -> &str {
    s["card"].as_str().unwrap()
}

fn apply_spec(e: &mut Entity, s: &Value, n: &Names) {
    if s.get("silenced").is_some_and(|v| crate::entity::truthy(Some(v))) {
        e.silence(&n.silenced);
    }
    if let Some(Value::Object(t)) = s.get("tags_exact").map(ints) {
        e.tags = t;
    }
    for t in list(s, "tags").iter().filter_map(Value::as_str) {
        e.give_tag(t, false);
    }
    for t in list(s, "eot_tags").iter().filter_map(Value::as_str) {
        e.give_tag(t, true);
    }
    for ench in list(s, "enchantments") {
        if let Value::Object(m) = ints(ench) {
            e.enchantments.push(m);
        }
    }
    e.damage = int(s.get("damage"));
    if let Some(a) = s.get("attacks") {
        e.set_tag(n.attacks, json!(int(Some(a))));
    }
}

/// JSON gives floats; the engine uses ints only.
pub(crate) fn ints(v: &Value) -> Value {
    match v {
        Value::Number(_) => json!(int(Some(v))),
        Value::Array(a) => Value::Array(a.iter().map(ints).collect()),
        Value::Object(m) => Value::Object(m.iter().map(|(k, x)| (k.clone(), ints(x))).collect()),
        _ => v.clone(),
    }
}

/// GDScript str() of a JSON value, for error messages.
fn show(v: Option<&Value>) -> String {
    match v {
        None | Some(Value::Null) => "<null>".into(),
        Some(Value::String(s)) => s.clone(),
        Some(x) => x.to_string(),
    }
}

/// Type errors in an entity spec (board item, weapon, hero_state, hand/deck item).
fn check_spec(at: &str, item: &Value) -> Result<(), String> {
    let Some(m) = item.as_object() else { return Ok(()) };
    for k in SPEC_LISTS {
        if m.get(k).is_some_and(|v| !v.is_array()) {
            return Err(format!("{at}.{k}: must be a list"));
        }
    }
    if list(item, "enchantments").iter().any(|e| !e.is_object()) {
        return Err(format!("{at}.enchantments: items must be objects"));
    }
    if m.get("tags_exact").is_some_and(|v| !v.is_object()) {
        return Err(format!("{at}.tags_exact: must be an object"));
    }
    for k in ["damage", "durability", "attacks"] {
        if m.get(k).is_some_and(|v| !v.is_number()) {
            return Err(format!("{at}.{k}: must be a number"));
        }
    }
    Ok(())
}

fn check_card(rs: &Ruleset, at: &str, id: Option<&Value>, kind: &str) -> Result<(), String> {
    let Some(s) = id.and_then(Value::as_str).filter(|s| rs.has(s)) else {
        return Err(format!("{at}: unknown card {}", show(id)));
    };
    if !kind.is_empty() && rs.card(s).kind != kind {
        return Err(format!("{at}: {s} is not a {}", kind.to_lowercase().replace('_', " ")));
    }
    Ok(())
}

/// Why a position can't be built for the built-in Classic ruleset.
pub fn validate(sc: &Value) -> Result<(), String> {
    validate_in(ruleset::classic(), sc)
}

pub fn validate_in(rs: &Ruleset, sc: &Value) -> Result<(), String> {
    let ps = match sc.get("players").and_then(Value::as_array) {
        Some(ps) if ps.len() == 2 => ps,
        _ => return Err("players: need exactly 2".into()),
    };
    for k in ["seed", "current", "turn"] {
        if sc.get(k).is_some_and(|v| !v.is_number()) {
            return Err(format!("{k}: must be a number"));
        }
    }
    if !matches!(sc.get("current").map_or(0, |v| int(Some(v))), 0 | 1) {
        return Err("current: must be 0 or 1".into());
    }
    for (i, d) in ps.iter().enumerate() {
        let at = format!("players[{i}]");
        if !d.is_object() || d.get("hero").is_none() {
            return Err(format!("{at}: hero is required"));
        }
        check_card(rs, &format!("{at}.hero"), d.get("hero"), "HERO")?;
        for k in NUMBER_FIELDS {
            if d.get(k).is_some_and(|v| !v.is_number()) {
                return Err(format!("{at}.{k}: must be a number"));
            }
        }
        if d.get("cost_mods").is_some_and(|v| !v.is_array()) {
            return Err(format!("{at}.cost_mods: must be a list"));
        }
        if let Some(hs) = d.get("hero_state") {
            if !hs.is_object() {
                return Err(format!("{at}.hero_state: must be an object"));
            }
            check_spec(&format!("{at}.hero_state"), hs)?;
        }
        let hero = d["hero"].as_str().unwrap();
        if d.get("hero_power").is_none() && rs.class_power(hero).is_none() {
            return Err(format!("{at}.hero_power: required for hero {hero}"));
        }
        if d.get("hero_power").is_some() {
            check_card(rs, &format!("{at}.hero_power"), d.get("hero_power"), "HERO_POWER")?;
        }
        for (zone, kind) in [("hand", ""), ("deck", ""), ("board", "MINION"), ("secrets", "SPELL")] {
            let items = match d.get(zone) {
                None => &[][..],
                Some(Value::Array(a)) => a.as_slice(),
                Some(_) => return Err(format!("{at}.{zone}: must be a list")),
            };
            for (j, item) in items.iter().enumerate() {
                let id = if item.is_string() { Some(item) } else { item.get("card") };
                let here = format!("{at}.{zone}[{j}]");
                check_card(rs, &here, id, kind)?;
                check_spec(&here, item)?;
            }
        }
        if list(d, "board").len() > rs.board {
            return Err(format!("{at}.board: more than {} minions", rs.board));
        }
        if list(d, "hand").len() > rs.hand {
            return Err(format!("{at}.hand: more than {} cards", rs.hand));
        }
        if let Some(w) = d.get("weapon").filter(|w| !w.is_null()) {
            if !(w.is_string() || w.is_object()) {
                return Err(format!("{at}.weapon: must be a card id or an object"));
            }
            let id = if w.is_string() { Some(w) } else { w.get("card") };
            check_card(rs, &format!("{at}.weapon"), id, "WEAPON")?;
            check_spec(&format!("{at}.weapon"), w)?;
        }
        if num(d, "max_mana") > rs.max_mana || num(d, "mana") < 0 {
            return Err(format!("{at}: mana out of range"));
        }
    }
    Ok(())
}

fn dump_entity(e: &Entity, n: &Names) -> Value {
    let skip = [n.to_destroy, n.died_pos];
    let tags: Map<String, Value> =
        e.tags.iter().filter(|(k, _)| !skip.contains(&k.as_str())).map(|(k, v)| (k.clone(), v.clone())).collect();
    let mut d = json!({"card": e.card_id, "damage": e.damage, "tags_exact": tags, "enchantments": e.enchantments,
        "silenced": e.silenced, "eot_tags": e.eot_tags});
    if e.is_weapon() {
        d["durability"] = json!(e.tag(n.durability));
    }
    d
}

/// The position as a scenario (Scenario.dump).
pub fn dump(g: &Game) -> Value {
    let n = g.n();
    let ps: Vec<Value> = g
        .players
        .iter()
        .map(|p| {
            let hero = g.e(p.hero);
            let hp = g.e(p.hero_power);
            let ids = |v: &[Id]| -> Vec<Value> { v.iter().map(|&id| json!(g.e(id).card_id)).collect() };
            json!({
                "hero": hero.card_id, "hero_power": hp.card_id,
                "damage": hero.damage, "armor": hero.tag(n.armor), "hero_attacks": hero.tag(n.attacks),
                "mana": p.mana, "max_mana": p.max_mana,
                "overload_owed": p.overload_owed, "overload_locked": p.overload_locked,
                "fatigue": p.fatigue, "cards_played": p.cards_played_this_turn,
                "hero_power_used": hp.has(n.used), "hero_power_locked": hp.has(n.locked),
                "cost_mods": p.cost_mods, "minions_played": p.minions_played_this_turn,
                "hero_state": dump_entity(hero, n),
                "hand": p.hand.iter().map(|&e| dump_entity(g.e(e), n)).collect::<Vec<_>>(),
                "deck": ids(&p.deck),
                "board": p.board.iter().map(|&e| dump_entity(g.e(e), n)).collect::<Vec<_>>(),
                "weapon": p.weapon.map_or(Value::Null, |w| dump_entity(g.e(w), n)),
                "secrets": ids(&p.secrets),
            })
        })
        .collect();
    json!({"seed": 1, "current": g.current, "turn": g.turn, "players": ps})
}
