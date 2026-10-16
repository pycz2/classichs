//! Pure rules: 2014 ranked stars and seasons, Elo, matchmaking windows, dates.
//! See docs/superpowers/specs/2026-10-15-ranked-research.md.

use serde::Serialize;
use serde_json::Value;

/// Rank N..=1 of the pack's ladder; 0 = Legend.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct Rank {
    pub rank: i64,
    pub stars: i64,
    pub streak: i64,
}

pub const LEGEND: i64 = 0;

/// One rank of a ladder (rules.json `ranked.ranks[]`, docs/packs/rules.md).
#[derive(Clone, Debug, PartialEq)]
pub struct Step {
    pub rank: i64,
    pub stars: i64,
    pub loses_stars: bool,
    pub floor: bool,
    pub streak_bonus: bool,
}

/// A pack's ranked ladder (rules.json `ranked`): the 2014 one in Classic.
#[derive(Clone, Debug, PartialEq)]
pub struct Ladder {
    pub start: Rank,
    /// From the lowest rank (the highest number) up to rank 1.
    pub ranks: Vec<Step>,
    pub streak_wins: i64,
    pub bonus_stars: i64,
    /// A Legend rank after the top one.
    pub legend: bool,
    pub reset_to: i64,
    pub per_rank_above: i64,
    pub legend_counts_as: i64,
}

impl Ladder {
    /// From rules.json's `ranked` (None: the pack has no ladder, or a malformed one).
    pub fn from_rules(r: &Value) -> Option<Ladder> {
        let i = |v: &Value, k: &str, d: i64| v.get(k).and_then(Value::as_i64).unwrap_or(d);
        let b = |v: &Value, k: &str, d: bool| v.get(k).and_then(Value::as_bool).unwrap_or(d);
        let ranks: Vec<Step> = r.get("ranks")?.as_array()?.iter()
            .map(|s| Some(Step { rank: s.get("rank")?.as_i64()?, stars: s.get("stars")?.as_i64()?.clamp(1, 100),
                loses_stars: b(s, "loses_stars", true), floor: b(s, "floor", false), streak_bonus: b(s, "streak_bonus", false) }))
            .collect::<Option<_>>()?;
        if ranks.is_empty() || ranks.len() > 200 || ranks.iter().any(|s| s.rank <= 0) {
            return None;
        }
        let low = ranks[0].rank;
        let start = r.get("start").unwrap_or(&Value::Null);
        let streak = r.get("streak").unwrap_or(&Value::Null);
        let reset = r.pointer("/season/reset").unwrap_or(&Value::Null);
        Some(Ladder {
            start: Rank { rank: i(start, "rank", low), stars: i(start, "stars", 0), streak: 0 },
            streak_wins: i(streak, "wins", 0),
            bonus_stars: i(streak, "bonus_stars", 0).clamp(0, 10),
            legend: r.get("legend").is_some_and(|l| l.is_object()),
            reset_to: i(reset, "to_rank", low),
            per_rank_above: i(reset, "stars_per_rank_above", 1),
            legend_counts_as: i(reset, "legend_counts_as", 0),
            ranks,
        })
    }

    /// The 2014 ladder (the built-in Classic pack's).
    pub fn classic() -> Ladder {
        let rules: Value = serde_json::from_slice(&classichs_engine::ruleset::classic_files()["rules.json"]).expect("classic rules.json");
        Ladder::from_rules(&rules["ranked"]).expect("the classic ladder")
    }

    fn index(&self, rank: i64) -> Option<usize> {
        self.ranks.iter().position(|s| s.rank == rank)
    }

    /// Stars a rank holds.
    pub fn max_stars(&self, rank: i64) -> i64 {
        self.index(rank).map_or(1, |i| self.ranks[i].stars)
    }

    /// Stars from the bottom to Legend (the matchmaking level of a Legend).
    pub fn legend_level(&self) -> i64 {
        self.ranks.iter().map(|s| s.stars).sum()
    }
}

impl Rank {
    pub fn legend(&self) -> bool {
        self.rank == LEGEND
    }

    /// Stars counted from the bottom of the ladder (Legend: all of them): the ranked matchmaking key.
    pub fn level(&self, l: &Ladder) -> i64 {
        match l.index(self.rank) {
            _ if self.legend() => l.legend_level(),
            Some(i) => l.ranks[..i].iter().map(|s| s.stars).sum::<i64>() + self.stars,
            None => 0,
        }
    }

    /// The rank `stars` stars above `from` (full ranks stay full: 2 stars → 25 at 2/2).
    pub fn climb(l: &Ladder, from: Rank, stars: i64) -> Rank {
        let mut r = from;
        for _ in 0..stars.clamp(0, 10_000) {
            r.add_star(l);
        }
        r
    }

    fn add_star(&mut self, l: &Ladder) {
        let Some(i) = l.index(self.rank) else { return };
        if self.stars < l.ranks[i].stars {
            self.stars += 1;
        } else if i + 1 < l.ranks.len() {
            self.rank = l.ranks[i + 1].rank;
            self.stars = 1;
        } else if l.legend {
            self.rank = LEGEND;
            self.stars = 0;
        }
    }

    pub fn win(&mut self, l: &Ladder) {
        self.streak += 1;
        let bonus = l.index(self.rank).is_some_and(|i| l.ranks[i].streak_bonus) && l.streak_wins > 0 && self.streak >= l.streak_wins;
        self.add_star(l);
        if bonus {
            for _ in 0..l.bonus_stars {
                self.add_star(l);
            }
        }
    }

    pub fn lose(&mut self, l: &Ladder) {
        self.streak = 0;
        let Some(i) = l.index(self.rank) else { return };
        let s = &l.ranks[i];
        if !s.loses_stars {
            return;
        }
        if self.stars > 0 {
            self.stars -= 1;
        } else if !s.floor && i > 0 {
            self.rank = l.ranks[i - 1].rank;
            self.stars = l.ranks[i - 1].stars - 1;
        }
    }

    /// The season reset: `reset_to` plus some stars per rank above it held (Legend counts as `legend_counts_as`).
    pub fn season_reset(&self, l: &Ladder) -> Rank {
        let held = if self.legend() { l.legend_counts_as } else { self.rank };
        Rank::climb(l, Rank { rank: l.reset_to, stars: 0, streak: 0 }, l.per_rank_above * (l.reset_to - held).max(0))
    }
}

/// Elo with K 32: the new ratings of a and b after a game a won (`a_won`) or lost.
pub fn elo(a: f64, b: f64, a_won: bool) -> (f64, f64) {
    let ea = 1.0 / (1.0 + 10f64.powf((b - a) / 400.0));
    let sa = if a_won { 1.0 } else { 0.0 };
    let d = 32.0 * (sa - ea);
    (a + d, b - d)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    Casual,
    Ranked,
    Arena,
    Friendly,
}

impl Mode {
    pub fn as_str(&self) -> &'static str {
        match self {
            Mode::Casual => "casual",
            Mode::Ranked => "ranked",
            Mode::Arena => "arena",
            Mode::Friendly => "friendly",
        }
    }
}

/// What a queued player is matched by.
#[derive(Clone, Copy, Debug)]
pub struct Key {
    pub mmr: f64,
    /// Ranked: stars from 25/0 (Legend 95); Arena: wins − losses.
    pub level: i64,
    pub legend: bool,
}

/// Is the pair compared by MMR (casual; two Legends) or by level (ranked stars, Arena record)?
fn by_mmr(mode: Mode, a: &Key, b: &Key) -> bool {
    mode == Mode::Casual || (mode == Mode::Ranked && a.legend && b.legend)
}

pub fn window(mode: Mode, mmr: bool, waited_secs: u64) -> f64 {
    let w = waited_secs as f64;
    match (mode, mmr) {
        (_, true) => 50.0 + 25.0 * w,
        (Mode::Ranked, false) => 2.0 + (waited_secs / 5) as f64,
        _ => (waited_secs / 10) as f64,
    }
}

/// The gap between two seekers when each one's window allows it.
pub fn fits(mode: Mode, a: &Key, a_waited: u64, b: &Key, b_waited: u64) -> Option<f64> {
    let m = by_mmr(mode, a, b);
    let gap = if m { (a.mmr - b.mmr).abs() } else { (a.level - b.level).abs() as f64 };
    (gap <= window(mode, m, a_waited) && gap <= window(mode, m, b_waited)).then_some(gap)
}

/// The window shown to a waiting player (by their own kind of key).
pub fn shown_window(mode: Mode, k: &Key, waited: u64) -> f64 {
    window(mode, mode == Mode::Casual || (mode == Mode::Ranked && k.legend), waited)
}

// --- time -------------------------------------------------------------------

pub fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// (year, month, day) of a unix day number (Howard Hinnant's civil_from_days).
fn civil(days: i64) -> (i64, i64, i64) {
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

/// The season of a unix time: months since year 0 (UTC calendar months).
pub fn season_of(t: i64) -> i64 {
    let (y, m, _) = civil(t.div_euclid(86400));
    y * 12 + m - 1
}

pub fn season_name(s: i64) -> String {
    format!("{:04}-{:02}", s / 12, s % 12 + 1)
}

pub fn date(t: i64) -> String {
    let (y, m, d) = civil(t.div_euclid(86400));
    let s = t.rem_euclid(86400);
    format!("{y:04}-{m:02}-{d:02} {:02}:{:02}", s / 3600, s % 3600 / 60)
}

/// A rank carried from `from` season to `to`: one reset per month passed.
pub fn advance(l: &Ladder, mut r: Rank, from: i64, to: i64) -> Rank {
    for _ in 0..(to - from).clamp(0, 30) {
        r = r.season_reset(l);
    }
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(rank: i64, stars: i64, streak: i64) -> Rank {
        Rank { rank, stars, streak }
    }

    #[test]
    fn stars_and_streaks() {
        let l = &Ladder::classic();
        let mut x = l.start;
        x.win(l);
        x.win(l);
        assert_eq!(x, r(25, 2, 2));
        x.win(l); // 3rd in a row: +2, overflow carries
        assert_eq!(x, r(24, 2, 3));
        x.lose(l); // no loss at 25-21
        assert_eq!(x, r(24, 2, 0));
        // 20 floor
        let mut x = r(20, 0, 0);
        x.lose(l);
        assert_eq!(x, r(20, 0, 0));
        let mut x = r(19, 0, 4);
        x.lose(l);
        assert_eq!(x, r(20, 2, 0));
        // no bonus at rank 5 and up; bonus at 6 can carry into 5
        let mut x = r(5, 0, 5);
        x.win(l);
        assert_eq!(x, r(5, 1, 6));
        let mut x = r(6, 5, 2);
        x.win(l);
        assert_eq!(x, r(5, 2, 3));
        // Legend after rank 1, never lost
        let mut x = r(1, 5, 0);
        x.win(l);
        assert!(x.legend());
        x.lose(l);
        assert!(x.legend());
        assert_eq!(l.start.level(l), 0);
        assert_eq!(r(1, 5, 0).level(l), 95);
        assert_eq!(r(LEGEND, 0, 0).level(l), 95);
    }

    #[test]
    fn season_reset() {
        let l = &Ladder::classic();
        let reset = |rank| r(rank, 0, 0).season_reset(l);
        assert_eq!(reset(15), r(21, 2, 0));
        assert_eq!(reset(20), r(23, 1, 0));
        assert_eq!(reset(10), r(19, 2, 0));
        assert_eq!(reset(5), r(17, 1, 0));
        assert_eq!(reset(1), r(16, 2, 0));
        assert_eq!(reset(LEGEND), r(16, 3, 0));
        assert_eq!(reset(25), r(25, 0, 0));
        assert_eq!(advance(l, r(LEGEND, 0, 0), 10, 10), r(LEGEND, 0, 0));
        assert_eq!(advance(l, r(LEGEND, 0, 0), 10, 11), r(16, 3, 0));
    }

    /// Another pack's ladder: 3 ranks of 2 stars, a floor at 2, a streak of 2 gives 2 more, no Legend.
    #[test]
    fn a_pack_ladder() {
        let l = &Ladder::from_rules(&serde_json::json!({"start": {"rank": 3, "stars": 0},
            "ranks": [{"rank": 3, "stars": 2, "streak_bonus": true}, {"rank": 2, "stars": 2, "floor": true, "streak_bonus": true}, {"rank": 1, "stars": 2}],
            "streak": {"wins": 2, "bonus_stars": 2}, "legend": null, "season": {"reset": {"to_rank": 3, "stars_per_rank_above": 2}}})).unwrap();
        let mut x = l.start;
        x.win(l);
        assert_eq!(x, r(3, 1, 1));
        x.win(l); // 2nd in a row: 1 + 2 stars
        assert_eq!(x, r(2, 2, 2));
        x.lose(l);
        x.lose(l);
        x.lose(l); // the floor at 2
        assert_eq!(x, r(2, 0, 0));
        let mut x = r(1, 0, 0);
        x.lose(l);
        assert_eq!(x, r(2, 1, 0));
        let mut x = r(1, 2, 0);
        x.win(l); // no Legend: stays full at the top
        assert_eq!(x, r(1, 2, 1));
        assert_eq!(x.level(l), 6);
        assert_eq!(r(1, 0, 0).season_reset(l), r(2, 2, 0)); // 2 ranks above 3, 2 stars each
        assert!(Ladder::from_rules(&serde_json::json!({"ranks": []})).is_none());
    }

    #[test]
    fn elo_k32() {
        let (a, b) = elo(1500.0, 1500.0, true);
        assert_eq!((a, b), (1516.0, 1484.0));
        let (a, _) = elo(1500.0, 1900.0, false);
        assert!((a - 1497.09).abs() < 0.01);
    }

    #[test]
    fn windows_grow() {
        let k = |mmr, level, legend| Key { mmr, level, legend };
        // casual: 50 + 25/s, inside both windows
        assert!(fits(Mode::Casual, &k(1500.0, 0, false), 0, &k(1550.0, 0, false), 0).is_some());
        assert!(fits(Mode::Casual, &k(1500.0, 0, false), 0, &k(1600.0, 0, false), 10).is_none());
        assert!(fits(Mode::Casual, &k(1500.0, 0, false), 2, &k(1600.0, 0, false), 2).is_some());
        // ranked: 2 stars + 1 per 5 s
        assert!(fits(Mode::Ranked, &k(0.0, 10, false), 0, &k(0.0, 13, false), 0).is_none());
        assert!(fits(Mode::Ranked, &k(0.0, 10, false), 5, &k(0.0, 13, false), 5).is_some());
        // two Legends by MMR
        assert!(fits(Mode::Ranked, &k(2000.0, 95, true), 0, &k(1500.0, 95, true), 0).is_none());
        // arena: record 0 + 1 per 10 s
        assert!(fits(Mode::Arena, &k(0.0, 2, false), 9, &k(0.0, 1, false), 9).is_none());
        assert!(fits(Mode::Arena, &k(0.0, 2, false), 10, &k(0.0, 1, false), 10).is_some());
    }

    #[test]
    fn dates() {
        assert_eq!(date(0), "1970-01-01 00:00");
        assert_eq!(season_name(season_of(1_792_000_000)), "2026-10");
        assert_eq!(season_of(1_792_000_000) - season_of(0), (2026 - 1970) * 12 + 9);
    }
}
