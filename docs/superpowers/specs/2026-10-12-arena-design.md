# Arena (online, two players) — design

Owner's request (2026-10-12): an Arena mode for two people online. Both connect
like an online game, meet in a lobby, each drafts a 30-card Arena deck the way
Hearthstone did in 2014, then they play a series until one has three wins.
Also: the match result from the local player's side over a picture (done in
0.20.0 stage 1), and a check that a draw works.

## Draft rules (2014 Arena; rulings from the sources below)

| Rule | Value |
|---|---|
| Hero | 3 different random classes are offered; the player takes one. |
| Picks | 30. Each pick offers 3 different cards of one rarity; the player takes one, the other two are gone. |
| Rarity tiers | Basic and Common are one tier ("common"), then Rare, Epic, Legendary. |
| Normal pick rarity | common 80 %, rare 14 %, epic 5 %, legendary 1 % (close to the observed 79/15/5/1). |
| Special picks | picks 1, 10, 20, 30 are Rare or better: rare 78 %, epic 18 %, legendary 4 %. |
| Pool | collectible cards of the hero's class and neutral cards; heroes excluded. |
| Class bias | a class card is 1.5 times as likely as a neutral card (+50 %). |
| Copies | no limit (more than 2 of a card, more than 1 of a Legendary). |

Sources: hearthstone.wiki.gg/wiki/Arena ("The 1st, 10th, 20th, and 30th picks
will be guaranteed to offer Rare, Epic, or Legendary cards"; class cards +50 %;
observed averages 79 % Common, 15 % Rare, 5 % Epic, 1 % Legendary). The exact
2014 per-pick odds were never published: the numbers above are a ruling.

## Flow

1. Play → Online Game: name → **kind: Game or Arena** → (Game only: deck) →
   Create / Join → codes. The hello carries the kind; different kinds fail with
   a clear message.
2. Arena screen (both players): hero choice → draft (3 cards, the deck list on
   the right, the mana curve at the bottom left) → lobby.
3. The opponent's progress is shown all the time: choosing a hero / hero chosen
   (not which), cards drafted N/30, ready.
4. Ready: when both are ready, game N starts with the two Arena decks. After a
   game both return to the lobby; the score is shown; Ready again starts the next
   game. A draw does not count. First to 3 wins takes the Arena.
5. In the lobby: Concede the Arena (the opponent wins it) and Exit to the menu
   (leaving gives the opponent the Arena).

## Protocol (ArenaSession over the same Transport)

- `hello {mode: "arena", protocol, version, data, name}`
- `status {hero: bool, cards: int, ready: bool}` — after every change.
- `game {g: n, m: <NetSession message>}` — game n runs a normal NetSession over
  a ChannelTransport (the hello of that session carries the deck; Arena decks
  are validated without the copy limit).
- `concede {}` — the sender gives up the Arena.
- `bye {}` — the sender left.

Score: both sides count it from each game's result (the games are lockstep, so
they agree).

## Rulings after the review (2026-10-12)

- Exit to the menu is on every Arena stage (hero choice, draft, lobby); leaving
  at any time gives the opponent the Arena.
- The Arena screen rebuilds only on a new stage or this player's own action;
  the opponent's progress and the score update in place.
- A lost connection (a closed tab looks the same as a network drop) ends the
  Arena without a winner: "The Arena ended" and the reason. An error on one side
  is sent to the other (`bye {code: "error"}`).
- While a game is starting, Ready shows "Waiting for the opponent…" and Concede
  is off; a game that starts after the Arena ended is not shown.
