//! A sandboxed, deterministic interpreter for a subset of Lua 5.4 (integers
//! only), for the card scripts of game packs. See `docs/packs/lua.md`.
//!
//! ```
//! use classichs_script::{compile, call_path, Host, Vm, Value};
//! struct Game { vm: Vm<Game> }
//! impl Host for Game { fn vm(&mut self) -> &mut Vm<Game> { &mut self.vm } }
//!
//! let chunk = compile("cards.lua", "return { X = { hp = function(n) return n * 2 end } }").unwrap();
//! let mut g = Game { vm: Vm::new() };
//! classichs_script::load(&mut g, "cards", &chunk).unwrap();
//! let r = call_path(&mut g, "cards", &["X", "hp"], &[Value::Int(21)]).unwrap();
//! assert_eq!(r, vec![Value::Int(42)]);
//! ```

#![forbid(unsafe_code)]

mod lex;
mod parse;
mod stdlib;
mod vm;

use std::fmt;
use std::sync::Arc;

pub use vm::{call, call_path, get_path, load, Vm};

/// A Lua string: bytes, shared.
pub type Str = Arc<[u8]>;

/// A reference to a heap object of a [`Vm`]. Checked on use: a reference to
/// an object the collector has freed gives an error, never another object.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Ref {
    pub(crate) idx: u32,
    pub(crate) gen: u32,
}

/// A Lua value. Tables and functions live in a [`Vm`]'s heap.
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash)]
pub enum Value {
    #[default]
    Nil,
    Bool(bool),
    Int(i64),
    Str(Str),
    Table(Ref),
    /// A Lua function (closure).
    Func(Ref),
    /// A host or library function (index into the VM's function list).
    Native(u32),
    /// Internal: a local captured by a closure. Never seen by scripts or hosts.
    #[doc(hidden)]
    Cell(Ref),
}

impl Value {
    pub fn is_nil(&self) -> bool {
        matches!(self, Value::Nil)
    }
    /// Lua truth: everything except nil and false.
    pub fn truthy(&self) -> bool {
        !matches!(self, Value::Nil | Value::Bool(false))
    }
    pub fn as_int(&self) -> Option<i64> {
        match self {
            Value::Int(i) => Some(*i),
            _ => None,
        }
    }
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }
    pub fn as_bytes(&self) -> Option<&[u8]> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }
    /// The string if it is valid UTF-8.
    pub fn as_str(&self) -> Option<&str> {
        self.as_bytes().and_then(|b| std::str::from_utf8(b).ok())
    }
    /// Lua's `type()`.
    pub fn type_name(&self) -> &'static str {
        match self {
            Value::Nil => "nil",
            Value::Bool(_) => "boolean",
            Value::Int(_) => "number",
            Value::Str(_) => "string",
            Value::Table(_) => "table",
            Value::Func(_) | Value::Native(_) => "function",
            Value::Cell(_) => "cell",
        }
    }
}

impl From<i64> for Value {
    fn from(v: i64) -> Self {
        Value::Int(v)
    }
}
impl From<i32> for Value {
    fn from(v: i32) -> Self {
        Value::Int(v.into())
    }
}
impl From<usize> for Value {
    fn from(v: usize) -> Self {
        Value::Int(i64::try_from(v).unwrap_or(i64::MAX))
    }
}
impl From<bool> for Value {
    fn from(v: bool) -> Self {
        Value::Bool(v)
    }
}
impl From<&str> for Value {
    fn from(v: &str) -> Self {
        Value::Str(v.as_bytes().into())
    }
}
impl From<String> for Value {
    fn from(v: String) -> Self {
        Value::Str(v.into_bytes().into())
    }
}
impl From<()> for Value {
    fn from(_: ()) -> Self {
        Value::Nil
    }
}
impl<T: Into<Value>> From<Option<T>> for Value {
    fn from(v: Option<T>) -> Self {
        v.map_or(Value::Nil, Into::into)
    }
}

/// Per-call limits (a "call" is one top-level [`call`] / [`load`] from Rust;
/// nested calls made by host functions share its budget).
#[derive(Clone, Copy, Debug)]
pub struct Limits {
    /// Steps: 1 per statement executed, per loop iteration and per function
    /// call; library functions charge 1 per element they touch.
    pub steps: u64,
    /// Nested function calls (Lua and library/host functions).
    pub depth: u32,
    /// Live entries in one table.
    pub table_size: usize,
    /// Bytes in one string.
    pub string_len: usize,
    /// Bytes allocated during the call (approximate accounting: a table 64,
    /// a new table key 32, a closure 32 + 8 per upvalue, a string its length + 16).
    pub alloc: u64,
}

impl Default for Limits {
    fn default() -> Self {
        Limits { steps: 200_000, depth: 200, table_size: 10_000, string_len: 64 * 1024, alloc: 16 << 20 }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ErrorKind {
    /// Syntax errors and load errors (undefined globals).
    Compile,
    /// A script error: `error()`, a type error, overflow, a bad argument.
    /// The only kind `pcall` catches.
    Runtime,
    /// A limit of [`Limits`] was exceeded (or the native stack guard).
    Limit,
    /// A host error scripts may not catch.
    Fatal,
}

/// An error with the script position ("file:line: message") and a traceback.
pub struct Error(Box<ErrorData>);

pub struct ErrorData {
    pub kind: ErrorKind,
    /// "file:line: message" (no position for errors raised with level 0).
    pub message: String,
    /// The Lua error value (`error(v)`; for other errors the message string).
    pub value: Value,
    /// Innermost first: "file:line: in function 'name'".
    pub traceback: Vec<String>,
    pub(crate) located: bool,
}

impl Error {
    pub(crate) fn new(kind: ErrorKind, message: String) -> Self {
        let value = Value::from(message.as_str());
        Error(Box::new(ErrorData { kind, message, value, traceback: Vec::new(), located: false }))
    }
    /// An error scripts can catch with `pcall`; the VM adds the position.
    pub fn runtime(message: impl Into<String>) -> Self {
        Error::new(ErrorKind::Runtime, message.into())
    }
    /// An error scripts cannot catch.
    pub fn fatal(message: impl Into<String>) -> Self {
        Error::new(ErrorKind::Fatal, message.into())
    }
    pub fn kind(&self) -> ErrorKind {
        self.0.kind
    }
}

impl std::ops::Deref for Error {
    type Target = ErrorData;
    fn deref(&self) -> &ErrorData {
        &self.0
    }
}

impl std::ops::DerefMut for Error {
    fn deref_mut(&mut self) -> &mut ErrorData {
        &mut self.0
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)?;
        if !self.traceback.is_empty() {
            write!(f, "\nstack traceback:")?;
            for t in &self.traceback {
                write!(f, "\n\t{t}")?;
            }
        }
        Ok(())
    }
}

impl fmt::Debug for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}: {self}", self.kind)
    }
}

impl std::error::Error for Error {}

/// The thing scripts run against: owns the [`Vm`] and whatever host functions
/// need (e.g. the game). Host functions get `&mut Self`, so they may call back
/// into scripts (re-entrantly) with [`call`].
pub trait Host: Sized + 'static {
    fn vm(&mut self) -> &mut Vm<Self>;
}

/// A host or library function.
pub type NativeFn<H> = fn(&mut H, Args) -> Result<Vec<Value>, Error>;

/// The arguments of a native call, with checked accessors that produce Lua's
/// "bad argument #n to 'name' (number expected, got nil)" errors.
pub struct Args {
    pub vals: Vec<Value>,
    pub name: &'static str,
}

impl Args {
    pub fn len(&self) -> usize {
        self.vals.len()
    }
    pub fn is_empty(&self) -> bool {
        self.vals.is_empty()
    }
    /// Argument `i` (0-based), nil when missing.
    pub fn get(&self, i: usize) -> Value {
        self.vals.get(i).cloned().unwrap_or_default()
    }
    pub fn bad(&self, i: usize, msg: &str) -> Error {
        Error::runtime(format!("bad argument #{} to '{}' ({msg})", i + 1, self.name))
    }
    fn expected(&self, i: usize, what: &str) -> Error {
        self.bad(i, &format!("{what} expected, got {}", self.get(i).type_name()))
    }
    pub fn int(&self, i: usize) -> Result<i64, Error> {
        self.get(i).as_int().ok_or_else(|| self.expected(i, "number"))
    }
    pub fn opt_int(&self, i: usize) -> Result<Option<i64>, Error> {
        match self.get(i) {
            Value::Nil => Ok(None),
            Value::Int(n) => Ok(Some(n)),
            _ => Err(self.expected(i, "number")),
        }
    }
    pub fn bytes(&self, i: usize) -> Result<Str, Error> {
        match self.get(i) {
            Value::Str(s) => Ok(s),
            _ => Err(self.expected(i, "string")),
        }
    }
    /// A string argument as Rust text (invalid UTF-8 replaced).
    pub fn string(&self, i: usize) -> Result<String, Error> {
        Ok(String::from_utf8_lossy(&self.bytes(i)?).into_owned())
    }
    pub fn table(&self, i: usize) -> Result<Value, Error> {
        match self.get(i) {
            v @ Value::Table(_) => Ok(v),
            _ => Err(self.expected(i, "table")),
        }
    }
    pub fn func(&self, i: usize) -> Result<Value, Error> {
        match self.get(i) {
            v @ (Value::Func(_) | Value::Native(_)) => Ok(v),
            _ => Err(self.expected(i, "function")),
        }
    }
}

/// A compiled chunk: parse once, load into any number of VMs (it is `Send + Sync`).
#[derive(Clone, Debug)]
pub struct Chunk(pub(crate) Arc<parse::Parsed>);

/// Compiles a chunk. `file` names it in error messages.
pub fn compile(file: &str, src: &str) -> Result<Chunk, Error> {
    compile_bytes(file, src.as_bytes())
}

pub fn compile_bytes(file: &str, src: &[u8]) -> Result<Chunk, Error> {
    parse::parse(file, src).map(|p| Chunk(Arc::new(p))).map_err(|(line, msg)| {
        let mut e = Error::new(ErrorKind::Compile, format!("{file}:{line}: {msg}"));
        e.located = true;
        e
    })
}
