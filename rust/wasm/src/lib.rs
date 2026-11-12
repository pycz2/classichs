//! The rules engine for the browser (web/rules.js): the host writes a UTF-8 request
//! into memory from `alloc`, calls `call(ptr, len)`, frees it with `dealloc`, and
//! reads the reply at `out_ptr()` / `out_len()` (valid until the next call).
//! `think(ptr, len)` is the game's own bot (classichs_brain::think); web/rules.js runs it in a Web
//! Worker with its own instance, so the page does not stop while the bot thinks. The module
//! imports `env.chs_now_ms` (performance.now()).
use classichs_engine::Engine;
use std::cell::RefCell;

thread_local! {
    static ENGINE: RefCell<Engine> = RefCell::new(Engine::new());
    static OUT: RefCell<String> = const { RefCell::new(String::new()) };
    static PCM: RefCell<Vec<i16>> = const { RefCell::new(Vec::new()) };
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

/// # Safety
/// `p` must point at `n` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn think(p: *const u8, n: usize) {
    let req = String::from_utf8_lossy(std::slice::from_raw_parts(p, n));
    let reply = match serde_json::from_str(&req) {
        Ok(v) => classichs_brain::think(&v),
        Err(e) => serde_json::json!({"ok": false, "error": format!("bad json: {e}")}),
    };
    OUT.with(|o| *o.borrow_mut() = reply.to_string());
}

/// An Ogg Opus file (classichs_opus) to 16-bit PCM at 48 kHz: the channel count (1 or 2), its
/// samples (interleaved, little-endian) at `pcm_ptr()` / `pcm_len()` bytes; 0 on a bad file, the
/// reason at `out_ptr()` / `out_len()`. web/rules.js runs it in an instance of its own.
///
/// # Safety
/// `p` must point at `n` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn opus_decode(p: *const u8, n: usize) -> u32 {
    PCM.with(|b| *b.borrow_mut() = Vec::new()); // (the last file's memory first)
    let r = classichs_opus::decode(std::slice::from_raw_parts(p, n));
    match r {
        Ok(pcm) => {
            PCM.with(|b| *b.borrow_mut() = pcm.samples);
            pcm.channels as u32
        }
        Err(e) => {
            OUT.with(|o| *o.borrow_mut() = e);
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn pcm_ptr() -> *const u8 {
    PCM.with(|b| b.borrow().as_ptr() as *const u8)
}

#[no_mangle]
pub extern "C" fn pcm_len() -> usize {
    PCM.with(|b| b.borrow().len() * 2)
}
