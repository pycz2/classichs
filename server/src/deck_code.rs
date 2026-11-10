//! Deck codes, the client's (game/deck_code.gd): Hearthstone deckstrings for every pack. The code is
//! base64 of varints `[0, 1, format, 1, hero, n1, singles…, n2, doubles…, n3, (card, count)…]`, each id
//! a card's `code_id` (Classic and Naxxramas: Hearthstone's dbfId, so Hearthstone's codes import; the
//! legacy one where no card has that number) or, for a pack without code numbers (Neonfall), the
//! Godot `String.hash()` of the card id (djb2 over the code points, 32 bits): what CardDb gives it.
//! The code names no pack: it is read in the game it is imported into. server/README.md, "Deck codes".

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use classichs_engine::deck::Deck;
use classichs_engine::ruleset::{Card, Ruleset};
use std::collections::{BTreeMap, HashMap};

/// The format the client writes (Hearthstone's Classic); Wild (1) and Standard (2) are read too.
pub const FORMAT_CLASSIC: u64 = 3;

/// A card's number in codes.
pub fn code_of(c: &Card) -> u64 {
    c.code_id.map_or_else(|| godot_hash(&c.id), |n| n as u64)
}

fn godot_hash(s: &str) -> u64 {
    s.chars().fold(5381u32, |h, c| h.wrapping_mul(33).wrapping_add(c as u32)) as u64
}

fn varint(out: &mut Vec<u8>, mut v: u64) {
    loop {
        let b = (v & 0x7f) as u8;
        v >>= 7;
        if v == 0 {
            out.push(b);
            return;
        }
        out.push(b | 0x80);
    }
}

/// The code of a deck (None: a card or the hero is not in these rules). Any deck, incomplete too.
pub fn encode(rs: &Ruleset, hero: &str, cards: &[String]) -> Option<String> {
    let mut counts: BTreeMap<u64, u64> = BTreeMap::new();
    for id in cards {
        *counts.entry(code_of(rs.cards.get(id)?)).or_default() += 1;
    }
    let pick = |f: fn(u64) -> bool| counts.iter().filter(|(_, n)| f(**n)).map(|(c, n)| (*c, *n)).collect::<Vec<_>>();
    let (singles, doubles, more) = (pick(|n| n == 1), pick(|n| n == 2), pick(|n| n > 2));
    let mut out = vec![];
    for v in [0, 1, FORMAT_CLASSIC, 1, code_of(rs.cards.get(hero)?)] {
        varint(&mut out, v);
    }
    for list in [&singles, &doubles] {
        varint(&mut out, list.len() as u64);
        list.iter().for_each(|(c, _)| varint(&mut out, *c));
    }
    varint(&mut out, more.len() as u64);
    for (c, n) in more {
        varint(&mut out, c);
        varint(&mut out, n);
    }
    Some(STANDARD.encode(out))
}

/// A deck read from a code.
#[derive(Debug, PartialEq)]
pub struct Decoded {
    /// From a "### Name" line (Hearthstone's copied text), else None.
    pub name: Option<String>,
    pub hero: String,
    pub cards: Vec<String>,
}

const NOT_A_CODE: &str = "This is not a deck code";

/// (format, heroes, [(card, count)]) of one line, as the client's DeckCode.parse.
fn parse(code: &str) -> Result<(u64, Vec<u64>, Vec<(u64, u64)>), String> {
    let code = code.trim();
    if code.len() < 8 || code.len() % 4 != 0 {
        return Err(NOT_A_CODE.into());
    }
    let raw = STANDARD.decode(code).map_err(|_| NOT_A_CODE.to_string())?;
    let mut it = raw.into_iter();
    let mut read = || -> Result<u64, String> {
        let (mut v, mut shift) = (0u64, 0);
        while shift < 63 {
            let b = it.next().ok_or(NOT_A_CODE)?;
            v |= u64::from(b & 0x7f) << shift;
            shift += 7;
            if b & 0x80 == 0 {
                return Ok(v);
            }
        }
        Err(NOT_A_CODE.into())
    };
    if read()? != 0 || read()? != 1 {
        return Err(NOT_A_CODE.into());
    }
    let format = read()?;
    let mut lists = vec![];
    for _ in 0..3 {
        let n = read()?;
        if n > 60 {
            return Err(NOT_A_CODE.into());
        }
        lists.push((0..n).map(|_| read()).collect::<Result<Vec<u64>, _>>()?);
    }
    let mut cards: Vec<(u64, u64)> = lists[1].iter().map(|c| (*c, 1)).chain(lists[2].iter().map(|c| (*c, 2))).collect();
    let more = read()?;
    if more > 60 {
        return Err(NOT_A_CODE.into());
    }
    for _ in 0..more {
        let c = read()?;
        cards.push((c, read()?.min(60)));
    }
    Ok((format, lists[0].clone(), cards))
}

/// A complete, legal deck of these rules from a code, or a text copied out of Hearthstone ("###
/// Name", "#" comment lines, the code on a line of its own), or why not.
pub fn decode(rs: &Ruleset, text: &str) -> Result<Decoded, String> {
    let mut name = None;
    let mut parsed = Err(NOT_A_CODE.to_string());
    for line in text.lines().map(str::trim) {
        if let Some(n) = line.strip_prefix("###") {
            name = Some(n.trim().chars().take(60).collect::<String>()).filter(|n| !n.is_empty());
        } else if !line.is_empty() && !line.starts_with('#') && parsed.is_err() {
            parsed = parse(line);
        }
    }
    let (format, heroes, counts) = parsed?;
    if !(1..=3).contains(&format) {
        return Err("Unknown deck format".into());
    }
    if heroes.len() != 1 {
        return Err("A deck needs exactly one hero".into());
    }
    let mut by_code: HashMap<u64, &str> = rs.cards.values().map(|c| (code_of(c), c.id.as_str())).collect();
    for c in rs.cards.values() {
        if let Some(l) = c.legacy_code_id {
            by_code.entry(l as u64).or_insert(&c.id);
        }
    }
    let mut cards = vec![];
    for (code, n) in counts {
        let id = by_code.get(&code).filter(|id| rs.collectible.binary_search(&id.to_string()).is_ok());
        let id = id.ok_or_else(|| format!("The deck has a card this game does not have (number {code})"))?;
        cards.extend(std::iter::repeat_n(id.to_string(), n as usize));
    }
    let hero = match by_code.get(&heroes[0]).filter(|h| rs.class_of_champion(h).is_some()) {
        Some(h) => h.to_string(),
        // a hero skin (Magni, Medivh…): the champion of the cards' class
        None => cards
            .iter()
            .filter_map(|id| rs.classes.iter().find(|k| !k.neutral && k.id == rs.card(id).card_class))
            .map(|k| k.champion.clone())
            .next()
            .ok_or("Unknown hero in the deck code")?,
    };
    let why = Deck { hero: hero.clone(), cards: cards.clone(), arena: false }.validate_in(rs);
    if !why.is_empty() {
        return Err(why);
    }
    Ok(Decoded { name, hero, cards })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn godot_string_hash() {
        // printed by Godot 4.7: "iris_null".hash(), "a".hash(), "ё".hash()
        assert_eq!([godot_hash("iris_null"), godot_hash("a"), godot_hash("ё")], [2488354134, 177670, 178678]);
    }

    #[test]
    fn hearthsim_reference_code() {
        // the client's test_deck_model.gd: a 2016 Hunter deck of Basic and Classic cards (Standard format)
        let d = decode(classichs_engine::ruleset::classic(), "AAECAR8GxwPJBLsFmQfZB/gIDI0B2AGoArUDhwSSBe0G6wfbCe0JgQr+DAA=").unwrap();
        assert_eq!((d.hero.as_str(), d.cards.len()), ("HERO_05", 30));
    }

    #[test]
    fn garbage_is_refused() {
        let rs = classichs_engine::ruleset::classic();
        for bad in ["", "   ", "hello world!", "AAAA", "AAECAQcAAAA=", "%%%%", "AAECAR8GxwPJBLsFmQfZB/gIDI0B2AGoArUDhwSSBe0G6wfbCe0J"] {
            assert!(decode(rs, bad).is_err(), "{bad}");
        }
    }
}
