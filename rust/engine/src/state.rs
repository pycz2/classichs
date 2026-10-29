//! Match state, event queue, death phase, auras and the primitives that card
//! hooks use (engine/game_state.gd). Turns, actions and legality: game.rs.

use crate::hooks::{Base, HookFn, HookSet, TSpec, TrapHook};
use crate::entity::{int, truthy, Entity, Id, NONE};
use crate::json;
use crate::lua::LuaSlot;
use crate::player::Player;
use crate::rng::Rng;
use crate::ruleset::{Names, Ruleset};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::collections::VecDeque;
use std::sync::OnceLock;

/// An event: a JSON object ({"type": ..., ...}).
pub type Ev = Map<String, Value>;

#[derive(Clone, Copy)]
pub(crate) enum Trigger {
    On(HookFn),
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
    /// Entity id n is entities[n - 1]; entities are never removed.
    pub entities: Vec<Entity>,
    pub turn: i64,
    pub current: usize,
    pub phase: &'static str,
    pub pending: Option<Pending>,
    pub game_over: bool,
    pub winner: i64,
    pub event_log: Vec<Ev>,
    /// Full match history, never trimmed: [{"turn", "player", "action", "events"}].
    /// Entry 0 is {"action": {"type": "start"}} with the opening draws.
    pub history: Vec<Value>,
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
}

impl Game {
    pub(crate) fn blank(rs: &'static Ruleset, seed: i64) -> Game {
        Game { rs, rng: Rng::new(seed as u64), players: vec![], entities: vec![], turn: 0, current: 0,
            phase: "MULLIGAN", pending: None, game_over: false, winner: -1, event_log: vec![], history: vec![],
            queue: VecDeque::new(), next_id: 1, next_order: 1, source_card: "", source_id: NONE,
            start_decks: [vec![], vec![]], lua: LuaSlot::default(), script_error: OnceLock::new() }
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
        self.entities.push(Entity::new(id, self.rs.card(card_id), controller));
        self.next_id += 1;
        id
    }

    pub fn e(&self, id: Id) -> &Entity {
        &self.entities[(id - 1) as usize]
    }

    pub fn em(&mut self, id: Id) -> &mut Entity {
        &mut self.entities[(id - 1) as usize]
    }

    /// The entity with this id, if it exists.
    pub fn ent(&self, id: Id) -> Option<&Entity> {
        if id >= 1 { self.entities.get((id - 1) as usize) } else { None }
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

    pub fn minions(&self, p: usize) -> Vec<Id> {
        self.players[p].board.clone()
    }

    pub fn all_minions(&self) -> Vec<Id> {
        let mut v = self.minions(0);
        v.extend(self.minions(1));
        self.by_order(v)
    }

    pub fn chars(&self, p: usize) -> Vec<Id> {
        let mut v = vec![self.players[p].hero];
        v.extend(&self.players[p].board);
        v
    }

    pub fn all_chars(&self) -> Vec<Id> {
        let mut v = self.chars(0);
        v.extend(self.chars(1));
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
        self.players[self.ctrl(me)].board.iter().copied().filter(|&m| m != me).collect()
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
        out
    }

    /// All entities whose hooks can trigger: heroes, hero powers, weapons, minions, secrets.
    pub fn in_play(&self) -> Vec<Id> {
        let mut out = vec![];
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
        if e.silenced { self.rs.hooks("") } else { &e.card.hooks }
    }

    // --- events and resolution --------------------------------------------------

    /// Logs the event (with the card whose effect did it) and returns its index.
    pub fn log_event(&mut self, ev: Value) -> usize {
        let Value::Object(mut ev) = ev else { panic!("event must be an object") };
        if !self.source_card.is_empty() && !ev.contains_key("by") {
            ev.insert("by".into(), json!(self.source_card));
            ev.insert("by_id".into(), json!(self.source_id));
        }
        self.event_log.push(ev);
        self.event_log.len() - 1
    }

    /// An event of the current action.
    pub fn ev(&self, i: usize) -> &Ev {
        &self.event_log[i]
    }

    pub fn ev_i(&self, i: usize, key: &str) -> i64 {
        int(self.event_log[i].get(key))
    }

    pub fn ev_s(&self, i: usize, key: &str) -> &str {
        self.event_log[i].get(key).and_then(Value::as_str).unwrap_or("")
    }

    pub fn ev_b(&self, i: usize, key: &str) -> bool {
        truthy(self.event_log[i].get(key))
    }

    pub fn ev_set(&mut self, i: usize, key: &str, v: Value) {
        self.event_log[i].insert(key.into(), v);
    }

    /// Logs the event and queues every matching "on" trigger (card and enchantment hooks).
    pub fn emit(&mut self, ev: Value) -> usize {
        let i = self.log_event(ev);
        let ty = self.ev_s(i, "type").to_string();
        for e in self.in_play() {
            let h = self.hooks_of(e);
            if let Some(f) = h.on(&ty) {
                self.queue.push_back(QItem { f: Trigger::On(f), me: e, ev: Some(i), needs_in_play: true });
            }
            if let Some(s) = h.trap {
                if s.event == ty {
                    self.queue.push_back(QItem { f: Trigger::Trap(s), me: e, ev: Some(i), needs_in_play: true });
                }
            }
            for hooks in self.ench_hooks(e) {
                if let Some(f) = hooks.on(&ty) {
                    self.queue.push_back(QItem { f: Trigger::On(f), me: e, ev: Some(i), needs_in_play: true });
                }
            }
        }
        i
    }

    /// The hooks of e's enchantments, in order.
    fn ench_hooks(&self, e: Id) -> Vec<&'static HookSet> {
        let rs = self.rs;
        self.e(e).enchantments.iter().filter_map(|x| x.get("hooks").and_then(Value::as_str)).map(|h| rs.hooks(h)).collect()
    }

    /// Calls matching "now" hooks (card and enchantment) at once. Used for
    /// replacement effects (`now` hooks: "predamage").
    pub fn emit_now(&mut self, ev: &mut Ev) {
        let ty = ev.get("type").and_then(Value::as_str).unwrap_or("").to_string();
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
                let me = q.me;
                self.from(me, |g| match q.f {
                    Trigger::On(f) => g.fx_on(f, me, q.ev.unwrap()),
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
            self.update_auras();
            if !self.death_phase() {
                break;
            }
        }
        self.update_auras();
    }

    fn death_phase(&mut self) -> bool {
        let mut dead = vec![];
        let n = self.n();
        for p in &self.players {
            for &m in &p.board {
                let e = self.e(m);
                if e.health() <= 0 || truthy(e.tags.get(n.to_destroy)) {
                    dead.push(m);
                }
            }
            if let Some(w) = p.weapon {
                let e = self.e(w);
                if e.tag(n.durability) <= 0 || truthy(e.tags.get(n.to_destroy)) {
                    dead.push(w);
                }
            }
        }
        let dead = self.by_order(dead);
        for &d in &dead {
            let c = self.ctrl(d);
            if self.e(d).is_minion() {
                let pos = self.players[c].board.iter().position(|&x| x == d).map_or(-1, |i| i as i64);
                self.em(d).set_tag(n.died_pos, json!(pos));
                self.players[c].board.retain(|&x| x != d);
            } else {
                self.players[c].weapon = None;
            }
            self.em(d).zone = "GRAVEYARD";
        }
        for &d in &dead {
            if let Some(f) = self.hooks_of(d).on_death {
                self.queue.push_back(QItem { f: Trigger::OnDeath(f), me: d, ev: None, needs_in_play: false });
            }
            for hooks in self.ench_hooks(d) {
                if let Some(f) = hooks.on_death {
                    self.queue.push_back(QItem { f: Trigger::OnDeath(f), me: d, ev: None, needs_in_play: false });
                }
            }
            let e = self.e(d);
            let ev = json!({"type": "death", "entity": d, "player": e.controller, "card": e.card_id,
                "minion": e.is_minion()});
            self.emit(ev);
        }
        let mut heroes_dead = vec![];
        for p in &self.players {
            let h = self.e(p.hero);
            if h.health() <= 0 || truthy(h.tags.get(n.to_destroy)) {
                heroes_dead.push(p.index);
            }
        }
        if !heroes_dead.is_empty() {
            self.game_over = true;
            self.phase = "OVER";
            self.winner = if heroes_dead.len() == 2 { -1 } else { self.opponent(heroes_dead[0]) as i64 };
            self.queue.clear();
            self.log_event(json!({"type": "game_over", "winner": self.winner}));
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
        let all = self.in_play();
        let before: Vec<(i64, i64)> = all.iter().map(|&e| (self.e(e).max_health(), self.e(e).health())).collect();
        for &e in &all {
            self.em(e).aura = Default::default();
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
            self.em(e).fix_health(before[i].0, before[i].1);
        }
    }

    pub fn aura_add(&mut self, t: Id, atk: i64, hp: i64, tags: &[(&str, Value)]) {
        let src = self.source_card;
        let n = self.n();
        let a = &mut self.em(t).aura;
        a.atk += atk;
        a.hp += hp;
        if !src.is_empty() && (atk != 0 || hp != 0) {
            let was = a.src.get(src).cloned().unwrap_or(json!([0, 0]));
            a.src.insert(src.to_string(), json!([int(was.get(0)) + atk, int(was.get(1)) + hp]));
        }
        for (k, v) in tags {
            if *k == n.spell_power || *k == n.power_multiplier {
                let n = int(a.tags.get(*k)) + int(Some(v));
                a.tags.insert(k.to_string(), json!(n));
            } else {
                a.tags.insert(k.to_string(), v.clone());
            }
        }
    }

    // --- primitives -------------------------------------------------------------

    fn alive_in_play(&self, t: Id) -> bool {
        t != NONE && self.e(t).zone == "PLAY"
    }

    pub fn damage(&mut self, src: Id, t: Id, amount: i64) -> i64 {
        if !self.alive_in_play(t) || amount <= 0 {
            return 0;
        }
        let mut pre = json!({"type": "predamage", "source": src, "target": t, "amount": amount});
        self.emit_now(pre.as_object_mut().unwrap());
        let mut amount = int(pre.get("amount"));
        let n = self.n();
        if amount <= 0 || self.e(t).has(n.immune) {
            return 0;
        }
        if self.e(t).has(n.barrier) {
            self.em(t).erase_tag(n.barrier);
            self.log_event(json!({"type": "divine_shield_lost", "target": t}));
            return 0;
        }
        if self.e(t).is_champion() {
            let armor = self.e(t).tag(n.armor);
            let absorbed = armor.min(amount);
            self.em(t).set_tag(n.armor, json!(armor - absorbed));
            amount -= absorbed;
            if amount <= 0 {
                self.log_event(json!({"type": "armor_lost", "target": t, "amount": absorbed}));
                return 0;
            }
        }
        self.em(t).damage += amount;
        if src != NONE && self.e(src).is_minion() && self.e(src).has(n.stealth) {
            self.em(src).erase_tag(n.stealth);
        }
        let player = self.ctrl(t);
        self.emit(json!({"type": "damage", "source": src, "target": t, "amount": amount, "player": player}));
        amount
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
        self.emit(json!({"type": "heal", "source": src, "target": t, "amount": healed}));
        healed
    }

    pub fn destroy(&mut self, e: Id) {
        if self.alive_in_play(e) {
            let t = self.n().to_destroy;
            self.em(e).set_tag(t, json!(true));
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
        self.emit(json!({"type": "summon", "entity": e, "player": c, "card": card}));
        self.emit(json!({"type": "after_summon", "entity": e, "player": c, "card": card}));
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
                self.log_event(json!({"type": "fatigue", "player": p, "amount": f}));
                self.damage(NONE, self.players[p].hero, f);
                continue;
            };
            let card = self.e(e).card_id;
            if self.players[p].hand.len() >= self.rs.hand {
                self.em(e).zone = "GRAVEYARD";
                self.log_event(json!({"type": "burn", "player": p, "entity": e, "card": card}));
                continue;
            }
            self.em(e).zone = "HAND";
            self.players[p].hand.push(e);
            out.push(e);
            self.emit(json!({"type": "draw", "player": p, "entity": e, "card": card}));
        }
        out
    }

    /// Draws a specific card from p's deck (burns it if the hand is full).
    pub fn draw_entity(&mut self, p: usize, e: Id) {
        let pl = &mut self.players[p];
        let Some(i) = pl.deck.iter().position(|&x| x == e) else { return };
        pl.deck.remove(i);
        let card = self.e(e).card_id;
        if self.players[p].hand.len() >= self.rs.hand {
            self.em(e).zone = "GRAVEYARD";
            self.log_event(json!({"type": "burn", "player": p, "entity": e, "card": card}));
            return;
        }
        self.em(e).zone = "HAND";
        self.players[p].hand.push(e);
        self.emit(json!({"type": "draw", "player": p, "entity": e, "card": card}));
    }

    pub fn add_to_hand(&mut self, p: usize, card_id: &str) -> Id {
        if self.players[p].hand.len() >= self.rs.hand {
            return NONE;
        }
        let e = self.new_entity(card_id, p);
        self.em(e).zone = "HAND";
        self.players[p].hand.push(e);
        self.log_event(json!({"type": "add_to_hand", "player": p, "entity": e, "card": card_id}));
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
            self.emit(json!({"type": "discard", "player": p, "entity": e, "card": card}));
        }
    }

    pub fn buff(&mut self, e: Id, atk: i64, hp: i64, eot: bool) {
        let mut ench = json!({"atk": atk, "hp": hp, "eot": eot});
        if !self.source_card.is_empty() {
            ench["src"] = json!(self.source_card);
        }
        self.em(e).add_enchant(ench);
        self.log_event(json!({"type": "buff", "target": e, "atk": atk, "hp": hp}));
    }

    /// Sets Attack and/or Health (-1 keeps the value). Setting Health clears damage.
    pub fn set_stats(&mut self, e: Id, atk: i64, hp: i64) {
        let mut ench = Map::new();
        if atk >= 0 {
            ench.insert("set_atk".into(), json!(atk));
        }
        if hp >= 0 {
            ench.insert("set_hp".into(), json!(hp));
            self.em(e).damage = 0;
        }
        if !self.source_card.is_empty() {
            ench.insert("src".into(), json!(self.source_card));
        }
        self.em(e).enchantments.push(ench);
        self.log_event(json!({"type": "buff", "target": e, "set_atk": atk, "set_hp": hp}));
    }

    pub fn silence(&mut self, e: Id) {
        let tags = &self.rs.names.silenced;
        self.em(e).silence(tags);
        self.log_event(json!({"type": "silence", "target": e}));
    }

    pub fn freeze(&mut self, e: Id) {
        if !self.alive_in_play(e) {
            return;
        }
        let (cur, n) = (self.current, self.n());
        let x = self.em(e);
        x.set_tag(n.frozen, json!(true));
        if x.controller == cur {
            x.set_tag(n.frozen_this_turn, json!(true));
        }
        self.log_event(json!({"type": "freeze", "target": e}));
    }

    pub fn transform(&mut self, e: Id, card_id: &str) -> Id {
        let c = self.ctrl(e);
        let Some(i) = self.players[c].board.iter().position(|&x| x == e) else { return NONE };
        let n = self.new_entity(card_id, c);
        self.players[c].board[i] = n;
        let (order, t) = (self.e(e).play_order, self.n().exhausted);
        let ne = self.em(n);
        ne.zone = "PLAY";
        ne.play_order = order;
        ne.give_tag(t, false);
        self.em(e).zone = "SETASIDE";
        self.log_event(json!({"type": "transform", "from": e, "to": n, "card": card_id}));
        n
    }

    /// Returns a minion to its owner's hand as a fresh card (NONE if the hand is full).
    pub fn return_to_hand(&mut self, e: Id) -> Id {
        let c = self.ctrl(e);
        if !self.players[c].board.contains(&e) {
            return NONE;
        }
        self.players[c].board.retain(|&x| x != e);
        self.em(e).zone = "SETASIDE";
        let card = self.e(e).card_id;
        let n = self.add_to_hand(c, &card);
        self.log_event(json!({"type": "return_to_hand", "entity": e, "new": n}));
        n
    }

    pub fn take_control(&mut self, e: Id, p: usize) {
        let c = self.ctrl(e);
        if c == p || !self.players[c].board.contains(&e) {
            return;
        }
        self.players[c].board.retain(|&x| x != e);
        if self.players[p].board.len() >= self.rs.board {
            self.em(e).zone = "GRAVEYARD";
            self.log_event(json!({"type": "destroy", "target": e}));
            return;
        }
        self.em(e).controller = p;
        self.players[p].board.push(e);
        let n = self.n();
        let x = self.em(e);
        x.give_tag(n.exhausted, false);
        x.set_tag(n.attacks, json!(0));
        self.log_event(json!({"type": "take_control", "target": e, "player": p}));
    }

    pub fn equip(&mut self, p: usize, card_id: &str) -> Id {
        let w = self.new_entity(card_id, p);
        self.equip_entity(w)
    }

    pub fn equip_entity(&mut self, w: Id) -> Id {
        let c = self.ctrl(w);
        if let Some(old) = self.players[c].weapon {
            self.em(old).zone = "GRAVEYARD";
            self.log_event(json!({"type": "destroy", "target": old}));
        }
        self.players[c].weapon = Some(w);
        self.enter_play(w);
        let card = self.e(w).card_id;
        self.emit(json!({"type": "equip", "player": c, "entity": w, "card": card}));
        w
    }

    pub fn gain_armor(&mut self, p: usize, n: i64) {
        let (h, t) = (self.hero(p), self.n().armor);
        let a = self.e(h).tag(t);
        self.em(h).set_tag(t, json!(a + n));
        self.log_event(json!({"type": "armor", "player": p, "amount": n}));
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
        self.log_event(json!({"type": "mana", "player": p, "max": max, "mana": mana}));
    }

    /// POWER_MULTIPLIER (an aura tag on the champion, a count) doubles damage and
    /// healing of spells and powers only, once per count.
    fn power_multiplier(&self, me: Id) -> i64 {
        let k = self.e(me).kind();
        if k != "SPELL" && k != "POWER" {
            return 1;
        }
        1 << int(self.e(self.hero(self.ctrl(me))).aura.tags.get(self.n().power_multiplier)).clamp(0, 20)
    }

    pub fn spell_dmg(&self, me: Id, n: i64) -> i64 {
        let t = self.n().spell_power;
        let sp: i64 = self.players[self.ctrl(me)].board.iter().map(|&m| self.e(m).spell_power(t)).sum();
        (n + sp) * self.power_multiplier(me)
    }

    pub fn hp_dmg(&self, me: Id, n: i64) -> i64 {
        n * self.power_multiplier(me)
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
        self.players[p].hero = h;
        self.log_event(json!({"type": "hero_replaced", "player": p, "entity": h, "card": card_id}));
        h
    }

    /// Replaces p's hero power with a fresh, unused one.
    pub fn set_hero_power(&mut self, p: usize, card_id: &str) -> Id {
        let old = self.players[p].hero_power;
        self.em(old).zone = "SETASIDE";
        let hp = self.new_entity(card_id, p);
        self.enter_play(hp);
        self.players[p].hero_power = hp;
        self.log_event(json!({"type": "hero_power_changed", "player": p, "entity": hp, "card": card_id}));
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

    pub fn trap_ready(&self, me: Id) -> bool {
        let e = self.e(me);
        e.zone == self.n().trap && self.current != e.controller
    }

    pub fn reveal(&mut self, me: Id) {
        let c = self.ctrl(me);
        self.players[c].secrets.retain(|&x| x != me);
        self.em(me).zone = "GRAVEYARD";
        let card = self.e(me).card_id;
        self.emit(json!({"type": "secret_revealed", "entity": me, "player": c, "card": card}));
    }

    pub fn request_choice(&mut self, me: Id, options: Vec<Id>) {
        let zones = options.iter().map(|&id| self.e(id).zone).collect();
        let player = self.ctrl(me);
        self.pending = Some(Pending { player, source: me, options: options.clone(), zones });
        self.log_event(json!({"type": "choice", "player": player, "options": options}));
    }

    pub fn add_cost_mod(&mut self, p: usize, mut m: Value) {
        m["turn"] = json!(self.turn);
        let Value::Object(m) = m else { unreachable!() };
        self.players[p].cost_mods.push(m);
    }

    fn mod_applies(&self, m: &Map<String, Value>, e: Id) -> bool {
        let x = self.e(e);
        match m.get("kind").and_then(Value::as_str).unwrap_or("") {
            "any" => true,
            "minion" => x.is_minion(),
            "spell" => x.kind() == "SPELL",
            "secret" | "trap" => x.card.trap,
            _ => false,
        }
    }

    pub fn cost(&self, e: Id) -> i64 {
        let x = self.e(e);
        let mut c = x.card.cost;
        if let Some(f) = x.card.hooks.cost_mod {
            c += self.fx_cost_mod(f, e);
        }
        for ench in &x.enchantments {
            c += int(ench.get("cost"));
        }
        for src in self.in_play() {
            if let Some(f) = self.hooks_of(src).cost_aura {
                if self.e(src).zone == "PLAY" {
                    c = self.fx_cost_aura(f, src, e, c);
                }
            }
        }
        for m in &self.players[x.controller].cost_mods {
            if int(m.get("turn")) == self.turn && self.mod_applies(m, e) {
                c = if m.contains_key("set") { int(m.get("set")) } else { c + int(m.get("delta")) };
            }
        }
        c.max(0)
    }

    /// Removes "until": "use" mods that applied to e (called when e is played).
    pub fn consume_cost_mods(&mut self, e: Id) {
        let c = self.ctrl(e);
        let mods = std::mem::take(&mut self.players[c].cost_mods);
        let keep = mods
            .into_iter()
            .filter(|m| {
                !(m.get("until").and_then(Value::as_str) == Some("use") && int(m.get("turn")) == self.turn && self.mod_applies(m, e))
            })
            .collect();
        self.players[c].cost_mods = keep;
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
            turn: self.turn, current: self.current, phase: self.phase, pending: self.pending.clone(),
            game_over: self.game_over, winner: self.winner, event_log: vec![], history: vec![], queue: VecDeque::new(),
            next_id: self.next_id, next_order: self.next_order, source_card: "", source_id: NONE,
            start_decks: [vec![], vec![]], lua: self.lua.share(), script_error: self.script_error.clone() }
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
        let ents: Map<String, Value> = self.entities.iter().map(|e| (e.id.to_string(), e.snapshot())).collect();
        let ps: Vec<Value> = self.players.iter().map(|p| p.snapshot()).collect();
        json!({"turn": self.turn, "current": self.current, "phase": self.phase,
            "rng": (self.rng.state as i64).to_string(), "next_id": self.next_id, "next_order": self.next_order,
            "pending": self.pending_value(), "game_over": self.game_over, "winner": self.winner,
            "entities": ents, "players": ps})
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

    pub fn add_tag_int(&mut self, e: Id, tag: &str, n: i64) {
        let v = self.e(e).tag(tag) + n;
        self.em(e).set_tag(tag, json!(v));
    }

    /// DIED_POS of a dead minion (-1 if it has none).
    pub fn died_pos(&self, e: Id) -> i64 {
        match self.e(e).tags.get(self.n().died_pos) {
            Some(v) => int(Some(v)),
            None => -1,
        }
    }
}

pub fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{:02x}", x)).collect()
}
