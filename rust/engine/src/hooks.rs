//! Hook sets: what the engine calls for a card or an enchantment ("ench:…").
//! Every hook is a function of the ruleset's Lua scripts (crate::lua,
//! docs/packs/api.md); the engine has no card logic of its own.

/// A hook function: an index into the ruleset's script functions (`LuaRules::fns`).
pub type HookFn = u32;

/// The base of a target spec (docs/packs/api.md `target`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Base {
    Any,
    Minion,
    EnemyMinion,
    FriendlyMinion,
    EnemyChar,
    FriendlyChar,
    EnemyChampion,
}

/// A target spec: a base plus an optional filter hook.
#[derive(Clone, Copy, Debug)]
pub struct TSpec {
    pub base: Base,
    pub filter: Option<HookFn>,
}

/// A TRAP: fires on `event` in the opponent's turn when `cond` holds (None: always);
/// the trap is revealed, then `effect` runs.
#[derive(Clone, Copy, Debug)]
pub struct TrapHook {
    pub event: &'static str,
    pub cond: Option<HookFn>,
    pub effect: HookFn,
}

/// The hooks of a card or of an enchantment, as the engine calls them.
#[derive(Clone, Default, Debug)]
pub struct HookSet {
    pub target: Option<TSpec>,
    pub on_play: Option<HookFn>,
    pub spell: Option<HookFn>,
    pub combo: Option<HookFn>,
    pub combo_target: Option<TSpec>,
    /// CHOICE: the two option cards, in card-text order.
    pub choice: Option<[&'static str; 2]>,
    /// The effect of a CHOICE option card.
    pub effect: Option<HookFn>,
    /// A POWER's effect.
    pub power: Option<HookFn>,
    pub can_play: Option<HookFn>,
    pub on_death: Option<HookFn>,
    pub on: Vec<(&'static str, HookFn)>,
    pub trap: Option<TrapHook>,
    /// Called at once (replacement effects): only "predamage".
    pub now: Vec<(&'static str, HookFn)>,
    pub aura: Option<HookFn>,
    /// Runs after every normal aura.
    pub aura_final: Option<HookFn>,
    pub cost_mod: Option<HookFn>,
    pub cost_aura: Option<HookFn>,
    pub on_choose: Option<HookFn>,
    pub immune_while_attacking: bool,
    pub durability_on_attack: Option<HookFn>,
}

impl HookSet {
    pub fn on(&self, ev_type: &str) -> Option<HookFn> {
        self.on.iter().find(|(t, _)| *t == ev_type).map(|(_, f)| *f)
    }
    pub fn now(&self, ev_type: &str) -> Option<HookFn> {
        self.now.iter().find(|(t, _)| *t == ev_type).map(|(_, f)| *f)
    }
}

/// What hooks a card has, for clients (glows, death marks, choice options):
/// {"on": [event types], "aura": true, "choose_one": [a, b], ...}. The keys are
/// the client protocol's (`battlecry` = ON_PLAY, `deathrattle` = ON_DEATH,
/// `secret` = TRAP, `hero_power` = POWER, `choose_one` = CHOICE).
pub fn summary(h: &HookSet) -> serde_json::Value {
    let mut m = serde_json::Map::new();
    let mut flag = |k: &str, b: bool| {
        if b {
            m.insert(k.into(), serde_json::Value::Bool(true));
        }
    };
    flag("target", h.target.is_some());
    flag("battlecry", h.on_play.is_some());
    flag("spell", h.spell.is_some());
    flag("combo", h.combo.is_some());
    flag("combo_target", h.combo_target.is_some());
    flag("effect", h.effect.is_some());
    flag("hero_power", h.power.is_some());
    flag("can_play", h.can_play.is_some());
    flag("deathrattle", h.on_death.is_some());
    flag("aura", h.aura.is_some() || h.aura_final.is_some());
    flag("cost_mod", h.cost_mod.is_some() || h.cost_aura.is_some());
    flag("on_choose", h.on_choose.is_some());
    flag("immune_while_attacking", h.immune_while_attacking);
    flag("durability_on_attack", h.durability_on_attack.is_some());
    let mut on: Vec<&str> = h.on.iter().map(|(t, _)| *t).collect();
    if let Some(s) = h.trap {
        on.push(s.event);
        m.insert("secret".into(), serde_json::Value::Bool(true));
    }
    on.extend(h.now.iter().map(|(t, _)| *t));
    if !on.is_empty() {
        m.insert("on".into(), serde_json::json!(on));
    }
    if let Some(c) = h.choice {
        m.insert("choose_one".into(), serde_json::json!(c));
    }
    serde_json::Value::Object(m)
}
