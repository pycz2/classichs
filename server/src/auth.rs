//! Passwords (argon2id), session tokens (SHA-256 stored), name rules, rate limits.

use argon2::password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use rand::RngCore;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::time::{Duration, Instant};

pub const TOKEN_DAYS: i64 = 30;

pub fn hash_password(pw: &str) -> String {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default().hash_password(pw.as_bytes(), &salt).expect("argon2").to_string()
}

pub fn verify_password(pw: &str, stored: &str) -> bool {
    PasswordHash::new(stored)
        .map(|h| Argon2::default().verify_password(pw.as_bytes(), &h).is_ok())
        .unwrap_or(false)
}

/// A hash to verify against when the account does not exist (same time either way).
pub fn dummy_hash() -> &'static str {
    static H: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    H.get_or_init(|| hash_password("not a real password"))
}

/// 32 random bytes, base64url: (token for the client, SHA-256 for the database).
pub fn new_token() -> (String, Vec<u8>) {
    let mut b = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut b);
    let t = URL_SAFE_NO_PAD.encode(b);
    let h = token_hash(&t);
    (t, h)
}

pub fn token_hash(t: &str) -> Vec<u8> {
    Sha256::digest(t.as_bytes()).to_vec()
}

pub fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

pub fn valid_user(u: &str) -> bool {
    (3..=20).contains(&u.len()) && u.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
}

pub fn valid_password(p: &str) -> bool {
    (8..=128).contains(&p.chars().count())
}

/// Tag: 3–16 letters or digits (unique case-insensitively, enforced by the database).
pub fn valid_tag(t: &str) -> bool {
    (3..=16).contains(&t.chars().count()) && t.chars().all(|c| c.is_alphanumeric())
}

/// At most `max` hits per `window` for each key (fixed windows).
pub struct RateLimit {
    window: Duration,
    max: u32,
    hits: HashMap<String, (Instant, u32)>,
}

impl RateLimit {
    pub fn new(max: u32, window: Duration) -> Self {
        RateLimit { window, max, hits: HashMap::new() }
    }

    pub fn allow(&mut self, key: &str, now: Instant) -> bool {
        let e = self.hits.entry(key.to_string()).or_insert((now, 0));
        if now.duration_since(e.0) >= self.window {
            *e = (now, 0);
        }
        e.1 += 1;
        e.1 <= self.max
    }

    pub fn sweep(&mut self, now: Instant) {
        let w = self.window;
        self.hits.retain(|_, e| now.duration_since(e.0) < w);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn passwords_and_tokens() {
        let h = hash_password("correct horse");
        assert!(h.starts_with("$argon2id$"));
        assert!(!h.contains("correct horse"));
        assert!(verify_password("correct horse", &h));
        assert!(!verify_password("wrong horse!", &h));
        assert!(!verify_password("x", "garbage"));
        let (t, th) = new_token();
        assert_eq!(t.len(), 43);
        assert_eq!(th, token_hash(&t));
        assert_ne!(new_token().0, t);
        assert!(ct_eq(b"abc", b"abc") && !ct_eq(b"abc", b"abd") && !ct_eq(b"ab", b"abc"));
    }

    #[test]
    fn name_rules() {
        assert!(valid_user("abc_9") && !valid_user("ab") && !valid_user("a b c") && !valid_user(&"a".repeat(21)));
        assert!(valid_password("12345678") && !valid_password("1234567") && !valid_password(&"x".repeat(129)));
        assert!(valid_tag("Jaina") && valid_tag("Джайна1") && !valid_tag("ja") && !valid_tag("ja_na"));
        assert!(!valid_tag(&"a".repeat(17)));
    }

    #[test]
    fn rate_limit() {
        let mut r = RateLimit::new(10, Duration::from_secs(60));
        let t = Instant::now();
        assert!((0..10).all(|_| r.allow("ip", t)));
        assert!(!r.allow("ip", t));
        assert!(r.allow("other", t));
        assert!(r.allow("ip", t + Duration::from_secs(61)));
        r.sweep(t + Duration::from_secs(200));
        assert!(r.hits.is_empty());
    }
}
