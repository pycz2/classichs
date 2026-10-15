//! `cargo run --release -p classichs-script --example bench`
use classichs_script::*;
use std::time::Instant;

struct G {
    vm: Vm<G>,
    hp: Vec<i64>,
}
impl Host for G {
    fn vm(&mut self) -> &mut Vm<G> {
        &mut self.vm
    }
}

fn minions(g: &mut G, _: Args) -> Result<Vec<Value>, Error> {
    let ids = (0..g.hp.len()).map(Value::from).collect();
    Ok(vec![g.vm.list(ids)?])
}
fn damage(g: &mut G, a: Args) -> Result<Vec<Value>, Error> {
    let (t, n) = (a.int(1)?, a.int(2)?);
    g.hp[t as usize] -= n;
    Ok(vec![])
}

const SRC: &str = r#"
local M = {}
function M.loop(n)
  local s = 0
  for i = 1, n do
    s = s + i % 7
  end
  return s
end
M.X = { hook = function(me, n) return n * 2 + me end }
M.Y = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(1)) do
      g.damage(me, m, 1)
    end
  end,
}
return M
"#;

fn main() {
    let mut g = G { vm: Vm::new(), hp: vec![100; 3] };
    g.vm.lib("g", &[("g.minions", minions), ("g.damage", damage)]);
    g.vm.limits.steps = u64::MAX;
    let t = Instant::now();
    let chunk = compile("bench.lua", SRC).unwrap();
    load(&mut g, "m", &chunk).unwrap();
    println!("compile + load: {:?}", t.elapsed());

    let n = 1_000_000;
    let t = Instant::now();
    let r = call_path(&mut g, "m", &["loop"], &[Value::Int(n)]).unwrap();
    let dt = t.elapsed();
    println!("loop of {n} iterations (s = s + i % 7): {dt:?} ({:.1} ns/iteration) -> {:?}", dt.as_nanos() as f64 / n as f64, r[0]);

    let f = get_path(&g.vm, "m", &["X", "hook"]).unwrap();
    let calls = 100_000;
    let t = Instant::now();
    let mut acc = 0;
    for i in 0..calls {
        acc += call(&mut g, &f, &[Value::Int(1), Value::Int(i)]).unwrap()[0].as_int().unwrap();
    }
    let dt = t.elapsed();
    println!("small hook x{calls} from Rust: {dt:?} ({:.0} ns/call) [{acc}]", dt.as_nanos() as f64 / calls as f64);

    let gv = g.vm.global("g");
    let t = Instant::now();
    for _ in 0..calls {
        call_path(&mut g, "m", &["Y", "spell"], &[gv.clone(), Value::Int(1)]).unwrap();
    }
    let dt = t.elapsed();
    println!(
        "spell hook (ipairs over g.minions, 3x g.damage) x{calls}: {dt:?} ({:.0} ns/call), heap objects {}",
        dt.as_nanos() as f64 / calls as f64,
        g.vm.heap_objects()
    );
}
