//! The Neonfall pack (packs/neon): every card's script in a small scenario, whole
//! bot-vs-bot games without script errors, and the balance simulation.
//!
//! Balance run (release, all cores): games per pairing and seat order in NEON_SIM,
//! NEON_DECKS=starter|random|both (default both), NEON_PAIR=a,b (one matchup), NEON_ALL=1 (every
//! card's win rate when played), NEON_TRACE=1 (game logs). Results: packs/neon/DESIGN.md §9.
//!   NEON_SIM=1000 cargo test --release -p classichs-engine --test neon simulate -- --nocapture

use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{bot, pack, scenario, Game};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::OnceLock;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The pack, loaded from its source folder.
fn rs() -> &'static Ruleset {
    static R: OnceLock<&'static Ruleset> = OnceLock::new();
    R.get_or_init(|| ruleset::load(&pack::read_dir(&repo().join("packs/neon")).unwrap()).expect("packs/neon loads"))
}

const FILL: [&str; 6] = ["glitch", "glitch", "glitch", "glitch", "glitch", "glitch"];

/// A game in a scenario: p0 and p1 are merged over the defaults (10 mana for p0, decks of Glitches).
struct T {
    g: Game,
}

fn game(p0: Value, p1: Value) -> T {
    game_cur(0, p0, p1)
}

fn game_cur(cur: i64, p0: Value, p1: Value) -> T {
    let merge = |base: Value, over: Value| {
        let mut b = base.as_object().unwrap().clone();
        b.extend(over.as_object().unwrap().clone());
        Value::Object(b)
    };
    let d0 = json!({"hero": "iris_null", "mana": 10, "max_mana": 10, "deck": FILL});
    let d1 = json!({"hero": "director_vale", "mana": 10, "max_mana": 10, "deck": FILL});
    let sc = json!({"current": cur, "seed": 7, "players": [merge(d0, p0), merge(d1, p1)]});
    T { g: scenario::build_in(rs(), &sc).unwrap() }
}

impl T {
    fn on_board(&self, p: usize, card: &str) -> Id {
        self.board(p).into_iter().find(|&m| self.g.e(m).card_id == card).unwrap_or_else(|| panic!("{card} not on board {p}"))
    }
    fn nth(&self, p: usize, i: usize) -> Id {
        self.g.players[p].board[i]
    }
    fn board(&self, p: usize) -> Vec<Id> {
        self.g.players[p].board.clone()
    }
    fn cards(&self, p: usize) -> Vec<String> {
        self.board(p).iter().map(|&m| self.g.e(m).card_id.clone()).collect()
    }
    fn hand(&self, p: usize) -> Vec<String> {
        self.g.players[p].hand.iter().map(|&m| self.g.e(m).card_id.clone()).collect()
    }
    fn hero(&self, p: usize) -> Id {
        self.g.players[p].hero
    }
    fn hp(&self, e: Id) -> i64 {
        self.g.e(e).health()
    }
    fn atk(&self, e: Id) -> i64 {
        self.g.e(e).atk()
    }
    fn has(&self, e: Id, tag: &str) -> bool {
        self.g.e(e).has(tag)
    }
    fn armor(&self, p: usize) -> i64 {
        self.g.e(self.hero(p)).tag("ARMOR")
    }
    fn alive(&self, e: Id) -> bool {
        self.g.e(e).zone == "PLAY"
    }
    fn legal(&self) -> Vec<Map<String, Value>> {
        self.g.legal_actions()
    }
    /// Applies the first legal action that `f` accepts.
    fn act(&mut self, what: &str, f: impl Fn(&Map<String, Value>) -> bool) -> &mut Self {
        let a = self.legal().into_iter().find(|a| f(a)).unwrap_or_else(|| panic!("no legal action: {what}"));
        let r = self.g.apply(&Value::Object(a));
        assert!(r.ok, "{what}: {}", r.error);
        assert_eq!(self.g.script_error.get(), None, "{what}");
        self
    }
    fn hand_id(&self, card: &str) -> Id {
        let p = self.g.current;
        *self.g.players[p].hand.iter().find(|&&e| self.g.e(e).card_id == card).unwrap_or_else(|| panic!("{card} not in hand"))
    }
    fn play_c(&mut self, card: &str, target: Id, choice: i64) -> &mut Self {
        let e = self.hand_id(card);
        let last = self.g.players[self.g.current].board.len() as i64;
        self.act(&format!("play {card}"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target && int(a.get("choice")) == choice
                && (int(a.get("pos")) == -1 || int(a.get("pos")) == last)
        })
    }
    fn play(&mut self, card: &str, target: Id) -> &mut Self {
        self.play_c(card, target, -1)
    }
    fn can_target(&self, card: &str, target: Id) -> bool {
        let e = self.hand_id(card);
        self.legal().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target)
    }
    fn playable(&self, card: &str) -> bool {
        let e = self.hand_id(card);
        self.legal().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e)
    }
    fn power(&mut self, target: Id) -> &mut Self {
        self.act("power", |a| a["type"] == "hero_power" && int(a.get("target")) == target)
    }
    fn can_power(&self) -> bool {
        self.legal().iter().any(|a| a["type"] == "hero_power")
    }
    fn attack(&mut self, a: Id, d: Id) -> &mut Self {
        self.act("attack", |x| x["type"] == "attack" && int(x.get("attacker")) == a && int(x.get("defender")) == d)
    }
    fn attacks_of(&self, a: Id) -> usize {
        self.legal().iter().filter(|x| x["type"] == "attack" && int(x.get("attacker")) == a).count()
    }
    fn end_turn(&mut self) -> &mut Self {
        self.act("end turn", |a| a["type"] == "end_turn")
    }
}

const NONE: Id = -1;

#[test]
fn the_built_pack_loads_and_plays() {
    let out = std::env::temp_dir().join(format!("neon-{}.cardpack", std::process::id()));
    let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/neon", "-o"]).arg(&out).output();
    let Ok(build) = build else {
        eprintln!("no python3: skipped");
        return;
    };
    assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
    let built = ruleset::load(&pack::read_zip(&std::fs::read(&out).unwrap()).unwrap()).expect("the built pack loads");
    let _ = std::fs::remove_file(&out);
    assert_eq!(built.hooks.len(), rs().hooks.len());
    let decks = starter_decks();
    let mut g = Game::new_in(built, "iris_null", &decks["iris_null"], "mother_rust", &decks["mother_rust"], 5, 0, true);
    while !g.game_over && g.turn < 90 {
        let p = if g.phase == "MULLIGAN" { (0..2).find(|&p| !g.players[p].mulliganed).unwrap() } else { g.current };
        let a = choose(&g, p).unwrap();
        assert!(g.apply(&Value::Object(a)).ok);
        assert_eq!(g.script_error.get(), None);
    }
    assert!(g.game_over);
}

#[test]
fn every_scripted_card_has_hooks() {
    let rs = rs();
    let cards: Vec<Value> = serde_json::from_str(&std::fs::read_to_string(repo().join("packs/neon/cards.json")).unwrap()).unwrap();
    for c in &cards {
        let id = c["id"].as_str().unwrap();
        let has_fx = c.get("effects").is_some() || c.get("options").is_some();
        assert_eq!(c.get("script").is_some(), has_fx, "{id}: script iff effects");
        if c.get("script").is_some() {
            assert!(rs.hooks.contains_key(id), "{id}: no hooks loaded");
        }
    }
}

// --- Ghost --------------------------------------------------------------------------------------

#[test]
fn ghost_cards() {
    // Siphon: kills a 1/1 and draws; a 0/3 survives, no card
    let mut t = game(json!({}), json!({"board": ["scrap_drone", "glitch"]}));
    let drone = t.nth(1, 0);
    t.power(drone);
    assert!(!t.alive(drone));
    assert_eq!(t.hand(0).len(), 1);
    assert!(!t.can_power(), "once a turn");
    let mut t = game(json!({}), json!({"board": ["glitch"]}));
    let glitch = t.nth(1, 0);
    t.power(glitch);
    assert_eq!((t.hp(glitch), t.hand(0).len()), (2, 0));

    // Zero-Day: 1 + Jam; Chain: 3 + Jam
    let mut t = game(json!({"hand": ["zero_day"]}), json!({"board": ["knockoff_mech"]}));
    let m = t.nth(1, 0);
    t.play("zero_day", m);
    assert_eq!(t.hp(m), 3);
    assert!(t.has(m, "FROZEN"));
    let mut t = game(json!({"hand": ["zero_day"], "cards_played": 1}), json!({"board": ["knockoff_mech"]}));
    let m = t.nth(1, 0);
    t.play("zero_day", m);
    assert_eq!(t.hp(m), 1);
    assert!(t.has(m, "FROZEN"));

    // Ghostwalk: +1/+1 and Cloak; Chain draws
    let mut t = game(json!({"hand": ["ghostwalk"], "board": ["scrap_drone"]}), json!({}));
    let m = t.nth(0, 0);
    t.play("ghostwalk", m);
    assert_eq!((t.atk(m), t.hp(m), t.has(m, "STEALTH"), t.hand(0).len()), (2, 2, true, 0));
    let mut t = game(json!({"hand": ["ghostwalk"], "board": ["scrap_drone"], "cards_played": 1}), json!({}));
    let m = t.nth(0, 0);
    t.play("ghostwalk", m);
    assert_eq!((t.atk(m), t.has(m, "STEALTH"), t.hand(0).len()), (2, true, 1));

    // Cache Raid: 1 card; Chain: 2
    let mut t = game(json!({"hand": ["cache_raid"]}), json!({}));
    t.play("cache_raid", NONE);
    assert_eq!(t.hand(0).len(), 1);
    let mut t = game(json!({"hand": ["cache_raid"], "cards_played": 1}), json!({}));
    t.play("cache_raid", NONE);
    assert_eq!(t.hand(0).len(), 2);

    // Signal Leech: Bandwidth +1 and 1 face damage after each spell
    let mut t = game(json!({"hand": ["zero_day"], "board": ["signal_leech"]}), json!({"board": ["knockoff_mech"]}));
    let m = t.nth(1, 0);
    t.play("zero_day", m);
    assert_eq!(t.hp(m), 2, "1 + Bandwidth 1");
    assert_eq!(t.hp(t.hero(1)), 29);

    // Static Lock: the target and its neighbours, and a card
    let mut t = game(json!({"hand": ["static_lock"]}), json!({"board": ["glitch", "scrap_drone", "glitch", "knockoff_mech"]}));
    let b = t.board(1);
    t.play("static_lock", b[1]);
    assert!(t.has(b[0], "FROZEN") && t.has(b[1], "FROZEN") && t.has(b[2], "FROZEN") && !t.has(b[3], "FROZEN"));
    assert_eq!(t.hand(0).len(), 1);

    // Lattice Diver: Cloak; Chain returns an enemy minion of cost 3 or less
    let mut t = game(json!({"hand": ["lattice_diver"]}), json!({"board": ["knockoff_mech", "riot_sentinel"]}));
    t.play("lattice_diver", NONE);
    let d = t.on_board(0, "lattice_diver");
    assert!(t.has(d, "STEALTH"));
    assert_eq!(t.board(1).len(), 2, "no Chain: no bounce");
    let mut t = game(json!({"hand": ["lattice_diver"], "cards_played": 1}), json!({"board": ["knockoff_mech", "riot_sentinel"]}));
    let (cheap, big) = (t.nth(1, 0), t.nth(1, 1));
    assert!(!t.can_target("lattice_diver", big), "cost 4");
    t.play("lattice_diver", cheap);
    assert_eq!(t.cards(1), vec!["riot_sentinel"]);
    assert_eq!(t.hand(1), vec!["knockoff_mech"]);

    // Firmware Rot: Wipe, then 2 damage (Hardlight already gone)
    let mut t = game(json!({"hand": ["firmware_rot"]}), json!({"board": ["riot_sentinel"]}));
    let m = t.nth(1, 0);
    t.play("firmware_rot", m);
    assert_eq!(t.hp(m), 3);
    assert!(!t.has(m, "GUARD") && !t.has(m, "BARRIER"));

    // Corrupt: an enemy minion becomes a 0/3 Firewall Glitch
    let mut t = game(json!({"hand": ["corrupt"], "board": ["scrap_drone"]}), json!({"board": ["knockoff_mech"]}));
    assert!(!t.can_target("corrupt", t.nth(0, 0)), "enemy minions only");
    let m = t.nth(1, 0);
    t.play("corrupt", m);
    let g = t.nth(1, 0);
    assert_eq!(t.cards(1), vec!["glitch"]);
    assert_eq!((t.atk(g), t.hp(g), t.has(g, "GUARD")), (0, 3, true));

    // Packet Storm: 2 to enemy minions; Chain: 3
    let mut t = game(json!({"hand": ["packet_storm"], "board": ["scrap_drone"]}), json!({"board": ["knockoff_mech", "glitch"]}));
    let (a, b) = (t.nth(1, 0), t.nth(1, 1));
    t.play("packet_storm", NONE);
    assert_eq!((t.hp(a), t.hp(b), t.board(0).len()), (2, 1, 1));
    let mut t = game(json!({"hand": ["packet_storm"], "cards_played": 1}), json!({"board": ["knockoff_mech", "glitch"]}));
    let a = t.nth(1, 0);
    t.play("packet_storm", NONE);
    assert_eq!(t.hp(a), 1);
    assert_eq!(t.board(1).len(), 1);

    // Recursive Hound: Flatline: a Hound Shard in hand
    let mut t = game(json!({"hand": ["zero_day"], "board": [{"card": "recursive_hound", "damage": 2}]}), json!({}));
    let h = t.nth(0, 0);
    t.play("zero_day", h);
    assert!(!t.alive(h));
    assert_eq!(t.hand(0), vec!["hound_shard"]);

    // Root Access: steal a random enemy minion; they draw 2; not without enemy minions
    let t0 = game(json!({"hand": ["root_access"]}), json!({}));
    assert!(!t0.playable("root_access"));
    let mut t = game(json!({"hand": ["root_access"]}), json!({"board": ["knockoff_mech"]}));
    t.play("root_access", NONE);
    assert_eq!(t.cards(0), vec!["knockoff_mech"]);
    assert_eq!((t.board(1).len(), t.hand(1).len()), (0, 2));

    // Compiler Wyrm: spells cost 1 less
    let t = game(json!({"hand": ["cache_raid", "packet_storm", "knockoff_mech"], "board": ["compiler_wyrm"]}), json!({}));
    let costs: Vec<i64> = t.g.players[0].hand.iter().map(|&e| t.g.cost(e)).collect();
    assert_eq!(costs, vec![1, 3, 2]);

    // SABLE: Wipe all enemy minions
    let mut t = game(json!({"hand": ["sable"], "board": ["club_bouncer"]}), json!({"board": ["riot_sentinel", "lattice_phantom"]}));
    t.play("sable", NONE);
    let b = t.board(1);
    assert!(b.iter().all(|&m| t.g.e(m).silenced));
    assert!(!t.has(b[0], "GUARD") && t.has(t.nth(0, 0), "GUARD"), "only enemies");
}

// --- Chromehead ---------------------------------------------------------------------------------

#[test]
fn chrome_cards() {
    // Shakedown: 2 face damage, 1 Plating
    let mut t = game(json!({"hero": "mother_rust"}), json!({}));
    t.power(NONE);
    assert_eq!((t.hp(t.hero(1)), t.armor(0)), (28, 1));

    // Rust Shiv: Plating after each champion attack, the last one too
    let mut t = game(json!({"hand": ["rust_shiv"]}), json!({}));
    t.play("rust_shiv", NONE);
    let w = t.g.players[0].weapon.unwrap();
    assert_eq!((t.atk(w), t.g.e(w).tag("DURABILITY")), (1, 3));
    let mut t = game(json!({"weapon": {"card": "rust_shiv", "durability": 1}}), json!({}));
    let (me, foe) = (t.hero(0), t.hero(1));
    t.attack(me, foe);
    assert_eq!((t.hp(foe), t.armor(0), t.g.players[0].weapon), (29, 1, None));

    // Nitro Shot: +2 Attack, Overclock, Heat 1
    let mut t = game(json!({"hand": ["nitro_shot"], "board": [{"card": "scrap_drone", "exhausted": true}]}), json!({}));
    let m = t.nth(0, 0);
    assert_eq!(t.attacks_of(m), 0);
    t.play("nitro_shot", m);
    assert_eq!(t.atk(m), 3);
    assert!(t.attacks_of(m) > 0);
    assert_eq!(t.g.players[0].overload_owed, 1);

    // Stim Junkie: Dual-Core only while damaged
    let t = game(json!({"board": ["stim_junkie", {"card": "stim_junkie", "damage": 1}]}), json!({}));
    assert!(!t.has(t.nth(0, 0), "DOUBLE_ATTACK") && t.has(t.nth(0, 1), "DOUBLE_ATTACK"));

    // Hot Courier: Overclock, Heat 1 (keywords)
    let mut t = game(json!({"hand": ["hot_courier"]}), json!({}));
    t.play("hot_courier", NONE);
    assert!(t.attacks_of(t.nth(0, 0)) > 0);
    assert_eq!(t.g.players[0].overload_owed, 1);

    // Chrome Up: 3 Plating, +2 champion Attack this turn
    let mut t = game(json!({"hand": ["chrome_up"]}), json!({}));
    t.play("chrome_up", NONE);
    let me = t.hero(0);
    assert_eq!((t.armor(0), t.g.hero_atk(me)), (3, 2));
    t.end_turn();
    assert_eq!(t.atk(me), 0);

    // Fence the Goods: discard 1 at random, draw 3
    let mut t = game(json!({"hand": ["fence_the_goods", "knockoff_mech", "corrupt"]}), json!({}));
    t.play("fence_the_goods", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 4);
    assert_eq!(h.iter().filter(|c| *c == "glitch").count(), 3);

    // Back-Alley Bomb: 5 to a minion, 2 to yourself
    let mut t = game(json!({"hand": ["back_alley_bomb"]}), json!({"board": ["riot_sentinel", "maglev_juggernaut"]}));
    let m = t.nth(1, 0);
    assert!(!t.can_target("back_alley_bomb", t.nth(1, 1)), "Encrypted");
    t.play("back_alley_bomb", m);
    assert_eq!(t.hp(m), 5, "Hardlight took it");
    assert_eq!(t.hp(t.hero(0)), 28);

    // Chain Whip: the champion attacks twice; Heat 1
    let mut t = game(json!({"hand": ["chain_whip"]}), json!({}));
    t.play("chain_whip", NONE);
    let (me, foe) = (t.hero(0), t.hero(1));
    t.attack(me, foe).attack(me, foe);
    assert_eq!((t.hp(foe), t.g.players[0].overload_owed), (26, 1));

    // Scrap Bruiser: 1 to all other minions
    let mut t = game(json!({"hand": ["scrap_bruiser"], "board": ["scrap_drone"]}), json!({"board": ["glitch"]}));
    let g1 = t.nth(1, 0);
    t.play("scrap_bruiser", NONE);
    assert_eq!(t.cards(0), vec!["scrap_bruiser"]);
    assert_eq!(t.hp(g1), 2);
    assert_eq!(t.hp(t.nth(0, 0)), 3);

    // Pawn Shark: discard 1, +3/+3
    let mut t = game(json!({"hand": ["pawn_shark", "corrupt"]}), json!({}));
    t.play("pawn_shark", NONE);
    let s = t.nth(0, 0);
    assert_eq!((t.atk(s), t.hp(s), t.hand(0).len()), (6, 6, 0));

    // Hydraulic Maul: 5/2 and 5 Plating
    let mut t = game(json!({"hand": ["hydraulic_maul"]}), json!({}));
    t.play("hydraulic_maul", NONE);
    assert_eq!((t.armor(0), t.atk(t.g.players[0].weapon.unwrap())), (5, 5));

    // Ramraider: Overclock, Heat 2
    let mut t = game(json!({"hand": ["ramraider"]}), json!({}));
    t.play("ramraider", NONE);
    assert!(t.attacks_of(t.nth(0, 0)) > 0);
    assert_eq!(t.g.players[0].overload_owed, 2);

    // Vulka: Firewall; 2 Plating whenever it takes damage
    let mut t = game(json!({"hand": ["scrap_bruiser"], "board": ["vulka"]}), json!({}));
    assert!(t.has(t.nth(0, 0), "GUARD"));
    t.play("scrap_bruiser", NONE);
    assert_eq!(t.armor(0), 2);

    // Heat: the locked mana is gone next turn
    let mut t = game(json!({"hand": ["ramraider"], "max_mana": 9, "mana": 9}), json!({}));
    t.play("ramraider", NONE).end_turn().end_turn();
    assert_eq!(t.g.players[0].mana, 8, "10 crystals, 2 locked");
}

// --- Executive ----------------------------------------------------------------------------------

#[test]
fn exec_cards() {
    // Deploy: a 0/2 Firewall Sentry Drone; not with a full board
    let mut t = game(json!({"hero": "director_vale"}), json!({}));
    t.power(NONE);
    let s = t.nth(0, 0);
    assert_eq!((t.g.e(s).card_id.as_str(), t.atk(s), t.hp(s), t.has(s, "GUARD")), ("sentry_drone", 0, 2, true));
    let t = game(json!({"hero": "director_vale", "board": vec!["glitch"; 7]}), json!({}));
    assert!(!t.can_power());

    // Field Auditor: Hardlight on a friendly Drone only
    let mut t = game(json!({"hand": ["field_auditor"], "board": ["sentry_drone", "glitch"]}), json!({}));
    let (d, g1) = (t.nth(0, 0), t.nth(0, 1));
    assert!(!t.can_target("field_auditor", g1));
    t.play("field_auditor", d);
    assert!(t.has(d, "BARRIER"));

    // Patch Job: heal 3 and Firewall
    let mut t = game(json!({"hand": ["patch_job"], "board": [{"card": "knockoff_mech", "damage": 3}]}), json!({}));
    let m = t.nth(0, 0);
    t.play("patch_job", m);
    assert_eq!((t.hp(m), t.has(m, "GUARD")), (4, true));

    // Severance: destroy yours, its Health to a random enemy minion
    let mut t = game(json!({"hand": ["severance"], "board": ["riot_sentinel"]}), json!({"board": ["knockoff_mech"]}));
    let (mine, foe) = (t.nth(0, 0), t.nth(1, 0));
    t.play("severance", mine);
    assert!(!t.alive(mine) && !t.alive(foe));

    // Executive Decision: Fork: Hard Reset (Wipe) or Retention Bonus (+2 Health, Firewall)
    let mut t = game(json!({"hand": ["executive_decision", "executive_decision"], "board": ["scrap_drone"]}), json!({"board": ["riot_sentinel"]}));
    let (mine, foe) = (t.nth(0, 0), t.nth(1, 0));
    t.play_c("executive_decision", foe, 0);
    assert!(t.g.e(foe).silenced && !t.has(foe, "GUARD"));
    t.play_c("executive_decision", mine, 1);
    assert_eq!((t.atk(mine), t.hp(mine), t.has(mine, "GUARD")), (1, 3, true));

    // Protocol: Golden Parachute: a friendly minion dies on their turn: draw 2
    let mut t = game(json!({"hand": ["golden_parachute"]}), json!({}));
    t.play("golden_parachute", NONE);
    assert_eq!(t.g.players[0].secrets.len(), 1);
    let mut t = game_cur(1, json!({"board": ["scrap_drone"], "secrets": ["golden_parachute"]}), json!({"board": ["knockoff_mech"]}));
    let (mine, foe) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(foe, mine);
    assert_eq!((t.hand(0).len(), t.g.players[0].secrets.len()), (2, 0));

    // Protocol: Lockout: their next minion takes 1 and is Jammed
    let mut t = game_cur(1, json!({"secrets": ["lockout"]}), json!({"hand": ["knockoff_mech"]}));
    t.play("knockoff_mech", NONE);
    let m = t.nth(1, 0);
    assert_eq!((t.hp(m), t.has(m, "FROZEN"), t.g.players[0].secrets.len()), (3, true, 0));

    // Medic Drone: heal 2 to a damaged friendly character at the end of your turn
    let mut t = game(json!({"damage": 5, "board": ["medic_drone"]}), json!({}));
    t.end_turn();
    assert_eq!(t.hp(t.hero(0)), 27);

    // Protocol: Asset Seizure: a copy of a dead enemy minion
    let mut t = game_cur(1, json!({"board": ["knockoff_mech"], "secrets": ["asset_seizure"]}), json!({"board": ["scrap_drone"]}));
    let (mine, foe) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(foe, mine);
    assert_eq!(t.hand(0), vec!["scrap_drone"]);

    // Grid Overseer: Drones +1 Attack
    let t = game(json!({"board": ["sentry_drone", "scrap_drone", "glitch", "grid_overseer"]}), json!({"board": ["scrap_drone"]}));
    let atks: Vec<i64> = t.board(0).iter().map(|&m| t.atk(m)).collect();
    assert_eq!(atks, vec![1, 2, 0, 2]);
    assert_eq!(t.atk(t.nth(1, 0)), 1, "not the enemy's");

    // Riot Sentinel: Firewall, Hardlight
    let t = game(json!({"board": ["riot_sentinel"]}), json!({}));
    assert!(t.has(t.nth(0, 0), "GUARD") && t.has(t.nth(0, 0), "BARRIER"));

    // Vat-Grown Clone: a copy, with its buffs
    let mut t = game(json!({"hand": ["vat_clone"]}), json!({}));
    t.play("vat_clone", NONE);
    assert_eq!(t.cards(0), vec!["vat_clone", "vat_clone"]);
    assert_eq!((t.atk(t.nth(0, 1)), t.hp(t.nth(0, 1))), (3, 3));

    // Enforcement Mech: Flatline: two Sentry Drones
    let mut t = game(json!({"hand": ["back_alley_bomb"], "board": ["glitch", "enforcement_mech", "glitch"]}), json!({}));
    let m = t.nth(0, 1);
    assert!(t.has(m, "GUARD"));
    t.play("back_alley_bomb", m);
    assert_eq!(t.cards(0), vec!["glitch", "sentry_drone", "sentry_drone", "glitch"]);

    // ARCHON: end of turn: a Sentry Drone, other Drones +1 Attack
    let mut t = game(json!({"board": ["archon", "sentry_drone", "glitch"]}), json!({}));
    t.end_turn();
    assert_eq!(t.cards(0), vec!["archon", "sentry_drone", "sentry_drone", "glitch"]);
    let atks: Vec<i64> = t.board(0).iter().map(|&m| t.atk(m)).collect();
    assert_eq!(atks, vec![6, 1, 1, 0]);
}

// --- Neutral and tokens ---------------------------------------------------------------------------

#[test]
fn neutral_cards() {
    // Jumpstart: 1 Mana this turn
    let mut t = game(json!({"hand": ["jumpstart"], "mana": 3}), json!({}));
    t.play("jumpstart", NONE);
    assert_eq!(t.g.players[0].mana, 4);

    // Signal Jammer: Jam an enemy minion
    let mut t = game(json!({"hand": ["signal_jammer"]}), json!({"board": ["knockoff_mech"]}));
    let m = t.nth(1, 0);
    t.play("signal_jammer", m);
    assert!(t.has(m, "FROZEN"));

    // Courier Drone: Flatline: a Jumpstart
    let mut t = game(json!({"hand": ["zero_day"], "board": ["courier_drone"]}), json!({}));
    t.play("zero_day", t.nth(0, 0));
    assert_eq!(t.hand(0), vec!["jumpstart"]);

    // Neon Moth: Cloak, Dual-Core
    let t = game(json!({"board": ["neon_moth"]}), json!({}));
    assert!(t.has(t.nth(0, 0), "STEALTH") && t.has(t.nth(0, 0), "DOUBLE_ATTACK"));

    // Holo Busker: another random friendly minion +1 Attack at the end of your turn
    let mut t = game(json!({"board": ["holo_busker", "scrap_drone"]}), json!({}));
    t.end_turn();
    assert_eq!((t.atk(t.nth(0, 0)), t.atk(t.nth(0, 1))), (1, 2));

    // Chrome Stray: Flatline: 2 to a random enemy minion
    let mut t = game(json!({"hand": ["zero_day"], "board": [{"card": "chrome_stray", "damage": 1}]}), json!({"board": ["glitch"]}));
    t.play("zero_day", t.nth(0, 0));
    assert_eq!(t.hp(t.nth(1, 0)), 1);

    // Knockoff Mech: 3/4, Heat 1
    let mut t = game(json!({"hand": ["knockoff_mech"]}), json!({}));
    t.play("knockoff_mech", NONE);
    assert_eq!((t.atk(t.nth(0, 0)), t.hp(t.nth(0, 0)), t.g.players[0].overload_owed), (3, 4, 1));

    // Club Bouncer: Flatline: Firewall to a random friendly minion
    let mut t = game(json!({"hand": ["zero_day"], "board": [{"card": "club_bouncer", "damage": 2}, "scrap_drone"]}), json!({}));
    let b = t.nth(0, 0);
    assert!(t.has(b, "GUARD"));
    t.play("zero_day", b);
    assert!(t.has(t.on_board(0, "scrap_drone"), "GUARD"));

    // Night Market Cook: heal 3 to all friendly characters
    let mut t = game(json!({"damage": 5, "hand": ["night_market_cook"], "board": [{"card": "knockoff_mech", "damage": 2}]}),
        json!({"damage": 5}));
    t.play("night_market_cook", NONE);
    assert_eq!((t.hp(t.hero(0)), t.hp(t.nth(0, 0)), t.hp(t.hero(1))), (28, 4, 25));

    // Glasshound Runner: Hardlight, Cloak
    let t = game(json!({"board": ["glasshound_runner"]}), json!({}));
    assert!(t.has(t.nth(0, 0), "BARRIER") && t.has(t.nth(0, 0), "STEALTH"));

    // Bit-Rot Daemon: 1 to a random enemy at the start of your turn
    let mut t = game_cur(1, json!({"board": ["bitrot_daemon"]}), json!({}));
    t.end_turn();
    assert_eq!(t.hp(t.hero(1)), 29);

    // Black Market Broker: a random class card
    let mut t = game(json!({"hand": ["black_market_broker"]}), json!({}));
    t.play("black_market_broker", NONE);
    let h = t.hand(0);
    assert_eq!(h.len(), 1);
    let c = rs().card(&h[0]);
    assert!(c.collectible && c.card_class != "NEUTRAL", "{}", h[0]);

    // Rooftop Sniper: Cloak, 2 damage to a minion
    let mut t = game(json!({"hand": ["rooftop_sniper"]}), json!({"board": ["knockoff_mech"]}));
    let m = t.nth(1, 0);
    t.play("rooftop_sniper", m);
    assert_eq!(t.hp(m), 2);
    assert!(t.has(t.nth(0, 0), "STEALTH"));

    // Lattice Phantom: Jam a random enemy minion at the end of your turn
    let mut t = game(json!({"board": ["lattice_phantom"]}), json!({"board": ["knockoff_mech"]}));
    assert!(t.has(t.nth(0, 0), "STEALTH"));
    t.end_turn();
    let m = t.nth(1, 0);
    assert!(t.has(m, "FROZEN"));
    assert_eq!(t.attacks_of(m), 0);

    // Swarm Wrangler: two 1/1 Scrap Drones
    let mut t = game(json!({"hand": ["swarm_wrangler"]}), json!({}));
    t.play("swarm_wrangler", NONE);
    assert_eq!(t.cards(0), vec!["swarm_wrangler", "scrap_drone", "scrap_drone"]);
    assert_eq!((t.atk(t.nth(0, 1)), t.hp(t.nth(0, 1))), (1, 1));

    // Rapid-Response Medic: Hardlight, heal 4
    let mut t = game(json!({"damage": 5, "hand": ["rapid_response_medic"]}), json!({}));
    let me = t.hero(0);
    t.play("rapid_response_medic", me);
    assert_eq!(t.hp(me), 29);
    assert!(t.has(t.nth(0, 0), "BARRIER"));

    // Repo Mech: Firewall, destroys the enemy weapon
    let mut t = game(json!({"hand": ["repo_mech"]}), json!({"weapon": "rust_shiv"}));
    t.play("repo_mech", NONE);
    assert_eq!(t.g.players[1].weapon, None);
    assert!(t.has(t.nth(0, 0), "GUARD"));

    // Billboard Leviathan: 1 to all enemy minions at the end of your turn
    let mut t = game(json!({"board": ["billboard_leviathan"]}), json!({"board": ["glitch", "scrap_drone"]}));
    t.end_turn();
    assert_eq!(t.cards(1), vec!["glitch"]);
    assert_eq!(t.hp(t.nth(1, 0)), 2);

    // Maglev Juggernaut: Encrypted
    let t = game(json!({"hand": ["zero_day"]}), json!({"board": ["maglev_juggernaut"]}));
    assert!(!t.can_target("zero_day", t.nth(1, 0)));

    // Varga: swap Attack and Health of all other minions; 0-Attack walls die
    let mut t = game(json!({"hand": ["varga"], "board": ["knockoff_mech"]}), json!({"board": ["glitch"]}));
    t.play("varga", NONE);
    let k = t.nth(0, 0);
    assert_eq!((t.atk(k), t.hp(k)), (4, 3));
    assert!(t.board(1).is_empty());
    let v = t.on_board(0, "varga");
    assert_eq!((t.atk(v), t.hp(v)), (4, 6));

    // Seawall Colossus: Firewall; Redline: Dual-Core
    let t = game(json!({"board": ["seawall_colossus", {"card": "seawall_colossus", "damage": 1}]}), json!({}));
    assert!(t.has(t.nth(0, 0), "GUARD") && !t.has(t.nth(0, 0), "DOUBLE_ATTACK") && t.has(t.nth(0, 1), "DOUBLE_ATTACK"));

    // The Last Free Mind: a random enemy minion becomes a Glitch at the end of your turn
    let mut t = game(json!({"board": ["last_free_mind"]}), json!({"board": ["knockoff_mech"]}));
    assert!(t.has(t.nth(0, 0), "SPELLPROOF"));
    t.end_turn();
    assert_eq!(t.cards(1), vec!["glitch"]);

    // Hound Shard: 2/1
    let t = game(json!({"board": ["hound_shard"]}), json!({}));
    assert_eq!((t.atk(t.nth(0, 0)), t.hp(t.nth(0, 0))), (2, 1));
}

// --- whole games ----------------------------------------------------------------------------------

fn starter_decks() -> BTreeMap<String, Vec<String>> {
    let mut out = BTreeMap::new();
    for f in std::fs::read_dir(repo().join("packs/neon/decks")).unwrap() {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(f.unwrap().path()).unwrap()).unwrap();
        let cards = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        out.insert(d["champion"].as_str().unwrap().to_string(), cards);
    }
    out
}

/// A random legal deck for a champion from its class and neutral collectible cards.
fn random_deck(champion: &str, seed: u64) -> Vec<String> {
    let rs = rs();
    let class = &rs.card(champion).card_class;
    let mut pool = vec![];
    for id in &rs.collectible {
        let c = rs.card(id);
        if c.kind != "HERO" && (c.card_class == *class || c.card_class == "NEUTRAL") {
            for _ in 0..(if c.rarity == "LEGENDARY" { 1 } else { 2 }) {
                pool.push(id.clone());
            }
        }
    }
    let mut x = seed.wrapping_mul(0x9E3779B97F4A7C15) | 1;
    let mut deck = vec![];
    while deck.len() < 30 {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        deck.push(pool.swap_remove((x % pool.len() as u64) as usize));
    }
    deck
}

struct Outcome {
    winner: i64,
    turns: i64,
    played: [Vec<String>; 2],
}

/// The engine's greedy bot, except that a Protocol it can afford is played instead of ending the
/// turn (the bot's value counts a card in hand but not a trap in play, so it never plays one).
fn choose(g: &Game, p: usize) -> Option<Map<String, Value>> {
    let a = bot::choose(g, p)?;
    if a["type"] != "end_turn" {
        return Some(a);
    }
    let trap = g.legal_actions().into_iter().find(|x| x["type"] == "play" && g.e(int(x.get("entity"))).card.trap);
    Some(trap.unwrap_or(a))
}

/// A bot-vs-bot game; panics on a script error.
fn play_game(c0: &str, d0: &[String], c1: &str, d1: &[String], seed: i64, first: i64) -> Outcome {
    let mut g = Game::new_in(rs(), c0, d0, c1, d1, seed, first, true);
    let mut played: [Vec<String>; 2] = Default::default();
    let mut steps = 0;
    let trace = std::env::var("NEON_TRACE").is_ok();
    while !g.game_over && g.turn < 90 {
        let p = if g.phase == "MULLIGAN" { (0..2).find(|&p| !g.players[p].mulliganed).unwrap() } else { g.current };
        let Some(a) = choose(&g, p) else { break };
        if a["type"] == "play" {
            played[p].push(g.e(int(a.get("entity"))).card_id.clone());
        }
        if trace {
            let name = |k: &str| a.get(k).map(|v| int(Some(v))).filter(|&x| x >= 0).map(|x| g.e(x).card_id.clone()).unwrap_or_default();
            match a["type"].as_str().unwrap() {
                "end_turn" => {
                    let side = |q: usize| {
                        let b: Vec<String> = g.players[q].board.iter().map(|&m| format!("{}{}/{}", g.e(m).card_id, g.e(m).atk(), g.e(m).health())).collect();
                        format!("hp {} arm {} hand {} [{}]", g.e(g.players[q].hero).health(), g.e(g.players[q].hero).tag("ARMOR"), g.players[q].hand.len(), b.join(" "))
                    };
                    println!("  end turn {}: P{p} {} | P{} {}", g.turn, side(p), 1 - p, side(1 - p));
                }
                "play" => println!("T{} P{p} play {} -> {}", g.turn, name("entity"), name("target")),
                "attack" => println!("T{} P{p} attack {} -> {}", g.turn, name("attacker"), name("defender")),
                t => println!("T{} P{p} {t} {}", g.turn, name("target")),
            }
        }
        let r = g.apply(&Value::Object(a));
        assert!(r.ok, "{}", r.error);
        if let Some(e) = g.script_error.get() {
            panic!("script error ({c0} vs {c1}, seed {seed}): {e}");
        }
        steps += 1;
        assert!(steps < 5000, "runaway game");
    }
    Outcome { winner: if g.game_over { g.winner } else { -1 }, turns: g.turn, played }
}

#[test]
fn bot_games_run_clean() {
    let decks = starter_decks();
    let champs: Vec<&String> = decks.keys().collect();
    let mut seed = 1;
    for a in &champs {
        for b in &champs {
            for _ in 0..2 {
                let o = play_game(a, &decks[*a], b, &decks[*b], seed, seed % 2);
                assert!(o.winner >= -1 && o.turns > 1);
                seed += 1;
            }
        }
    }
    for (i, a) in champs.iter().enumerate() {
        let b = champs[(i + 1) % champs.len()];
        play_game(a, &random_deck(a, i as u64 + 11), b, &random_deck(b, i as u64 + 77), 100 + i as i64, 0);
    }
}

// --- balance simulation (NEON_SIM games per pairing and seat order) -------------------------------

#[derive(Default, Clone)]
struct Tally {
    games: u64,
    wins: u64,
    draws: u64,
}

impl Tally {
    fn add(&mut self, won: bool, draw: bool) {
        self.games += 1;
        self.wins += won as u64;
        self.draws += draw as u64;
    }
    /// Win rate, a draw counting half, in percent.
    fn rate(&self) -> f64 {
        if self.games == 0 { 0.0 } else { 100.0 * (self.wins as f64 + 0.5 * self.draws as f64) / self.games as f64 }
    }
}

#[test]
fn simulate() {
    let Some(n) = std::env::var("NEON_SIM").ok().and_then(|s| s.parse::<u64>().ok()) else {
        eprintln!("NEON_SIM not set: skipped");
        return;
    };
    let mode = std::env::var("NEON_DECKS").unwrap_or_else(|_| "both".into());
    let decks = starter_decks();
    let champs: Vec<String> = decks.keys().cloned().collect();
    for random in [false, true] {
        if (random && mode == "starter") || (!random && mode == "random") {
            continue;
        }
        // jobs: (a, b, first, seed) for every unordered pair (no mirrors), both seat orders
        let mut jobs = vec![];
        for (i, a) in champs.iter().enumerate() {
            for b in &champs[i + 1..] {
                // NEON_PAIR=a,b: only that matchup
                if std::env::var("NEON_PAIR").is_ok_and(|f| !(f.contains(a.as_str()) && f.contains(b.as_str()))) {
                    continue;
                }
                for first in 0..2 {
                    for k in 0..n {
                        jobs.push((a.clone(), b.clone(), first, k as i64 * 2 + first + 1));
                    }
                }
            }
        }
        let threads = std::thread::available_parallelism().map_or(4, |x| x.get());
        let chunks: Vec<Vec<_>> = (0..threads).map(|t| jobs.iter().skip(t).step_by(threads).cloned().collect()).collect();
        let results: Vec<(String, String, i64, Outcome)> = std::thread::scope(|s| {
            let hs: Vec<_> = chunks
                .iter()
                .map(|chunk| {
                    let decks = &decks;
                    s.spawn(move || {
                        chunk
                            .iter()
                            .map(|(a, b, first, seed)| {
                                let (da, db) = if random {
                                    (random_deck(a, *seed as u64 * 31 + 1), random_deck(b, *seed as u64 * 31 + 2))
                                } else {
                                    (decks[a].clone(), decks[b].clone())
                                };
                                (a.clone(), b.clone(), *first, play_game(a, &da, b, &db, *seed, *first))
                            })
                            .collect::<Vec<_>>()
                    })
                })
                .collect();
            hs.into_iter().flat_map(|h| h.join().unwrap()).collect()
        });
        let mut champ: BTreeMap<String, Tally> = BTreeMap::new();
        let mut matchup: BTreeMap<(String, String), Tally> = BTreeMap::new();
        let mut first_t = Tally::default();
        let mut cards: BTreeMap<String, Tally> = BTreeMap::new();
        let (mut turns, mut draws) = (0i64, 0u64);
        for (a, b, first, o) in &results {
            let draw = o.winner < 0;
            draws += draw as u64;
            turns += o.turns;
            champ.entry(a.clone()).or_default().add(o.winner == 0, draw);
            champ.entry(b.clone()).or_default().add(o.winner == 1, draw);
            matchup.entry((a.clone(), b.clone())).or_default().add(o.winner == 0, draw);
            first_t.add(o.winner == *first, draw);
            for p in 0..2 {
                let mut seen: Vec<&String> = o.played[p].iter().collect();
                seen.sort();
                seen.dedup();
                for c in seen {
                    cards.entry(c.clone()).or_default().add(o.winner == p as i64, draw);
                }
            }
        }
        println!("\n=== {} decks: {} games ({} per pairing and seat order) ===", if random { "random" } else { "starter" }, results.len(), n);
        println!("average game length: {:.1} turns; draws {}; first player wins {:.1}%", turns as f64 / results.len() as f64, draws,
            first_t.rate());
        for (c, t) in &champ {
            println!("champion {c:14} {:5.1}%  ({} games)", t.rate(), t.games);
        }
        for ((a, b), t) in &matchup {
            println!("matchup {a:14} vs {b:14} {:5.1}%", t.rate());
        }
        let mut by: Vec<(&String, &Tally)> = cards.iter().filter(|(_, t)| t.games >= 50).collect();
        by.sort_by(|x, y| y.1.rate().partial_cmp(&x.1.rate()).unwrap());
        println!("win rate when played (>= 50 games), top and bottom 8:");
        for (c, t) in by.iter().take(8).chain(by.iter().rev().take(8).rev()) {
            println!("  {c:22} {:5.1}%  ({} games)", t.rate(), t.games);
        }
        if std::env::var("NEON_ALL").is_ok() {
            for (c, t) in &cards {
                println!("  all {c:22} {:5.1}%  ({} games)", t.rate(), t.games);
            }
        }
    }
}
