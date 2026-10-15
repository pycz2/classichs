//! Godot's `RandomNumberGenerator` (RandomPCG, PCG32 XSH-RR), bit for bit:
//! seeding, `randi`, `randi_range`, `randf` and the `state` property.

const MULT: u64 = 6364136223846793005;
const DEFAULT_INC: u64 = 1442695040888963407;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Rng {
    pub state: u64,
    inc: u64,
    seed: u64,
}

impl Default for Rng {
    fn default() -> Self {
        Rng::new(12047754176567800795)
    }
}

impl Rng {
    /// `rng.seed = seed` on a fresh generator.
    pub fn new(seed: u64) -> Rng {
        let mut r = Rng { state: 0, inc: (DEFAULT_INC << 1) | 1, seed };
        r.set_seed(seed);
        r
    }

    /// pcg32_srandom_r with Godot's fixed stream.
    pub fn set_seed(&mut self, seed: u64) {
        self.seed = seed;
        self.state = 0;
        self.next();
        self.state = self.state.wrapping_add(seed);
        self.next();
    }

    /// The `seed` property: the last seed set (randi does not change it in Godot 4.7).
    pub fn seed(&self) -> u64 {
        self.seed
    }

    fn next(&mut self) -> u32 {
        let old = self.state;
        self.state = old.wrapping_mul(MULT).wrapping_add(self.inc);
        let xorshifted = (((old >> 18) ^ old) >> 27) as u32;
        let rot = (old >> 59) as u32;
        xorshifted.rotate_right(rot)
    }

    pub fn randi(&mut self) -> u32 {
        self.next()
    }

    /// pcg32_boundedrand_r.
    fn bounded(&mut self, bound: u32) -> u32 {
        let threshold = bound.wrapping_neg() % bound;
        loop {
            let r = self.next();
            if r >= threshold {
                return r % bound;
            }
        }
    }

    /// `randi_range(from, to)`, both ends included, either order.
    pub fn randi_range(&mut self, from: i64, to: i64) -> i64 {
        if from == to {
            return from;
        }
        let bounds = (from - to).unsigned_abs() as u32 + 1;
        self.bounded(bounds) as i64 + from.min(to)
    }

    /// `randf()` in [0, 1] (a 32-bit float, as Godot returns it).
    pub fn randf(&mut self) -> f64 {
        let proto_exp_offset = self.next();
        if proto_exp_offset == 0 {
            return 0.0;
        }
        let significand = (self.next() | 0x8000_0001) as f32;
        let exp = -32 - proto_exp_offset.leading_zeros() as i32;
        (significand * 2f32.powi(exp)) as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Values printed by Godot 4.7.2 (more in tests/fixtures/misc.jsonl).
    #[test]
    fn matches_godot() {
        let mut r = Rng::new(0);
        assert_eq!(r.state as i64, -8330585842245805678);
        let got: Vec<i64> = (0..6).map(|i| r.randi_range(0, i + 1)).collect();
        assert_eq!(got, vec![1, 0, 0, 3, 3, 6]);
        assert_eq!(r.randi_range(3, 5), 5);
        assert_eq!(r.randi_range(5, 3), 5);
        assert_eq!(r.randi_range(7, 7), 7);
        assert_eq!(r.state as i64, -8057191695202445318);
        let f: Vec<String> = (0..8).map(|_| format!("{:.20}", r.randf())).collect();
        assert_eq!(f[0], "0.85928440093994140625");
        assert_eq!(f[7], "0.99049568176269531250");
        assert_eq!(r.randi(), 2169385747);
        assert_eq!(r.state as i64, 6804368887496053537);
        let mut r = Rng::new(-5i64 as u64);
        assert_eq!(r.state as i64, -3257778814060667471);
        let got: Vec<i64> = (0..6).map(|i| r.randi_range(0, i + 1)).collect();
        assert_eq!(got, vec![0, 1, 0, 2, 0, 3]);
    }
}
