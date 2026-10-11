# Classic HS

A fan remake of **Hearthstone Classic** as it was in June 2014, before Naxxramas: all 382 Basic and Classic cards, nine classes, the original tutorial, a bot, and online play with a friend straight from the browser — without servers.

**▶ Play: https://pycz2.github.io/classichs/** · [Changelog](CHANGELOG.md) · [На русском](#на-русском)

![A match](media/screens/en/match.png)

## Features

- **All 382 cards** with original names, values and mechanics: Secrets, Choose One, Overload, Combo, Enrage, Deathrattle, auras, transformations and more.
- **Training** against a simple bot of any class; works offline.
- **Online play without a server.** WebRTC connects two browsers directly (public Google STUN). One player creates an invite code, the other answers with a code; the codes go through any messenger. Both games run the same deterministic engine in lockstep and check the game state after every move. 75-second turns with the rope.
- **Tutorial** like the original: six missions as Jaina against Hogger, Millhouse Manastorm, Lorewalker Cho, King Mukla, Hemet Nesingwary and Illidan Stormrage.
- **Collection and decks:** every card unlocked, unlimited decks saved in the browser, Hearthstone-compatible deck codes (import and export).
- **Deck tracker** (your deck, cards left with the chance to draw each one, what the opponent played) and the **full move history** of the match.
- **Debug table:** set up any position in JSON and play it against the bot or for both sides.
- **8 languages** (English, Русский, Deutsch, Français, Español, Português (Brasil), Italiano, Polski), synthesized sound and music, speech for emotes and legendary minions, 6 emotes and mute, screen shake toggle, fullscreen.
- **Own art:** every card, hero and hero power is drawn by code — no image files, a light download.

| | |
|---|---|
| ![Deck tracker](media/screens/en/tracker.png) | ![History](media/screens/en/history.png) |
| ![Collection](media/screens/en/collection.png) | ![Tutorial](media/screens/en/tutorial.png) |
| ![Online](media/screens/en/online.png) | ![Settings](media/screens/en/settings.png) |

## Build and run

You need [Godot 4.7.2](https://godotengine.org/) (standard build, no C#) and its export templates for the web build.

```sh
godot --path .                 # run the game
./run_tests.sh                 # run all tests (headless)
./run_tests.sh -- deck_code    # only tests whose "file:method" contains the text
tools/build_site.sh            # web build + landing page into build/site
tools/build_site.sh --publish  # ... and publish to the gh-pages branch
```

Other tools: `tools/extract_cards.py` rebuilds `data/cards.json` from HearthstoneJSON; `tools/gen_audio.py` synthesizes `audio/*.wav`.

## How it is built

| Folder | What is there |
|---|---|
| `engine/` | Deterministic game engine: entities with tags and enchantments, event queue, death phase, auras, legal actions, state hash. No floats, one seeded RNG. |
| `cards/` | One hook dictionary per card (battlecry, deathrattle, triggers, auras, cost changes…), by class. |
| `game/` | Match controller, bot, decks and deck codes, tutorial missions, settings, locale, sound, deck tracker. |
| `net/` | Transport (WebRTC data channel), signalling codes, session protocol (hello, start, actions with state hashes, emotes). |
| `ui/` | All screens, built in code; procedural art. |
| `tests/` | Over 640 tests: every card, engine rules, deck codes, network protocol, UI flows, random full-game simulations. |
| `site/` | The GitHub Pages landing page. |
| `docs/superpowers/` | Design specs and implementation plans with the decisions taken. |

## На русском

Фанатский ремейк Hearthstone Classic (июнь 2014): все 382 карты, девять классов, обучение как в оригинале, тренировка с ботом и игра с другом по сети прямо в браузере без серверов — коды подключения передаются через любой мессенджер. Коллекция, колоды и коды колод, дектрекер, история ходов, отладочный стол, 8 языков, звук и озвучка. Играть: **https://pycz2.github.io/classichs/**

![Матч](media/screens/ru/match.png)

## Legal

Classic HS is a non-commercial fan project and is not affiliated with or endorsed by Blizzard Entertainment. Hearthstone and the card names and texts are trademarks and property of Blizzard Entertainment, Inc. Card data comes from [HearthstoneJSON](https://hearthstonejson.com/). All art in the game is drawn by code. The code is under the [MIT License](LICENSE).
