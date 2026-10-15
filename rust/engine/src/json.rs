//! Godot's `JSON.stringify(value)` with its defaults (no indent, sorted keys,
//! 14 significant float digits), byte for byte: `state_hash()` hashes its output.

use serde_json::Value;

pub fn stringify(v: &Value) -> String {
    let mut out = String::new();
    write(v, &mut out);
    out
}

fn write(v: &Value, out: &mut String) {
    match v {
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                out.push_str(&i.to_string());
            } else if let Some(u) = n.as_u64() {
                out.push_str(&(u as i64).to_string());
            } else {
                out.push_str(&float(n.as_f64().unwrap_or(0.0)));
            }
        }
        Value::String(s) => escape(s, out),
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
        // serde_json's Map is a BTreeMap: keys come sorted by code point, as Godot sorts them.
        Value::Object(m) => {
            out.push('{');
            for (i, (k, x)) in m.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                escape(k, out);
                out.push(':');
                write(x, out);
            }
            out.push('}');
        }
    }
}

/// String::json_escape.
fn escape(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{b}' => out.push_str("\\v"),
            _ => out.push(c),
        }
    }
    out.push('"');
}

/// Godot: String::num(x, max(1, 14 - floor(log10|x|))), trailing zeros cut to one.
fn float(x: f64) -> String {
    if x == 0.0 {
        return "0.0".into();
    }
    let prec = (14 - x.abs().log10().floor() as i32).max(1) as usize;
    let mut s = format!("{:.*}", prec, x);
    while s.ends_with('0') && !s.ends_with(".0") {
        s.pop();
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn matches_godot() {
        // Printed by Godot 4.7.2 for the same value.
        let v = json!({"b": 1, "a": [1.0, 0.5, 2.25, -3, true, null, "x\"\\\n\t/é"],
            "c": {"10": 1, "9": 2, "1": 3}, "f": 1e20, "g": 0.1, "h": 123456.789, "i": -0.0});
        assert_eq!(stringify(&v), r#"{"a":[1.0,0.5,2.25,-3,true,null,"x\"\\\n\t/é"],"b":1,"c":{"1":3,"10":1,"9":2},"f":100000000000000000000.0,"g":0.1,"h":123456.789,"i":0.0}"#);
        assert_eq!(stringify(&json!({"k": 1.0 / 3.0, "big": 4294967296.0})), r#"{"big":4294967296.0,"k":0.333333333333333}"#);
    }
}
