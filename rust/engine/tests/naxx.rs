//! The Naxxramas pack (packs/naxx, built by tools/pack.py from Classic's cards and the Curse of
//! Naxxramas): each new card's script in a small scenario, the engine mechanics it needs
//! (POISON, DOUBLE_ON_DEATH, DIED_TURN, g.graveyard, g.put_trap, g.resolve), and whole bot games
//! with every deck template. Needs python3 (skipped without it).

use classichs_engine::entity::{int, Id};
use classichs_engine::ruleset::{self, Ruleset};
use classichs_engine::{bot, pack, scenario, Game};
use serde_json::{json, Map, Value};
use std::path::PathBuf;
use std::sync::OnceLock;

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

/// The pack, built once (its recipe needs tools/pack.py); None without python3.
fn rs() -> Option<&'static Ruleset> {
    static R: OnceLock<Option<&'static Ruleset>> = OnceLock::new();
    *R.get_or_init(|| {
        let out = std::env::temp_dir().join(format!("naxx-{}.cardpack", std::process::id()));
        let build = std::process::Command::new("python3").current_dir(repo()).args(["tools/pack.py", "build", "packs/naxx", "-o"]).arg(&out).output().ok()?;
        assert!(build.status.success(), "pack.py build: {}", String::from_utf8_lossy(&build.stdout));
        let files = pack::read_zip(&std::fs::read(&out).unwrap()).unwrap();
        let _ = std::fs::remove_file(&out);
        Some(ruleset::load(&files).expect("the built pack loads"))
    })
}

const WISP: &str = "VAN_CS2_231";
const YETI: &str = "VAN_CS2_182";
const FIREBALL: &str = "VAN_CS2_029";
const FILL: [&str; 6] = [WISP, WISP, WISP, WISP, WISP, WISP];

struct T {
    g: Game,
}

/// A game in a scenario: p0 and p1 are merged over the defaults (10 mana each, decks of Wisps); p0's turn.
fn game(p0: Value, p1: Value) -> Option<T> {
    let rs = rs()?;
    let merge = |base: Value, over: Value| {
        let mut b = base.as_object().unwrap().clone();
        b.extend(over.as_object().unwrap().clone());
        Value::Object(b)
    };
    let d0 = json!({"hero": "HERO_08", "mana": 10, "max_mana": 10, "deck": FILL});
    let d1 = json!({"hero": "HERO_01", "mana": 10, "max_mana": 10, "deck": FILL});
    let sc = json!({"current": 0, "seed": 7, "players": [merge(d0, p0), merge(d1, p1)]});
    Some(T { g: scenario::build_in(rs, &sc).unwrap() })
}

impl T {
    fn nth(&self, p: usize, i: usize) -> Id {
        self.g.players[p].board[i]
    }
    fn on_board(&self, p: usize, card: &str) -> Id {
        *self.g.players[p].board.iter().find(|&&m| self.g.e(m).card_id == card).unwrap_or_else(|| panic!("{card} not on board {p}"))
    }
    fn cards(&self, p: usize) -> Vec<String> {
        self.g.players[p].board.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn hand(&self, p: usize) -> Vec<String> {
        self.g.players[p].hand.iter().map(|&m| self.g.e(m).card_id.to_string()).collect()
    }
    fn hero(&self, p: usize) -> Id {
        self.g.players[p].hero
    }
    fn stats(&self, e: Id) -> (i64, i64) {
        (self.g.e(e).atk(), self.g.e(e).health())
    }
    fn alive(&self, e: Id) -> bool {
        self.g.e(e).zone == "PLAY"
    }
    fn act(&mut self, what: &str, f: impl Fn(&Map<String, Value>) -> bool) -> &mut Self {
        let a = self.g.legal_actions().into_iter().find(|a| f(a)).unwrap_or_else(|| panic!("no legal action: {what}"));
        let r = self.g.apply(&Value::Object(a));
        assert!(r.ok, "{what}: {}", r.error);
        assert_eq!(self.g.script_error.get(), None, "{what}");
        self
    }
    fn hand_id(&self, card: &str) -> Id {
        let p = self.g.current;
        *self.g.players[p].hand.iter().find(|&&e| self.g.e(e).card_id == card).unwrap_or_else(|| panic!("{card} not in hand"))
    }
    fn play(&mut self, card: &str, target: Id) -> &mut Self {
        let e = self.hand_id(card);
        let last = self.g.players[self.g.current].board.len() as i64;
        self.act(&format!("play {card}"), |a| {
            a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target && (int(a.get("pos")) == -1 || int(a.get("pos")) == last)
        })
    }
    fn can_target(&self, card: &str, target: Id) -> bool {
        let e = self.hand_id(card);
        self.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e && int(a.get("target")) == target)
    }
    fn attack(&mut self, a: Id, d: Id) -> &mut Self {
        self.act("attack", |x| x["type"] == "attack" && int(x.get("attacker")) == a && int(x.get("defender")) == d)
    }
    fn end_turn(&mut self) -> &mut Self {
        self.act("end turn", |a| a["type"] == "end_turn")
    }
    fn cost(&self, card: &str) -> i64 {
        self.g.cost(self.hand_id(card))
    }
}

const NONE: Id = -1;

macro_rules! scene {
    ($p0:tt, $p1:tt) => {
        match game(json!($p0), json!($p1)) {
            Some(t) => t,
            None => {
                eprintln!("no python3: skipped");
                return;
            }
        }
    };
}

#[test]
fn release_versions() {
    let Some(rs) = rs() else { return };
    let c = |id: &str| rs.card(id);
    // Undertaker +1/+1 (nerfed to +1 Attack in January 2015): see `undertaker`; no Undead tribe in 2014
    assert_eq!(c("FP1_028").race, "");
    assert_eq!((c("FP1_002").race.as_str(), c("FP1_011").race.as_str(), c("FP1_010").race.as_str()), ("BEAST", "BEAST", "BEAST"));
    assert_eq!(c("FP1_002t").race, "");
    assert_eq!(c("FP1_012").health, 5, "Sludge Belcher 3/5 until 2023");
    assert_eq!(c("FP1_007t").cost, 3, "Nerubian costs 3 until 2016");
    assert_eq!(c("FP1_025").cost, 2, "Reincarnate costs 2 until 2023");
    assert!(rs.collectible.iter().filter(|id| id.starts_with("FP1_")).count() == 30);
}

#[test]
fn zombie_chow_heals_the_enemy_hero() {
    let mut t = scene!({"board": ["FP1_001"], "hand": [FIREBALL]}, {"damage": 10});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    assert_eq!(t.g.e(t.hero(1)).health(), 25);
}

#[test]
fn haunted_creeper_and_baron_rivendare() {
    let mut t = scene!({"board": ["FP1_002"], "hand": [FIREBALL]}, {});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    assert_eq!(t.cards(0), ["FP1_002t", "FP1_002t"]);
    // Rivendare: twice
    let mut t = scene!({"board": ["FP1_031", "FP1_002"], "hand": [FIREBALL]}, {});
    let m = t.nth(0, 1);
    t.play(FIREBALL, m);
    assert_eq!(t.cards(0).iter().filter(|c| *c == "FP1_002t").count(), 4);
    // Rivendare dying at the same time: once (Twisting Nether)
    let mut t = scene!({"board": ["FP1_031", "FP1_002"], "hand": ["VAN_EX1_312"]}, {});
    t.play("VAN_EX1_312", NONE);
    assert_eq!(t.cards(0), ["FP1_002t", "FP1_002t"]);
    // the enemy's Rivendare does nothing for my minions
    let mut t = scene!({"board": ["FP1_002"], "hand": [FIREBALL]}, {"board": ["FP1_031"]});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    assert_eq!(t.cards(0).len(), 2);
    // Ancestral Spirit (a Deathrattle since this patch) is doubled too
    let mut t = scene!({"board": ["FP1_031", YETI], "hand": ["VAN_CS2_038", "VAN_EX1_309"]}, {});
    let y = t.nth(0, 1);
    t.play("VAN_CS2_038", y);
    let y = t.nth(0, 1);
    t.play("VAN_EX1_309", y);
    assert_eq!(t.cards(0), ["FP1_031", YETI, YETI]);
}

#[test]
fn echoing_ooze_copies_itself_at_the_end_of_the_turn() {
    let mut t = scene!({"hand": ["FP1_003", "VAN_CS2_092"]}, {});
    t.play("FP1_003", NONE);
    let o = t.nth(0, 0);
    t.play("VAN_CS2_092", o);
    assert_eq!(t.cards(0).len(), 1);
    t.end_turn();
    assert_eq!(t.cards(0), ["FP1_003", "FP1_003"]);
    assert_eq!(t.stats(t.nth(0, 1)), (5, 6), "an exact copy");
    t.end_turn();
    assert_eq!(t.cards(0).len(), 2, "only once");
    // silenced before the end of the turn: no copy
    let mut t = scene!({"hand": ["FP1_003", "VAN_CS2_203"]}, {});
    t.play("FP1_003", NONE);
    let o = t.nth(0, 0);
    t.play("VAN_CS2_203", o);
    t.end_turn();
    assert_eq!(t.cards(0).len(), 2, "the Ooze and the Owl");
}

#[test]
fn mad_scientist_puts_a_secret_into_play() {
    let mut t = scene!({"board": ["FP1_004"], "hand": [FIREBALL], "deck": [WISP, "VAN_EX1_287", WISP]}, {});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    let s = &t.g.players[0].secrets;
    assert_eq!(s.len(), 1);
    assert_eq!(t.g.e(s[0]).card_id, "VAN_EX1_287");
    assert_eq!(t.g.players[0].deck.len(), 2);
    // the same Secret already in play: nothing
    let mut t = scene!({"board": ["FP1_004"], "hand": [FIREBALL], "deck": [WISP, "VAN_EX1_287"], "secrets": ["VAN_EX1_287"]}, {});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    assert_eq!((t.g.players[0].secrets.len(), t.g.players[0].deck.len()), (1, 2));
}

const FIVE_SECRETS: [&str; 5] = ["VAN_EX1_289", "VAN_EX1_294", "VAN_EX1_295", "VAN_EX1_594", "VAN_tt_010"];

#[test]
fn at_most_five_secrets() {
    // played from the hand: a sixth Secret is not playable, a fifth is
    let mut t = scene!({"hand": ["VAN_EX1_287"], "secrets": FIVE_SECRETS}, {});
    let e = t.hand_id("VAN_EX1_287");
    assert!(!t.g.legal_actions().iter().any(|a| a["type"] == "play" && int(a.get("entity")) == e), "a sixth Secret");
    let mut t = scene!({"hand": ["VAN_EX1_287"], "secrets": FIVE_SECRETS[..4]}, {});
    t.play("VAN_EX1_287", NONE);
    assert_eq!(t.g.players[0].secrets.len(), 5);
    // Mad Scientist with five: the Secret stays in the deck
    let mut t = scene!({"board": ["FP1_004"], "hand": [FIREBALL], "deck": [WISP, "VAN_EX1_287"], "secrets": FIVE_SECRETS}, {});
    let m = t.nth(0, 0);
    t.play(FIREBALL, m);
    assert_eq!((t.g.players[0].secrets.len(), t.g.players[0].deck.len()), (5, 2));
}

#[test]
fn shade_stoneskin_and_stealth() {
    let mut t = scene!({"board": ["FP1_005", {"card": "FP1_027", "damage": 3}]}, {"hand": [FIREBALL]});
    let (s, g) = (t.nth(0, 0), t.nth(0, 1));
    t.end_turn();
    assert!(!t.can_target(FIREBALL, s), "Stealth");
    assert_eq!(t.stats(g), (1, 1));
    t.end_turn();
    assert_eq!(t.stats(s), (3, 3));
    assert_eq!(t.stats(g), (1, 4));
}

#[test]
fn nerubian_egg_sludge_belcher_webspinner_dancing_swords() {
    let mut t = scene!({"board": ["FP1_007", "FP1_012", "FP1_011", "FP1_029"], "hand": ["VAN_EX1_312"]}, {});
    let before = t.g.players[1].hand.len();
    t.play("VAN_EX1_312", NONE);
    let mut left = t.cards(0);
    left.sort();
    assert_eq!(left, ["FP1_007t", "FP1_012t"]);
    assert_eq!(t.stats(t.on_board(0, "FP1_007t")), (4, 4));
    assert_eq!(t.stats(t.on_board(0, "FP1_012t")), (1, 2));
    assert!(t.g.e(t.on_board(0, "FP1_012t")).has("TAUNT"));
    let beast = t.g.players[0].hand.last().copied().unwrap();
    assert_eq!(t.g.e(beast).card.race, "BEAST");
    assert_eq!(t.g.players[1].hand.len(), before + 1, "Dancing Swords: the opponent draws");
}

#[test]
fn spectral_knight_cant_be_targeted_by_spells() {
    let t = scene!({"hand": [FIREBALL]}, {"board": ["FP1_008"]});
    assert!(!t.can_target(FIREBALL, t.nth(1, 0)));
}

#[test]
fn deathlord_gives_the_opponent_a_minion_from_their_deck() {
    let mut t = scene!({"hand": ["VAN_CS2_076"], "deck": [FIREBALL, YETI, FIREBALL]}, {"board": ["FP1_009"]});
    let m = t.nth(1, 0);
    t.play("VAN_CS2_076", m);
    assert_eq!(t.cards(0), [YETI], "the Deathlord's opponent gets it");
    assert_eq!(t.g.players[0].deck.len(), 2);
}

#[test]
fn maexxna_destroys_what_it_damages() {
    let mut t = scene!({"board": ["FP1_010"]}, {"board": ["VAN_CS2_186"]});
    let (m, golem) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(m, golem);
    assert!(!t.alive(golem));
    // silenced: no more
    let mut t = scene!({"board": [{"card": "FP1_010", "silenced": true}]}, {"board": ["VAN_CS2_186"]});
    let (m, golem) = (t.nth(0, 0), t.nth(1, 0));
    t.attack(m, golem);
    assert!(t.alive(golem));
}

#[test]
fn kel_thuzad_brings_back_friendly_minions_that_died_this_turn() {
    let mut t = scene!({"board": ["FP1_013", YETI], "hand": [FIREBALL, "VAN_CS2_076"]}, {"board": ["VAN_CS2_186"]});
    let y = t.nth(0, 1);
    t.play(FIREBALL, y);
    let golem = t.nth(1, 0);
    t.play("VAN_CS2_076", golem);
    assert_eq!(t.cards(0), ["FP1_013"]);
    t.end_turn();
    assert_eq!(t.cards(0), ["FP1_013", YETI]);
    assert!(t.cards(1).is_empty(), "not the enemy's");
    t.end_turn();
    assert_eq!(t.cards(0), ["FP1_013", YETI], "not again");
}

#[test]
fn feugen_and_stalagg_make_thaddius() {
    let mut t = scene!({"board": ["FP1_014"], "hand": [FIREBALL, "VAN_CS2_076"]}, {"board": ["FP1_015"]});
    let s = t.nth(0, 0);
    t.play(FIREBALL, s);
    assert!(t.cards(0).is_empty(), "Feugen has not died yet");
    let f = t.nth(1, 0);
    t.play("VAN_CS2_076", f);
    assert_eq!(t.cards(1), ["FP1_014t"], "the other side's Stalagg counts");
    assert_eq!(t.stats(t.nth(1, 0)), (11, 11));
}

#[test]
fn wailing_soul_silences_your_other_minions() {
    let mut t = scene!({"board": ["VAN_CS2_179"], "hand": ["FP1_016"]}, {"board": ["VAN_CS2_179"]});
    t.play("FP1_016", NONE);
    assert!(!t.g.e(t.nth(0, 0)).has("TAUNT"));
    assert!(t.g.e(t.nth(1, 0)).has("TAUNT"));
}

#[test]
fn nerubar_weblord_taxes_battlecries() {
    let t = scene!({"hand": ["VAN_CS2_189", WISP, FIREBALL]}, {"board": ["FP1_017"]});
    assert_eq!((t.cost("VAN_CS2_189"), t.cost(WISP), t.cost(FIREBALL)), (3, 0, 4));
}

#[test]
fn duplicate_and_avenge() {
    let mut t = scene!({"hand": [FIREBALL]}, {"board": [YETI], "secrets": ["FP1_018"], "hand": []});
    let y = t.nth(1, 0);
    t.play(FIREBALL, y);
    assert_eq!(t.hand(1), [YETI, YETI]);
    assert!(t.g.players[1].secrets.is_empty());
    let mut t = scene!({"hand": [FIREBALL, FIREBALL]}, {"board": [WISP, YETI], "secrets": ["FP1_020"]});
    let w = t.nth(1, 0);
    t.play(FIREBALL, w);
    assert_eq!(t.stats(t.on_board(1, YETI)), (7, 7));
    // alone: Avenge waits
    let mut t = scene!({"hand": [FIREBALL]}, {"board": [WISP], "secrets": ["FP1_020"]});
    let w = t.nth(1, 0);
    t.play(FIREBALL, w);
    assert_eq!(t.g.players[1].secrets.len(), 1);
}

#[test]
fn poison_seeds_deathrattles_first() {
    let mut t = scene!({"board": ["FP1_002", WISP], "hand": ["FP1_019"]}, {"board": [YETI]});
    t.play("FP1_019", NONE);
    assert_eq!(t.cards(0), ["FP1_002t", "FP1_002t", "FP1_019t", "FP1_019t"]);
    assert_eq!(t.cards(1), ["FP1_019t"]);
}

#[test]
fn reincarnate_returns_a_fresh_copy_after_its_deathrattle() {
    let mut t = scene!({"hand": ["FP1_025"]}, {"board": [{"card": "VAN_EX1_556", "damage": 2}]});
    let g = t.nth(1, 0);
    t.play("FP1_025", g);
    assert_eq!(t.cards(1), ["VAN_skele21", "VAN_EX1_556"]);
    assert_eq!(t.stats(t.nth(1, 1)), (2, 3));
}

#[test]
fn deaths_bite_unstable_ghoul_dark_cultist() {
    let mut t = scene!({"weapon": {"card": "FP1_021", "durability": 1}, "board": ["FP1_023", WISP]}, {"board": ["FP1_024", WISP]});
    let h = t.hero(0);
    let e = t.hero(1);
    let ghoul = t.nth(1, 0);
    // Taunt: the ghoul first
    t.attack(h, ghoul);
    // the axe broke (1 to all), the ghoul died (1 to all): both Wisps die, the Cultist takes 2
    assert!(t.g.players[0].weapon.is_none());
    assert!(t.cards(1).is_empty());
    assert_eq!(t.cards(0), ["FP1_023"]);
    assert_eq!(t.g.e(e).health(), 30);
}

#[test]
fn voidcaller_and_anubar_ambusher() {
    let mut t = scene!({"board": ["FP1_022"], "hand": [FIREBALL, "VAN_CS2_065"]}, {});
    let v = t.nth(0, 0);
    t.play(FIREBALL, v);
    assert_eq!(t.cards(0), ["VAN_CS2_065"], "the Demon came from the hand");
    assert!(t.hand(0).is_empty());
    // Ambusher: a random friendly minion back to the hand
    let mut t = scene!({"board": ["FP1_026", YETI], "hand": [FIREBALL]}, {});
    let a = t.nth(0, 0);
    t.play(FIREBALL, a);
    assert!(t.cards(0).is_empty());
    assert_eq!(t.hand(0), [YETI]);
}

#[test]
fn undertaker_grows_with_deathrattles() {
    let mut t = scene!({"board": ["FP1_028"], "hand": ["VAN_EX1_029", WISP]}, {});
    let u = t.nth(0, 0);
    t.play("VAN_EX1_029", NONE).play(WISP, NONE);
    assert_eq!(t.stats(u), (2, 3), "+1/+1 at the release");
}

#[test]
fn loatheb_taxes_the_next_turn_only() {
    let mut t = scene!({"hand": ["FP1_030"]}, {"hand": [FIREBALL]});
    t.play("FP1_030", NONE).end_turn();
    assert_eq!(t.cost(FIREBALL), 9);
    t.end_turn().end_turn();
    assert_eq!(t.cost(FIREBALL), 4);
}

#[test]
fn deck_templates_play_bot_games() {
    let Some(rs) = rs() else { return };
    let mut decks = vec![];
    let mut files: Vec<_> = std::fs::read_dir(repo().join("packs/naxx/decks")).unwrap().map(|f| f.unwrap().path()).collect();
    files.sort();
    for f in files {
        let d: Value = serde_json::from_str(&std::fs::read_to_string(f).unwrap()).unwrap();
        let cards: Vec<String> = d["cards"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(cards.len(), 30);
        decks.push((d["champion"].as_str().unwrap().to_string(), cards));
    }
    let mut over = 0;
    for (i, (c0, d0)) in decks.iter().enumerate() {
        let (c1, d1) = &decks[(i + 3) % decks.len()];
        for seed in 0..2 {
            let mut g = Game::new_in(rs, c0, d0, c1, d1, seed + 10 * i as i64, -1, true);
            let mut steps = 0;
            while !g.game_over && g.turn < 80 {
                let p = if g.phase == "MULLIGAN" { (0..2).find(|&p| !g.players[p].mulliganed).unwrap() } else { g.current };
                let a = bot::choose(&g, p).unwrap();
                assert!(g.apply(&Value::Object(a)).ok);
                assert_eq!(g.script_error.get(), None, "{c0} vs {c1}");
                steps += 1;
                assert!(steps < 4000);
            }
            over += g.game_over as usize;
        }
    }
    assert!(over >= decks.len(), "most games end");
}

/// Eaglehorn Bow as at the Naxxramas release (patch 1.1.0.6024, 2014-07-22): only a friendly
/// Secret revealed gives +1 Durability (in the June 2014 Classic pack, any Secret did).
#[test]
fn eaglehorn_bow_counts_only_friendly_secrets() {
    let mut t = scene!({"hero": "HERO_05", "weapon": "VAN_EX1_536"}, {"hero": "HERO_08", "secrets": ["VAN_EX1_289"]});
    let bow = t.g.players[0].weapon.expect("the bow is equipped");
    let (me, them) = (t.hero(0), t.hero(1));
    t.attack(me, them);
    assert_eq!(t.g.e(bow).tag("DURABILITY"), 1, "the enemy's Ice Barrier gives nothing: 2 - 1 (the attack)");
}
