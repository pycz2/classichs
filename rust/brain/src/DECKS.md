# Bot deck library

Constructed decks for the AI bots, Classic card set (June 2014 Basic + Expert, pre-nerf; `VAN_` ids from `data/cards.json`).
One file per deck: `{"name", "hero", "archetype", "source", "cards": [30 ids]}`.

Sources: the 10 shipped decks from `packs/classic/decks/` (cards unchanged), lists from HearthstoneTopDecks
(Classic format, 2021), and a few lists composed from the 2014 vanilla archetypes where no complete list was
found online (marked "composed" in the source column). Card names were mapped to the collectible `VAN_`
card with the exact enUS name.

| Class | Deck | Archetype | File | Source |
|---|---|---|---|---|
| Druid | Midrange Druid | midrange | `druid_midrange.json` | packs/classic/decks/03_midrange_druid.json |
| Druid | Ramp Druid | control | `druid_ramp.json` | https://www.hearthstonetopdecks.com/decks/classic-ramp-druid/ |
| Druid | Token Druid | combo | `druid_token.json` | https://www.hearthstonetopdecks.com/decks/classic-token-druid/ |
| Hunter | Control Hunter | control | `hunter_control.json` | composed from the June 2014 vanilla meta archetype (no complete online list found) |
| Hunter | Face Hunter | aggro | `hunter_face.json` | https://www.hearthstonetopdecks.com/decks/classic-face-hunter-2/ |
| Hunter | Midrange Hunter | midrange | `hunter_midrange.json` | packs/classic/decks/09_midrange_hunter.json |
| Hunter | Midrange Hunter (Sunshine) | midrange | `hunter_midrange_sunshine.json` | https://www.hearthstonetopdecks.com/decks/classic-midrange-sunshine-hunter/ |
| Mage | Control Mage | control | `mage_control.json` | composed from the June 2014 vanilla meta archetype (no complete online list found) |
| Mage | Freeze Mage | control | `mage_freeze.json` | packs/classic/decks/08_freeze_mage.json |
| Mage | Freeze Mage (TopDecks) | control | `mage_freeze_topdecks.json` | https://www.hearthstonetopdecks.com/decks/classic-freeze-mage-6/ |
| Mage | Tempo Mage | midrange | `mage_tempo.json` | https://www.hearthstonetopdecks.com/decks/classic-tempo-mage-2/ |
| Paladin | Aggro Paladin (Shockadin) | aggro | `paladin_aggro.json` | https://www.hearthstonetopdecks.com/decks/classic-aggro-paladin-shockadin/ |
| Paladin | Control Paladin (Healadin) | control | `paladin_control.json` | https://www.hearthstonetopdecks.com/decks/classic-control-paladin-healadin/ |
| Paladin | Midrange Paladin | midrange | `paladin_midrange.json` | packs/classic/decks/06_midrange_paladin.json |
| Priest | Inner Fire Priest | combo | `priest_combo.json` | composed from the June 2014 vanilla meta archetype (no complete online list found); archetype: https://hearthstone.wiki.gg/wiki/Combo_Priest |
| Priest | Control Priest | control | `priest_control.json` | packs/classic/decks/04_control_priest.json |
| Priest | Control Priest (TopDecks) | control | `priest_control_topdecks.json` | https://www.hearthstonetopdecks.com/decks/classic-control-priest-4/ |
| Priest | Shadow Priest | midrange | `priest_shadow.json` | composed from the June 2014 vanilla meta archetype (no complete online list found) |
| Rogue | Aggro Rogue | aggro | `rogue_aggro.json` | https://www.hearthstonetopdecks.com/decks/classic-aggro-rogue-2/ |
| Rogue | Midrange Rogue | midrange | `rogue_midrange.json` | composed from the June 2014 vanilla meta archetype (no complete online list found) |
| Rogue | Miracle Rogue | combo | `rogue_miracle.json` | packs/classic/decks/05_miracle_rogue.json |
| Rogue | Miracle Rogue (TopDecks) | combo | `rogue_miracle_topdecks.json` | https://www.hearthstonetopdecks.com/decks/classic-miracle-rogue-2/ |
| Shaman | Burn Shaman | aggro | `shaman_burn.json` | https://www.hearthstonetopdecks.com/decks/classic-burn-shaman/ |
| Shaman | Hybrid Shaman | aggro | `shaman_hybrid.json` | https://www.hearthstonetopdecks.com/decks/classic-hybrid-shaman/ |
| Shaman | Midrange Shaman | midrange | `shaman_midrange.json` | packs/classic/decks/02_midrange_shaman.json |
| Shaman | Kolento's Midrange Shaman | midrange | `shaman_midrange_kolento.json` | https://www.hearthstonetopdecks.com/best-hearthstone-classic-decks-for-every-class/ |
| Warlock | Control Warlock (Jaraxxus) | control | `warlock_control.json` | composed from the June 2014 vanilla meta archetype (no complete online list found) |
| Warlock | Handlock | control | `warlock_handlock.json` | packs/classic/decks/07_handlock.json |
| Warlock | Savjz's Handlock | control | `warlock_handlock_savjz.json` | https://www.hearthstonetopdecks.com/decks/classic-hand-warlock-handlock/ |
| Warlock | Zoolock | aggro | `warlock_zoo.json` | packs/classic/decks/10_zoolock.json |
| Warlock | Zoo Warlock (TopDecks) | aggro | `warlock_zoo_topdecks.json` | https://www.hearthstonetopdecks.com/decks/classic-zoo-warlock-zoolock/ |
| Warrior | Aggro Warrior | aggro | `warrior_aggro.json` | https://www.hearthstonetopdecks.com/decks/classic-aggro-warrior/ |
| Warrior | Control Warrior | control | `warrior_control.json` | packs/classic/decks/01_control_warrior.json |
| Warrior | Control Warrior (TopDecks) | control | `warrior_control_topdecks.json` | https://www.hearthstonetopdecks.com/decks/classic-control-warrior-2/ |
| Warrior | Worgen OTK Warrior | combo | `warrior_worgen_otk.json` | composed from the June 2014 vanilla meta archetype (no complete online list found); archetype: https://www.icy-veins.com/hearthstone/classic-worgen-otk-warrior-deck |

## Validation

Every file was checked by the real engine: a small Rust binary (outside the repo) depending on
`rust/engine` calls `Engine::new().call({"op":"validate","deck":{"hero":..., "cards":...}})` for each
`bots/decks/*.json`; all 35 decks returned `{"ok": true}` (30 cards, at most 2 copies, 1 per legendary,
only the hero's class and neutral, collectible only). Unknown ids are dropped by `Deck::from_value_in`, so a bad id
shows up as a card-count error.
