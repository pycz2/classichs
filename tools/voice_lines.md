# Voice lines (data/voice_lines.json)

What the cards say when they are played, attack or die, plus the heroes' emotes, as text.
Nothing in the game reads the file yet.

## Format

```json
"VAN_EX1_116": {
  "play":   {"en": "Leeroooooy Jeeeenkiiiiins!", "ru": "...", "de": "...", ...},
  "attack": {"en": "Time's up! Let's do this.", ...},
  "death":  {"en": "At least I have chicken!", ...},
  "source": "https://hearthstone.wiki.gg/wiki/Leeroy_Jenkins_(Classic)",
  "translated": ["de", "es", "fr", "it", "pl", "pt_BR", "ru"]
}
```

- Keys: `play`, `attack`, `death` for minions and weapons. Heroes have `start` (the line at the
  start of a match), `greetings`, `well_played`, `thanks`, `wow`, `oops`, `threaten`
  (the 6 emotes), `concede` and `attack`. A key is only there when the card says a line.
- Languages: `en ru de fr es pt_BR it pl`.
- `translated` lists the languages that are **our own translation**, not the game's text.
  For now that is every language except `en`.

## How it was made

1. **English, official**: `python3 tools/fetch_voice_lines.py` reads the Cargo tables of
   hearthstone.wiki.gg through its API: `Sound` (the sound files of each card, looked up by
   the project's id first, so `VAN_` cards get their June 2014 sounds, then by the id without
   `VAN_`) and `AudioText` (the wiki's transcript of each sound file). For heroes the emote
   text comes from the client's own string tags (`GAMEPLAY_EMOTE_HERO_08_THREATEN`, ...).
   Wiki links are reduced to their label, stage directions such as `<yawns>` are removed,
   and lines that are only a sound (`<death sound>`, `<Snarl>`) are left out. The script only
   writes `en` and `source`; translations already in the file are kept. wiki.gg rejects
   browser user agents, so the script sends its own and waits 1 s between requests.
2. **Other languages, our translation**: no source with the localized texts was found (see
   below). They were translated from the English lines (by Claude, one pass per language),
   using the official localized card and lore names from `data/cards.json`, and are marked in
   `translated`. When an official text turns up, replace the string and remove the language
   from `translated`.

## Sources

- hearthstone.wiki.gg: card pages, the "Sounds" section, Cargo tables `Sound` and `AudioText`
  (`https://hearthstone.wiki.gg/api.php?action=cargoquery&tables=AudioText&fields=file,text`).
- Searched without finding localized texts: the localized Hearthstone wikis on Fandom
  (ru, de, fr, es, pt-br, pl; small and without quotes), localized wiki.gg editions (none
  except zh), outof.games and Hearthpwn (sound file names only, no text), Blizzard forums
  (audio files only), and web searches for known lines in each language. The game plays these
  lines as localized audio without subtitles, so their text exists only in the audio. The
  hero emote strings exist in each client's string files, but no public copy was found.

## Coverage

163 cards: 148 minions, 11 heroes (the 9 classic heroes, Lord Jaraxxus, the tutorial Jaina),
4 weapons (Ashbringer, Truesilver Champion, Fiery War Axe, Gorehowl). 151 of the 240
collectible minions, weapons and heroes have lines.

| Line type | Lines |
|---|---|
| attack | 157 |
| play | 152 |
| death | 13 |
| greetings, well_played, thanks, oops, threaten, concede | 11 each |
| start, wow | 10 each |
| **total** | **408** |

| Language | Lines | Official | Our translation |
|---|---|---|---|
| en | 408 | 408 | 0 |
| ru, de, fr, es, pt_BR, it, pl | 408 each | 0 | 408 each |

## Missing

- **Cards that say nothing**: 155 of the 318 minions, weapons and heroes have only sound effects
  (beasts, murlocs, elementals, golems, totems, dragons, most tokens). They have no entry.
- **Death lines**: most minions only groan when they die, so only 13 have a `death` line.
- **Heroes**: no hero has a victory line. A hero's death is a sound, not a line, so there is
  no `defeat`. Thrall's `wow` and the heroes' `attack` come from the sound file transcripts,
  not the client strings.
- **Spoken but not transcribed on the wiki**: Crazed Hunter (TU4d_002), Pandaren Scout
  (TU4f_002) and Shado-Pan Monk (TU4f_003).
- **Tutorial bosses** (Hogger, King Mukla, Millhouse, Hemet, Illidan, Lorewalker Cho) only
  have tutorial dialogue, which is not collected here.
- **Official ru/de/fr/es/pt_BR/it/pl text**: none (see Sources).
