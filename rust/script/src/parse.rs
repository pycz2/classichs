//! Parser and resolver: tokens to a tree with resolved variables.
//!
//! Every `local` declaration in a function gets its own frame slot (slots are
//! never reused), so the executor needs no scopes. A slot captured by an inner
//! function is marked in `Proto::captured`; the executor keeps such a local in
//! a heap cell shared with the closures. Names that are neither locals nor
//! upvalues are globals: read-only, resolved when the chunk is loaded.

use crate::lex::{tokenize, Tok};
use crate::Str;
use std::sync::Arc;

/// Deepest syntactic nesting (blocks, operators, suffixes) inside one chunk.
pub const MAX_NEST: u32 = 200;
const MAX_SLOTS: usize = 60_000;

#[derive(Debug)]
pub struct Proto {
    pub name: String,
    pub file: Arc<str>,
    pub line: u32,
    pub nparams: usize,
    pub vararg: bool,
    pub nslots: usize,
    pub captured: Vec<bool>,
    pub slot_names: Vec<String>,
    pub upval_names: Vec<String>,
    pub body: Block,
    /// Deepest nesting inside the body (bounds the executor's native stack use).
    pub nest: u32,
}

pub type Block = Vec<Stmt>;

#[derive(Debug)]
pub struct Stmt {
    pub line: u32,
    pub kind: S,
}

#[derive(Debug)]
pub enum S {
    Local(Vec<u16>, Vec<Expr>),
    LocalFunc(u16, Box<FuncDef>),
    Assign(Vec<Target>, Vec<Expr>),
    Call(Box<Call>),
    Do(Block),
    While(Expr, Block),
    Repeat(Block, Expr),
    If(Vec<(Expr, Block)>, Option<Block>),
    NumFor(u16, Box<[Expr; 3]>, Block),
    GenFor(Vec<u16>, Vec<Expr>, Block),
    Return(Vec<Expr>),
    Break,
}

#[derive(Debug)]
pub enum Target {
    Local(u16),
    Upval(u16),
    Index(Expr, Expr),
}

#[derive(Debug)]
pub enum Expr {
    Nil,
    True,
    False,
    Int(i64),
    Str(Str),
    Vararg,
    Local(u16),
    Upval(u16),
    Global(u16, Arc<str>),
    Index(Box<(Expr, Expr)>),
    Call(Box<Call>),
    Func(Box<FuncDef>),
    Bin(Bin, Box<(Expr, Expr)>),
    And(Box<(Expr, Expr)>),
    Or(Box<(Expr, Expr)>),
    Not(Box<Expr>),
    Neg(Box<Expr>),
    Len(Box<Expr>),
    Table(Vec<Field>),
    /// `(f())` / `(...)`: one value only.
    Paren(Box<Expr>),
}

#[derive(Debug)]
pub enum Field {
    Pos(Expr),
    Key(Expr, Expr),
}

#[derive(Debug)]
pub struct Call {
    pub f: Expr,
    pub method: Option<Str>,
    pub args: Vec<Expr>,
    pub line: u32,
}

#[derive(Debug)]
pub struct FuncDef {
    pub proto: Arc<Proto>,
    pub caps: Vec<Cap>,
}

#[derive(Clone, Copy, Debug)]
pub enum Cap {
    Local(u16),
    Upval(u16),
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Bin {
    Add,
    Sub,
    Mul,
    IDiv,
    Mod,
    Concat,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
}

impl Bin {
    pub fn sym(self) -> &'static str {
        match self {
            Bin::Add => "+",
            Bin::Sub => "-",
            Bin::Mul => "*",
            Bin::IDiv => "//",
            Bin::Mod => "%",
            Bin::Concat => "..",
            Bin::Eq => "==",
            Bin::Ne => "~=",
            Bin::Lt => "<",
            Bin::Le => "<=",
            Bin::Gt => ">",
            Bin::Ge => ">=",
        }
    }
}

/// A parsed chunk: the main function plus the globals it reads (name, first line).
#[derive(Debug)]
pub struct Parsed {
    pub main: Arc<Proto>,
    pub globals: Vec<(Arc<str>, u32)>,
}

pub fn parse(file: &str, src: &[u8]) -> Result<Parsed, (u32, String)> {
    let toks = tokenize(src)?;
    let mut p = P { toks, pos: 0, file: file.into(), funcs: Vec::new(), globals: Vec::new(), depth: 0, fn_name: None };
    p.open_func(true);
    let body = p.block()?;
    if p.peek() != &Tok::Eof {
        return p.err("'<eof>' expected");
    }
    let main = p.close_func(body, "main chunk".into(), 0, 0);
    Ok(Parsed { main, globals: p.globals })
}

struct FS {
    scopes: Vec<Vec<(String, u16)>>,
    captured: Vec<bool>,
    slot_names: Vec<String>,
    upvals: Vec<(String, Cap)>,
    vararg: bool,
    loops: u32,
    depth0: u32,
    nest: u32,
}

struct P {
    toks: Vec<(Tok, u32)>,
    pos: usize,
    file: Arc<str>,
    funcs: Vec<FS>,
    globals: Vec<(Arc<str>, u32)>,
    depth: u32,
    /// The name for the next function literal (`local f = function`, `t.f = function`).
    fn_name: Option<String>,
}

type R<T> = Result<T, (u32, String)>;

fn tok_text(t: &Tok) -> String {
    match t {
        Tok::Name(n) => n.clone(),
        Tok::Str(s) => String::from_utf8_lossy(s).into_owned(),
        Tok::Int(i) => i.to_string(),
        Tok::Sym(s) => s.to_string(),
        Tok::Eof => "<eof>".into(),
    }
}

/// (left, right) priorities, Lua's table.
fn binop(t: &Tok) -> Option<(Bin, u8, u8)> {
    let Tok::Sym(s) = t else { return None };
    Some(match *s {
        "or" | "and" => return None,
        "==" => (Bin::Eq, 3, 3),
        "~=" => (Bin::Ne, 3, 3),
        "<" => (Bin::Lt, 3, 3),
        "<=" => (Bin::Le, 3, 3),
        ">" => (Bin::Gt, 3, 3),
        ">=" => (Bin::Ge, 3, 3),
        ".." => (Bin::Concat, 9, 8),
        "+" => (Bin::Add, 10, 10),
        "-" => (Bin::Sub, 10, 10),
        "*" => (Bin::Mul, 11, 11),
        "//" => (Bin::IDiv, 11, 11),
        "%" => (Bin::Mod, 11, 11),
        _ => return None,
    })
}

const UNARY_PRIO: u8 = 12;

fn block_end(t: &Tok) -> bool {
    matches!(t, Tok::Eof | Tok::Sym("end" | "else" | "elseif" | "until"))
}

impl P {
    fn peek(&self) -> &Tok {
        &self.toks[self.pos].0
    }
    fn peek2(&self) -> &Tok {
        &self.toks[(self.pos + 1).min(self.toks.len() - 1)].0
    }
    fn line(&self) -> u32 {
        self.toks[self.pos].1
    }
    fn next(&mut self) -> Tok {
        let t = self.toks[self.pos].0.clone();
        if self.pos + 1 < self.toks.len() {
            self.pos += 1;
        }
        t
    }
    fn err<T>(&self, msg: impl Into<String>) -> R<T> {
        Err((self.line(), format!("{} near '{}'", msg.into(), tok_text(self.peek()))))
    }
    fn check(&mut self, s: &str) -> bool {
        if matches!(self.peek(), Tok::Sym(x) if *x == s) {
            self.next();
            true
        } else {
            false
        }
    }
    fn expect(&mut self, s: &str) -> R<()> {
        if self.check(s) {
            Ok(())
        } else {
            self.err(format!("'{s}' expected"))
        }
    }
    /// `what` opened at `line` must be closed by `s`.
    fn close(&mut self, s: &str, what: &str, line: u32) -> R<()> {
        if self.check(s) {
            Ok(())
        } else if line == self.line() {
            self.err(format!("'{s}' expected"))
        } else {
            self.err(format!("'{s}' expected (to close '{what}' at line {line})"))
        }
    }
    fn name(&mut self) -> R<String> {
        match self.peek().clone() {
            Tok::Name(n) => {
                if n == "_ENV" || n == "_G" {
                    return self.err(format!("'{n}' is not available (scripts cannot access the global environment)"));
                }
                self.next();
                Ok(n)
            }
            _ => self.err("<name> expected"),
        }
    }

    fn enter(&mut self) -> R<()> {
        self.depth += 1;
        if self.depth > MAX_NEST {
            return self.err("chunk has too many syntax levels");
        }
        let f = self.funcs.last_mut().expect("function state");
        f.nest = f.nest.max(self.depth - f.depth0);
        Ok(())
    }

    fn fs(&mut self) -> &mut FS {
        self.funcs.last_mut().expect("function state")
    }

    fn open_func(&mut self, vararg: bool) {
        self.funcs.push(FS {
            scopes: vec![Vec::new()],
            captured: Vec::new(),
            slot_names: Vec::new(),
            upvals: Vec::new(),
            vararg,
            loops: 0,
            depth0: self.depth,
            nest: 0,
        });
    }

    fn close_func(&mut self, body: Block, name: String, line: u32, nparams: usize) -> Arc<Proto> {
        let f = self.funcs.pop().expect("function state");
        Arc::new(Proto {
            name,
            file: self.file.clone(),
            line,
            nparams,
            vararg: f.vararg,
            nslots: f.captured.len(),
            captured: f.captured,
            slot_names: f.slot_names,
            upval_names: f.upvals.into_iter().map(|u| u.0).collect(),
            body,
            nest: f.nest + 1,
        })
    }

    /// A new slot; not visible until `activate`.
    fn new_slot(&mut self, name: &str) -> R<u16> {
        let f = self.fs();
        if f.captured.len() >= MAX_SLOTS {
            return self.err("too many local variables in one function");
        }
        let f = self.fs();
        f.captured.push(false);
        f.slot_names.push(name.to_string());
        Ok((f.captured.len() - 1) as u16)
    }

    fn activate(&mut self, name: String, slot: u16) {
        self.fs().scopes.last_mut().expect("scope").push((name, slot));
    }

    fn find_local(&self, fi: usize, name: &str) -> Option<u16> {
        self.funcs[fi].scopes.iter().rev().flat_map(|s| s.iter().rev()).find(|(n, _)| n == name).map(|(_, s)| *s)
    }

    fn find_upval(&mut self, fi: usize, name: &str) -> Option<u16> {
        if fi == 0 {
            return None;
        }
        if let Some(i) = self.funcs[fi].upvals.iter().position(|(n, _)| n == name) {
            return Some(i as u16);
        }
        let cap = if let Some(s) = self.find_local(fi - 1, name) {
            self.funcs[fi - 1].captured[s as usize] = true;
            Cap::Local(s)
        } else {
            Cap::Upval(self.find_upval(fi - 1, name)?)
        };
        self.funcs[fi].upvals.push((name.to_string(), cap));
        Some((self.funcs[fi].upvals.len() - 1) as u16)
    }

    fn resolve(&mut self, name: &str, line: u32) -> Expr {
        let fi = self.funcs.len() - 1;
        if let Some(s) = self.find_local(fi, name) {
            return Expr::Local(s);
        }
        if let Some(u) = self.find_upval(fi, name) {
            return Expr::Upval(u);
        }
        let i = match self.globals.iter().position(|(n, _)| &**n == name) {
            Some(i) => i,
            None => {
                self.globals.push((name.into(), line));
                self.globals.len() - 1
            }
        };
        Expr::Global(i as u16, self.globals[i].0.clone())
    }

    fn block(&mut self) -> R<Block> {
        self.enter()?;
        self.fs().scopes.push(Vec::new());
        let b = self.block_body();
        self.fs().scopes.pop();
        self.depth -= 1;
        b
    }

    /// Statements up to the block end, in the current scope.
    fn block_body(&mut self) -> R<Block> {
        let mut out = Vec::new();
        loop {
            if block_end(self.peek()) {
                return Ok(out);
            }
            let line = self.line();
            if self.check("return") {
                let exprs = if block_end(self.peek()) || matches!(self.peek(), Tok::Sym(";")) {
                    Vec::new()
                } else {
                    self.exprlist()?
                };
                self.check(";");
                if !block_end(self.peek()) {
                    return self.err("'end' expected (nothing may follow 'return')");
                }
                out.push(Stmt { line, kind: S::Return(exprs) });
                return Ok(out);
            }
            if let Some(kind) = self.statement()? {
                out.push(Stmt { line, kind });
            }
        }
    }

    fn statement(&mut self) -> R<Option<S>> {
        let line = self.line();
        let t = self.peek().clone();
        let s = match t {
            Tok::Sym(";") => {
                self.next();
                return Ok(None);
            }
            Tok::Sym("if") => {
                self.next();
                let mut arms = Vec::new();
                let c = self.expr()?;
                self.expect("then")?;
                arms.push((c, self.block()?));
                let mut other = None;
                loop {
                    if self.check("elseif") {
                        let c = self.expr()?;
                        self.expect("then")?;
                        arms.push((c, self.block()?));
                    } else if self.check("else") {
                        other = Some(self.block()?);
                        self.close("end", "if", line)?;
                        break;
                    } else {
                        self.close("end", "if", line)?;
                        break;
                    }
                }
                S::If(arms, other)
            }
            Tok::Sym("while") => {
                self.next();
                let c = self.expr()?;
                self.expect("do")?;
                let b = self.loop_block()?;
                self.close("end", "while", line)?;
                S::While(c, b)
            }
            Tok::Sym("do") => {
                self.next();
                let b = self.block()?;
                self.close("end", "do", line)?;
                S::Do(b)
            }
            Tok::Sym("for") => {
                self.next();
                self.for_stmt(line)?
            }
            Tok::Sym("repeat") => {
                self.next();
                self.enter()?;
                self.fs().scopes.push(Vec::new());
                self.fs().loops += 1;
                let b = self.block_body();
                self.fs().loops -= 1;
                let r = b.and_then(|b| {
                    self.close("until", "repeat", line)?;
                    Ok(S::Repeat(b, self.expr()?))
                });
                self.fs().scopes.pop();
                self.depth -= 1;
                r?
            }
            Tok::Sym("function") => {
                self.next();
                let n = self.name()?;
                let mut full = n.clone();
                let mut target = self.resolve(&n, line);
                let mut method = false;
                loop {
                    let dot = self.check(".");
                    if !dot && !self.check(":") {
                        break;
                    }
                    let k = self.name()?;
                    full.push(if dot { '.' } else { ':' });
                    full.push_str(&k);
                    target = Expr::Index(Box::new((target, Expr::Str(k.as_bytes().into()))));
                    if !dot {
                        method = true;
                        break;
                    }
                }
                let f = self.body(method, full, line)?;
                let t = self.target(target)?;
                S::Assign(vec![t], vec![f])
            }
            Tok::Sym("local") => {
                self.next();
                if self.check("function") {
                    let n = self.name()?;
                    let slot = self.new_slot(&n)?;
                    self.activate(n.clone(), slot);
                    let Expr::Func(f) = self.body(false, n, line)? else { unreachable!() };
                    S::LocalFunc(slot, f)
                } else {
                    let mut names = vec![self.name()?];
                    if matches!(self.peek(), Tok::Sym("<")) {
                        return self.err("variable attributes (<const>, <close>) are not supported");
                    }
                    while self.check(",") {
                        names.push(self.name()?);
                    }
                    let exprs = if self.check("=") {
                        if names.len() == 1 {
                            self.fn_name = Some(names[0].clone());
                        }
                        self.named_exprlist()?
                    } else {
                        Vec::new()
                    };
                    let mut slots = Vec::new();
                    for n in &names {
                        slots.push(self.new_slot(n)?);
                    }
                    for (n, s) in names.into_iter().zip(&slots) {
                        self.activate(n, *s);
                    }
                    S::Local(slots, exprs)
                }
            }
            Tok::Sym("break") => {
                self.next();
                if self.fs().loops == 0 {
                    return Err((line, "'break' outside a loop".into()));
                }
                S::Break
            }
            Tok::Sym("goto") => return self.err("'goto' is not supported"),
            Tok::Sym("::") => return self.err("labels are not supported"),
            _ => {
                let e = self.suffixed()?;
                if matches!(self.peek(), Tok::Sym("=" | ",")) {
                    let mut targets = vec![self.target(e)?];
                    while self.check(",") {
                        let e = self.suffixed()?;
                        targets.push(self.target(e)?);
                    }
                    self.expect("=")?;
                    if let [t] = &targets[..] {
                        self.fn_name = self.target_name(t);
                    }
                    S::Assign(targets, self.named_exprlist()?)
                } else if let Expr::Call(c) = e {
                    S::Call(c)
                } else {
                    return self.err("syntax error (a statement must be an assignment or a call)");
                }
            }
        };
        Ok(Some(s))
    }

    fn loop_block(&mut self) -> R<Block> {
        self.fs().loops += 1;
        let b = self.block();
        self.fs().loops -= 1;
        b
    }

    fn target(&self, e: Expr) -> R<Target> {
        match e {
            Expr::Local(s) => Ok(Target::Local(s)),
            Expr::Upval(u) => Ok(Target::Upval(u)),
            Expr::Index(b) => Ok(Target::Index(b.0, b.1)),
            Expr::Global(_, n) => {
                Err((self.line(), format!("assignment to undeclared global '{n}' (declare it with 'local')")))
            }
            _ => self.err("syntax error (cannot assign to this expression)"),
        }
    }

    fn for_stmt(&mut self, line: u32) -> R<S> {
        let n1 = self.name()?;
        if self.check("=") {
            let a = self.expr()?;
            self.expect(",")?;
            let b = self.expr()?;
            let c = if self.check(",") { self.expr()? } else { Expr::Int(1) };
            self.expect("do")?;
            self.fs().scopes.push(Vec::new());
            let slot = self.new_slot(&n1)?;
            self.activate(n1, slot);
            let body = self.loop_block();
            self.fs().scopes.pop();
            let body = body?;
            self.close("end", "for", line)?;
            return Ok(S::NumFor(slot, Box::new([a, b, c]), body));
        }
        let mut names = vec![n1];
        while self.check(",") {
            names.push(self.name()?);
        }
        self.expect("in")?;
        let exprs = self.exprlist()?;
        self.expect("do")?;
        self.fs().scopes.push(Vec::new());
        let mut slots = Vec::new();
        for n in names {
            let s = self.new_slot(&n)?;
            self.activate(n, s);
            slots.push(s);
        }
        let body = self.loop_block();
        self.fs().scopes.pop();
        let body = body?;
        self.close("end", "for", line)?;
        Ok(S::GenFor(slots, exprs, body))
    }

    /// `(params) block end` → a function expression.
    fn body(&mut self, method: bool, name: String, line: u32) -> R<Expr> {
        self.open_func(false);
        let r = self.body_inner(method);
        let (body, nparams) = match r {
            Ok(x) => x,
            Err(e) => {
                self.funcs.pop();
                return Err(e);
            }
        };
        if let Err(e) = self.close("end", "function", line) {
            self.funcs.pop();
            return Err(e);
        }
        let caps = self.fs().upvals.iter().map(|u| u.1).collect();
        let proto = self.close_func(body, name, line, nparams);
        Ok(Expr::Func(Box::new(FuncDef { proto, caps })))
    }

    fn body_inner(&mut self, method: bool) -> R<(Block, usize)> {
        let mut n = 0;
        if method {
            let s = self.new_slot("self")?;
            self.activate("self".into(), s);
            n += 1;
        }
        self.expect("(")?;
        if !self.check(")") {
            loop {
                if self.check("...") {
                    self.fs().vararg = true;
                    self.expect(")")?;
                    break;
                }
                let p = self.name()?;
                let s = self.new_slot(&p)?;
                self.activate(p, s);
                n += 1;
                if !self.check(",") {
                    self.expect(")")?;
                    break;
                }
            }
        }
        // The function's own loops are separate from the enclosing ones.
        let b = self.block()?;
        Ok((b, n))
    }

    /// An expression list whose first item, if a function literal, takes `self.fn_name`.
    fn named_exprlist(&mut self) -> R<Vec<Expr>> {
        if !matches!(self.peek(), Tok::Sym("function")) {
            self.fn_name = None;
        }
        let r = self.exprlist();
        self.fn_name = None;
        r
    }

    /// "a.b.c" for a target made of names and constant fields (for tracebacks).
    fn target_name(&self, t: &Target) -> Option<String> {
        fn expr_name(p: &P, e: &Expr) -> Option<String> {
            let f = p.funcs.last()?;
            match e {
                Expr::Local(s) => f.slot_names.get(*s as usize).cloned(),
                Expr::Upval(u) => f.upvals.get(*u as usize).map(|u| u.0.clone()),
                Expr::Global(_, n) => Some(n.to_string()),
                Expr::Index(b) => match &b.1 {
                    Expr::Str(k) => Some(format!("{}.{}", expr_name(p, &b.0)?, String::from_utf8_lossy(k))),
                    _ => None,
                },
                _ => None,
            }
        }
        match t {
            Target::Index(o, Expr::Str(k)) => Some(format!("{}.{}", expr_name(self, o)?, String::from_utf8_lossy(k))),
            Target::Local(s) => self.funcs.last()?.slot_names.get(*s as usize).cloned(),
            Target::Upval(u) => self.funcs.last()?.upvals.get(*u as usize).map(|u| u.0.clone()),
            _ => None,
        }
    }

    fn exprlist(&mut self) -> R<Vec<Expr>> {
        let mut v = vec![self.expr()?];
        while self.check(",") {
            v.push(self.expr()?);
        }
        Ok(v)
    }

    fn expr(&mut self) -> R<Expr> {
        self.subexpr(0)
    }

    fn subexpr(&mut self, limit: u8) -> R<Expr> {
        let d0 = self.depth;
        let r = self.subexpr_inner(limit);
        self.depth = d0;
        r
    }

    fn subexpr_inner(&mut self, limit: u8) -> R<Expr> {
        self.enter()?;
        let mut e = match self.peek() {
            Tok::Sym("not") => {
                self.next();
                Expr::Not(Box::new(self.subexpr(UNARY_PRIO)?))
            }
            Tok::Sym("-") => {
                self.next();
                match self.subexpr(UNARY_PRIO)? {
                    Expr::Int(n) if n != i64::MIN => Expr::Int(-n),
                    x => Expr::Neg(Box::new(x)),
                }
            }
            Tok::Sym("#") => {
                self.next();
                Expr::Len(Box::new(self.subexpr(UNARY_PRIO)?))
            }
            Tok::Sym("~") => return self.err("bitwise operators are not supported"),
            _ => self.simple()?,
        };
        loop {
            match self.peek() {
                Tok::Sym("/") => return self.err("'/' is not supported (no floats); use '//' for integer division"),
                Tok::Sym("^") => return self.err("'^' is not supported (no floats)"),
                Tok::Sym("&" | "|" | "~" | "<<" | ">>") => return self.err("bitwise operators are not supported"),
                _ => {}
            }
            let (kind, l, r) = match self.peek() {
                Tok::Sym("or") => (None, 1, 1),
                Tok::Sym("and") => (Some(None), 2, 2),
                t => match binop(t) {
                    Some((b, l, r)) => (Some(Some(b)), l, r),
                    None => break,
                },
            };
            if l <= limit {
                break;
            }
            self.next();
            self.enter()?;
            let rhs = self.subexpr(r)?;
            let pair = Box::new((e, rhs));
            e = match kind {
                None => Expr::Or(pair),
                Some(None) => Expr::And(pair),
                Some(Some(b)) => Expr::Bin(b, pair),
            };
        }
        Ok(e)
    }

    fn simple(&mut self) -> R<Expr> {
        let line = self.line();
        Ok(match self.peek().clone() {
            Tok::Int(n) => {
                self.next();
                Expr::Int(n)
            }
            Tok::Str(s) => {
                self.next();
                Expr::Str(s.into())
            }
            Tok::Sym("nil") => {
                self.next();
                Expr::Nil
            }
            Tok::Sym("true") => {
                self.next();
                Expr::True
            }
            Tok::Sym("false") => {
                self.next();
                Expr::False
            }
            Tok::Sym("...") => {
                if !self.fs().vararg {
                    return self.err("cannot use '...' outside a vararg function");
                }
                self.next();
                Expr::Vararg
            }
            Tok::Sym("{") => self.table()?,
            Tok::Sym("function") => {
                self.next();
                let name = self.fn_name.take().unwrap_or_else(|| format!("<anonymous:{line}>"));
                self.body(false, name, line)?
            }
            _ => self.suffixed()?,
        })
    }

    fn primary(&mut self) -> R<Expr> {
        let line = self.line();
        match self.peek() {
            Tok::Name(_) => {
                let n = self.name()?;
                Ok(self.resolve(&n, line))
            }
            Tok::Sym("(") => {
                self.next();
                let e = self.expr()?;
                self.close(")", "(", line)?;
                Ok(match e {
                    Expr::Call(_) | Expr::Vararg => Expr::Paren(Box::new(e)),
                    e => e,
                })
            }
            _ => self.err("unexpected symbol"),
        }
    }

    fn suffixed(&mut self) -> R<Expr> {
        let d0 = self.depth;
        let r = self.suffixed_inner();
        self.depth = d0;
        r
    }

    fn suffixed_inner(&mut self) -> R<Expr> {
        let mut e = self.primary()?;
        loop {
            let line = self.line();
            match self.peek() {
                Tok::Sym(".") => {
                    self.next();
                    let k = self.name()?;
                    e = Expr::Index(Box::new((e, Expr::Str(k.as_bytes().into()))));
                }
                Tok::Sym("[") => {
                    self.next();
                    let k = self.expr()?;
                    self.expect("]")?;
                    e = Expr::Index(Box::new((e, k)));
                }
                Tok::Sym(":") => {
                    self.next();
                    let m = self.name()?;
                    let args = self.args()?;
                    e = Expr::Call(Box::new(Call { f: e, method: Some(m.as_bytes().into()), args, line }));
                }
                Tok::Sym("(" | "{") | Tok::Str(_) => {
                    let args = self.args()?;
                    e = Expr::Call(Box::new(Call { f: e, method: None, args, line }));
                }
                _ => return Ok(e),
            }
            self.enter()?;
        }
    }

    fn args(&mut self) -> R<Vec<Expr>> {
        let line = self.line();
        match self.peek().clone() {
            Tok::Str(s) => {
                self.next();
                Ok(vec![Expr::Str(s.into())])
            }
            Tok::Sym("{") => Ok(vec![self.table()?]),
            Tok::Sym("(") => {
                self.next();
                if self.check(")") {
                    return Ok(Vec::new());
                }
                let v = self.exprlist()?;
                self.close(")", "(", line)?;
                Ok(v)
            }
            _ => self.err("function arguments expected"),
        }
    }

    fn table(&mut self) -> R<Expr> {
        let line = self.line();
        self.expect("{")?;
        self.enter()?;
        let mut fields = Vec::new();
        loop {
            if matches!(self.peek(), Tok::Sym("}")) {
                break;
            }
            match (self.peek().clone(), self.peek2()) {
                (Tok::Sym("["), _) => {
                    self.next();
                    let k = self.expr()?;
                    self.expect("]")?;
                    self.expect("=")?;
                    fields.push(Field::Key(k, self.expr()?));
                }
                (Tok::Name(n), Tok::Sym("=")) => {
                    let n = if n == "_ENV" || n == "_G" { self.name()? } else { n };
                    self.next();
                    self.next();
                    let v = match self.peek() {
                        Tok::Sym("function") => {
                            let l = self.line();
                            self.next();
                            self.body(false, n.clone(), l)?
                        }
                        _ => self.expr()?,
                    };
                    fields.push(Field::Key(Expr::Str(n.as_bytes().into()), v));
                }
                _ => fields.push(Field::Pos(self.expr()?)),
            }
            if !self.check(",") && !self.check(";") {
                break;
            }
        }
        self.close("}", "{", line)?;
        self.depth -= 1;
        Ok(Expr::Table(fields))
    }
}
