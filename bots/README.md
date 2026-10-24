# classichs-bots

Bots that play **Classic** on a Classic HS game server through its WebSocket protocol (no game client),
to give the server life: ladder bots (ranked, then casual, then ranked… with a random deck of
`decks/`) and Arena bots (draft by `arena_tiers.json`, play the run to its end, start a new one). A random
5–15 s pause before every game. Plan and design: `docs/superpowers/plans/2026-10-24-bots.md`.

```sh
cd bots && cargo build --release
target/release/classichs-bots --server wss://hs.borovilov.xyz --ladder 6 --arena 3
# admin page (no login, local only): http://127.0.0.1:8098/
```

Options: `--server`, `--ladder N`, `--arena N`, `--admin 127.0.0.1:PORT`, `--prefix Bot` (accounts
`Bot_Ladder_1…`, `Bot_Arena_1…`), `--state-dir bots/state` (accounts and tokens, git-ignored),
`--think-ms 1200` (time per decision), `--pause 5-15`, `--root` (the repository).

**How a bot thinks** (`src/brain.rs`): only from the player's view the server sends. Hidden cards are
guessed many times over ("worlds": the own deck list minus the cards seen; the opponent's class pool —
the deck library or the Arena scores), each world with its own random seed. In each world every first
action is tried, the turn finished greedily, the opponent's whole turn played, and the position scored;
the action with the best average is played. Against the engine's built-in greedy bot (which sees
everything) it won 27 of 35 games (`cargo test --release --test duel -- --nocapture`).
