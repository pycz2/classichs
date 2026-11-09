//! The tournament formats as pure functions: the matches made at seeding (round robin,
//! Scheveningen, single and double elimination), the Swiss pairing of a round, the
//! standings and the places. Players are seed indices here (0..n) or account ids (i64).

use std::collections::{HashMap, HashSet};

/// One side of a match planned at seeding.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Side {
    /// The entrant with this seed (0-based).
    Seed(usize),
    /// Nobody: the other side gets the match (a bye).
    Bye,
    /// The winner of the planned match with this index.
    Winner(usize),
    /// The loser of the planned match with this index.
    Loser(usize),
}

/// A match planned at seeding.
#[derive(Clone, Debug, PartialEq)]
pub struct Spec {
    pub round: i64,
    /// Elimination: "w" (winners), "l" (losers), "gf" (grand final); "" else.
    pub bracket: &'static str,
    pub slot: i64,
    pub sides: [Side; 2],
    /// Elimination: the loser is out at this stage (later stages place higher); 0 = not out.
    pub out: i64,
}

fn spec(round: usize, bracket: &'static str, slot: usize, sides: [Side; 2], out: usize) -> Spec {
    Spec { round: round as i64, bracket, slot: slot as i64, sides, out: out as i64 }
}

/// Round robin by the circle method: every pair meets once per cycle (`cycles` 1 or 2; the
/// second with the sides swapped). An odd count sits one player out each round (no match).
pub fn round_robin(n: usize, cycles: usize) -> Vec<Spec> {
    let m = n + n % 2;
    let mut ring: Vec<usize> = (0..m).collect();
    let mut out = vec![];
    if n < 2 {
        return out;
    }
    let rounds = m - 1;
    for c in 0..cycles {
        for r in 0..rounds {
            let mut slot = 0;
            for i in 0..m / 2 {
                let (a, b) = (ring[i], ring[m - 1 - i]);
                if a < n && b < n {
                    let s = if c == 1 { [Side::Seed(b), Side::Seed(a)] } else { [Side::Seed(a), Side::Seed(b)] };
                    out.push(spec(c * rounds + r + 1, "", slot, s, 0));
                    slot += 1;
                }
            }
            ring[1..].rotate_right(1);
        }
    }
    out
}

/// The team of a seed in Scheveningen: the first half (one more for an odd count) is team 0.
/// The seeds are random, so the teams are too.
pub fn team(n: usize, seed: usize) -> i64 {
    if seed < n.div_ceil(2) { 0 } else { 1 }
}

/// Scheveningen: everyone of team 0 plays everyone of team 1, one match each per round.
pub fn scheveningen(n: usize) -> Vec<Spec> {
    let p = n.div_ceil(2);
    let q = n - p;
    let mut out = vec![];
    for r in 0..p {
        let mut slot = 0;
        for i in 0..p {
            let j = (i + r) % p;
            if j < q {
                out.push(spec(r + 1, "", slot, [Side::Seed(i), Side::Seed(p + j)], 0));
                slot += 1;
            }
        }
    }
    out
}

/// Seed positions in a bracket of `size` (a power of two): the top seeds meet last.
fn positions(size: usize) -> Vec<usize> {
    let mut p = vec![0];
    while p.len() < size {
        let len = p.len();
        p = p.iter().flat_map(|&s| [s, 2 * len - 1 - s]).collect();
    }
    p
}

/// A bracket to the next power of two (byes for the top seeds); `double`: a losers bracket and
/// a grand final (no reset).
pub fn elimination(n: usize, double: bool) -> Vec<Spec> {
    let size = n.next_power_of_two().max(2);
    let k = size.trailing_zeros() as usize;
    let mut out: Vec<Spec> = vec![];
    let pos = positions(size);
    let seat = |i: usize| if pos[i] < n { Side::Seed(pos[i]) } else { Side::Bye };
    // wb[r] = the indices of winners' round r+1
    let mut wb: Vec<Vec<usize>> = vec![];
    for r in 0..k {
        let count = size >> (r + 1);
        let mut row = vec![];
        for s in 0..count {
            let sides = if r == 0 { [seat(2 * s), seat(2 * s + 1)] } else { [Side::Winner(wb[r - 1][2 * s]), Side::Winner(wb[r - 1][2 * s + 1])] };
            row.push(out.len());
            out.push(spec(r + 1, "w", s, sides, if double { 0 } else { r + 1 }));
        }
        wb.push(row);
    }
    if !double {
        return out;
    }
    let final_w = wb[k - 1][0];
    if k == 1 {
        out.push(spec(1, "gf", 0, [Side::Winner(final_w), Side::Loser(final_w)], 1));
        return out;
    }
    // lb[r] = the indices of losers' round r+1; the stage of a losers' round is its number
    let mut lb: Vec<Vec<usize>> = vec![];
    let mut row = vec![];
    for s in 0..size / 4 {
        row.push(out.len());
        out.push(spec(1, "l", s, [Side::Loser(wb[0][2 * s]), Side::Loser(wb[0][2 * s + 1])], 1));
    }
    lb.push(row);
    for j in 1..k {
        // the losers of winners' round j+1 drop in (reversed every other round: fewer rematches)
        let count = size >> (j + 1);
        let r = 2 * j;
        let mut row = vec![];
        for s in 0..count {
            let d = if j % 2 == 1 { count - 1 - s } else { s };
            row.push(out.len());
            out.push(spec(r, "l", s, [Side::Winner(lb[r - 2][s]), Side::Loser(wb[j][d])], r));
        }
        lb.push(row);
        if j < k - 1 {
            let mut row = vec![];
            for s in 0..count / 2 {
                row.push(out.len());
                out.push(spec(r + 1, "l", s, [Side::Winner(lb[r - 1][2 * s]), Side::Winner(lb[r - 1][2 * s + 1])], r + 1));
            }
            lb.push(row);
        }
    }
    let final_l = lb[lb.len() - 1][0];
    out.push(spec(1, "gf", 0, [Side::Winner(final_w), Side::Winner(final_l)], lb.len() + 1));
    out
}

/// A side once known: a player, nobody (a bye), or not yet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Slot {
    Known(i64),
    Empty,
    Pending,
}

/// What a side is now; `outcome(i)`: the (winner, loser) of planned match i once it is over.
pub fn resolve(side: Side, seeds: &[i64], outcome: &dyn Fn(usize) -> Option<(Option<i64>, Option<i64>)>) -> Slot {
    let of = |x: Option<i64>| x.map_or(Slot::Empty, Slot::Known);
    match side {
        Side::Seed(i) => seeds.get(i).map_or(Slot::Empty, |&p| Slot::Known(p)),
        Side::Bye => Slot::Empty,
        Side::Winner(i) => outcome(i).map_or(Slot::Pending, |(w, _)| of(w)),
        Side::Loser(i) => outcome(i).map_or(Slot::Pending, |(_, l)| of(l)),
    }
}

/// Swiss: the pairs of the next round. `order`: the players still in, best first; `played`:
/// the pairs that met (either order); `had_bye`. An odd count gives a bye to the lowest player
/// without one. Pairs go down the order (so within score groups first) and avoid rematches
/// when the search finds a way; else rematches are allowed.
pub fn swiss_pairs(order: &[i64], played: &HashSet<(i64, i64)>, had_bye: &HashSet<i64>) -> (Vec<(i64, i64)>, Option<i64>) {
    let mut rest: Vec<i64> = order.to_vec();
    let bye = if rest.len() % 2 == 1 {
        let i = rest.iter().rposition(|p| !had_bye.contains(p)).unwrap_or(rest.len() - 1);
        Some(rest.remove(i))
    } else {
        None
    };
    let met = |a: i64, b: i64| played.contains(&(a, b)) || played.contains(&(b, a));
    fn search(rest: &mut Vec<i64>, out: &mut Vec<(i64, i64)>, met: &dyn Fn(i64, i64) -> bool, budget: &mut u32) -> bool {
        if rest.is_empty() {
            return true;
        }
        if *budget == 0 {
            return false;
        }
        *budget -= 1;
        let a = rest.remove(0);
        for i in 0..rest.len() {
            let b = rest[i];
            if met(a, b) {
                continue;
            }
            rest.remove(i);
            out.push((a, b));
            if search(rest, out, met, budget) {
                return true;
            }
            out.pop();
            rest.insert(i, b);
        }
        rest.insert(0, a);
        false
    }
    let mut out = vec![];
    // ponytail: a bounded depth-first search; a weighted matching if big Swiss events ever rematch needlessly
    let mut budget = 200_000;
    if !search(&mut rest.clone(), &mut out, &met, &mut budget) {
        out = rest.chunks(2).map(|c| (c[0], c[1])).collect();
    }
    (out, bye)
}

/// Default Swiss rounds: ceil(log2 n), 1..10.
pub fn swiss_rounds(n: usize) -> i64 {
    (n.max(2).next_power_of_two().trailing_zeros() as i64).clamp(1, 10)
}

/// A finished match for the standings: the sides (None = a bye), the winner, the games won.
#[derive(Clone, Debug)]
pub struct Played {
    pub p: [Option<i64>; 2],
    pub winner: Option<i64>,
    pub score: [i64; 2],
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Stand {
    /// Matches won (byes too).
    pub points: i64,
    pub match_losses: i64,
    /// Games won and lost.
    pub wins: i64,
    pub losses: i64,
    /// The sum of the opponents' points (Swiss tiebreak).
    pub buchholz: i64,
}

pub fn standings(players: &[i64], matches: &[Played]) -> HashMap<i64, Stand> {
    let mut s: HashMap<i64, Stand> = players.iter().map(|&p| (p, Stand::default())).collect();
    let mut opp: HashMap<i64, Vec<i64>> = HashMap::new();
    for m in matches {
        for i in 0..2 {
            let Some(p) = m.p[i] else { continue };
            let e = s.entry(p).or_default();
            e.wins += m.score[i];
            e.losses += m.score[1 - i];
            if m.winner == Some(p) {
                e.points += 1;
            } else if m.winner.is_some() {
                e.match_losses += 1;
            }
            if let Some(o) = m.p[1 - i] {
                opp.entry(p).or_default().push(o);
            }
        }
    }
    let points: HashMap<i64, i64> = s.iter().map(|(p, x)| (*p, x.points)).collect();
    for (p, x) in s.iter_mut() {
        x.buchholz = opp.get(p).map_or(0, |o| o.iter().map(|q| points.get(q).copied().unwrap_or(0)).sum());
    }
    s
}

/// Places by a key (higher is better): equal keys share a place (1 + the count of better ones).
pub fn places<K: Ord + Copy>(keys: &[(i64, K)]) -> HashMap<i64, i64> {
    keys.iter().map(|&(p, k)| (p, 1 + keys.iter().filter(|(_, o)| *o > k).count() as i64)).collect()
}

/// Table places (round robin, Swiss, Scheveningen): points, then game wins − losses, then
/// (`buchholz`) the Buchholz score.
pub fn table_places(st: &HashMap<i64, Stand>, buchholz: bool) -> HashMap<i64, i64> {
    let keys: Vec<(i64, (i64, i64, i64))> =
        st.iter().map(|(p, s)| (*p, (s.points, s.wins - s.losses, if buchholz { s.buchholz } else { 0 }))).collect();
    places(&keys)
}

/// Elimination places: by the stage where one went out (never out = the winner, first).
pub fn elimination_places(out: &HashMap<i64, i64>, players: &[i64]) -> HashMap<i64, i64> {
    let keys: Vec<(i64, i64)> = players.iter().map(|p| (*p, out.get(p).copied().unwrap_or(i64::MAX))).collect();
    places(&keys)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SIZES: [usize; 6] = [2, 3, 5, 8, 13, 128];

    fn pairs(specs: &[Spec]) -> Vec<(usize, usize, i64)> {
        specs
            .iter()
            .map(|s| match s.sides {
                [Side::Seed(a), Side::Seed(b)] => (a, b, s.round),
                _ => panic!("not a fixed pair: {s:?}"),
            })
            .collect()
    }

    /// Nobody plays twice in a round.
    fn one_per_round(p: &[(usize, usize, i64)]) {
        let mut seen = HashSet::new();
        for &(a, b, r) in p {
            assert!(a != b);
            assert!(seen.insert((a, r)) && seen.insert((b, r)), "a player twice in round {r}");
        }
    }

    #[test]
    fn round_robin_every_pair_once_per_cycle() {
        for n in SIZES {
            for cycles in [1, 2] {
                let p = pairs(&round_robin(n, cycles));
                one_per_round(&p);
                let mut count: HashMap<(usize, usize), usize> = HashMap::new();
                for &(a, b, _) in &p {
                    *count.entry((a.min(b), a.max(b))).or_default() += 1;
                }
                assert_eq!(count.len(), n * (n - 1) / 2, "n {n}");
                assert!(count.values().all(|&c| c == cycles), "n {n} cycles {cycles}");
                let rounds = p.iter().map(|x| x.2).max().unwrap();
                assert_eq!(rounds as usize, cycles * (n + n % 2 - 1), "n {n}");
            }
        }
    }

    #[test]
    fn scheveningen_everyone_meets_the_other_team_once() {
        for n in SIZES {
            let p = pairs(&scheveningen(n));
            one_per_round(&p);
            let mut met = HashSet::new();
            for &(a, b, _) in &p {
                assert_ne!(team(n, a), team(n, b));
                assert!(met.insert((a, b)), "twice: {a} {b}");
            }
            let t0 = (0..n).filter(|&s| team(n, s) == 0).count();
            assert_eq!(met.len(), t0 * (n - t0));
            assert!(t0 == n.div_ceil(2));
        }
    }

    /// Plays a planned bracket: the lower seed wins (or `upset` decides); returns the
    /// outcomes and the stage each player went out at.
    fn run(specs: &[Spec], n: usize, upset: &dyn Fn(i64, i64) -> bool) -> (Vec<Option<(Option<i64>, Option<i64>)>>, HashMap<i64, i64>, HashMap<i64, usize>) {
        let seeds: Vec<i64> = (0..n as i64).collect();
        let mut done: Vec<Option<(Option<i64>, Option<i64>)>> = vec![None; specs.len()];
        let mut out = HashMap::new();
        let mut played: HashMap<i64, usize> = HashMap::new();
        loop {
            let mut moved = false;
            for i in 0..specs.len() {
                if done[i].is_some() {
                    continue;
                }
                let snapshot = done.clone();
                let f = |j: usize| snapshot[j];
                let s = specs[i].sides.map(|x| resolve(x, &seeds, &f));
                let r = match s {
                    [Slot::Known(a), Slot::Known(b)] => {
                        assert_ne!(a, b, "a player meets itself in {:?}", specs[i]);
                        *played.entry(a).or_default() += 1;
                        *played.entry(b).or_default() += 1;
                        let a_wins = (a < b) != upset(a, b);
                        let (w, l) = if a_wins { (a, b) } else { (b, a) };
                        if specs[i].out > 0 {
                            assert!(out.insert(l, specs[i].out).is_none(), "{l} out twice");
                        }
                        Some((Some(w), Some(l)))
                    }
                    [Slot::Known(a), Slot::Empty] | [Slot::Empty, Slot::Known(a)] => Some((Some(a), None)),
                    [Slot::Empty, Slot::Empty] => Some((None, None)),
                    _ => None,
                };
                if r.is_some() {
                    done[i] = r;
                    moved = true;
                }
            }
            if !moved {
                break;
            }
        }
        (done, out, played)
    }

    #[test]
    fn single_elimination() {
        for n in SIZES {
            let specs = elimination(n, false);
            let size = n.next_power_of_two().max(2);
            assert_eq!(specs.len(), size - 1);
            let (done, out, played) = run(&specs, n, &|_, _| false);
            assert!(done.iter().all(|d| d.is_some()), "n {n}: a match never resolved");
            assert_eq!(done.last().unwrap().unwrap().0, Some(0), "the top seed wins");
            assert_eq!(out.len(), n - 1, "everyone but the winner is out once");
            // the byes go to the top seeds
            let byes = size - n;
            for s in specs.iter().filter(|s| s.round == 1) {
                match s.sides {
                    [Side::Seed(a), Side::Bye] | [Side::Bye, Side::Seed(a)] => assert!(a < byes, "n {n}: seed {a} got a bye"),
                    [Side::Seed(_), Side::Seed(_)] => {}
                    x => panic!("n {n}: {x:?} in round 1"),
                }
            }
            assert!(played.values().all(|&c| c >= 1));
            let pl = elimination_places(&out, &(0..n as i64).collect::<Vec<_>>());
            assert_eq!(pl[&0], 1);
            if n >= 2 {
                assert_eq!(pl[&1], 2, "n {n}");
            }
            if n >= 4 {
                assert_eq!((pl[&2], pl[&3]), (3, 3), "n {n}: both semi-final losers third");
            }
        }
    }

    #[test]
    fn double_elimination() {
        for n in SIZES {
            let specs = elimination(n, true);
            for upset in [false, true] {
                let (done, out, played) = run(&specs, n, &|a, b| upset && (a + b) % 3 == 0);
                assert!(done.iter().all(|d| d.is_some()), "n {n}: a match never resolved");
                assert_eq!(out.len(), n - 1, "n {n}: everyone but the winner is out once");
                // everyone (but a lone winner of byes) loses twice before going out: plays at least 2 matches
                for p in 0..n as i64 {
                    if out.contains_key(&p) {
                        assert!(played.get(&p).copied().unwrap_or(0) >= 2, "n {n}: {p} out after one match");
                    }
                }
                let champ = done.last().unwrap().unwrap().0.unwrap();
                assert!(!out.contains_key(&champ));
                let pl = elimination_places(&out, &(0..n as i64).collect::<Vec<_>>());
                assert_eq!(pl[&champ], 1);
                assert_eq!(pl.values().filter(|&&p| p == 2).count(), 1, "n {n}: one second place");
                if !upset {
                    assert_eq!(champ, 0);
                }
            }
        }
    }

    #[test]
    fn double_elimination_grand_final_without_reset() {
        // 4 players: 1 beats 0 in the winners' final, 0 comes back through the losers' bracket and
        // wins the grand final: no second final, 1 is second.
        let specs = elimination(4, true);
        let gf = specs.len() - 1;
        assert_eq!(specs[gf].bracket, "gf");
        let (done, out, _) = run(&specs, 4, &|a, b| (a, b) == (0, 1));
        assert_eq!(done[gf].unwrap(), (Some(0), Some(1)));
        assert_eq!(out[&1], specs[gf].out);
        assert_eq!(elimination_places(&out, &[0, 1, 2, 3])[&1], 2);
    }

    #[test]
    fn swiss_no_rematch_and_byes() {
        for n in SIZES {
            let players: Vec<i64> = (0..n as i64).collect();
            let mut played = HashSet::new();
            let mut byes = HashSet::new();
            let mut ms: Vec<Played> = vec![];
            let rounds = swiss_rounds(n);
            for _ in 0..rounds {
                let st = standings(&players, &ms);
                let mut order = players.clone();
                order.sort_by_key(|p| (-st[p].points, *p));
                let (pairs, bye) = swiss_pairs(&order, &played, &byes);
                assert_eq!(bye.is_some(), n % 2 == 1);
                if let Some(b) = bye {
                    assert!(byes.insert(b), "n {n}: a second bye for {b} while others had none");
                    ms.push(Played { p: [Some(b), None], winner: Some(b), score: [0, 0] });
                }
                let mut seen = HashSet::new();
                for &(a, b) in &pairs {
                    assert!(!played.contains(&(a, b)) && !played.contains(&(b, a)), "n {n}: rematch {a} {b}");
                    assert!(seen.insert(a) && seen.insert(b));
                    played.insert((a, b));
                    let w = a.min(b);
                    ms.push(Played { p: [Some(a), Some(b)], winner: Some(w), score: if w == a { [1, 0] } else { [0, 1] } });
                }
                assert_eq!(seen.len() + bye.iter().count(), n);
            }
        }
    }

    #[test]
    fn swiss_rematch_only_when_unavoidable() {
        // 2 players, 2 rounds: they must meet again
        let mut played = HashSet::new();
        played.insert((0, 1));
        let (p, bye) = swiss_pairs(&[0, 1], &played, &HashSet::new());
        assert_eq!((p, bye), (vec![(0, 1)], None));
        // 4 players: top two met, so 0 plays 2
        let (p, _) = swiss_pairs(&[0, 1, 2, 3], &played, &HashSet::new());
        assert_eq!(p, vec![(0, 2), (1, 3)]);
    }

    #[test]
    fn standings_and_table_places() {
        let ms = vec![
            Played { p: [Some(1), Some(2)], winner: Some(1), score: [2, 0] },
            Played { p: [Some(3), Some(4)], winner: Some(3), score: [2, 1] },
            Played { p: [Some(1), Some(3)], winner: Some(1), score: [2, 1] },
            Played { p: [Some(2), Some(4)], winner: Some(2), score: [2, 0] },
            Played { p: [Some(5), None], winner: Some(5), score: [0, 0] },
        ];
        let st = standings(&[1, 2, 3, 4, 5], &ms);
        assert_eq!(st[&1], Stand { points: 2, match_losses: 0, wins: 4, losses: 1, buchholz: 2 });
        assert_eq!(st[&5].points, 1);
        let pl = table_places(&st, false);
        assert_eq!(pl[&1], 1);
        // 2 (games 2-2), 3 (3-3) and 5 (a bye, 0-0): one point, +0 each: shared
        assert_eq!((pl[&2], pl[&3], pl[&5]), (2, 2, 2));
        assert_eq!(pl[&4], 5);
        // Buchholz: 2 and 3 met 1 (2 points) and 4 (0); 5 met nobody
        let pb = table_places(&st, true);
        assert_eq!((pb[&2], pb[&3], pb[&5]), (2, 2, 4));
    }
}
