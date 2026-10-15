//! The rules engine for the browser (web/rules.js): the host writes a UTF-8 request
//! into memory from `alloc`, calls `call(ptr, len)`, frees it with `dealloc`, and
//! reads the reply at `out_ptr()` / `out_len()` (valid until the next call).
use classichs_engine::Engine;
use std::cell::RefCell;

thread_local! {
    static ENGINE: RefCell<Engine> = RefCell::new(Engine::new());
    static OUT: RefCell<String> = const { RefCell::new(String::new()) };
}

#[no_mangle]
pub extern "C" fn alloc(n: usize) -> *mut u8 {
    let mut v = Vec::<u8>::with_capacity(n);
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}

/// # Safety
/// `p` and `n` must come from one `alloc(n)`.
#[no_mangle]
pub unsafe extern "C" fn dealloc(p: *mut u8, n: usize) {
    drop(Vec::from_raw_parts(p, 0, n));
}

/// # Safety
/// `p` must point at `n` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn call(p: *const u8, n: usize) {
    let req = String::from_utf8_lossy(std::slice::from_raw_parts(p, n));
    let reply = ENGINE.with(|e| e.borrow_mut().call(&req));
    OUT.with(|o| *o.borrow_mut() = reply);
}

#[no_mangle]
pub extern "C" fn out_ptr() -> *const u8 {
    OUT.with(|o| o.borrow().as_ptr())
}

#[no_mangle]
pub extern "C" fn out_len() -> usize {
    OUT.with(|o| o.borrow().len())
}
