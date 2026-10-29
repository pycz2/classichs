//! Match setup, turns, actions and legality (engine/game.gd).

use crate::hooks::TSpec;
use crate::entity::{vint, vtruthy, Id, NONE};
use crate::json;
use crate::rng::Rng;
use crate::ruleset::{self, Ruleset};
use crate::state::Game;
use serde_json::{json, Map, Value};

pub use crate::state::Ev;

/// An action: {"type": ..., "player": ..., ...} with whole numbers as ints.
pub type Action = Map<String, Value>;

/// The result of `apply`.
#[derive(Debug, Clone)]
pub struct Applied {
    pub ok: bool,
    pub error: String,
    pub events: Vec<Ev>,
}

/// splitmix64(seed + (p + 1) * golden): the seed of player p's mulligan shuffle.
/// Portable (engine/game.gd mulligan_seed does the same with GDScript ints).
pub fn mulligan_seed(seed: u64, p: usize) -> u64 {
    let mut z = seed.wrapping_add((p as u64 + 1).wrapping_mul(0x9E3779B97F4A7C15));
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
    z ^ (z >> 31)
}

/// A legal action, typed (`legal_actions` gives them as JSON objects).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Act {
    Mulligan { player: i64, replace: Vec<Id> },
    EndTurn { player: i64 },
    Concede { player: i64 },
    Play { player: i64, entity: Id, target: Id, pos: i64, choice: i64 },
    HeroPower { player: i64, target: Id },
    Attack { player: i64, attacker: Id, defender: Id },
    Choose { player: i64, option: Id },
}

impl Act {
    pub fn player(&self) -> i64 {
        match *self {
            Act::Mulligan { player, .. }
            | Act::EndTurn { player }
            | Act::Concede { player }
            | Act::Play { player, .. }
            | Act::HeroPower { player, .. }
            | Act::Attack { player, .. }
            | Act::Choose { player, .. } => player,
        }
    }

    pub fn to_map(&self) -> Action {
        let v = match self {
            Act::Mulligan { player, replace } => json!({"type": "mulligan", "player": player, "replace": replace}),
            Act::EndTurn { player } => json!({"type": "end_turn", "player": player}),
            Act::Concede { player } => json!({"type": "concede", "player": player}),
            Act::Play { player, entity, target, pos, choice } => {
                json!({"type": "play", "player": player, "entity": entity, "target": target, "pos": pos, "choice": choice})
            }
            Act::HeroPower { player, target } => json!({"type": "hero_power", "player": player, "target": target}),
            Act::Attack { player, attacker, defender } => {
                json!({"type": "attack", "player": player, "attacker": attacker, "defender": defender})
            }
            Act::Choose { player, option } => json!({"type": "choose", "player": player, "option": option}),
        };
        match v {
            Value::Object(m) => m,
            _ => unreachable!(),
        }
    }

    /// The action a normalized JSON action is, if it has exactly the fields of one.
    pub fn from_map(a: &Action) -> Option<Act> {
        let i = |k: &str| a.get(k).and_then(Value::as_i64);
        let (n, player) = (a.len(), i("player")?);
        Some(match a.get("type")?.as_str()? {
            "mulligan" if n == 3 => {
                let replace = a.get("replace")?.as_array()?.iter().map(Value::as_i64).collect::<Option<Vec<Id>>>()?;
                Act::Mulligan { player, replace }
            }
            "end_turn" if n == 2 => Act::EndTurn { player },
            "concede" if n == 2 => Act::Concede { player },
            "play" if n == 6 => Act::Play { player, entity: i("entity")?, target: i("target")?, pos: i("pos")?, choice: i("choice")? },
            "hero_power" if n == 3 => Act::HeroPower { player, target: i("target")? },
            "attack" if n == 4 => Act::Attack { player, attacker: i("attacker")?, defender: i("defender")? },
            "choose" if n == 3 => Act::Choose { player, option: i("option")? },
            _ => return None,
        })
    }
}

impl Game {
    /// A new match of the built-in ruleset: decks are card id lists (the last card is
    /// the top before the shuffle). first = -1 lets the RNG choose; deal=false skips
    /// the opening draws.
    pub fn new(hero0: &str, deck0: &[String], hero1: &str, deck1: &[String], seed: i64, first: i64, deal: bool) -> Game {
        Game::new_in(ruleset::classic(), hero0, deck0, hero1, deck1, seed, first, deal)
    }

    /// A new match of a ruleset (`Game::new` plays the built-in Classic one).
    #[allow(clippy::too_many_arguments)]
    pub fn new_in(rs: &'static Ruleset, hero0: &str, deck0: &[String], hero1: &str, deck1: &[String], seed: i64, first: i64,
        deal: bool) -> Game {
        let mut g = Game::blank(rs, seed);
        g.start_decks = [deck0.to_vec(), deck1.to_vec()];
        g.setup_players(hero0, hero1);
        for (i, deck) in [deck0, deck1].into_iter().enumerate() {
            for card_id in deck {
                let e = g.new_entity(card_id, i);
                g.em(e).zone = "DECK";
                g.players[i].deck.push(e);
            }
            let mut d = std::mem::take(&mut g.players[i].deck);
            g.shuffle_ids(&mut d);
            g.players[i].deck = d;
        }
        g.current = if first >= 0 { first as usize } else { g.rng.randi_range(0, 1) as usize };
        if deal {
            let [a, b] = rs.start_hand;
            g.draw(g.current, a);
            g.draw(g.opponent(g.current), b);
        }
        let events: Vec<Value> = std::mem::take(&mut g.event_log).into_iter().map(Value::Object).collect();
        g.history.push(json!({"turn": 0, "player": g.current, "action": {"type": "start"}, "events": events}));
        g
    }

    // --- apply ------------------------------------------------------------------

    /// Applies one action. Illegal actions change nothing.
    pub fn apply(&mut self, action: &Value) -> Applied {
        let a = normalize(action);
        if self.script_error.get().is_some() && !self.game_over {
            self.event_log.clear();
            self.end_by_script_error();
            let events = std::mem::take(&mut self.event_log);
            let ev_values: Vec<Value> = events.iter().cloned().map(Value::Object).collect();
            self.history.push(entry(self.turn, json!(self.current), a, ev_values));
            return Applied { ok: true, error: String::new(), events };
        }
        // the whole legal list even for a malformed action: its read-only hooks may fail (a script error)
        let act = if a.is_empty() { None } else { Some(self.legal()).and_then(|l| Act::from_map(&a).filter(|x| l.contains(x))) };
        let Some(act) = act else {
            return Applied { ok: false, error: format!("illegal action {}", json::stringify(&Value::Object(a))), events: vec![] };
        };
        let who = self.current;
        self.run(act);
        let events = self.event_log.clone();
        let ev_values: Vec<Value> = events.iter().cloned().map(Value::Object).collect();
        let player = a.get("player").cloned().unwrap_or(json!(who));
        self.history.push(entry(self.turn, player, a, ev_values));
        Applied { ok: true, error: String::new(), events }
    }

    /// `apply` of an action known to be legal here (one of `legal()` of this very state):
    /// no legality check, no history, no events for a caller (the bot's look-ahead copies).
    pub(crate) fn apply_legal(&mut self, act: Act) -> bool {
        if self.script_error.get().is_some() {
            if self.game_over {
                return false;
            }
            self.event_log.clear();
            self.end_by_script_error();
            return true;
        }
        self.run(act);
        true
    }

    /// Runs a legal action (one of `legal()` of this state).
    pub(crate) fn run(&mut self, act: Act) {
        self.event_log.clear();
        match act {
            Act::Mulligan { player, replace } => self.do_mulligan(player as usize, replace),
            Act::EndTurn { .. } => self.end_turn(),
            Act::Concede { player } => self.concede(player as usize),
            Act::Play { entity, target, pos, choice, .. } => self.do_play(entity, target, pos, choice),
            Act::Attack { attacker, defender, .. } => self.do_attack(attacker, defender),
            Act::HeroPower { target, .. } => self.do_hero_power(target),
            Act::Choose { option, .. } => self.do_choose(option),
        }
        self.resolve();
        self.prune_pending();
    }

    pub fn legal_actions(&self) -> Vec<Action> {
        self.legal().iter().map(Act::to_map).collect()
    }

    /// The legal actions, typed, in the order `legal_actions` gives them.
    pub fn legal(&self) -> Vec<Act> {
        let mut out = vec![];
        if self.game_over || self.script_error.get().is_some() {
            return out;
        }
        if self.phase == "MULLIGAN" {
            for p in &self.players {
                if !p.mulliganed {
                    for ids in subsets(&p.hand) {
                        out.push(Act::Mulligan { player: p.index as i64, replace: ids });
                    }
                }
            }
        } else {
            out.push(Act::EndTurn { player: self.current as i64 });
            self.legal_play_actions(&mut out);
        }
        for p in 0..2 {
            out.push(Act::Concede { player: p });
        }
        out
    }

    // --- mulligan and turns -----------------------------------------------------

    /// Records p's choice; both mulligans run in a fixed order once both have
    /// arrived. A player's mulligan is carried out at once; the game starts when
    /// both have chosen.
    fn do_mulligan(&mut self, p: usize, replace: Vec<Id>) {
        self.players[p].mulliganed = true;
        self.players[p].mulligan_replace = replace.clone();
        self.log_event(json!({"type": "mulligan_chosen", "player": p}));
        self.run_mulligan(p, &replace);
        if self.players[0].mulliganed && self.players[1].mulliganed {
            self.finish_mulligan();
        }
    }

    /// New cards take the places of the replaced ones; the old ones are shuffled
    /// back with the player's own random stream.
    fn run_mulligan(&mut self, p: usize, old: &[Id]) {
        let fresh = self.draw(p, old.len() as i64);
        let mut hand = vec![];
        let mut k = 0;
        for &e in &self.players[p].hand {
            if old.contains(&e) {
                if k < fresh.len() {
                    hand.push(fresh[k]);
                    k += 1;
                }
            } else if !fresh.contains(&e) {
                hand.push(e);
            }
        }
        self.players[p].hand = hand;
        for &e in old {
            self.em(e).zone = "DECK";
            self.players[p].deck.push(e);
        }
        let mut own = Rng::new(mulligan_seed(self.rng.seed(), p));
        Game::shuffle(&mut self.players[p].deck, &mut own);
        self.log_event(json!({"type": "mulligan", "player": p, "count": old.len()}));
    }

    fn finish_mulligan(&mut self) {
        if let Some(coin) = &self.rs.coin {
            self.add_to_hand(self.opponent(self.current), coin);
        }
        self.phase = "PLAY";
        self.start_turn();
    }

    fn start_turn(&mut self) {
        let cur = self.current;
        self.turn += 1;
        let (max, n) = (self.rs.max_mana, self.n());
        let p = &mut self.players[cur];
        p.max_mana = max.min(p.max_mana + 1);
        p.mana_locked = p.mana_lock_owed;
        p.mana_lock_owed = 0;
        p.mana = 0.max(p.max_mana - p.mana_locked);
        p.cards_played_this_turn = 0;
        p.minions_played_this_turn = 0;
        let hp = p.hero_power;
        self.em(hp).erase_tag(n.used);
        for c in self.chars(cur) {
            let e = self.em(c);
            e.erase_tag(n.exhausted);
            e.set_tag(n.attacks, 0i64);
        }
        self.emit(json!({"type": "turn_start", "player": cur, "turn": self.turn}));
        self.resolve();
        if !self.game_over && (self.turn > 1 || self.rs.first_player_draws) {
            self.draw(cur, 1);
        }
    }

    fn end_turn(&mut self) {
        let cur = self.current;
        self.emit(json!({"type": "turn_end", "player": cur}));
        self.resolve();
        if self.game_over {
            return;
        }
        for e in self.in_play() {
            self.em(e).remove_eot();
        }
        let turn = self.turn;
        for pl in &mut self.players {
            pl.cost_mods.retain(|m| vint(m.get("turn")) > turn);
        }
        let n = self.n();
        for c in self.chars(cur) {
            let e = self.em(c);
            if e.has(n.frozen) && !(vtruthy(e.tags.get(n.frozen_this_turn)) && e.tag(n.attacks) > 0) {
                e.erase_tag(n.frozen);
            }
            e.erase_tag(n.frozen_this_turn);
        }
        self.log_event(json!({"type": "turn_end", "player": cur}));
        self.current = self.opponent(cur);
        self.start_turn();
    }

    fn concede(&mut self, p: usize) {
        self.game_over = true;
        self.phase = "OVER";
        self.winner = self.opponent(p) as i64;
        self.log_event(json!({"type": "game_over", "winner": self.winner}));
    }

    fn legal_play_actions(&self, out: &mut Vec<Act>) {
        if let Some(p) = &self.pending {
            out.clear();
            for id in self.pending_options() {
                out.push(Act::Choose { player: p.player as i64, option: id });
            }
            return;
        }
        let cur = self.current;
        let player = cur as i64;
        let p = &self.players[cur];
        for &e in &p.hand {
            if self.cost(e) > p.mana || !self.can_play(e) {
                continue;
            }
            let choices: &[i64] = if self.e(e).card.hooks.choice.is_some() { &[0, 1] } else { &[-1] };
            for &choice in choices {
                for t in self.play_targets(e, choice) {
                    for pos in self.positions(e) {
                        out.push(Act::Play { player, entity: e, target: t, pos, choice });
                    }
                }
            }
        }
        let hp = p.hero_power;
        let hpe = self.e(hp);
        let n = self.n();
        if !hpe.has(n.used) && !hpe.has(n.locked) && self.cost(hp) <= p.mana {
            let hh = &hpe.card.hooks;
            if hh.power.is_some() && hh.can_play.is_none_or(|f| self.fx_can_play(f, hp)) {
                for t in self.spec_targets(hp, hh.target, true, false) {
                    out.push(Act::HeroPower { player, target: t });
                }
            }
        }
        for a in self.chars(cur) {
            if self.can_attack(a) {
                for d in self.defenders(a) {
                    out.push(Act::Attack { player, attacker: a, defender: d });
                }
            }
        }
    }

    fn can_play(&self, e: Id) -> bool {
        let x = self.e(e);
        let p = &self.players[x.controller];
        if x.is_minion() && p.board.len() >= self.rs.board {
            return false;
        }
        if x.card.trap && p.secrets.iter().any(|&s| self.e(s).card_id == x.card_id) {
            return false;
        }
        x.card.hooks.can_play.is_none_or(|f| self.fx_can_play(f, e))
    }

    pub fn combo_active(&self, e: Id) -> bool {
        self.players[self.ctrl(e)].cards_played_this_turn > 0
    }

    /// Target ids for playing e with the given choice. [-1] means "no target";
    /// an empty list means e cannot be played.
    fn play_targets(&self, e: Id, choice: i64) -> Vec<Id> {
        let is_spell = self.e(e).kind() == "SPELL";
        self.spec_targets(e, self.target_spec(e, choice, self.combo_active(e)), is_spell, !is_spell)
    }

    /// The target spec that applies when e is played with this choice and combo state.
    pub fn target_spec(&self, e: Id, choice: i64, combo: bool) -> Option<TSpec> {
        let h = &self.e(e).card.hooks;
        if h.combo_target.is_some() {
            return if combo { h.combo_target } else { None };
        }
        if choice >= 0 {
            return self.rs.hooks(h.choice.unwrap()[choice as usize]).target;
        }
        h.target
    }

    fn spec_targets(&self, e: Id, spec: Option<TSpec>, is_spell: bool, optional: bool) -> Vec<Id> {
        let Some(spec) = spec else { return vec![NONE] };
        let ids = self.targets(e, &spec, is_spell);
        if ids.is_empty() && optional {
            return vec![NONE];
        }
        ids
    }

    fn positions(&self, e: Id) -> Vec<i64> {
        let x = self.e(e);
        if !x.is_minion() {
            return vec![-1];
        }
        (0..=self.players[x.controller].board.len() as i64).collect()
    }

    fn can_attack(&self, a: Id) -> bool {
        let (x, n) = (self.e(a), self.n());
        if self.attack_value(a) <= 0 || x.has(n.frozen) || x.has(n.cant_attack) {
            return false;
        }
        if x.is_minion() && x.has(n.exhausted) && !x.has(n.haste) {
            return false;
        }
        let weapon_wf = x.is_champion() && self.players[x.controller].weapon.is_some_and(|w| self.e(w).has(n.double_attack));
        let limit = if x.has(n.double_attack) || weapon_wf { 2 } else { 1 };
        x.tag(n.attacks) < limit
    }

    fn defenders(&self, a: Id) -> Vec<Id> {
        let mut all = vec![];
        let mut taunts = vec![];
        let foe = self.opponent(self.ctrl(a));
        let n = self.n();
        for t in self.chars(foe) {
            let te = self.e(t);
            if te.has(n.stealth) {
                continue;
            }
            if te.is_champion() && te.has(n.guarded) && !self.players[foe].board.is_empty() {
                continue; // GUARDED (a tutorial boss): minions first
            }
            all.push(t);
            if te.is_minion() && te.has(n.guard) {
                taunts.push(t);
            }
        }
        if taunts.is_empty() { all } else { taunts }
    }

    // --- play -------------------------------------------------------------------

    fn do_play(&mut self, e: Id, t: Id, pos: i64, choice: i64) {
        let c = self.ctrl(e);
        let cost = self.cost(e);
        self.players[c].mana -= cost;
        self.consume_cost_mods(e);
        self.players[c].hand.retain(|&x| x != e);
        let combo = self.combo_active(e);
        self.players[c].cards_played_this_turn += 1;
        self.players[c].mana_lock_owed += self.e(e).card.mana_lock;
        match self.e(e).kind() {
            "MINION" => self.play_minion(e, t, pos, choice, combo),
            "SPELL" => self.play_spell(e, t, choice, combo),
            "WEAPON" => self.play_weapon(e, t, combo),
            _ => {}
        }
    }

    fn run_effect(&mut self, e: Id, key: &str, t: Id, choice: i64, combo: bool) {
        let h = &self.e(e).card.hooks;
        if t == NONE && self.target_spec(e, choice, combo).is_some() {
            return; // targeted effect with no target (none was valid, or it left play)
        }
        let f = if choice >= 0 {
            self.rs.hooks(h.choice.unwrap()[choice as usize]).effect
        } else if combo && h.combo.is_some() {
            h.combo
        } else if key == "on_play" {
            h.on_play
        } else {
            h.spell
        };
        if let Some(f) = f {
            self.from(e, |g| g.fx_effect(f, e, t));
        }
    }

    fn play_minion(&mut self, e: Id, mut t: Id, pos: i64, choice: i64, combo: bool) {
        let c = self.ctrl(e);
        let card = self.e(e).card_id;
        self.players[c].minions_played_this_turn += 1;
        self.place_on_board(e, pos);
        let ex = self.n().exhausted;
        self.em(e).give_tag(ex, false);
        self.emit(json!({"type": "play", "entity": e, "player": c, "kind": "minion", "target": t, "card": card}));
        self.emit(json!({"type": "summon", "entity": e, "player": c, "card": card}));
        self.resolve();
        if self.game_over || self.e(e).zone != "PLAY" {
            return;
        }
        if t != NONE && self.e(t).zone != "PLAY" {
            t = NONE;
        }
        self.run_effect(e, "on_play", t, choice, combo);
        self.resolve();
        if self.game_over || self.e(e).zone != "PLAY" {
            return;
        }
        let c = self.ctrl(e);
        self.emit(json!({"type": "after_summon", "entity": e, "player": c, "card": card, "played": true}));
    }

    fn play_spell(&mut self, e: Id, t: Id, choice: i64, combo: bool) {
        let c = self.ctrl(e);
        let card = self.e(e).card_id;
        let is_trap = self.e(e).card.trap;
        self.em(e).zone = "SETASIDE";
        let ev = self.emit(json!({"type": "play", "entity": e, "player": c, "kind": "spell", "secret": is_trap,
            "target": t, "card": card, "countered": false}));
        self.resolve();
        if self.game_over {
            return;
        }
        let countered = self.ev_b(ev, "countered");
        if is_trap {
            if countered {
                self.em(e).zone = "GRAVEYARD";
            } else {
                self.players[c].secrets.push(e);
                self.enter_play(e);
                self.em(e).zone = self.rs.names.trap;
            }
            self.emit(json!({"type": "after_spell", "entity": e, "player": c, "card": card}));
            return;
        }
        if !countered {
            let nt = self.ev_i(ev, "target");
            let nt = if nt >= 0 { nt } else { NONE };
            if nt == NONE || self.e(nt).zone == "PLAY" {
                self.run_effect(e, "spell", nt, choice, combo);
                self.resolve();
            }
        }
        self.em(e).zone = "GRAVEYARD";
        if !self.game_over {
            self.emit(json!({"type": "after_spell", "entity": e, "player": c, "card": card}));
        }
    }

    fn play_weapon(&mut self, e: Id, t: Id, combo: bool) {
        let c = self.ctrl(e);
        let card = self.e(e).card_id;
        self.emit(json!({"type": "play", "entity": e, "player": c, "kind": "weapon", "target": t, "card": card}));
        self.resolve();
        if self.game_over {
            return;
        }
        self.run_effect(e, "on_play", t, -1, combo);
        self.resolve();
        if !self.game_over {
            self.equip_entity(e);
        }
    }

    // --- attack -----------------------------------------------------------------

    fn do_attack(&mut self, a: Id, d: Id) {
        let names = self.n();
        let n = self.e(a).tag(names.attacks) + 1;
        self.em(a).set_tag(names.attacks, n);
        self.em(a).erase_tag(names.stealth);
        let c = self.ctrl(a);
        let ev = self.emit(json!({"type": "attack", "attacker": a, "defender": d, "player": c}));
        self.resolve();
        if self.game_over || self.e(a).zone != "PLAY" || self.ctrl(a) != self.current {
            return;
        }
        let d = self.ev_i(ev, "defender");
        if self.ent(d).is_none_or(|x| x.zone != "PLAY") {
            return;
        }
        let weapon = if self.e(a).is_champion() { self.players[self.ctrl(a)].weapon } else { None };
        let immune = weapon.is_some_and(|w| self.e(w).card.hooks.immune_while_attacking);
        if immune {
            self.em(a).give_tag(names.immune, false);
        }
        let a_dmg = self.attack_value(a);
        let d_dmg = self.attack_value(d);
        self.damage(a, d, a_dmg);
        self.damage(d, a, d_dmg);
        if immune {
            self.em(a).erase_tag(names.immune);
        }
        if let Some(w) = weapon {
            if self.e(w).zone == "PLAY" {
                let lose = match self.e(w).card.hooks.durability_on_attack {
                    Some(f) => self.fx_dur(f, w, d),
                    None => true,
                };
                if lose {
                    let dur = self.e(w).tag(names.durability) - 1;
                    self.em(w).set_tag(names.durability, dur);
                }
            }
        }
        let c = self.ctrl(a);
        self.emit(json!({"type": "after_attack", "attacker": a, "defender": d, "player": c}));
    }

    // --- hero power and choice --------------------------------------------------

    fn do_hero_power(&mut self, t: Id) {
        let cur = self.current;
        let hp = self.players[cur].hero_power;
        let cost = self.cost(hp);
        self.players[cur].mana -= cost;
        let used = self.n().used;
        self.em(hp).give_tag(used, false);
        if let Some(f) = self.e(hp).card.hooks.power {
            self.from(hp, |g| g.fx_effect(f, hp, t));
        }
        self.emit(json!({"type": "hero_power", "player": cur, "entity": hp, "target": t}));
    }

    /// Offered options that are still in the zone they were offered from.
    pub fn pending_options(&self) -> Vec<Id> {
        let Some(p) = &self.pending else { return vec![] };
        p.options.iter().zip(&p.zones).filter(|(&id, &z)| self.e(id).zone == z).map(|(&id, _)| id).collect()
    }

    fn do_choose(&mut self, option: Id) {
        let src = self.pending.as_ref().unwrap().source;
        let still = self.pending_options();
        self.pending = None;
        if let Some(f) = self.e(src).card.hooks.on_choose {
            self.from(src, |g| g.fx_choose(f, src, option, still));
        }
    }

    /// A choice whose options all left their zone (drawn by a trigger, say) is dropped.
    fn prune_pending(&mut self) {
        if let Some(p) = &self.pending {
            if self.pending_options().is_empty() {
                let player = p.player;
                self.log_event(json!({"type": "choice_cancelled", "player": player}));
                self.pending = None;
            }
        }
    }
}

/// A history entry ({"turn", "player", "action", "events"}).
fn entry(turn: i64, player: Value, action: Action, events: Vec<Value>) -> Value {
    let mut m = Map::new();
    m.insert("action".into(), Value::Object(action));
    m.insert("events".into(), Value::Array(events));
    m.insert("player".into(), player);
    m.insert("turn".into(), json!(turn));
    Value::Object(m)
}

fn subsets(ids: &[Id]) -> Vec<Vec<Id>> {
    (0..1u32 << ids.len())
        .map(|mask| {
            let mut s: Vec<Id> = (0..ids.len()).filter(|i| mask & (1 << i) != 0).map(|i| ids[i]).collect();
            s.sort();
            s
        })
        .collect()
}

/// int for whole numbers (JSON may give floats), None otherwise.
fn as_int(v: &Value) -> Option<i64> {
    let n = v.as_number()?;
    if let Some(i) = n.as_i64() {
        return Some(i);
    }
    let f = n.as_f64()?;
    (f == f.floor()).then_some(f as i64)
}

/// Converts floats to ints and sorts mulligan ids, so equality checks work.
/// Returns {} for malformed input (it comes from the network: never trust it).
pub fn normalize(action: &Value) -> Action {
    let Some(m) = action.as_object() else { return Action::new() };
    let mut a = Action::new();
    for (k, v) in m {
        let v = match k.as_str() {
            "type" => match v {
                Value::String(_) => v.clone(),
                _ => return Action::new(),
            },
            "replace" => {
                let Some(arr) = v.as_array() else { return Action::new() };
                let mut ids = vec![];
                for x in arr {
                    match as_int(x) {
                        Some(n) => ids.push(n),
                        None => return Action::new(),
                    }
                }
                ids.sort();
                json!(ids)
            }
            _ => match as_int(v) {
                Some(n) => json!(n),
                None => return Action::new(),
            },
        };
        a.insert(k.clone(), v);
    }
    if a.contains_key("type") && a.contains_key("player") { a } else { Action::new() }
}

#[cfg(test)]
mod tests {
    /// Values printed by Godot 4.7.2 for Game.mulligan_seed.
    #[test]
    fn mulligan_seed_matches_gdscript() {
        assert_eq!(super::mulligan_seed(0, 0) as i64, -2152535657050944081);
        assert_eq!(super::mulligan_seed(0, 1) as i64, 7960286522194355700);
        assert_eq!(super::mulligan_seed(-5i64 as u64, 1) as i64, -8161798454662654712);
        assert_eq!(super::mulligan_seed(i64::MIN as u64, 0) as i64, 5196802822362493915);
    }
}
