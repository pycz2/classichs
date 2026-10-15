//! The host API, with a toy game and the card examples of docs/packs/lua.md.
use classichs_script::*;

struct Minion {
    id: i64,
    card: &'static str,
    owner: i64,
    atk: i64,
    hp: i64,
    aura_atk: i64,
}

struct Game {
    vm: Vm<Game>,
    minions: Vec<Minion>,
    /// Spells and other entities: (id, owner).
    others: Vec<(i64, i64)>,
    hand: [i64; 2],
    log: Vec<String>,
}

impl Host for Game {
    fn vm(&mut self) -> &mut Vm<Game> {
        &mut self.vm
    }
}

type R = Result<Vec<Value>, Error>;

impl Game {
    fn owner(&self, id: i64) -> Result<i64, Error> {
        self.minions
            .iter()
            .map(|m| (m.id, m.owner))
            .chain(self.others.iter().copied())
            .find(|e| e.0 == id)
            .map(|e| e.1)
            .ok_or_else(|| Error::runtime(format!("no entity {id}")))
    }
    fn ids(&mut self, f: impl Fn(&Minion) -> bool) -> R {
        let ids = self.minions.iter().filter(|m| f(m)).map(|m| Value::Int(m.id)).collect();
        Ok(vec![self.vm.list(ids)?])
    }
    fn hook(&self, card: &str, path: &[&str]) -> Value {
        let mut p = vec![card];
        p.extend_from_slice(path);
        get_path(&self.vm, "cards", &p).unwrap_or_default()
    }
    fn run_auras(&mut self) -> Result<(), Error> {
        for m in &mut self.minions {
            m.aura_atk = 0;
        }
        let g = self.vm.global("g");
        for (id, card) in self.minions.iter().map(|m| (m.id, m.card)).collect::<Vec<_>>() {
            let f = self.hook(card, &["aura"]);
            if !f.is_nil() {
                call(self, &f, &[g.clone(), Value::Int(id)])?;
            }
        }
        Ok(())
    }
}

fn minions(g: &mut Game, a: Args) -> R {
    let p = a.int(0)?;
    g.ids(|m| m.owner == p)
}
fn enemy(g: &mut Game, a: Args) -> R {
    Ok(vec![Value::Int(1 - g.owner(a.int(0)?)?)])
}
fn ctrl(g: &mut Game, a: Args) -> R {
    Ok(vec![Value::Int(g.owner(a.int(0)?)?)])
}
fn others(g: &mut Game, a: Args) -> R {
    let me = a.int(0)?;
    let p = g.owner(me)?;
    g.ids(|m| m.owner == p && m.id != me)
}
fn spell_dmg(_: &mut Game, a: Args) -> R {
    Ok(vec![Value::Int(a.int(1)?)])
}
fn draw(g: &mut Game, a: Args) -> R {
    let p = a.int(0)?;
    g.hand[p as usize] += 1;
    Ok(vec![])
}
fn aura_add(g: &mut Game, a: Args) -> R {
    let (t, atk) = (a.int(0)?, a.int(1)?);
    let m = g.minions.iter_mut().find(|m| m.id == t).ok_or_else(|| Error::runtime(format!("no minion {t}")))?;
    m.aura_atk += atk;
    Ok(vec![])
}
/// Damages a minion, then lets every minion's `on.damage` hook see the event
/// (a re-entrant call into the scripts), then removes the dead.
fn damage(g: &mut Game, a: Args) -> R {
    let (src, t, n) = (a.int(0)?, a.int(1)?, a.int(2)?);
    let m = g.minions.iter_mut().find(|m| m.id == t).ok_or_else(|| Error::runtime(format!("no minion {t}")))?;
    m.hp -= n;
    g.log.push(format!("{src} hits {t} for {n}"));
    let ev = g.vm.new_table();
    g.vm.set(&ev, "source", src)?;
    g.vm.set(&ev, "target", t)?;
    g.vm.set(&ev, "amount", n)?;
    let gv = g.vm.global("g");
    for (id, card) in g.minions.iter().map(|m| (m.id, m.card)).collect::<Vec<_>>() {
        let f = g.hook(card, &["on", "damage"]);
        if !f.is_nil() {
            call(g, &f, &[gv.clone(), Value::Int(id), ev.clone()])?;
        }
    }
    g.minions.retain(|m| m.hp > 0);
    Ok(vec![])
}
fn fail(_: &mut Game, _: Args) -> R {
    Err(Error::fatal("engine invariant broken"))
}

const CARDS: &str = r#"
local cards = {}

-- Spell: deal 4 damage to all enemy minions.
cards.FLAMESTRIKE = {
  spell = function(g, me, target)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, g.spell_dmg(me, 4))
    end
  end,
}

-- Minion: whenever this minion takes damage, draw a card.
cards.ACOLYTE = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        g.draw(g.ctrl(me))
      end
    end,
  },
}

-- Minion: your other minions have +1 attack.
cards.RAID_LEADER = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      g.aura_add(m, 1)
    end
  end,
}

cards.BROKEN = {
  spell = function(g, me)
    g.damage(me, 999, 1)
  end,
  fatal = function(g)
    return pcall(g.fail)
  end,
}

return cards
"#;

fn game() -> Game {
    let mut vm = Vm::new();
    vm.lib(
        "g",
        &[
            ("g.minions", minions),
            ("g.enemy", enemy),
            ("g.ctrl", ctrl),
            ("g.others", others),
            ("g.spell_dmg", spell_dmg),
            ("g.draw", draw),
            ("g.aura_add", aura_add),
            ("g.damage", damage),
            ("g.fail", fail),
        ],
    );
    let m = |id, card, owner, atk, hp| Minion { id, card, owner, atk, hp, aura_atk: 0 };
    let mut g = Game {
        vm,
        minions: vec![m(1, "RAID_LEADER", 0, 2, 2), m(2, "ACOLYTE", 0, 0, 3), m(3, "ACOLYTE", 1, 0, 3), m(4, "WISP", 1, 1, 5)],
        others: vec![(10, 0), (11, 1)],
        hand: [0, 0],
        log: Vec::new(),
    };
    let chunk = compile("cards.lua", CARDS).unwrap();
    load(&mut g, "cards", &chunk).unwrap();
    g
}

#[test]
fn card_examples() {
    let mut g = game();
    let gv = g.vm.global("g");
    // Flamestrike from player 0 hits both enemy minions; the enemy Acolyte draws.
    call_path(&mut g, "cards", &["FLAMESTRIKE", "spell"], &[gv.clone(), Value::Int(10), Value::Nil]).unwrap();
    assert_eq!(g.log, vec!["10 hits 3 for 4", "10 hits 4 for 4"]);
    assert_eq!(g.hand, [0, 1]);
    assert_eq!(g.minions.iter().map(|m| (m.id, m.hp)).collect::<Vec<_>>(), vec![(1, 2), (2, 3), (4, 1)]);
    // Raid Leader's aura.
    g.run_auras().unwrap();
    let atk: Vec<_> = g.minions.iter().map(|m| m.atk + m.aura_atk).collect();
    assert_eq!(atk, vec![2, 1, 1]);
    // Flamestrike from player 1: our Acolyte draws for player 0; both our minions die.
    call_path(&mut g, "cards", &["FLAMESTRIKE", "spell"], &[gv, Value::Int(11), Value::Nil]).unwrap();
    assert_eq!(g.hand, [1, 1]);
    g.run_auras().unwrap();
    assert_eq!(g.minions.iter().map(|m| m.atk + m.aura_atk).collect::<Vec<_>>(), vec![1]);
}

#[test]
fn host_errors_carry_the_script_position() {
    let mut g = game();
    let gv = g.vm.global("g");
    let e = call_path(&mut g, "cards", &["BROKEN", "spell"], &[gv.clone(), Value::Int(10)]).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Runtime);
    let line = CARDS.lines().position(|l| l.contains("g.damage(me, 999, 1)")).unwrap() + 1;
    assert_eq!(e.message, format!("cards.lua:{line}: no minion 999"));
    assert!(e.traceback[0].contains("in function 'spell'"), "{:?}", e.traceback);
    // Fatal host errors go through pcall.
    let e = call_path(&mut g, "cards", &["BROKEN", "fatal"], &[gv]).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Fatal);
    assert!(e.message.ends_with("engine invariant broken"));
    // The host library is read-only for scripts.
    let chunk = compile("evil.lua", "g.damage = nil").unwrap();
    assert!(load(&mut g, "evil", &chunk).unwrap_err().message.contains("read-only"));
}

#[test]
fn values_both_ways() {
    let mut g = game();
    let vm = &mut g.vm;
    let t = vm.list(vec![Value::Int(1), "two".into(), true.into()]).unwrap();
    assert_eq!(vm.list_items(&t).unwrap(), vec![Value::Int(1), Value::from("two"), Value::Bool(true)]);
    vm.set(&t, "k", 5).unwrap();
    assert_eq!(vm.get(&t, "k").unwrap().as_int(), Some(5));
    assert_eq!(vm.get(&t, 2).unwrap().as_str(), Some("two"));
    let keys: Vec<String> = vm.pairs(&t).unwrap().iter().map(|(k, _)| vm.display(k)).collect();
    assert_eq!(keys, vec!["1", "2", "3", "k"]);
    vm.freeze(&t);
    assert!(vm.set(&t, "k", 6).is_err());
    assert_eq!(Value::from(Some(3)), Value::Int(3));
    assert_eq!(Value::from(None::<i64>), Value::Nil);
    assert_eq!(Value::from(()).type_name(), "nil");
    // Tables from scripts come back as Rust data.
    let chunk = compile("t.lua", "return { list = {3, 2, 1}, name = 'x', flag = false }").unwrap();
    let m = load(&mut g, "t", &chunk).unwrap();
    let list = g.vm.get(&m, "list").unwrap();
    let ints: Vec<i64> = g.vm.list_items(&list).unwrap().iter().filter_map(Value::as_int).collect();
    assert_eq!(ints, vec![3, 2, 1]);
    assert_eq!(get_path(&g.vm, "t", &["name"]).unwrap().as_str(), Some("x"));
    assert_eq!(get_path(&g.vm, "t", &["missing", "deeper"]).unwrap(), Value::Nil);
    assert!(get_path(&g.vm, "nope", &[]).is_err());
}

#[test]
fn compiled_once_loaded_many_times() {
    fn assert_send_sync<X: Send + Sync>() {}
    fn assert_send<X: Send>() {}
    assert_send_sync::<Chunk>();
    assert_send::<Vm<Game>>();
    let chunk = compile("cards.lua", CARDS).unwrap();
    let chunk2 = chunk.clone();
    let h = std::thread::spawn(move || {
        let mut g = game();
        load(&mut g, "again", &chunk2).unwrap();
        g.minions.len()
    });
    assert_eq!(h.join().unwrap(), 4);
    let mut g = game();
    for i in 0..3 {
        load(&mut g, &format!("copy{i}"), &chunk).unwrap();
    }
    assert!(matches!(g.vm.module("copy2"), Value::Table(_)));
}

#[test]
fn undefined_globals_fail_at_load_with_a_line() {
    let mut g = game();
    let chunk = compile("c.lua", "return {\n  spell = function(g)\n    return gg.damage()\n  end\n}").unwrap();
    let e = load(&mut g, "c", &chunk).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Compile);
    assert_eq!(e.message, "c.lua:3: undefined global 'gg'");
}

#[test]
fn stale_references_are_errors_not_other_objects() {
    let mut g = game();
    let t = g.vm.new_table();
    g.vm.set(&t, "x", 1).unwrap();
    g.vm.collect(&[]);
    let u = g.vm.new_table(); // may reuse the slot
    assert!(g.vm.get(&t, "x").is_err());
    assert_eq!(g.vm.get(&u, "x").unwrap(), Value::Nil);
    // Pinned values survive.
    let p = g.vm.new_table();
    g.vm.pin(p.clone());
    g.vm.collect(&[]);
    assert!(g.vm.set(&p, "y", 2).is_ok());
}

#[test]
fn reentrant_calls_share_the_budget() {
    fn again(g: &mut Game, a: Args) -> R {
        let n = a.int(0)?;
        call_path(g, "r", &["f"], &[Value::Int(n)])
    }
    let mut g = game();
    let f = g.vm.register("again", again);
    g.vm.set_global("again", f);
    let chunk = compile("r.lua", "local M = {} function M.f(n) if n == 0 then return 'done' end return again(n - 1) end return M").unwrap();
    load(&mut g, "r", &chunk).unwrap();
    assert_eq!(call_path(&mut g, "r", &["f"], &[Value::Int(50)]).unwrap(), vec![Value::from("done")]);
    let e = call_path(&mut g, "r", &["f"], &[Value::Int(500)]).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Limit);
    assert_eq!(call_path(&mut g, "r", &["f"], &[Value::Int(3)]).unwrap(), vec![Value::from("done")]);
}
