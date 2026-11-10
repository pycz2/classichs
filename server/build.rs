//! The server's version is the game's release version (project.godot `config/version`, as
//! .github/workflows/release.yml names the binaries); CLASSICHS_VERSION at build time wins.
fn main() {
    println!("cargo:rerun-if-changed=../project.godot");
    println!("cargo:rerun-if-env-changed=CLASSICHS_VERSION");
    let v = std::env::var("CLASSICHS_VERSION").ok().filter(|v| !v.is_empty()).or_else(|| {
        let p = std::fs::read_to_string("../project.godot").ok()?;
        p.lines().find_map(|l| Some(l.strip_prefix("config/version=\"")?.strip_suffix('"')?.to_string()))
    });
    println!("cargo:rustc-env=CLASSICHS_VERSION={}", v.unwrap_or_else(|| std::env::var("CARGO_PKG_VERSION").unwrap()));
}
