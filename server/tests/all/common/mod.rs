//! Test packs: the built-in Classic rules files (rules, cards, missions, scripts) with another
//! manifest id, some rules.json values changed and extra files: valid packs with their own
//! rules_hash (the manifest's is filled in).

use classichs_engine::ruleset;
use serde_json::{json, Value};
use std::io::{Cursor, Write};

/// `patch`: JSON pointers into rules.json and their new values; `extra`: more files.
pub fn pack_bytes(id: &str, version: &str, patch: &[(&str, Value)], extra: &[(&str, &[u8])]) -> Vec<u8> {
    let mut files = ruleset::classic_files();
    let mut rules: Value = serde_json::from_slice(&files["rules.json"]).unwrap();
    for (p, v) in patch {
        *rules.pointer_mut(p).unwrap_or_else(|| panic!("rules.json has no {p}")) = v.clone();
    }
    files.insert("rules.json".into(), serde_json::to_vec(&rules).unwrap());
    for (p, b) in extra {
        files.insert(p.to_string(), b.to_vec());
    }
    let mut m: Value = serde_json::from_slice(&files["manifest.json"]).unwrap();
    m["id"] = json!(id);
    m["version"] = json!(version);
    m["name"] = json!({"en": "Test pack", "ru": "Тестовый"});
    m["rules_hash"] = json!(classichs_engine::pack::rules_hash(&files).unwrap());
    files.insert("manifest.json".into(), serde_json::to_vec(&m).unwrap());
    let mut w = zip::ZipWriter::new(Cursor::new(vec![]));
    for (name, body) in &files {
        w.start_file(name.as_str(), zip::write::SimpleFileOptions::default()).unwrap();
        w.write_all(body).unwrap();
    }
    w.finish().unwrap().into_inner()
}

/// The rules_hash of a test pack.
#[allow(dead_code)]
pub fn rules_hash(zip: &[u8]) -> String {
    classichs_server::packs::inspect(zip).unwrap().info.rules_hash
}
