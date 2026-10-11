# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions: [SemVer](https://semver.org/).

## [Unreleased]

## [0.12.0] - 2026-10-11

### Added
- Effects on the table: spells, Battlecries, Deathrattles and start and end of turn effects send bolts from their source to each target. At the hit every minion and hero shows what happened to it: a burst for damage, sparkles for healing, arrows for a buff or a debuff, a flash for a new keyword, ice, a Silence ring, transform smoke, a summon portal, a Deathrattle skull, a Battlecry flare, a swirl when control changes, a shield for armor.
- Changed numbers on cards grow for a moment with their gem.
- A card's race (Beast, Demon, Dragon, Murloc, Mech, Totem, Pirate, Undead) on a plate at the bottom of the card.
- An Immune minion glows white with sparks turning around it.

### Changed
- The Taunt shield follows the outline of the minion's portrait.
- "Your Turn" shows after the end of turn effects.

## [0.11.0] - 2026-10-11

### Added
- Six card backs to choose in the settings: Classic, Horde, Druid, Arcane, Gold, Night.
- Effects Lab in the Debug Table: any card on the table and in hand with its pop-up boxes; keywords, buffs, debuffs, auras, damage, Silence, sleep, cost changes and glows can be switched on and off in any of the 8 languages.

### Changed
- The table changes at the moment of the hit: numbers, shields and deaths show when the attacker touches its target or the spell's bolt arrives, not before. A dying minion fades out with its last numbers.

### Fixed
- In the web version a white box stood above the menu title instead of the dragon.
- The cards on the game's page are drawn by the game itself and look as they do in the game.

## [0.10.0] - 2026-10-11

### Added
- Every card now has its own generated picture.
- Card text is laid out by hand for every card in every language: the lines, the font size and the position. A check makes sure no text goes past the frame or onto the stones; lines are even, numbers stay with their words, keywords are not split.
- Card Lab (in the Debug Table): one card in all 8 languages at once with its frames and a list of problems; sizes, position and lines can be changed and saved.
- Minions show their changes in pop-up boxes: buffs with the card that gave them, auras, set values, gained keywords, Frozen, Silenced. Keyword boxes also in the collection and in deck building.
- Legendary cards: a straight gold dragon frieze along the card's top edge.
- The loading splash in the current menu look.

### Changed
- The sword behind the attack stone sticks out to the top left, past the card's edge, away from the text.
- Stronger contrast of the numbers on cards, above all buffed and damaged values.

### Fixed
- The French text of some cards showed "|4(point,points)" instead of "point" or "points".
- On the game's page the title's last letter is no longer cut.

## [0.9.0] - 2026-10-12

### Added
- Main menu: a generated tavern background with a slow zoom, flying sparks, a vector gold title with a dragon and a running glint, buttons appear one by one.
- Generated backgrounds: the match is played on a stone board on a tavern table, deck choice and the collection sit in a tavern library, the other screens are on a darkened tavern.
- Alegreya font for the interface (Latin, Cyrillic, Greek) and wooden tavern-style buttons with rounded corners and a gold frame; rounded input fields, gold sliders.
- Card texts always fit the frame: the font size is fitted by measuring for every card in every language. Keywords in bold.
- Keyword explanation boxes beside the enlarged card.
- A sword behind the attack stone, a compact generated dragon on legendary cards.
- The hero power flips over after use; the "End Turn" button glows green when there are no moves left.
- Rarity filter in the collection and in deck building.
- Deck lists like the original: a strip of the hero's portrait behind the deck name, a strip of the card's art in the deck's card list, the cost on a crystal, the deck fill as a bar.
- The changelog opens in the game's language.
- The game can be installed as an app (PWA) and played offline after the first load.
- The game page shows screenshots in English.

### Fixed
- Repeated or too frequent opponent intents no longer load the board; the history pop-up card is not recreated on every mouse move; the mulligan confirmation yields to the timer and to a lost connection; a dragged card stays on top of the board.

## [0.8.1] - 2026-10-11

### Fixed (after review)
- In online games, the timer could end a new turn on its own while the opponent's turn animation was still playing.
- Right-clicking while dragging a card now cancels the drag without errors.
- Hand cards are no longer drawn on top of settings, menus, the mulligan and the game over screen.
- A minion returned to hand or transformed now changes in place instead of "dying" and being replaced by a new card from the deck.

## [0.8.0] - 2026-10-11

### Added
- A table like the original: oval minions with an attack stone and a health drop, a stone Taunt shield, a golden dragon over legendaries, card frames with a name ribbon and parchment, arched hero portraits with a class crest.
- Animated effects on the table: Windfury, Divine Shield, Stealth, Freeze, sleep, triggers, Deathrattle, auras, Enrage, spell damage, Silence.
- Card dragging: the card follows the cursor, minions spread apart to make room for the insertion spot, curved arrows for spells, attacks and the hero power. Click-to-select still works too.
- Animations: drawing a card from the deck, playing a card (the opponent's card flips over midway), spell flight, minion and hero attacks, hero power, death, return to hand, mulligan, secret reveal, a "Your turn" banner, lines with a "talking" hero. The bot waits for animations to finish.
- Fan-shaped hand: the card under the cursor rises and grows.
- The deck by the hero: thickness reflects the number of cards, the exact number shows on hover.
- Gear menu in the top right corner: history, deck tracker, settings, concede. Emotes are on right-click on your own hero, "Squelch" is on the opponent's hero.
- History strip on the left: pictures of played cards, the card on hover, the text history on click.
- In online games you can see where the opponent is looking: a raised card in their hand, their red arrow, a highlighted minion.
- Card images: generated illustrations (local Codex), original art (local play only) and your own sets, any folder in `art/`; chosen in settings. Where there is no image, drawn art is used, unique for every card.
- Animation speed setting: from normal up to 4 times faster.
- A basic deck for each hero on first launch.
- Class icons in the collection, hero selection and opponent selection; cost filters are mana crystals.
- A game page in 8 languages, with card images, hero portraits, a fan of cards, sparks and counters.

### Changed
- New tavern-style music: plucked lute and harp, flute, pad, bass, tambourine and shaker, echo and reverb. The menu has a calm waltz, battles have three different tracks of 60-90 seconds each. Every match starts with a track different from the last one, and when a track ends the next one plays.
- Mana crystals instead of the "Mana 3/5" text.

## [0.7.0] - 2026-10-11

### Added
- A game page on GitHub Pages: https://pycz2.github.io/classichs/ — an animated header, features, a screenshot gallery, Russian and English; the game can be launched right on the page.
- `README.md` with screenshots, features, build instructions and the project structure.
- `tools/build_site.sh`: builds the site and publishes it to the `gh-pages` branch.

### Changed
- The example on the debug table is now a showcase position: a secret, a weapon, Taunt, legendary minions, a full hand.
- The Russian lines of the first mission's boss use the official name "Hogger".

### Fixed
- Characters missing from the font were shown as squares: minion icons (Deathrattle, trigger, Silence) are now vector, the arrow is ASCII. A test checks that the font contains every interface and translation character.

## [0.6.0] - 2026-10-11

### Added
- Interface in 8 languages: English, Русский, Deutsch, Français, Español, Português (Brasil), Italiano, Polski. The default language is the system language; the language can be changed in settings instantly, without a restart.
- Settings screen (from the menu and from a match): language, music, sound and voice volume, voice-over, screen shake, full screen, player name.
- Vector art for every card, hero and hero power: a motif based on name, race, type and class (fire, ice, yeti, sheep, murloc, weapon and others).
- Table event sounds and two tunes (menu and battle); all sounds are synthesized, with no external files.
- Voice-over with the system voice in the interface language: names of legendary minions and new heroes, emotes, lines of the tutorial bosses.
- Changelog: clicking the version in the menu corner opens the entire change history of the game.
- Deck tracker in a match: your deck, remaining cards with the chance of drawing each next, cards the opponent has played. Each view can be hidden; the choice is remembered.
- Turn timer in online games: 75 seconds, a fuse burns during the last 15 seconds; when time runs out the turn ends by itself.

### Changed
- The turn history marks the start of a turn by event, not by text; the history panel no longer jumps down while the player reads old entries.
- Desync reasons and the default player name are translated.

### Fixed
- The "Concede" button did not become "Menu" after the game ended.

### Fixed (after review)
- After opening, the turn history shows new turns.
- Changing the language in a match also changes the deck tracker and history titles, the bot name and open windows.
- Long card texts no longer overflow the frame.

## [0.5.0] - 2026-10-11

### Added
- Tutorial: six missions as Jaina, like the original — Hogger, Millhouse Manastorm, Lorewalker Cho, King Mukla, Hemet Nesingwary, Illidan Stormrage.
- Step-by-step hints, boss lines, rules for the first missions (you cannot lose, you cannot end the turn with unspent mana or an unused attack), the hero power unlocks in the fifth mission.
- Tutorial boss cards: Hogger SMASH!, Barrel, Stomp, Will of Mukla, Transcendence, Flames of Azzinoth, Flame Burst and others.
- Reward screen after a victory; tutorial progress is saved, completed missions can be replayed.

## [0.4.0] - 2026-10-11

### Added
- Online play in the browser without a server of our own: WebRTC directly between browsers, Google's public STUN. The host creates an invite code, the guest replies with an answer code; the codes can be passed through any messenger.
- Match synchronization: both sides verify the game state after every turn; on a mismatch, a wrong game version or a dropped connection a clear message is shown.
- Player name (visible to the opponent), 6 emotes and a "squelch opponent" button.

### Fixed (after review)
- In online games both players choose the mulligan at the same time.
- More reliable connection across different networks: the game waits until the browser finds an external address; there is a connection timeout with a hint.
- Clear messages: "opponent left", "different game version", "different card data", "desync".
- Emotes cannot be sent more often than once every 1.5 seconds; "squelch" immediately hides the emote being shown.

## [0.3.0] - 2026-10-11

### Added
- Collection: all 382 cards, pages of 8 cards, class tabs, cost filter, search, an enlarged card on hover.
- Decks: unlimited number, create, edit, copy, delete; Hearthstone rules (30 cards, 2 copies, 1 legendary, only your own class and neutral cards).
- Decks are saved in the browser and persist after a restart; a corrupted file is not lost but set aside as `decks.bad.json`.
- Hearthstone deck codes: export in the Classic format; import of Classic, Standard and Wild codes, including old 2014-2016 decks with original cards and text copied from the client.
- Practice: choose your own deck; an incomplete deck cannot be started.

### Fixed (after review)
- A code import error is shown in the import window.
- A deck with a vanished card opens and can be edited; the player is told if the deck file was corrupted (a copy is saved).
- Deck codes with other hero skins (Magni, Medivh, etc.) and codes from text with a title on the first line are imported.
- The deck is saved after every change, not only on the "Done" button.

## [0.2.0] - 2026-10-11

### Added
- Main menu, class selection for practice, basic decks for nine classes.
- Game table: heroes, hero powers, weapons, secrets, boards, hands, mana; mulligan, Choose One, Tracking choice, game over screen.
- Mouse controls: card → option → place on the table → target; attack; hero power; a tooltip with an enlarged card.
- Simple effects: floating damage and healing numbers, a shadow of a dead minion, screen shake on heavy damage.
- Practice bot: tries actions on a copy of the game and picks the best one.
- Turn history during a match: all turns from the start, with no length limit; cards the opponent drew are hidden.
- Debug table: a scenario in JSON, card search and adding to hand, board or deck; play against the bot or as both sides; a "Position → JSON" button.

### Fixed (after review)
- A minion can be placed between others by clicking an adjacent minion.
- The history does not show the opponent cards discarded by Tracking.
- The debug table reports wrong field types in a scenario and does not start a broken match.
- Conceding a match requires confirmation.
- The bot thinks faster in large positions.

### Fixed
- A secret counts as a spell: it is seen by Mana Wyrm, Antonidas, Pyromancer, Gadgetzan, Violet Teacher, Mana Addict; Counterspell cancels a secret.
- Shadow Madness: the stolen minion can attack even if it attacked on its owner's previous turn.
- Tracking does not discard cards the player has not seen.
- Mulligan: the result does not depend on the order in which the players confirmed their choice (important for online play).
- You can concede at any moment, including during the opponent's turn and during the mulligan.
- Scenarios preserve the cost of cards in hand, the hero state and the played minions counter; a scenario error gives a message, not a crash.
- Lightspawn does not depend on aura order; Conceal does not remove a minion's own Stealth; Snake Trap does not trigger on a full board.
- An invalid action (for example, from the network) is rejected without changing the state.

## [0.1.0] - 2026-10-11

### Added
- Godot 4.7 project skeleton and a test runner.
- Data for 382 collectible cards of the Classic format (June 2014), tokens and tutorial cards in 14 languages.
- Engine: match start, mulligan, The Coin, turn, mana, Overload, Fatigue, card burning, Frozen thawing.
- Engine: full match history (`history`) — every action and all its events from the start of the match.
- Engine: playing cards, Battlecry, Combo, Choose One, secrets, weapons, attacks, Taunt, Stealth, Windfury, hero power, list of legal actions.
- Engine: scenarios — building any position from JSON and saving the current position to JSON (the basis of the debug table).
- Cards: hero powers of all 9 classes, INFERNO!, Mind Spike, Mind Shatter, The Coin.
- Cards: neutral Basic (43).
- Cards: neutral Classic COMMON (40).
- Cards: neutral Classic RARE (36).
- Cards: neutral Classic EPIC (11).
- Cards: neutral legendary, reward and promo cards (27) and their tokens: Bananas, Dream cards, Power Chord, Gelbin's inventions, Healing Totem.
- Cards: Druid (25) and Choose One variants.
- Cards: Hunter (25), Hunter secrets, Tracking.
- Cards: Mage (25), Mage secrets.
- Cards: Paladin (25), Paladin secrets.
- Cards: Priest (25).
- Cards: Rogue (25), Combo.
- Cards: Shaman (25), Overload.
- Cards: Warlock (25), Lord Jaraxxus.
- Cards: Warrior (25). All 382 collectible Classic cards are implemented.
- Completeness check: every card with an effect has a hook; 1000 random matches without errors; the engine works in the web build, the hash matches the native one.
