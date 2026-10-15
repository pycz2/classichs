//! The executor recursion stays inside a small native stack (wasm's default
//! is 1 MiB) whatever the script: limits fire before the stack runs out.
mod common;
use common::*;

fn nested_ifs(k: usize) -> String {
    let mut s = String::from("local function f(n) if n == 0 then return 0 end ");
    s += &"if true then ".repeat(k);
    s += "return f(n - 1) + 1 ";
    s += &"end ".repeat(k);
    s += "end return f(100000)";
    s
}

fn nested_exprs(k: usize) -> String {
    let mut s = String::from("local function f(n) if n == 0 then return 0 end return ");
    s += &"(1 + ".repeat(k);
    s += "f(n - 1)";
    s += &")".repeat(k);
    s += " end return f(100000)";
    s
}

fn nested_natives() -> String {
    "local function f(n) return pcall(f, n + 1) end return f(1)".into()
}

fn nested_list() -> String {
    "local function f(t) return list.map(t, function(x) return f({x}) end) end return f({1})".into()
}

fn in_thread(stack: usize, src: String) -> Result<String, String> {
    std::thread::Builder::new()
        .stack_size(stack)
        .spawn(move || match run(&src) {
            Ok(_) => Ok("ok".to_string()),
            Err(e) => Err(format!("{:?}", e.kind())),
        })
        .unwrap()
        .join()
        .unwrap()
}

#[test]
fn deep_scripts_hit_limits_not_the_native_stack() {
    let stack = 1 << 20;
    for src in [nested_ifs(5), nested_ifs(60), nested_ifs(190), nested_exprs(5), nested_exprs(45), nested_natives(), nested_list()] {
        let r = in_thread(stack, src);
        assert_eq!(r, Err("Limit".to_string()));
    }
}


#[test]
fn too_deep_source_is_a_compile_error() {
    assert_eq!(in_thread(1 << 20, nested_exprs(150)), Err("Compile".to_string()));
    assert_eq!(in_thread(1 << 20, format!("return {}1{}", "(".repeat(100_000), ")".repeat(100_000))), Err("Compile".to_string()));
    assert_eq!(in_thread(1 << 20, format!("return {}1", "- ".repeat(100_000))), Err("Compile".to_string()));
    assert_eq!(in_thread(1 << 20, format!("local x = 1 return x{}", " + x".repeat(100_000))), Err("Compile".to_string()));
}

#[test]
fn ordinary_recursion_reaches_the_depth_limit() {
    // A function of ordinary shape recurses to the documented depth.
    let src = "local function f(n) if n > 0 then local x = n * 2 if x > 0 then return f(n - 1) + 1 end end return 0 end return f(190)";
    assert_eq!(in_thread(1 << 20, src.into()), Ok("ok".to_string()));
    let src = "local function f(n) return f(n + 1) end return f(1)";
    assert_eq!(in_thread(1 << 20, src.into()), Err("Limit".to_string()));
}
