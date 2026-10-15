//! The standard library: base functions, table, string, math, list.

use crate::vm::{INEXT, NEXT};
use crate::{call, Args, Error, Host, NativeFn, Ref, Value, Vm};

type R = Result<Vec<Value>, Error>;

pub(crate) fn install<H: Host>(vm: &mut Vm<H>) {
    let next = vm.register("next", next::<H>);
    let inext = vm.register("ipairs_iterator", inext::<H>);
    debug_assert!(next == Value::Native(NEXT) && inext == Value::Native(INEXT));
    vm.set_global("next", next);
    let base: &[(&'static str, NativeFn<H>)] = &[
        ("ipairs", ipairs),
        ("pairs", pairs),
        ("type", type_),
        ("tostring", tostring),
        ("tonumber", tonumber),
        ("select", select),
        ("error", error),
        ("assert", assert),
        ("pcall", pcall),
    ];
    for (n, f) in base {
        let v = vm.register(n, *f);
        vm.set_global(n, v);
    }
    vm.lib(
        "table",
        &[
            ("table.insert", t_insert),
            ("table.remove", t_remove),
            ("table.sort", t_sort),
            ("table.concat", t_concat),
            ("table.unpack", t_unpack),
        ],
    );
    vm.string_lib = vm.lib(
        "string",
        &[
            ("string.len", s_len),
            ("string.sub", s_sub),
            ("string.upper", s_upper),
            ("string.lower", s_lower),
            ("string.rep", s_rep),
            ("string.format", s_format),
            ("string.find", s_find),
            ("string.byte", s_byte),
            ("string.char", s_char),
        ],
    );
    let math = vm.lib(
        "math",
        &[("math.min", m_min), ("math.max", m_max), ("math.abs", m_abs), ("math.clamp", m_clamp), ("math.floor", m_floor)],
    );
    if let Value::Table(r) = math {
        if let Ok(t) = vm.table_mut(r) {
            let _ = t.set("maxinteger".into(), Value::Int(i64::MAX), usize::MAX);
            let _ = t.set("mininteger".into(), Value::Int(i64::MIN), usize::MAX);
        }
    }
    vm.lib(
        "list",
        &[
            ("list.filter", l_filter),
            ("list.map", l_map),
            ("list.count", l_count),
            ("list.any", l_any),
            ("list.all", l_all),
            ("list.sum", l_sum),
            ("list.sort_by", l_sort_by),
        ],
    );
}

/// The load error for a global that does not exist, with a hint for the
/// things the sandbox leaves out on purpose.
pub(crate) fn undefined_global(name: &str) -> String {
    let why = match name {
        "setmetatable" | "getmetatable" => "metatables are not supported",
        "rawset" | "rawget" | "rawequal" | "rawlen" => "raw access is not available (there are no metatables)",
        "coroutine" => "coroutines are not supported",
        "load" | "loadstring" | "loadfile" | "dofile" | "require" | "package" => "scripts cannot load code",
        "io" | "os" | "debug" | "collectgarbage" | "print" | "utf8" => "not available in the sandbox",
        "unpack" => "use table.unpack",
        _ => return format!("undefined global '{name}'"),
    };
    format!("'{name}' is not available: {why}")
}

fn tref(a: &Args, i: usize) -> Result<Ref, Error> {
    match a.table(i)? {
        Value::Table(r) => Ok(r),
        _ => Err(a.bad(i, "table expected")),
    }
}

fn call1<H: Host>(h: &mut H, f: &Value, args: &[Value]) -> Result<Value, Error> {
    Ok(call(h, f, args)?.into_iter().next().unwrap_or_default())
}

/// `a < b` for sorting: integers or strings.
fn less<H>(vm: &Vm<H>, a: &Value, b: &Value) -> Result<bool, Error> {
    match (a, b) {
        (Value::Int(x), Value::Int(y)) => Ok(x < y),
        (Value::Str(x), Value::Str(y)) => Ok(x < y),
        _ => {
            let (x, y) = (a.type_name(), b.type_name());
            Err(vm.rt_err(if x == y { format!("attempt to compare two {x} values") } else { format!("attempt to compare {x} with {y}") }))
        }
    }
}

/// Stable merge sort with a fallible comparator (`less(a, b)`: a goes first).
fn merge_sort<E>(v: Vec<Value>, less: &mut dyn FnMut(&Value, &Value) -> Result<bool, E>) -> Result<Vec<Value>, E> {
    let n = v.len();
    let mut src = v;
    let mut dst = src.clone();
    let mut w = 1;
    while w < n {
        let mut i = 0;
        while i < n {
            let mid = (i + w).min(n);
            let hi = (i + 2 * w).min(n);
            let (mut l, mut r) = (i, mid);
            for slot in dst.iter_mut().take(hi).skip(i) {
                let take_r = r < hi && (l == mid || less(&src[r], &src[l])?);
                if take_r {
                    *slot = src[r].clone();
                    r += 1;
                } else {
                    *slot = src[l].clone();
                    l += 1;
                }
            }
            i = hi;
        }
        std::mem::swap(&mut src, &mut dst);
        w *= 2;
    }
    Ok(src)
}

// ---------------------------------------------------------------- base

fn next<H: Host>(h: &mut H, a: Args) -> R {
    let r = tref(&a, 0)?;
    let vm = h.vm();
    vm.step(1)?;
    match vm.table(r)?.next(&a.get(1)) {
        Ok(Some((k, v))) => Ok(vec![k, v]),
        Ok(None) => Ok(vec![Value::Nil]),
        Err(()) => Err(Error::runtime("invalid key to 'next'")),
    }
}

fn inext<H: Host>(h: &mut H, a: Args) -> R {
    let r = tref(&a, 0)?;
    let i = a.int(1)?.saturating_add(1);
    let v = h.vm().table(r)?.get_int(i);
    Ok(if v.is_nil() { vec![Value::Nil] } else { vec![Value::Int(i), v] })
}

fn ipairs<H: Host>(_: &mut H, a: Args) -> R {
    let t = a.table(0)?;
    Ok(vec![Value::Native(INEXT), t, Value::Int(0)])
}

fn pairs<H: Host>(_: &mut H, a: Args) -> R {
    let t = a.table(0)?;
    Ok(vec![Value::Native(NEXT), t, Value::Nil])
}

fn type_<H: Host>(_: &mut H, a: Args) -> R {
    if a.is_empty() {
        return Err(a.bad(0, "value expected"));
    }
    Ok(vec![a.get(0).type_name().into()])
}

fn tostring<H: Host>(h: &mut H, a: Args) -> R {
    Ok(vec![match a.get(0) {
        v @ Value::Str(_) => v,
        v => h.vm().display(&v).into(),
    }])
}

fn parse_int(s: &str, base: u32) -> Option<i64> {
    let s = s.trim_matches(|c: char| c.is_ascii_whitespace());
    let (neg, s) = match s.as_bytes().first() {
        Some(b'-') => (true, &s[1..]),
        Some(b'+') => (false, &s[1..]),
        _ => (false, s),
    };
    let (s, base) = match (base, s.get(..2)) {
        (10, Some("0x" | "0X")) => (&s[2..], 16),
        _ => (s, base),
    };
    if s.is_empty() || !s.chars().all(|c| c.is_digit(base)) {
        return None;
    }
    let n = i128::from_str_radix(s, base).ok()?;
    i64::try_from(if neg { -n } else { n }).ok()
}

fn tonumber<H: Host>(_: &mut H, a: Args) -> R {
    let base = a.opt_int(1)?;
    let v = match (a.get(0), base) {
        (Value::Int(n), None) => Value::Int(n),
        (Value::Str(s), b) => {
            let b = b.unwrap_or(10);
            if !(2..=36).contains(&b) {
                return Err(a.bad(1, "base out of range"));
            }
            std::str::from_utf8(&s).ok().and_then(|s| parse_int(s, b as u32)).into()
        }
        (_, Some(_)) => return Err(a.bad(0, &format!("string expected, got {}", a.get(0).type_name()))),
        _ => Value::Nil,
    };
    Ok(vec![v])
}

fn select<H: Host>(_: &mut H, a: Args) -> R {
    let n = a.len() as i64 - 1;
    if a.get(0).as_bytes() == Some(b"#") {
        return Ok(vec![Value::Int(n)]);
    }
    let i = a.int(0)?;
    let i = if i < 0 { n + i } else if i == 0 { -1 } else { i - 1 };
    if i < 0 {
        return Err(a.bad(0, "index out of range"));
    }
    Ok(a.vals.into_iter().skip(1 + i as usize).collect())
}

fn error<H: Host>(h: &mut H, a: Args) -> R {
    let v = a.get(0);
    let level = a.opt_int(1)?.unwrap_or(1);
    let vm = h.vm();
    if let (Value::Str(s), true) = (&v, level > 0) {
        return Err(vm.locate(Error::runtime(String::from_utf8_lossy(s).into_owned()), level as usize));
    }
    let msg = match &v {
        Value::Str(s) => String::from_utf8_lossy(s).into_owned(),
        Value::Int(_) | Value::Bool(_) | Value::Nil => vm.display(&v),
        _ => format!("(error object is a {} value)", v.type_name()),
    };
    let mut e = Error::runtime(msg);
    e.value = v;
    e.traceback = vm.traceback();
    e.located = true;
    Err(e)
}

fn assert<H: Host>(h: &mut H, a: Args) -> R {
    if a.get(0).truthy() {
        return Ok(a.vals);
    }
    if a.len() < 2 || a.get(1).is_nil() {
        return Err(Error::runtime("assertion failed!"));
    }
    let v = a.get(1);
    let vm = h.vm();
    let mut e = Error::runtime(vm.display(&v));
    e.value = v;
    e.traceback = vm.traceback();
    e.located = true;
    Err(e)
}

fn pcall<H: Host>(h: &mut H, a: Args) -> R {
    if a.is_empty() {
        return Err(a.bad(0, "value expected"));
    }
    let f = a.get(0);
    let vm = h.vm();
    let (stack, calls, depth) = (vm.stack.len(), vm.calls.len(), vm.depth);
    match call(h, &f, &a.vals[1..]) {
        Ok(mut v) => {
            v.insert(0, Value::Bool(true));
            Ok(v)
        }
        Err(e) if e.kind() == crate::ErrorKind::Runtime => {
            let vm = h.vm();
            vm.stack.truncate(stack);
            vm.calls.truncate(calls);
            debug_assert_eq!(vm.depth, depth);
            Ok(vec![Value::Bool(false), e.value.clone()])
        }
        Err(e) => Err(e),
    }
}

// ---------------------------------------------------------------- table

fn border<H: Host>(h: &mut H, r: Ref) -> Result<i64, Error> {
    Ok(h.vm().table(r)?.border())
}

fn t_insert<H: Host>(h: &mut H, a: Args) -> R {
    let r = tref(&a, 0)?;
    let t = Value::Table(r);
    let n = border(h, r)?;
    let (pos, v) = match a.len() {
        2 => (n + 1, a.get(1)),
        3 => {
            let p = a.int(1)?;
            if p < 1 || p > n + 1 {
                return Err(a.bad(1, "position out of bounds"));
            }
            (p, a.get(2))
        }
        _ => return Err(Error::runtime("wrong number of arguments to 'insert'")),
    };
    let vm = h.vm();
    vm.step((n - pos + 1) as u64)?;
    let mut i = n;
    while i >= pos {
        let x = vm.table(r)?.get_int(i);
        vm.set_index(&t, Value::Int(i + 1), x, "")?;
        i -= 1;
    }
    vm.set_index(&t, Value::Int(pos), v, "")?;
    Ok(vec![])
}

fn t_remove<H: Host>(h: &mut H, a: Args) -> R {
    let r = tref(&a, 0)?;
    let t = Value::Table(r);
    let n = border(h, r)?;
    let mut pos = a.opt_int(1)?.unwrap_or(n);
    if pos != n && (pos < 1 || pos > n + 1) {
        return Err(a.bad(1, "position out of bounds"));
    }
    let vm = h.vm();
    let v = vm.table(r)?.get_int(pos);
    vm.step((n - pos).max(0) as u64 + 1)?;
    while pos < n {
        let x = vm.table(r)?.get_int(pos + 1);
        vm.set_index(&t, Value::Int(pos), x, "")?;
        pos += 1;
    }
    vm.set_index(&t, Value::Int(pos), Value::Nil, "")?;
    Ok(vec![v])
}

fn t_sort<H: Host>(h: &mut H, a: Args) -> R {
    let r = tref(&a, 0)?;
    let t = Value::Table(r);
    let comp = a.get(1);
    if !comp.is_nil() {
        a.func(1)?;
    }
    let vm = h.vm();
    if vm.table(r)?.readonly {
        return Err(Error::runtime("attempt to modify a read-only table"));
    }
    let items = vm.list_items(&t)?;
    vm.step(items.len() as u64)?;
    let sorted = merge_sort(items, &mut |x, y| {
        if comp.is_nil() {
            h.vm().step(1)?;
            less(h.vm(), x, y)
        } else {
            Ok(call1(h, &comp, &[x.clone(), y.clone()])?.truthy())
        }
    })?;
    let vm = h.vm();
    for (i, v) in sorted.into_iter().enumerate() {
        vm.set_index(&t, Value::from(i + 1), v, "")?;
    }
    Ok(vec![])
}

fn t_concat<H: Host>(h: &mut H, a: Args) -> R {
    let r = tref(&a, 0)?;
    let sep = match a.get(1) {
        Value::Nil => Vec::new(),
        Value::Str(s) => s.to_vec(),
        Value::Int(n) => n.to_string().into_bytes(),
        _ => return Err(a.bad(1, "string expected")),
    };
    let n = border(h, r)?;
    let i = a.opt_int(2)?.unwrap_or(1);
    let j = a.opt_int(3)?.unwrap_or(n);
    let vm = h.vm();
    let mut out = Vec::new();
    let mut k = i;
    while k <= j {
        vm.step(1)?;
        match vm.table(r)?.get_int(k) {
            Value::Str(s) => out.extend_from_slice(&s),
            Value::Int(x) => out.extend_from_slice(x.to_string().as_bytes()),
            v => return Err(Error::runtime(format!("invalid value (at index {k}) in table for 'concat' ({})", v.type_name()))),
        }
        vm.check_len(out.len())?;
        if k == j {
            break;
        }
        out.extend_from_slice(&sep);
        k += 1;
    }
    Ok(vec![vm.new_str(out)?])
}

fn t_unpack<H: Host>(h: &mut H, a: Args) -> R {
    let r = tref(&a, 0)?;
    let n = border(h, r)?;
    let i = a.opt_int(1)?.unwrap_or(1);
    let j = a.opt_int(2)?.unwrap_or(n);
    if i > j {
        return Ok(vec![]);
    }
    let vm = h.vm();
    let count = j as i128 - i as i128 + 1;
    if count > vm.limits.table_size as i128 {
        return Err(Error::runtime("too many results to unpack"));
    }
    vm.step(count as u64)?;
    let t = vm.table(r)?;
    Ok((i..=j).map(|k| t.get_int(k)).collect())
}

// ---------------------------------------------------------------- string

/// Lua's posrelatI: a start position, 1-based, clamped to >= 1.
fn start_pos(p: i64, len: i64) -> i64 {
    if p > 0 {
        p
    } else if p == 0 || p < -len {
        1
    } else {
        len + p + 1
    }
}

/// Lua's getendpos: an end position clamped to <= len.
fn end_pos(p: i64, len: i64) -> i64 {
    if p > len {
        len
    } else if p >= 0 {
        p
    } else if p < -len {
        0
    } else {
        len + p + 1
    }
}

fn s_len<H: Host>(_: &mut H, a: Args) -> R {
    Ok(vec![Value::from(a.bytes(0)?.len())])
}

fn s_sub<H: Host>(h: &mut H, a: Args) -> R {
    let s = a.bytes(0)?;
    let len = s.len() as i64;
    let i = start_pos(a.opt_int(1)?.unwrap_or(1), len);
    let j = end_pos(a.opt_int(2)?.unwrap_or(-1), len);
    let out = if i > j { Vec::new() } else { s[(i - 1) as usize..j as usize].to_vec() };
    Ok(vec![h.vm().new_str(out)?])
}

fn s_upper<H: Host>(h: &mut H, a: Args) -> R {
    let s = a.bytes(0)?;
    Ok(vec![h.vm().new_str(s.to_ascii_uppercase())?])
}

fn s_lower<H: Host>(h: &mut H, a: Args) -> R {
    let s = a.bytes(0)?;
    Ok(vec![h.vm().new_str(s.to_ascii_lowercase())?])
}

fn s_rep<H: Host>(h: &mut H, a: Args) -> R {
    let s = a.bytes(0)?;
    let n = a.int(1)?;
    let sep = match a.get(2) {
        Value::Nil => Vec::new(),
        _ => a.bytes(2)?.to_vec(),
    };
    if n <= 0 {
        return Ok(vec![Value::from("")]);
    }
    let vm = h.vm();
    let total = (s.len() as u128) * (n as u128) + (sep.len() as u128) * (n as u128 - 1);
    vm.check_len(usize::try_from(total).unwrap_or(usize::MAX))?;
    let mut out = Vec::with_capacity(total as usize);
    for k in 0..n {
        if k > 0 {
            out.extend_from_slice(&sep);
        }
        out.extend_from_slice(&s);
    }
    Ok(vec![vm.new_str(out)?])
}

fn s_format<H: Host>(h: &mut H, a: Args) -> R {
    let f = a.bytes(0)?;
    let vm = h.vm();
    let mut out = Vec::new();
    let mut arg = 1;
    let mut i = 0;
    while i < f.len() {
        let c = f[i];
        i += 1;
        if c != b'%' {
            out.push(c);
            continue;
        }
        let d = f.get(i).copied().unwrap_or(0);
        i += 1;
        match d {
            b'%' => out.push(b'%'),
            b'd' | b's' => {
                if arg >= a.len() {
                    return Err(a.bad(arg, "no value"));
                }
                if d == b'd' {
                    out.extend_from_slice(a.int(arg)?.to_string().as_bytes());
                } else {
                    match a.get(arg) {
                        Value::Str(s) => out.extend_from_slice(&s),
                        v => out.extend_from_slice(vm.display(&v).as_bytes()),
                    }
                }
                arg += 1;
            }
            _ => {
                return Err(Error::runtime(format!(
                    "invalid conversion '%{}' to 'format' (only %d, %s and %% are supported)",
                    d as char
                )))
            }
        }
        vm.check_len(out.len())?;
    }
    Ok(vec![vm.new_str(out)?])
}

fn s_find<H: Host>(h: &mut H, a: Args) -> R {
    let s = a.bytes(0)?;
    let p = a.bytes(1)?;
    let len = s.len() as i64;
    let init = start_pos(a.opt_int(2)?.unwrap_or(1), len);
    let plain = a.get(3).truthy();
    if !plain && p.iter().any(|c| b"^$*+?.([%-".contains(c)) {
        return Err(Error::runtime(
            "string.find: patterns are not supported (pass true as the 4th argument for a plain search)",
        ));
    }
    if init > len + 1 {
        return Ok(vec![Value::Nil]);
    }
    let from = (init - 1) as usize;
    h.vm().step((s.len() - from) as u64 / 16 + 1)?;
    let hit = if p.is_empty() { Some(0) } else { s[from..].windows(p.len()).position(|w| w == &p[..]) };
    Ok(match hit {
        Some(k) => {
            let st = (from + k + 1) as i64;
            vec![Value::Int(st), Value::Int(st + p.len() as i64 - 1)]
        }
        None => vec![Value::Nil],
    })
}

fn s_byte<H: Host>(_: &mut H, a: Args) -> R {
    let s = a.bytes(0)?;
    let len = s.len() as i64;
    let i = a.opt_int(1)?.unwrap_or(1);
    let i = start_pos(i, len);
    let j = end_pos(a.opt_int(2)?.unwrap_or(i), len);
    Ok(if i > j { vec![] } else { s[(i - 1) as usize..j as usize].iter().map(|b| Value::Int(*b as i64)).collect() })
}

fn s_char<H: Host>(h: &mut H, a: Args) -> R {
    let mut out = Vec::with_capacity(a.len());
    for i in 0..a.len() {
        let c = a.int(i)?;
        if !(0..=255).contains(&c) {
            return Err(a.bad(i, "value out of range"));
        }
        out.push(c as u8);
    }
    Ok(vec![h.vm().new_str(out)?])
}

// ---------------------------------------------------------------- math

fn ints(a: &Args) -> Result<Vec<i64>, Error> {
    if a.is_empty() {
        return Err(a.bad(0, "number expected, got no value"));
    }
    (0..a.len()).map(|i| a.int(i)).collect()
}

fn m_min<H: Host>(_: &mut H, a: Args) -> R {
    Ok(vec![Value::Int(ints(&a)?.into_iter().min().unwrap_or(0))])
}

fn m_max<H: Host>(_: &mut H, a: Args) -> R {
    Ok(vec![Value::Int(ints(&a)?.into_iter().max().unwrap_or(0))])
}

fn m_abs<H: Host>(_: &mut H, a: Args) -> R {
    let n = a.int(0)?;
    n.checked_abs().map(|v| vec![Value::Int(v)]).ok_or_else(|| Error::runtime("integer overflow in 'math.abs'"))
}

fn m_floor<H: Host>(_: &mut H, a: Args) -> R {
    Ok(vec![Value::Int(a.int(0)?)])
}

fn m_clamp<H: Host>(_: &mut H, a: Args) -> R {
    let (x, lo, hi) = (a.int(0)?, a.int(1)?, a.int(2)?);
    if lo > hi {
        return Err(a.bad(1, "min is greater than max"));
    }
    Ok(vec![Value::Int(x.clamp(lo, hi))])
}

// ---------------------------------------------------------------- list

fn items<H: Host>(h: &mut H, a: &Args) -> Result<Vec<Value>, Error> {
    let t = a.table(0)?;
    let vm = h.vm();
    let v = vm.list_items(&t)?;
    vm.step(v.len() as u64)?;
    Ok(v)
}

fn new_list<H: Host>(h: &mut H, vals: Vec<Value>) -> R {
    let vm = h.vm();
    let t = vm.new_table_charged()?;
    for (i, v) in vals.into_iter().enumerate() {
        vm.set_index(&t, Value::from(i + 1), v, "")?;
    }
    Ok(vec![t])
}

fn l_filter<H: Host>(h: &mut H, a: Args) -> R {
    let f = a.func(1)?;
    let mut out = Vec::new();
    for (i, v) in items(h, &a)?.into_iter().enumerate() {
        if call1(h, &f, &[v.clone(), Value::from(i + 1)])?.truthy() {
            out.push(v);
        }
    }
    new_list(h, out)
}

fn l_map<H: Host>(h: &mut H, a: Args) -> R {
    let f = a.func(1)?;
    let mut out = Vec::new();
    for (i, v) in items(h, &a)?.into_iter().enumerate() {
        let x = call1(h, &f, &[v, Value::from(i + 1)])?;
        if !x.is_nil() {
            out.push(x);
        }
    }
    new_list(h, out)
}

/// Calls the optional predicate `a[1]` on every item; returns the results.
fn tests<H: Host>(h: &mut H, a: &Args) -> Result<Vec<bool>, Error> {
    let f = a.get(1);
    if !f.is_nil() {
        a.func(1)?;
    }
    let mut out = Vec::new();
    for (i, v) in items(h, a)?.into_iter().enumerate() {
        out.push(f.is_nil() || call1(h, &f, &[v, Value::from(i + 1)])?.truthy());
    }
    Ok(out)
}

fn l_count<H: Host>(h: &mut H, a: Args) -> R {
    Ok(vec![Value::from(tests(h, &a)?.into_iter().filter(|b| *b).count())])
}

fn l_any<H: Host>(h: &mut H, a: Args) -> R {
    let f = a.func(1)?;
    for (i, v) in items(h, &a)?.into_iter().enumerate() {
        if call1(h, &f, &[v, Value::from(i + 1)])?.truthy() {
            return Ok(vec![Value::Bool(true)]);
        }
    }
    Ok(vec![Value::Bool(false)])
}

fn l_all<H: Host>(h: &mut H, a: Args) -> R {
    let f = a.func(1)?;
    for (i, v) in items(h, &a)?.into_iter().enumerate() {
        if !call1(h, &f, &[v, Value::from(i + 1)])?.truthy() {
            return Ok(vec![Value::Bool(false)]);
        }
    }
    Ok(vec![Value::Bool(true)])
}

fn l_sum<H: Host>(h: &mut H, a: Args) -> R {
    let f = a.get(1);
    if !f.is_nil() {
        a.func(1)?;
    }
    let mut s: i64 = 0;
    for (i, v) in items(h, &a)?.into_iter().enumerate() {
        let x = if f.is_nil() { v } else { call1(h, &f, &[v, Value::from(i + 1)])? };
        let Value::Int(x) = x else {
            return Err(Error::runtime(format!("list.sum: item {} is a {}, not a number", i + 1, x.type_name())));
        };
        s = s.checked_add(x).ok_or_else(|| Error::runtime("integer overflow in 'list.sum'"))?;
    }
    Ok(vec![Value::Int(s)])
}

fn l_sort_by<H: Host>(h: &mut H, a: Args) -> R {
    let f = a.func(1)?;
    let mut keyed = Vec::new();
    for v in items(h, &a)? {
        let k = call1(h, &f, std::slice::from_ref(&v))?;
        keyed.push((k, v));
    }
    // Sort indices by key, stably; then pick the items.
    let idx: Vec<Value> = (0..keyed.len()).map(Value::from).collect();
    let sorted = merge_sort(idx, &mut |x, y| {
        let (i, j) = (x.as_int().unwrap_or(0) as usize, y.as_int().unwrap_or(0) as usize);
        h.vm().step(1)?;
        less(h.vm(), &keyed[i].0, &keyed[j].0)
    })?;
    let out = sorted.into_iter().map(|i| keyed[i.as_int().unwrap_or(0) as usize].1.clone()).collect();
    new_list(h, out)
}
