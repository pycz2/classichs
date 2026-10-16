//! Embeds the built-in Classic ruleset: the rules part of the pack source
//! (packs/classic: manifest, rules, missions, scripts) and its cards.json, made
//! here from data/cards.json + cards.patch.json as `tools/pack.py` makes it
//! (recipe step `hsjson`; names and texts are left out: the engine needs none).

use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    let mut v: Vec<PathBuf> = rd.flatten().map(|e| e.path()).collect();
    v.sort();
    for p in v {
        if p.is_dir() {
            walk(&p, out);
        } else {
            out.push(p);
        }
    }
}

/// tools/pack.py step_hsjson (without the texts).
fn classic_cards(data: &[u8], patch: &[u8]) -> Vec<u8> {
    let mut data: Vec<Map<String, Value>> = serde_json::from_slice(data).expect("data/cards.json");
    let patch: Map<String, Value> = serde_json::from_slice(patch).expect("cards.patch.json");
    let fields = [("cardClass", "class"), ("rarity", "rarity"), ("set", "set"), ("collectible", "collectible"),
        ("cost", "cost"), ("attack", "attack"), ("health", "health"), ("durability", "durability"), ("race", "race"),
        ("mechanics", "keywords"), ("referencedTags", "refs"), ("spellDamage", "spell_power"), ("overload", "mana_lock"),
        ("elite", "unique"), ("dbfId", "code_id"), ("legacyDbfId", "legacy_code_id")];
    data.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    for id in patch.keys() {
        assert!(data.iter().any(|c| c["id"] == *id), "cards.patch.json: unknown card {id}");
    }
    let out: Vec<Value> = data
        .iter()
        .map(|c| {
            let mut card = Map::new();
            card.insert("id".into(), c["id"].clone());
            let ty = match c["type"].as_str().unwrap_or("") {
                "HERO" => "CHAMPION",
                "HERO_POWER" => "POWER",
                t => t,
            };
            card.insert("type".into(), json!(ty));
            for (a, k) in fields {
                match c.get(a) {
                    None | Some(Value::Null) | Some(Value::Bool(false)) => {}
                    Some(Value::Array(x)) if x.is_empty() => {}
                    Some(v) => {
                        card.insert(k.into(), v.clone());
                    }
                }
            }
            if let Some(Value::Object(p)) = patch.get(c["id"].as_str().unwrap_or("")) {
                for (k, v) in p {
                    card.insert(k.clone(), v.clone());
                }
            }
            Value::Object(card)
        })
        .collect();
    serde_json::to_vec(&out).unwrap()
}

fn main() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..").canonicalize().expect("repo");
    let src = root.join("packs/classic");
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let mut files = vec![src.join("manifest.json"), src.join("rules.json")];
    for (d, ext) in [("missions", "json"), ("scripts", "lua")] {
        let mut v = vec![];
        walk(&src.join(d), &mut v);
        files.extend(v.into_iter().filter(|p| p.extension().is_some_and(|e| e == ext)));
        println!("cargo:rerun-if-changed={}", src.join(d).display());
    }
    let (data_p, patch_p) = (root.join("data/cards.json"), src.join("cards.patch.json"));
    let data = std::fs::read(&data_p).expect("data/cards.json");
    std::fs::write(out_dir.join("cards.json"), classic_cards(&data, &std::fs::read(&patch_p).expect("cards.patch.json"))).unwrap();
    let hash: String = Sha256::digest(&data).iter().map(|b| format!("{b:02x}")).collect();
    let mut out = format!("/// SHA-256 of data/cards.json (`ping`'s data hash).\npub const DATA_HASH: &str = {hash:?};\n");
    out += "pub const FILES: &[(&str, &[u8])] = &[\n";
    out += &format!("    (\"cards.json\", include_bytes!({:?})),\n", out_dir.join("cards.json").display().to_string());
    for f in files.iter().chain([&data_p, &patch_p]) {
        println!("cargo:rerun-if-changed={}", f.display());
    }
    for f in &files {
        let rel = f.strip_prefix(&src).unwrap().to_string_lossy().replace('\\', "/");
        out += &format!("    ({rel:?}, include_bytes!({:?})),\n", f.display().to_string());
    }
    out += "];\n";
    std::fs::write(out_dir.join("classic_files.rs"), out).unwrap();
}
