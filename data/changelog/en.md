# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions: [SemVer](https://semver.org/).

## [Unreleased]

### Fixed
- A game no longer freezes for half a minute in the big games, The Witchwood for one, the first time a card deals damage or heals (Kobold Librarian hitting its own hero did it) or a card without a picture has to be drawn. At that moment the client worked out the drawn pictures of every card of the game at once; that now takes a split second.

## [0.71.0] - 2026-11-12

### Added
- An FPS counter: the "FPS counter" switch in the settings (off by default) shows the frames per second in small print in the top left corner of every screen.
- Opus sound: all sounds, voice lines and music of the packs are now Opus, and the client plays it on every platform, the browser included. Higher quality: voice 48 kbps, sounds 96 kbps, music 128 kbps.
- Packs can give a card sounds by role: aiming (plays while a target is chosen), missile, impact, trigger, a secret's reveal, a quest's progress, a weapon breaking; music for the mulligan, victory and defeat. A card without its own sound plays the common one.

### Fixed
- The menu music is in the built game again: it was left out of the builds.
- Hero Powers, a secret's reveal, a quest's progress and the start of a turn sound again in a match; the "your turn" sound plays only on your turn.

## [0.70.0] - 2026-11-12

### Added
- **Eleven new games, the expansions after Naxxramas.** Each holds every card of the games before it (Basic, Classic, Naxxramas and on in order), and every card is as it was on the expansion's release day: cost, stats, tribe, texts in 8 languages. Each game has its own deck templates of that time's meta (10 to 19), bots that play it, its own look and a set mark.
- Goblins vs Gnomes 2014 (cards as of December 8, 2014): Mechs, Spare Parts, Mega-Windfury, Mimiron's Head.
- Blackrock Mountain 2015 (April 2, 2015): Dragons and "if you're holding a Dragon" cards, Emperor Thaurissan, Nefarian.
- The Grand Tournament 2015 (August 24, 2015): Inspire, Jousts, upgraded Hero Powers.
- The League of Explorers 2015 (November 12, 2015): Discover, Reno Jackson, Brann Bronzebeard.
- Whispers of the Old Gods 2016 (April 26, 2016): C'Thun and his rituals, N'Zoth, Yogg-Saron and the twelve Classic card changes of that day.
- One Night in Karazhan 2016 (August 11, 2016, the first wing): the Portals, Medivh and Atiesh, Prince Malchezaar, Barnes.
- Mean Streets of Gadgetzan 2016 (December 1, 2016): Jade Golems, Kazakus, cards of three classes at once.
- Journey to Un'Goro 2017 (April 6, 2017): Quests and their rewards, Adapt, Elementals, Dormant minions.
- Knights of the Frozen Throne 2017 (August 10, 2017): the Death Knight hero cards, Lifesteal, a Zombeast made of two Beasts.
- Kobolds & Catacombs 2017 (December 7, 2017): minions straight from the deck onto the board, Spellstones that grow, Legendary weapons.
- The Witchwood 2018 (April 12, 2018): Echo, Rush, cards for decks of only even or only odd costs (Genn and Baku).
- The new games are not in the client builds, so the desktop, Android and web apps did not grow. Download a game from a server or install the file ClassicHS-x.y.z-<game>.cardpack from the release page. Each game stands alone and needs no other: it carries the pictures of the older cards, and the new cards have simple drawn pictures.
- Cards in the hand whose condition holds right now glow yellow: Combo, "if your deck has no duplicates", "if you're holding a Dragon" and more.
- Expansion cards show their set mark, also beside the big card; the collection has a set filter.
- The board and the match history show the new mechanics: a Joust with a card of each deck, a Quest's progress beside its hero, Dormant minions, an extra turn, hero cards with their Armor, Lifesteal, cards of several classes.
- In your own local pack with sounds, Legendary cards have their own music: it plays when the card is played, and the background music goes quiet meanwhile.

### Changed
- The turn's fuse burns towards the End Turn button, as in Hearthstone.
- Each side has at most 5 Secrets, as in Hearthstone since 2014. A sixth Secret can't be played from the hand, Mad Scientist with five leaves his Secret in the deck, and Kezan Mystic destroys a Secret instead of taking it.
- A pack may weigh up to 1 GiB (2 GiB unpacked), in the client and on a server, a player's pack too. The server reads a pack from disk in parts and never holds it in memory whole.
- The server installs its bundled games in the background: after an update it takes players at once, and a new game shows up in the list as soon as it passes its check.

### Fixed
- A bot that can't make its move (for example, after an error in a card's script) no longer repeats it endlessly: it stops with one error.
- The German text of Classic's upgraded Paladin Hero Power no longer shows empty brackets.

## [0.67.0] - 2026-11-11

### Added
- Bots in tournaments: the creator adds bots of a chosen level (Easy, Medium, Hard, Super hard — two of each on the server) up to the player limit and can remove them. Bots bring decks of the game, accept their matches, ban, pick a deck and play every game to the end; their matches run at the same time. The creator can always watch the tournament's matches; replays are kept. A bot busy in another tournament is free only when that one is over.

## [0.66.0] - 2026-11-10

### Added
- Admin panel, a player's page: per game — the rank (rank, stars, Legend, streak, hidden MMRs; reset to the season's start), the game settings, the decks (their cards, copy the code, add from a code checked by the rules, rename, delete, copy to another player); the Arena run (wins, losses, reset, end); the tag. Changes reach the player at once when online and go to the log. A deck code (Hearthstone format) can be copied wherever the admin panel shows decks: statistics, a match's page, tournament entrants.

## [0.65.0] - 2026-11-10

### Added
- Super hard on the server: the admin's bots can play at it, and a ranked Legend who waits long for an opponent gets a Super hard auto-bot instead of a Hard one (3 seconds a decision on the server).

## [0.64.0] - 2026-11-10

### Changed
- The Super hard bot in training is stronger: it searches a plan for the whole turn (a beam search), looks at the opponent's answer and its own next turn, and judges positions with a model learned from 2000 games. It wins 60% of games against Hard (400 games over 19 decks) and 72% against Medium. As before, it thinks up to 6 seconds a decision and is done 10 seconds before its turn ends.

## [0.63.0] - 2026-11-10

### Added
- Admin panel, statistics: a class-versus-class matrix (the row's win rate against the column, the games, red to green, mirrors on the diagonal, each class's total); earlier periods to choose — yesterday, any past day, week, month, year. Day statistics of decks and cards are kept 400 days; the statistics take almost half the space they did.

## [0.62.0] - 2026-11-10

### Added
- Admin panel: the server's version in the corner of every page; the dashboard shows how much space the database and the pack store take.
- Admin panel: any game's replay right on its page — Play opens the replay at the bottom as in the client (a cut-down web build with only the replay view; it gets the game's pack from the server). It closes with its cross or on another page.
- Admin panel: HSReplay-like statistics per game — class win rates by mode and rank, the top 20 decks and the top 5 of each class, cards (in how many decks, copies, deck win rate, how often played and the played win rate, the mulligan: kept or replaced), for this hour, day, week, month, year and all time, with charts and the cards' English names. Updated after every game; the games played before come from their replays.

## [0.61.0] - 2026-11-10

### Added
- The server's bots play every game on the server, not only Classic: any bundled or uploaded game. When no opponent is found within the time set in the admin panel, a bot comes with a deck from that game's templates (or a class's starter deck) and plays with its cards.
- Training has the Super hard bot back — the first hard bot: it weighs every action in each of up to 200 guesses of the hidden cards and the opponent's whole turn. It thinks while more than 10 seconds of its turn are left, then takes the best it found and plays the turn out quickly, so it never hangs or misses a turn.

## [0.60.0] - 2026-11-10

### Added
- **A new game, Naxxramas 2014**: every Basic and Classic card and all 30 Curse of Naxxramas cards with their tokens, each as at the adventure's release (July 22, 2014): Undertaker +1/+1, Sludge Belcher 3/5, Reincarnate for 2, no Undead tribe, Eaglehorn Bow grows only with friendly Secrets (patch 1.1.0.6024).
- New mechanics in the engine: double Deathrattles (Baron Rivendare), Poisonous (Maexxna), the minions that died this turn come back (Kel'Thuzad), the opponent's spells cost more (Loatheb), Feugen and Stalagg, Mad Scientist, Poison Seeds, Reincarnate and more.
- 10 deck templates of the 2014 meta, bots that play Naxxramas, its own look (menu, board, result screens) and simplified 2D art for the new cards; it installs as a normal pack and is on the server.

## [0.51.0] - 2026-11-10

### Changed
- Classic and Basic cards are as in June 2014 (the last patch before Naxxramas), from the game's data of the time and the Hearthstone Wiki's history: Defias Ringleader 2/2; Bane of Doom deals 2 and summons one of the six demons of 2014; Eaglehorn Bow grows with any revealed Secret; Laughing Sister costs 3; Succubus is back (not Felstalker); Shadow of Nothing goes at the end of the turn; the 2014 Mechs and Undead have no race; 37 card texts and 40+ names as in 2014 in every language.
- Nozdormu works: while he is on the board a turn lasts 15 seconds — on a server, in training with the bot and in code play (with the rope).

### Added
- The original card and hero voice in your own local pack: a minion's sound and line when it lands, attacks and dies, spell sounds, the heroes' emotes and lines (not enough mana, can't attack, the start). The pack is built locally (tools/fetch_original_sounds.py, pack.py --sound-set and --voice) and never sent anywhere.
- In your own local art pack: the 2014 art of the cards whose art changed later (Succubus, Windfury Harpy, Secretkeeper, Eviscerate, Bite, Deadly Shot, Headcrack).

### Fixed
- Effects during an attack happen half-way: the attack pauses, the Secret reveals and acts fully (Noble Sacrifice — the attack goes into the Defender, Misdirection — to the new target, Freezing Trap — the attacker flies back to the hand, Vaporize — the attacker dies on its way, Explosive Trap), Truesilver Champion's heal half-way too.
- Divine Shield pops at the same moment the attacker takes its damage.
- A weapon's durability below its card's is red, like damaged health.
- Spell Damage on a minion has a new magical effect; a sleeping minion lets out green z; hidden effects (Corruption and others) are marked on the minion and described in its big card.
- Discarded cards fly up and burn; a card copied from the opponent's hand comes from that hand.
- A player's pack on a server may weigh up to 128 MiB (as in the client).

## [0.50.0] - 2026-11-09

### Added
- **Tournaments** on a server: anyone creates one from the game menu's Tournaments. Formats: elimination (one or two lives, with a losers bracket), Swiss, round robin, teams (Scheveningen). Conquest or Last Hero Standing series, Bo1 to Bo7, with or without bans. Sign-up, decks of different classes, the bracket, places with medals for the top 3, tabs Upcoming, Finished, Closed. A minute for each match step (accept the game, ban, pick a deck).
- **Replays**: every server game is kept; the last 10 games are in the game menu's Replays. Watch them with seeking by turn and action, both hands face up. Export and import a replay file.
- **Watching** a friend's game: Watch in the friends list. In tournaments the creator and the players who are out may watch matches with both hands open, when the creator allows it.
- **Registration by invite key**: the admin turns it on in the admin panel, makes keys (a note, how many uses) and sees who came with which key.
- In the admin panel: the wait before a bot comes instead of a live opponent (0 to 10 minutes), the invite keys and tournaments pages, a game's replay download.
- Parallax in the main menu: the picture, the particles and dust move with the mouse or the phone's tilt.

## [0.42.2] - 2026-11-05

### Changed
- Touchscreen: a card can no longer be dragged straight out of the small hand. The first tap only opens the hand (as in 0.42.0).

## [0.42.1] - 2026-11-05

### Fixed
- Searching for a server game with a deck kept on the server never ended: the server refused the deck because of a note field. Now the client does not send it, the server takes such decks, and a refusal stops the search.
- Server games (Arena, ranked, casual) froze when a minion came onto the board: the numbers in the server's answer did not match the ones on the table.
- A full deck no longer covers the game timer: the pile grows down.
- A minion let go on the board during an animation stands in its slot at once and waits there, instead of going back to the hand.
- Touchscreen: you can drag a card out of the small hand at once, without a tap to open it first.

## [0.42.0] - 2026-11-03

### Added
- Touchscreen (Android and browsers): the hand waits small in the bottom right; a tap opens it, a tap beside it closes it.
- Touchscreen: a tap on a hand card only shows it. A card is played only when you drag it above the bottom third of the screen; let go lower, it goes back to the hand.
- Touchscreen: every list (decks, collection, games, server, friends, chat, history and more) scrolls with a finger, also when the drag starts on a button; a quick swipe flings on.
- Touchscreen: a long press shows the tooltip (the cards in a deck, yours and the opponent's; why a deck cannot be played; what the buttons do) and is the right click (your hero's emotes).
- Touchscreen: in the collection and the Arena draft a tap adds the card; a long press only shows it.

### Changed
- The deck on the table is clearly thicker with many cards and thinner with few.

### Fixed
- A minion you put down stands in the slot you chose while its Battlecry acts, and does not move after it (it used to go back to the hand for a moment and fly back).

## [0.41.1] - 2026-11-03

### Fixed
- Upload a game to a server now offers your own build of a game the server has (the same rules, your own pictures): Classic with your own art set, say.

## [0.41.0] - 2026-11-03

### Added
- A tutorial for Neonfall: six missions with their bosses, from the first card to all of the game's mechanics, in eight languages.
- Adding a game from a file shows what happens: reading the file with a progress bar, then the checks.

### Fixed
- Russian letters did not show in the Classic pack: its title font has no Cyrillic. Missing letters now come from the client's font, and the game menu's title is written in capitals.
- A minion with a Battlecry first lands on the board (the others make room), then its Battlecry happens, then it settles.
- A card drawn by another card (Novice Engineer) comes from the deck, not from the minion.
- An imported pack's own picture set (built from its maker's folder) can now be chosen.

## [0.40.0] - 2026-11-03

### Changed
- The game is called **Classic Heroes Showdown** (short Classic HS). It is now an engine for card games: each game is a pack with its own rules, cards, look, music, tutorial and deck templates.
- A new menu: Play, Settings, Exit. Play → Direct (the game library, then the chosen game's menu in its own look) or Server (connections, login, the server's home with friends and the server's games).
- Global settings: language, volume, card back, animation speed, screen shake, fullscreen. Art and music sets are chosen per game (kept on the server in server mode); Debug tools are in the settings inside a game.
- Decks are kept per game; on a server they are the server's decks of that game, and local decks can be copied there. No ready-made decks in the list any more: a new deck starts from scratch or from one of the pack's templates.
- The tutorial and scene effects (rain, snow, embers) are now part of the pack. The tavern look moved into the Classic pack; the client itself looks neutral.

### Added
- Pack tools in the game library: build a game from a folder, check it (files, JSON, Lua scripts with line numbers, art, translations, tutorial), play trial bot games, install it.
- The site has a "For developers" section: making your own game, card scripts in Lua, the engine API reference, checking and testing, an interactive architecture map. The landing page is in the Neonfall style.
- Settings move over by themselves on update: art and music sets to Classic, servers to connections, your decks to their game.

## [0.32.0] - 2026-11-02

### Added
- Decks can be kept on the game server: the cloud mark on a deck. The deck is saved on every change and appears on your other devices after login.
- A new "Simple 2D" picture set for Neonfall.
- Phones: a long press on a text field opens a menu (Paste, Select all, Copy, Cut); the login password has a Paste button.

### Fixed
- Moves play in order, step by step: the opponent's card flies out of the hand, an arrow shows its target, and each effect is shown on its own (Arcane Missiles and Mad Bomber hit one by one). This works both ways and at a faster animation speed too.
- Mulligan: replaced cards go to the deck, new ones take their places, then the Coin appears, and the cards go into the hand in the same order.
- Android: a copied password could not be pasted into the login field.
- While searching for a server game only Cancel works: other modes, the Arena, logout and changing the game wait until the search is cancelled.
- The web version no longer loads an old cached version: a new version is taken on a normal reload.

## [0.31.0] - 2026-10-30

### Added
- Training against a smart bot at a level of your choice: easy, medium or hard. It is the same bot as on the server and sees only its own cards. It works on every platform and offline; the bot thinks in the background, so the game does not freeze.
- Server: a player who waits 30 seconds alone in a ranked, casual or Arena queue gets an auto-bot for one game. Its strength follows the player's hidden rating; in the Arena, the wins of the run.
- Arena bots take a random one of the three heroes; the easy bot picks cards at random, the medium one mostly the best, the hard one always the best for its mana curve.
- Hovering a card shows the cards it creates or summons (tokens, transformations, Choose One cards, the hero power).
- The deck editor shows the mana curve above the card list.

### Fixed
- Server bots no longer stop for minutes on a full board and no longer lose because of late moves. A move that arrives after the turn has ended is refused without a penalty, which also protects players on slow connections.
- The rules engine is faster: copying a game about 10 times, a move 3.5 times.

## [0.30.0] - 2026-10-26

### Added
- Code play (direct, without a server) now works not only in the browser but also on Windows, macOS, Linux and Android. Players on different platforms can play each other, for example a browser against Android.

### Fixed
- Firefox: Ctrl+V and Cmd+V did not paste into text fields, and a click on a field opened a "Paste" menu. Pasting works now, and the menu no longer appears.

## [0.29.2] - 2026-10-25

### Fixed
- Android: the app could not reach a game server — log in, register, play online, download games. The build lacked the internet permission; now it has it, and the build checks it.

## [0.29.1] - 2026-10-24

### Added
- Server admin: its own tab icon — the gold tile with the dark diamond of the panel's logo.

## [0.29.0] - 2026-10-24

### Added
- Bots on the server: the server runs its own players of Classic — ranked, casual and Arena — so there is always someone to play. The server admin has a new Bots page: how many, how strong (easy, medium, hard), which games, the schedule and pauses; start and stop them live; what each one does, its game as it sees it, its last decision and its log.
- Bots play fair: like any player, through the same protocol, and see only their own side; they weigh the opponent's hidden cards by probability.

## [0.28.4] - 2026-10-24

### Added
- A new picture set for Classic, “Photoreal”: all 534 cards photorealistic with very few details. Pick it in Games → Classic 2014 → Card pictures (or in the settings).

### Fixed
- Android: the game no longer hangs on its splash screen. The build compressed the built-in games (packs) inside the APK, and Android took minutes to read them; now they are stored uncompressed and the game opens in a few seconds.
- Browser: Ctrl+V (Cmd+V) in a text field pastes what is in the clipboard now. The first paste used to give the previous contents (or nothing), for example a password copied from a password manager.
- Android: the password field is marked as a password, so the keyboard and a password manager can offer the saved password; the server address gets an address keyboard.
- Phones: a text field rises above the on-screen keyboard; the keyboard used to cover the fields low on the screen, so you could not see what you typed. The hint in the server list no longer runs under the Close button.

## [0.28.3] - 2026-10-24

### Fixed
- Android: the game's rules library is built for 16 KB memory pages (Android 15 and newer phones). Such phones used to run the game in a compatibility mode or not at all.
- No default server any more: the game starts and plays without one; add a server later in Settings → Game servers (or with the server button in Online Game).

## [0.28.2] - 2026-10-23

### Added
- A new picture set for Classic, “Simple painted”: all 534 cards as painted illustrations with very few details. Pick it in Games → Classic 2014 → Card pictures (or in the settings).

## [0.28.1] - 2026-10-19

### Added
- A new picture set for Classic, “Cartoon 2D”: all 534 cards in a flat cartoon style. Pick it in Games → Classic 2014 → Card pictures (or in the settings).

## [0.28.0] - 2026-10-16

### Added
- A new game, Neonfall: cyberpunk in drowned Vesper Arc. Three champions (Iris Null, Mother Rust, Director Vale), 60 new cards, its own art, sounds, music, fonts and a neon look. It is the server's default game.
- A Games screen: pick the game, its art, sound and music sets, add your own game from a .cardpack file (in the browser too), delete downloaded ones.
- In direct play with codes, a friend can send you a game you lack: a consent dialog, a transfer with progress, an integrity check.
- Several game servers in the settings, each with its own login and friends. Logging in to the same account elsewhere closes the old session (“You logged in on another device”).
- The server serves games: queues, ranks and the Arena per game; a friendly game on a friend's own game, downloaded with consent.
- An Android signing check: python3 tools/android_keystore_check.py opens a page that checks the GitHub secrets and makes a new key.

### Changed
- The engine knows nothing about Hearthstone any more: the whole game — rules, cards, their logic in a small Lua, texts, art, sounds, ranks, timers — lives in a .cardpack. Classic 2014 became such a pack and was checked on 7833 recorded games: the results match bit for bit.
- The protocol of direct play is version 3: older versions cannot play with this one.

## [0.27.1] - 2026-10-15

### Fixed
- The Windows and Linux builds start again: the rules engine now ships next to the game. Windows is a .zip (ClassicHS.exe with the .dll next to it); the AppImage has it inside. Documentation images no longer end up in the game.

## [0.27.0] - 2026-10-15

### Added
- Game server: a new lobby in the style of the game — deck boxes with heroes, a Casual/Ranked switch, the rank medal with stars, a big Play button; the Arena with the ticket, big hero portraits, the draft and the run screen to 12 wins.
- The server login is remembered: the game logs in by itself at start. While you are logged in, every screen has a friends button: who is online, searching or playing, requests, chat windows over the game, and invites you can accept from anywhere.
- A new server admin panel: a live dashboard, an event log with filters (logins, messages, moves, errors), games with their moves in real time, accounts, conversations; dark and light themes.

### Changed
- All the rules of the game now live in one Rust module: it runs inside the game on every platform (as WebAssembly in the browser) and on the server; the game window only draws. The rules were checked on 7833 recorded games: the results match the old engine bit for bit.
- Server games: the server runs the game and sends each player only what that player may see — the opponent's hidden cards never reach your computer. The turn timer runs on the server; after a dropped connection you can come back into the game.
- Direct play with codes: both games check every move; if they differ, the game ends for both with a “something does not add up” message (nobody is banned). Older versions cannot play with this one.

## [0.26.1] - 2026-10-15

### Fixed
- In the downloaded game for Windows, macOS, Linux and Android, “Online Game” now works: you can play through a game server there. Direct play with codes stays in the browser version only.

## [0.26.0] - 2026-10-15

### Added
- A game server (experimental, optional): Online Game → “Through a game server”. An account with a password, casual and ranked games (the 25 ranks of 2014 and Legend, stars, a new season every month; a hidden rating finds an equal opponent), the Arena to 12 wins or 3 losses, friends by tag, messages, invites to a friendly game and blocking. The server checks every move with the game's own rules. The server address is in Settings → “Game server” (ws://localhost:7377 by default). The server itself (Rust, the server/ folder) is not hosted anywhere: you run it yourself; every release has server builds for Windows, macOS and Linux. Playing directly with codes stays as it was.

## [0.25.1] - 2026-10-15

### Fixed
- The opponent's Secrets show on the top of their portrait, like yours (they were under it).

## [0.25.0] - 2026-10-15

### Added
- Builds for every platform: each version gets a GitHub release with the game for Windows (.exe), Linux (.AppImage), macOS (.zip), Android (.apk) and the web build (.zip). The site links to it: "Download the game".

## [0.24.1] - 2026-10-12

### Changed
- Basic decks are gone from the deck lists: every class has a classic deck. A Basic deck appears only for a class without a classic one (none now). Unchanged Basic decks leave the saved decks once; changed ones stay.

## [0.24.0] - 2026-10-12

### Added
- Settings → Music set: generated or open (CC0) — medieval tavern tunes by RandomMind: "Minstrel Dance" in the menu, "The Old Tower Inn", "King's Feast" and "The Bard's Tale" in battle. The sounds stay the generated ones.

## [0.23.3] - 2026-10-12

### Changed
- The mulligan as in the original: the chosen cards fly into the deck, the new ones fly into their places and stay in front of you ("Waiting for the opponent…"); once the opponent has chosen, the Coin turns up beside them for the second player, then all the cards go down into the hand in the same order, and only then the first turn's card is drawn. The hand under the mulligan screen is hidden.
- The deck tracker button is under the menu button and no longer covers the opponent's mana crystals.

## [0.23.2] - 2026-10-12

### Changed
- A playable Combo card in the hand glows yellow instead of green once a card was played this turn (its Combo will work).
- The Coin always comes with its own animation — it spins in with a golden light and goes into the hand — also when the opponent finished the mulligan later, and for both players.

## [0.23.1] - 2026-10-12

### Fixed
- The button that mutes the opponent shows the state: "Mute", and "Unmute" while the opponent is muted.

## [0.23.0] - 2026-10-12

### Changed
- Mulligan: after Confirm the new cards come into the hand at once, without waiting for the opponent, and take the places of the replaced ones — the hand keeps the order of the mulligan screen; then "Waiting for the opponent…". Online games stay in sync: each player's mulligan shuffle uses that player's own random stream.
- The online mulligan timer has no fuse: in the last 10 seconds red numbers show under Confirm.
- What the opponent points at no longer hides your own glow: the green or yellow stays, with a faint red ring outside.
- A card burnt by a full hand burns with the shader only, without the rising triangles.

## [0.22.0] - 2026-10-12

### Added
- An order queue: the next move can be given without waiting for the last one's animation — play a card, attack, use the hero power, end the turn. Orders wait in a queue (marked yellow) and are carried out one by one after the animations, in order; whether an order is possible is checked after the ones already queued. If an order became impossible (the turn ended), the queue is cancelled with a hint. The tutorial has no queue.

### Changed
- The turn fuse burns without the dotted line of ash behind it.

## [0.21.1] - 2026-10-12

### Changed
- Online game: whatever the opponent points at glows red — minions, heroes, hero powers, weapons, Secrets and the raised card in their hand (only minions showed before, in white).

## [0.21.0] - 2026-10-12

### Added
- Arena rules: before the heroes, the host chooses for both "One deck for the whole Arena" or "A new deck for every game"; the second has a separate setting "Players may keep their deck instead of drafting again". With it on, after each game each player chooses "Draft a new deck" or "Keep my deck", and the opponent sees the player deciding. The guest waits for the choice and sees the rules; the score is in sight during a new draft.

### Changed
- Arena: Legendary cards come twice as often (2 % in a normal pick, 8 % in picks 1, 10, 20 and 30), Epic cards one and a half times as often (7.5 % and 27 %).

## [0.20.1] - 2026-10-12

### Changed
- The match result pictures are compressed: the game's download is about 61 MB again (64 MB in 0.20.0).

## [0.20.0] - 2026-10-12

### Added
- The Arena with a friend online: Online Game → Arena. Each player takes one of three heroes and drafts 30 cards like the 2014 Arena: three cards of one rarity per pick (Basic and Common count as one), Rare or better at picks 1, 10, 20 and 30, class cards one and a half times as likely, no limit on copies. The deck list is on the right, the mana curve at the bottom left, the opponent's progress at the top right (hero chosen or not, cards, ready; never the hero or the cards). When both press Ready, a series to three wins starts; after each game there is the lobby with the score; you can concede the Arena or exit to the menu at any stage.
- The result of a game from your side — Victory!, Defeat or Draw — over a semi-transparent picture of it (online games showed "Player N wins").

### Checked
- A draw: a Hellfire that kills both heroes is a draw, and both heroes shatter.

## [0.19.5] - 2026-10-12

### Fixed
- Site: the open source section showed “{tests}” instead of the number of tests.

## [0.19.4] - 2026-10-12

### Added
- A link to the site in Telegram, WhatsApp, Discord, Slack and other messengers shows a preview with the main screenshot of the game (a match), the title and a description.

## [0.19.3] - 2026-10-12

### Added
- Site: the game version and a “What's new” block (the latest changelog entries in the page language), an “In a match” section, questions and answers (requirements, phones, where decks are kept, playing offline, installing as an app, what online play sends, how to report a bug), an open source section; the changelog link opens the page language; on a phone the page no longer scrolls sideways.

## [0.19.2] - 2026-10-12

### Changed
- The site and the README now match the game: training with a choice of deck and bot hero, ten well-known Classic decks, the relay for online play, debug tools in Settings, emotes in the heroes' words, card art sets and backs; the online steps use the game's button names; outdated claims are gone (no servers at all, all art drawn by code).

## [0.19.1] - 2026-10-12

### Changed
- Site: new screenshots (history by turns, deck tracker, mission lessons, debug tools; the Russian page shows Russian shots), texts for the game as it is now, and the game's download size (about 61 MB). On a phone a tap enlarges a card in the fan and a double tap turns it over.

## [0.19.0] - 2026-10-12

### Added
- On the first run the game asks you to choose a language; the system's language is lit.

## [0.18.5] - 2026-10-12

### Changed
- Random damage to several targets (Arcane Missiles, Avenging Wrath, Mad Bomber, Multi-Shot, Forked Lightning and so on) flies one missile at a time; the target's health number drops with each hit.

## [0.18.4] - 2026-10-12

### Added
- Elusive: the minion is wrapped in a shimmering golden haze, and the word has its pop-up box (spells and Hero Powers can't target it).

## [0.18.3] - 2026-10-12

### Added
- Burnt cards (full hand) and fatigue damage show in the history on the left: their own tile with a picture and a note on hover.

### Fixed
- Tutorial: Lorewalker Cho can't be attacked while he has minions.

## [0.18.2] - 2026-10-12

### Changed
- Speech synthesis is gone: the game no longer reads names and emotes aloud; the Voice and Speech settings are removed. Heroes' lines show as text in speech bubbles with a tail pointing at the hero.

### Fixed
- A ticked box lost its background under the mouse.

## [0.18.1] - 2026-10-12

### Added
- Scene editor: Secrets and Weapon zones, a choice of who moves first, and tokens in the card list.

## [0.18.0] - 2026-10-12

### Changed
- The debug tools moved into Settings and became one screen with tabs: "Scene" (build a scene with the mouse: heroes, mana, damage, armor, hand, board, deck; the JSON beside it; the mode as radio buttons), "Interaction test" (ready scenarios for each of the 534 cards, 1108 in all: pick a card and a scenario and it plays in a real match with all effects and sounds), "Card test" and "Effects test".

## [0.17.1] - 2026-10-12

### Added
- On defeat the hero's portrait bursts into shards.
- The lightning and poison marks stand still and pop with a light sound when their effect goes off.

### Fixed
- Tutorial: "Next Mission" opens the notes as a screen of their own; the reward screen no longer blocks going on.

## [0.17.0] - 2026-10-12

### Added
- The move history on the left is split by turns ("Turn N" in the player's colour); hovering a move shows what it did and to whom: damage, healing, buffs, freezing, silencing, deaths, summons, weapon equips, plus the Battlecries and Deathrattles it set off. The opponent's hidden cards stay hidden.
- The deck tracker has its own button next to the menu: "Your deck" with card pictures, ×2, dimmed cards that are gone and each card's chance to be drawn; "Opponent played", a growing list with ×2.

## [0.16.2] - 2026-10-12

### Fixed
- Tutorial: after a win, "Next Mission" opened the notes under the reward screen and the screen locked up.

## [0.16.1] - 2026-10-12

### Added
- Under the End Turn button: the match time and, in online games, the time left in the turn.
- Everything on the table lights up under the mouse; a weapon turns over when it is not its hero's turn.
- Minions and heroes speak their lines (when played, attacking, dying, emotes, the opening line, conceding) when a recording exists; heroes' emotes are in their own words.

### Changed
- The timer's fuse is a twisted cord with a glowing ember, sparks and smoke.
- A burnt card burns away from its edges with a glowing rim.
- A hit on a hero: a bigger damage number; more than 5 damage shakes harder with a heavy sound.
- A hero that can attack glows brighter.

## [0.16.0] - 2026-10-11

### Added
- Main menu: Play opens a submenu with online play, training and the tutorial.
- Training in steps: choose a deck from a list with hero portraits (or go to the decks), then the opponent from a 3×3 grid of portraits, then Play.
- Online play in steps: name, deck, Create game or Join game; the codes have a Copy button right beside them.
- Tutorial: missions with the bosses' portraits; before each mission, illustrated notes on its new concepts (card parts, combat, mana, spells, Battlecry, Taunt, Charge, Deathrattle, Hero Power, Freeze, weapons).
- Collection and decks on one screen: all cards on the left with class tabs, type, cost and rarity filters and search; decks on the right with copy, export and delete buttons; a deck opens for editing in the same place.

### Fixed
- Online play: a TURN relay for networks with no direct path; the guest waits up to 4 minutes for the host's answer and keeps renewing the connection candidates all that time (before, the browser gave up after a few seconds).

## [0.15.3] - 2026-10-11

### Added
- The loading splash shows the game's version.

## [0.15.2] - 2026-10-11

### Changed
- Class emblems are simple and flat; the sword at the attack gem is shorter, points up to the right, with the hilt showing at the bottom left; the lightning under the portrait is half as big; the poison bottle is green, smaller and still.
- Silence: glowing pink ribbons wind around the portrait.
- Deathrattle: the skull mark grows out of the minion and rises.
- A Battlecry minion first takes its place, then the arrow to the target starts from it; right-click or leading the arrow back into the hand cancels, and the card goes back to the hand.

### Fixed
- The Spell Damage sparks sometimes stopped moving.

## [0.15.1] - 2026-10-11

### Changed
- The mana, health, attack, armor and durability gems are smaller, with a plain centre so the numbers read better; the marks under the portrait are smaller.

## [0.15.0] - 2026-10-11

### Added
- Painted interface pictures: the mana crystal, the health drop, the attack gem with a sword, armor and durability shields, the Taunt shield, a skull and crossbones, a poison bottle, a lightning bolt, class emblems, a fatigue picture.
- Poisonous minions (Emperor Cobra, Patient Assassin) are marked with a poison bottle.
- A keyword box for Enrage.
- A silenced minion's card shows its text crossed out with a red cross when hovered.
- Overload shows at once: orange padlocks above the crystals for next turn; a locked crystal shows a padlock instead of a cross.
- A card made by a card on the table (Archmage Antonidas, Ysera) flies into the hand from it.

### Changed
- Glows (playable, selected, target) are always outside every effect on a card.
- Windfury: gusts on a tilted orbit, passing behind the card and in front of it.
- Stealth: a haze the picture shows faintly through; Frozen: a layer of frost and an icy rim.
- Secrets on the hero portrait are round: purple for the Mage, green for the Hunter, yellow for the Paladin.
- Rarity gems are round, with a shadow and a highlight.
- A legendary minion's dragon covers only the top of the oval.

## [0.14.1] - 2026-10-11

### Changed
- A legendary minion's dragon on the table coils around the portrait's oval.

### Fixed
- In the browser the first Cmd/Ctrl+V pasted nothing instead of the copied code (a friend's code, deck import).
- Online play: the time a tab was hidden no longer cuts the wait for the connection short.
- A card in hand can be taken by pressing below the raised card, where it was.
- Keyword boxes show again when hovering a card in hand.

## [0.14.0] - 2026-10-11

### Added
- 10 ready classic decks in the deck menu: Control Warrior, Midrange Shaman, Midrange Druid, Control Priest, Miracle Rogue, Midrange Paladin, Handlock, Freeze Mage, Midrange Hunter, Zoolock. Players with saved decks get them once.

## [0.13.0] - 2026-10-11

### Added
- Mulligan: replaced cards fly into the deck, new ones fly into their places, the Coin spins in with a golden light, then the whole hand goes down. Cards marked for replacement carry a red seal with a white cross.
- Fatigue: a dark card with a skull and its damage flies from the empty deck into the hero.
- A burnt card (full hand) shows and goes up in flames.
- Hovering a deck also shows the number of cards in that player's hand.

### Changed
- The mana the card under the mouse would spend pulses clearly, when there is mana for it.
- The glow of playable cards and buttons is narrower and brighter at the edge.

## [0.12.2] - 2026-10-11

### Changed
- Playable cards, minions, the hero power and the End Turn button have a soft pulsing glow instead of an outline.

## [0.12.1] - 2026-10-11

### Added
- Hovering a card in hand makes the mana crystals it would spend blink, when it can be played.

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
