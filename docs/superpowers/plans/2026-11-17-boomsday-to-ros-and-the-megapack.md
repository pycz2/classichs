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

### Status 2026-11-26 07:20 (overnight run; not released yet)

Done and in main (d577dcc): the megapack foundation (pack versions, the version view in Python/Rust/GDScript; spec
docs/superpowers/specs/2026-11-26-megapack-design.md); packs/eras with all 58 versions (default 31761; 97 MB);
Standard/Wild in the engine (every random pool, deck checks), formats.json (33 periods), the Arena pool/bans/extra
cards per period, 2370 HearthPwn decks in the versions; the version choice and Compare versions; the server's
pack_version table and one queue/ladder per (version, format), the Play screen's version and mode; background pack
installs with stages (18.7 s → 0.15 s), the server's upload stages; the debug mode (all mechanics, effects on any card,
scenario library, 619 tricky cases, the walk with marks); card picture framing (waits for the owner's export);
minion attack sounds (local packs rebuilt); client fixes (foldable phone: 16:9 with bars, no spoilers, the fuse line,
keyword lines). Local: ~/ClassicHS-local/prep/decks (3661), prep/patches/ranked_arena.json.

Left for 0.73.0:
- Ranked and Arena rules per version from ranked_arena.json: rank names (en/ru per build), medals (ours in public
  packs), stars, streaks, floors, season reset, Legend; Arena run limits/rewards per period — server and client.
- The Arena-only cards: 28 Taverns of Time TOT_*, 9 BCON_* (with scripts, via version patches); Zayle (DAL_800)
  needs a builder key for deck_recipes and the 2019 lists.
- Fix the base packs' bugs the version agents found (now fixed only by version scripts): Shadow of Nothing (brm+),
  Power Word: Glory heals the minion's controller (tgt+), Ship's Cannon on summon (gvg+), Sapling's class (loe, og),
  AT_042/AT_037 without CHOOSE_ONE (og), Blessing of Wisdom twice, Force of Nature on a full board, C'Thun losing its
  buffs after Redemption, Servant of Yogg/Mistcaller/Potion of Polymorph (msg+), Jungle Giants counting The Darkness;
  the suspected engine bug: Frostmourne's last-Durability kill does not come back.
- Engine-wide rule changes not modelled (11.2 Counterspell order, summon triggers reading in-hand stats; 9166
  Auchenai healing-as-damage triggers; Gladiator's Longbow immunity timing; Celestial Emissary; old weapon
  Deathrattle timing) — each needs an engine flag.
- Client gaps: the pack tools' Install button and the web's waiting install still block; the replay player does not
  read game_format; the admin's player page edits only the pack-id ladder; friendly invites and Arena have no format;
  the Training format choice is not remembered; Compare versions flags markup-only text differences across bases.
- The foldable phone: edge-to-edge (no bars) needs every screen laid out for any aspect — the owner to decide.
- Text-only versions share a rules hash (13921/14366, 18336/19506/19632, 23180/23576, 29933/30103): one ladder each.
- The server keeps at most MAX_RULESETS = 48 rule sets loaded (server/src/packs.rs; leaked 'static, freed only by a
  restart): with 58 eras versions plus 18 packs, players opening many versions hit "try again after its restart".
  Measure one ruleset's memory (the host has ~900 MB), then unload unused ones (refcount / LRU) or raise the limit.
- Changelog: assembled in CHANGELOG.md / data/changelog (2ecdc2e); add the last items before the release.


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
- Minion attack sounds (the owner, 2026-11-20: "we have the downloaded attack sounds of minions; add them"). What is
  there: ~/ClassicHS-local/sounds/cache/wiki holds 693 attack sound effects (`*_Attack*.wav`, `*_Attack_Underlay.wav`,
  e.g. `AT_067_MagnataurAlpha_Attack.wav`, `ArmoredTiger_Attack_Underlay.wav`) and ~2090 attack lines (`VO_*_ATTACK_*`,
  wiki and ru); the per-set folders (~/ClassicHS-local/<set>/set, voice/<lang>) already have 880 `<id>_attack.opus`
  effects and their `_attack` lines. The client plays a card's `attack` sound and line as the attacker leaps
  (game/sound.gd `attack_start`; docs/packs/format.md "sounds"). To do: map every downloaded attack effect and line to
  its card (by id in the name, else by the card's name; the media browser ~/ClassicHS-local/media-browser shows which
  are unused), convert to Opus into each set (`<id>_attack.opus`, voice `<id>_attack.opus` per language), for every
  pack from Classic to Rise of Shadows and the megapack; then check in a match that a minion's attack plays its own
  sound and line (and the impact `attack` after it), on desktop, Android and the web; list the cards still without one.
- DONE in 0.72.2 (2026-11-20; the release took 15m28s instead of 61m39s; not done: macOS on two machines, as macOS
  is no longer on the longest path, and the trial of the built packs in CI). A faster build and release (the owner, 2026-11-20: all the improvements of the local report
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
  - From the log analysis (2026-11-20, runs 44760153274 and 44765059030):
    - First and biggest: the Rust cache is dead since 2026-11-12. Its key is the OS plus the Cargo.lock hash; the
      saved caches were made by rustc 1.99.1, the runners now have 1.100.0, so cargo throws the cache away and
      compiles every crate (300–390 "Compiling" lines a job), while the exact key match keeps the new cache from being
      saved. Put the toolchain in the key (dtolnay/rust-toolchain's `cachekey` output) or pin the toolchain.
      Warm (run 43274843104): the whole main run 14m44s instead of 26m41s; ~690 s off macOS.
    - The server's 12 integration test files in one test binary (tests/all.rs with a `mod` per file): linking
      14 test binaries at opt-level 3 costs 190–260 s a job; ~100–200 s off.
    - Tag: publish the release from the game job (gh release upload) instead of 1.86 GB through artifacts
      (download 286 s, the upload to the release itself 18 s). Main: no "game" artifact (nothing uses it;
      --from-ci takes only the server and the replay viewer), or compression-level 0 (everything in it is compressed).
    - The Godot cache only with the templates in use (402 MB of 1.9 GB; restore 22 s now).
    - setup-android: use the runner's SDK (it downloads cmdline-tools again, 16 s).
    - export_all.sh: build_packs, fetch_webrtc, the import and the cardpack copy once, not per platform; print each
      platform's time.
    - Keep build/test_times.json between runs, so the test processes get equal shares by time.
    - Correctness: `built_packs_pass_the_trial` checks no pack in CI (the rust job builds no packs): build them first
      or say so in the test.
- Ranked and Arena rules of every version (the owner, 2026-11-23). Already collected
  (~/ClassicHS-local/prep/patches/modes.md §6–7, work/format_timeline.json): the Arena card pools per period (Wild,
  Standard-only from 2017-02-28, Taverns of Time, the 2019 set rotations), every Arena ban with its dates, the
  draft rules over time (rarity picks, class/spell weights, buckets, Dual-class Arena), and for Ranked only an
  outline (ranks 25…1 and Legend, separate Standard/Wild ladders from 2016-04-26, floors at 20/15/10/5 from
  2017-02-28, new-player ranks 50…26 from 2018-10-02, fewer stars at low ranks from 2019-01-24).
  Missing — a research task for a subagent first (wiki pages and their cached copies, patch notes; every value with
  its source and the date/patch it changed; output ~/ClassicHS-local/prep/patches/ranked_arena.json + .md):
  - Ranked per period: each rank's name (25 … 1, the new-player ranks 50 … 26 and theirs) in English and Russian
    (the game's own texts), its medal picture (the file per rank, which period's look; Blizzard pictures stay
    local: the public packs get our own medals), stars per rank, win-streak bonus stars (from which rank up),
    which ranks cannot lose stars, the floors that are kept (within a season, "cannot fall below"), the season
    reset rule at a new season (how many ranks/stars back, per period), Legend (how it is reached, its numbers),
    the season length and the end-of-season rewards; Standard and Wild differences.
  - Arena per period: the run limits (wins, losses), the entry price, the rewards by number of wins, how the class
    is offered (3 heroes), retire rules, the Arena rotation and Hall of Fame interplay, special events (Dual-class,
    Taverns of Time) — whatever the game showed the player.
  Then implement per version and mode in the megapack: the ladder (ranks, names, medals, stars, streaks, floors,
  season reset) and the Arena run rules and rewards as each version had them; a checked table in the report.
- No spoilers while the opponent's turn still plays out (the owner, 2026-11-25). When the opponent has already ended
  the turn in the game state but the table still animates his actions and the turn change, our side must not show
  it yet: the end-turn button stays in the opponent's state (not lit as "your turn"), and our hand and board show no
  playable / not playable highlights (and no attack glow), until the queued animations and the turn-change animation
  are over; then everything lights up at once. The same for a reconnect, a spectator and a replay. Check with long
  opponent turns (many actions, Secrets, Deathrattles), on desktop and phone, in a bot game and over the server.
- Card picture framing (the owner, 2026-11-25). A local browser tool (~/ClassicHS-local/art-framing/index.html,
  made by its make.py) lets the owner move and zoom each picture inside its card's art window and exports
  art-framing.json: {"format": "classichs-art-framing/1", "sets": {"<art set>": {"<card id>": {"x", "y", "zoom"}}}}
  (x, y: the covering square's centre moved by that fraction of its side, right/down; zoom: the side multiplied).
  To do when the owner hands over the file: the pack format gets art/<set>/framing.json (docs/packs/format.md, the
  schema, tools/pack.py copies and checks it, the hashes), the client applies it in Art.paint_in for every window
  (hand card, board minion, hero, hero power, history, icons), the local "-custom-art" packs and the public packs
  get the owner's values, and a test pins one moved card.
- The debug mode brought up to date (the owner, 2026-11-25; ui/debug_table.gd: Scene, Interaction test, Card test,
  Effects test):
  - Every mechanic added since Classic, in the scene editor and the tests: Quests, hero cards, Dormant, Magnetic,
    Echo, Rush, Lifesteal, Poisonous, Reborn, Overkill, Twinspell, Discover, Adapt, Choose One with N options, Start
    of Game, Deathrattles given, Mega-Windfury, Can't attack, spell damage N, the doubling auras (Brann, Baron
    Rivendare, Rhyssa …) and so on — taken from the engine and the active pack (its keywords and tags), not a fixed
    Classic list.
  - Effects test (ui/effects_lab.gd: now 18 Classic effects): every keyword, tag and kind of enchantment the active
    pack has, on any card type: minion, weapon, spell, hero, hero power, Secret/Quest, in hand and in play.
  - Many scenarios per card (now 3380 interaction tests for 2718 cards, mostly one each): a library of
    (a) generic scenarios applied to every card by its mechanics: play/enter (Battlecry, the sound, the line, the
    legendary music), attack (sound, line), take damage, die (Deathrattle, sound), be silenced, returned to the hand,
    copied, transformed, stolen, frozen, doubled by Brann/Rivendare, buffed by an aura at each board position, a
    Secret against it, its targets; (b) hand-written tricky interactions per card (e.g. Supercollider with its
    neighbours, Swamp King Dred with Mayor Noggenfogger and Misdirection, Mass Hysteria on one side only). Each
    scenario: a playable scene, what to do and what should happen, and a mark passed / failed / note.
  - A walk through a whole pack: card after card, its scenario list and the checklist (enter, attack, death,
    sounds, lines, animations), the marks kept and exportable (JSON) for an agent to fix the failed ones.
- Tournament chats: moved to 0.74.0 (the owner, 2026-11-20), see 2026-11-20-roles-and-sub-servers.md §4.
- 0.72.0 leftovers: the raw `fuse` line in the history after Magnetic; Zilliax's English text ("Magnetic" and "Divine
  Shield" on one line).
- The decks of every version: from the owner's browser run of ~/ClassicHS-local/prep/patches/hearthpwn_decks.js
  (hearthpwn_decks.json).
  The owner ran it on 2026-11-20: ~/ClassicHS-local/prep/patches/hearthpwn_decks.json — 1751 decks (1731 with a deck
  code, 20 without), HearthPwn builds 13…50 (launch … Rise of the Mech), every class, Standard and Wild from Old Gods
  on; each deck: class, archetype, rating, views, updated date, its HearthPwn build, the lists (build, format) it was
  among the top 4 of its class in.
