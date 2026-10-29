//! The places to think (the CPU the bots may take at once): when all are taken, the bot whose turn
//! ends first goes first, not the one that came first.

use std::sync::{Arc, Mutex};
use tokio::sync::oneshot;
use tokio::time::Instant;

pub struct Think {
    inner: Mutex<Inner>,
}

struct Inner {
    free: usize,
    /// (the waiter's turn deadline, arrival order, where its place goes)
    waiting: Vec<(Instant, u64, oneshot::Sender<Place>)>,
    arrived: u64,
}

/// A place taken; dropping it hands it on (or frees it).
pub struct Place {
    gate: Arc<Think>,
}

impl Think {
    pub fn new(places: usize) -> Arc<Think> {
        Arc::new(Think { inner: Mutex::new(Inner { free: places.max(1), waiting: vec![], arrived: 0 }) })
    }

    /// A place for a bot whose turn ends at `deadline`.
    pub async fn enter(self: &Arc<Self>, deadline: Instant) -> Place {
        let rx = {
            let mut i = self.inner.lock().unwrap_or_else(|e| e.into_inner());
            if i.free > 0 {
                i.free -= 1;
                return Place { gate: self.clone() };
            }
            let (tx, rx) = oneshot::channel();
            i.arrived += 1;
            let n = i.arrived;
            i.waiting.push((deadline, n, tx));
            rx
        };
        // (the sender lives in `waiting` until a place comes, so this never fails)
        rx.await.expect("a place")
    }

    /// Bots waiting for a place now.
    pub fn waiting(&self) -> usize {
        self.inner.lock().unwrap_or_else(|e| e.into_inner()).waiting.len()
    }
}

impl Drop for Place {
    fn drop(&mut self) {
        let mut i = self.gate.inner.lock().unwrap_or_else(|e| e.into_inner());
        loop {
            let Some(k) = (0..i.waiting.len()).min_by_key(|&k| (i.waiting[k].0, i.waiting[k].1)) else { break };
            let (_, _, tx) = i.waiting.swap_remove(k);
            match tx.send(Place { gate: self.gate.clone() }) {
                Ok(()) => return,
                // that bot stopped waiting: the place must not come back here (the lock is held)
                Err(p) => std::mem::forget(p),
            }
        }
        i.free += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn the_nearest_deadline_goes_first() {
        let t = Think::new(1);
        let held = t.enter(Instant::now()).await;
        let now = Instant::now();
        let order = Arc::new(Mutex::new(vec![]));
        let mut tasks = vec![];
        for (name, secs) in [("late", 60), ("soon", 5), ("middle", 30)] {
            let (t, order) = (t.clone(), order.clone());
            tasks.push(tokio::spawn(async move {
                let _p = t.enter(now + Duration::from_secs(secs)).await;
                order.lock().unwrap().push(name);
            }));
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert_eq!(t.waiting(), 3);
        drop(held);
        for task in tasks {
            task.await.unwrap();
        }
        assert_eq!(*order.lock().unwrap(), ["soon", "middle", "late"]);
    }

    #[tokio::test]
    async fn a_place_of_a_bot_that_left_is_not_lost() {
        let t = Think::new(1);
        let held = t.enter(Instant::now()).await;
        let gone = tokio::spawn({
            let t = t.clone();
            async move {
                let _p = t.enter(Instant::now()).await;
            }
        });
        tokio::time::sleep(Duration::from_millis(10)).await;
        gone.abort();
        let _ = gone.await;
        drop(held);
        // the place is free again
        tokio::time::timeout(Duration::from_secs(1), t.enter(Instant::now())).await.expect("free");
    }
}
