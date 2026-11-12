//! Match state, event queue, death phase, auras and the primitives that card
//! hooks use (engine/game_state.gd). Turns, actions and legality: game.rs.

use crate::hooks::{Base, HookFn, HookSet, TSpec, TrapHook};
use crate::entity::{obj, vint, vtruthy, Entity, Id, Obj, Str, V, NONE};
use crate::json;
use crate::lua::LuaSlot;
use crate::player::Player;
use crate::rng::Rng;
use crate::ruleset::{Names, Ruleset};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::sync::{Arc, OnceLock};

/// An event as callers get it: a JSON object ({"type": ..., ...}). The game keeps them as `Obj`.
pub type Ev = Map<String, Value>;

#[derive(Clone, Copy)]
pub(crate) enum Trigger {
    On(HookFn),
    /// A `hand` hook: runs only while its card is still in the hand.
    Hand(HookFn),
    Trap(TrapHook),
    OnDeath(HookFn),
}

#[derive(Clone, Copy)]
pub(crate) struct QItem {
    f: Trigger,
    me: Id,
    /// Index into event_log (None: a deathrattle's empty event).
    ev: Option<usize>,
    needs_in_play: bool,
}

/// One entry of the match history: an action and its events.
#[derive(Clone, Debug)]
pub struct Hist {
    pub turn: i64,
    pub player: Value,
    pub action: Map<String, Value>,
    pub events: Vec<Obj>,
}

impl Hist {
    /// The events as callers get them.
    pub fn events(&self) -> Vec<Ev> {
        self.events.iter().map(Obj::to_map).collect()
    }

    /// {"turn", "player", "action", "events"}.
    pub fn to_value(&self) -> Value {
        let mut m = Map::new();
        m.insert("action".into(), Value::Object(self.action.clone()));
        m.insert("events".into(), Value::Array(self.events.iter().map(Obj::to_value).collect()));
        m.insert("player".into(), self.player.clone());
        m.insert("turn".into(), json!(self.turn));
        Value::Object(m)
    }
}

/// A choice the player must make (`g.request_choice`).
#[derive(Clone, Debug)]
pub struct Pending {
    pub player: usize,
    pub source: Id,
    pub options: Vec<Id>,
    /// The zone each option was offered from.
    pub zones: Vec<&'static str>,
}

pub struct Game {
    /// What is being played: rules, cards, mechanic names, hooks.
    pub rs: &'static Ruleset,
    pub rng: Rng,
    pub players: Vec<Player>,
    /// Entity id n is entities[n - 1]; entities are never removed. Shared with look-ahead
    /// copies until one changes (`em`).
    pub entities: Vec<Arc<Entity>>,
    pub turn: i64,
    pub current: usize,
    pub phase: &'static str,
    pub pending: Option<Pending>,
    /// Choices asked for while one was pending (two Discovers of a doubled Battlecry), in order.
    pub pending_next: Vec<Pending>,
    pub game_over: bool,
    pub winner: i64,
    pub event_log: Vec<Obj>,
    /// Full match history, never trimmed. Entry 0 is the start ({"type": "start"}) with the opening draws.
    pub history: Vec<Hist>,
    pub(crate) queue: VecDeque<QItem>,
    pub(crate) next_id: Id,
    pub(crate) next_order: i64,
    /// The card whose effect is running now (buffs and auras remember it; display only).
    pub source_card: &'static str,
    pub source_id: Id,
    /// The deck lists the match started with (the deck tracker shows them).
    pub start_decks: [Vec<String>; 2],
    /// The interpreter of the card scripts (crate::lua).
    pub(crate) lua: LuaSlot,
    /// Why a card script failed (the game then ended as a draw).
    pub script_error: OnceLock<String>,
    /// Calls of script actions that may change the game (all but `g.aura_add`).
    pub(crate) writes: u64,
}

impl Game {
    pub(crate) fn blank(rs: &'static Ruleset, seed: i64) -> Game {
        Game { rs, rng: Rng::new(seed as u64), players: vec![], entities: vec![], turn: 0, current: 0,
            phase: "MULLIGAN", pending: None, pending_next: vec![], game_over: false, winner: -1, event_log: vec![], history: vec![],
            queue: VecDeque::new(), next_id: 1, next_order: 1, source_card: "", source_id: NONE,
            start_decks: [vec![], vec![]], lua: LuaSlot::default(), script_error: OnceLock::new(), writes: 0 }
    }

    /// A game with no cards: the host that loads a pack's scripts.
    pub(crate) fn loader() -> Game {
        static EMPTY: OnceLock<&'static Ruleset> = OnceLock::new();
        let rs = EMPTY.get_or_init(|| {
            let mut f = crate::pack::Files::new();
            f.insert("manifest.json".into(), br#"{"format": 1}"#.to_vec());
            f.insert("rules.json".into(), b"{}".to_vec());
            f.insert("cards.json".into(), b"[]".to_vec());
            Box::leak(Box::new(Ruleset::from_files(&f, false).expect("the empty ruleset")))
        });
        Game::blank(rs, 0)
    }

    /// The pack's tag names.
    pub fn n(&self) -> &'static Names {
        &self.rs.names
    }

    pub(crate) fn setup_players(&mut self, hero0: &str, hero1: &str) {
        for (i, hero_id) in [hero0, hero1].into_iter().enumerate() {
            let mut p = Player::new(i);
            p.hero = self.new_entity(hero_id, i);
            self.enter_play(p.hero);
            let power = self.rs.class_power(hero_id).unwrap_or(&self.rs.default_power).to_string();
            p.hero_power = self.new_entity(&power, i);
            self.enter_play(p.hero_power);
            self.players.push(p);
        }
    }

    // --- entities -------------------------------------------------------------

    pub fn new_entity(&mut self, card_id: &str, controller: usize) -> Id {
        let id = self.next_id;
        self.entities.push(Arc::new(Entity::new(id, self.rs.card(card_id), controller)));
        self.next_id += 1;
        id
    }

    pub fn e(&self, id: Id) -> &Entity {
        &self.entities[(id - 1) as usize]
    }

    pub fn em(&mut self, id: Id) -> &mut Entity {
        Arc::make_mut(&mut self.entities[(id - 1) as usize])
    }

    /// The entity with this id, if it exists.
    pub fn ent(&self, id: Id) -> Option<&Entity> {
        if id >= 1 { self.entities.get((id - 1) as usize).map(|e| &**e) } else { None }
    }

    pub fn ctrl(&self, id: Id) -> usize {
        self.e(id).controller
    }

    pub(crate) fn enter_play(&mut self, id: Id) {
        let order = self.next_order;
        self.next_order += 1;
        let e = self.em(id);
        e.zone = "PLAY";
        e.play_order = order;
    }

    pub fn place_on_board(&mut self, id: Id, pos: i64) {
        let c = self.ctrl(id);
        let board = &mut self.players[c].board;
        let pos = if pos < 0 || pos as usize > board.len() { board.len() } else { pos as usize };
        board.insert(pos, id);
        self.enter_play(id);
    }

    pub fn opponent(&self, p: usize) -> usize {
        1 - p
    }

    /// Not DORMANT (a pack that names it: Sherazin's seed, Nether Portal): a dormant minion holds its place on the
    /// board but is no character for anything else (no target, no attack, no damage, in no list of minions).
    pub fn awake(&self, m: Id) -> bool {
        self.n().dormant.is_none_or(|t| !self.e(m).tags.contains_key(t))
    }

    /// p's minions that are awake (`awake`), left to right.
    fn board_awake(&self, p: usize) -> impl Iterator<Item = &Id> {
        self.players[p].board.iter().filter(|&&m| self.awake(m))
    }

    pub fn minions(&self, p: usize) -> Vec<Id> {
        self.board_awake(p).copied().collect()
    }

    pub fn all_minions(&self) -> Vec<Id> {
        let mut v: Vec<Id> = self.board_awake(0).chain(self.board_awake(1)).copied().collect();
        v = self.by_order(v);
        v
    }

    pub fn chars(&self, p: usize) -> Vec<Id> {
        let mut v = Vec::with_capacity(self.players[p].board.len() + 1);
        v.push(self.players[p].hero);
        v.extend(self.board_awake(p));
        v
    }

    pub fn all_chars(&self) -> Vec<Id> {
        let (a, b) = (&self.players[0], &self.players[1]);
        let mut v = Vec::with_capacity(a.board.len() + b.board.len() + 2);
        v.push(a.hero);
        v.extend(self.board_awake(0));
        v.push(b.hero);
        v.extend(self.board_awake(1));
        self.by_order(v)
    }

    pub fn hero(&self, p: usize) -> Id {
        self.players[p].hero
    }

    pub fn weapon(&self, p: usize) -> Option<Id> {
        self.players[p].weapon
    }

    /// Friendly minions of me, without me.
    pub fn others(&self, me: Id) -> Vec<Id> {
        self.board_awake(self.ctrl(me)).copied().filter(|&m| m != me).collect()
    }

    /// Summons for me's controller right of me (left-to-right board order).
    pub fn summon_right(&mut self, me: Id, card_id: &str) -> Id {
        let c = self.ctrl(me);
        let pos = match self.players[c].board.iter().position(|&m| m == me) {
            Some(i) => i as i64 + 1,
            None => -1,
        };
        self.summon(c, card_id, pos)
    }

    pub fn board_pos(&self, m: Id) -> Option<usize> {
        self.players[self.ctrl(m)].board.iter().position(|&x| x == m)
    }

    pub fn adjacent(&self, m: Id) -> Vec<Id> {
        let board = &self.players[self.ctrl(m)].board;
        let mut out = vec![];
        if let Some(i) = board.iter().position(|&x| x == m) {
            if i > 0 {
                out.push(board[i - 1]);
            }
            if i + 1 < board.len() {
                out.push(board[i + 1]);
            }
        }
        out.retain(|&x| self.awake(x));
        out
    }

    /// All entities whose hooks can trigger: heroes, hero powers, weapons, minions, secrets.
    pub fn in_play(&self) -> Vec<Id> {
        let mut out = Vec::with_capacity(self.players.iter().map(|p| 3 + p.board.len() + p.secrets.len()).sum());
        for p in &self.players {
            out.push(p.hero);
            out.push(p.hero_power);
            if let Some(w) = p.weapon {
                out.push(w);
            }
            out.extend(&p.board);
            out.extend(&p.secrets);
        }
        self.by_order(out)
    }

    pub fn by_order(&self, mut v: Vec<Id>) -> Vec<Id> {
        v.sort_by_key(|&id| self.e(id).play_order);
        v
    }

    pub fn hooks_of(&self, id: Id) -> &'static HookSet {
        let e = self.e(id);
        if e.silenced { self.rs.hooks("") } else { e.hooks() }
    }

    // --- events and resolution --------------------------------------------------

    /// Logs the event (with the card whose effect did it) and returns its index.
    pub fn log_event(&mut self, mut ev: Obj) -> usize {
        if !self.source_card.is_empty() && !ev.contains_key("by") {
            ev.insert("by", self.source_card);
            ev.insert("by_id", self.source_id);
        }
        self.event_log.push(ev);
        self.event_log.len() - 1
    }

    /// An event of the current action.
    pub fn ev(&self, i: usize) -> &Obj {
        &self.event_log[i]
    }

    pub fn ev_i(&self, i: usize, key: &str) -> i64 {
        vint(self.event_log[i].get(key))
    }

    pub fn ev_s(&self, i: usize, key: &str) -> &str {
        self.event_log[i].get(key).and_then(V::as_str).unwrap_or("")
    }

    pub fn ev_b(&self, i: usize, key: &str) -> bool {
        vtruthy(self.event_log[i].get(key))
    }

    pub fn ev_set(&mut self, i: usize, key: impl Into<Str>, v: impl Into<V>) {
        self.event_log[i].insert(key, v);
    }

    /// Logs the event and queues every matching "on" trigger (card and enchantment hooks).
    pub fn emit(&mut self, ev: Obj) -> usize {
        let i = self.log_event(ev);
        let ty = match self.event_log[i].get("type") {
            Some(V::Str(s)) => s.clone(),
            _ => Str::Borrowed(""),
        };
        let rs = self.rs;
        // DOUBLE_TURN_END (an aura count on the champion: Drakkari Enchanter): the `turn_end` hooks of its owner's
        // entities run that many more times, at the end of either player's turn (Gruul grows twice each turn)
        let extra = |g: &Game, e: Id| -> usize {
            match g.n().double_turn_end {
                Some(t) if ty == "turn_end" => {
                    vint(g.e(g.hero(g.ctrl(e))).aura.tags.get(t)).clamp(0, 10) as usize
                }
                _ => 0,
            }
        };
        for e in self.in_play() {
            let h = self.hooks_of(e);
            let times = 1 + extra(self, e);
            if let Some(f) = h.on(&ty) {
                for _ in 0..times {
                    self.queue.push_back(QItem { f: Trigger::On(f), me: e, ev: Some(i), needs_in_play: true });
                }
            }
            if let Some(s) = h.trap {
                if s.event == ty {
                    self.queue.push_back(QItem { f: Trigger::Trap(s), me: e, ev: Some(i), needs_in_play: true });
                }
            }
            for x in &self.entities[(e - 1) as usize].enchantments {
                if let Some(f) = x.get("hooks").and_then(V::as_str).and_then(|h| rs.hooks(h).on(&ty)) {
                    for _ in 0..times {
                        self.queue.push_back(QItem { f: Trigger::On(f), me: e, ev: Some(i), needs_in_play: true });
                    }
                }
            }
        }
        // the pack's player hooks (rules.json `player_hooks`), once for each player, `me` = the champion
        if let Some(f) = rs.player_hooks.as_deref().and_then(|h| rs.hooks(h).on(&ty)) {
            for p in 0..self.players.len() {
                let h = self.players[p].hero;
                self.queue.push_back(QItem { f: Trigger::On(f), me: h, ev: Some(i), needs_in_play: true });
            }
        }
        if self.phase != "MULLIGAN" {
            // cards in the hands with `hand` hooks, their card's and their enchantments' (none in Classic: its queue
            // is unchanged)
            for p in 0..self.players.len() {
                for k in 0..self.players[p].hand.len() {
                    let e = self.players[p].hand[k];
                    if let Some(f) = self.e(e).hooks().hand(&ty) {
                        self.queue.push_back(QItem { f: Trigger::Hand(f), me: e, ev: Some(i), needs_in_play: false });
                    }
                    for x in &self.entities[(e - 1) as usize].enchantments {
                        if let Some(f) = x.get("hooks").and_then(V::as_str).and_then(|h| rs.hooks(h).hand(&ty)) {
                            self.queue.push_back(QItem { f: Trigger::Hand(f), me: e, ev: Some(i), needs_in_play: false });
                        }
                    }
                }
            }
            // the discarded card's own `hand.discard` hook, although it left the hand ("when you discard this":
            // Fist of Jaraxxus; no Classic card has one)
            if ty == "discard" {
                let e = vint(self.event_log[i].get("entity"));
                if let Some(f) = self.ent(e).and_then(|x| x.hooks().hand("discard")) {
                    self.queue.push_back(QItem { f: Trigger::On(f), me: e, ev: Some(i), needs_in_play: false });
                }
            }
        }
        i
    }

    /// The hooks of e's enchantments, in order.
    fn ench_hooks(&self, e: Id) -> Vec<&'static HookSet> {
        let rs = self.rs;
        self.e(e).enchantments.iter().filter_map(|x| x.get("hooks").and_then(V::as_str)).map(|h| rs.hooks(h)).collect()
    }

    /// The death hooks of e's enchantments, in order: a `hooks` set's, or (`{deathrattle = <card id>}`) only that
    /// card's own death hook (Unearthed Raptor: a copy of a minion's Deathrattle, not its other hooks).
    fn ench_deaths(&self, e: Id) -> Vec<HookFn> {
        let rs = self.rs;
        self.e(e)
            .enchantments
            .iter()
            .filter_map(|x| x.get("hooks").or_else(|| x.get("deathrattle")).and_then(V::as_str))
            .filter_map(|h| rs.hooks(h).on_death)
            .collect()
    }

    /// Calls matching "now" hooks (card and enchantment) at once. Used for
    /// replacement effects (`now` hooks: "predamage").
    pub fn emit_now(&mut self, ev: &mut Obj) {
        let ty = ev.get("type").and_then(V::as_str).unwrap_or("").to_string();
        for e in self.in_play() {
            if let Some(f) = self.hooks_of(e).now(&ty) {
                self.from(e, |g| g.fx_now(f, e, &mut *ev));
            }
            for hooks in self.ench_hooks(e) {
                if let Some(f) = hooks.now(&ty) {
                    self.from(e, |g| g.fx_now(f, e, &mut *ev));
                }
            }
        }
    }

    /// Runs queued triggers, then the death phase, until nothing is left.
    pub fn resolve(&mut self) {
        self.end_by_script_error();
        let mut steps = 0;
        let trap = self.n().trap;
        while !self.game_over {
            while !self.queue.is_empty() && !self.game_over {
                steps += 1;
                if steps > self.rs.queue_steps {
                    self.queue.clear();
                    break;
                }
                let q = self.queue.pop_front().unwrap();
                let zone = self.e(q.me).zone;
                if q.needs_in_play && !(zone == "PLAY" || zone == trap) {
                    continue;
                }
                if matches!(q.f, Trigger::Hand(_)) && zone != "HAND" {
                    continue;
                }
                let me = q.me;
                self.from(me, |g| match q.f {
                    Trigger::On(f) | Trigger::Hand(f) => g.fx_on(f, me, q.ev.unwrap()),
                    Trigger::Trap(s) => {
                        let ev = q.ev.unwrap();
                        if g.trap_ready(me) && s.cond.is_none_or(|c| g.fx_cond(c, me, ev)) && !g.game_over {
                            g.reveal(me);
                            g.fx_on(s.effect, me, ev);
                        }
                    }
                    Trigger::OnDeath(f) => g.fx_me(f, me),
                });
                self.end_by_script_error();
            }
            let pure = self.auras();
            let over = self.game_over;
            if !self.death_phase() {
                // no deaths changed nothing: auras again would give the same (card scripts keep no state)
                if pure && over == self.game_over {
                    return;
                }
                break;
            }
        }
        self.update_auras();
    }

    /// Removes the dead (minions, weapons) and queues their death hooks and `death` events, without running
    /// the queue (`g.remove_dead`); true if anything died.
    pub(crate) fn death_phase(&mut self) -> bool {
        let mut dead = vec![];
        let n = self.n();
        for p in &self.players {
            for &m in &p.board {
                let e = self.e(m);
                if e.health() <= 0 || vtruthy(e.tags.get(n.to_destroy)) {
                    dead.push(m);
                }
            }
            if let Some(w) = p.weapon {
                let e = self.e(w);
                if e.tag(n.durability) <= 0 || vtruthy(e.tags.get(n.to_destroy)) {
                    dead.push(w);
                }
            }
        }
        let dead = self.by_order(dead);
        let turn = self.turn;
        for &d in &dead {
            let c = self.ctrl(d);
            if self.e(d).is_minion() {
                let pos = self.players[c].board.iter().position(|&x| x == d).map_or(-1, |i| i as i64);
                self.em(d).set_tag(n.died_pos, pos);
                if let Some(t) = n.died_turn {
                    self.em(d).set_tag(t, turn);
                }
                self.players[c].board.retain(|&x| x != d);
            } else {
                self.players[c].weapon = None;
            }
            self.em(d).zone = "GRAVEYARD";
        }
        // DOUBLE_ON_DEATH (Baron Rivendare): only while its source is still on the board after these deaths
        let twice = self.players.iter().any(|p| self.e(p.hero).aura.tags.contains_key(n.double_on_death));
        if twice {
            self.auras();
        }
        for &d in &dead {
            let times = if twice && self.e(d).is_minion() && self.e(self.hero(self.ctrl(d))).has(n.double_on_death) { 2 } else { 1 };
            for _ in 0..times {
                if let Some(f) = self.hooks_of(d).on_death {
                    self.queue.push_back(QItem { f: Trigger::OnDeath(f), me: d, ev: None, needs_in_play: false });
                }
                for f in self.ench_deaths(d) {
                    self.queue.push_back(QItem { f: Trigger::OnDeath(f), me: d, ev: None, needs_in_play: false });
                }
            }
            let e = self.e(d);
            let ev = obj!{"type": "death", "entity": d, "player": e.controller, "card": e.card_id, "minion": e.is_minion()};
            self.emit(ev);
        }
        let mut heroes_dead = vec![];
        for p in &self.players {
            let h = self.e(p.hero);
            if h.health() <= 0 || vtruthy(h.tags.get(n.to_destroy)) {
                heroes_dead.push(p.index);
            }
        }
        if !heroes_dead.is_empty() {
            self.game_over = true;
            self.phase = "OVER";
            self.winner = if heroes_dead.len() == 2 { -1 } else { self.opponent(heroes_dead[0]) as i64 };
            self.queue.clear();
            self.log_event(obj!{"type": "game_over", "winner": self.winner});
            return false;
        }
        !dead.is_empty()
    }

    /// Runs f with source_card set to the card of e, then restores it.
    pub fn from<R>(&mut self, e: Id, f: impl FnOnce(&mut Game) -> R) -> R {
        let was = std::mem::take(&mut self.source_card);
        let was_id = self.source_id;
        if e != NONE {
            self.source_card = self.e(e).card_id;
            self.source_id = e;
        } else {
            self.source_id = NONE;
        }
        let r = f(self);
        self.source_card = was;
        self.source_id = was_id;
        r
    }

    pub fn update_auras(&mut self) {
        self.auras();
    }

    /// `update_auras`; true if the hooks only added auras and no Health was lost, so that
    /// running it again on the same state changes nothing.
    fn auras(&mut self) -> bool {
        let was = (self.writes, self.rng.state, self.script_error.get().is_some());
        let mut same = true;
        let all = self.in_play();
        let before: Vec<(i64, i64)> = all.iter().map(|&e| (self.e(e).max_health(), self.e(e).health())).collect();
        for &e in &all {
            let a = &self.e(e).aura;
            if a.atk != 0 || a.hp != 0 || !a.tags.is_empty() || !a.src.is_empty() {
                self.em(e).aura = Default::default();
            }
        }
        for final_pass in [false, true] {
            for &e in &all {
                let h = self.hooks_of(e);
                let f = if final_pass { h.aura_final } else { h.aura };
                if let Some(f) = f {
                    if self.e(e).zone == "PLAY" {
                        self.from(e, |g| g.fx_me(f, e));
                    }
                }
            }
        }
        for (i, &e) in all.iter().enumerate() {
            // fix_health changes nothing unless max Health dropped
            if self.e(e).max_health() < before[i].0 {
                let d = self.e(e).damage;
                self.em(e).fix_health(before[i].0, before[i].1);
                same &= self.e(e).damage == d;
            }
        }
        same && was == (self.writes, self.rng.state, self.script_error.get().is_some())
    }

    pub fn aura_add(&mut self, t: Id, atk: i64, hp: i64, tags: Vec<(Str, V)>) {
        let src = self.source_card;
        let n = self.n();
        let a = &mut self.em(t).aura;
        a.atk += atk;
        a.hp += hp;
        if !src.is_empty() && (atk != 0 || hp != 0) {
            match a.src.binary_search_by(|(k, _)| (*k).cmp(src)) {
                Ok(i) => {
                    a.src[i].1[0] += atk;
                    a.src[i].1[1] += hp;
                }
                Err(i) => a.src.insert(i, (src, [atk, hp])),
            }
        }
        for (k, v) in tags {
            if k == n.spell_power || k == n.power_multiplier || k == n.power_damage || Some(k.as_ref()) == n.double_turn_end {
                let n = vint(a.tags.get(&k)) + v.int();
                a.tags.insert(k, n);
            } else {
                a.tags.insert(k, v);
            }
        }
    }

    // --- primitives -------------------------------------------------------------

    fn alive_in_play(&self, t: Id) -> bool {
        t != NONE && self.e(t).zone == "PLAY"
    }

    pub fn damage(&mut self, src: Id, t: Id, amount: i64) -> i64 {
        self.damage_from(src, t, amount, true)
    }

    /// `damage`; `steal`: a LIFESTEAL source heals its champion (not the damage a Lifesteal heal turned into: it
    /// hurts the champion once, Auchenai Soulpriest in Knights of the Frozen Throne).
    fn damage_from(&mut self, src: Id, t: Id, amount: i64, steal: bool) -> i64 {
        if !self.alive_in_play(t) || amount <= 0 || !self.awake(t) {
            return 0;
        }
        let mut pre = obj!{"type": "predamage", "source": src, "target": t, "amount": amount};
        self.emit_now(&mut pre);
        let mut amount = vint(pre.get("amount"));
        let n = self.n();
        if amount <= 0 || self.e(t).has(n.immune) {
            return 0;
        }
        if self.e(t).has(n.barrier) {
            self.em(t).erase_tag(n.barrier);
            // an event a pack's hooks may hear ("after a friendly minion loses Divine Shield": Bolvar, Fireblood); no
            // older pack listens to it
            self.emit(obj!{"type": "divine_shield_lost", "target": t});
            return 0;
        }
        let dealt = amount; // Lifesteal heals what was dealt, Armor or not
        let stealer = if steal { self.lifesteal_of(src) } else { None };
        if self.e(t).is_champion() {
            let armor = self.e(t).tag(n.armor);
            let absorbed = armor.min(amount);
            self.em(t).set_tag(n.armor, armor - absorbed);
            amount -= absorbed;
            if amount <= 0 {
                self.log_event(obj!{"type": "armor_lost", "target": t, "amount": absorbed});
                if let Some(p) = stealer {
                    self.lifesteal_heal(src, p, dealt);
                }
                return 0;
            }
        }
        self.em(t).damage += amount;
        if src != NONE && self.e(src).is_minion() && self.e(src).has(n.stealth) {
            self.em(src).erase_tag(n.stealth);
        }
        // a champion attacking with a POISON weapon (Envenom Weapon) poisons as a POISON minion does
        let weapon_poison = |g: &Game| {
            let s = g.e(src);
            s.is_champion() && s.controller == g.current && g.players[s.controller].weapon.is_some_and(|w| g.e(w).has(n.poison))
        };
        if src != NONE && self.e(t).is_minion() && (self.e(src).has(n.poison) || weapon_poison(self)) {
            self.em(t).set_tag(n.to_destroy, true);
        }
        let player = self.ctrl(t);
        self.emit(obj!{"type": "damage", "source": src, "target": t, "amount": amount, "player": player});
        if let Some(p) = stealer {
            self.lifesteal_heal(src, p, dealt);
        }
        amount
    }

    /// The player whose champion src's damage heals (LIFESTEAL, a pack that names it): src has it, or src is a
    /// champion attacking with a LIFESTEAL weapon on its turn.
    fn lifesteal_of(&self, src: Id) -> Option<usize> {
        let t = self.n().lifesteal?;
        let s = self.ent(src)?;
        let weapon = s.is_champion() && s.controller == self.current
            && self.players[s.controller].weapon.is_some_and(|w| self.e(w).has(t));
        (s.has(t) || weapon).then_some(s.controller)
    }

    /// A Lifesteal heal of p's champion by n from src; healing that is damage (HEAL_IS_DAMAGE: Auchenai Soulpriest)
    /// hurts it, once.
    fn lifesteal_heal(&mut self, src: Id, p: usize, n: i64) {
        let h = self.hero(p);
        if self.e(h).has(self.n().heal_is_damage) {
            self.damage_from(src, h, n, false);
        } else {
            self.heal(src, h, n);
        }
    }

    pub fn heal(&mut self, src: Id, t: Id, amount: i64) -> i64 {
        if !self.alive_in_play(t) || amount <= 0 {
            return 0;
        }
        if src != NONE && self.e(self.hero(self.ctrl(src))).has(self.n().heal_is_damage) {
            return self.damage(src, t, amount);
        }
        let healed = amount.min(self.e(t).damage);
        if healed <= 0 {
            return 0;
        }
        self.em(t).damage -= healed;
        self.emit(obj!{"type": "heal", "source": src, "target": t, "amount": healed});
        healed
    }

    /// The shortest turn time (seconds) a minion in play asks for (card `turn_seconds`,
    /// Nozdormu); None = turns have their usual time. Servers and clients time turns by it.
    pub fn turn_seconds(&self) -> Option<i64> {
        self.players.iter().flat_map(|p| p.board.iter()).map(|&m| self.e(m).card.turn_seconds).filter(|&s| s > 0).min()
    }

    pub fn destroy(&mut self, e: Id) {
        if self.alive_in_play(e) && self.awake(e) {
            let t = self.n().to_destroy;
            self.em(e).set_tag(t, true);
        }
    }

    pub fn summon(&mut self, p: usize, card_id: &str, pos: i64) -> Id {
        if self.players[p].board.len() >= self.rs.board {
            return NONE;
        }
        let e = self.new_entity(card_id, p);
        self.summon_entity(e, pos)
    }

    /// Puts an existing entity (for example a card from the hand) onto the board as a summon.
    pub fn summon_entity(&mut self, e: Id, pos: i64) -> Id {
        let c = self.ctrl(e);
        if self.players[c].board.len() >= self.rs.board {
            return NONE;
        }
        self.place_on_board(e, pos);
        let t = self.n().exhausted;
        self.em(e).give_tag(t, false);
        let card = self.e(e).card_id;
        self.emit(obj!{"type": "summon", "entity": e, "player": c, "card": card});
        self.emit(obj!{"type": "after_summon", "entity": e, "player": c, "card": card});
        e
    }

    pub fn draw(&mut self, p: usize, count: i64) -> Vec<Id> {
        let mut out = vec![];
        for _ in 0..count {
            let Some(e) = self.players[p].deck.pop() else {
                let (on, first, step) = self.rs.fatigue;
                if !on {
                    continue;
                }
                self.players[p].fatigue += 1;
                let f = first + (self.players[p].fatigue - 1) * step;
                self.log_event(obj!{"type": "fatigue", "player": p, "amount": f});
                self.damage(NONE, self.players[p].hero, f);
                continue;
            };
            let card = self.e(e).card_id;
            if self.players[p].hand.len() >= self.rs.hand {
                self.em(e).zone = "GRAVEYARD";
                self.log_event(obj!{"type": "burn", "player": p, "entity": e, "card": card});
                continue;
            }
            self.em(e).zone = "HAND";
            self.players[p].hand.push(e);
            out.push(e);
            self.emit(obj!{"type": "draw", "player": p, "entity": e, "card": card});
        }
        out
    }

    /// Draws a specific card from p's deck (burns it if the hand is full).
    pub fn draw_entity(&mut self, p: usize, e: Id, quiet: bool) {
        let pl = &mut self.players[p];
        let Some(i) = pl.deck.iter().position(|&x| x == e) else { return };
        pl.deck.remove(i);
        let card = self.e(e).card_id;
        if self.players[p].hand.len() >= self.rs.hand {
            self.em(e).zone = "GRAVEYARD";
            self.log_event(obj!{"type": "burn", "player": p, "entity": e, "card": card});
            return;
        }
        self.em(e).zone = "HAND";
        self.players[p].hand.push(e);
        if quiet {
            // put into the hand, not drawn: no `draw` event (Ancient Harbinger)
            self.log_event(obj!{"type": "to_hand", "player": p, "entity": e, "card": card});
            return;
        }
        self.emit(obj!{"type": "draw", "player": p, "entity": e, "card": card});
    }

    /// A new card entity for p, set aside (an option of `g.request_choice`: Totemic Slam).
    pub fn create(&mut self, p: usize, card_id: &str) -> Id {
        let e = self.new_entity(card_id, p);
        self.em(e).created = true;
        self.log_event(obj!{"type": "create", "player": p, "entity": e, "card": self.e(e).card_id});
        e
    }

    pub fn add_to_hand(&mut self, p: usize, card_id: &str) -> Id {
        if self.players[p].hand.len() >= self.rs.hand {
            return NONE;
        }
        let e = self.new_entity(card_id, p);
        self.em(e).zone = "HAND";
        self.players[p].hand.push(e);
        self.emit(obj!{"type": "add_to_hand", "player": p, "entity": e, "card": self.e(e).card_id});
        e
    }

    pub fn discard_random(&mut self, p: usize, count: i64) {
        for _ in 0..count {
            let hand = self.players[p].hand.clone();
            let e = self.random_choice(&hand);
            if e == NONE {
                return;
            }
            self.players[p].hand.retain(|&x| x != e);
            self.em(e).zone = "GRAVEYARD";
            let card = self.e(e).card_id;
            self.emit(obj!{"type": "discard", "player": p, "entity": e, "card": card});
        }
    }

    pub fn buff(&mut self, e: Id, atk: i64, hp: i64, eot: bool) {
        let mut ench = Obj::new();
        ench.insert("atk", atk);
        ench.insert("eot", eot);
        ench.insert("hp", hp);
        if !self.source_card.is_empty() {
            ench.insert("src", self.source_card);
        }
        self.em(e).enchantments.push(ench);
        self.log_event(obj!{"type": "buff", "target": e, "atk": atk, "hp": hp});
    }

    /// Sets Attack and/or Health (-1 keeps the value). Setting Health clears damage.
    pub fn set_stats(&mut self, e: Id, atk: i64, hp: i64) {
        let mut ench = Obj::new();
        if atk >= 0 {
            ench.insert("set_atk", atk);
        }
        if hp >= 0 {
            ench.insert("set_hp", hp);
            self.em(e).damage = 0;
        }
        if !self.source_card.is_empty() {
            ench.insert("src", self.source_card);
        }
        self.em(e).enchantments.push(ench);
        self.log_event(obj!{"type": "buff", "target": e, "set_atk": atk, "set_hp": hp});
    }

    pub fn silence(&mut self, e: Id) {
        let tags = &self.rs.names.silenced;
        self.em(e).silence(tags);
        self.log_event(obj!{"type": "silence", "target": e});
    }

    pub fn freeze(&mut self, e: Id) {
        if !self.alive_in_play(e) {
            return;
        }
        let (cur, n) = (self.current, self.n());
        let x = self.em(e);
        x.set_tag(n.frozen, true);
        if x.controller == cur {
            x.set_tag(n.frozen_this_turn, true);
        }
        // an event a pack's hooks may hear ("whenever another minion is Frozen": Moorabi); no older pack listens to it
        self.emit(obj!{"type": "freeze", "target": e});
    }

    pub fn transform(&mut self, e: Id, card_id: &str) -> Id {
        let c = self.ctrl(e);
        let Some(i) = self.players[c].board.iter().position(|&x| x == e) else { return self.transform_card(e, card_id) };
        let n = self.new_entity(card_id, c);
        self.players[c].board[i] = n;
        let (order, t, choice) = (self.e(e).play_order, self.n().exhausted, self.e(e).choice);
        let ne = self.em(n);
        ne.zone = "PLAY";
        ne.play_order = order;
        ne.choice = choice; // the option it was played with (`g.choice`: Fatespinner becomes its in-play form)
        ne.give_tag(t, false);
        self.em(e).zone = "SETASIDE";
        self.emit(obj!{"type": "transform", "from": e, "to": n, "card": self.e(n).card_id});
        n
    }

    /// Transforms a card in its owner's hand or deck into another card, in its place (Shifter Zerus, Renounce
    /// Darkness); NONE if it is in neither. Only its owner sees which card it became (the event's `entity`).
    fn transform_card(&mut self, e: Id, card_id: &str) -> Id {
        let c = self.ctrl(e);
        let pl = &self.players[c];
        let (hand, i) = match (pl.hand.iter().position(|&x| x == e), pl.deck.iter().position(|&x| x == e)) {
            (Some(i), _) => (true, i),
            (None, Some(i)) => (false, i),
            _ => return NONE,
        };
        let n = self.new_entity(card_id, c);
        let zone = self.e(e).zone;
        self.em(n).zone = zone;
        if hand {
            self.players[c].hand[i] = n;
        } else {
            self.players[c].deck[i] = n;
        }
        self.em(e).zone = "SETASIDE";
        self.em(e).created = true; // set aside from a hidden zone: still only its owner sees which card it was
        self.emit(obj!{"type": "transform", "from": e, "entity": n, "player": c, "card": self.e(n).card_id});
        n
    }

    /// Returns a minion to its owner's hand as a fresh card (NONE if the hand is full).
    pub fn return_to_hand(&mut self, e: Id) -> Id {
        let c = self.ctrl(e);
        if !self.players[c].board.contains(&e) {
            return NONE;
        }
        if self.rs.full_hand_return_dies && self.players[c].hand.len() >= self.rs.hand {
            self.destroy(e); // it dies in the next death phase, as any other
            return NONE;
        }
        self.players[c].board.retain(|&x| x != e);
        self.em(e).zone = "SETASIDE";
        let card = self.e(e).card_id;
        let n = self.add_to_hand(c, &card);
        self.log_event(obj!{"type": "return_to_hand", "entity": e, "new": n});
        n
    }

    pub fn take_control(&mut self, e: Id, p: usize) {
        let c = self.ctrl(e);
        if c != p && self.players[c].secrets.contains(&e) {
            // a trap changes sides; one its new owner already has, or one over their limit, is destroyed (Kezan Mystic)
            self.players[c].secrets.retain(|&x| x != e);
            if !self.trap_room(p, self.e(e).card_id) {
                self.em(e).zone = "GRAVEYARD";
                self.log_event(obj!{"type": "destroy", "target": e});
                return;
            }
            self.em(e).controller = p;
            self.players[p].secrets.push(e);
            self.emit(obj!{"type": "take_control", "target": e, "player": p});
            return;
        }
        if c == p || !self.players[c].board.contains(&e) {
            return;
        }
        self.players[c].board.retain(|&x| x != e);
        if self.players[p].board.len() >= self.rs.board {
            self.em(e).zone = "GRAVEYARD";
            self.log_event(obj!{"type": "destroy", "target": e});
            return;
        }
        self.em(e).controller = p;
        self.players[p].board.push(e);
        let n = self.n();
        let x = self.em(e);
        x.give_tag(n.exhausted, false);
        x.set_tag(n.attacks, 0i64);
        self.emit(obj!{"type": "take_control", "target": e, "player": p});
    }

    /// A new card shuffled into p's deck at a random place (`g.add_to_deck`).
    pub fn add_to_deck(&mut self, p: usize, card_id: &str) -> Id {
        let e = self.new_entity(card_id, p);
        self.em(e).zone = "DECK";
        let n = self.players[p].deck.len() as i64;
        let i = self.rng.randi_range(0, n) as usize;
        self.players[p].deck.insert(i, e);
        self.log_event(obj!{"type": "add_to_deck", "player": p, "entity": e, "card": self.e(e).card_id});
        e
    }

    /// Runs m's death hooks now (its card's, unless silenced, then its enchantments'), as if it died:
    /// Feign Death.
    pub fn run_death_hooks(&mut self, m: Id) {
        self.run_death_hooks_of(m, false);
    }

    /// `run_death_hooks`; `own`: only its card's Deathrattle and the ones copied onto it (`{deathrattle = card}`:
    /// Unearthed Raptor), not the hook sets other cards gave it (Spikeridged Steed's, Spirit Echo's: Spiritsinger Umbra).
    pub fn run_death_hooks_of(&mut self, m: Id, own: bool) {
        let mut fs: Vec<HookFn> = self.hooks_of(m).on_death.into_iter().collect();
        if own {
            let rs = self.rs;
            let copied = self.e(m).enchantments.iter().filter_map(|x| x.get("deathrattle").and_then(V::as_str));
            let copied: Vec<HookFn> = copied.filter_map(|h| rs.hooks(h).on_death).collect();
            fs.extend(copied);
        } else {
            fs.extend(self.ench_deaths(m));
        }
        for f in fs {
            if self.game_over {
                return;
            }
            self.from(m, |g| g.fx_me(f, m));
        }
    }

    pub fn equip(&mut self, p: usize, card_id: &str) -> Id {
        let w = self.new_entity(card_id, p);
        self.equip_entity(w)
    }

    pub fn equip_entity(&mut self, w: Id) -> Id {
        let c = self.ctrl(w);
        if let Some(old) = self.players[c].weapon {
            self.em(old).zone = "GRAVEYARD";
            self.log_event(obj!{"type": "destroy", "target": old});
            if self.rs.replaced_weapon_dies {
                // destroyed as any other (behaviour.replaced_weapon_dies): its Deathrattle, the `death` event
                for f in self.hooks_of(old).on_death.into_iter().chain(self.ench_deaths(old)) {
                    self.queue.push_back(QItem { f: Trigger::OnDeath(f), me: old, ev: None, needs_in_play: false });
                }
                let card = self.e(old).card_id;
                self.emit(obj!{"type": "death", "entity": old, "player": c, "card": card, "minion": false});
            }
        }
        self.players[c].weapon = Some(w);
        self.enter_play(w);
        let card = self.e(w).card_id;
        self.emit(obj!{"type": "equip", "player": c, "entity": w, "card": card});
        w
    }

    pub fn gain_armor(&mut self, p: usize, n: i64) {
        let (h, t) = (self.hero(p), self.n().armor);
        let a = self.e(h).tag(t);
        self.em(h).set_tag(t, a + n);
        self.emit(obj!{"type": "armor", "player": p, "amount": n});
    }

    /// Full crystals by default. empty=true adds empty crystals.
    pub fn gain_mana(&mut self, p: usize, n: i64, empty: bool) {
        let max = self.rs.max_mana;
        let pl = &mut self.players[p];
        for _ in 0..n {
            if pl.max_mana < max {
                pl.max_mana += 1;
                if !empty {
                    pl.mana += 1;
                }
            }
        }
        let (max, mana) = (pl.max_mana, pl.mana);
        self.log_event(obj!{"type": "mana", "player": p, "max": max, "mana": mana});
    }

    /// POWER_MULTIPLIER (an aura tag on the champion, a count) doubles damage and
    /// healing of spells and powers only, once per count.
    fn power_multiplier(&self, me: Id) -> i64 {
        let k = self.e(me).kind();
        if k != "SPELL" && k != "POWER" {
            return 1;
        }
        1 << vint(self.e(self.hero(self.ctrl(me))).aura.tags.get(self.n().power_multiplier)).clamp(0, 20)
    }

    pub fn spell_dmg(&self, me: Id, n: i64) -> i64 {
        (n + self.side_spell_power(self.ctrl(me))) * self.power_multiplier(me)
    }

    /// p's spell power: its minions', and its champion's (an aura tag: Jungle Moonkin gives the opponent's too).
    pub fn side_spell_power(&self, p: usize) -> i64 {
        let t = self.n().spell_power;
        let pl = &self.players[p];
        pl.board.iter().map(|&m| self.e(m).spell_power(t)).sum::<i64>() + self.ent(pl.hero).map_or(0, |h| vint(h.aura.tags.get(t)))
    }

    /// A power's damage: n plus POWER_DAMAGE (an aura tag on the champion: Fallen Hero), then POWER_MULTIPLIER.
    pub fn hp_dmg(&self, me: Id, n: i64) -> i64 {
        let bonus = if self.e(me).kind() == "POWER" {
            vint(self.e(self.hero(self.ctrl(me))).aura.tags.get(self.n().power_damage))
        } else {
            0
        };
        (n + bonus) * self.power_multiplier(me)
    }

    pub fn heal_amt(&self, me: Id, n: i64) -> i64 {
        n * self.power_multiplier(me)
    }

    /// Replaces p's hero with a fresh hero entity (full health, no armor or Frozen).
    pub fn replace_hero(&mut self, p: usize, card_id: &str) -> Id {
        let old = self.players[p].hero;
        self.em(old).zone = "SETASIDE";
        let h = self.new_entity(card_id, p);
        self.enter_play(h);
        if let Some(t) = self.n().powers_used {
            if let Some(v) = self.e(old).tags.get(t).cloned() {
                self.em(h).set_tag(t, v); // the count is the player's: a new champion keeps it
            }
        }
        self.players[p].hero = h;
        self.log_event(obj!{"type": "hero_replaced", "player": p, "entity": h, "card": self.e(h).card_id});
        h
    }

    /// Replaces p's hero power with a fresh, unused one.
    pub fn set_hero_power(&mut self, p: usize, card_id: &str) -> Id {
        let old = self.players[p].hero_power;
        self.em(old).zone = "SETASIDE";
        let hp = self.new_entity(card_id, p);
        self.enter_play(hp);
        self.players[p].hero_power = hp;
        self.log_event(obj!{"type": "hero_power_changed", "player": p, "entity": hp, "card": self.e(hp).card_id});
        hp
    }

    /// A random element (None for an empty list).
    pub fn pick<T: Clone>(&mut self, arr: &[T]) -> Option<T> {
        if arr.is_empty() {
            return None;
        }
        Some(arr[self.rng.randi_range(0, arr.len() as i64 - 1) as usize].clone())
    }

    pub fn random_choice(&mut self, arr: &[Id]) -> Id {
        self.pick(arr).unwrap_or(NONE)
    }

    /// Random entity from arr that is in play and not already dying (health > 0).
    pub fn random_alive(&mut self, arr: &[Id]) -> Id {
        let alive: Vec<Id> = arr.iter().copied().filter(|&e| self.e(e).zone == "PLAY" && self.e(e).health() > 0).collect();
        self.random_choice(&alive)
    }

    pub fn shuffle<T>(arr: &mut [T], r: &mut Rng) {
        for i in (1..arr.len()).rev() {
            let j = r.randi_range(0, i as i64) as usize;
            arr.swap(i, j);
        }
    }

    pub fn shuffle_ids(&mut self, arr: &mut [Id]) {
        Game::shuffle(arr, &mut self.rng);
    }

    fn spec_ok(&self, src: Id, spec: &TSpec, t: Id) -> bool {
        let te = self.e(t);
        let mine = te.controller == self.ctrl(src);
        let base = match spec.base {
            Base::Any => true,
            Base::Minion => te.is_minion(),
            Base::EnemyMinion => te.is_minion() && !mine,
            Base::FriendlyMinion => te.is_minion() && mine,
            Base::EnemyChar => !mine,
            Base::FriendlyChar => mine,
            Base::EnemyChampion => te.is_champion() && !mine,
        };
        base && spec.filter.is_none_or(|p| self.fx_filter(p, src, t))
    }

    /// Characters that src may target. Enemy Stealth is never targetable;
    /// SPELLPROOF blocks spells and powers (is_spell=true).
    pub fn targets(&self, src: Id, spec: &TSpec, is_spell: bool) -> Vec<Id> {
        let (me, n) = (self.ctrl(src), self.n());
        self.all_chars()
            .into_iter()
            .filter(|&t| {
                let te = self.e(t);
                !(te.controller != me && te.has(n.stealth)) && !(is_spell && te.has(n.spellproof)) && self.spec_ok(src, spec, t)
            })
            .collect()
    }

    /// Whether player `p` may get trap `card` into play: fewer than `limits.secrets` traps and not
    /// this one already. Every way in checks it (played from the hand, `put_trap`, `take_control`).
    pub fn trap_room(&self, p: usize, card: &str) -> bool {
        let s = &self.players[p].secrets;
        s.len() < self.rs.secrets && !s.iter().any(|&x| self.e(x).card_id == card)
    }

    /// Whether player `p` may play a task card (a Quest): no task of theirs in play, and room in the trap zone.
    pub fn task_room(&self, p: usize) -> bool {
        let s = &self.players[p].secrets;
        s.len() < self.rs.secrets && !s.iter().any(|&x| self.e(x).card.task)
    }

    /// p's traps in play, without its task (`g.traps`: a Quest is no Secret).
    pub fn traps(&self, p: usize) -> Vec<Id> {
        self.players[p].secrets.iter().copied().filter(|&x| !self.e(x).card.task).collect()
    }

    /// p's task in play (a Quest), if any (`g.tasks`).
    pub fn tasks(&self, p: usize) -> Vec<Id> {
        self.players[p].secrets.iter().copied().filter(|&x| self.e(x).card.task).collect()
    }

    /// What p's task in play is worth to a bot: 4, and up to 8 more as it nears its goal (0 without one).
    pub fn task_value(&self, p: usize) -> f64 {
        let n = self.n();
        let (Some(tp), Some(tg)) = (n.task_progress, n.task_goal) else { return 0.0 };
        self.tasks(p).iter().map(|&q| {
            let (got, goal) = (self.e(q).tag(tp), self.e(q).tag(tg).max(1));
            4.0 + 8.0 * got.min(goal) as f64 / goal as f64
        }).sum()
    }

    pub fn trap_ready(&self, me: Id) -> bool {
        let e = self.e(me);
        e.zone == self.n().trap && self.current != e.controller
    }

    pub fn reveal(&mut self, me: Id) {
        let c = self.ctrl(me);
        self.players[c].secrets.retain(|&x| x != me);
        self.em(me).zone = "GRAVEYARD";
        let card = self.e(me).card_id;
        self.emit(obj!{"type": "secret_revealed", "entity": me, "player": c, "card": card});
    }

    /// Puts a trap card of its owner's hand or deck into play as if it were played (Mad Scientist);
    /// false (and it stays where it is) if it is not a trap there, the same trap is already in play
    /// or its owner has `limits.secrets` traps.
    pub fn put_trap(&mut self, e: Id) -> bool {
        let c = self.ctrl(e);
        let x = self.e(e);
        let card = x.card_id;
        // (a card made by `g.create`, set aside, too: "put a random Secret into the battlefield", Professor Putricide)
        let made = x.zone == "SETASIDE" && x.created;
        if !x.card.trap || !(x.zone == "HAND" || x.zone == "DECK" || made) || !self.trap_room(c, card) {
            return false;
        }
        let pl = &mut self.players[c];
        pl.hand.retain(|&y| y != e);
        pl.deck.retain(|&y| y != e);
        pl.secrets.push(e);
        self.enter_play(e);
        self.em(e).zone = self.rs.names.trap;
        self.log_event(obj!{"type": "trap_put", "entity": e, "player": c, "card": card});
        true
    }

    pub fn request_choice(&mut self, me: Id, options: Vec<Id>) {
        if self.e(me).auto_choice {
            // cast with random choices (g.cast_random): one option at random, at once
            let opt = self.random_choice(&options);
            if let Some(f) = self.e(me).hooks().on_choose {
                self.from(me, |g| g.fx_choose(f, me, opt, options));
            }
            return;
        }
        let zones = options.iter().map(|&id| self.e(id).zone).collect();
        let player = self.ctrl(me);
        let p = Pending { player, source: me, options: options.clone(), zones };
        if self.pending.is_some() {
            self.pending_next.push(p); // asked once the one before is answered
            return;
        }
        self.pending = Some(p);
        self.log_event(obj!{"type": "choice", "player": player, "options": options});
    }

    pub fn add_cost_mod(&mut self, p: usize, mut m: Value) {
        m["turn"] = json!(self.turn);
        if self.rs.cost_in_order {
            m["order"] = json!(self.stamp());
        }
        let Value::Object(m) = m else { unreachable!() };
        let rs = self.rs;
        self.players[p].cost_mods.push(Obj::of(&m, &|s| rs.intern(s)));
    }

    fn mod_applies(&self, m: &Obj, e: Id) -> bool {
        let x = self.e(e);
        if m.get("race").and_then(V::as_str).is_some_and(|r| r != x.card.race) {
            return false;
        }
        match m.get("kind").and_then(V::as_str).unwrap_or("") {
            "any" => true,
            "minion" => x.is_minion(),
            "spell" => x.kind() == "SPELL",
            "secret" | "trap" => x.card.trap,
            "power" => x.kind() == "POWER",
            _ => false,
        }
    }

    pub fn cost(&self, e: Id) -> i64 {
        self.cost_in(e, &self.cost_auras())
    }

    /// Entities in play with a cost aura, in play order (for `cost_in`).
    pub(crate) fn cost_auras(&self) -> Vec<Id> {
        self.in_play().into_iter().filter(|&s| self.hooks_of(s).cost_aura.is_some()).collect()
    }

    /// `cost` with the cost auras given.
    pub(crate) fn cost_in(&self, e: Id, auras: &[Id]) -> i64 {
        if self.rs.cost_in_order {
            return self.cost_in_order(e, auras);
        }
        let x = self.e(e);
        let mut c = x.card.cost;
        if let Some(f) = x.hooks().cost_mod {
            c += self.fx_cost_mod(f, e);
        }
        for ench in &x.enchantments {
            if let Some(v) = ench.get("cost_set") {
                c = v.int(); // "its cost becomes (n)" (Bright-Eyed Scout), then later changes
            }
            c += vint(ench.get("cost"));
        }
        for &src in auras {
            if let Some(f) = self.hooks_of(src).cost_aura {
                if self.e(src).zone == "PLAY" {
                    c = self.fx_cost_aura(f, src, e, c);
                }
            }
        }
        for m in &self.players[x.controller].cost_mods {
            if (vint(m.get("turn")) == self.turn || lasting(m)) && self.mod_applies(m, e) {
                c = if m.contains_key("set") { vint(m.get("set")) } else { c + vint(m.get("delta")) };
            }
        }
        c.max(0)
    }

    /// `cost_in` of a pack with `behaviour.cost_in_order` (Hearthstone until 2017): after the card's own `cost_mod`,
    /// its cost enchantments, the cost auras and its player's cost mods apply in the order they came (an enchantment
    /// or a mod by its `order`, stamped when it was made; an aura by when its source came into play), except a
    /// `cost_first` aura, which comes before them all (Summoning Portal); 0 at least at the end.
    fn cost_in_order(&self, e: Id, auras: &[Id]) -> i64 {
        enum It<'a> {
            Ench(&'a Obj),
            Aura(Id),
            Mod(&'a Obj),
        }
        let x = self.e(e);
        let mut c = x.card.cost;
        if let Some(f) = x.hooks().cost_mod {
            c += self.fx_cost_mod(f, e);
        }
        let mut items: Vec<(i64, It)> = vec![];
        for ench in x.enchantments.iter().filter(|m| m.contains_key("cost") || m.contains_key("cost_set")) {
            items.push((vint(ench.get("order")), It::Ench(ench)));
        }
        for &src in auras {
            let s = self.e(src);
            if s.zone == "PLAY" && self.hooks_of(src).cost_aura.is_some() {
                let first = self.hooks_of(src).cost_first; // its rank among the ones before all others
                items.push((if first > 0 { i64::MIN + first } else { s.play_order }, It::Aura(src)));
            }
        }
        for m in &self.players[x.controller].cost_mods {
            if (vint(m.get("turn")) == self.turn || lasting(m)) && self.mod_applies(m, e) {
                items.push((vint(m.get("order")), It::Mod(m)));
            }
        }
        items.sort_by_key(|(o, _)| *o);
        for (_, it) in items {
            c = match it {
                It::Ench(m) if m.contains_key("cost_set") => vint(m.get("cost_set")) + vint(m.get("cost")),
                It::Ench(m) => c + vint(m.get("cost")),
                It::Aura(src) => self.fx_cost_aura(self.hooks_of(src).cost_aura.unwrap(), src, e, c),
                It::Mod(m) if m.contains_key("set") => vint(m.get("set")),
                It::Mod(m) => c + vint(m.get("delta")),
            };
        }
        c.max(0)
    }

    /// Whether e costs Health instead of Mana now: one of its player's cost mods with `health = true` applies to it
    /// (Cho'gall). Its cost is then paid as damage to its champion (Armor first).
    pub fn pays_health(&self, e: Id) -> bool {
        let x = self.e(e);
        self.players[x.controller].cost_mods.iter().any(|m| {
            vtruthy(m.get("health")) && (vint(m.get("turn")) == self.turn || lasting(m)) && self.mod_applies(m, e)
        })
    }

    /// The next stamp of `order` (an enchantment's or a cost mod's: `cost_in_order`); it shares the play order's count.
    pub(crate) fn stamp(&mut self) -> i64 {
        self.next_order += 1;
        self.next_order - 1
    }

    /// Removes "until": "use" mods that applied to e (called when e is played).
    pub fn consume_cost_mods(&mut self, e: Id) {
        let c = self.ctrl(e);
        let mods = std::mem::take(&mut self.players[c].cost_mods);
        let keep = mods
            .into_iter()
            .filter(|m| {
                !(m.get("until").and_then(V::as_str) == Some("use")
                    && (vint(m.get("turn")) == self.turn || lasting(m))
                    && self.mod_applies(m, e))
            })
            .collect();
        self.players[c].cost_mods = keep;
    }

    /// p's Overloaded crystals unlocked: the ones locked this turn are mana again, nothing is owed next turn.
    pub fn unlock_mana(&mut self, p: usize) {
        let pl = &mut self.players[p];
        pl.mana = pl.max_mana.min(pl.mana + pl.mana_locked);
        pl.mana_locked = 0;
        pl.mana_lock_owed = 0;
    }

    /// Hero attack: weapon attack counts only on the controller's own turn.
    pub fn hero_atk(&self, hero: Id) -> i64 {
        let h = self.e(hero);
        let mut v = h.atk();
        if let Some(w) = self.players[h.controller].weapon {
            if h.controller == self.current {
                v += self.e(w).atk();
            }
        }
        v
    }

    pub fn attack_value(&self, e: Id) -> i64 {
        if self.e(e).is_champion() { self.hero_atk(e) } else { self.e(e).atk() }
    }

    // --- look-ahead -------------------------------------------------------------

    /// Deep copy for look-ahead (the bot). Same entity ids and RNG state; history
    /// and event log are not copied. Call only between actions (empty queue).
    /// The copy shares the card scripts' interpreter (crate::lua); `deep_clone`
    /// gives an independent one.
    pub fn clone_state(&self) -> Game {
        Game { rs: self.rs, rng: self.rng.clone(), players: self.players.clone(), entities: self.entities.clone(),
            turn: self.turn, current: self.current, phase: self.phase, pending: self.pending.clone(), pending_next: self.pending_next.clone(),
            game_over: self.game_over, winner: self.winner, event_log: vec![], history: vec![], queue: VecDeque::new(),
            next_id: self.next_id, next_order: self.next_order, source_card: "", source_id: NONE,
            start_decks: [vec![], vec![]], lua: self.lua.share(), script_error: self.script_error.clone(), writes: 0 }
    }

    /// clone_state with its own copy of the scripts' interpreter (a game of its own: `new {copy}`).
    pub fn deep_clone(&self) -> Game {
        let mut g = self.clone_state();
        g.lua = self.lua.deep();
        g
    }

    /// Transforms me into a copy of t, with t's damage,
    /// enchantments, keywords and Silence. Auras are not copied; the copy is a new
    /// minion (summoning sickness, not Frozen).
    pub fn copy_minion(&mut self, me: Id, t: Id) -> Id {
        let card = self.e(t).card_id;
        let n = self.transform(me, &card);
        if n == NONE {
            return NONE;
        }
        let names = self.n();
        if self.e(t).silenced {
            self.em(n).silence(&names.silenced);
        }
        let src = self.e(t).clone();
        let ne = self.em(n);
        ne.tags = src.tags;
        for k in [names.frozen, names.frozen_this_turn, names.attacks, names.to_destroy, names.died_pos] {
            ne.tags.remove(k);
        }
        ne.give_tag(names.exhausted, false);
        ne.enchantments = src.enchantments;
        ne.damage = src.damage;
        ne.borrowed = src.borrowed; // the hooks it borrowed (a Zombeast's first Beast's)
        ne.choice = src.choice; // its Choose One option (`g.choice`: a copy of Fatespinner keeps its secret Deathrattle)
        n
    }

    // --- serialization ----------------------------------------------------------

    pub fn pending_value(&self) -> Value {
        match &self.pending {
            None => json!({}),
            Some(p) => {
                let zones: Map<String, Value> =
                    p.options.iter().zip(&p.zones).map(|(id, z)| (id.to_string(), json!(z))).collect();
                json!({"player": p.player, "source": p.source, "options": p.options, "zones": zones})
            }
        }
    }

    pub fn to_dict(&self) -> Value {
        let mut d = self.dict_base();
        d["entities"] = Value::Object(self.entities.iter().map(|e| (e.id.to_string(), e.snapshot())).collect());
        d
    }

    /// `to_dict` without "entities".
    pub(crate) fn dict_base(&self) -> Value {
        let mut d = json!({"turn": self.turn, "current": self.current, "phase": self.phase,
            "rng": (self.rng.state as i64).to_string(), "next_id": self.next_id, "next_order": self.next_order,
            "game_over": self.game_over, "winner": self.winner});
        d["pending"] = self.pending_value();
        if !self.pending_next.is_empty() {
            d["pending_next"] = json!(self.pending_next.iter().map(|p| json!({"player": p.player, "source": p.source,
                "options": p.options})).collect::<Vec<_>>());
        }
        d["players"] = Value::Array(self.players.iter().map(|p| p.snapshot()).collect());
        d
    }

    pub fn state_hash(&self) -> String {
        hex(&Sha256::digest(json::stringify(&self.to_dict()).as_bytes()))
    }

    pub fn card(&self, id: Id) -> &'static crate::ruleset::Card {
        self.e(id).card
    }

    /// The opponent of me's controller.
    pub fn foe(&self, me: Id) -> usize {
        1 - self.ctrl(me)
    }

    pub fn add_tag_int(&mut self, e: Id, tag: Str, n: i64) {
        let v = self.e(e).tag(&tag) + n;
        self.em(e).set_tag(tag, v);
    }

    /// DIED_POS of a dead minion (-1 if it has none).
    pub fn died_pos(&self, e: Id) -> i64 {
        self.e(e).tags.get(self.n().died_pos).map_or(-1, V::int)
    }
}

pub fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{:02x}", x)).collect()
}

/// A cost mod that holds on any turn until a card it applies to is played (`lasting = true`: Dragon Consort).
pub(crate) fn lasting(m: &Obj) -> bool {
    vtruthy(m.get("lasting"))
}
