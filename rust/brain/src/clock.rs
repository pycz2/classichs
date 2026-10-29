//! A monotonic clock that also works in the browser's WASM (no std::time there): there the host gives
//! `env.chs_now_ms` (performance.now(), web/rules.js).

use std::time::Duration;

#[cfg(not(target_arch = "wasm32"))]
pub fn now() -> Duration {
    static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    START.get_or_init(std::time::Instant::now).elapsed()
}

#[cfg(target_arch = "wasm32")]
pub fn now() -> Duration {
    #[link(wasm_import_module = "env")]
    extern "C" {
        fn chs_now_ms() -> f64;
    }
    Duration::from_secs_f64(unsafe { chs_now_ms() }.max(0.0) / 1000.0)
}
