//! Match setup, turns, actions and legality (engine/game.gd).

use crate::cards;
use crate::entity::{int, truthy, Id, NONE};
use crate::json;
use crate::rng::Rng;
use crate::state::{Game, MAX_BOARD, MAX_MANA};
use serde_json::{json, Map, Value};

pub use crate::state::Ev;

pub const COIN: &str = "GAME_005";

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

fn obj(v: Value) -> Action {
    match v {
        Value::Object(m) => m,
        _ => unreachable!(),
    }
}

impl Game {
    /// A new match: decks are card id lists (the last card is the top before the
    /// shuffle). first = -1 lets the RNG choose; deal=false skips the opening draws.
    pub fn new(hero0: &str, deck0: &[String], hero1: &str, deck1: &[String], seed: i64, first: i64, deal: bool) -> Game {
        let mut g = Game::blank(seed);
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
            g.draw(g.current, 3);
            g.draw(g.opponent(g.current), 4);
        }
        let events: Vec<Value> = std::mem::take(&mut g.event_log).into_iter().map(Value::Object).collect();
        g.history.push(json!({"turn": 0, "player": g.current, "action": {"type": "start"}, "events": events}));
        g
    }

    // --- apply ------------------------------------------------------------------

    /// Applies one action. Illegal actions change nothing.
    pub fn apply(&mut self, action: &Value) -> Applied {
        let a = normalize(action);
        if a.is_empty() || !self.legal_actions().contains(&a) {
            return Applied { ok: false, error: format!("illegal action {}", json::stringify(&Value::Object(a))), events: vec![] };
        }
        self.event_log.clear();
        let who = self.current;
        let p = int(a.get("player")) as usize;
        match a["type"].as_str().unwrap() {
            "mulligan" => {
                let replace: Vec<Id> = a["replace"].as_array().unwrap().iter().map(|x| int(Some(x))).collect();
                self.do_mulligan(p, replace)
            }
            "end_turn" => self.end_turn(),
            "concede" => self.concede(p),
            _ => self.apply_play_action(&a),
        }
        self.resolve();
        self.prune_pending();
        let events = self.event_log.clone();
        let ev_values: Vec<Value> = events.iter().cloned().map(Value::Object).collect();
        let player = a.get("player").cloned().unwrap_or(json!(who));
        self.history.push(json!({"turn": self.turn, "player": player, "action": a, "events": ev_values}));
        Applied { ok: true, error: String::new(), events }
    }

    pub fn legal_actions(&self) -> Vec<Action> {
        let mut out = vec![];
        if self.game_over {
            return out;
        }
        if self.phase == "MULLIGAN" {
            for p in &self.players {
                if !p.mulliganed {
                    for ids in subsets(&p.hand) {
                        out.push(obj(json!({"type": "mulligan", "player": p.index, "replace": ids})));
                    }
                }
            }
        } else {
            out.push(obj(json!({"type": "end_turn", "player": self.current})));
            self.legal_play_actions(&mut out);
        }
        for p in 0..2 {
            out.push(obj(json!({"type": "concede", "player": p})));
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
        self.add_to_hand(self.opponent(self.current), COIN);
        self.phase = "PLAY";
        self.start_turn();
    }

    fn start_turn(&mut self) {
        let cur = self.current;
        self.turn += 1;
        let p = &mut self.players[cur];
        p.max_mana = MAX_MANA.min(p.max_mana + 1);
        p.overload_locked = p.overload_owed;
        p.overload_owed = 0;
        p.mana = 0.max(p.max_mana - p.overload_locked);
        p.cards_played_this_turn = 0;
        p.minions_played_this_turn = 0;
        let hp = p.hero_power;
        self.em(hp).erase_tag("USED");
        for c in self.chars(cur) {
            let e = self.em(c);
            e.erase_tag("EXHAUSTED");
            e.set_tag("ATTACKS", json!(0));
        }
        self.emit(json!({"type": "turn_start", "player": cur, "turn": self.turn}));
        self.resolve();
        if !self.game_over {
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
            pl.cost_mods.retain(|m| int(m.get("turn")) > turn);
        }
        for c in self.chars(cur) {
            let e = self.em(c);
            if e.has("FROZEN") && !(truthy(e.tags.get("FROZEN_THIS_TURN")) && e.tag("ATTACKS") > 0) {
                e.erase_tag("FROZEN");
            }
            e.erase_tag("FROZEN_THIS_TURN");
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

    fn apply_play_action(&mut self, a: &Action) {
        let i = |k: &str| int(a.get(k));
        match a["type"].as_str().unwrap() {
            "play" => self.do_play(i("entity"), i("target"), i("pos"), i("choice")),
            "attack" => self.do_attack(i("attacker"), i("defender")),
            "hero_power" => self.do_hero_power(i("target")),
            "choose" => self.do_choose(i("option")),
            _ => {}
        }
    }

    fn legal_play_actions(&self, out: &mut Vec<Action>) {
        if let Some(p) = &self.pending {
            out.clear();
            for id in self.pending_options() {
                out.push(obj(json!({"type": "choose", "player": p.player, "option": id})));
            }
            return;
        }
        let cur = self.current;
        let p = &self.players[cur];
        for &e in &p.hand {
            if self.cost(e) > p.mana || !self.can_play(e) {
                continue;
            }
            let choices: &[i64] = if cards::of(&self.e(e).card_id).choose_one.is_some() { &[0, 1] } else { &[-1] };
            for &choice in choices {
                for t in self.play_targets(e, choice) {
                    for pos in self.positions(e) {
                        out.push(obj(json!({"type": "play", "player": cur, "entity": e, "target": t, "pos": pos,
                            "choice": choice})));
                    }
                }
            }
        }
        let hp = p.hero_power;
        let hpe = self.e(hp);
        if !hpe.has("USED") && !hpe.has("LOCKED") && self.cost(hp) <= p.mana {
            let hh = cards::of(&hpe.card_id);
            if hh.hero_power.is_some() && hh.can_play.is_none_or(|f| f(self, hp)) {
                for t in self.spec_targets(hp, hh.target, true, false) {
                    out.push(obj(json!({"type": "hero_power", "player": cur, "target": t})));
                }
            }
        }
        for a in self.chars(cur) {
            if self.can_attack(a) {
                for d in self.defenders(a) {
                    out.push(obj(json!({"type": "attack", "player": cur, "attacker": a, "defender": d})));
                }
            }
        }
    }

    fn can_play(&self, e: Id) -> bool {
        let x = self.e(e);
        let p = &self.players[x.controller];
        if x.is_minion() && p.board.len() >= MAX_BOARD {
            return false;
        }
        if x.card.has_mechanic("SECRET") && p.secrets.iter().any(|&s| self.e(s).card_id == x.card_id) {
            return false;
        }
        cards::of(&x.card_id).can_play.is_none_or(|f| f(self, e))
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
    pub fn target_spec(&self, e: Id, choice: i64, combo: bool) -> Option<cards::Spec> {
        let h = cards::of(&self.e(e).card_id);
        if h.combo_target.is_some() {
            return if combo { h.combo_target } else { None };
        }
        if choice >= 0 {
            return cards::of(h.choose_one.unwrap()[choice as usize]).target;
        }
        h.target
    }

    fn spec_targets(&self, e: Id, spec: Option<cards::Spec>, is_spell: bool, optional: bool) -> Vec<Id> {
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
        let x = self.e(a);
        if self.attack_value(a) <= 0 || x.has("FROZEN") || x.has("CANT_ATTACK") {
            return false;
        }
        if x.is_minion() && x.has("EXHAUSTED") && !x.has("CHARGE") {
            return false;
        }
        let weapon_wf = x.is_hero() && self.players[x.controller].weapon.is_some_and(|w| self.e(w).has("WINDFURY"));
        let limit = if x.has("WINDFURY") || weapon_wf { 2 } else { 1 };
        x.tag("ATTACKS") < limit
    }

    fn defenders(&self, a: Id) -> Vec<Id> {
        let mut all = vec![];
        let mut taunts = vec![];
        let foe = self.opponent(self.ctrl(a));
        for t in self.chars(foe) {
            let te = self.e(t);
            if te.has("STEALTH") {
                continue;
            }
            if te.is_hero() && te.has("GUARDED") && !self.players[foe].board.is_empty() {
                continue; // a tutorial boss behind his minions (Lorewalker Cho): minions first
            }
            all.push(t);
            if te.is_minion() && te.has("TAUNT") {
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
        self.players[c].overload_owed += self.e(e).card.overload;
        match self.e(e).kind() {
            "MINION" => self.play_minion(e, t, pos, choice, combo),
            "SPELL" => self.play_spell(e, t, choice, combo),
            "WEAPON" => self.play_weapon(e, t, combo),
            _ => {}
        }
    }

    fn run_effect(&mut self, e: Id, key: &str, t: Id, choice: i64, combo: bool) {
        let h = cards::of(&self.e(e).card_id);
        if t == NONE && self.target_spec(e, choice, combo).is_some() {
            return; // targeted effect with no target (none was valid, or it left play)
        }
        let f = if choice >= 0 {
            cards::of(h.choose_one.unwrap()[choice as usize]).effect
        } else if combo && h.combo.is_some() {
            h.combo
        } else if key == "battlecry" {
            h.battlecry
        } else {
            h.spell
        };
        if let Some(f) = f {
            self.from(e, |g| f(g, e, t));
        }
    }

    fn play_minion(&mut self, e: Id, mut t: Id, pos: i64, choice: i64, combo: bool) {
        let c = self.ctrl(e);
        let card = self.e(e).card_id.clone();
        self.players[c].minions_played_this_turn += 1;
        self.place_on_board(e, pos);
        self.em(e).give_tag("EXHAUSTED", false);
        self.emit(json!({"type": "play", "entity": e, "player": c, "kind": "minion", "target": t, "card": card}));
        self.emit(json!({"type": "summon", "entity": e, "player": c, "card": card}));
        self.resolve();
        if self.game_over || self.e(e).zone != "PLAY" {
            return;
        }
        if t != NONE && self.e(t).zone != "PLAY" {
            t = NONE;
        }
        self.run_effect(e, "battlecry", t, choice, combo);
        self.resolve();
        if self.game_over || self.e(e).zone != "PLAY" {
            return;
        }
        let c = self.ctrl(e);
        self.emit(json!({"type": "after_summon", "entity": e, "player": c, "card": card, "played": true}));
    }

    fn play_spell(&mut self, e: Id, t: Id, choice: i64, combo: bool) {
        let c = self.ctrl(e);
        let card = self.e(e).card_id.clone();
        let is_secret = self.e(e).card.has_mechanic("SECRET");
        self.em(e).zone = "SETASIDE";
        let ev = self.emit(json!({"type": "play", "entity": e, "player": c, "kind": "spell", "secret": is_secret,
            "target": t, "card": card, "countered": false}));
        self.resolve();
        if self.game_over {
            return;
        }
        let countered = self.ev_b(ev, "countered");
        if is_secret {
            if countered {
                self.em(e).zone = "GRAVEYARD";
            } else {
                self.players[c].secrets.push(e);
                self.enter_play(e);
                self.em(e).zone = "SECRET";
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
        let card = self.e(e).card_id.clone();
        self.emit(json!({"type": "play", "entity": e, "player": c, "kind": "weapon", "target": t, "card": card}));
        self.resolve();
        if self.game_over {
            return;
        }
        self.run_effect(e, "battlecry", t, -1, combo);
        self.resolve();
        if !self.game_over {
            self.equip_entity(e);
        }
    }

    // --- attack -----------------------------------------------------------------

    fn do_attack(&mut self, a: Id, d: Id) {
        let n = self.e(a).tag("ATTACKS") + 1;
        self.em(a).set_tag("ATTACKS", json!(n));
        self.em(a).erase_tag("STEALTH");
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
        let weapon = if self.e(a).is_hero() { self.players[self.ctrl(a)].weapon } else { None };
        let immune = weapon.is_some_and(|w| cards::of(&self.e(w).card_id).immune_while_attacking);
        if immune {
            self.em(a).give_tag("IMMUNE", false);
        }
        let a_dmg = self.attack_value(a);
        let d_dmg = self.attack_value(d);
        self.damage(a, d, a_dmg);
        self.damage(d, a, d_dmg);
        if immune {
            self.em(a).erase_tag("IMMUNE");
        }
        if let Some(w) = weapon {
            if self.e(w).zone == "PLAY" {
                let lose = match cards::of(&self.e(w).card_id).durability_on_attack {
                    Some(f) => f(self, w, d),
                    None => true,
                };
                if lose {
                    let dur = self.e(w).tag("DURABILITY") - 1;
                    self.em(w).set_tag("DURABILITY", json!(dur));
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
        self.em(hp).give_tag("USED", false);
        if let Some(f) = cards::of(&self.e(hp).card_id).hero_power {
            self.from(hp, |g| f(g, hp, t));
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
        if let Some(f) = cards::of(&self.e(src).card_id).on_choose {
            self.from(src, |g| f(g, src, option, still));
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
