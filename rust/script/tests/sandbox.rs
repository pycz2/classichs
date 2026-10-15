//! Escape attempts: everything here must fail with a clear error.
mod common;
use common::*;

#[track_caller]
fn compile_err(src: &str) -> String {
    match compile("x.lua", src) {
        Ok(_) => panic!("expected a compile error: {src}"),
        Err(e) => {
            assert_eq!(e.kind(), ErrorKind::Compile);
            e.message.clone()
        }
    }
}

/// Compiles fine but fails to load (undefined global).
#[track_caller]
fn load_err(src: &str) -> String {
    let (k, m) = err_kind(src);
    assert_eq!(k, ErrorKind::Compile, "{m}");
    m
}

#[test]
fn no_global_environment() {
    assert!(compile_err("return _G").contains("'_G' is not available"));
    assert!(compile_err("return _ENV.print").contains("'_ENV' is not available"));
    assert!(compile_err("local _ENV = {}").contains("'_ENV' is not available"));
    assert!(compile_err("return {_G = 1}").contains("'_G' is not available"));
    assert!(compile_err("x = 1").contains("assignment to undeclared global 'x'"));
    assert!(compile_err("function f() end").contains("assignment to undeclared global 'f'"));
    assert!(compile_err("a, b = 1, 2").contains("undeclared global 'a'"));
    assert!(load_err("return undefined_thing").contains("undefined global 'undefined_thing'"));
}

#[test]
fn no_metatables_coroutines_or_loading() {
    for (src, hint) in [
        ("setmetatable({}, {})", "metatables are not supported"),
        ("return getmetatable('')", "metatables are not supported"),
        ("rawset({}, 1, 2)", "raw access is not available"),
        ("return rawget(string, 'rep')", "raw access is not available"),
        ("return rawequal(1, 1)", "raw access"),
        ("coroutine.wrap(function() end)", "coroutines are not supported"),
        ("load('return 1')", "scripts cannot load code"),
        ("loadstring('return 1')", "scripts cannot load code"),
        ("dofile('x.lua')", "scripts cannot load code"),
        ("require('os')", "scripts cannot load code"),
        ("return package.loaded", "scripts cannot load code"),
        ("io.write('x')", "not available in the sandbox"),
        ("return os.time()", "not available in the sandbox"),
        ("return debug.getinfo(1)", "not available in the sandbox"),
        ("collectgarbage()", "not available in the sandbox"),
        ("print('x')", "not available in the sandbox"),
        ("return unpack({1})", "use table.unpack"),
    ] {
        let m = load_err(src);
        assert!(m.contains(hint), "{src}: {m}");
    }
    assert!(err("return string.dump(function() end)").contains("attempt to call a nil value (field 'dump')"));
    assert_eq!(ok("return string.gsub, string.match, string.gmatch, table.pack, math.random, math.sqrt"), "nil, nil, nil, nil, nil, nil");
}

#[test]
fn no_goto_floats_or_bitwise() {
    assert!(compile_err("goto done").contains("'goto' is not supported"));
    assert!(compile_err("::top::").contains("labels are not supported"));
    assert!(compile_err("return 1.5").contains("floating-point numbers are not supported"));
    assert!(compile_err("return 1e3").contains("floating-point numbers are not supported"));
    assert!(compile_err("return .5").contains("floating-point numbers are not supported"));
    assert!(compile_err("return 0x1p4").contains("floating-point numbers are not supported"));
    assert!(compile_err("return 7 / 2").contains("'/' is not supported (no floats); use '//'"));
    assert!(compile_err("return 2 ^ 3").contains("'^' is not supported"));
    assert!(compile_err("return 1 & 2").contains("bitwise operators are not supported"));
    assert!(compile_err("return 1 | 2").contains("bitwise operators are not supported"));
    assert!(compile_err("return ~1").contains("bitwise operators are not supported"));
    assert!(compile_err("return 1 << 2").contains("bitwise operators are not supported"));
    assert!(compile_err("local x <const> = 1").contains("attributes"));
    assert!(compile_err("local x <close> = nil").contains("attributes"));
    assert!(compile_err("return 3x").contains("malformed number"));
}

#[test]
fn library_tables_are_read_only() {
    for src in [
        "string.upper = nil",
        "table.insert = function() end",
        "math.pi = 3",
        "list.extra = 1",
        "local s = string s.rep = nil",
        "table.insert(string, 'x')",
        "table.sort(table)",
        "table.remove(math, 1)",
    ] {
        let (k, m) = err_kind(src);
        assert_eq!(k, ErrorKind::Runtime, "{src}");
        assert!(m.contains("read-only table"), "{src}: {m}");
    }
    // Scripts own the tables they make.
    assert_eq!(ok("local t = {} t.x = 1 return t.x"), "1");
}

#[test]
fn string_bombs_are_bounded() {
    let (k, m) = err_kind("return string.rep('x', 1099511627776)");
    assert_eq!(k, ErrorKind::Limit);
    assert!(m.contains("string length limit exceeded"), "{m}");
    let (k, _) = err_kind("return string.rep('abc', math.maxinteger, 'sep')");
    assert_eq!(k, ErrorKind::Limit);
    let (k, _) = err_kind("local s = 'xx' while true do s = s .. s end");
    assert_eq!(k, ErrorKind::Limit);
    let (k, _) = err_kind("local t = {} for i = 1, 9000 do t[i] = 'abcdefghij' end return table.concat(t)");
    assert_eq!(k, ErrorKind::Limit);
    let (k, _) = err_kind("return string.format(string.rep('%s', 30000), table.unpack(list.map(string.rep('x', 30000, ','), tostring)))");
    assert!(matches!(k, ErrorKind::Limit | ErrorKind::Runtime));
}

#[test]
fn pcall_cannot_swallow_limits() {
    let (k, _) = err_kind("local ok = pcall(function() while true do end end) return ok");
    assert_eq!(k, ErrorKind::Limit);
    let (k, _) = err_kind("local function f() return f() end local ok = pcall(f) return ok");
    assert_eq!(k, ErrorKind::Limit);
    let (k, _) = err_kind("local ok = pcall(string.rep, 'x', 1073741824) return ok");
    assert_eq!(k, ErrorKind::Limit);
    let (k, _) = err_kind("local ok = pcall(function() local t = {} for i = 1, 20000 do t[i] = i end end) return ok");
    assert_eq!(k, ErrorKind::Limit);
    // Even a pcall inside an error handler loop.
    let (k, _) = err_kind("while true do pcall(error, 'x') end");
    assert_eq!(k, ErrorKind::Limit);
}

#[test]
fn tostring_does_not_leak_addresses() {
    let a = ok("return tostring({}), tostring(function() end), tostring(print_ or pairs)".replace("print_ or ", "").as_str());
    assert!(a.starts_with("table: #"), "{a}");
    assert!(a.contains("function: builtin 'pairs'"), "{a}");
    // Same script, same text, in a fresh VM.
    assert_eq!(a, ok("return tostring({}), tostring(function() end), tostring(pairs)"));
}
