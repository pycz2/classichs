//! Reading a game pack: the `.cardpack` zip (or an unpacked folder), strict
//! JSON, the canonical JSON form and `rules_hash` (docs/packs/format.md §1, §3;
//! the same as `tools/pack.py`).

use serde::de::{self, Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

/// Path → bytes of the files of a pack that the engine reads.
pub type Files = BTreeMap<String, Vec<u8>>;

const MIB: usize = 1 << 20;
const MAX_PACK: usize = 128 * MIB;
const MAX_UNPACKED: usize = 256 * MIB;
const MAX_FILES: usize = 10_000;
const MAX_FILE: usize = 16 * MIB;
const MAX_RULES: usize = 8 * MIB;
const MAX_RATIO: usize = 200;

/// Files that `rules_hash` covers (and the only ones the engine needs, with the manifest).
pub fn is_rules_file(p: &str) -> bool {
    p == "rules.json"
        || p == "cards.json"
        || (p.starts_with("missions/") && p.ends_with(".json"))
        || (p.starts_with("scripts/") && p.ends_with(".lua"))
}

fn wanted(p: &str) -> bool {
    p == "manifest.json" || is_rules_file(p)
}

/// Path rules of format.md §1: segments `[A-Za-z0-9_][A-Za-z0-9_.-]*`, at most 200 characters.
fn path_ok(p: &str) -> bool {
    p.len() <= 200
        && p.split('/').all(|s| {
            let mut c = s.chars();
            c.next().is_some_and(|f| f.is_ascii_alphanumeric() || f == '_')
                && c.all(|x| x.is_ascii_alphanumeric() || matches!(x, '_' | '.' | '-'))
        })
}

fn u16_at(b: &[u8], i: usize) -> Result<usize, String> {
    b.get(i..i + 2).map(|x| u16::from_le_bytes([x[0], x[1]]) as usize).ok_or_else(|| "truncated zip".to_string())
}

fn u32_at(b: &[u8], i: usize) -> Result<usize, String> {
    b.get(i..i + 4).map(|x| u32::from_le_bytes([x[0], x[1], x[2], x[3]]) as usize).ok_or_else(|| "truncated zip".to_string())
}

/// The rules files and the manifest of a `.cardpack`, checking the limits of format.md §1.
/// ponytail: no CRC check (the hashes of the files catch corruption that matters); no zip64.
pub fn read_zip(b: &[u8]) -> Result<Files, String> {
    if b.len() > MAX_PACK {
        return Err(format!("the pack is {} bytes, more than {MAX_PACK}", b.len()));
    }
    let from = b.len().saturating_sub(22 + 65_535);
    let eocd = (from..b.len().saturating_sub(21))
        .rev()
        .find(|&i| b[i..i + 4] == [0x50, 0x4b, 0x05, 0x06])
        .ok_or("not a zip file")?;
    let count = u16_at(b, eocd + 10)?;
    let mut at = u32_at(b, eocd + 16)?;
    if count > MAX_FILES {
        return Err(format!("{count} files, more than {MAX_FILES}"));
    }
    let (mut out, mut seen) = (Files::new(), std::collections::BTreeSet::new());
    let (mut unpacked, mut rules) = (0usize, 0usize);
    for _ in 0..count {
        if u32_at(b, at)? != 0x0201_4b50 {
            return Err("bad zip central directory".into());
        }
        let (flags, method) = (u16_at(b, at + 8)?, u16_at(b, at + 10)?);
        let (csize, usize_) = (u32_at(b, at + 20)?, u32_at(b, at + 24)?);
        let (nlen, xlen, clen) = (u16_at(b, at + 28)?, u16_at(b, at + 30)?, u16_at(b, at + 32)?);
        let (attr, local) = (u32_at(b, at + 38)?, u32_at(b, at + 42)?);
        let name = std::str::from_utf8(b.get(at + 46..at + 46 + nlen).ok_or("truncated zip")?)
            .map_err(|_| "a file name is not UTF-8")?
            .to_string();
        at += 46 + nlen + xlen + clen;
        if name.ends_with('/') {
            continue;
        }
        if !path_ok(&name) {
            return Err(format!("{name}: a path a pack may not have"));
        }
        if !seen.insert(name.clone()) {
            return Err(format!("{name}: twice in the zip"));
        }
        if flags & 1 != 0 {
            return Err(format!("{name}: encrypted"));
        }
        if (attr >> 16) & 0o170000 == 0o120000 {
            return Err(format!("{name}: a symbolic link"));
        }
        if csize == 0xFFFF_FFFF || usize_ == 0xFFFF_FFFF {
            return Err(format!("{name}: zip64 is not supported"));
        }
        if usize_ > MAX_FILE || (csize > 0 && usize_ / csize > MAX_RATIO) {
            return Err(format!("{name}: too big or too compressed"));
        }
        unpacked += usize_;
        if unpacked > MAX_UNPACKED {
            return Err("the pack is too big unpacked".into());
        }
        if !wanted(&name) {
            continue;
        }
        rules += usize_;
        if rules > MAX_RULES {
            return Err(format!("the rules part is more than {MAX_RULES} bytes"));
        }
        if u32_at(b, local)? != 0x0403_4b50 {
            return Err(format!("{name}: bad local header"));
        }
        let start = local + 30 + u16_at(b, local + 26)? + u16_at(b, local + 28)?;
        let data = b.get(start..start + csize).ok_or("truncated zip")?;
        let bytes = match method {
            0 => data.to_vec(),
            8 => miniz_oxide::inflate::decompress_to_vec_with_limit(data, usize_)
                .map_err(|_| format!("{name}: bad deflate data"))?,
            m => return Err(format!("{name}: compression method {m} is not supported")),
        };
        if bytes.len() != usize_ {
            return Err(format!("{name}: wrong size"));
        }
        out.insert(name, bytes);
    }
    Ok(out)
}

/// The rules files and the manifest of an unpacked pack folder (native hosts, tests, development).
pub fn read_dir(dir: &std::path::Path) -> Result<Files, String> {
    fn walk(root: &std::path::Path, dir: &std::path::Path, out: &mut Files) -> Result<(), String> {
        let rd = std::fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        let mut items: Vec<_> = rd.flatten().collect();
        items.sort_by_key(|e| e.file_name());
        for e in items {
            let p = e.path();
            let rel = p.strip_prefix(root).map_err(|e| e.to_string())?.to_string_lossy().replace('\\', "/");
            if p.is_dir() {
                walk(root, &p, out)?;
            } else if wanted(&rel) {
                out.insert(rel, std::fs::read(&p).map_err(|e| format!("{}: {e}", p.display()))?);
            }
        }
        Ok(())
    }
    let mut out = Files::new();
    walk(dir, dir, &mut out)?;
    Ok(out)
}

/// Standard base64 (padding optional, whitespace ignored).
pub fn base64(s: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let (mut acc, mut bits) = (0u32, 0);
    for c in s.bytes().filter(|c| !c.is_ascii_whitespace() && *c != b'=') {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            _ => return Err("bad base64".into()),
        };
        acc = (acc << 6) | v as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
        }
    }
    Ok(out)
}

// --- strict JSON ------------------------------------------------------------------------------

struct Strict(Value);

impl<'de> Deserialize<'de> for Strict {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        d.deserialize_any(StrictVisitor).map(Strict)
    }
}

struct StrictVisitor;

impl<'de> Visitor<'de> for StrictVisitor {
    type Value = Value;
    fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("JSON")
    }
    fn visit_bool<E>(self, v: bool) -> Result<Value, E> {
        Ok(Value::Bool(v))
    }
    fn visit_i64<E>(self, v: i64) -> Result<Value, E> {
        Ok(Value::Number(v.into()))
    }
    fn visit_u64<E>(self, v: u64) -> Result<Value, E> {
        Ok(Value::Number(v.into()))
    }
    fn visit_f64<E: de::Error>(self, v: f64) -> Result<Value, E> {
        Err(E::custom(format!("fractions are not allowed ({v})")))
    }
    fn visit_str<E>(self, v: &str) -> Result<Value, E> {
        Ok(Value::String(v.to_string()))
    }
    fn visit_string<E>(self, v: String) -> Result<Value, E> {
        Ok(Value::String(v))
    }
    fn visit_unit<E>(self) -> Result<Value, E> {
        Ok(Value::Null)
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut s: A) -> Result<Value, A::Error> {
        let mut v = vec![];
        while let Some(Strict(x)) = s.next_element()? {
            v.push(x);
        }
        Ok(Value::Array(v))
    }
    fn visit_map<A: MapAccess<'de>>(self, mut m: A) -> Result<Value, A::Error> {
        let mut out = Map::new();
        while let Some(k) = m.next_key::<String>()? {
            let Strict(v) = m.next_value()?;
            if out.insert(k.clone(), v).is_some() {
                return Err(de::Error::custom(format!("duplicate key {k:?}")));
            }
        }
        Ok(Value::Object(out))
    }
}

/// JSON parsed as format.md §3 demands: UTF-8 without BOM, no duplicate keys, no fractions.
pub fn strict_json(bytes: &[u8], what: &str) -> Result<Value, String> {
    if bytes.starts_with(b"\xef\xbb\xbf") {
        return Err(format!("{what}: UTF-8 BOM"));
    }
    let mut d = serde_json::Deserializer::from_slice(bytes);
    let v = Strict::deserialize(&mut d).map_err(|e| format!("{what}: {e}"))?;
    d.end().map_err(|e| format!("{what}: {e}"))?;
    Ok(v.0)
}

/// The canonical JSON bytes (Python `json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":"))`).
pub fn canonical(v: &Value) -> String {
    fn esc(s: &str, out: &mut String) {
        out.push('"');
        for c in s.chars() {
            match c {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                '\u{8}' => out.push_str("\\b"),
                '\u{c}' => out.push_str("\\f"),
                c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
                c => out.push(c),
            }
        }
        out.push('"');
    }
    fn write(v: &Value, out: &mut String) {
        match v {
            Value::Null => out.push_str("null"),
            Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Value::Number(n) => out.push_str(&n.to_string()),
            Value::String(s) => esc(s, out),
            Value::Array(a) => {
                out.push('[');
                for (i, x) in a.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    write(x, out);
                }
                out.push(']');
            }
            Value::Object(m) => {
                let mut keys: Vec<&String> = m.keys().collect();
                keys.sort();
                out.push('{');
                for (i, k) in keys.into_iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    esc(k, out);
                    out.push(':');
                    write(&m[k], out);
                }
                out.push('}');
            }
        }
    }
    let mut out = String::new();
    write(v, &mut out);
    out
}

/// Presentation fields of a card: not part of `rules_hash`.
const PRESENTATION: [&str; 3] = ["fx", "sounds", "voice"];

/// A Lua file as hashed and run: no leading BOM, `\r\n` and `\r` as `\n`.
pub fn lua_text(data: &[u8]) -> Vec<u8> {
    let d = data.strip_prefix(b"\xef\xbb\xbf").unwrap_or(data);
    let mut out = Vec::with_capacity(d.len());
    let mut i = 0;
    while i < d.len() {
        if d[i] == b'\r' {
            out.push(b'\n');
            if d.get(i + 1) == Some(&b'\n') {
                i += 1;
            }
        } else {
            out.push(d[i]);
        }
        i += 1;
    }
    out
}

fn normalized(path: &str, data: &[u8]) -> Result<Vec<u8>, String> {
    if path.ends_with(".lua") {
        return Ok(lua_text(data));
    }
    let mut v = strict_json(data, path)?;
    if path == "cards.json" {
        if let Value::Array(cards) = &mut v {
            for c in cards.iter_mut().filter_map(Value::as_object_mut) {
                for k in PRESENTATION {
                    c.remove(k);
                }
            }
        }
    }
    Ok(canonical(&v).into_bytes())
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// `rules_hash` of format.md §3 over the rules files among `files`.
pub fn rules_hash(files: &Files) -> Result<String, String> {
    let mut h = Sha256::new();
    h.update(b"cardpack-rules/1\n");
    // BTreeMap<String> iterates in byte order of the paths, as the format sorts them.
    for (p, d) in files.iter().filter(|(p, _)| is_rules_file(p)) {
        h.update(format!("{p}:{}\n", hex(&Sha256::digest(normalized(p, d)?))).as_bytes());
    }
    Ok(hex(&h.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strict_json_refuses_what_the_format_refuses() {
        assert!(strict_json(br#"{"a": 1, "a": 2}"#, "x").unwrap_err().contains("duplicate"));
        assert!(strict_json(b"[1.5]", "x").unwrap_err().contains("fraction"));
        assert!(strict_json(b"\xef\xbb\xbf{}", "x").is_err());
        assert_eq!(canonical(&strict_json("{\"b\":[1,true,null],\"a\":\"\u{e9}\\n\\u0001\"}".as_bytes(), "x").unwrap()),
            "{\"a\":\"\u{e9}\\n\\u0001\",\"b\":[1,true,null]}");
    }

    #[test]
    fn base64_decodes() {
        assert_eq!(base64("aGVsbG8gd29ybGQ=").unwrap(), b"hello world");
        assert_eq!(base64("YQ").unwrap(), b"a");
    }

    #[test]
    fn paths() {
        assert!(path_ok("scripts/mage.lua") && path_ok("art/generated/VAN_CS2_029.jpg"));
        assert!(!path_ok("../x") && !path_ok("/x") && !path_ok("a/.hidden") && !path_ok("a//b"));
    }
}
