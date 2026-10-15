//! Pure rules: 2014 ranked stars and seasons, Elo, matchmaking windows, dates.
//! See docs/superpowers/specs/2026-10-15-ranked-research.md.

use serde::Serialize;

/// Rank 25..=1; 0 = Legend.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct Rank {
    pub rank: i64,
    pub stars: i64,
    pub streak: i64,
}

pub const LEGEND: i64 = 0;
/// Stars from 25/0 to Legend.
pub const LEGEND_LEVEL: i64 = 95;

impl Default for Rank {
    fn default() -> Self {
        Rank { rank: 25, stars: 0, streak: 0 }
    }
}

/// Stars a rank holds: 2 (25–21), 3 (20–16), 4 (15–11), 5 (10–1).
pub fn max_stars(rank: i64) -> i64 {
    match rank {
        21..=25 => 2,
        16..=20 => 3,
        11..=15 => 4,
        _ => 5,
    }
}

impl Rank {
    pub fn legend(&self) -> bool {
        self.rank == LEGEND
    }

    /// Stars counted from 25/0 (Legend = 95): the ranked matchmaking key.
    pub fn level(&self) -> i64 {
        if self.legend() {
            return LEGEND_LEVEL;
        }
        ((self.rank + 1)..=25).map(max_stars).sum::<i64>() + self.stars
    }

    /// The rank holding `level` stars counted from 25/0 (full ranks stay full: 2 stars → 25 at 2/2).
    pub fn from_level(level: i64) -> Rank {
        let mut r = Rank::default();
        for _ in 0..level {
            r.add_star();
        }
        r
    }

    fn add_star(&mut self) {
        if self.legend() {
            return;
        }
        if self.stars < max_stars(self.rank) {
            self.stars += 1;
        } else if self.rank == 1 {
            self.rank = LEGEND;
            self.stars = 0;
        } else {
            self.rank -= 1;
            self.stars = 1;
        }
    }

    pub fn win(&mut self) {
        self.streak += 1;
        let bonus = self.streak >= 3 && self.rank >= 6;
        self.add_star();
        if bonus {
            self.add_star();
        }
    }

    pub fn lose(&mut self) {
        self.streak = 0;
        if self.legend() || self.rank >= 21 {
            return;
        }
        if self.stars > 0 {
            self.stars -= 1;
        } else if self.rank < 20 {
            self.rank += 1;
            self.stars = max_stars(self.rank) - 1;
        } // rank 20 with no stars: the floor
    }

    /// The monthly reset: rank 25 plus one star per rank above 25 held (Legend counts as 0).
    pub fn season_reset(&self) -> Rank {
        Rank::from_level(25 - self.rank)
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
pub fn advance(mut r: Rank, from: i64, to: i64) -> Rank {
    for _ in 0..(to - from).clamp(0, 30) {
        r = r.season_reset();
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
        let mut x = Rank::default();
        x.win();
        x.win();
        assert_eq!(x, r(25, 2, 2));
        x.win(); // 3rd in a row: +2, overflow carries
        assert_eq!(x, r(24, 2, 3));
        x.lose(); // no loss at 25-21
        assert_eq!(x, r(24, 2, 0));
        // 20 floor
        let mut x = r(20, 0, 0);
        x.lose();
        assert_eq!(x, r(20, 0, 0));
        let mut x = r(19, 0, 4);
        x.lose();
        assert_eq!(x, r(20, 2, 0));
        // no bonus at rank 5 and up; bonus at 6 can carry into 5
        let mut x = r(5, 0, 5);
        x.win();
        assert_eq!(x, r(5, 1, 6));
        let mut x = r(6, 5, 2);
        x.win();
        assert_eq!(x, r(5, 2, 3));
        // Legend after rank 1, never lost
        let mut x = r(1, 5, 0);
        x.win();
        assert!(x.legend());
        x.lose();
        assert!(x.legend());
        assert_eq!(Rank::default().level(), 0);
        assert_eq!(r(1, 5, 0).level(), 95);
    }

    #[test]
    fn season_reset() {
        let reset = |rank| r(rank, 0, 0).season_reset();
        assert_eq!(reset(15), r(21, 2, 0));
        assert_eq!(reset(20), r(23, 1, 0));
        assert_eq!(reset(10), r(19, 2, 0));
        assert_eq!(reset(5), r(17, 1, 0));
        assert_eq!(reset(1), r(16, 2, 0));
        assert_eq!(reset(LEGEND), r(16, 3, 0));
        assert_eq!(reset(25), r(25, 0, 0));
        assert_eq!(advance(r(LEGEND, 0, 0), 10, 10), r(LEGEND, 0, 0));
        assert_eq!(advance(r(LEGEND, 0, 0), 10, 11), r(16, 3, 0));
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
