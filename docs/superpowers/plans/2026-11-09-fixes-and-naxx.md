# 0.51 fixes and 0.60 Naxxramas — the owner's list and who does what

Agreed 2026-11-09. Source of historical truth: the Hearthstone Wiki (hearthstone.wiki.gg: card pages with
their patch history, "Patch x.y" pages, old art and sound files). Fixes first (0.51.0), then Naxxramas (0.60.0).
The "Shared rules" of docs/superpowers/plans/2026-11-09-server-features.md are binding (worktree, tests, never
touch port 7377 / the owner's DB / user data, i18n in 8 languages, commit trailers, no push, report in Russian).
Ports for local servers: R 7461–7469, V 7471–7479, A 7481–7489, N 7491–7499.
Blizzard assets (art/original, art/custom, downloaded sounds) stay local: never in git, never in a distributed
pack (the `local` sets of tools/pack.py), only in the owner's local packs.

## R — rules and card data (Classic pack, engine)
1. Defias Ringleader (Rogue) is 3/2 in our game; at the 2014 release it was 2/2 — check and fix.
2. Nozdormu: "Players only have 15 seconds to take their turns" does nothing — make it work everywhere: online
   (server timers), and also local games (training vs the bot, code play), where the rope/timer then shows.
3. Sacrificial Pact must be able to destroy Lord Jaraxxus (a Demon hero), as in 2014.
4. Bane of Doom: 2 damage in the original? Check and fix.
5. Eaglehorn Bow: only friendly Secrets revealed, or any? Check the 2014 text and behaviour and fix.
6. Cards renamed or changed since 2014 must be as at release (e.g. Succubus, later Felstalker): names in all
   languages, texts, stats. Go through the whole Classic set against the wiki's history; list every change.

## V — the table: animation timing and looks (client; the engine only where the event order needs it)
1. A weapon's durability below its maximum is red, like a damaged minion's health.
2. Effects during an attack happen in the middle of the lunge, not after it: Truesilver Champion's heal,
   attack-triggered Secrets (Explosive Trap, Freezing Trap, Misdirection, Noble Sacrifice, Vaporize): the attack
   pauses mid-way, the Secret reveals, its effect plays fully (Noble Sacrifice: the defender appears and the
   attack goes into it, animated; Freezing Trap: the attacker returns to the hand; Vaporize: the attacker is
   destroyed on its way to the hero), then the rest.
3. Divine Shield: the shield pops and the attacker takes its damage at the same moment, not one after another.
4. The Spell Damage effect on a card: much more beautiful, really magical sparkles (a shader).
5. A sleeping minion lets out green Z, not white.
6. Hidden effects on a minion (Corruption, other enchantments) get a mark on the minion and are listed in the
   hover/long-press card view on the board, readable.
7. Discarded cards fly up (out of the hand), not down.
8. A card copied from the opponent's hand (Mind Vision and the like) comes from the opponent's hand, not from a deck.

## A — original 2014 art and sounds (local assets + the client's playback)
1. The custom art set: the art as at the 2014 release for every card whose art changed since (Succubus and the
   others); keep the newer art only for the Druid Choose One variants. Find the old art (wiki file histories,
   HearthstoneJSON, other archives), download it locally, rebuild the owner's local custom pack.
2. Sounds: find and download the original card sounds (play, attack, death, special) and hero lines (greetings,
   emotes, errors, …) — English at least, the other supported languages where they exist — and the generic
   effect sounds (hits, missiles, …). Pack them into the owner's local pack (a local sound set / voice), and make
   the client play them: a minion's play/enter, attack, death; a spell's sound; hero emotes and lines; impacts.
3. The same for the Naxxramas cards (FP1_*) for part N.

## N — Naxxramas (a new game pack, 0.60)
A separate game: all Basic and Classic cards plus every Naxxramas card, each as it was at Naxxramas's release
(July 2014; check the balance changes between the launch and then). Engine support for the new mechanics
(Deathrattle-heavy cards, Baron Rivendare, Kel'Thuzad, Loatheb, Feugen/Stalagg, Maexxna's Poisonous, Mad
Scientist, Undertaker, Duplicate, Avenge, Poison Seeds, Reincarnate, …), Lua scripts, card tests, deck
templates, bots able to play it, the simplified 2D art set generated for the new cards (Codex, as Neonfall's
art; the other sets reuse the Classic pictures), built by tools/build_packs.sh and CI, bundled on the server.
