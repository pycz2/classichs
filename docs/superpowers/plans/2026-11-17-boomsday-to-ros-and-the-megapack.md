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
- How a pack is checked and stored, on the client and on the server (the owner, 2026-11-20). Unpacking alone gains
  little: images and sounds are stored in the zip uncompressed, and the server loads a pack's rules once per process.
  The time goes elsewhere:
  - Measure every stage first, on the client (desktop, Android, web) and on the server, with a big pack (~60 MB) and
    the megapack.
  - Client install (`game/packs.gd` `install`): today the whole pack is in memory, then a temp file, then `problems()`
    reads nearly every file and `content_hash()` reads every file again (GDScript). Move the check and both hashes into
    the Rust extension (the engine has the same code the server uses: `engine_pack::read_zip_from`, the hashes), one
    read of each file; download straight to a file (above).
  - Server receive (`server/src/packs.rs` `receive` → `check_file` → `add`): today it hashes while receiving, then reads
    the whole zip twice more (`inspect_from`, `content_hash_from`), then the trial game. Check and hash in one read; the
    admin panel (and a player's upload from the client) shows the stages: receiving (bytes), checking, trial game,
    storing, done — the same stage names on the server and in the client.
  - Card pictures are decoded from PNG on every load (`Pack.image`): add a cache of decoded pictures only if the
    measurement shows it matters.
  - The web: every file of `user://` is held in memory anyway, so an unpacked copy there would cost memory; keep one zip.
- A foldable phone (the owner, 2026-11-20): on the small (outer) screen the mobile version opens as a page that
  scrolls up and down, with only a part of the game in view, instead of filling the screen. Unfolded to the big
  screen, it is skewed at first and comes right only after entering a game and changing the menu. The game must
  always fill the whole screen that is on, and lay itself out again at once on every switch of screen, size or
  turn (fold/unfold, rotation), without a page scroll. It is the Android app (the owner, 2026-11-20); check the web
  build in a phone's browser too. Test with an emulator's foldable profile or by resizing the window in steps.
  A first lead: `ui/main.gd` `_fit_phone` — on a phone screen wider than 16:9 it makes the menu screens 1280 wide
  and taller than the window, inside the pan that scrolls up and down (UI fix 58, "Phone landscape: maybe some
  scrolling"); the outer screen of a foldable is such a long one. And the zoom is chosen from the screen in view, so
  after a size change it may stay as it was until the next screen change (the skew after unfolding).
- A faster build and release (the owner, 2026-11-20: all the improvements of the local report
  ~/ClassicHS-local/ci-report/index.html; the release of 0.72.1 took 61 min, GitHub built the same code 3 times):
  - The tag builds nothing again: its release job takes the files of the main run of the same commit
    (actions/download-artifact with run-id) and makes the GitHub release (tag wait 24.4 → ~5.5 min).
  - The splash goes into the version commit (tools/release.sh makes it before that commit): no second main run.
  - Commits only in `docs/` start no build (`paths-ignore: docs/**` on the push to main).
  - macOS: arm64 and x86_64 of the rules engine on two machines in parallel, `lipo` in the game job (−~4.5 min on
    the longest branch).
  - Server tests only on Linux; macOS and Windows only build the server.
  - The game job splits: the tests start right after the Linux machine, the export waits for all three.
  - The game tests on 4 processes (the runner has 4 cores; check the WebRTC test under load).
  - Deploy: download only the release files that changed (compare the host's pack hashes with the files' sha256
    from the GitHub API), and let the host download them from GitHub itself instead of an upload over the home line
    (needs a change of classichs-deploy on the host: the owner runs the sudo step).
  - Expected: a release in ~25 min instead of 61; ~1 h less of GitHub machine time per release.
  - Plus what the detailed log analysis (the report's section on the slow stages) finds.
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

Chat moderation and keeping (the owner, 2026-11-20):
- Moderators and admins (by permission: `chats.moderate`, see the 0.74.0 roles plan) can delete a message in a
  tournament chat or the tournaments list's chat. A deleted message stays as a line "deleted by <moderator>" (the text
  hidden), so everyone sees that someone removed it and who. Moderators/admins also from the admin panel.
- A tournament's chat opens when the tournament is created and closes 10 minutes after the tournament ends; then nobody
  can write in it (it stays readable while kept).
- The tournaments list's common chat keeps only the last 2 weeks: older messages are removed (a daily cleanup on the
  server).
- Private messages between players (the friends chat) are kept 2 weeks too; older ones are removed the same way.
- A tournament's own chat is kept 2 weeks as well (the owner, 2026-11-20): messages older than 2 weeks are removed by
  the same daily cleanup, also after the chat is closed.
- The keeping time is a setting in the admin panel (the owner, 2026-11-20): 2 weeks by default, any number of days, or
  "unlimited" (never removed). Only the super admin may change it (with the 0.74.0 roles: a permission of the super
  level, e.g. `settings.retention`); until 0.74.0 the admin.
- Confirmed by the owner (2026-11-20): exactly one common chat in the tournaments list, and each tournament has its own
  chat, isolated from every other tournament's chat (a message, its readers and its moderation belong to that
  tournament only).
