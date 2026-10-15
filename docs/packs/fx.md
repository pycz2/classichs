# Visual effects (`fx`)

The client has a fixed catalog of named effects (D16). A pack never draws
anything itself: a card names effects in its `fx` field and the client plays
them. An unknown name plays the slot's default. Machine-readable list:
[schema/fx.json](schema/fx.json). The code: `ui/table_fx.gd` (effects on the
table), `ui/match_view.gd` (bolts, missiles, shake, shatter, burn, fatigue,
reveal, banner, lunge, pulse), `ui/art.gd` (`ELEMENT_COLORS`).

```json
"fx": {"element": "fire", "cast": "bolt", "hit": "hurt"}        // Fireball
"fx": {"element": "arcane", "cast": "missiles", "hit": "hurt"}  // Arcane Missiles
"fx": {"play": "battlecry", "death": "skull"}                  // a minion
```

## 1. Slots of a card's `fx`

| Slot | When | Names | Default |
|---|---|---|---|
| `element` | Colour of the spell's or power's bolt and of its hits | `fire ice arcane moon holy shadow nature lightning poison steel gold` | gold `ffd43b` for non-spells; the class's element for spells |
| `cast` | A spell or power is played | `bolt`, `missiles`, `none` | `bolt` when it has a target |
| `hit` | On each character it changes | `hurt heal buff debuff gain freeze silence smoke destroy portal whoosh control armor none` | by the event (damage → `hurt`, heal → `heal`, …) |
| `play` | A minion is played | `battlecry`, `portal`, `none` | `battlecry` when its play hook did something |
| `death` | A minion dies | `skull`, `destroy`, `none` | `skull` when it had an unsilenced death hook |

## 2. The catalog

### Elements (`ui/art.gd` `ELEMENT_COLORS`: main, light)

| Element | Colours | | Element | Colours |
|---|---|---|---|---|
| `fire` | `e2541b`, `ffd23f` | | `nature` | `40c057`, `d8f5a2` |
| `ice` | `4dabf7`, `e7f5ff` | | `lightning` | `74c0fc`, `fff3bf` |
| `arcane` | `c77dff`, `f3d9ff` | | `poison` | `82c91e`, `e9fac8` |
| `moon` | `adb5bd`, `fff3bf` | | `steel` | `868e96`, `f1f3f5` |
| `holy` | `fab005`, `fff9db` | | `gold` | `f59f00`, `fff3bf` |
| `shadow` | `7b2cbf`, `e0aaff` | | | |

### Casts

| Name | Looks like | Params |
|---|---|---|
| `bolt` | A glowing orb (white core, coloured halo) flies from the card or the power to the target in 0.32 s and bursts. | colour: `element` |
| `missiles` | One small bolt per hit, 0.3 s apart; the target's number drops at each hit (for random multi-hits). | colour: `element` |
| `none` | Nothing flies. | |

### Hits (`ui/table_fx.gd`; life in seconds; default colour)

| Name | Looks like | Life | Colour |
|---|---|---|---|
| `hurt` | A burst with ten sparks flying out | 0.55 | `ff7b2e` (or the element) |
| `heal` | Rising star sparkles in a soft glow | 0.8 | `8ce99a` |
| `buff` | Rising arrows in a soft glow | 0.8 | `ffd43b` |
| `debuff` | Arrows sinking | 0.7 | `b197fc` |
| `gain` | A bright ring opening out (a keyword gained) | 0.6 | `ffffff` |
| `freeze` | Eight ice shards growing out, blue glow | 0.8 | `a5d8ff` |
| `silence` | Two rings closing in | 0.7 | `b197fc` |
| `smoke` | Puffs drifting apart (a transform) | 0.8 | `f783ac` |
| `destroy` | Dark puffs drifting apart | 0.7 | `343a40` |
| `portal` | A golden ring with turning sparks (a summon) | 0.8 | `ffd43b` |
| `whoosh` | Puffs drifting apart and up (back to hand) | 0.6 | `ffffff` |
| `control` | A swirl of dots (taken control of) | 0.8 | `9775fa` |
| `armor` | A grey shield popping up | 0.7 | `ced4da` |
| `none` | Nothing. | | |

### Play and death

| Name | Looks like |
|---|---|
| `battlecry` | A bright golden ring opening out from the minion (0.6 s). |
| `portal` | As the hit `portal`. |
| `skull` | The minion's death mark grows and rises out of where it died (1.1 s). |
| `destroy` | As the hit `destroy`. |

### Table effects (the client uses them by event; a pack can't name them on a card)

| Name | Looks like | Params |
|---|---|---|
| `shake` | The table shakes (heavy hits, the end of a game). | strength 1 or 2 |
| `shatter` | The losing champion's portrait breaks into flying shards. | |
| `burn` | A card drawn into a full hand shows, then burns away from its edges. | |
| `fatigue` | A dark card with a skull flies from the empty deck to the champion. | damage |
| `reveal` | A revealed trap shows big in the middle for 0.9 s. | card |
| `banner` | Big text grows in the middle and fades ("Your turn"). | text |
| `lunge` | The attacker leaps at its target and back; the hit lands at the touch. | |
| `pulse` | The power button flashes (1.3×) before its bolt. | |

States are drawn from engine keywords, not from `fx`: `GUARD` (a shield frame),
`BARRIER` (a golden bubble), `STEALTH`, `FROZEN` (ice), `DOUBLE_ATTACK`,
`HASTE`, `IMMUNE`, `SPELL_POWER`, the sleeping mark, the trigger and death marks.

## 3. Classic: how its cards got their `fx`

The Classic client picks a spell's colour from its picture plan (`Art.design`),
and plays hits by event. `packs/classic/cards.patch.json` writes that down per
card as a starting point (dumped from `Art._subject` with headless Godot):

- `element` (spells and powers): the element of the name's motif (fire, frost,
  arcane, …), else the class's: Mage arcane, Priest and Paladin holy, Warlock
  shadow, Druid and Hunter nature, Shaman lightning, Rogue poison, Warrior steel,
  Dream moon.
- `hit`, from the English text: damage → `hurt`; restore/heal → `heal`; +Attack
  /+Health → `buff`; Armor → `armor`; Divine Shield, Taunt, Stealth, Immune →
  `gain`; destroy → `destroy`; transform → `smoke`; return → `whoosh`; silence →
  `silence`; freeze without damage → `freeze`; summon → `portal`; mana → `gain`.
- `cast`: `missiles` when the text deals damage at random; `bolt` for the rest
  except draw, summon, mana, secrets and plain emblems (nothing flies).
- Minions: `play: battlecry` with `BATTLECRY`, `death: skull` with `DEATHRATTLE`.

Phase C makes the client read `fx` from the pack instead of deriving it; until
then these values equal what the client shows.
