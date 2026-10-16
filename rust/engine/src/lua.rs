//! Card hooks written in Lua (docs/packs/api.md): loading a pack's scripts,
//! the `g` library that exposes the engine to them, and calling them.
//!
//! Two interpreters serve a ruleset:
//! - the main one (`Vm<Game>`, host = the game) runs every hook that may change
//!   the game. A game checks it out of a slot it shares with its look-ahead
//!   copies (`Game::clone_state`), so the bot does not copy the Lua heap for
//!   every action it tries (a copy of a full pack's heap costs ~0.1 ms).
//!   Hence card scripts must keep no state of their own between calls: state
//!   belongs in the game (tags, enchantments).
//! - a read-only one (`Vm<Probe>`) runs the hooks the engine asks while it only
//!   reads the game (`&Game`: legal actions, costs): target filters, `can_play`,
//!   `cost_mod`, `cost_aura`. Its `g` has only the query functions.
//!
//! A script error ends the game as a draw with the reason (`Game::script_error`),
//! never a panic.

use crate::cards::{Base, Fx, HookSet, SecretH, TSpec};
use crate::entity::{Id, NONE};
use crate::ruleset::{leak, Ruleset};
use crate::state::{Ev, Game};
use classichs_script::{call, compile_bytes, load, Args, Chunk, Error, Host, Value as L, Vm};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

type R = Result<Vec<L>, Error>;

/// A ruleset's scripts, loaded once: template interpreters every game copies from.
pub struct LuaRules {
    main: Vm<Game>,
    probe: Vm<Probe>,
    g_main: L,
    g_probe: L,
    /// Hook functions: (main interpreter, read-only interpreter or nil).
    fns: Vec<(L, L)>,
    pool: Mutex<Vec<Probe>>,
}

/// The host of the read-only interpreter: a pointer to the game it is asked
/// about, set only while `Game::probe` runs a hook (which holds `&Game` meanwhile).
pub struct Probe {
    vm: Vm<Probe>,
    game: *const Game,
}

// SAFETY: `game` is null except during `Game::probe`, on the thread that holds the `&Game`.
unsafe impl Send for Probe {}

impl Host for Probe {
    fn vm(&mut self) -> &mut Vm<Probe> {
        &mut self.vm
    }
}

impl Host for Game {
    fn vm(&mut self) -> &mut Vm<Game> {
        self.lua.cur.as_mut().expect("a Lua call without its interpreter")
    }
}

/// The interpreter of a game: shared with its look-ahead copies, checked out for a call.
#[derive(Default)]
pub struct LuaSlot {
    shared: Arc<Mutex<Option<Box<Vm<Game>>>>>,
    pub(crate) cur: Option<Box<Vm<Game>>>,
}

impl LuaSlot {
    /// The same interpreter (a look-ahead copy).
    pub fn share(&self) -> LuaSlot {
        LuaSlot { shared: self.shared.clone(), cur: None }
    }
    /// A copy of the interpreter (an independent game).
    pub fn deep(&self) -> LuaSlot {
        let vm = self.shared.lock().unwrap_or_else(|e| e.into_inner()).clone();
        LuaSlot { shared: Arc::new(Mutex::new(vm)), cur: None }
    }
    fn checkout(&self, lr: &LuaRules) -> Box<Vm<Game>> {
        let free = self.shared.lock().unwrap_or_else(|e| e.into_inner()).take();
        free.unwrap_or_else(|| Box::new(lr.main.clone()))
    }
    fn checkin(&self, vm: Box<Vm<Game>>) {
        let mut s = self.shared.lock().unwrap_or_else(|e| e.into_inner());
        if s.is_none() {
            *s = Some(vm);
        }
    }
}

/// What a hook context gives the query functions: the game.
pub trait Ctx: Host {
    fn game(&self) -> Result<&Game, Error>;
}

impl Ctx for Game {
    fn game(&self) -> Result<&Game, Error> {
        Ok(self)
    }
}

impl Ctx for Probe {
    fn game(&self) -> Result<&Game, Error> {
        if self.game.is_null() {
            return Err(Error::fatal("the game is not available here (a script's top level)"));
        }
        // SAFETY: see `Probe`; the pointer is valid while a probe call runs.
        Ok(unsafe { &*self.game })
    }
}

// --- loading ---------------------------------------------------------------------------------

fn err(e: Error) -> String {
    e.to_string()
}

/// Loads a pack's scripts: `scripts/lib.lua` first (its table becomes the global `lib`),
/// then the others in path order; every key of a card file's table is a hook set.
pub(crate) fn build(rs: &Ruleset, scripts: &[(&String, &Vec<u8>)]) -> Result<(Option<LuaRules>, HashMap<String, HookSet>), String> {
    if scripts.is_empty() {
        return Ok((None, HashMap::new()));
    }
    let mut order: Vec<(&String, Chunk)> = vec![];
    for (p, b) in scripts {
        order.push((p, compile_bytes(p, &crate::pack::lua_text(b)).map_err(err)?));
    }
    order.sort_by_key(|(p, _)| (p.as_str() != "scripts/lib.lua", p.to_string()));
    let mut main = Vm::<Game>::new();
    let g_main = main.lib("g", &[QUERIES_MAIN, ACTIONS].concat());
    let mut host = Game::loader();
    host.lua.cur = Some(Box::new(main));
    let mut probe = Probe { vm: Vm::new(), game: std::ptr::null() };
    let g_probe = probe.vm.lib("g", QUERIES_PROBE);
    for (p, chunk) in &order {
        let m = load(&mut host, p, chunk).map_err(err)?;
        let mp = load(&mut probe, p, chunk).map_err(err)?;
        if p.as_str() == "scripts/lib.lua" {
            host.vm().set_global("lib", m);
            probe.vm.set_global("lib", mp);
        } else if !matches!(m, L::Table(_)) {
            return Err(format!("{p}: must return a table of cards"));
        }
    }
    let main = *host.lua.cur.take().unwrap();
    let mut fns = vec![];
    let mut sets: HashMap<(String, String), HookSet> = HashMap::new();
    for (p, _) in order.iter().filter(|(p, _)| p.as_str() != "scripts/lib.lua") {
        let (mt, pt) = (main.module(p), probe.vm.module(p));
        for (k, v) in main.pairs(&mt).map_err(err)? {
            let key = k.as_str().ok_or(format!("{p}: a key that is not a card id"))?.to_string();
            let mut ps = Parse { m: &main, p: &probe.vm, fns: &mut fns, at: format!("{p}: {key}") };
            let pv = probe.vm.get(&pt, k.clone()).map_err(err)?;
            let hs = ps.hooks(&v, &pv)?;
            sets.insert((p.to_string(), key), hs);
        }
    }
    let mut hooks = HashMap::new();
    for ((file, key), hs) in &sets {
        if !rs.cards.contains_key(key) && hooks.insert(key.clone(), hs.clone()).is_some() {
            return Err(format!("{file}: {key} is defined twice"));
        }
    }
    for c in rs.cards.values().filter(|c| !c.script.is_empty()) {
        let (file, key) = c.script.split_once('#').ok_or(format!("{}: script {} has no #<key>", c.id, c.script))?;
        let hs = sets.get(&(file.to_string(), key.to_string())).ok_or(format!("{}: no hooks {}", c.id, c.script))?;
        hooks.insert(c.id.clone(), hs.clone());
    }
    let mut main = main;
    for (p, _) in &order {
        let (m, pm) = (main.module(p), probe.vm.module(p));
        freeze(&mut main, &m, 3);
        freeze(&mut probe.vm, &pm, 3);
    }
    let lr = LuaRules { main, probe: probe.vm, g_main, g_probe, fns, pool: Mutex::new(vec![]) };
    Ok((Some(lr), hooks))
}

/// Makes a module's tables read-only (hook sets and their `on`, `secret`, … tables): hooks
/// can't keep state in them.
fn freeze<H>(vm: &mut Vm<H>, t: &L, depth: u32) {
    if depth == 0 || !matches!(t, L::Table(_)) {
        return;
    }
    vm.freeze(t);
    for (_, v) in vm.pairs(t).unwrap_or_default() {
        freeze(vm, &v, depth - 1);
    }
}

struct Parse<'a> {
    m: &'a Vm<Game>,
    p: &'a Vm<Probe>,
    fns: &'a mut Vec<(L, L)>,
    at: String,
}

impl Parse<'_> {
    fn bad(&self, what: &str) -> String {
        format!("{}: {what}", self.at)
    }

    /// A function field; `ro`: also from the read-only interpreter.
    fn func(&mut self, v: &L, pv: &L, field: &str, ro: bool) -> Result<u32, String> {
        if !matches!(v, L::Func(_)) {
            return Err(self.bad(&format!("{field} must be a function")));
        }
        self.fns.push((v.clone(), if ro { pv.clone() } else { L::Nil }));
        Ok(self.fns.len() as u32 - 1)
    }

    fn get(&self, t: &L, pt: &L, k: &str) -> (L, L) {
        (self.m.get(t, k).unwrap_or_default(), self.p.get(pt, k).unwrap_or_default())
    }

    fn spec(&mut self, v: &L, pv: &L, field: &str) -> Result<TSpec, String> {
        let base_of = |s: &str| -> Option<Base> {
            Some(match s {
                "any" => Base::Any,
                "minion" => Base::Minion,
                "enemy_minion" => Base::EnemyMinion,
                "friendly_minion" => Base::FriendlyMinion,
                "enemy_char" => Base::EnemyChar,
                "friendly_char" => Base::FriendlyChar,
                "enemy_hero" => Base::EnemyHero,
                _ => return None,
            })
        };
        if let Some(s) = v.as_str() {
            return Ok(TSpec { base: base_of(s).ok_or(self.bad(&format!("{field}: unknown target {s:?}")))?, pred: None });
        }
        let (b, pb) = self.get(v, pv, "base");
        let base = b.as_str().and_then(base_of).ok_or(self.bad(&format!("{field}.base: a target kind expected")))?;
        let (f, pf) = self.get(v, pv, "filter");
        let pred = if f.is_nil() { None } else { Some(Fx::Lua(self.func(&f, &pf, "filter", true)?)) };
        let _ = pb;
        Ok(TSpec { base, pred })
    }

    fn hooks(&mut self, t: &L, pt: &L) -> Result<HookSet, String> {
        if !matches!(t, L::Table(_)) {
            return Err(self.bad("hooks must be a table"));
        }
        let mut h = HookSet { lua: true, ..HookSet::default() };
        for (k, v) in self.m.pairs(t).map_err(err)? {
            let key = k.as_str().unwrap_or("?").to_string();
            let pv = self.p.get(pt, k.clone()).unwrap_or_default();
            macro_rules! f {
                ($ro:expr) => {
                    Fx::Lua(self.func(&v, &pv, &key, $ro)?)
                };
            }
            match key.as_str() {
                "target" => h.target = Some(self.spec(&v, &pv, &key)?),
                "combo_target" => h.combo_target = Some(self.spec(&v, &pv, &key)?),
                "battlecry" | "on_play" => h.battlecry = Some(f!(false)),
                "spell" => h.spell = Some(f!(false)),
                "combo" => h.combo = Some(f!(false)),
                "effect" => h.effect = Some(f!(false)),
                "hero_power" => h.hero_power = Some(f!(false)),
                "deathrattle" | "on_death" => h.deathrattle = Some(f!(false)),
                "aura" => h.aura = Some(f!(false)),
                "aura_final" => h.aura_final = Some(f!(false)),
                "on_choose" => h.on_choose = Some(f!(false)),
                "durability_on_attack" => h.durability_on_attack = Some(f!(false)),
                "can_play" => h.can_play = Some(f!(true)),
                "cost_mod" => h.cost_mod = Some(f!(true)),
                "cost_aura" => h.cost_aura = Some(f!(true)),
                "immune_while_attacking" => h.immune_while_attacking = v.truthy(),
                "choose_one" => {
                    let o = self.m.list_items(&v).map_err(err)?;
                    match (o.first().and_then(L::as_str), o.get(1).and_then(L::as_str), o.len()) {
                        (Some(a), Some(b), 2) => h.choose_one = Some([leak(a), leak(b)]),
                        _ => return Err(self.bad("choose_one must be a list of two card ids")),
                    }
                }
                "on" | "now" => {
                    for (ek, ev) in self.m.pairs(&v).map_err(err)? {
                        let name = ek.as_str().ok_or(self.bad(&format!("{key}: event names are strings")))?;
                        let fi = self.func(&ev, &L::Nil, &format!("{key}.{name}"), false)?;
                        if key == "on" {
                            h.on.push((leak(name), Fx::Lua(fi)));
                        } else {
                            h.now.push((leak(name), Fx::Lua(fi)));
                        }
                    }
                }
                "secret" | "trap" => {
                    let (e, _) = self.get(&v, &pv, "event");
                    let event = leak(e.as_str().ok_or(self.bad("secret.event must be an event name"))?);
                    let (c, _) = self.get(&v, &pv, "cond");
                    let cond = if c.is_nil() { None } else { Some(Fx::Lua(self.func(&c, &L::Nil, "secret.cond", false)?)) };
                    let (x, _) = self.get(&v, &pv, "effect");
                    let effect = Fx::Lua(self.func(&x, &L::Nil, "secret.effect", false)?);
                    h.secret = Some(SecretH { event, cond, effect });
                }
                _ => return Err(self.bad(&format!("unknown hook '{key}'"))),
            }
        }
        Ok(h)
    }
}

// --- calling hooks ---------------------------------------------------------------------------

fn id(e: Id) -> L {
    if e == NONE { L::Nil } else { L::Int(e) }
}

/// JSON → Lua (events, enchantments).
fn to_lua<H>(vm: &mut Vm<H>, v: &Value, depth: u32) -> Result<L, Error> {
    if depth > 16 {
        return Err(Error::runtime("value nested too deep"));
    }
    Ok(match v {
        Value::Null => L::Nil,
        Value::Bool(b) => L::Bool(*b),
        Value::Number(_) => L::Int(crate::entity::int(Some(v))),
        Value::String(s) => L::from(s.as_str()),
        Value::Array(a) => {
            let mut items = vec![];
            for x in a {
                items.push(to_lua(vm, x, depth + 1)?);
            }
            vm.list(items)?
        }
        Value::Object(m) => {
            let t = vm.new_table();
            for (k, x) in m {
                let x = to_lua(vm, x, depth + 1)?;
                vm.set(&t, k.as_str(), x)?;
            }
            t
        }
    })
}

/// Lua → JSON: a table with keys 1..n is an array, other tables objects (string keys).
fn to_json<H>(vm: &Vm<H>, v: &L, depth: u32) -> Result<Value, Error> {
    if depth > 16 {
        return Err(Error::runtime("table nested too deep (or a cycle)"));
    }
    Ok(match v {
        L::Nil => Value::Null,
        L::Bool(b) => Value::Bool(*b),
        L::Int(i) => json!(i),
        L::Str(_) => Value::String(v.as_str().map(String::from).unwrap_or_else(|| vm.display(v))),
        L::Table(_) => {
            let items = vm.pairs(v)?;
            if items.iter().enumerate().all(|(i, (k, _))| *k == L::Int(i as i64 + 1)) && !items.is_empty() {
                let mut a = vec![];
                for (_, x) in &items {
                    a.push(to_json(vm, x, depth + 1)?);
                }
                Value::Array(a)
            } else {
                let mut m = Map::new();
                for (k, x) in &items {
                    let key = match k {
                        L::Str(_) => k.as_str().unwrap_or("").to_string(),
                        L::Int(i) => i.to_string(),
                        _ => return Err(Error::runtime("table keys must be strings or numbers")),
                    };
                    m.insert(key, to_json(vm, x, depth + 1)?);
                }
                Value::Object(m)
            }
        }
        _ => return Err(Error::runtime("a function can't be stored in the game")),
    })
}

fn empty(v: &Value) -> bool {
    matches!(v, Value::Array(a) if a.is_empty()) || matches!(v, Value::Object(o) if o.is_empty())
}

/// Copies the fields a hook changed in its event table back to the event.
fn write_back(g: &mut Game, t: &L, ev: &mut Ev) -> Result<(), Error> {
    let Value::Object(b) = to_json(g.vm(), t, 0)? else { return Ok(()) };
    for (k, v) in &b {
        match ev.get(k) {
            Some(old) if old == v || (empty(old) && empty(v)) => {}
            _ => {
                ev.insert(k.clone(), v.clone());
            }
        }
    }
    ev.retain(|k, v| b.contains_key(k) || v.is_null());
    Ok(())
}

impl Game {
    /// Runs Lua hook function `f` of the main interpreter: `args` builds the
    /// arguments after `g`, `after` reads the results (and gets the arguments,
    /// `g` first). None if the script failed
    /// (the game is then over).
    fn lua<T>(&mut self, f: u32, args: impl FnOnce(&mut Game) -> Result<Vec<L>, Error>,
        after: impl FnOnce(&mut Game, Vec<L>, &[L]) -> Result<T, Error>) -> Option<T> {
        if self.script_error.get().is_some() {
            return None;
        }
        let lr = self.rs.lua.as_ref()?;
        let top = self.lua.cur.is_none();
        if top {
            self.lua.cur = Some(self.lua.checkout(lr));
        }
        let r = (|| {
            let mut a = vec![lr.g_main.clone()];
            a.extend(args(self)?);
            let out = call(self, &lr.fns[f as usize].0, &a)?;
            after(self, out, &a)
        })();
        if top {
            if let Some(vm) = self.lua.cur.take() {
                self.lua.checkin(vm);
            }
        }
        match r {
            Ok(v) => Some(v),
            Err(e) => {
                self.script_failed(&e);
                None
            }
        }
    }

    /// Runs a read-only hook (`&self`): the first result, or None if it failed
    /// (the error ends the game at the next step).
    fn probe(&self, f: u32, args: &[L]) -> Option<L> {
        if self.script_error.get().is_some() {
            return None;
        }
        let lr = self.rs.lua.as_ref()?;
        let free = lr.pool.lock().unwrap_or_else(|e| e.into_inner()).pop();
        let mut p = free.unwrap_or_else(|| Probe { vm: lr.probe.clone(), game: std::ptr::null() });
        p.game = self as *const Game;
        let mut a = vec![lr.g_probe.clone()];
        a.extend_from_slice(args);
        let r = call(&mut p, &lr.fns[f as usize].1, &a);
        p.game = std::ptr::null();
        lr.pool.lock().unwrap_or_else(|e| e.into_inner()).push(p);
        match r {
            Ok(v) => Some(v.into_iter().next().unwrap_or_default()),
            Err(e) => {
                let _ = self.script_error.set(script_message(&e));
                None
            }
        }
    }

    /// Ends the game after a script error: a draw, with the reason in the event.
    pub(crate) fn script_failed(&mut self, e: &Error) {
        let _ = self.script_error.set(script_message(e));
        self.end_by_script_error();
    }

    pub(crate) fn end_by_script_error(&mut self) {
        let Some(msg) = self.script_error.get().cloned() else { return };
        if self.game_over {
            return;
        }
        self.game_over = true;
        self.phase = "OVER";
        self.winner = -1;
        self.queue.clear();
        self.log_event(json!({"type": "game_over", "winner": -1, "reason": "script_error", "error": msg}));
    }

    pub(crate) fn fx_effect(&mut self, f: Fx<crate::cards::Effect>, me: Id, t: Id) {
        match f {
            Fx::Rust(f) => f(self, me, t),
            Fx::Lua(i) => {
                self.lua(i, |_| Ok(vec![L::Int(me), id(t)]), |_, _, _| Ok(()));
            }
        }
    }

    pub(crate) fn fx_me(&mut self, f: Fx<fn(&mut Game, Id)>, me: Id) {
        match f {
            Fx::Rust(f) => f(self, me),
            Fx::Lua(i) => {
                self.lua(i, |_| Ok(vec![L::Int(me)]), |_, _, _| Ok(()));
            }
        }
    }

    /// An event hook; changes to the event table go back to the logged event.
    pub(crate) fn fx_on(&mut self, f: Fx<crate::cards::OnFn>, me: Id, ev: usize) {
        match f {
            Fx::Rust(f) => f(self, me, ev),
            Fx::Lua(i) => {
                self.lua(
                    i,
                    |g| {
                        let e = Value::Object(g.event_log[ev].clone());
                        Ok(vec![L::Int(me), to_lua(g.vm(), &e, 0)?])
                    },
                    |g, _, a| {
                        let mut e = std::mem::take(&mut g.event_log[ev]);
                        let r = write_back(g, &a[2], &mut e);
                        g.event_log[ev] = e;
                        r
                    },
                );
            }
        }
    }

    pub(crate) fn fx_now(&mut self, f: Fx<crate::cards::NowFn>, me: Id, ev: &mut Ev) {
        match f {
            Fx::Rust(f) => f(self, me, ev),
            Fx::Lua(i) => {
                let src = Value::Object(ev.clone());
                self.lua(i, |g| Ok(vec![L::Int(me), to_lua(g.vm(), &src, 0)?]), |g, _, a| write_back(g, &a[2], ev));
            }
        }
    }

    pub(crate) fn fx_cond(&mut self, f: Fx<crate::cards::SecretCond>, me: Id, ev: usize) -> bool {
        match f {
            Fx::Rust(f) => f(self, me, ev),
            Fx::Lua(i) => self
                .lua(i, |g| {
                        let e = Value::Object(g.event_log[ev].clone());
                        Ok(vec![L::Int(me), to_lua(g.vm(), &e, 0)?])
                    }, |_, r, _| {
                    Ok(r.first().is_some_and(L::truthy))
                })
                .unwrap_or(false),
        }
    }

    pub(crate) fn fx_choose(&mut self, f: Fx<crate::cards::OnChoose>, me: Id, opt: Id, still: Vec<Id>) {
        match f {
            Fx::Rust(f) => f(self, me, opt, still),
            Fx::Lua(i) => {
                self.lua(i, |g| Ok(vec![L::Int(me), L::Int(opt), g.vm().list(still.into_iter().map(L::Int).collect())?]), |_, _, _| {
                    Ok(())
                });
            }
        }
    }

    pub(crate) fn fx_dur(&mut self, f: Fx<crate::cards::DurFn>, w: Id, d: Id) -> bool {
        match f {
            Fx::Rust(f) => f(self, w, d),
            Fx::Lua(i) => self.lua(i, |_| Ok(vec![L::Int(w), L::Int(d)]), |_, r, _| Ok(r.first().is_some_and(L::truthy))).unwrap_or(true),
        }
    }

    pub(crate) fn fx_can_play(&self, f: Fx<crate::cards::CanPlay>, me: Id) -> bool {
        match f {
            Fx::Rust(f) => f(self, me),
            Fx::Lua(i) => self.probe(i, &[L::Int(me)]).is_some_and(|v| v.truthy()),
        }
    }

    pub(crate) fn fx_pred(&self, f: Fx<crate::cards::Pred>, me: Id, t: Id) -> bool {
        match f {
            Fx::Rust(f) => f(self, me, t),
            Fx::Lua(i) => self.probe(i, &[L::Int(me), L::Int(t)]).is_some_and(|v| v.truthy()),
        }
    }

    pub(crate) fn fx_cost_mod(&self, f: Fx<crate::cards::CostMod>, me: Id) -> i64 {
        match f {
            Fx::Rust(f) => f(self, me),
            Fx::Lua(i) => self.probe(i, &[L::Int(me)]).and_then(|v| v.as_int()).unwrap_or(0),
        }
    }

    pub(crate) fn fx_cost_aura(&self, f: Fx<crate::cards::CostAura>, me: Id, card: Id, c: i64) -> i64 {
        match f {
            Fx::Rust(f) => f(self, me, card, c),
            Fx::Lua(i) => self.probe(i, &[L::Int(me), L::Int(card), L::Int(c)]).and_then(|v| v.as_int()).unwrap_or(c),
        }
    }
}

fn script_message(e: &Error) -> String {
    let mut m = e.message.clone();
    if let Some(t) = e.traceback.first() {
        if !m.contains(t.as_str()) {
            m = format!("{m} ({t})");
        }
    }
    m
}

// --- the `g` library -------------------------------------------------------------------------

const LIMIT: i64 = 1_000_000;

fn one(v: impl Into<L>) -> R {
    Ok(vec![v.into()])
}

fn none() -> R {
    Ok(vec![])
}

fn ent(g: &Game, a: &Args, i: usize) -> Result<Id, Error> {
    match a.get(i) {
        L::Int(n) if n >= 1 && n < g.next_id => Ok(n),
        v => Err(a.bad(i, &format!("entity expected, got {}", if v.is_nil() { "nil".into() } else { format!("{v:?}") }))),
    }
}

/// An entity or nil/-1 (NONE): actions on NONE do nothing.
fn opt_ent(g: &Game, a: &Args, i: usize) -> Result<Id, Error> {
    match a.get(i) {
        L::Nil | L::Int(-1) => Ok(NONE),
        _ => ent(g, a, i),
    }
}

fn player(a: &Args, i: usize) -> Result<usize, Error> {
    match a.get(i) {
        L::Int(n @ 0..=1) => Ok(n as usize),
        v => Err(a.bad(i, &format!("player expected (0 or 1), got {}", v.type_name()))),
    }
}

fn num(a: &Args, i: usize, def: i64) -> Result<i64, Error> {
    Ok(a.opt_int(i)?.unwrap_or(def).clamp(-LIMIT, LIMIT))
}

fn card_arg(g: &Game, a: &Args, i: usize, kind: &str) -> Result<String, Error> {
    let c = a.string(i)?;
    match g.rs.cards.get(&c) {
        None => Err(a.bad(i, &format!("unknown card '{c}'"))),
        Some(x) if !kind.is_empty() && x.kind != kind => Err(a.bad(i, &format!("'{c}' is not a {}", type_name(kind)))),
        _ => Ok(c),
    }
}

fn tag_arg(g: &Game, a: &Args, i: usize) -> Result<String, Error> {
    Ok(g.rs.names.tag(&a.string(i)?).to_string())
}

/// The pack's type name of an engine kind.
fn type_name(kind: &str) -> &str {
    match kind {
        "HERO" => "CHAMPION",
        "HERO_POWER" => "POWER",
        k => k,
    }
}

fn zone_name(g: &Game, z: &str) -> &'static str {
    match z {
        "DECK" => "DECK",
        "HAND" => "HAND",
        "PLAY" => "PLAY",
        "GRAVEYARD" => "GRAVEYARD",
        "SETASIDE" => "SETASIDE",
        _ if z == g.rs.names.trap || z == "TRAP" => g.rs.names.trap,
        _ => "",
    }
}

fn ids<C: Ctx>(h: &mut C, v: Vec<Id>) -> R {
    Ok(vec![h.vm().list(v.into_iter().map(L::Int).collect())?])
}

fn live(g: &Game) -> Result<(), Error> {
    if g.script_error.get().is_some() {
        return Err(Error::fatal("the game ended: a card script failed"));
    }
    Ok(())
}

macro_rules! q {
    ($name:ident, |$g:ident, $a:ident| $body:expr) => {
        fn $name<C: Ctx>(h: &mut C, $a: Args) -> R {
            let v = {
                let $g = h.game()?;
                $body
            };
            v
        }
    };
}

macro_rules! ql {
    ($name:ident, |$g:ident, $a:ident| $body:expr) => {
        fn $name<C: Ctx>(h: &mut C, $a: Args) -> R {
            let v: Vec<Id> = {
                let $g = h.game()?;
                $body
            };
            ids(h, v)
        }
    };
}

q!(q_ctrl, |g, a| one(g.ctrl(ent(g, &a, 0)?) as i64));
q!(q_enemy, |g, a| one(g.foe(ent(g, &a, 0)?) as i64));
q!(q_opponent, |_g, a| one(1 - player(&a, 0)? as i64));
q!(q_hero, |g, a| one(g.hero(player(&a, 0)?)));
q!(q_power, |g, a| one(g.players[player(&a, 0)?].hero_power));
q!(q_weapon, |g, a| Ok(vec![g.weapon(player(&a, 0)?).map_or(L::Nil, L::Int)]));
ql!(q_minions, |g, a| g.minions(player(&a, 0)?));
ql!(q_all_minions, |g, _a| g.all_minions());
ql!(q_chars, |g, a| g.chars(player(&a, 0)?));
ql!(q_all_chars, |g, _a| g.all_chars());
ql!(q_others, |g, a| g.others(ent(g, &a, 0)?));
ql!(q_adjacent, |g, a| g.adjacent(ent(g, &a, 0)?));
ql!(q_hand, |g, a| g.players[player(&a, 0)?].hand.clone());
ql!(q_deck, |g, a| g.players[player(&a, 0)?].deck.clone());
ql!(q_traps, |g, a| g.players[player(&a, 0)?].secrets.clone());
q!(q_card, |g, a| one(g.e(ent(g, &a, 0)?).card_id.as_str()));
q!(q_type, |g, a| one(type_name(g.e(ent(g, &a, 0)?).kind())));
q!(q_race, |g, a| one(g.e(ent(g, &a, 0)?).race()));
q!(q_class, |g, a| one(g.e(ent(g, &a, 0)?).card.card_class.as_str()));
q!(q_zone, |g, a| one(g.e(ent(g, &a, 0)?).zone));
q!(q_atk, |g, a| one(g.e(ent(g, &a, 0)?).atk()));
q!(q_attack, |g, a| one(g.attack_value(ent(g, &a, 0)?)));
q!(q_health, |g, a| one(g.e(ent(g, &a, 0)?).health()));
q!(q_max_health, |g, a| one(g.e(ent(g, &a, 0)?).max_health()));
q!(q_dmg, |g, a| one(g.e(ent(g, &a, 0)?).damage));
q!(q_has, |g, a| one(g.e(ent(g, &a, 0)?).has(&tag_arg(g, &a, 1)?)));
q!(q_tag, |g, a| {
    let (e, t) = (ent(g, &a, 0)?, tag_arg(g, &a, 1)?);
    let x = g.e(e);
    one(x.tag(&t) + crate::entity::int(x.aura.tags.get(&t)))
});
q!(q_silenced, |g, a| one(g.e(ent(g, &a, 0)?).silenced));
q!(q_is_minion, |g, a| one(g.e(ent(g, &a, 0)?).is_minion()));
q!(q_is_champion, |g, a| one(g.e(ent(g, &a, 0)?).is_hero()));
q!(q_is_weapon, |g, a| one(g.e(ent(g, &a, 0)?).is_weapon()));
q!(q_is_spell, |g, a| one(g.e(ent(g, &a, 0)?).kind() == "SPELL"));
q!(q_turn, |g, _a| one(g.turn));
q!(q_current, |g, _a| one(g.current as i64));
q!(q_mana, |g, a| one(g.players[player(&a, 0)?].mana));
q!(q_max_mana, |g, a| one(g.players[player(&a, 0)?].max_mana));
q!(q_cards_played, |g, a| one(g.players[player(&a, 0)?].cards_played_this_turn));
q!(q_minions_played, |g, a| one(g.players[player(&a, 0)?].minions_played_this_turn));
q!(q_room, |g, a| one(g.rs.board.saturating_sub(g.players[player(&a, 0)?].board.len()) as i64));
q!(q_board_pos, |g, a| Ok(vec![g.board_pos(ent(g, &a, 0)?).map_or(L::Nil, |i| L::Int(i as i64))]));
q!(q_died_pos, |g, a| one(g.died_pos(ent(g, &a, 0)?)));
q!(q_trap_ready, |g, a| one(g.secret_ready(ent(g, &a, 0)?)));
q!(q_spell_dmg, |g, a| one(g.spell_dmg(ent(g, &a, 0)?, num(&a, 1, 0)?)));
q!(q_heal_amt, |g, a| one(g.heal_amt(ent(g, &a, 0)?, num(&a, 1, 0)?)));
q!(q_hp_dmg, |g, a| one(g.hp_dmg(ent(g, &a, 0)?, num(&a, 1, 0)?)));
q!(q_rule, |g, a| {
    let r = g.rs;
    one(match a.string(0)?.as_str() {
        "hand" => r.hand as i64,
        "board" => r.board as i64,
        "max_mana" => r.max_mana,
        "deck_size" => r.deck_size as i64,
        "champion_health" => r.champion_health,
        n => return Err(a.bad(0, &format!("unknown rule '{n}'"))),
    })
});
q!(q_combo, |g, a| one(g.combo_active(ent(g, &a, 0)?)));

fn q_mine<C: Ctx>(h: &mut C, a: Args) -> R {
    let p = h.vm().get(&a.table(1)?, "player")?;
    let g = h.game()?;
    one(p == L::Int(g.ctrl(ent(g, &a, 0)?) as i64))
}

fn q_enchants<C: Ctx>(h: &mut C, a: Args) -> R {
    let v: Vec<Id> = {
        let g = h.game()?;
        g.e(ent(g, &a, 0)?).ench_players(&a.string(1)?).into_iter().map(|p| p as i64).collect()
    };
    ids(h, v)
}

fn q_info<C: Ctx>(h: &mut C, a: Args) -> R {
    let v = {
        let g = h.game()?;
        let c = g.rs.card(&card_arg(g, &a, 0, "")?);
        json!({"id": c.id, "type": type_name(&c.kind), "class": c.card_class, "rarity": c.rarity, "set": c.set,
            "cost": c.cost, "attack": c.attack, "health": c.health, "durability": c.durability, "race": c.race,
            "mana_lock": c.overload, "spell_power": c.spell_damage.unwrap_or(0), "collectible": c.collectible,
            "keywords": c.mechanics, "trap": c.trap})
    };
    one(to_lua(h.vm(), &v, 0)?)
}

fn q_collectible<C: Ctx>(h: &mut C, _a: Args) -> R {
    let v: Vec<L> = h.game()?.rs.collectible.iter().map(|s| L::from(s.as_str())).collect();
    one(h.vm().list(v)?)
}

/// Query functions, for both interpreters.
macro_rules! queries {
    ($t:ty) => {
        &[
            ("g.ctrl", q_ctrl::<$t>), ("g.enemy", q_enemy::<$t>), ("g.opponent", q_opponent::<$t>),
            ("g.hero", q_hero::<$t>), ("g.power", q_power::<$t>), ("g.weapon", q_weapon::<$t>),
            ("g.minions", q_minions::<$t>), ("g.all_minions", q_all_minions::<$t>), ("g.chars", q_chars::<$t>),
            ("g.all_chars", q_all_chars::<$t>), ("g.others", q_others::<$t>), ("g.adjacent", q_adjacent::<$t>),
            ("g.hand", q_hand::<$t>), ("g.deck", q_deck::<$t>), ("g.traps", q_traps::<$t>), ("g.card", q_card::<$t>),
            ("g.type", q_type::<$t>), ("g.race", q_race::<$t>), ("g.class", q_class::<$t>), ("g.zone", q_zone::<$t>),
            ("g.atk", q_atk::<$t>), ("g.attack", q_attack::<$t>), ("g.health", q_health::<$t>),
            ("g.max_health", q_max_health::<$t>), ("g.dmg", q_dmg::<$t>), ("g.has", q_has::<$t>), ("g.tag", q_tag::<$t>),
            ("g.silenced", q_silenced::<$t>), ("g.is_minion", q_is_minion::<$t>), ("g.is_champion", q_is_champion::<$t>),
            ("g.is_weapon", q_is_weapon::<$t>), ("g.is_spell", q_is_spell::<$t>), ("g.turn", q_turn::<$t>),
            ("g.current", q_current::<$t>), ("g.mana", q_mana::<$t>), ("g.max_mana", q_max_mana::<$t>),
            ("g.cards_played", q_cards_played::<$t>), ("g.minions_played", q_minions_played::<$t>),
            ("g.room", q_room::<$t>), ("g.board_pos", q_board_pos::<$t>), ("g.died_pos", q_died_pos::<$t>),
            ("g.trap_ready", q_trap_ready::<$t>), ("g.spell_dmg", q_spell_dmg::<$t>), ("g.heal_amt", q_heal_amt::<$t>),
            ("g.hp_dmg", q_hp_dmg::<$t>), ("g.rule", q_rule::<$t>), ("g.combo", q_combo::<$t>), ("g.mine", q_mine::<$t>),
            ("g.enchants", q_enchants::<$t>), ("g.info", q_info::<$t>), ("g.collectible", q_collectible::<$t>),
        ]
    };
}

const QUERIES_MAIN: &[(&str, classichs_script::NativeFn<Game>)] = queries!(Game);
const QUERIES_PROBE: &[(&str, classichs_script::NativeFn<Probe>)] = queries!(Probe);

// --- actions (main interpreter only) -------------------------------------------------------

fn opt_id(e: Id) -> R {
    Ok(vec![id(e)])
}

fn a_damage(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (s, t, n) = (opt_ent(g, &a, 0)?, opt_ent(g, &a, 1)?, num(&a, 2, 0)?);
    one(g.damage(s, t, n))
}
fn a_heal(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (s, t, n) = (opt_ent(g, &a, 0)?, opt_ent(g, &a, 1)?, num(&a, 2, 0)?);
    one(g.heal(s, t, n))
}
fn a_destroy(g: &mut Game, a: Args) -> R {
    live(g)?;
    let e = opt_ent(g, &a, 0)?;
    g.destroy(e);
    none()
}
fn a_summon(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, c, pos) = (player(&a, 0)?, card_arg(g, &a, 1, "MINION")?, num(&a, 2, -1)?);
    opt_id(g.summon(p, &c, pos))
}
fn a_summon_right(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (me, c) = (ent(g, &a, 0)?, card_arg(g, &a, 1, "MINION")?);
    opt_id(g.summon_right(me, &c))
}
fn a_summon_entity(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, pos) = (ent(g, &a, 0)?, num(&a, 1, -1)?);
    if !g.e(e).is_minion() || g.e(e).zone == "PLAY" {
        return Err(a.bad(0, "a minion card that is not in play expected"));
    }
    let c = g.ctrl(e);
    let pl = &mut g.players[c];
    pl.hand.retain(|&x| x != e);
    pl.deck.retain(|&x| x != e);
    opt_id(g.summon_entity(e, pos))
}
fn a_draw(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, n) = (player(&a, 0)?, num(&a, 1, 1)?.clamp(0, 100));
    let v = g.draw(p, n);
    ids(g, v)
}
fn a_draw_entity(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, e) = (player(&a, 0)?, ent(g, &a, 1)?);
    g.draw_entity(p, e);
    none()
}
fn a_add_to_hand(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, c) = (player(&a, 0)?, card_arg(g, &a, 1, "")?);
    opt_id(g.add_to_hand(p, &c))
}
fn a_discard_random(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, n) = (player(&a, 0)?, num(&a, 1, 1)?.clamp(0, 100));
    g.discard_random(p, n);
    none()
}
fn a_discard(g: &mut Game, a: Args) -> R {
    live(g)?;
    let e = ent(g, &a, 0)?;
    let p = g.ctrl(e);
    if g.players[p].hand.contains(&e) {
        g.players[p].hand.retain(|&x| x != e);
        g.em(e).zone = "GRAVEYARD";
        let card = g.e(e).card_id.clone();
        g.emit(json!({"type": "discard", "player": p, "entity": e, "card": card}));
    }
    none()
}
fn a_buff(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, at, hp) = (opt_ent(g, &a, 0)?, num(&a, 1, 0)?, num(&a, 2, 0)?);
    if e != NONE {
        g.buff(e, at, hp, a.get(3).truthy());
    }
    none()
}
fn a_set_stats(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, at, hp) = (opt_ent(g, &a, 0)?, num(&a, 1, -1)?, num(&a, 2, -1)?);
    if e != NONE {
        g.set_stats(e, at.max(-1), hp.max(-1));
    }
    none()
}
fn a_silence(g: &mut Game, a: Args) -> R {
    live(g)?;
    let e = opt_ent(g, &a, 0)?;
    if e != NONE {
        g.silence(e);
    }
    none()
}
fn a_freeze(g: &mut Game, a: Args) -> R {
    live(g)?;
    let e = opt_ent(g, &a, 0)?;
    g.freeze(e);
    none()
}
fn a_transform(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, c) = (opt_ent(g, &a, 0)?, card_arg(g, &a, 1, "MINION")?);
    opt_id(if e == NONE { NONE } else { g.transform(e, &c) })
}
fn a_return_to_hand(g: &mut Game, a: Args) -> R {
    live(g)?;
    let e = opt_ent(g, &a, 0)?;
    opt_id(if e == NONE { NONE } else { g.return_to_hand(e) })
}
fn a_take_control(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, p) = (opt_ent(g, &a, 0)?, player(&a, 1)?);
    if e != NONE {
        g.take_control(e, p);
    }
    none()
}
fn a_copy_minion(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (me, t) = (ent(g, &a, 0)?, ent(g, &a, 1)?);
    opt_id(g.copy_minion(me, t))
}
fn a_equip(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, c) = (player(&a, 0)?, card_arg(g, &a, 1, "WEAPON")?);
    one(g.equip(p, &c))
}
fn a_gain_armor(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, n) = (player(&a, 0)?, num(&a, 1, 0)?);
    g.gain_armor(p, n);
    none()
}
fn a_gain_mana(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, n) = (player(&a, 0)?, num(&a, 1, 1)?.clamp(0, 100));
    g.gain_mana(p, n, a.get(2).truthy());
    none()
}
fn a_add_mana(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, n) = (player(&a, 0)?, num(&a, 1, 1)?);
    let max = g.rs.max_mana;
    let pl = &mut g.players[p];
    pl.mana = max.min(pl.mana + n);
    none()
}
fn a_set_mana(g: &mut Game, a: Args) -> R {
    live(g)?;
    let p = player(&a, 0)?;
    let (mana, max) = (a.opt_int(1)?, a.opt_int(2)?);
    let cap = g.rs.max_mana;
    let pl = &mut g.players[p];
    if let Some(m) = max {
        pl.max_mana = m.clamp(0, cap);
    }
    if let Some(m) = mana {
        pl.mana = m.clamp(0, LIMIT);
    }
    none()
}
fn a_set_tag(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, t) = (ent(g, &a, 0)?, tag_arg(g, &a, 1)?);
    match a.get(2) {
        L::Nil => g.em(e).erase_tag(&t),
        L::Bool(b) => g.em(e).set_tag(&t, json!(b)),
        L::Int(n) => g.em(e).set_tag(&t, json!(n.clamp(-LIMIT, LIMIT))),
        L::Str(_) => g.em(e).set_tag(&t, json!(a.string(2)?)),
        _ => return Err(a.bad(2, "a boolean, number, string or nil expected")),
    }
    none()
}
fn a_give_tag(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, t) = (opt_ent(g, &a, 0)?, tag_arg(g, &a, 1)?);
    if e != NONE {
        g.em(e).give_tag(&t, a.get(2).truthy());
    }
    none()
}
fn a_erase_tag(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, t) = (opt_ent(g, &a, 0)?, tag_arg(g, &a, 1)?);
    if e != NONE {
        g.em(e).erase_tag(&t);
    }
    none()
}
fn a_add_tag(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, t, n) = (opt_ent(g, &a, 0)?, tag_arg(g, &a, 1)?, num(&a, 2, 1)?);
    if e != NONE {
        g.add_tag_int(e, &t, n);
    }
    none()
}
fn a_set_damage(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, n) = (ent(g, &a, 0)?, num(&a, 1, 0)?);
    g.em(e).damage = n.max(0);
    none()
}
fn a_enchant(g: &mut Game, a: Args) -> R {
    live(g)?;
    let e = ent(g, &a, 0)?;
    let v = to_json(g.vm(), &a.table(1)?, 0)?;
    match v {
        Value::Object(m) => g.em(e).enchantments.push(m),
        _ => return Err(a.bad(1, "a table with named fields expected")),
    }
    none()
}
fn a_remove_enchant(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (e, hooks) = (ent(g, &a, 0)?, a.string(1)?);
    g.em(e).enchantments.retain(|x| x.get("hooks").and_then(Value::as_str) != Some(hooks.as_str()));
    none()
}
fn a_aura_add(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (t, at, hp) = (ent(g, &a, 0)?, num(&a, 1, 0)?, num(&a, 2, 0)?);
    let mut tags: Vec<(String, Value)> = vec![];
    if let L::Table(_) = a.get(3) {
        for (k, v) in g.vm().pairs(&a.get(3))? {
            let name = g.rs.names.tag(k.as_str().ok_or_else(|| a.bad(3, "tag names must be strings"))?).to_string();
            tags.push((name, to_json(g.vm(), &v, 0)?));
        }
    }
    let tags: Vec<(&str, Value)> = tags.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
    g.aura_add(t, at, hp, &tags);
    none()
}
fn a_replace_hero(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, c) = (player(&a, 0)?, card_arg(g, &a, 1, "HERO")?);
    one(g.replace_hero(p, &c))
}
fn a_set_power(g: &mut Game, a: Args) -> R {
    live(g)?;
    let (p, c) = (player(&a, 0)?, card_arg(g, &a, 1, "HERO_POWER")?);
    one(g.set_hero_power(p, &c))
}
fn a_reveal(g: &mut Game, a: Args) -> R {
    live(g)?;
    let e = ent(g, &a, 0)?;
    if g.e(e).zone == g.rs.names.trap {
        g.reveal(e);
    }
    none()
}
fn a_request_choice(g: &mut Game, a: Args) -> R {
    live(g)?;
    let me = ent(g, &a, 0)?;
    let mut opts = vec![];
    for (k, v) in g.vm().list_items(&a.table(1)?)?.into_iter().enumerate() {
        match v {
            L::Int(n) if n >= 1 && n < g.next_id => opts.push(n),
            _ => return Err(a.bad(1, &format!("item {} is not an entity", k + 1))),
        }
    }
    if !opts.is_empty() {
        g.request_choice(me, opts);
    }
    none()
}
fn a_add_cost_mod(g: &mut Game, a: Args) -> R {
    live(g)?;
    let p = player(&a, 0)?;
    let m = to_json(g.vm(), &a.table(1)?, 0)?;
    let Some(turn) = m.as_object().map(|o| o.get("turn").cloned()) else { return Err(a.bad(1, "a table expected")) };
    g.add_cost_mod(p, m);
    if let (Some(t), Some(last)) = (turn, g.players[p].cost_mods.last_mut()) {
        last.insert("turn".into(), t); // add_cost_mod stamps this turn; a given one wins (Millhouse: next turn)
    }
    none()
}
fn a_log(g: &mut Game, a: Args) -> R {
    live(g)?;
    let v = to_json(g.vm(), &a.table(0)?, 0)?;
    if !v.get("type").is_some_and(Value::is_string) {
        return Err(a.bad(0, "an event needs a string 'type'"));
    }
    one(g.log_event(v) as i64)
}
fn a_emit(g: &mut Game, a: Args) -> R {
    live(g)?;
    let v = to_json(g.vm(), &a.table(0)?, 0)?;
    if !v.get("type").is_some_and(Value::is_string) {
        return Err(a.bad(0, "an event needs a string 'type'"));
    }
    g.emit(v);
    none()
}
fn a_remove(g: &mut Game, a: Args) -> R {
    live(g)?;
    let e = ent(g, &a, 0)?;
    let zone = match a.get(1) {
        L::Nil => None,
        _ => match zone_name(g, &a.string(1)?) {
            "" => return Err(a.bad(1, "a zone name expected")),
            z => Some(z),
        },
    };
    let p = g.ctrl(e);
    let pl = &mut g.players[p];
    pl.hand.retain(|&x| x != e);
    pl.deck.retain(|&x| x != e);
    pl.board.retain(|&x| x != e);
    pl.secrets.retain(|&x| x != e);
    if pl.weapon == Some(e) {
        pl.weapon = None;
    }
    if let Some(z) = zone {
        g.em(e).zone = z;
    }
    none()
}
fn a_random(g: &mut Game, a: Args) -> R {
    let (lo, hi) = (a.int(0)?, a.int(1)?);
    if hi < lo || hi - lo > LIMIT {
        return Err(a.bad(1, "a range lo..hi expected"));
    }
    one(g.rng.randi_range(lo, hi))
}
fn a_pick(g: &mut Game, a: Args) -> R {
    let items = g.vm().list_items(&a.table(0)?)?;
    Ok(vec![g.pick(&items).unwrap_or_default()])
}
fn a_random_alive(g: &mut Game, a: Args) -> R {
    let items = g.vm().list_items(&a.table(0)?)?;
    let mut v = vec![];
    for x in items {
        match x {
            L::Int(n) if n >= 1 && n < g.next_id => v.push(n),
            _ => return Err(a.bad(0, "a list of entities expected")),
        }
    }
    opt_id(g.random_alive(&v))
}
fn a_shuffle(g: &mut Game, a: Args) -> R {
    let t = a.table(0)?;
    let mut items = g.vm().list_items(&t)?;
    Game::shuffle(&mut items, &mut g.rng);
    for (i, v) in items.into_iter().enumerate() {
        g.vm().set(&t, L::from(i + 1), v)?;
    }
    one(t)
}
fn a_cost(g: &mut Game, a: Args) -> R {
    let e = ent(g, &a, 0)?;
    one(g.cost(e))
}

const ACTIONS: &[(&str, classichs_script::NativeFn<Game>)] = &[
    ("g.damage", a_damage), ("g.heal", a_heal), ("g.destroy", a_destroy), ("g.summon", a_summon),
    ("g.summon_right", a_summon_right), ("g.summon_entity", a_summon_entity), ("g.draw", a_draw),
    ("g.draw_entity", a_draw_entity), ("g.add_to_hand", a_add_to_hand), ("g.discard_random", a_discard_random),
    ("g.discard", a_discard), ("g.buff", a_buff), ("g.set_stats", a_set_stats), ("g.silence", a_silence),
    ("g.freeze", a_freeze), ("g.transform", a_transform), ("g.return_to_hand", a_return_to_hand),
    ("g.take_control", a_take_control), ("g.copy_minion", a_copy_minion), ("g.equip", a_equip),
    ("g.gain_armor", a_gain_armor), ("g.gain_mana", a_gain_mana), ("g.add_mana", a_add_mana), ("g.set_mana", a_set_mana),
    ("g.set_tag", a_set_tag), ("g.give_tag", a_give_tag), ("g.erase_tag", a_erase_tag), ("g.add_tag", a_add_tag),
    ("g.set_damage", a_set_damage), ("g.enchant", a_enchant), ("g.remove_enchant", a_remove_enchant),
    ("g.aura_add", a_aura_add), ("g.replace_hero", a_replace_hero), ("g.set_power", a_set_power), ("g.reveal", a_reveal),
    ("g.request_choice", a_request_choice), ("g.add_cost_mod", a_add_cost_mod), ("g.log", a_log), ("g.emit", a_emit),
    ("g.remove", a_remove), ("g.random", a_random), ("g.pick", a_pick), ("g.random_alive", a_random_alive),
    ("g.shuffle", a_shuffle), ("g.cost", a_cost),
];
