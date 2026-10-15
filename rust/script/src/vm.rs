//! The heap, tables, the collector and the tree-walking executor.

use crate::parse::{Bin, Block, Call, Cap, Expr, Field, FuncDef, Proto, Target, S};
use crate::{stdlib, Args, Chunk, Error, ErrorKind, Host, Limits, NativeFn, Ref, Value};
use std::collections::{BTreeMap, HashMap};
use std::hash::{BuildHasherDefault, Hasher};
use std::sync::Arc;

type R<T> = Result<T, Error>;

/// Native stack guard: the sum, over active calls, of each function's
/// syntactic nesting plus `CALL_NEST`. Keeps the executor's recursion within
/// a 1 MiB stack (wasm's default) whatever the scripts do.
const NEST_BUDGET: u32 = 3000;
const CALL_NEST: u32 = 4;
const NONE: u32 = u32::MAX;

/// Native function indices the generic `for` runs inline.
pub(crate) const NEXT: u32 = 0;
pub(crate) const INEXT: u32 = 1;

// ---------------------------------------------------------------- tables

/// A small deterministic hasher (only used for lookups, never observable).
#[derive(Default, Clone, Copy)]
pub(crate) struct Fx(u64);

impl Hasher for Fx {
    fn write(&mut self, b: &[u8]) {
        for &x in b {
            self.write_u64(x as u64);
        }
    }
    fn write_u8(&mut self, x: u8) {
        self.write_u64(x as u64)
    }
    fn write_u32(&mut self, x: u32) {
        self.write_u64(x as u64)
    }
    fn write_usize(&mut self, x: usize) {
        self.write_u64(x as u64)
    }
    fn write_i64(&mut self, x: i64) {
        self.write_u64(x as u64)
    }
    fn write_isize(&mut self, x: isize) {
        self.write_u64(x as u64)
    }
    fn write_u64(&mut self, x: u64) {
        self.0 = (self.0.rotate_left(5) ^ x).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    }
    fn finish(&self) -> u64 {
        self.0
    }
}

/// A table: one map in insertion order. Removing a key leaves a tombstone
/// (nil value) so `next` keeps working while a loop clears fields.
#[derive(Clone, Default, Debug)]
pub(crate) struct Table {
    keys: Vec<Value>,
    vals: Vec<Value>,
    index: HashMap<Value, u32, BuildHasherDefault<Fx>>,
    live: usize,
    pub readonly: bool,
}

pub(crate) enum SetErr {
    NilKey,
    Full,
}

impl Table {
    pub fn get(&self, k: &Value) -> Value {
        match self.index.get(k) {
            Some(&i) => self.vals[i as usize].clone(),
            None => Value::Nil,
        }
    }

    pub fn get_int(&self, i: i64) -> Value {
        self.get(&Value::Int(i))
    }

    /// Ok(true) when a new key was added. A key added again after its removal
    /// goes to the end of the order, like any new key.
    pub fn set(&mut self, k: Value, v: Value, max: usize) -> Result<bool, SetErr> {
        if let Some(&i) = self.index.get(&k) {
            let slot = &mut self.vals[i as usize];
            if !slot.is_nil() {
                if v.is_nil() {
                    self.live -= 1;
                }
                *slot = v;
                return Ok(false);
            }
        }
        if v.is_nil() {
            return Ok(false);
        }
        if k.is_nil() {
            return Err(SetErr::NilKey);
        }
        if self.live >= max {
            return Err(SetErr::Full);
        }
        if self.keys.len() >= 2 * self.live + 16 {
            self.compact();
        }
        self.index.insert(k.clone(), self.keys.len() as u32);
        self.keys.push(k);
        self.vals.push(v);
        self.live += 1;
        Ok(true)
    }

    fn compact(&mut self) {
        let (keys, vals) = (std::mem::take(&mut self.keys), std::mem::take(&mut self.vals));
        self.index.clear();
        for (k, v) in keys.into_iter().zip(vals) {
            if !v.is_nil() {
                self.index.insert(k.clone(), self.keys.len() as u32);
                self.keys.push(k);
                self.vals.push(v);
            }
        }
    }

    /// The entry after `k` (nil: the first), in insertion order; Err for an unknown key.
    pub fn next(&self, k: &Value) -> Result<Option<(Value, Value)>, ()> {
        let start = match k {
            Value::Nil => 0,
            _ => *self.index.get(k).ok_or(())? as usize + 1,
        };
        Ok((start..self.keys.len()).find(|&i| !self.vals[i].is_nil()).map(|i| (self.keys[i].clone(), self.vals[i].clone())))
    }

    /// A border: n with t[n] ~= nil and t[n+1] == nil (0 if t[1] is nil).
    pub fn border(&self) -> i64 {
        if self.get_int(1).is_nil() {
            return 0;
        }
        let (mut i, mut j) = (1i64, 2i64);
        while !self.get_int(j).is_nil() {
            i = j;
            j = j.saturating_mul(2);
            if j == i64::MAX {
                break;
            }
        }
        while j - i > 1 {
            let m = i + (j - i) / 2;
            if self.get_int(m).is_nil() {
                j = m;
            } else {
                i = m;
            }
        }
        i
    }

    pub fn entries(&self) -> impl Iterator<Item = (&Value, &Value)> {
        self.keys.iter().zip(&self.vals).filter(|(_, v)| !v.is_nil())
    }
}

// ---------------------------------------------------------------- heap

#[derive(Clone, Debug)]
pub(crate) struct Closure {
    pub proto: Arc<Proto>,
    pub upvals: Arc<[Ref]>,
    pub env: u32,
}

#[derive(Clone, Debug)]
enum Obj {
    Free(u32),
    Table(Table),
    Func(Closure),
    Cell(Value),
}

#[derive(Clone, Debug)]
struct Slot {
    gen: u32,
    obj: Obj,
}

#[derive(Clone, Debug)]
pub(crate) struct CallInfo {
    pub proto: Arc<Proto>,
    pub line: u32,
}

/// A virtual machine: heap, globals, loaded modules and host functions.
/// `Clone` copies the whole Lua state (for game-state snapshots).
pub struct Vm<H> {
    heap: Vec<Slot>,
    free: u32,
    live: usize,
    gc_next: usize,
    pub(crate) stack: Vec<Value>,
    globals: BTreeMap<String, Value>,
    envs: Vec<Vec<Value>>,
    modules: BTreeMap<String, Value>,
    pinned: Vec<Value>,
    pub(crate) natives: Vec<(&'static str, NativeFn<H>)>,
    pub(crate) calls: Vec<CallInfo>,
    pub limits: Limits,
    pub(crate) steps: u64,
    alloc: u64,
    pub(crate) depth: u32,
    nest: u32,
    pub(crate) string_lib: Value,
}

impl<H> Clone for Vm<H> {
    fn clone(&self) -> Self {
        Vm {
            heap: self.heap.clone(),
            free: self.free,
            live: self.live,
            gc_next: self.gc_next,
            stack: self.stack.clone(),
            globals: self.globals.clone(),
            envs: self.envs.clone(),
            modules: self.modules.clone(),
            pinned: self.pinned.clone(),
            natives: self.natives.clone(),
            calls: self.calls.clone(),
            limits: self.limits,
            steps: self.steps,
            alloc: self.alloc,
            depth: self.depth,
            nest: self.nest,
            string_lib: self.string_lib.clone(),
        }
    }
}

impl<H: Host> Default for Vm<H> {
    fn default() -> Self {
        Self::new()
    }
}

impl<H: Host> Vm<H> {
    /// A VM with the standard library and default limits.
    pub fn new() -> Self {
        let limits = Limits::default();
        let mut vm = Vm {
            heap: Vec::new(),
            free: NONE,
            live: 0,
            gc_next: 4096,
            stack: Vec::new(),
            globals: BTreeMap::new(),
            envs: Vec::new(),
            modules: BTreeMap::new(),
            pinned: Vec::new(),
            natives: Vec::new(),
            calls: Vec::new(),
            limits,
            steps: limits.steps,
            alloc: limits.alloc,
            depth: 0,
            nest: 0,
            string_lib: Value::Nil,
        };
        stdlib::install(&mut vm);
        vm
    }
}

impl<H> Vm<H> {

    /// Registers a host function; the result can be stored anywhere (a global, a table field).
    pub fn register(&mut self, name: &'static str, f: NativeFn<H>) -> Value {
        self.natives.push((name, f));
        Value::Native((self.natives.len() - 1) as u32)
    }

    /// A read-only global table of host functions:
    /// `lib("g", &[("g.damage", damage)])` makes `g.damage`. The full name
    /// ("g.damage") is what argument errors show; the table key is its last part.
    pub fn lib(&mut self, name: &str, fns: &[(&'static str, NativeFn<H>)]) -> Value {
        let t = self.new_table();
        for (n, f) in fns {
            let v = self.register(n, *f);
            let key = n.rsplit('.').next().unwrap_or(n);
            let _ = self.set(&t, key, v);
        }
        self.freeze(&t);
        self.set_global(name, t.clone());
        t
    }

    /// Sets a global. Chunks see the globals that exist when they are loaded.
    pub fn set_global(&mut self, name: &str, v: Value) {
        self.globals.insert(name.to_string(), v);
    }

    pub fn global(&self, name: &str) -> Value {
        self.globals.get(name).cloned().unwrap_or_default()
    }

    /// A loaded module's value (what its chunk returned).
    pub fn module(&self, name: &str) -> Value {
        self.modules.get(name).cloned().unwrap_or_default()
    }

    /// Forgets any call in progress. Only needed if a host function panicked
    /// and the panic was caught: the next call then starts fresh.
    pub fn reset(&mut self) {
        self.stack.clear();
        self.calls.clear();
        self.depth = 0;
        self.nest = 0;
    }

    /// Keeps a value alive across collections until `unpin_all`.
    pub fn pin(&mut self, v: Value) {
        self.pinned.push(v);
    }

    pub fn unpin_all(&mut self) {
        self.pinned.clear();
    }

    // ------------------------------------------------------------ heap access

    fn alloc_obj(&mut self, obj: Obj) -> Ref {
        self.live += 1;
        if self.free != NONE {
            let idx = self.free;
            let s = &mut self.heap[idx as usize];
            if let Obj::Free(next) = s.obj {
                self.free = next;
            }
            s.obj = obj;
            return Ref { idx, gen: s.gen };
        }
        self.heap.push(Slot { gen: 0, obj });
        Ref { idx: (self.heap.len() - 1) as u32, gen: 0 }
    }

    /// Charges the allocation budget (only inside a call: the host's own
    /// allocations between calls are free).
    pub(crate) fn charge(&mut self, bytes: u64) -> R<()> {
        if self.depth == 0 {
            return Ok(());
        }
        if self.alloc < bytes {
            self.alloc = 0;
            return Err(self.limit_err(format!("memory limit exceeded ({} bytes per call)", self.limits.alloc)));
        }
        self.alloc -= bytes;
        Ok(())
    }

    /// Charges `n` steps (library functions that loop).
    pub(crate) fn step(&mut self, n: u64) -> R<()> {
        if self.steps < n {
            self.steps = 0;
            return Err(self.limit_err(format!("step limit exceeded ({} steps per call)", self.limits.steps)));
        }
        self.steps -= n;
        Ok(())
    }

    fn slot(&self, r: Ref) -> R<&Obj> {
        match self.heap.get(r.idx as usize) {
            Some(s) if s.gen == r.gen && !matches!(s.obj, Obj::Free(_)) => Ok(&s.obj),
            _ => Err(Error::fatal("stale reference to a collected Lua object")),
        }
    }

    fn slot_mut(&mut self, r: Ref) -> R<&mut Obj> {
        match self.heap.get_mut(r.idx as usize) {
            Some(s) if s.gen == r.gen && !matches!(s.obj, Obj::Free(_)) => Ok(&mut s.obj),
            _ => Err(Error::fatal("stale reference to a collected Lua object")),
        }
    }

    pub(crate) fn table(&self, r: Ref) -> R<&Table> {
        match self.slot(r)? {
            Obj::Table(t) => Ok(t),
            _ => Err(Error::fatal("not a table")),
        }
    }

    pub(crate) fn table_mut(&mut self, r: Ref) -> R<&mut Table> {
        match self.slot_mut(r)? {
            Obj::Table(t) => Ok(t),
            _ => Err(Error::fatal("not a table")),
        }
    }

    fn closure(&self, r: Ref) -> R<&Closure> {
        match self.slot(r)? {
            Obj::Func(c) => Ok(c),
            _ => Err(Error::fatal("not a function")),
        }
    }

    fn cell(&self, r: Ref) -> R<Value> {
        match self.slot(r)? {
            Obj::Cell(v) => Ok(v.clone()),
            _ => Err(Error::fatal("not a cell")),
        }
    }

    fn cell_set(&mut self, r: Ref, v: Value) -> R<()> {
        match self.slot_mut(r)? {
            Obj::Cell(c) => {
                *c = v;
                Ok(())
            }
            _ => Err(Error::fatal("not a cell")),
        }
    }

    fn new_cell(&mut self, v: Value) -> R<Ref> {
        self.charge(16)?;
        Ok(self.alloc_obj(Obj::Cell(v)))
    }

    // ------------------------------------------------------------ public value helpers

    /// A new empty table.
    pub fn new_table(&mut self) -> Value {
        Value::Table(self.alloc_obj(Obj::Table(Table::default())))
    }

    pub(crate) fn new_table_charged(&mut self) -> R<Value> {
        self.charge(64)?;
        Ok(self.new_table())
    }

    /// A table {v1, v2, ...}.
    pub fn list(&mut self, vals: Vec<Value>) -> R<Value> {
        let t = self.new_table();
        for (i, v) in vals.into_iter().enumerate() {
            self.set(&t, Value::from(i + 1), v)?;
        }
        Ok(t)
    }

    /// A string value, checked against the string limit and charged.
    pub(crate) fn new_str(&mut self, b: Vec<u8>) -> R<Value> {
        self.check_len(b.len())?;
        self.charge(b.len() as u64 + 16)?;
        Ok(Value::Str(b.into()))
    }

    pub(crate) fn check_len(&self, n: usize) -> R<()> {
        if n > self.limits.string_len {
            return Err(self.limit_err(format!("string length limit exceeded ({} bytes)", self.limits.string_len)));
        }
        Ok(())
    }

    /// `t[k]` for a table (no error for missing keys).
    pub fn get(&self, t: &Value, k: impl Into<Value>) -> R<Value> {
        match t {
            Value::Table(r) => Ok(self.table(*r)?.get(&k.into())),
            v => Err(Error::runtime(format!("attempt to index a {} value", v.type_name()))),
        }
    }

    /// `t[k] = v`, with Lua's checks (nil key, read-only, table size).
    pub fn set(&mut self, t: &Value, k: impl Into<Value>, v: impl Into<Value>) -> R<()> {
        self.set_index(t, k.into(), v.into(), "")
    }

    /// t[1], t[2], ... up to the first nil.
    pub fn list_items(&self, t: &Value) -> R<Vec<Value>> {
        let Value::Table(r) = t else { return Err(Error::runtime(format!("table expected, got {}", t.type_name()))) };
        let t = self.table(*r)?;
        let mut out = Vec::new();
        loop {
            let v = t.get_int(out.len() as i64 + 1);
            if v.is_nil() {
                return Ok(out);
            }
            out.push(v);
        }
    }

    /// All entries in iteration (insertion) order.
    pub fn pairs(&self, t: &Value) -> R<Vec<(Value, Value)>> {
        let Value::Table(r) = t else { return Err(Error::runtime(format!("table expected, got {}", t.type_name()))) };
        Ok(self.table(*r)?.entries().map(|(k, v)| (k.clone(), v.clone())).collect())
    }

    /// Makes a table read-only (assignments to it are errors).
    pub fn freeze(&mut self, t: &Value) {
        if let Value::Table(r) = t {
            if let Ok(t) = self.table_mut(*r) {
                t.readonly = true;
            }
        }
    }

    /// Lua's `tostring`.
    pub fn display(&self, v: &Value) -> String {
        match v {
            Value::Nil => "nil".into(),
            Value::Bool(b) => b.to_string(),
            Value::Int(i) => i.to_string(),
            Value::Str(s) => String::from_utf8_lossy(s).into_owned(),
            Value::Table(r) => format!("table: #{}", r.idx),
            Value::Func(r) => format!("function: #{}", r.idx),
            Value::Native(i) => format!("function: builtin '{}'", self.natives.get(*i as usize).map_or("?", |n| n.0)),
            Value::Cell(_) => "cell".into(),
        }
    }

    // ------------------------------------------------------------ errors

    fn where_(&self, level: usize) -> String {
        match self.calls.len().checked_sub(level) {
            Some(i) => {
                let c = &self.calls[i];
                format!("{}:{}: ", c.proto.file, c.line)
            }
            None => String::new(),
        }
    }

    pub(crate) fn traceback(&self) -> Vec<String> {
        let n = self.calls.len();
        let mut out = Vec::new();
        for (k, c) in self.calls.iter().rev().enumerate() {
            if k == 10 && n > 12 {
                out.push(format!("... ({} more)", n - 11));
            }
            if k >= 10 && k + 1 < n && n > 12 {
                continue;
            }
            let what = if c.proto.name == "main chunk" { "in main chunk".into() } else { format!("in function '{}'", c.proto.name) };
            out.push(format!("{}:{}: {what}", c.proto.file, c.line));
        }
        out
    }

    /// Adds "file:line: " (of the Lua frame `level` up) and a traceback.
    pub(crate) fn locate(&self, mut e: Error, level: usize) -> Error {
        if !e.located {
            e.located = true;
            if level > 0 {
                e.message = format!("{}{}", self.where_(level), e.message);
                if let Value::Str(_) = e.value {
                    e.value = Value::from(e.message.as_str());
                }
            }
            e.traceback = self.traceback();
        }
        e
    }

    pub(crate) fn rt_err(&self, msg: String) -> Error {
        self.locate(Error::runtime(msg), 1)
    }

    fn limit_err(&self, msg: String) -> Error {
        self.locate(Error::new(ErrorKind::Limit, msg), 1)
    }

    // ------------------------------------------------------------ indexing

    pub(crate) fn index(&self, o: &Value, k: &Value) -> R<Value> {
        match o {
            Value::Table(r) => Ok(self.table(*r)?.get(k)),
            Value::Str(_) if matches!(k, Value::Str(_)) => self.index(&self.string_lib, k),
            _ => Err(Error::runtime(format!("attempt to index a {} value", o.type_name()))),
        }
    }

    pub(crate) fn set_index(&mut self, o: &Value, k: Value, v: Value, what: &str) -> R<()> {
        let Value::Table(r) = o else {
            return Err(self.rt_err(format!("attempt to index a {} value{what}", o.type_name())));
        };
        let max = self.limits.table_size;
        let t = self.table_mut(*r)?;
        if t.readonly {
            return Err(self.rt_err(format!("attempt to modify a read-only table{what}")));
        }
        match t.set(k, v, max) {
            Ok(true) => self.charge(32),
            Ok(false) => Ok(()),
            Err(SetErr::NilKey) => Err(self.rt_err("table index is nil".into())),
            Err(SetErr::Full) => Err(self.limit_err(format!("table size limit exceeded ({max} entries)"))),
        }
    }

    // ------------------------------------------------------------ collector

    /// Frees every object not reachable from the roots: globals, modules,
    /// pinned values, the value stack and `extra`.
    pub fn collect(&mut self, extra: &[Value]) {
        let mut mark = vec![false; self.heap.len()];
        let mut work: Vec<u32> = Vec::new();
        fn push(heap: &[Slot], mark: &mut [bool], work: &mut Vec<u32>, v: &Value) {
            if let Value::Table(r) | Value::Func(r) | Value::Cell(r) = v {
                push_ref(heap, mark, work, *r);
            }
        }
        fn push_ref(heap: &[Slot], mark: &mut [bool], work: &mut Vec<u32>, r: Ref) {
            let i = r.idx as usize;
            if i < heap.len() && heap[i].gen == r.gen && !mark[i] {
                mark[i] = true;
                work.push(r.idx);
            }
        }
        let roots = self
            .stack
            .iter()
            .chain(self.globals.values())
            .chain(self.envs.iter().flatten())
            .chain(self.modules.values())
            .chain(&self.pinned)
            .chain(std::iter::once(&self.string_lib))
            .chain(extra);
        for v in roots {
            push(&self.heap, &mut mark, &mut work, v);
        }
        while let Some(i) = work.pop() {
            match &self.heap[i as usize].obj {
                Obj::Table(t) => {
                    for v in t.keys.iter().chain(&t.vals) {
                        push(&self.heap, &mut mark, &mut work, v);
                    }
                }
                Obj::Func(c) => {
                    for r in c.upvals.iter() {
                        push_ref(&self.heap, &mut mark, &mut work, *r);
                    }
                }
                Obj::Cell(v) => push(&self.heap, &mut mark, &mut work, v),
                Obj::Free(_) => {}
            }
        }
        for (i, s) in self.heap.iter_mut().enumerate() {
            if !mark[i] && !matches!(s.obj, Obj::Free(_)) {
                s.obj = Obj::Free(self.free);
                s.gen = s.gen.wrapping_add(1);
                self.free = i as u32;
                self.live -= 1;
            }
        }
        self.gc_next = (self.live * 2).max(4096);
    }

    /// Live heap objects (tables, closures, captured locals).
    pub fn heap_objects(&self) -> usize {
        self.live
    }
}

// ---------------------------------------------------------------- entry points

/// Loads a compiled chunk as module `name`: resolves its globals, runs it and
/// keeps what it returns (see [`Vm::module`]).
pub fn load<H: Host>(h: &mut H, name: &str, chunk: &Chunk) -> R<Value> {
    let vm = h.vm();
    let p = &chunk.0;
    let mut env = Vec::with_capacity(p.globals.len());
    for (g, line) in &p.globals {
        match vm.globals.get(&**g) {
            Some(v) => env.push(v.clone()),
            None => {
                let mut e =
                    Error::new(ErrorKind::Compile, format!("{}:{line}: {}", p.main.file, crate::stdlib::undefined_global(g)));
                e.located = true;
                return Err(e);
            }
        }
    }
    vm.envs.push(env);
    let env = (vm.envs.len() - 1) as u32;
    let f = Value::Func(vm.alloc_obj(Obj::Func(Closure { proto: p.main.clone(), upvals: Arc::from([]), env })));
    let r = call(h, &f, &[])?;
    let m = r.into_iter().next().unwrap_or_default();
    h.vm().modules.insert(name.to_string(), m.clone());
    Ok(m)
}

/// Calls a function value with arguments. From Rust at the top level it
/// resets the per-call budgets (and may collect garbage first); from inside a
/// host function it runs within the current call's budget.
pub fn call<H: Host>(h: &mut H, f: &Value, args: &[Value]) -> R<Vec<Value>> {
    let vm = h.vm();
    let top = vm.depth == 0;
    if top {
        vm.steps = vm.limits.steps;
        vm.alloc = vm.limits.alloc;
        vm.nest = 0;
        vm.stack.clear();
        vm.calls.clear();
        if vm.live > vm.gc_next {
            let mut extra = args.to_vec();
            extra.push(f.clone());
            vm.collect(&extra);
        }
    }
    let base = vm.stack.len();
    vm.stack.extend_from_slice(args);
    let r = call_value(h, f, base, &|| String::new());
    let vm = h.vm();
    match r {
        Ok(n) => {
            let out = vm.stack.drain(base..base + n).collect();
            vm.stack.truncate(base);
            Ok(out)
        }
        Err(e) => {
            vm.stack.truncate(base);
            Err(e)
        }
    }
}

/// Calls `module[path[0]][path[1]]...` (e.g. `["CS2_032", "spell"]`).
pub fn call_path<H: Host>(h: &mut H, module: &str, path: &[&str], args: &[Value]) -> R<Vec<Value>> {
    let f = get_path(h.vm(), module, path)?;
    call(h, &f, args)
}

/// `module[path[0]][path[1]]...`; nil when a step is missing.
pub fn get_path<H: Host>(vm: &Vm<H>, module: &str, path: &[&str]) -> R<Value> {
    let Some(mut v) = vm.modules.get(module).cloned() else {
        return Err(Error::fatal(format!("no module '{module}'")));
    };
    for k in path {
        if v.is_nil() {
            return Ok(Value::Nil);
        }
        v = vm.index(&v, &Value::from(*k))?;
    }
    Ok(v)
}

// ---------------------------------------------------------------- executor

struct Frame<'a> {
    base: usize,
    proto: &'a Proto,
    upvals: &'a [Ref],
    env: u32,
    varargs: Vec<Value>,
}

enum Flow {
    Normal,
    Break,
    /// n results on top of the stack.
    Return(usize),
}

/// Calls `f` with the arguments at stack[base..]; leaves the results at
/// stack[base..base+n] and returns n.
fn call_value<H: Host>(h: &mut H, f: &Value, base: usize, desc: &dyn Fn() -> String) -> R<usize> {
    match f {
        Value::Func(r) => {
            let cl = h.vm().closure(*r)?.clone();
            call_closure(h, &cl, base)
        }
        Value::Native(i) => {
            let vm = h.vm();
            let Some(&(name, fp)) = vm.natives.get(*i as usize) else { return Err(Error::fatal("bad native function")) };
            enter(vm, CALL_NEST)?;
            let vals: Vec<Value> = vm.stack.drain(base..).collect();
            let r = fp(h, Args { vals, name });
            let vm = h.vm();
            leave(vm, CALL_NEST);
            match r {
                Ok(v) => {
                    vm.stack.truncate(base);
                    let n = v.len();
                    vm.stack.extend(v);
                    Ok(n)
                }
                Err(e) => Err(vm.locate(e, 1)),
            }
        }
        v => {
            let vm = h.vm();
            Err(vm.rt_err(format!("attempt to call a {} value{}", v.type_name(), desc())))
        }
    }
}

fn enter<H>(vm: &mut Vm<H>, nest: u32) -> R<()> {
    if vm.depth >= vm.limits.depth {
        return Err(vm.limit_err(format!("stack overflow (call depth limit {})", vm.limits.depth)));
    }
    if vm.nest + nest > NEST_BUDGET {
        return Err(vm.limit_err("stack overflow (nesting of active calls too deep)".into()));
    }
    vm.depth += 1;
    vm.nest += nest;
    Ok(())
}

fn leave<H>(vm: &mut Vm<H>, nest: u32) {
    vm.depth -= 1;
    vm.nest -= nest;
}

fn call_closure<H: Host>(h: &mut H, cl: &Closure, base: usize) -> R<usize> {
    let p: &Proto = &cl.proto;
    let vm = h.vm();
    let nest = p.nest + CALL_NEST;
    enter(vm, nest)?;
    if let Err(e) = vm.step(1) {
        leave(vm, nest);
        return Err(e);
    }
    let nargs = vm.stack.len() - base;
    let varargs = if p.vararg && nargs > p.nparams {
        vm.stack.drain(base + p.nparams..).collect()
    } else {
        vm.stack.truncate(base + nargs.min(p.nparams));
        Vec::new()
    };
    vm.stack.resize(base + p.nslots, Value::Nil);
    vm.calls.push(CallInfo { proto: cl.proto.clone(), line: p.line });
    let fr = Frame { base, proto: p, upvals: &cl.upvals, env: cl.env, varargs };
    let mut r = Ok(Flow::Normal);
    for i in 0..p.nparams {
        if p.captured[i] {
            let v = std::mem::take(&mut vm.stack[base + i]);
            if let Err(e) = decl(vm, &fr, i as u16, v) {
                r = Err(e);
                break;
            }
        }
    }
    if r.is_ok() {
        r = exec_block(h, &fr, &p.body);
    }
    let vm = h.vm();
    vm.calls.pop();
    leave(vm, nest);
    match r? {
        Flow::Return(n) => {
            let start = vm.stack.len() - n;
            vm.stack.drain(base..start);
            Ok(n)
        }
        _ => {
            vm.stack.truncate(base);
            Ok(0)
        }
    }
}

fn decl<H>(vm: &mut Vm<H>, fr: &Frame, s: u16, v: Value) -> R<()> {
    let v = if fr.proto.captured[s as usize] { Value::Cell(vm.new_cell(v)?) } else { v };
    vm.stack[fr.base + s as usize] = v;
    Ok(())
}

fn set_local<H>(vm: &mut Vm<H>, fr: &Frame, s: u16, v: Value) -> R<()> {
    let slot = &mut vm.stack[fr.base + s as usize];
    if let Value::Cell(c) = slot {
        let c = *c;
        vm.cell_set(c, v)
    } else {
        *slot = v;
        Ok(())
    }
}

fn get_local<H>(vm: &Vm<H>, fr: &Frame, s: u16) -> R<Value> {
    match &vm.stack[fr.base + s as usize] {
        Value::Cell(c) => vm.cell(*c),
        v => Ok(v.clone()),
    }
}

// The executor recurses through `exec_block` and `eval`; their frames are kept
// small by moving every bulky statement and expression into its own
// non-inlined function (this is what lets 200 nested calls fit a 1 MiB stack).

fn exec_block<H: Host>(h: &mut H, fr: &Frame, b: &Block) -> R<Flow> {
    for st in b {
        let vm = h.vm();
        if vm.steps == 0 {
            vm.step(1)?;
        }
        vm.steps -= 1;
        if let Some(c) = vm.calls.last_mut() {
            c.line = st.line;
        }
        let flow = match &st.kind {
            S::Local(slots, exprs) => exec_local(h, fr, slots, exprs)?,
            S::LocalFunc(s, fd) => exec_local_func(h.vm(), fr, *s, fd)?,
            S::Assign(targets, exprs) => exec_assign(h, fr, targets, exprs)?,
            S::Call(c) => exec_call(h, fr, c)?,
            S::Do(b) => exec_block(h, fr, b)?,
            S::While(c, b) => exec_while(h, fr, c, b)?,
            S::Repeat(b, c) => exec_repeat(h, fr, b, c)?,
            S::If(arms, other) => exec_if(h, fr, arms, other.as_ref())?,
            S::NumFor(slot, e, body) => exec_numfor(h, fr, *slot, e, body)?,
            S::GenFor(slots, exprs, body) => exec_genfor(h, fr, slots, exprs, body)?,
            S::Return(exprs) => return exec_return(h, fr, exprs),
            S::Break => return Ok(Flow::Break),
        };
        if !matches!(flow, Flow::Normal) {
            return Ok(flow);
        }
    }
    Ok(Flow::Normal)
}

#[inline(never)]
fn exec_local<H: Host>(h: &mut H, fr: &Frame, slots: &[u16], exprs: &[Expr]) -> R<Flow> {
    if slots.len() == 1 && exprs.len() == 1 {
        let v = eval(h, fr, &exprs[0])?;
        decl(h.vm(), fr, slots[0], v)?;
    } else {
        let start = h.vm().stack.len();
        eval_list(h, fr, exprs, Some(slots.len()))?;
        let vm = h.vm();
        let vals: Vec<Value> = vm.stack.drain(start..).collect();
        for (s, v) in slots.iter().zip(vals) {
            decl(vm, fr, *s, v)?;
        }
    }
    Ok(Flow::Normal)
}

#[inline(never)]
fn exec_local_func<H>(vm: &mut Vm<H>, fr: &Frame, s: u16, fd: &FuncDef) -> R<Flow> {
    decl(vm, fr, s, Value::Nil)?;
    let f = make_closure(vm, fr, fd)?;
    set_local(vm, fr, s, f)?;
    Ok(Flow::Normal)
}

#[inline(never)]
fn exec_assign<H: Host>(h: &mut H, fr: &Frame, targets: &[Target], exprs: &[Expr]) -> R<Flow> {
    if targets.len() == 1 && exprs.len() == 1 {
        match &targets[0] {
            Target::Local(s) => {
                let v = eval(h, fr, &exprs[0])?;
                set_local(h.vm(), fr, *s, v)?;
            }
            Target::Upval(u) => {
                let v = eval(h, fr, &exprs[0])?;
                h.vm().cell_set(fr.upvals[*u as usize], v)?;
            }
            Target::Index(o, k) => {
                let ov = eval(h, fr, o)?;
                let kv = eval(h, fr, k)?;
                let v = eval(h, fr, &exprs[0])?;
                let what = describe(fr, o);
                h.vm().set_index(&ov, kv, v, &what)?;
            }
        }
        return Ok(Flow::Normal);
    }
    // Lua order: the target tables and keys, then the values, then the stores left to right.
    let mut places = Vec::with_capacity(targets.len());
    for t in targets {
        if let Target::Index(o, k) = t {
            let ov = eval(h, fr, o)?;
            let kv = eval(h, fr, k)?;
            places.push(Some((ov, kv)));
        } else {
            places.push(None);
        }
    }
    let start = h.vm().stack.len();
    eval_list(h, fr, exprs, Some(targets.len()))?;
    let vm = h.vm();
    let vals: Vec<Value> = vm.stack.drain(start..).collect();
    for ((t, place), v) in targets.iter().zip(places).zip(vals) {
        match (t, place) {
            (Target::Local(s), _) => set_local(vm, fr, *s, v)?,
            (Target::Upval(u), _) => vm.cell_set(fr.upvals[*u as usize], v)?,
            (Target::Index(o, _), Some((ov, kv))) => {
                let what = describe(fr, o);
                vm.set_index(&ov, kv, v, &what)?
            }
            (Target::Index(..), None) => {}
        }
    }
    Ok(Flow::Normal)
}

#[inline(never)]
fn exec_call<H: Host>(h: &mut H, fr: &Frame, c: &Call) -> R<Flow> {
    let start = h.vm().stack.len();
    eval_call(h, fr, c)?;
    h.vm().stack.truncate(start);
    Ok(Flow::Normal)
}

#[inline(never)]
fn exec_while<H: Host>(h: &mut H, fr: &Frame, c: &Expr, b: &Block) -> R<Flow> {
    loop {
        h.vm().step(1)?;
        if !eval(h, fr, c)?.truthy() {
            return Ok(Flow::Normal);
        }
        match exec_block(h, fr, b)? {
            Flow::Normal => {}
            Flow::Break => return Ok(Flow::Normal),
            f => return Ok(f),
        }
    }
}

#[inline(never)]
fn exec_repeat<H: Host>(h: &mut H, fr: &Frame, b: &Block, c: &Expr) -> R<Flow> {
    loop {
        h.vm().step(1)?;
        match exec_block(h, fr, b)? {
            Flow::Normal => {}
            Flow::Break => return Ok(Flow::Normal),
            f => return Ok(f),
        }
        if eval(h, fr, c)?.truthy() {
            return Ok(Flow::Normal);
        }
    }
}

#[inline(never)]
fn exec_if<H: Host>(h: &mut H, fr: &Frame, arms: &[(Expr, Block)], other: Option<&Block>) -> R<Flow> {
    for (c, b) in arms {
        if eval(h, fr, c)?.truthy() {
            return exec_block(h, fr, b);
        }
    }
    match other {
        Some(b) => exec_block(h, fr, b),
        None => Ok(Flow::Normal),
    }
}

#[inline(never)]
fn exec_numfor<H: Host>(h: &mut H, fr: &Frame, slot: u16, e: &[Expr; 3], body: &Block) -> R<Flow> {
    let mut v = [0i64; 3];
    for (i, what) in ["initial", "limit", "step"].iter().enumerate() {
        match eval(h, fr, &e[i])? {
            Value::Int(n) => v[i] = n,
            x => return Err(h.vm().rt_err(format!("'for' {what} value must be a number, got {}", x.type_name()))),
        }
    }
    let [a, b, s] = v;
    if s == 0 {
        return Err(h.vm().rt_err("'for' step is zero".into()));
    }
    if (s > 0 && a > b) || (s < 0 && a < b) {
        return Ok(Flow::Normal);
    }
    // The iteration count is fixed up front (as in Lua 5.4), so the loop never overflows.
    let count = ((b as i128 - a as i128) / s as i128) as u64;
    let mut i: u64 = 0;
    loop {
        let x = (a as i128 + i as i128 * s as i128) as i64;
        let vm = h.vm();
        vm.step(1)?;
        decl(vm, fr, slot, Value::Int(x))?;
        match exec_block(h, fr, body)? {
            Flow::Normal => {}
            Flow::Break => return Ok(Flow::Normal),
            f => return Ok(f),
        }
        if i == count {
            return Ok(Flow::Normal);
        }
        i += 1;
    }
}

#[inline(never)]
fn exec_genfor<H: Host>(h: &mut H, fr: &Frame, slots: &[u16], exprs: &[Expr], body: &Block) -> R<Flow> {
    let start = h.vm().stack.len();
    eval_list(h, fr, exprs, Some(3))?;
    let vm = h.vm();
    let mut it: Vec<Value> = vm.stack.drain(start..).collect();
    let mut ctl = std::mem::take(&mut it[2]);
    let (f, s) = (std::mem::take(&mut it[0]), std::mem::take(&mut it[1]));
    loop {
        let Some((k, v)) = gen_next(h, &f, &s, &ctl)? else { return Ok(Flow::Normal) };
        ctl = k.clone();
        let vm = h.vm();
        for (j, sl) in slots.iter().enumerate() {
            let x = match j {
                0 => k.clone(),
                1 => v.clone(),
                _ => Value::Nil,
            };
            decl(vm, fr, *sl, x)?;
        }
        match exec_block(h, fr, body)? {
            Flow::Normal => {}
            Flow::Break => return Ok(Flow::Normal),
            f => return Ok(f),
        }
    }
}

/// One step of a generic `for`: `next` and the `ipairs` iterator run inline.
fn gen_next<H: Host>(h: &mut H, f: &Value, s: &Value, ctl: &Value) -> R<Option<(Value, Value)>> {
    let vm = h.vm();
    vm.step(1)?;
    match (f, s) {
        (Value::Native(NEXT), Value::Table(r)) => match vm.table(*r)?.next(ctl) {
            Ok(kv) => Ok(kv),
            Err(()) => Err(vm.rt_err("invalid key to 'next'".into())),
        },
        (Value::Native(INEXT), Value::Table(r)) => {
            let i = ctl.as_int().unwrap_or(0).saturating_add(1);
            let v = vm.table(*r)?.get_int(i);
            Ok(if v.is_nil() { None } else { Some((Value::Int(i), v)) })
        }
        _ => {
            let base = vm.stack.len();
            vm.stack.push(s.clone());
            vm.stack.push(ctl.clone());
            let n = call_value(h, f, base, &|| " (for iterator)".into())?;
            let vm = h.vm();
            let mut r: Vec<Value> = vm.stack.drain(base..base + n).collect();
            vm.stack.truncate(base);
            r.resize(2, Value::Nil);
            if r[0].is_nil() {
                return Ok(None);
            }
            let v = r.pop().unwrap_or_default();
            Ok(Some((r.pop().unwrap_or_default(), v)))
        }
    }
}

#[inline(never)]
fn exec_return<H: Host>(h: &mut H, fr: &Frame, exprs: &[Expr]) -> R<Flow> {
    if exprs.len() == 1 && !matches!(exprs[0], Expr::Call(_) | Expr::Vararg) {
        let v = eval(h, fr, &exprs[0])?;
        h.vm().stack.push(v);
        return Ok(Flow::Return(1));
    }
    let n = eval_list(h, fr, exprs, None)?;
    Ok(Flow::Return(n))
}

/// Pushes the values of `exprs` (the last one expanded) and adjusts the
/// count to `want`. Returns the number pushed.
fn eval_list<H: Host>(h: &mut H, fr: &Frame, exprs: &[Expr], want: Option<usize>) -> R<usize> {
    let start = h.vm().stack.len();
    for (i, e) in exprs.iter().enumerate() {
        let last = i + 1 == exprs.len();
        match e {
            Expr::Call(c) if last => {
                eval_call(h, fr, c)?;
            }
            Expr::Vararg if last => {
                let vm = h.vm();
                vm.charge(8 * fr.varargs.len() as u64)?;
                vm.stack.extend_from_slice(&fr.varargs);
            }
            _ => {
                let v = eval(h, fr, e)?;
                h.vm().stack.push(v);
            }
        }
    }
    let vm = h.vm();
    if let Some(w) = want {
        vm.stack.resize(start + w, Value::Nil);
    }
    Ok(vm.stack.len() - start)
}

/// Evaluates a call; the results are at the old stack top. Returns their count.
fn eval_call<H: Host>(h: &mut H, fr: &Frame, c: &Call) -> R<usize> {
    let (f, base) = if let Some(m) = &c.method {
        let obj = eval(h, fr, &c.f)?;
        let vm = h.vm();
        let f = match vm.index(&obj, &Value::Str(m.clone())) {
            Err(e) if e.kind() == ErrorKind::Runtime => {
                return Err(vm.rt_err(format!("{}{}", e.message, describe(fr, &c.f))))
            }
            r => r?,
        };
        let base = vm.stack.len();
        vm.stack.push(obj);
        (f, base)
    } else {
        let f = eval(h, fr, &c.f)?;
        (f, h.vm().stack.len())
    };
    eval_list(h, fr, &c.args, None)?;
    let vm = h.vm();
    if let Some(ci) = vm.calls.last_mut() {
        ci.line = c.line;
    }
    let desc = || match &c.method {
        Some(m) => format!(" (method '{}')", String::from_utf8_lossy(m)),
        None => describe(fr, &c.f),
    };
    call_value(h, &f, base, &desc)
}

/// " (local 'x')" etc. for error messages.
fn describe(fr: &Frame, e: &Expr) -> String {
    match e {
        Expr::Local(s) => format!(" (local '{}')", fr.proto.slot_names[*s as usize]),
        Expr::Upval(u) => format!(" (upvalue '{}')", fr.proto.upval_names[*u as usize]),
        Expr::Global(_, n) => format!(" (global '{n}')"),
        Expr::Index(b) => match &b.1 {
            Expr::Str(k) => format!(" (field '{}')", String::from_utf8_lossy(k)),
            _ => String::new(),
        },
        _ => String::new(),
    }
}

fn make_closure<H>(vm: &mut Vm<H>, fr: &Frame, fd: &FuncDef) -> R<Value> {
    vm.charge(32 + 8 * fd.caps.len() as u64)?;
    let mut ups = Vec::with_capacity(fd.caps.len());
    for c in &fd.caps {
        ups.push(match c {
            Cap::Upval(u) => fr.upvals[*u as usize],
            Cap::Local(s) => {
                let i = fr.base + *s as usize;
                match vm.stack[i] {
                    Value::Cell(r) => r,
                    _ => {
                        let v = std::mem::take(&mut vm.stack[i]);
                        let r = vm.new_cell(v)?;
                        vm.stack[i] = Value::Cell(r);
                        r
                    }
                }
            }
        });
    }
    let r = vm.alloc_obj(Obj::Func(Closure { proto: fd.proto.clone(), upvals: ups.into(), env: fr.env }));
    Ok(Value::Func(r))
}

fn eval<H: Host>(h: &mut H, fr: &Frame, e: &Expr) -> R<Value> {
    Ok(match e {
        Expr::Nil => Value::Nil,
        Expr::True => Value::Bool(true),
        Expr::False => Value::Bool(false),
        Expr::Int(n) => Value::Int(*n),
        Expr::Str(s) => Value::Str(s.clone()),
        Expr::Vararg => fr.varargs.first().cloned().unwrap_or_default(),
        Expr::Local(s) => get_local(h.vm(), fr, *s)?,
        Expr::Upval(u) => h.vm().cell(fr.upvals[*u as usize])?,
        Expr::Global(i, _) => h.vm().envs[fr.env as usize][*i as usize].clone(),
        Expr::Index(b) => eval_index(h, fr, b)?,
        Expr::Call(c) => eval_call1(h, fr, c)?,
        Expr::Paren(inner) => eval(h, fr, inner)?,
        Expr::Func(fd) => make_closure(h.vm(), fr, fd)?,
        Expr::And(b) => {
            let a = eval(h, fr, &b.0)?;
            if !a.truthy() {
                a
            } else {
                eval(h, fr, &b.1)?
            }
        }
        Expr::Or(b) => {
            let a = eval(h, fr, &b.0)?;
            if a.truthy() {
                a
            } else {
                eval(h, fr, &b.1)?
            }
        }
        Expr::Not(x) => Value::Bool(!eval(h, fr, x)?.truthy()),
        Expr::Neg(x) => {
            let v = eval(h, fr, x)?;
            unary(h.vm(), fr, true, v, x)?
        }
        Expr::Len(x) => {
            let v = eval(h, fr, x)?;
            unary(h.vm(), fr, false, v, x)?
        }
        Expr::Bin(op, b) => {
            let x = eval(h, fr, &b.0)?;
            let y = eval(h, fr, &b.1)?;
            // Fast path: integers that do not overflow.
            if let (Value::Int(p), Value::Int(q)) = (&x, &y) {
                let (p, q) = (*p, *q);
                let fast = match op {
                    Bin::Add => p.checked_add(q).map(Value::Int),
                    Bin::Sub => p.checked_sub(q).map(Value::Int),
                    Bin::Mul => p.checked_mul(q).map(Value::Int),
                    Bin::Mod if q > 0 && p >= 0 => Some(Value::Int(p % q)),
                    Bin::IDiv if q > 0 && p >= 0 => Some(Value::Int(p / q)),
                    Bin::Eq => Some(Value::Bool(p == q)),
                    Bin::Ne => Some(Value::Bool(p != q)),
                    Bin::Lt => Some(Value::Bool(p < q)),
                    Bin::Le => Some(Value::Bool(p <= q)),
                    Bin::Gt => Some(Value::Bool(p > q)),
                    Bin::Ge => Some(Value::Bool(p >= q)),
                    _ => None,
                };
                if let Some(v) = fast {
                    return Ok(v);
                }
            }
            binary(h.vm(), fr, *op, x, y, b)?
        }
        Expr::Table(fields) => eval_table(h, fr, fields)?,
    })
}

#[inline(never)]
fn eval_index<H: Host>(h: &mut H, fr: &Frame, b: &(Expr, Expr)) -> R<Value> {
    let o = eval(h, fr, &b.0)?;
    let k = eval(h, fr, &b.1)?;
    let vm = h.vm();
    match vm.index(&o, &k) {
        Err(e) if e.kind() == ErrorKind::Runtime => Err(vm.rt_err(format!("{}{}", e.message, describe(fr, &b.0)))),
        r => r,
    }
}

#[inline(never)]
fn eval_call1<H: Host>(h: &mut H, fr: &Frame, c: &Call) -> R<Value> {
    let start = h.vm().stack.len();
    let n = eval_call(h, fr, c)?;
    let vm = h.vm();
    let v = if n > 0 { std::mem::take(&mut vm.stack[start]) } else { Value::Nil };
    vm.stack.truncate(start);
    Ok(v)
}

#[inline(never)]
fn unary<H>(vm: &mut Vm<H>, fr: &Frame, neg: bool, v: Value, x: &Expr) -> R<Value> {
    Ok(match (neg, v) {
        (true, Value::Int(n)) => match n.checked_neg() {
            Some(v) => Value::Int(v),
            None => return Err(vm.rt_err("integer overflow in unary '-'".into())),
        },
        (false, Value::Str(s)) => Value::from(s.len()),
        (false, Value::Table(r)) => Value::Int(vm.table(r)?.border()),
        (true, v) => {
            return Err(vm.rt_err(format!("attempt to perform arithmetic on a {} value{}", v.type_name(), describe(fr, x))))
        }
        (false, v) => return Err(vm.rt_err(format!("attempt to get length of a {} value{}", v.type_name(), describe(fr, x)))),
    })
}

#[inline(never)]
fn eval_table<H: Host>(h: &mut H, fr: &Frame, fields: &[Field]) -> R<Value> {
    let t = h.vm().new_table_charged()?;
    let mut pos = 1i64;
    for (i, f) in fields.iter().enumerate() {
        match f {
            Field::Pos(e) if i + 1 == fields.len() && matches!(e, Expr::Call(_) | Expr::Vararg) => {
                let start = h.vm().stack.len();
                eval_list(h, fr, std::slice::from_ref(e), None)?;
                let vm = h.vm();
                let vals: Vec<Value> = vm.stack.drain(start..).collect();
                for v in vals {
                    vm.set_index(&t, Value::Int(pos), v, "")?;
                    pos += 1;
                }
            }
            Field::Pos(e) => {
                let v = eval(h, fr, e)?;
                h.vm().set_index(&t, Value::Int(pos), v, "")?;
                pos += 1;
            }
            Field::Key(k, v) => {
                let k = eval(h, fr, k)?;
                let v = eval(h, fr, v)?;
                h.vm().set_index(&t, k, v, "")?;
            }
        }
    }
    Ok(t)
}

#[inline(never)]
fn binary<H>(vm: &mut Vm<H>, fr: &Frame, op: Bin, x: Value, y: Value, b: &(Expr, Expr)) -> R<Value> {
    use Value::Int;
    Ok(match (op, &x, &y) {
        (Bin::Eq, ..) => Value::Bool(x == y),
        (Bin::Ne, ..) => Value::Bool(x != y),
        (Bin::Add, Int(a), Int(c)) => Int(a.checked_add(*c).ok_or_else(|| overflow(vm, op))?),
        (Bin::Sub, Int(a), Int(c)) => Int(a.checked_sub(*c).ok_or_else(|| overflow(vm, op))?),
        (Bin::Mul, Int(a), Int(c)) => Int(a.checked_mul(*c).ok_or_else(|| overflow(vm, op))?),
        (Bin::IDiv, Int(a), Int(c)) => {
            if *c == 0 {
                return Err(vm.rt_err("attempt to perform 'n//0'".into()));
            }
            let q = a.checked_div(*c).ok_or_else(|| overflow(vm, op))?;
            Int(if a % c != 0 && ((*a < 0) != (*c < 0)) { q - 1 } else { q })
        }
        (Bin::Mod, Int(a), Int(c)) => {
            if *c == 0 {
                return Err(vm.rt_err("attempt to perform 'n%%0'".into()));
            }
            let r = a.checked_rem(*c).unwrap_or(0);
            Int(if r != 0 && ((r < 0) != (*c < 0)) { r + c } else { r })
        }
        (Bin::Lt, Int(a), Int(c)) => Value::Bool(a < c),
        (Bin::Le, Int(a), Int(c)) => Value::Bool(a <= c),
        (Bin::Gt, Int(a), Int(c)) => Value::Bool(a > c),
        (Bin::Ge, Int(a), Int(c)) => Value::Bool(a >= c),
        (Bin::Lt, Value::Str(a), Value::Str(c)) => Value::Bool(a < c),
        (Bin::Le, Value::Str(a), Value::Str(c)) => Value::Bool(a <= c),
        (Bin::Gt, Value::Str(a), Value::Str(c)) => Value::Bool(a > c),
        (Bin::Ge, Value::Str(a), Value::Str(c)) => Value::Bool(a >= c),
        (Bin::Concat, Int(_) | Value::Str(_), Int(_) | Value::Str(_)) => {
            let (p, q) = (concat_part(&x), concat_part(&y));
            vm.check_len(p.len() + q.len())?;
            let mut s = Vec::with_capacity(p.len() + q.len());
            s.extend_from_slice(&p);
            s.extend_from_slice(&q);
            vm.new_str(s)?
        }
        (Bin::Lt | Bin::Le | Bin::Gt | Bin::Ge, ..) => {
            let (a, c) = (x.type_name(), y.type_name());
            return Err(vm.rt_err(if a == c { format!("attempt to compare two {a} values") } else { format!("attempt to compare {a} with {c}") }));
        }
        (Bin::Concat, ..) => {
            let (bad, e) = if matches!(x, Int(_) | Value::Str(_)) { (&y, &b.1) } else { (&x, &b.0) };
            return Err(vm.rt_err(format!("attempt to concatenate a {} value{}", bad.type_name(), describe(fr, e))));
        }
        _ => {
            let (bad, e) = if matches!(x, Int(_)) { (&y, &b.1) } else { (&x, &b.0) };
            return Err(vm.rt_err(format!("attempt to perform arithmetic on a {} value{}", bad.type_name(), describe(fr, e))));
        }
    })
}

fn concat_part(v: &Value) -> std::borrow::Cow<'_, [u8]> {
    match v {
        Value::Str(s) => std::borrow::Cow::Borrowed(s),
        Value::Int(i) => std::borrow::Cow::Owned(i.to_string().into_bytes()),
        _ => std::borrow::Cow::Borrowed(&[]),
    }
}

fn overflow<H>(vm: &Vm<H>, op: Bin) -> Error {
    vm.rt_err(format!("integer overflow in '{}'", op.sym()))
}
