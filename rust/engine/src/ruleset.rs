//! A ruleset: what a game pack defines for play (rules.json, cards.json,
//! mechanic names, missions, card scripts), loaded and ready (docs/packs/).
//! Each ruleset is built once per `rules_hash` and kept for the life of the
//! process (`&'static`), so entities and games can point into it.
//! The built-in one is the Classic pack, made from the repo's sources at build time.

use crate::hooks::HookSet;
use crate::lua::LuaRules;
use crate::missions::Mission;
use crate::pack::{self, Files};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap};
use std::sync::{Mutex, OnceLock};

/// The engine's vocabulary (docs/packs/schema/keywords.json).
const KEYWORDS_JSON: &str = include_str!("../../../docs/packs/schema/keywords.json");

/// Engine ids of the keywords a card starts with as a `true` tag.
const START_TAGS: [&str; 10] =
    ["GUARD", "HASTE", "BARRIER", "STEALTH", "DOUBLE_ATTACK", "CANT_ATTACK", "SPELLPROOF", "FROZEN", "IMMUNE", "FROZEN_THIS_TURN"];
/// Engine ids of the tags Silence removes.
const SILENCED: [&str; 11] = ["GUARD", "HASTE", "BARRIER", "STEALTH", "DOUBLE_ATTACK", "CANT_ATTACK", "SPELLPROOF", "FROZEN",
    "IMMUNE", "FROZEN_THIS_TURN", "SPELL_POWER"];
/// Rarity tiers in the order the Arena draws them.
pub const TIERS: [&str; 4] = ["common", "rare", "epic", "legendary"];

pub(crate) fn leak(s: &str) -> &'static str {
    Box::leak(s.to_string().into_boxed_str())
}

/// A card as the engine uses it. `kind` is the pack type (`MINION`, `SPELL`,
/// `WEAPON`, `CHAMPION`, `POWER`, `ENCHANTMENT`); snapshots show the client's
/// older names (`api::snapshot`).
#[derive(Debug, Default)]
pub struct Card {
    pub id: String,
    pub kind: String,
    pub cost: i64,
    pub attack: i64,
    pub health: i64,
    pub durability: i64,
    /// MANA_LOCK amount.
    pub mana_lock: i64,
    /// SPELL_POWER amount.
    pub spell_power: Option<i64>,
    pub race: String,
    /// The pack's keyword names.
    pub keywords: Vec<String>,
    pub rarity: String,
    pub card_class: String,
    pub collectible: bool,
    pub set: String,
    /// CHAMPION: its POWER card ("" = none).
    pub power: String,
    /// `scripts/<file>.lua#<key>` ("" = no script).
    pub script: String,
    /// A TRAP spell.
    pub trap: bool,
    /// The tags an entity of this card starts with.
    pub start_tags: Map<String, Value>,
    /// Its hooks (set once the scripts are loaded).
    pub hooks: HookSet,
}

#[derive(Deserialize)]
struct PackCard {
    id: String,
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    class: String,
    #[serde(default)]
    rarity: String,
    #[serde(default)]
    set: String,
    #[serde(default)]
    collectible: bool,
    #[serde(default)]
    cost: i64,
    #[serde(default)]
    attack: i64,
    #[serde(default)]
    health: i64,
    #[serde(default)]
    durability: i64,
    #[serde(default)]
    race: String,
    #[serde(default)]
    keywords: Vec<String>,
    spell_power: Option<i64>,
    #[serde(default)]
    mana_lock: i64,
    #[serde(default)]
    power: String,
    #[serde(default)]
    script: String,
}

/// Tag names (the pack's names of the engine's mechanics, D7): the engine
/// reads and writes tags by these, so snapshots and hashes show the pack's words.
#[derive(Debug, Clone)]
pub struct Names {
    pub guard: &'static str,
    pub haste: &'static str,
    pub barrier: &'static str,
    pub double_attack: &'static str,
    pub stealth: &'static str,
    pub spellproof: &'static str,
    pub cant_attack: &'static str,
    pub immune: &'static str,
    pub spell_power: &'static str,
    pub frozen: &'static str,
    pub frozen_this_turn: &'static str,
    pub exhausted: &'static str,
    pub attacks: &'static str,
    pub armor: &'static str,
    pub durability: &'static str,
    pub used: &'static str,
    pub locked: &'static str,
    pub guarded: &'static str,
    pub to_destroy: &'static str,
    pub died_pos: &'static str,
    pub power_multiplier: &'static str,
    pub heal_is_damage: &'static str,
    /// The TRAP mechanic's name: also the zone that holds traps.
    pub trap: &'static str,
    /// Tags Silence removes.
    pub silenced: Vec<&'static str>,
    /// Engine id → pack name.
    by_engine: HashMap<String, &'static str>,
    /// Pack name → engine id.
    pub engine_of: HashMap<String, String>,
}

impl Names {
    fn new(mechanics: &Map<String, Value>) -> Result<Names, String> {
        let vocab: Value = serde_json::from_str(KEYWORDS_JSON).expect("keywords.json");
        let ids: Vec<&str> = vocab["keywords"].as_array().unwrap().iter().filter_map(|k| k["id"].as_str()).collect();
        let mut by_engine = HashMap::new();
        let mut engine_of = HashMap::new();
        for (name, m) in mechanics {
            let eid = m.get("engine").and_then(Value::as_str).ok_or(format!("mechanic {name}: no engine id"))?;
            if !ids.contains(&eid) {
                return Err(format!("mechanic {name}: unknown engine id {eid}"));
            }
            if by_engine.insert(eid.to_string(), leak(name)).is_some() {
                return Err(format!("two mechanics map to {eid}"));
            }
            engine_of.insert(name.clone(), eid.to_string());
        }
        let n = |id: &str| -> &'static str { by_engine.get(id).copied().unwrap_or_else(|| leak(id)) };
        Ok(Names {
            guard: n("GUARD"),
            haste: n("HASTE"),
            barrier: n("BARRIER"),
            double_attack: n("DOUBLE_ATTACK"),
            stealth: n("STEALTH"),
            spellproof: n("SPELLPROOF"),
            cant_attack: n("CANT_ATTACK"),
            immune: n("IMMUNE"),
            spell_power: n("SPELL_POWER"),
            frozen: n("FROZEN"),
            frozen_this_turn: n("FROZEN_THIS_TURN"),
            exhausted: n("EXHAUSTED"),
            attacks: n("ATTACKS"),
            armor: n("ARMOR"),
            durability: n("DURABILITY"),
            used: n("USED"),
            locked: n("LOCKED"),
            guarded: n("GUARDED"),
            to_destroy: n("TO_DESTROY"),
            died_pos: n("DIED_POS"),
            power_multiplier: n("POWER_MULTIPLIER"),
            heal_is_damage: n("HEAL_IS_DAMAGE"),
            trap: n("TRAP"),
            silenced: SILENCED.iter().map(|id| n(id)).collect(),
            by_engine: by_engine.clone(),
            engine_of,
        })
    }

    /// The tag name for a name a script gives: a pack name as is; an engine
    /// id the pack renames becomes the pack's name.
    pub fn tag<'a>(&self, s: &'a str) -> &'a str {
        if self.engine_of.contains_key(s) {
            return s;
        }
        self.by_engine.get(s).copied().unwrap_or(s)
    }

    /// The engine id of a pack name (the name itself if the pack does not map it).
    pub fn engine<'a>(&'a self, s: &'a str) -> &'a str {
        self.engine_of.get(s).map_or(s, String::as_str)
    }
}

#[derive(Debug, Default, Clone)]
pub struct Class {
    pub id: String,
    pub champion: String,
    pub neutral: bool,
    pub playable: bool,
}

#[derive(Debug, Default)]
pub struct Arena {
    pub sets: Vec<String>,
    pub champions_offered: usize,
    pub classes: Vec<String>,
    pub picks: usize,
    pub offer: usize,
    /// Per mille, in TIERS order.
    pub tier_weights: Vec<(&'static str, i64)>,
    /// 0-based pick indexes that use `special_tier_weights`.
    pub special_picks: Vec<usize>,
    pub special_tier_weights: Vec<(&'static str, i64)>,
    pub class_weight: i64,
    pub neutral_weight: i64,
}

pub struct Ruleset {
    pub id: String,
    pub version: String,
    pub rules_hash: String,
    /// What `ping`/`data_hash` report: the built-in ruleset keeps the SHA-256 of
    /// data/cards.json (as before packs); a pack gives its rules_hash.
    pub data_hash: String,
    pub builtin: bool,
    pub cards: HashMap<String, Card>,
    /// Collectible cards of the constructed sets, sorted by id.
    pub collectible: Vec<String>,
    pub arena_pool: Vec<String>,
    pub names: Names,
    pub hand: usize,
    pub board: usize,
    pub max_mana: i64,
    pub deck_size: usize,
    pub copies: usize,
    pub copies_by_rarity: HashMap<String, usize>,
    pub queue_steps: usize,
    pub champion_health: i64,
    pub start_hand: [i64; 2],
    pub coin: Option<String>,
    /// `start.first_player_draws`: the first player draws on their first turn (Classic: yes).
    pub first_player_draws: bool,
    /// `bot.trap`: what the bot counts for each of its own traps in play (a card in hand is 1; Classic: 0).
    pub bot_trap: f64,
    /// `bot.depth`: 2 = before ending its turn the bot also tries two actions in a row (Classic: 1).
    pub bot_depth: i64,
    pub fatigue: (bool, i64, i64),
    pub default_power: String,
    pub classes: Vec<Class>,
    pub tiers: HashMap<String, String>,
    pub no_rarity_tier: String,
    /// Rarities whose class cards a starter deck takes two of (`modes.constructed.starter_rarities`).
    pub starter_rarities: Vec<String>,
    pub starter_core: Vec<String>,
    pub own_and_neutral: bool,
    pub arena: Arena,
    pub missions: Vec<Mission>,
    /// Hook sets by card id or hook name ("ench:…").
    pub hooks: HashMap<String, HookSet>,
    pub lua: Option<LuaRules>,
}

fn i(v: &Value, k: &str, def: i64) -> i64 {
    v.get(k).and_then(Value::as_i64).unwrap_or(def)
}

fn s(v: &Value, k: &str) -> String {
    v.get(k).and_then(Value::as_str).unwrap_or("").to_string()
}

fn strs(v: &Value, k: &str) -> Vec<String> {
    v.get(k).and_then(Value::as_array).map_or(vec![], |a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
}

fn weights(v: &Value) -> Vec<(&'static str, i64)> {
    TIERS.iter().filter_map(|t| v.get(*t).and_then(Value::as_i64).map(|w| (*t, w))).collect()
}

impl Ruleset {
    /// The card (panics on an unknown id: check `has` at trust boundaries).
    pub fn card(&self, id: &str) -> &Card {
        self.cards.get(id).unwrap_or_else(|| panic!("unknown card {id}"))
    }

    pub fn has(&self, id: &str) -> bool {
        self.cards.contains_key(id)
    }

    /// The hooks of a card id or hook name (none if it has none).
    pub fn hooks(&self, id: &str) -> &HookSet {
        static EMPTY: OnceLock<HookSet> = OnceLock::new();
        self.hooks.get(id).unwrap_or_else(|| EMPTY.get_or_init(HookSet::default))
    }

    /// The champion of a playable class.
    pub fn champion(&self, class: &str) -> Option<&str> {
        self.classes.iter().find(|c| c.id == class && !c.champion.is_empty()).map(|c| c.champion.as_str())
    }

    /// The class whose champion this is.
    pub fn class_of_champion(&self, hero: &str) -> Option<&str> {
        self.classes.iter().find(|c| c.champion == hero && !hero.is_empty()).map(|c| c.id.as_str())
    }

    pub fn is_neutral(&self, class: &str) -> bool {
        self.classes.iter().any(|c| c.id == class && c.neutral)
    }

    /// The power a class champion starts with (None for other champions).
    pub fn class_power(&self, hero: &str) -> Option<&str> {
        self.class_of_champion(hero)?;
        let p = self.cards.get(hero)?.power.as_str();
        Some(if p.is_empty() { self.default_power.as_str() } else { p })
    }

    pub fn tier(&self, id: &str) -> &str {
        let r = &self.card(id).rarity;
        if r.is_empty() {
            return &self.no_rarity_tier;
        }
        self.tiers.get(r).map_or(self.no_rarity_tier.as_str(), String::as_str)
    }

    pub fn mission(&self, n: usize) -> Option<&Mission> {
        self.missions.iter().find(|m| m.id == n)
    }

    /// Builds a ruleset from the files of a pack (manifest, rules, cards, missions, scripts).
    pub fn from_files(files: &Files, builtin: bool) -> Result<Ruleset, String> {
        let get = |p: &str| files.get(p).ok_or(format!("{p} is missing"));
        let manifest = pack::strict_json(get("manifest.json")?, "manifest.json")?;
        if manifest.get("format") != Some(&json!(1)) {
            return Err("manifest.json: unknown format".into());
        }
        let rules = pack::strict_json(get("rules.json")?, "rules.json")?;
        let names = Names::new(rules.get("mechanics").and_then(Value::as_object).unwrap_or(&Map::new()))?;
        let champion_health = i(&rules["limits"], "champion_health", 30);
        let list: Vec<PackCard> = serde_json::from_value(pack::strict_json(get("cards.json")?, "cards.json")?)
            .map_err(|e| format!("cards.json: {e}"))?;
        let mut cards = HashMap::new();
        for c in list {
            let card = make_card(c, &names, champion_health)?;
            if cards.contains_key(&card.id) {
                return Err(format!("cards.json: {} twice", card.id));
            }
            cards.insert(card.id.clone(), card);
        }
        let lim = &rules["limits"];
        let start = &rules["start"];
        let fat = &rules["fatigue"];
        let modes = &rules["modes"];
        let ar = &modes["arena"];
        let constructed = &modes["constructed"];
        let sets_of = |m: &Value| strs(m, "sets");
        let pool = |sets: &[String]| -> Vec<String> {
            let mut v: Vec<String> =
                cards.values().filter(|c| c.collectible && sets.contains(&c.set)).map(|c| c.id.clone()).collect();
            v.sort();
            v
        };
        let classes = rules["classes"].as_array().map_or(vec![], |a| {
            a.iter()
                .map(|c| Class {
                    id: s(c, "id"),
                    champion: s(c, "champion"),
                    neutral: c.get("neutral") == Some(&json!(true)),
                    playable: c.get("playable") != Some(&json!(false)),
                })
                .collect()
        });
        let mut missions = vec![];
        for (p, b) in files.iter().filter(|(p, _)| p.starts_with("missions/") && p.ends_with(".json")) {
            missions.push(Mission::from_json(&pack::strict_json(b, p)?).map_err(|e| format!("{p}: {e}"))?);
        }
        missions.sort_by_key(|m| m.id);
        let mut rs = Ruleset {
            id: s(&manifest, "id"),
            version: s(&manifest, "version"),
            rules_hash: pack::rules_hash(files)?,
            data_hash: String::new(),
            builtin,
            collectible: pool(&sets_of(constructed)),
            arena_pool: pool(&sets_of(ar)),
            cards,
            names,
            hand: i(lim, "hand", 10) as usize,
            board: i(lim, "board", 7) as usize,
            max_mana: i(lim, "max_mana", 10),
            deck_size: i(lim, "deck_size", 30) as usize,
            copies: i(lim, "copies", 2) as usize,
            copies_by_rarity: lim
                .get("copies_by_rarity")
                .and_then(Value::as_object)
                .map_or(HashMap::new(), |m| m.iter().map(|(k, v)| (k.clone(), v.as_i64().unwrap_or(0) as usize)).collect()),
            queue_steps: i(lim, "queue_steps", 5000) as usize,
            champion_health,
            start_hand: start.get("hand").and_then(Value::as_array).map_or([3, 4], |h| {
                [h.first().and_then(Value::as_i64).unwrap_or(3), h.get(1).and_then(Value::as_i64).unwrap_or(4)]
            }),
            coin: start.get("coin").and_then(Value::as_str).map(String::from),
            first_player_draws: start.get("first_player_draws") != Some(&json!(false)),
            bot_trap: i(&rules["bot"], "trap", 0) as f64,
            bot_depth: i(&rules["bot"], "depth", 1),
            fatigue: (fat.get("enabled") != Some(&json!(false)), i(fat, "first", 1), i(fat, "step", 1)),
            default_power: s(&rules, "default_power"),
            classes,
            tiers: rules["rarities"]
                .as_array()
                .map_or(HashMap::new(), |a| a.iter().map(|r| (s(r, "id"), s(r, "tier"))).collect()),
            no_rarity_tier: rules.get("no_rarity_tier").and_then(Value::as_str).unwrap_or("common").to_string(),
            starter_rarities: strs(constructed, "starter_rarities"),
            starter_core: strs(constructed, "starter_core"),
            own_and_neutral: constructed.get("class_cards").and_then(Value::as_str).unwrap_or("own_and_neutral")
                == "own_and_neutral",
            arena: Arena {
                sets: sets_of(ar),
                champions_offered: i(ar, "champions_offered", 3) as usize,
                classes: strs(ar, "classes"),
                picks: i(ar, "picks", 30) as usize,
                offer: i(ar, "offer", 3) as usize,
                tier_weights: weights(&ar["tier_weights"]),
                special_picks: ar["special_picks"]
                    .as_array()
                    .map_or(vec![], |a| a.iter().filter_map(Value::as_i64).map(|n| (n - 1).max(0) as usize).collect()),
                special_tier_weights: weights(&ar["special_tier_weights"]),
                class_weight: i(ar, "class_weight", 3),
                neutral_weight: i(ar, "neutral_weight", 2),
            },
            missions,
            hooks: HashMap::new(),
            lua: None,
        };
        rs.data_hash = rs.rules_hash.clone();
        for c in rs.cards.values() {
            if !c.power.is_empty() && !rs.cards.contains_key(&c.power) {
                return Err(format!("{}: unknown power {}", c.id, c.power));
            }
        }
        let champions = rs.cards.values().any(|c| c.kind == "CHAMPION");
        if champions && rs.cards.get(&rs.default_power).is_none_or(|c| c.kind != "POWER") {
            return Err(format!("rules.json: default_power {:?} is not a POWER card", rs.default_power));
        }
        let scripts: Vec<(&String, &Vec<u8>)> = files.iter().filter(|(p, _)| p.starts_with("scripts/") && p.ends_with(".lua")).collect();
        let (lua, hooks) = crate::lua::build(&rs, &scripts)?;
        rs.lua = lua;
        if let Some(m) = rs.missions.iter().find(|m| !m.script.is_empty() && !hooks.contains_key(&m.script)) {
            return Err(format!("missions/{}.json: no hooks {}", m.id, m.script));
        }
        for c in rs.cards.values_mut() {
            if let Some(h) = hooks.get(&c.id) {
                c.hooks = h.clone();
            }
        }
        rs.hooks = hooks;
        Ok(rs)
    }
}

fn make_card(c: PackCard, names: &Names, champion_health: i64) -> Result<Card, String> {
    let kind = match c.kind.as_str() {
        "MINION" | "SPELL" | "WEAPON" | "CHAMPION" | "POWER" | "ENCHANTMENT" => c.kind.clone(),
        k => return Err(format!("{}: unknown type {k}", c.id)),
    };
    let mut tags = Map::new();
    let mut trap = false;
    for k in &c.keywords {
        let eid = names.engine_of.get(k).ok_or(format!("{}: keyword {k} is not in rules.json mechanics", c.id))?;
        if START_TAGS.contains(&eid.as_str()) {
            tags.insert(k.clone(), Value::Bool(true));
        }
        trap |= eid == "TRAP";
    }
    if let Some(n) = c.spell_power {
        tags.insert(names.spell_power.into(), json!(n));
    }
    if kind == "WEAPON" {
        tags.insert(names.durability.into(), json!(c.durability));
    }
    if kind == "CHAMPION" {
        tags.insert(names.armor.into(), json!(0));
    }
    Ok(Card {
        trap: trap && kind == "SPELL",
        health: if kind == "CHAMPION" && c.health == 0 { champion_health } else { c.health },
        id: c.id,
        kind,
        cost: c.cost,
        attack: c.attack,
        durability: c.durability,
        mana_lock: c.mana_lock,
        spell_power: c.spell_power,
        race: c.race,
        keywords: c.keywords,
        rarity: c.rarity,
        card_class: c.class,
        collectible: c.collectible,
        set: c.set,
        power: c.power,
        script: c.script,
        start_tags: tags,
        hooks: HookSet::default(),
    })
}

// --- the built-in Classic ruleset and the cache ----------------------------------------------

mod classic_files {
    include!(concat!(env!("OUT_DIR"), "/classic_files.rs"));
}

/// The rules files of the built-in Classic pack (build.rs: packs/classic, cards.json from data/cards.json).
pub fn classic_files() -> Files {
    classic_files::FILES.iter().map(|(p, b)| (p.to_string(), b.to_vec())).collect()
}

fn cache() -> &'static Mutex<BTreeMap<String, &'static Ruleset>> {
    static C: OnceLock<Mutex<BTreeMap<String, &'static Ruleset>>> = OnceLock::new();
    C.get_or_init(Default::default)
}

/// The built-in Classic ruleset (the default of every API call without `pack`).
pub fn classic() -> &'static Ruleset {
    static R: OnceLock<&'static Ruleset> = OnceLock::new();
    R.get_or_init(|| {
        let mut rs = Ruleset::from_files(&classic_files(), true).expect("the built-in Classic pack");
        rs.data_hash = classic_files::DATA_HASH.to_string();
        let rs: &'static Ruleset = Box::leak(Box::new(rs));
        cache().lock().unwrap().entry(rs.rules_hash.clone()).or_insert(rs);
        rs
    })
}

/// Loads a pack (its files) once per rules_hash.
/// ponytail: rulesets are leaked (games point into them); bounded by the distinct packs a
/// process loads. Use Arc<Ruleset> if a server ever loads an unbounded number of packs.
pub fn load(files: &Files) -> Result<&'static Ruleset, String> {
    classic();
    let h = pack::rules_hash(files)?;
    if let Some(r) = cache().lock().unwrap().get(&h) {
        return Ok(r);
    }
    let rs: &'static Ruleset = Box::leak(Box::new(Ruleset::from_files(files, false)?));
    Ok(*cache().lock().unwrap().entry(h).or_insert(rs))
}

/// A loaded ruleset by rules_hash.
pub fn get(rules_hash: &str) -> Option<&'static Ruleset> {
    classic();
    cache().lock().unwrap().get(rules_hash).copied()
}
