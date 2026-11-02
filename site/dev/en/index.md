# Make card games for {name}

{name} is an engine for card games of the Hearthstone kind: two champions, mana that grows every turn, minions on a board, spells, weapons, traps. The engine knows only these general rules. A **game** — its cards, what each card does, its champions, names, art, sounds, music, look and ranks — comes in one file, a **game pack** (`.cardpack`). Classic 2014 is one pack; **Neonfall**, a rainy cyberpunk game with three champions and 60 cards, is another. Yours can be the next.

> A pack runs everywhere {name} runs: in the browser, on Windows, macOS, Linux and Android, and on a game server. The same pack with the same moves gives the same game on every one of them.

## What you need

- A text editor. A pack is JSON files and small Lua scripts; no compiler, no game engine to install.
- Python 3 for `tools/pack.py` (it builds and checks a pack; standard library only). Get it with the source code: `git clone https://github.com/pycz2/classichs`.
- {name} itself to play your game: the browser version on this site is enough. For the quick command-line test run (`tools/pack_try.gd`) you also need Godot 4.7 and the rules engine (see [Testing](testing.html)).

## The path from an idea to a game

1. **Write the rules and cards.** `rules.json` says how big a deck is, how many cards a hand holds, what the champions are; `cards.json` lists every card with its numbers. A card without special text needs nothing else. → [Make your own game](packs.html)
2. **Give the special cards a script.** "When played, deal 1 damage", "your other minions have +1 Attack", "when this dies, summon a Cub" — each is a few lines of Lua against the engine's `g` library. → [Card scripts in Lua](lua.html), [Engine API](api.html)
3. **Name everything in every language.** Card names and texts, your own names for the mechanics (Neonfall calls Taunt *Firewall* and Battlecry *Boot*), classes, decks.
4. **Build and check.** `tools/pack.py build` makes the `.cardpack`, refuses broken references and writes the hashes; `tools/pack_try.gd` plays your game bot against bot and shows any script error with its file and line. → [Testing and validating](testing.html)
5. **Play it.** In the game: *Games → Import a game file*. Share the file with friends, or upload it to a game server.

## Start from an example

| Example | What it shows |
|---|---|
| **Tiny Duel** (on [Make your own game](packs.html#a-whole-pack-in-ten-files)) | The smallest real game: two champions, eight cards, two decks, three script files. Copy it and grow it. |
| **Neonfall** (`packs/neon` in the source) | A complete original game: 73 cards, three starter decks, eight languages, its own art, sounds, synthwave music and interface theme (`ui/theme.json`). Every script example on these pages is one of its cards. |
| **Classic 2014** (`packs/classic`) | 534 cards, every Hearthstone Classic mechanic in Lua, six tutorial missions, the 2014 ranked ladder. Its `recipe.json` builds the pack from data kept elsewhere in the repository. |

## These pages

| Page | |
|---|---|
| [Make your own game](packs.html) | What a pack is, every file and its fields, building it, loading it into the game or a server, versions and hashes, limits, the tutorial. |
| [Card scripts in Lua](lua.html) | The language as the engine runs it (and what it leaves out), how and when each hook runs, worked examples from a vanilla minion to a trap, debugging. |
| [Engine API (g.*)](api.html) | Every hook and every `g.*` function with its arguments, made from the engine's own source, so it is never out of date. |
| [Testing and validating](testing.html) | What `pack.py check` reports, a quick bot-vs-bot run, the Debug tools in the game, the server's check of an uploaded pack. |
| [Architecture](architecture.html) | How the whole of {name} is built: an interactive block diagram of the system, every block opened up (its parts, data and protocols), and step-by-step flows — a card is played, a server game, a bot decides, a pack loads, code play, the web update, deploy — each step linked to its line of code. |
| Reference (English) | The format as the engine and tools implement it, section by section: the pack format, `rules.json`, `cards.json`, visual effects, the Lua subset, hooks and `g`. |
