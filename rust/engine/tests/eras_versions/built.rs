//! A pack source built by tools/pack.py once for every test binary and process: the build (packs/eras takes about
//! half a minute) is kept in target/tmp under a key of its inputs (every file of packs/ and tools/: its path, size
//! and time), made under a file lock by the first test that needs it and read by the others.

#![allow(dead_code)]

use classichs_engine::pack::{self, Files};
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn key(dir: &Path, h: &mut impl Hasher) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    let mut es: Vec<_> = rd.flatten().collect();
    es.sort_by_key(|e| e.file_name());
    for e in es {
        let Ok(m) = e.metadata() else { continue };
        e.file_name().hash(h);
        if m.is_dir() {
            key(&e.path(), h);
        } else {
            (m.len(), m.modified().ok()).hash(h);
        }
    }
}

/// `src` (a pack source such as "packs/eras") built by tools/pack.py, read as the engine reads it; None without python3.
pub fn built(src: &str) -> Option<Files> {
    let mut h = std::collections::hash_map::DefaultHasher::new();
    for d in ["packs", "tools"] {
        key(&repo().join(d), &mut h);
    }
    let name = src.replace('/', "_");
    let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR"));
    let out = dir.join(format!("{name}-{:016x}.cardpack", h.finish()));
    if !out.exists() {
        std::fs::create_dir_all(&dir).unwrap();
        let lock = std::fs::File::create(dir.join(format!("{name}.lock"))).unwrap();
        lock.lock().unwrap(); // released when the process ends, even when it fails
        if !out.exists() {
            let tmp = dir.join(format!("{name}-{}.tmp", std::process::id()));
            let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", src, "-o"]).arg(&tmp).output().ok()?;
            assert!(build.status.success(), "pack.py build {src}: {}", String::from_utf8_lossy(&build.stdout));
            // the builds of older inputs go
            for e in std::fs::read_dir(&dir).unwrap().flatten() {
                let f = e.file_name().to_string_lossy().into_owned();
                if f.starts_with(&format!("{name}-")) && f.ends_with(".cardpack") {
                    let _ = std::fs::remove_file(e.path());
                }
            }
            std::fs::rename(&tmp, &out).unwrap();
        }
    }
    Some(pack::read_zip(&std::fs::read(&out).unwrap()).unwrap())
}
