# Card tests

Scenes for watching every card in a real game (Debug Table → "Interaction test").
Each file here is a JSON object: card id → list of tests. All files are merged.

```json
{
  "VAN_CS2_189": [
    {
      "kind": "battlecry",
      "title": "Elven Archer: Battlecry hits an enemy minion for 1",
      "scene": {"current": 0, "players": [
        {"hero": "HERO_05", "mana": 10, "max_mana": 10, "hand": ["VAN_CS2_189"], "deck": ["VAN_CS2_120"]},
        {"hero": "HERO_08", "board": ["VAN_CS2_231"], "deck": ["VAN_CS2_120"]}]},
      "steps": [
        {"do": "play", "card": {"side": 0, "zone": "hand", "index": 0}, "target": {"side": 1, "zone": "board", "index": 0}}
      ]
    }
  ]
}
```

- `kind`: one of `play` (played from hand, no special effect), `battlecry`, `spell`, `combo`, `choose_one`,
  `attack`, `death` (the card dies — Deathrattle), `trigger` (an "on" effect: whenever / at the end of turn…),
  `aura`, `enrage`, `secret`, `weapon`, `hero_power`, `taunt`, `charge`, `divine_shield`, `stealth`,
  `windfury`, `freeze`, `spell_damage`, `overload`, `other`.
- `title`: a short English line saying what to watch.
- `scene`: the Debug Table scenario (engine/scenario.gd): `current`, `turn`, `players` with `hero`, `mana`,
  `max_mana`, `damage`, `armor`, `weapon`, `hand`, `deck`, `board`, `secrets`; a card may be a string id or
  `{"card": id, "exhausted": false, "damage": n, …}`. Minions on the board are not exhausted unless asked.
  Give both decks a few cards so draws work.
- `steps`, played in order (each must be legal at that moment): `{"do": "play", "card": ref, "target": ref,
  "pos": n, "choice": n}`, `{"do": "attack", "attacker": ref, "defender": ref}`, `{"do": "hero_power",
  "target": ref}`, `{"do": "end_turn"}`, `{"do": "choose", "option": n}`.
  A ref is `{"side": 0|1, "zone": "hand"|"board"|"secret", "index": n}` or `{"side": s, "zone": "hero"|"weapon"|"power"}`.
  Refs are read at the moment of the step (after earlier steps changed the table).
- Check: `godot --headless --path . --script res://tools/check_card_tests.gd` must print 0 problems.
