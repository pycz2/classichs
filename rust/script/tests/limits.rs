mod common;
use common::*;

fn with_limits(l: Limits) -> T {
    let mut t = host();
    t.vm.limits = l;
    t
}

#[track_caller]
fn limit_msg(t: &mut T, src: &str) -> String {
    match run_in(t, src) {
        Ok(_) => panic!("expected a limit error: {src}"),
        Err(e) => {
            assert_eq!(e.kind(), ErrorKind::Limit, "{e}");
            e.message.clone()
        }
    }
}

#[test]
fn defaults() {
    let l = Limits::default();
    assert_eq!((l.steps, l.depth, l.table_size, l.string_len), (200_000, 200, 10_000, 65_536));
}

#[test]
fn steps() {
    let m = limit_msg(&mut host(), "while true do end");
    assert_eq!(m, "test.lua:1: step limit exceeded (200000 steps per call)");
    assert!(limit_msg(&mut host(), "repeat until false").contains("step limit"));
    assert!(limit_msg(&mut host(), "for i = 1, math.maxinteger do end").contains("step limit"));
    assert!(limit_msg(&mut host(), "local function f() end while true do f() end").contains("step limit"));
    let mut t = with_limits(Limits { steps: 1000, ..Limits::default() });
    assert!(run_in(&mut t, "local s = 0 for i = 1, 300 do s = s + i end return s").is_ok());
    assert!(limit_msg(&mut t, "local s = 0 for i = 1, 600 do s = s + i end return s").contains("(1000 steps per call)"));
    // Library loops are charged too.
    assert!(limit_msg(&mut t, "local t = {} for i = 1, 100 do t[i] = i end for i = 1, 20 do table.sort(t, function(a, b) return a > b end) end").contains("step limit"));
}

#[test]
fn step_budget_is_per_top_level_call() {
    let mut t = host();
    let chunk = compile("m.lua", "return { burn = function(n) local s = 0 for i = 1, n do s = s + 1 end return s end }").unwrap();
    load(&mut t, "m", &chunk).unwrap();
    for _ in 0..5 {
        assert_eq!(call_path(&mut t, "m", &["burn"], &[Value::Int(90_000)]).unwrap(), vec![Value::Int(90_000)]);
    }
    let e = call_path(&mut t, "m", &["burn"], &[Value::Int(300_000)]).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Limit);
    // The VM is usable after a limit error.
    assert_eq!(call_path(&mut t, "m", &["burn"], &[Value::Int(5)]).unwrap(), vec![Value::Int(5)]);
}

#[test]
fn depth() {
    let m = limit_msg(&mut host(), "local function f(n) return f(n + 1) end return f(1)");
    assert_eq!(m, "test.lua:1: stack overflow (call depth limit 200)");
    let mut t = with_limits(Limits { depth: 20, ..Limits::default() });
    assert!(run_in(&mut t, "local function f(n) if n == 0 then return 0 end return 1 + f(n - 1) end return f(15)").is_ok());
    assert!(limit_msg(&mut t, "local function f(n) if n == 0 then return 0 end return 1 + f(n - 1) end return f(25)").contains("call depth limit 20"));
    // Library calls count: sort comparators that recurse through table.sort.
    let src = "local function f(t) table.sort(t, function(a, b) f({2, 1}) return a < b end) end f({2, 1})";
    assert!(limit_msg(&mut host(), src).contains("stack overflow"));
}

#[test]
fn table_size() {
    let m = limit_msg(&mut host(), "local t = {} for i = 1, 20000 do t[i] = i end");
    assert_eq!(m, "test.lua:1: table size limit exceeded (10000 entries)");
    let mut t = with_limits(Limits { table_size: 100, ..Limits::default() });
    assert!(run_in(&mut t, "local t = {} for i = 1, 100 do t[i] = i end for i = 1, 100 do t[i] = nil end for i = 1, 100 do t['k' .. i] = i end").is_ok());
    assert!(limit_msg(&mut t, "local t = {} for i = 1, 101 do t[i] = i end").contains("(100 entries)"));
    assert!(limit_msg(&mut t, &format!("return {{{}}}", "1, ".repeat(101))).contains("table size"));
    assert!(limit_msg(&mut t, "local t = {} for i = 1, 100 do t[i] = i end table.insert(t, 1)").contains("table size"));
}

#[test]
fn string_length() {
    let m = limit_msg(&mut host(), "return string.rep('ab', 40000)");
    assert_eq!(m, "test.lua:1: string length limit exceeded (65536 bytes)");
    let mut t = with_limits(Limits { string_len: 10, ..Limits::default() });
    assert!(run_in(&mut t, "return ('x'):rep(10), '0123456789'").is_ok());
    assert!(limit_msg(&mut t, "return ('x'):rep(11)").contains("(10 bytes)"));
    assert!(limit_msg(&mut t, "return 'abcdef' .. 'ghijk'").contains("string length"));
    assert!(limit_msg(&mut t, "return string.format('%d%d', 123456, 123456)").contains("string length"));
    assert!(limit_msg(&mut t, "return table.concat({'abcdef', 'ghijk'})").contains("string length"));
    assert!(limit_msg(&mut t, "return tostring(12345) .. 123456").contains("string length"));
}

#[test]
fn allocation_budget() {
    let mut t = with_limits(Limits { alloc: 10_000, ..Limits::default() });
    assert!(run_in(&mut t, "local t = {} for i = 1, 20 do t[i] = {} end").is_ok());
    let m = limit_msg(&mut t, "local t = {} for i = 1, 200 do t[i] = {} end");
    assert!(m.contains("memory limit exceeded (10000 bytes per call)"), "{m}");
    assert!(limit_msg(&mut t, "local fs = {} for i = 1, 300 do fs[i] = function() return i end end").contains("memory limit"));
    assert!(limit_msg(&mut t, "local s = '' for i = 1, 100 do s = s .. 'abcdefghij' .. i end").contains("memory limit"));
    // Default budget: garbage in a loop runs out before memory does.
    let (k, _) = err_kind("while true do local t = {1, 2, 3, 4, 5, 6, 7, 8} end");
    assert_eq!(k, ErrorKind::Limit);
}

#[test]
fn garbage_is_collected_between_calls() {
    let mut t = host();
    let chunk = compile("m.lua", "local keep = {} return { churn = function() local x for i = 1, 500 do x = {i, {i}} end keep.last = x end }").unwrap();
    load(&mut t, "m", &chunk).unwrap();
    let mut peak = 0;
    for _ in 0..100 {
        call_path(&mut t, "m", &["churn"], &[]).unwrap();
        peak = peak.max(t.vm.heap_objects());
    }
    assert!(peak < 20_000, "heap grew to {peak} objects");
    // What is reachable survives.
    let r = run_in(&mut t, "return 1").unwrap();
    assert_eq!(r, vec![Value::Int(1)]);
    t.vm.collect(&[]);
    let last = get_path(&t.vm, "m", &["churn"]).unwrap();
    assert!(matches!(last, Value::Func(_)));
}
