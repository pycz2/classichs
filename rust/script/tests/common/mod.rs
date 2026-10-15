#![allow(dead_code)]
pub use classichs_script::*;

pub struct T {
    pub vm: Vm<T>,
    pub log: Vec<String>,
}

impl Host for T {
    fn vm(&mut self) -> &mut Vm<T> {
        &mut self.vm
    }
}

pub fn host() -> T {
    T { vm: Vm::new(), log: Vec::new() }
}

/// Runs `src` as the body of a vararg function (same line numbers) and returns its results.
pub fn run_in(t: &mut T, src: &str) -> Result<Vec<Value>, Error> {
    let chunk = compile("test.lua", &format!("return function(...) {src}\nend"))?;
    let f = load(t, "test", &chunk)?;
    call(t, &f, &[])
}

pub fn run(src: &str) -> Result<Vec<Value>, Error> {
    run_in(&mut host(), src)
}

pub fn show(t: &T, v: &[Value]) -> String {
    v.iter().map(|x| t.vm.display(x)).collect::<Vec<_>>().join(", ")
}

/// The results, as "a, b, c".
#[track_caller]
pub fn ok(src: &str) -> String {
    let mut t = host();
    match run_in(&mut t, src) {
        Ok(v) => show(&t, &v),
        Err(e) => panic!("script failed: {e}\n--- source:\n{src}"),
    }
}

/// The error message.
#[track_caller]
pub fn err(src: &str) -> String {
    match run(src) {
        Ok(v) => panic!("expected an error, got {} values\n--- source:\n{src}", v.len()),
        Err(e) => e.message.clone(),
    }
}

#[track_caller]
pub fn err_kind(src: &str) -> (ErrorKind, String) {
    match run(src) {
        Ok(_) => panic!("expected an error\n--- source:\n{src}"),
        Err(e) => (e.kind(), e.message.clone()),
    }
}
