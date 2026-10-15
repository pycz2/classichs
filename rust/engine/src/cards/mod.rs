//! Card hooks by card id (cards/registry.gd). Each class file has `register`.
//!
//! A hook is a plain function; `me` is the entity whose card it is, `t` the
//! target (or NONE), `ev` an index into `Game::event_log`.

use crate::entity::Id;
use crate::state::{Ev, Game};
use std::collections::HashMap;
use std::sync::OnceLock;

mod druid;
mod heroes;
mod hunter;
mod mage;
mod neutral;
mod paladin;
mod priest;
mod rogue;
mod shaman;
mod tutorial;
mod warlock;
mod warrior;

pub use neutral::copy_minion;

fn ev_mine(g: &Game, me: Id, ev: usize) -> bool {
    g.ev_mine(me, ev)
}

pub type Effect = fn(&mut Game, Id, Id);
pub type OnFn = fn(&mut Game, Id, usize);
pub type NowFn = fn(&mut Game, Id, &mut Ev);
pub type DeathFn = fn(&mut Game, Id);
pub type AuraFn = fn(&mut Game, Id);
pub type CanPlay = fn(&Game, Id) -> bool;
pub type CostMod = fn(&Game, Id) -> i64;
pub type CostAura = fn(&Game, Id, Id, i64) -> i64;
pub type OnChoose = fn(&mut Game, Id, Id, Vec<Id>);
pub type Pred = fn(&Game, Id, Id) -> bool;
pub type SecretCond = fn(&Game, Id, usize) -> bool;

/// Target specification (engine/t.gd): a base filter plus an optional extra test.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Base {
    Any,
    Minion,
    EnemyMinion,
    FriendlyMinion,
    EnemyChar,
    FriendlyChar,
    EnemyHero,
}

#[derive(Clone, Copy)]
pub struct Spec {
    pub base: Base,
    pub pred: Option<Pred>,
}

pub const fn spec(base: Base) -> Option<Spec> {
    Some(Spec { base, pred: None })
}

pub const fn spec_if(base: Base, pred: Pred) -> Option<Spec> {
    Some(Spec { base, pred: Some(pred) })
}

pub const ANY: Option<Spec> = spec(Base::Any);
pub const MINION: Option<Spec> = spec(Base::Minion);
pub const ENEMY_MINION: Option<Spec> = spec(Base::EnemyMinion);
pub const FRIENDLY_MINION: Option<Spec> = spec(Base::FriendlyMinion);
pub const ENEMY_CHAR: Option<Spec> = spec(Base::EnemyChar);
pub const FRIENDLY_CHAR: Option<Spec> = spec(Base::FriendlyChar);

/// Cards.secret: fires on `event` during the opponent's turn when cond holds;
/// the secret is revealed, then effect runs.
#[derive(Clone, Copy)]
pub struct Secret {
    pub event: &'static str,
    pub cond: SecretCond,
    pub effect: OnFn,
}

#[derive(Clone, Default)]
pub struct Hooks {
    pub target: Option<Spec>,
    pub battlecry: Option<Effect>,
    pub spell: Option<Effect>,
    pub combo: Option<Effect>,
    pub combo_target: Option<Spec>,
    /// Choose One: the two option cards, in card-text order.
    pub choose_one: Option<[&'static str; 2]>,
    /// The effect of a Choose One option card.
    pub effect: Option<Effect>,
    pub hero_power: Option<Effect>,
    pub can_play: Option<CanPlay>,
    pub deathrattle: Option<DeathFn>,
    pub on: Vec<(&'static str, OnFn)>,
    pub secret: Option<Secret>,
    /// Called at once (replacement effects): only "predamage".
    pub now: Vec<(&'static str, NowFn)>,
    pub aura: Option<AuraFn>,
    /// Runs after every normal aura (Lightspawn).
    pub aura_final: Option<AuraFn>,
    pub cost_mod: Option<CostMod>,
    pub cost_aura: Option<CostAura>,
    pub on_choose: Option<OnChoose>,
    pub immune_while_attacking: bool,
    pub durability_on_attack: Option<fn(&mut Game, Id, Id) -> bool>,
}

impl Hooks {
    pub fn on(&self, ev_type: &str) -> Option<OnFn> {
        self.on.iter().find(|(t, _)| *t == ev_type).map(|(_, f)| *f)
    }
    pub fn now(&self, ev_type: &str) -> Option<NowFn> {
        self.now.iter().find(|(t, _)| *t == ev_type).map(|(_, f)| *f)
    }
}

pub type Registry = HashMap<&'static str, Hooks>;

fn registry() -> &'static Registry {
    static R: OnceLock<Registry> = OnceLock::new();
    R.get_or_init(|| {
        let mut r = Registry::new();
        heroes::register(&mut r);
        neutral::register(&mut r);
        druid::register(&mut r);
        hunter::register(&mut r);
        mage::register(&mut r);
        paladin::register(&mut r);
        priest::register(&mut r);
        rogue::register(&mut r);
        shaman::register(&mut r);
        warlock::register(&mut r);
        warrior::register(&mut r);
        tutorial::register(&mut r);
        r
    })
}

/// The hooks of a card id ("" or unknown: none).
pub fn of(card_id: &str) -> &'static Hooks {
    static EMPTY: OnceLock<Hooks> = OnceLock::new();
    registry().get(card_id).unwrap_or_else(|| EMPTY.get_or_init(Hooks::default))
}

/// What hooks a card has, for clients (glows, Deathrattle skulls, Choose One
/// options): {"on": [event types], "aura": true, "choose_one": [a, b], ...}.
pub fn summary(card_id: &str) -> serde_json::Value {
    let h = of(card_id);
    let mut m = serde_json::Map::new();
    let mut flag = |k: &str, b: bool| {
        if b {
            m.insert(k.into(), serde_json::Value::Bool(true));
        }
    };
    flag("target", h.target.is_some());
    flag("battlecry", h.battlecry.is_some());
    flag("spell", h.spell.is_some());
    flag("combo", h.combo.is_some());
    flag("combo_target", h.combo_target.is_some());
    flag("effect", h.effect.is_some());
    flag("hero_power", h.hero_power.is_some());
    flag("can_play", h.can_play.is_some());
    flag("deathrattle", h.deathrattle.is_some());
    flag("aura", h.aura.is_some() || h.aura_final.is_some());
    flag("cost_mod", h.cost_mod.is_some() || h.cost_aura.is_some());
    flag("on_choose", h.on_choose.is_some());
    flag("immune_while_attacking", h.immune_while_attacking);
    flag("durability_on_attack", h.durability_on_attack.is_some());
    let mut on: Vec<&str> = h.on.iter().map(|(t, _)| *t).collect();
    if let Some(s) = h.secret {
        on.push(s.event);
        m.insert("secret".into(), serde_json::Value::Bool(true));
    }
    on.extend(h.now.iter().map(|(t, _)| *t));
    if !on.is_empty() {
        m.insert("on".into(), serde_json::json!(on));
    }
    if let Some(c) = h.choose_one {
        m.insert("choose_one".into(), serde_json::json!(c));
    }
    serde_json::Value::Object(m)
}

/// Every card id with hooks.
pub fn all_ids() -> Vec<&'static str> {
    let mut v: Vec<&'static str> = registry().keys().copied().collect();
    v.sort();
    v
}

/// Hooks with nothing set (for `..d()`).
pub(crate) fn d() -> Hooks {
    Hooks::default()
}

/// Helpers that card hooks share.
impl Game {
    /// The opponent of me's controller.
    pub fn foe(&self, me: Id) -> usize {
        1 - self.ctrl(me)
    }

    /// p's weapon, or NONE.
    pub fn weapon_of(&self, p: usize) -> Id {
        self.players[p].weapon.unwrap_or(crate::entity::NONE)
    }

    pub fn board_has_room(&self, me: Id) -> bool {
        self.players[self.ctrl(me)].board.len() < crate::state::MAX_BOARD
    }

    pub fn add_tag_int(&mut self, e: Id, tag: &str, n: i64) {
        let v = self.e(e).tag(tag) + n;
        self.em(e).set_tag(tag, serde_json::json!(v));
    }

    /// The event's "player" is me's controller.
    pub fn ev_mine(&self, me: Id, ev: usize) -> bool {
        self.ev_i(ev, "player") == self.ctrl(me) as i64
    }

    /// DIED_POS of a dead minion (-1 if it has none).
    pub fn died_pos(&self, e: Id) -> i64 {
        match self.e(e).tags.get("DIED_POS") {
            Some(v) => crate::entity::int(Some(v)),
            None => -1,
        }
    }
}
