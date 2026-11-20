# Boomsday … Rise of Shadows, the table's animations, then the megapack — the owner's request (2026-11-17)

## Version 0.72.0 (one release)

### Three more expansions, one after another (as steps 1–11 of 2026-11-11-expansions.md)

| # | Set | Released | Pack id | HearthstoneJSON prefix |
|---|---|---|---|---|
| 12 | The Boomsday Project | 2018-08-07 | boom-2018 | BOT_ |
| 13 | Rastakhan's Rumble | 2018-12-04 | trl-2018 | TRL_ |
| 14 | Rise of Shadows | 2019-04-09 | dal-2019 | DAL_ |

Same rules as before (docs/packs/expansion-checklist.md): every card exactly as on that set's release day, base = the
previous pack, self-contained, no generated card art, backgrounds via Codex, the owner's local pack with Blizzard art,
Opus sounds by role, voice EN+RU and original music; decks of that meta from real sources. Preparation (data, assets,
decks, backgrounds) for all three runs in parallel first; the packs are built one after another.

### Fixes

- Vicious Fledgling attacks the enemy hero in a ranked game → its Adapt choice → the game freezes; nothing can be
  played until the turn ends.
- The installed packs screen: the right panel scrolls (a long description pushes "Delete" off the window).
- Legendary play music in the packs does not play.

### The table shows what happens (animations)

- An effect on a Hero Power, a deck or a hand shows at that place.
- Stats or cost of a card in hand changed: green when buffed (cost: its colour changes), the same for the Hero Power's
  cost and a weapon's stats.
- A card shuffled into a deck flies from its source into that deck; a card added to a hand flies from its source into
  that hand — any deck, any hand, always from where it comes.
- Freeze together with damage happens at the same moment; a nicer freeze shader.
- The end-turn button flips to the other side when the turn changes.
- Joust: the cards fly out of both decks; whose card is which and who won is clear.
- Start of Game effects animate what they do.
- A targeted spell turns into a spell effect while it is the targeting arrow; back to a card if it returns to the hand;
  the opponent never sees the card.
- A secret that triggers is revealed: its card shown, with its sound (check what exists).

## Version 0.73.0: the megapack

One pack with shared media (pictures, sounds, music) and every game version up to the end of Rise of Shadows: each
balance patch of the Hearthstone Wiki (and art/sound changes where they happened, e.g. Patches) is a version with its own
full copy of the card data (texts, balance, rules) that points at the shared media it uses. The player picks the game
and then its version. It replaces the separate packs (Classic, Naxxramas, the expansions) and holds every version made
so far and all the ones between, so any past meta can be played.

Modes per version: before Whispers of the Old Gods only Standard; from it Standard and Wild with the sets of each format
as in the game at that time. Each version and each mode has its own ladder and its own casual queue.

Research of every patch (balance, art, sounds) runs in parallel subagents, as do media and decks.

### The version diff (added 2026-11-19)

Next to choosing a version there is "Compare versions": pick any two versions and see every card that differs between
them as a visual diff — the card as in the first version on the left, as in the second on the right, the changed parts
(cost, attack, health, text, tribe, rarity, keywords, picture) marked in red — plus the cards added and removed. The
list scrolls, and Back returns to the version choice.

### Also in 0.73.0 (the owner, 2026-11-19)

- Installing a pack from a server (and from a file, and over code play): after the download the client hangs near 99%
  for a long time. Measure the stages; download straight to a file; run the checking, fingerprint and install in the
  background (threads on desktop/Android, chunked per frame on the web) with a progress bar per stage and a small
  indicator on every screen; the player can leave the screen or play another game meanwhile; installs queue.
- 0.72.0 leftovers: the raw `fuse` line in the history after Magnetic; Zilliax's English text ("Magnetic" and "Divine
  Shield" on one line).
- The decks of every version: from the owner's browser run of ~/ClassicHS-local/prep/patches/hearthpwn_decks.js
  (hearthpwn_decks.json).
  The owner ran it on 2026-11-20: ~/ClassicHS-local/prep/patches/hearthpwn_decks.json — 1751 decks (1731 with a deck
  code, 20 without), HearthPwn builds 13…50 (launch … Rise of the Mech), every class, Standard and Wild from Old Gods
  on; each deck: class, archetype, rating, views, updated date, its HearthPwn build, the lists (build, format) it was
  among the top 4 of its class in.

### Tournament chats (the owner, 2026-11-20; for a later version)

- A chat in the tournaments list and a chat inside each tournament: every player there can write, everyone sees the
  messages live.
- Marks: inside a tournament, a server admin has an "admin" mark and the tournament's creator a "creator" mark; in the
  tournaments list's chat only admins are marked.
- The admin panel shows these chats (the list's and each tournament's) and lets an admin write in them as the admin.
