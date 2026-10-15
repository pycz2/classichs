//! Property tests: random token streams, random bytes and mutated programs
//! never panic, always finish (limits), and run the same way twice.
mod common;
use common::*;

struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        // xorshift64*
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_f491_4f6c_dd1d)
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
    fn pick<'a>(&mut self, v: &[&'a str]) -> &'a str {
        v[self.below(v.len())]
    }
}

const VOCAB: &[&str] = &[
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while", "goto", "+", "-", "*", "//", "%", "/", "^", "#", "==", "~=",
    "<=", ">=", "<", ">", "=", "(", ")", "{", "}", "[", "]", ";", ":", ",", ".", "..", "...", "::", "~", "&", "x", "y",
    "t", "f", "g", "i", "self", "pairs", "ipairs", "next", "select", "pcall", "error", "assert", "type", "tostring",
    "tonumber", "string", "table", "math", "list", "rep", "sort", "insert", "remove", "sub", "find", "format", "concat",
    "unpack", "byte", "char", "upper", "min", "max", "clamp", "filter", "map", "sum", "sort_by", "0", "1", "-1", "2", "3",
    "100", "65536", "9223372036854775807", "0x7fffffffffffffff", "'s'", "\"%d%s\"", "[[long]]", "'\\x41\\z  \\u{48}'",
    "'#'", "1.5", "--", "\n",
];

const CORPUS: &[&str] = &[
    "local t = {} for i = 1, 10 do t[#t + 1] = i * i end return table.concat(t, ',')",
    "local function f(n) if n < 2 then return n end return f(n - 1) + f(n - 2) end return f(15)",
    "local function counter() local n = 0 return function() n = n + 1 return n end end local c = counter() c() return c()",
    "local t = {a = 1, b = 2, 3, 4} local s = '' for k, v in pairs(t) do s = s .. tostring(k) .. v end return s",
    "local function f(...) local a, b = ... return select('#', ...), a, b, ... end return f(1, nil, 3)",
    "local x, y = 1, 2 x, y = y, x local t = {} t.x, t.y = x, y return t.x // t.y, t.x % -2, -t.y",
    "local s = ('abc'):rep(3, '-') return s:sub(2, -2):upper(), s:find('c-a', 1, true), #s, s:byte(1, 3)",
    "local ok, e = pcall(function() error({code = 1}) end) return ok, type(e), e.code",
    "local t = {5, 3, 1, 4} table.sort(t, function(a, b) return a > b end) table.insert(t, 2, 9) return table.remove(t), table.unpack(t)",
    "local l = list.filter({1, 2, 3, 4}, function(x) return x % 2 == 0 end) return list.sum(list.map(l, function(x) return x * 10 end))",
    "local i = 0 repeat i = i + 1 if i == 3 then break end until i > 10 while i < 20 do i = i + 7 end return i",
    "local obj = {n = 1} function obj:inc(k) self.n = self.n + (k or 1) return self end return obj:inc():inc(5).n",
    "local m = math.max(1, 5, 3) local c = math.clamp(m, 0, 4) return string.format('%d/%s %%', c, tostring(m))",
    "local t = {} for i = 10, 1, -3 do t[i] = i end for k in pairs(t) do t[k] = nil end return next(t), #t",
];

/// `FUZZ_SCALE=50 FUZZ_SEED=7 cargo test -p classichs-script --test fuzz` for a longer run.
fn scale(n: usize) -> usize {
    n * std::env::var("FUZZ_SCALE").ok().and_then(|s| s.parse().ok()).unwrap_or(1)
}

fn seed(s: u64) -> Rng {
    Rng(s ^ std::env::var("FUZZ_SEED").ok().and_then(|s| s.parse::<u64>().ok()).unwrap_or(0).wrapping_mul(0x9e37_79b9))
}

fn limited() -> T {
    let mut t = host();
    t.vm.limits = Limits { steps: 20_000, depth: 50, table_size: 1000, string_len: 4096, alloc: 1 << 20 };
    t
}

/// Compiles and runs; returns a description of the outcome. Panics are test failures.
fn outcome(src: &[u8]) -> String {
    let chunk = match compile_bytes("fuzz.lua", src) {
        Ok(c) => c,
        Err(e) => return format!("compile: {}", e.message),
    };
    let mut t = limited();
    let r = load(&mut t, "fuzz", &chunk).and_then(|f| match f {
        Value::Func(_) | Value::Native(_) => call(&mut t, &f, &[Value::Int(1), "x".into()]),
        v => Ok(vec![v]),
    });
    match r {
        Ok(v) => format!("ok: {}", show(&t, &v)),
        Err(e) => format!("{:?}: {}", e.kind(), e),
    }
}

#[test]
fn random_token_streams_never_panic() {
    let mut rng = seed(0x9e37_79b9_7f4a_7c15);
    let mut compiled = 0;
    for _ in 0..scale(40_000) {
        let n = 1 + rng.below(40);
        let src: Vec<&str> = (0..n).map(|_| rng.pick(VOCAB)).collect();
        let src = src.join(" ");
        let r = outcome(src.as_bytes());
        if !r.starts_with("compile") {
            compiled += 1;
        }
    }
    assert!(compiled > 100, "only {compiled} streams compiled");
}

#[test]
fn random_bytes_never_panic() {
    let mut rng = seed(12345);
    let alphabet = b"abcxyz0123456789 \n\t()[]{}=<>~+-*/%^#.,;:'\"\\[]=-";
    for _ in 0..scale(20_000) {
        let n = rng.below(80);
        let src: Vec<u8> = (0..n)
            .map(|_| if rng.below(10) == 0 { rng.next() as u8 } else { alphabet[rng.below(alphabet.len())] })
            .collect();
        outcome(&src);
    }
}

#[test]
fn mutated_programs_never_panic_and_are_deterministic() {
    for p in CORPUS {
        assert!(outcome(format!("return function(...) {p} end").as_bytes()).starts_with("ok"), "{p}: {}", outcome(p.as_bytes()));
    }
    let mut rng = seed(777);
    let mut ran = 0;
    for _ in 0..scale(30_000) {
        let base = CORPUS[rng.below(CORPUS.len())];
        let mut toks: Vec<String> = base.split(' ').map(String::from).collect();
        for _ in 0..1 + rng.below(3) {
            let i = rng.below(toks.len());
            match rng.below(5) {
                0 => {
                    toks.remove(i);
                }
                1 => {
                    let t = toks[i].clone();
                    toks.insert(i, t);
                }
                2 => toks[i] = rng.pick(VOCAB).to_string(),
                3 => {
                    let j = rng.below(toks.len());
                    toks.swap(i, j);
                }
                _ => toks.insert(i, rng.pick(VOCAB).to_string()),
            }
            if toks.is_empty() {
                toks.push("return".into());
            }
        }
        let src = format!("return function(...) {} end", toks.join(" "));
        let a = outcome(src.as_bytes());
        if !a.starts_with("compile") {
            ran += 1;
            assert_eq!(a, outcome(src.as_bytes()), "nondeterministic: {src}");
        }
    }
    assert!(ran > 1000, "only {ran} mutants ran");
}

#[test]
fn hostile_programs_finish() {
    for src in [
        "local function f() return f() end return f()",
        "local t = {} while true do t[#t + 1] = {} end",
        "local s = 'x' while true do s = s .. s end",
        "local t = {} t[1] = t for i = 1, 100000 do t = {t} end",
        "local function f(...) return f(..., ...) end return f(1)",
        "local t = {} for i = 1, 900 do t[i] = i end for i = 1, 100 do table.sort(t, function(a, b) return a > b end) end",
        "while true do pcall(function() local t = {} for i = 1, 10 do t[i] = tostring(i) end end) end",
        "local f f = function(n) return list.map({n}, f) end return f(1)",
        "for i = 1, math.maxinteger do local x = {} end",
    ] {
        let r = outcome(format!("return function(...) {src} end").as_bytes());
        assert!(r.starts_with("Limit"), "{src}: {r}");
    }
}
