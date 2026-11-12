//! Match setup, turns, actions and legality (engine/game.gd).

use crate::hooks::TSpec;
use crate::entity::{obj, vint, vtruthy, Id, Obj, NONE};
use crate::json;
use crate::rng::Rng;
use crate::ruleset::{self, Ruleset};
use crate::state::{Game, Hist};
use serde_json::{json, Map, Value};

pub use crate::state::Ev;

/// The `choice` of a Choose One card played with both options (BOTH_CHOICES: Fandral Staghelm).
pub const BOTH: i64 = 2;

/// An action: {"type": ..., "player": ..., ...} with whole numbers as ints.
pub type Action = Map<String, Value>;

/// The result of `apply`.
#[derive(Debug, Clone)]
pub struct Applied {
    pub ok: bool,
    pub error: String,
    log: Vec<Obj>,
}

impl Applied {
    /// The events of the action, as JSON objects.
    pub fn events(&self) -> Vec<Ev> {
        self.log.iter().map(Obj::to_map).collect()
    }
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
            if d.iter().any(|&e| g.e(e).card.task) {
                // a task card (a Quest) starts in the opening hand: it goes on top, in the order the shuffle gave
                let (tasks, rest): (Vec<Id>, Vec<Id>) = d.iter().partition(|&&e| g.e(e).card.task);
                d = rest.into_iter().chain(tasks).collect();
            }
            g.players[i].deck = d;
        }
        g.current = if first >= 0 { first as usize } else { g.rng.randi_range(0, 1) as usize };
        if deal {
            let [a, b] = rs.start_hand;
            g.draw(g.current, a);
            g.draw(g.opponent(g.current), b);
            g.queue.clear(); // the opening hands' draws set off nothing (a player hook on `draw`: Crystal Core)
        }
        let events = std::mem::take(&mut g.event_log);
        let action = Action::from_iter([("type".to_string(), json!("start"))]);
        g.history.push(Hist { turn: 0, player: json!(g.current), action, events });
        g
    }

    // --- apply ------------------------------------------------------------------

    /// Applies one action. Illegal actions change nothing.
    pub fn apply(&mut self, action: &Value) -> Applied {
        let a = normalize(action);
        if self.script_error.get().is_some() && !self.game_over {
            self.event_log.clear();
            self.end_by_script_error();
            let log = std::mem::take(&mut self.event_log);
            self.history.push(Hist { turn: self.turn, player: json!(self.current), action: a, events: log.clone() });
            return Applied { ok: true, error: String::new(), log };
        }
        // the whole legal list even for a malformed action: its read-only hooks may fail (a script error)
        let act = if a.is_empty() { None } else { Some(self.legal()).and_then(|l| Act::from_map(&a).filter(|x| l.contains(x))) };
        let Some(act) = act else {
            return Applied { ok: false, error: format!("illegal action {}", json::stringify(&Value::Object(a))), log: vec![] };
        };
        let who = self.current;
        self.run(act);
        let log = std::mem::take(&mut self.event_log);
        let player = a.get("player").cloned().unwrap_or(json!(who));
        self.history.push(Hist { turn: self.turn, player, action: a, events: log.clone() });
        Applied { ok: true, error: String::new(), log }
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
            Act::Play { entity, target, pos, choice, .. } => {
                let t = self.random_target(target, |g| g.play_targets(entity, choice));
                self.do_play(entity, t, pos, choice)
            }
            Act::Attack { attacker, defender, .. } => {
                // past Taunt and Stealth, never a friendly one (Mayor Noggenfogger's note on hearthstone.wiki.gg)
                let d = self.random_target(defender, |g| g.any_defenders(attacker));
                self.do_attack(attacker, d)
            }
            Act::HeroPower { target, .. } => {
                let hp = self.players[self.current].hero_power;
                let t = self.random_target(target, |g| g.spec_targets(hp, g.live_spec(hp, g.e(hp).hooks().target), true, false));
                self.do_hero_power(t)
            }
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
        self.log_event(obj!{"type": "mulligan_chosen", "player": p});
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
        self.log_event(obj!{"type": "mulligan", "player": p, "count": old.len()});
    }

    fn finish_mulligan(&mut self) {
        // "when the game starts", after the mulligan (Prince Malchezaar): only for a pack whose player hooks listen, so
        // no other game logs it
        let rs = self.rs;
        if rs.player_hooks.as_deref().is_some_and(|h| rs.hooks(h).on("game_start").is_some()) {
            self.emit(obj!{"type": "game_start"});
            self.resolve();
        }
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
        if let Some(t) = n.power_uses {
            self.em(hp).erase_tag(t);
        }
        for c in self.chars(cur) {
            let e = self.em(c);
            e.erase_tag(n.exhausted);
            e.set_tag(n.attacks, 0i64);
        }
        self.emit(obj!{"type": "turn_start", "player": cur, "turn": self.turn});
        self.resolve();
        if !self.game_over && (self.turn > 1 || self.rs.first_player_draws) {
            self.draw(cur, 1);
        }
    }

    fn end_turn(&mut self) {
        let cur = self.current;
        self.emit(obj!{"type": "turn_end", "player": cur});
        self.resolve();
        if self.game_over {
            return;
        }
        for e in self.in_play() {
            self.em(e).remove_eot();
        }
        let turn = self.turn;
        for pl in &mut self.players {
            pl.cost_mods.retain(|m| vint(m.get("turn")) > turn || crate::state::lasting(m));
        }
        let n = self.n();
        for c in self.chars(cur) {
            let e = self.em(c);
            if e.has(n.frozen) && !(vtruthy(e.tags.get(n.frozen_this_turn)) && e.tag(n.attacks) > 0) {
                e.erase_tag(n.frozen);
            }
            e.erase_tag(n.frozen_this_turn);
        }
        self.log_event(obj!{"type": "turn_end", "player": cur});
        // an extra turn it is owed (Time Warp) comes before the opponent's
        if self.players[cur].extra_turns > 0 {
            self.players[cur].extra_turns -= 1;
            self.log_event(obj!{"type": "extra_turn", "player": cur});
        } else {
            self.current = self.opponent(cur);
        }
        self.start_turn();
    }

    fn concede(&mut self, p: usize) {
        self.game_over = true;
        self.phase = "OVER";
        self.winner = self.opponent(p) as i64;
        self.log_event(obj!{"type": "game_over", "winner": self.winner});
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
        let auras = self.cost_auras();
        for &e in &p.hand {
            let cost = self.cost_in(e, &auras);
            let affordable = if self.pays_health(e) {
                let h = self.e(p.hero);
                h.health() + h.tag(self.n().armor) > cost // Health (and Armor) instead of Mana, more than it costs
            } else {
                cost <= p.mana
            };
            if !affordable || !self.can_play(e) {
                continue;
            }
            let choices: &[i64] = match self.e(e).hooks().choice {
                Some(_) if self.both_choices(cur) => &[BOTH],
                Some(_) => &[0, 1],
                None => &[-1],
            };
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
        if !hpe.has(n.used) && !hpe.has(n.locked) && self.cost_in(hp, &auras) <= p.mana {
            let hh = hpe.hooks();
            if hh.power.is_some() && hh.can_play.is_none_or(|f| self.fx_can_play(f, hp)) {
                for t in self.spec_targets(hp, self.live_spec(hp, hh.target), true, false) {
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
        if x.card.trap && !self.trap_room(x.controller, x.card_id) {
            return false;
        }
        if x.card.task && !self.task_room(x.controller) {
            return false;
        }
        x.hooks().can_play.is_none_or(|f| self.fx_can_play(f, e))
    }

    pub fn combo_active(&self, e: Id) -> bool {
        self.players[self.ctrl(e)].cards_played_this_turn > 0
    }

    /// Whether a card in a hand glows yellow (its condition holds now, as Hearthstone shows it): its
    /// script's `glow(g, me)` hook says so, else a card with a COMBO hook glows while its combo is on.
    /// Only on its owner's turn. For clients only (snapshots); nothing in the rules reads it.
    pub fn glows(&self, e: Id) -> bool {
        let x = self.e(e);
        if x.zone != "HAND" || x.controller != self.current || self.game_over {
            return false;
        }
        match x.hooks().glow {
            Some(f) => self.fx_can_play(f, e),
            None => x.hooks().combo.is_some() && self.combo_active(e),
        }
    }

    /// Target ids for playing e with the given choice. [-1] means "no target";
    /// an empty list means e cannot be played.
    fn play_targets(&self, e: Id, choice: i64) -> Vec<Id> {
        let is_spell = self.e(e).kind() == "SPELL";
        self.spec_targets(e, self.target_spec(e, choice, self.combo_active(e)), is_spell, !is_spell)
    }

    /// The target spec that applies when e is played with this choice and combo state.
    pub fn target_spec(&self, e: Id, choice: i64, combo: bool) -> Option<TSpec> {
        let h = self.e(e).hooks();
        let spec = if h.combo_target.is_some() {
            if combo { h.combo_target } else { None }
        } else if choice == BOTH {
            // both options on one target: the first option's target, else the second's
            let [a, b] = h.choice.unwrap();
            self.rs.hooks(a).target.or(self.rs.hooks(b).target)
        } else if choice >= 0 {
            self.rs.hooks(h.choice.unwrap()[choice as usize]).target
        } else {
            h.target
        };
        self.live_spec(e, spec)
    }

    /// RANDOM_TARGETS (an aura tag on the acting player's champion: Mayor Noggenfogger): the chosen target of a
    /// play, an attack or a power becomes a random one of its valid targets (`valid`, as `legal` lists them, the
    /// chosen one too). Only in a pack that names the mechanic; no target chosen: none.
    fn random_target(&mut self, t: Id, valid: impl Fn(&Game) -> Vec<Id>) -> Id {
        let Some(tag) = self.n().random_targets else { return t };
        if t == NONE || !self.e(self.hero(self.current)).aura.tags.contains_key(tag) {
            return t;
        }
        let ids: Vec<Id> = valid(self).into_iter().filter(|&x| x != NONE).collect();
        if ids.len() < 2 {
            return t;
        }
        let i = self.rng.randi_range(0, ids.len() as i64 - 1) as usize;
        let nt = ids[i];
        if nt != t {
            self.log_event(obj!{"type": "retarget", "from": t, "to": nt});
        }
        nt
    }

    /// A target spec as it applies now: none while its `when` hook does not hold.
    fn live_spec(&self, e: Id, spec: Option<TSpec>) -> Option<TSpec> {
        spec.filter(|s| s.when.is_none_or(|f| self.fx_can_play(f, e)))
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
        let weapon = |t: &str| x.is_champion() && self.players[x.controller].weapon.is_some_and(|w| self.e(w).has(t));
        if x.has(n.unlimited_attacks) || weapon(n.unlimited_attacks) {
            return true; // Fool's Bane: as many attacks as it has the weapon for
        }
        let limit = if x.has(n.double_attack) || weapon(n.double_attack) { 2 } else { 1 };
        x.tag(n.attacks) < limit
    }

    /// The enemy characters a may hit when its attack goes astray (RANDOM_TARGETS): every one, Taunt or Stealth or
    /// not, but a champion only if a may attack champions.
    fn any_defenders(&self, a: Id) -> Vec<Id> {
        let n = self.n();
        let (x, p) = (self.e(a), self.ctrl(a));
        let no_heroes = x.has(n.cant_attack_heroes)
            || (x.is_champion() && self.players[p].weapon.is_some_and(|w| self.e(w).has(n.cant_attack_heroes)));
        self.chars(self.opponent(p)).into_iter().filter(|&t| !(no_heroes && self.e(t).is_champion())).collect()
    }

    fn defenders(&self, a: Id) -> Vec<Id> {
        let mut all = vec![];
        let mut taunts = vec![];
        let foe = self.opponent(self.ctrl(a));
        let n = self.n();
        // a champion's weapon that cannot attack champions keeps it off them too (Fool's Bane)
        let (x, p) = (self.e(a), self.ctrl(a));
        let no_heroes = x.has(n.cant_attack_heroes)
            || (x.is_champion() && self.players[p].weapon.is_some_and(|w| self.e(w).has(n.cant_attack_heroes)));
        for t in self.chars(foe) {
            let te = self.e(t);
            if te.has(n.stealth) || (no_heroes && te.is_champion()) {
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
        if self.pays_health(e) {
            let h = self.hero(c);
            self.damage(NONE, h, cost); // Cho'gall: the cost in Health, as damage (Armor first)
        } else {
            self.players[c].mana -= cost;
        }
        if let Some(t) = self.n().played_cost {
            self.em(e).set_tag(t, cost);
        }
        self.consume_cost_mods(e);
        self.players[c].hand.retain(|&x| x != e);
        let combo = self.combo_active(e);
        let x = self.em(e);
        (x.choice, x.comboed) = (choice, combo);
        self.players[c].cards_played_this_turn += 1;
        self.players[c].mana_lock_owed += self.e(e).card.mana_lock;
        match self.e(e).kind() {
            "MINION" => self.play_minion(e, t, pos, choice, combo),
            "SPELL" => self.play_spell(e, t, choice, combo),
            "WEAPON" => self.play_weapon(e, t, combo),
            "CHAMPION" => self.play_champion(e, t, choice, combo),
            _ => {}
        }
    }

    /// A hero card (a CHAMPION played from the hand: Knights of the Frozen Throne's Death Knights): the `play` event
    /// (kind `champion`), then it becomes its player's champion (`become_champion`), its `armor` is gained (added to
    /// the Armor it had) and its `power` replaces the power (a fresh one, usable this turn), then its Battlecry.
    fn play_champion(&mut self, e: Id, t: Id, choice: i64, combo: bool) {
        let c = self.ctrl(e);
        let card = self.e(e).card_id;
        self.emit(obj!{"type": "play", "entity": e, "player": c, "kind": "champion", "target": t, "card": card});
        self.resolve();
        if self.game_over {
            return;
        }
        self.become_champion(e);
        let armor = self.e(e).card.armor;
        if armor > 0 {
            self.gain_armor(c, armor);
        }
        let t = if t != NONE && self.e(t).zone != "PLAY" { NONE } else { t };
        self.run_effect(e, "on_play", t, choice, combo);
    }

    /// Makes the card e (a CHAMPION) its controller's champion in the old one's place (hearthstone.wiki.gg, Hero card):
    /// it keeps the old one's Health and maximum Health, Armor, attacks made this turn (patch 9.0: a new champion does
    /// not "refresh" the weapon swing) and the rest of its state (buffs, "this turn" tags), but not Frozen (a hero card
    /// thaws). Its power (if it names one) becomes a fresh power. Logs `hero_replaced`.
    pub fn become_champion(&mut self, e: Id) {
        let p = self.ctrl(e);
        let old = self.players[p].hero;
        let (n, rs) = (self.n(), self.rs);
        let o = self.e(old).clone();
        self.em(old).zone = "SETASIDE";
        self.enter_play(e);
        let x = self.em(e);
        x.enchantments = o.enchantments.clone();
        x.eot_tags = o.eot_tags.clone();
        for (k, v) in o.tags.iter() {
            if k != n.frozen && k != n.frozen_this_turn {
                x.tags.insert(rs.intern(k), v.clone());
            }
        }
        let old_max = o.max_health() - o.aura.hp;
        if x.max_health() != old_max {
            let mut base = Obj::new();
            base.insert("base", true);
            base.insert("set_hp", old_max - (x.max_health() - x.card.health));
            x.enchantments.insert(0, base); // its maximum Health is the old champion's
        }
        x.damage = o.damage;
        self.players[p].hero = e;
        self.log_event(obj!{"type": "hero_replaced", "player": p, "entity": e, "card": self.e(e).card_id});
        let power = self.e(e).card.power.as_str();
        if !power.is_empty() {
            self.set_hero_power(p, power);
        }
    }

    /// Casts a copy of the spell `orig` for src's controller on t, as `orig` was cast (its Choose One option, its
    /// Combo): only its effect, no `play` or `after_spell` event, no target check (Djinni of Zephyrs). Logs `cast`.
    pub fn cast_copy(&mut self, src: Id, orig: Id, t: Id) {
        let (p, o) = (self.ctrl(src), self.e(orig));
        let (card, choice, combo) = (o.card_id, o.choice, o.comboed);
        let h = o.hooks();
        let fs = if choice >= 0 && h.choice.is_some() {
            self.choice_effects(h, choice)
        } else if combo && h.combo.is_some() {
            h.combo.into_iter().collect()
        } else {
            h.spell.into_iter().collect()
        };
        let e = self.new_entity(card, p);
        self.log_event(obj!{"type": "cast", "player": p, "entity": e, "card": card, "target": t});
        for (i, f) in fs.into_iter().enumerate() {
            if i > 0 && self.game_over {
                break;
            }
            self.from(e, |c| c.fx_effect(f, e, t));
        }
        self.em(e).zone = "GRAVEYARD";
    }

    /// Casts a new spell `card` for src's controller with every choice made at random (Yogg-Saron, Hope's End): a
    /// random valid target (not an enemy with Stealth or Immune; none: it fizzles), a random Choose One option (both
    /// with BOTH_CHOICES), its offered choices picked at random; its Combo only if its player played a card before
    /// src this turn. A trap goes into play if it may. Only its effect: no `play` or `after_spell` event, no Overload.
    /// Logs `cast` with `random`; returns the spell (NONE if it fizzled).
    pub fn cast_random(&mut self, src: Id, card: &str) -> Id {
        let p = self.ctrl(src);
        let e = self.new_entity(card, p);
        let card = self.e(e).card_id;
        let h = self.e(e).hooks();
        let choice = match h.choice {
            Some(_) if self.both_choices(p) => BOTH,
            Some(_) => self.rng.randi_range(0, 1),
            None => -1,
        };
        let combo = self.players[p].cards_played_this_turn > 1;
        let x = self.em(e);
        (x.choice, x.comboed, x.auto_choice) = (choice, combo, true);
        if self.e(e).hooks().can_play.is_some_and(|f| !self.fx_can_play(f, e)) {
            // what it needs is missing (Blade Flurry without a weapon): it fizzles
            self.log_event(obj!{"type": "fizzle", "player": p, "entity": e, "card": card});
            self.em(e).zone = "GRAVEYARD";
            return NONE;
        }
        if self.e(e).card.trap || self.e(e).card.task {
            self.log_event(obj!{"type": "cast", "player": p, "entity": e, "card": card, "target": NONE, "random": true});
            let task = self.e(e).card.task;
            if if task { self.task_room(p) } else { self.trap_room(p, card) } {
                self.players[p].secrets.push(e);
                self.enter_play(e);
                self.em(e).zone = self.rs.names.trap;
                if task {
                    self.run_effect(e, "spell", NONE, -1, false); // its start (the goal it shows)
                }
            } else {
                self.em(e).zone = "GRAVEYARD";
            }
            return e;
        }
        let mut t = NONE;
        if let Some(spec) = self.target_spec(e, choice, combo) {
            let (n, valid) = (self.n(), self.targets(e, &spec, true));
            let valid: Vec<Id> = valid.into_iter().filter(|&x| !(self.ctrl(x) != p && self.e(x).has(n.immune))).collect();
            t = self.random_choice(&valid);
            if t == NONE {
                self.log_event(obj!{"type": "fizzle", "player": p, "entity": e, "card": card});
                self.em(e).zone = "GRAVEYARD";
                return NONE;
            }
        }
        self.log_event(obj!{"type": "cast", "player": p, "entity": e, "card": card, "target": t, "random": true});
        self.em(e).zone = "SETASIDE";
        self.run_effect(e, "spell", t, choice, combo);
        self.em(e).zone = "GRAVEYARD";
        e
    }

    /// p's Choose One cards have both effects now (BOTH_CHOICES on the champion: Fandral Staghelm).
    pub fn both_choices(&self, p: usize) -> bool {
        self.e(self.hero(p)).has(self.n().both_choices)
    }

    /// The effects of a CHOICE card played with this choice: the option's, or with BOTH the card's `both` hook, else
    /// both options' in card order.
    fn choice_effects(&self, h: &crate::hooks::HookSet, choice: i64) -> Vec<crate::hooks::HookFn> {
        let [a, b] = h.choice.unwrap();
        match choice {
            BOTH => match h.both {
                Some(f) => vec![f],
                None => [a, b].iter().filter_map(|o| self.rs.hooks(o).effect).collect(),
            },
            c => self.rs.hooks([a, b][c as usize & 1]).effect.into_iter().collect(),
        }
    }

    fn run_effect(&mut self, e: Id, key: &str, t: Id, choice: i64, combo: bool) {
        let h = self.e(e).hooks();
        if t == NONE && self.target_spec(e, choice, combo).is_some() {
            return; // targeted effect with no target (none was valid, or it left play)
        }
        let mut battlecry = false;
        let f = if choice >= 0 {
            for (i, f) in self.choice_effects(h, choice).into_iter().enumerate() {
                if i > 0 && self.game_over {
                    break;
                }
                self.from(e, |x| x.fx_effect(f, e, t)); // (a Choose One: its option, or both)
            }
            None
        } else if combo && h.combo.is_some() {
            h.combo
        } else if key == "on_play" {
            battlecry = true;
            h.on_play
        } else {
            h.spell
        };
        if let Some(f) = f {
            // DOUBLE_ON_PLAY (Brann Bronzebeard, in play as the Battlecry starts): a Battlecry (not a Combo, not a
            // Choose One) runs twice, on the same target, with no death phase between
            let twice = battlecry && self.e(self.hero(self.ctrl(e))).aura.tags.contains_key(self.n().double_on_play);
            for i in 0..1 + twice as usize {
                if i > 0 && self.game_over {
                    break;
                }
                self.from(e, |g| g.fx_effect(f, e, t));
            }
        }
    }

    fn play_minion(&mut self, e: Id, mut t: Id, pos: i64, choice: i64, combo: bool) {
        let c = self.ctrl(e);
        let card = self.e(e).card_id;
        self.players[c].minions_played_this_turn += 1;
        self.place_on_board(e, pos);
        let ex = self.n().exhausted;
        self.em(e).give_tag(ex, false);
        self.emit(obj!{"type": "play", "entity": e, "player": c, "kind": "minion", "target": t, "card": card});
        self.emit(obj!{"type": "summon", "entity": e, "player": c, "card": card});
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
        self.emit(obj!{"type": "after_summon", "entity": e, "player": c, "card": card, "played": true});
    }

    fn play_spell(&mut self, e: Id, t: Id, choice: i64, combo: bool) {
        let c = self.ctrl(e);
        let card = self.e(e).card_id;
        let (is_trap, is_task) = (self.e(e).card.trap, self.e(e).card.task);
        self.em(e).zone = "SETASIDE";
        let mut play = obj!{"type": "play", "entity": e, "player": c, "kind": "spell", "secret": is_trap,
            "target": t, "card": card, "countered": false};
        if is_task {
            play.insert("task", true); // a Quest: it goes up to its champion too, in sight of both players
        }
        let ev = self.emit(play);
        self.resolve();
        if self.game_over {
            return;
        }
        let countered = self.ev_b(ev, "countered");
        if is_trap || is_task {
            if countered {
                self.em(e).zone = "GRAVEYARD";
            } else {
                self.players[c].secrets.push(e);
                self.enter_play(e);
                self.em(e).zone = self.rs.names.trap;
                if is_task {
                    // a task's `spell` hook runs once it waits in the trap zone: its goal (QUEST_PROGRESS_TOTAL)
                    self.run_effect(e, "spell", NONE, -1, false);
                    self.resolve();
                    if self.game_over {
                        return;
                    }
                }
            }
            if !(countered && self.rs.countered_no_after_spell) {
                self.emit(obj!{"type": "after_spell", "entity": e, "player": c, "card": card});
            }
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
        if !self.game_over && !(countered && self.rs.countered_no_after_spell) {
            self.emit(obj!{"type": "after_spell", "entity": e, "player": c, "card": card});
        }
    }

    fn play_weapon(&mut self, e: Id, t: Id, combo: bool) {
        let c = self.ctrl(e);
        let card = self.e(e).card_id;
        self.emit(obj!{"type": "play", "entity": e, "player": c, "kind": "weapon", "target": t, "card": card});
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
        self.attack_now(a, d, false);
    }

    /// An attack of a on d. `forced`: a card makes it attack (`g.force_attack`: Swamp King Dred) in any turn; it uses
    /// none of its attacks.
    pub(crate) fn attack_now(&mut self, a: Id, d: Id, forced: bool) {
        let names = self.n();
        if !forced {
            let n = self.e(a).tag(names.attacks) + 1;
            self.em(a).set_tag(names.attacks, n);
        }
        self.em(a).erase_tag(names.stealth);
        let c = self.ctrl(a);
        let ev = self.emit(obj!{"type": "attack", "attacker": a, "defender": d, "player": c});
        self.resolve();
        if self.game_over || self.e(a).zone != "PLAY" || (!forced && self.ctrl(a) != self.current) || self.ctrl(a) != c {
            return;
        }
        let d = self.ev_i(ev, "defender");
        if self.ent(d).is_none_or(|x| x.zone != "PLAY") {
            return;
        }
        let weapon = if self.e(a).is_champion() { self.players[self.ctrl(a)].weapon } else { None };
        let immune = weapon.is_some_and(|w| self.e(w).hooks().immune_while_attacking);
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
                let lose = match self.e(w).hooks().durability_on_attack {
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
        self.emit(obj!{"type": "after_attack", "attacker": a, "defender": d, "player": c});
    }

    // --- hero power and choice --------------------------------------------------

    fn do_hero_power(&mut self, t: Id) {
        let cur = self.current;
        let hp = self.players[cur].hero_power;
        let cost = self.cost(hp);
        self.players[cur].mana -= cost;
        self.consume_cost_mods(hp);
        let n = self.n();
        self.em(hp).give_tag(n.used, false);
        if let Some(t) = n.power_uses {
            self.add_tag_int(hp, t.into(), 1);
        }
        if let Some(t) = n.powers_used {
            let h = self.players[cur].hero;
            self.add_tag_int(h, t.into(), 1);
        }
        if let Some(f) = self.e(hp).hooks().power {
            self.from(hp, |g| g.fx_effect(f, hp, t));
        }
        self.emit(obj!{"type": "hero_power", "player": cur, "entity": hp, "target": t});
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
        if let Some(f) = self.e(src).hooks().on_choose {
            self.from(src, |g| g.fx_choose(f, src, option, still));
        }
    }

    /// A choice whose options all left their zone (drawn by a trigger, say) is dropped; once none is pending, the
    /// next one asked for meanwhile comes (Brann Bronzebeard's second Discover).
    fn prune_pending(&mut self) {
        loop {
            if self.pending.is_none() && !self.pending_next.is_empty() {
                let p = self.pending_next.remove(0);
                self.log_event(obj!{"type": "choice", "player": p.player, "options": p.options.clone()});
                self.pending = Some(p);
            }
            let Some(p) = &self.pending else { return };
            if !self.pending_options().is_empty() {
                return;
            }
            let player = p.player;
            self.log_event(obj!{"type": "choice_cancelled", "player": player});
            self.pending = None;
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
