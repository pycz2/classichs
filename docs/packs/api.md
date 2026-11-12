# Card scripts: the engine API (`g`) and hooks

How a pack's Lua scripts talk to the engine (`rust/engine`, phase B of
`docs/superpowers/plans/2026-10-16-game-packs.md`). The language itself (an
integers-only, sandboxed Lua 5.4 subset, its limits and standard library) is in
[lua.md](lua.md); the files of a pack in [format.md](format.md).

Contents: [script files](#script-files) · [hooks](#hooks) · [events](#events) ·
[the `g` library](#the-g-library) · [errors and limits](#errors-and-limits) ·
[checking a pack against recorded games](#checking-a-pack-against-recorded-games)

## Script files

`scripts/<file>.lua` returns a table: **key → hook set**. A key is a card id or
the name of an enchantment's hooks (`"ench:nightmare"`).

```lua
-- scripts/mage.lua
local cards = {}

cards.VAN_CS2_029 = {                -- Fireball
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 6))
  end,
}

return cards
```

- A card uses a hook set only if `cards.json` points at it:
  `"script": "scripts/mage.lua#VAN_CS2_029"` (file `#` key; several cards may
  point at one key). A card without `script` has no hooks.
- A key that is not a card id is a **named hook set** for enchantments:
  `g.enchant(m, {hooks = "ench:nightmare", player = p})` gives minion `m` the
  `on`/`now`/`deathrattle` hooks of `ench:nightmare`. Names are global: the same
  name in two files is a load error.
- `scripts/lib.lua` (optional) is loaded first; the table it returns is the
  global **`lib`** in every other file (shared helpers). It is not a card file.
- Files load once per pack, in path order. Top-level code runs at load time and
  must not touch the game (the `g` functions fail there).
- **Scripts keep no state of their own.** Locals at the top of a file are fine
  for constants and helper functions, never for game state: the bot runs
  look-ahead copies of the game on the same interpreter, and the read-only hooks
  run on another one. Put state in the game: tags (`g.set_tag`), enchantments
  (`g.enchant`), stats. After loading, the tables a file returned (and the
  tables inside them, two levels deep) are read-only.

Everything about a pack loads or fails at once: a syntax error, an unknown
global, an unknown hook name (`spel = …`), a card whose `script` points nowhere
— `load_pack` returns the error and the pack is refused.

## Hooks

`me` is the entity whose hooks run (the card, the minion, the trap, the
champion power), `t` the chosen target (`nil` when none), `ev` an event table.
Return values are ignored unless said otherwise.

| Hook | Signature | When |
|---|---|---|
| `target` | `"any"` \| `{base = …, filter = fn(g, me, t) → bool, when = fn(g, me) → bool}` | The card (or power) needs a target. Bases: `any`, `minion`, `enemy_minion`, `friendly_minion`, `enemy_char`, `friendly_char`, `enemy_hero` (alias `enemy_champion`). Enemy STEALTH is never a target; SPELLPROOF blocks spells and powers. A minion's battlecry target is optional (no valid target: it is played without one); a spell's is required. `filter` is read-only. `when` (read-only): the spec applies only while it holds, else the card or power has no target (`t` is `nil`): Steady Shot with Steamwheedle Sniper. |
| `battlecry` (alias `on_play`) | `fn(g, me, t)` | A minion or weapon is played from the hand (after it is on the board / before it is equipped). |
| `spell` | `fn(g, me, t)` | A spell is cast (not if countered). A TASK card's (a Quest's) runs once it waits in the trap zone: it sets its goal (`TASK_GOAL`); its `on` hooks then count (`TASK_PROGRESS`) and fulfil it (`g.remove`, the reward to the hand). |
| `combo` | `fn(g, me, t)` | Instead of `battlecry`/`spell` when another card was played before it this turn. |
| `combo_target` | like `target` | The target spec while combo is active (no target without combo). |
| `choose_one` (alias `choice`) | `{"OPTION_A", "OPTION_B"}` | Two option *cards*; the player picks one (`choice` 0/1); the option card's `target` and `effect` are used. |
| `effect` | `fn(g, me, t)` | On a Choose One option card: what the option does (`me` is the played card). |
| `hero_power` (alias `power`) | `fn(g, me, t)` | On a POWER card: the power is used. |
| `can_play` | `fn(g, me) → bool` | The card/power may be played now (read-only). |
| `glow` | `fn(g, me) → bool` | The card in the hand glows yellow now: its condition holds ("if you're holding a Dragon", "if your deck has no duplicates"…; read-only, for clients: snapshots mark it `glow`, no rule reads it). Without it a card with a `combo` hook glows while its combo is on (`g.combo(me)`). |
| `text` | `fn(g, me) → string, …` | The values of the card text's `{0}`, `{1}`, … now (read-only, for clients: snapshots carry them as `text_args`; no rule reads them): a Jade card's next Golem (`"4/4"`, and `"n"` for English's "a{1}" before 8, 11, 18), a made potion's two effects (a value that is a card id stands for that card's text in the player's language). Without it the client leaves the placeholders out. |
| `deathrattle` (alias `on_death`) | `fn(g, me)` | It died (minion or weapon; `g.died_pos(me)` is where). |
| `on` | `{<event type> = fn(g, me, ev)}` | Any event of that type while `me` is in play (or a trap). Queued: runs after the action that caused it. |
| `hand` | `{<event type> = fn(g, me, ev)}` | Like `on`, while the card is in its owner's hand (also an enchantment's `hooks` set's `hand` hooks: Shifter Zerus) (not during the mulligan; skipped if it left the hand before its turn in the queue): "when you draw this" (`draw` with `ev.entity == me`: Flame Leviathan, Burrowing Mine), "while this is in your hand" (Bolvar Fordragon). `hand.discard` also runs for the discarded card itself, which has left the hand: "when you discard this" (Fist of Jaraxxus). |
| `now` | `{predamage = fn(g, me, ev)}` | Replacement effects: runs at once, inside `g.damage`, before damage applies; set `ev.amount` to change it. |
| `secret` (alias `trap`) | `{event = "<type>", cond = fn(g, me, ev) → bool, effect = fn(g, me, ev)}` | A trap: on `event` during the opponent's turn, if `cond` (omitted: always) holds, the trap is revealed, then `effect` runs. |
| `aura` | `fn(g, me)` | Recomputed after every change while `me` is in play: call `g.aura_add` for what it gives now. |
| `aura_final` | `fn(g, me)` | Like `aura`, after every other aura (Lightspawn: attack = health). |
| `cost_mod` | `fn(g, me) → int` | Added to this card's cost (read-only). |
| `cost_aura` | `fn(g, me, card, cost) → int` | While `me` is in play: the new cost of any `card` (read-only; return `cost` to leave it). |
| `on_choose` | `fn(g, me, option, still)` | The player chose `option` of a `g.request_choice` (`still`: the offered ids still where they were). |
| `immune_while_attacking` | `true` | A weapon: its champion is IMMUNE while attacking with it. |
| `durability_on_attack` | `fn(g, w, defender) → bool` | A weapon: whether attacking costs durability (default yes). |
| `both` | `fn(g, me, t)` | A Choose One card played with both options (BOTH_CHOICES, Fandral Staghelm: `choice` 2): this instead of the two options' `effect`s in card order (Druid of the Claw's combined form; Keeper of the Grove silences first). |
| `cost_first` | `true` | Its `cost_aura` comes before every other cost change in a pack with `behaviour.cost_in_order` (Summoning Portal). |

**Read-only hooks** (`target.filter`, `can_play`, `glow`, `text`, `cost_mod`, `cost_aura`) run
while the engine only looks at the game (legal actions, costs in snapshots).
Their `g` has only the query functions; calling an action there is an error.
They must not depend on anything but the game.

An error in a read-only hook ends the game at the next action; in any other
hook at once (see [errors](#errors-and-limits)).

## Events

`on`, `now` and `secret` hooks get the event as a table: `ev.type`, and the
fields of that type. Entity ids are numbers; "none" is `-1` in events (not
`nil`). A field that the event lacks is `nil` — compare carefully
(`ev.target >= 0` fails on `nil`).

**Changing an event**: assign to the table (`ev.countered = true`,
`ev.target = n`, `ev.amount = 0`). When the hook returns, changed fields are
copied back into the logged event, which the engine then reads (a countered
spell does not run; a redirected spell hits the new target; `predamage`
amounts replace the damage).

| `type` | Fields | Notes |
|---|---|---|
| `play` | `entity`, `player`, `card`, `kind` (`minion`/`spell`/`weapon`), `target`; spells: `secret`, `countered`, `task` (only a TASK card's: true) | Before the card's effect. `countered = true` (spells) stops it. Changing `target` redirects a spell. |
| `summon` | `entity`, `player`, `card` | A minion entered the board (played or summoned). |
| `after_summon` | `entity`, `player`, `card`, `played` (true if played from hand) | After its battlecry. |
| `after_spell` | `entity`, `player`, `card` | After a spell resolved. |
| `attack` | `attacker`, `defender`, `player` | Before damage. Changing `defender` redirects (Misdirection). |
| `after_attack` | `attacker`, `defender`, `player` | |
| `damage` | `source`, `target`, `amount`, `player` (the target's controller) | Damage dealt (after armor). |
| `predamage` (`now` only) | `source`, `target`, `amount` | Before damage; set `amount`. |
| `heal` | `source`, `target`, `amount` | |
| `death` | `entity`, `player`, `card`, `minion` (bool) | |
| `draw` | `player`, `entity`, `card` | |
| `discard` | `player`, `entity`, `card` | |
| `equip` | `player`, `entity`, `card` | |
| `armor` | `player`, `amount` | A champion gained Armor (Siege Engine). |
| `hero_power` | `player`, `entity`, `target` | After the power's effect: Inspire (an `on` hook; the pack names it ON_POWER). Events logged during the power's effect carry `by_id` = the power (a draw "from your Hero Power": Wilfred Fizzlebang). |
| `secret_revealed` | `entity`, `player`, `card` | |
| `turn_start`, `turn_end` | `player` (+ `turn`) | `turn_end` hooks run before "this turn" effects end. |
| `game_start` | | Once, when both players have finished the mulligan, before the coin and the first turn ("when the game starts": Prince Malchezaar). Only for a pack whose `player_hooks` set has an `on.game_start` hook (rules.md); the player hooks see it once for each player, `me` that player's champion (the decks are full, the hands drawn). |

Events every hook can also log: `g.log{type = …}` (only logged) and
`g.emit{type = …}` (logged and triggers `on` hooks).

## The `g` library

`g` is passed to every hook and is read-only. Arguments: `e`, `me`, `t`, `m`
are entity ids; `p` a player (0 or 1); `card` a card id; `tag` a mechanic name
(the **pack's** name, e.g. Classic `"TAUNT"`; an engine id the pack renames,
e.g. `"GUARD"`, also works). Positions on the board are **0-based**, left to
right; `nil` means "the right end". A function that finds nothing returns
`nil`. Numbers given to actions are clamped to ±1 000 000. Lists are Lua arrays
(`for _, m in ipairs(g.minions(p))`), in the engine's order.

### Queries (every hook, read-only ones too)

| Function | Returns |
|---|---|
| `g.ctrl(e)` | The player who controls `e`. |
| `g.enemy(e)` | The opponent of `e`'s controller. |
| `g.opponent(p)` | `1 - p`. |
| `g.hero(p)`, `g.power(p)` | The champion, the champion's power. |
| `g.weapon(p)` | The weapon, or `nil`. |
| `g.minions(p)` | `p`'s minions, left to right. |
| `g.all_minions()` | All minions, in play order (oldest first). |
| `g.chars(p)` | `p`'s champion, then minions left to right. |
| `g.all_chars()` | All characters, in play order. |
| `g.others(me)` | `me`'s side's minions without `me`. |
| `g.adjacent(m)` | The minions left and right of `m` (left first). |
| `g.hand(p)`, `g.deck(p)` | Card entities; the deck's **last** item is its top. |
| `g.traps(p)` | `p`'s traps (secrets) in play (not its task: a Quest is no Secret). |
| `g.tasks(p)` | `p`'s task in play (a TASK card: Journey to Un'Goro's Quests), as a list of none or one. |
| `g.card(e)` | Its card id. |
| `g.type(e)` | `MINION`, `SPELL`, `WEAPON`, `CHAMPION`, `POWER`. |
| `g.race(e)`, `g.class(e)` | Card fields (`""` if none). |
| `g.zone(e)` | `DECK`, `HAND`, `PLAY`, the trap zone (the pack's TRAP name; Classic `SECRET`), `GRAVEYARD`, `SETASIDE`. |
| `g.atk(e)` | Attack (with buffs and auras). |
| `g.attack(e)` | What it hits for: a champion's includes the weapon on its own turn. |
| `g.health(e)`, `g.max_health(e)`, `g.dmg(e)` | Current health, max health, damage taken. |
| `g.has(e, tag)` | The tag is set (by the card, the game or an aura). |
| `g.tag(e, tag)` | The tag's number (true = 1), tags plus auras (`g.tag(m, "SPELLPOWER")`). |
| `g.silenced(e)` | |
| `g.is_minion(e)`, `g.is_champion(e)`, `g.is_weapon(e)`, `g.is_spell(e)` | |
| `g.turn()`, `g.current()` | The turn number, whose turn it is. |
| `g.mana(p)`, `g.max_mana(p)` | Mana now, crystals. |
| `g.locked(p)` | `p`'s crystals Overload locked this turn (Kun the Forgotten King refreshes the others). |
| `g.cards_played(p)`, `g.minions_played(p)` | Cards and minions `p` played this turn. |
| `g.combo(e)` | Combo is active for `e`: its controller played another card before it this turn. |
| `g.room(p)` | Free board slots (`g.room(p) > 0`: room for one; note `0` is true in Lua). |
| `g.board_pos(m)` | Its 0-based position, or `nil`. |
| `g.died_pos(m)` | Where a dead minion stood (0-based), or `-1`. |
| `g.trap_ready(me)` | `me` is a trap in play and it is the opponent's turn. |
| `g.spell_dmg(me, n)` | `n` plus `me`'s side spell power (its minions' and its champion's SPELL_POWER: an aura tag on the champion, Jungle Moonkin), doubled per POWER_MULTIPLIER (spells and powers). |
| `g.heal_amt(me, n)`, `g.hp_dmg(me, n)` | Healing / power damage `n` after POWER_MULTIPLIER; a power's damage first adds POWER_DAMAGE (an aura tag on its champion: Fallen Hero). |
| `g.rule(name)` | `hand`, `board`, `max_mana`, `deck_size`, `champion_health` from rules.json. |
| `g.mine(me, ev)` | `ev.player` is `me`'s controller. |
| `g.enchants(e, hooks)` | The `player` fields of `e`'s enchantments with these hooks. |
| `g.info(card)` | A card's data: `{id, type, class, rarity, set, cost, attack, health, durability, race, mana_lock, spell_power, collectible, keywords, trap}`, and `classes` (a list) for a multi-class card (cards.md: a card of each of its classes; its `class` is neutral), `task = true` for a TASK card (a Quest). |
| `g.collectible()` | Collectible card ids of the constructed sets, sorted; no TASK card (a Quest is never made at random nor Discovered). |
| `g.count(p, name)` | A count of the game `g.add_count` keeps for `p` (0 if none). |
| `g.graveyard(p)` | `p`'s cards in the GRAVEYARD zone, in play order: dead minions and weapons, played spells, discarded and burned cards. A minion that died on the board has `DIED_POS` (`g.died_pos(e) >= 0`), and `DIED_TURN` (the turn) in a pack that names that mechanic (Naxxramas: Kel'Thuzad, Feugen and Stalagg). |

### Actions (not in read-only hooks)

Actions on `nil` (or `-1`) as the entity do nothing, so
`g.destroy(g.weapon(g.enemy(me)))` is fine without a check.

| Function | Does / returns |
|---|---|
| `g.damage(src, t, n)` | Deals `n` (DIVINE_SHIELD, IMMUNE, armor, `predamage` apply). Returns the damage dealt. |
| `g.heal(src, t, n)` | Restores up to `n` (HEAL_IS_DAMAGE turns it into damage). Returns the amount. |
| `g.destroy(e)` | Marks it to die in the next death phase. |
| `g.summon(p, card[, pos])` | A new minion; returns it, or `nil` if the board is full. |
| `g.summon_right(me, card)` | Summons for `me`'s side right of `me`. |
| `g.summon_entity(e[, pos])` | Puts a minion card that is not in play (in the hand or deck: it leaves them) on the board as a summon. |
| `g.draw(p[, n])` | Draws `n` (default 1): fatigue, burns on a full hand. Returns the drawn ids. |
| `g.draw_entity(p, e[, quiet])` | Draws that card of `p`'s deck (`quiet`: it is put into the hand, not drawn: no `draw` event, logs `to_hand`; Ancient Harbinger). |
| `g.add_to_hand(p, card)` | A new card in hand (or `nil` if full). |
| `g.create(p, card)` | A new card entity of `p`'s, set aside (zone `SETASIDE`, logs `create`): an option for `g.request_choice` that is in no zone (Totemic Slam's totems, Discover). Only `p` ever sees which card it is (snapshots and events of the other player show `""`). |
| `g.discard_random(p[, n])`, `g.discard(e)` | Discards (emits `discard`). |
| `g.buff(e, atk, hp[, this_turn])` | An enchantment +atk/+hp (`true`: until the end of the turn). |
| `g.set_stats(e, atk, hp)` | Sets attack and/or health (`nil` keeps one); setting health heals. |
| `g.silence(e)`, `g.freeze(e)` | |
| `g.transform(e, card)` | Replaces a minion in play with a new minion, or a card in its owner's hand or deck with any card in its place (Shifter Zerus, Renounce Darkness; only the owner sees the new card); returns it. |
| `g.return_to_hand(e)` | Returns a minion as a fresh card; returns the new card or `nil`. |
| `g.take_control(e, p)` | A minion, or a trap (it moves to `p`'s traps; if `p` has that trap already or `limits.secrets` traps, it is destroyed: Kezan Mystic). |
| `g.copy_minion(me, t)` | Turns `me` into a copy of `t` (stats, enchantments, tags, silence). |
| `g.equip(p, card)` | A new weapon (the old one is destroyed). |
| `g.add_to_deck(p, card)` | A new card shuffled into `p`'s deck at a random place (logs `add_to_deck`); returns it. |
| `g.deathrattle(m)` | Runs `m`'s death hooks now, as if it died, without killing it: its card's (unless silenced), then its enchantments' (Feign Death). |
| `g.gain_armor(p, n)` | |
| `g.gain_mana(p, n[, empty])` | Crystals up to max mana (`empty`: empty crystals). |
| `g.add_mana(p, n)` | Mana this turn (up to max mana; The Coin). |
| `g.set_mana(p, mana, max)` | Sets mana and/or crystals (`nil` keeps one). |
| `g.unlock_mana(p)` | Unlocks `p`'s Overloaded crystals: those locked this turn are mana again (up to the crystals), nothing is owed next turn (Lava Shock). |
| `g.set_tag(e, tag, v)` | `v`: boolean, number, string; `nil` removes. |
| `g.give_tag(e, tag[, this_turn])`, `g.erase_tag(e, tag)`, `g.add_tag(e, tag, n)` | |
| `g.set_damage(e, n)` | Sets the damage taken (Alexstrasza). |
| `g.enchant(e, t)` | Adds an enchantment table: `{hooks = name, player = p}`, `{cost = -2}`, `{cost_set = 5}` (its cost becomes 5, then later changes apply: Bright-Eyed Scout; in the order it came with `behaviour.cost_in_order`), `{set_atk = 5, set_hp = 5, base = true}` (`base`: new base stats, put under every other enchantment, and Silence leaves it: Crystal Core), `{atk = 1, hp = 1, eot = true}`, `{deathrattle = card}` (only that card's own Deathrattle hook, not its other hooks: Unearthed Raptor; with `from = t`, t's tags that no mechanic names come along to `e`, so the copy keeps what t's Deathrattle holds: Moat Lurker's minion), … |
| `g.remove_enchant(e, hooks[, p])` | Removes `e`'s enchantments with these hooks (`p` given: only those whose `player` is `p`; Conceal, Headcrack, Shadow Madness). |
| `g.aura_add(e, atk, hp[, tags])` | In an `aura` hook: what `e` gets now (`{WINDFURY = true}`, `{SPELLPOWER = 1}`). |
| `g.replace_hero(p, card)`, `g.set_power(p, card)` | A new champion / power. |
| `g.reveal(me)` | Reveals a trap (for `now` hooks; `secret` hooks are revealed for you). |
| `g.request_choice(me, ids)` | The player must choose one of these entities; `on_choose` gets it. Asked while another choice is pending (a doubled Battlecry: two Discovers), it comes once that one is answered. |
| `g.cast(me, spell, t)` | Casts a copy of the spell entity `spell` for `me`'s player on `t` (or none), as `spell` was cast (its Choose One option, its Combo): only its effect, no `play` or `after_spell` event, no target check; logs `cast` (Djinni of Zephyrs). |
| `g.cast_random(me, card[, overload])` | Casts a new spell `card` for `me`'s player with every choice made at random (Yogg-Saron): a random valid target (no enemy with Stealth or Immune; none, or its `can_play` fails: it fizzles, logs `fizzle`, returns `nil`), a random Choose One option (both with BOTH_CHOICES), its `g.request_choice` picked at once at random; Combo only if a card was played before `me` this turn; a trap goes into play if it may. Only its effect: no `play`/`after_spell` event, no Overload (`g.cast_random(me, card, true)`: its Overload too, owed by `me`'s player, cast or fizzled: Yogg-Saron since patch 6.2). Logs `cast` with `random`; returns the spell. |
| `g.extra_turn(p)` | `p` takes one more turn after the current one, before the opponent's (Time Warp; two cast in one turn still give one): the turn ends as usual, logs `extra_turn` and the same player's turn starts (a mana crystal, a draw). In the player's snapshot `extra_turns` while some are owed. |
| `g.force_attack(a, d)` | `a` attacks `d` now, in any turn (Swamp King Dred: "attack it"): the `attack` event (a redirect counts), the damage both ways, `after_attack`; past Taunt and Stealth, Frozen or exhausted, and it uses none of `a`'s attacks. Nothing happens unless both are characters of different sides in play, awake and not dying. |
| `g.add_count(p, name[, n])` | Adds `n` (default 1) to `p`'s count `name` (in the player's snapshot `counts`; kept by a new champion): spells cast, Totems summoned this game. Returns the new count. |
| `g.add_cost_mod(p, t)` | `{kind = "spell"|"minion"|"secret" (or "trap")|"power"|"any", set = n or delta = n, until = "use"|"turn_end"[, turn = n][, race = r][, lasting = true]}`; `turn` defaults to now. `race`: only cards of that race (Dragon Consort: `"DRAGON"`). `"power"`: the champion's power (a `"use"` mod goes when the power is used: Fencing Coach; Saboteur: `turn = g.turn() + 1`). `lasting`: it holds on any turn, kept until a card it applies to is played (with `until = "use"`: "the next Dragon you play costs (2) less"). `health = true`: the cards it applies to cost Health instead of Mana (paid as damage to the champion, Armor first; playable only while Health and Armor are more than the cost: Cho'gall). |
| `g.log(ev)`, `g.emit(ev)` | Logs an event table (`emit` also triggers `on` hooks). |
| `g.remove(e[, zone])` | Takes `e` out of its hand/deck/board/trap list (and the weapon slot), optionally setting its zone. |
| `g.cost(e)` | A card's cost now (cost hooks included). |
| `g.random(lo, hi)` | A random integer `lo..hi` from the game's generator. |
| `g.pick(list)` | A random item (or `nil` for an empty list). |
| `g.random_alive(list)` | A random item that is in play and not dying, or `nil`. |
| `g.shuffle(list)` | Shuffles the list in place (and returns it). |
| `g.put_trap(e)` | Puts a trap card of its owner's hand or deck into play, as if played but without the `play` event (logs `trap_put`); `false` (it stays where it is) when `e` is no trap there, the same trap is already in play or its owner has `limits.secrets` traps (Mad Scientist). |
| `g.remove_dead()` | The death phase now: the dead leave the board (room for a summon) and their Deathrattles and `death` events are queued, to run after the hook (Mimiron's Head: V-07-TR-0N comes before the Mechs' Deathrattles). |
| `g.resolve()` | Runs the queued triggers and the death phase now, inside the hook (Poison Seeds and Reincarnate: the destroyed minions die and their Deathrattles go before the Treants or the copy come). |

Randomness must come from these (the game's seeded generator): every
platform, the server and replays then agree.

## Errors and limits

- A runtime error (`error(...)`, a nil call, a bad argument:
  `bad argument #2 to 'g.damage' (entity expected, got nil)`) or a limit
  (200 000 steps per hook call, depth, memory; [lua.md](lua.md)) **ends the game
  as a draw**: the engine logs `{"type": "game_over", "winner": -1, "reason":
  "script_error", "error": "scripts/x.lua:12: …"}`, and every API state reply
  then has `script_error` (the client shows "a card script failed: …").
- Hooks the engine calls while running a hook (a damage triggers a `now` hook)
  share its step budget.
- The engine never panics on a script; a pack that cannot load is refused by
  `load_pack` with the reason.

## Checking a pack against recorded games

Every Classic card hook is Lua (`packs/classic/scripts/`); the engine has no
card logic of its own. The Classic pack is checked against the games recorded
from the old GDScript engine (7833 games, rust/engine/README.md "Parity"):

```sh
cd rust
# quick (~3 s): the committed 1731 games that mention a Warrior card
PARITY_BIG=0 PARITY_FILTER=WARRIOR cargo test -p classichs-engine --test parity -- --nocapture
# a few cards, all fixtures
PARITY_FILTER=VAN_EX1_398,VAN_EX1_407 cargo test -p classichs-engine --test parity -- --nocapture
# everything, 7833 games (~80 s)
cargo test -p classichs-engine -- --nocapture
```

`PARITY_FILTER` takes card ids, class names and `lua` (every card with hooks),
comma-separated; a game is replayed if its recorded line mentions any of them.
`PARITY_BIG=0` skips `fixtures/big`. The first lines of a mismatch report show
the step, the action and what differs. The Classic scripts are built into the
engine (build.rs), so a test run always uses the current ones.
`builtin_rules_hash_matches_pack_py` (tests/packs.rs) checks the built-in
ruleset against `tools/pack.py`.

### Pitfalls

- **Same order, same randomness.** Parity compares every event and the RNG
  state: a change to a Classic script must call `g.pick`/`g.random`/`g.random_alive`
  exactly where it did, as many times, on lists in the same order, and keep
  event order (damage before freeze…).
- `nil` vs `-1`: queries and actions return `nil` for "none"; events keep `-1`.
  `ev.field` is `nil` when the event lacks it — `nil >= 0` is an error.
- `0` and `""` are **true** in Lua: write `g.room(p) > 0`, `#list > 0`.
- Positions are 0-based (`g.summon(p, card, g.died_pos(me))`), lists 1-based.
- `until`, `end`, `and`, `or`, `not` are keywords: `{ ["until"] = "use" }`.
- No `continue`, no `/` (use `//`), no floats, no global variables.
- Read-only hooks (`target.filter`, `can_play`, `glow`, `text`, `cost_mod`, `cost_aura`) see
  only queries: no `g.cost`, no actions.
- `g.tag` adds aura values (`SPELLPOWER` from an aura counts); `g.add_tag`
  changes only the entity's own tag.
- An `on` hook's changes to `ev` are written back; a copy of `ev` is not.
- Do not keep game state in file-level locals (see [script files](#script-files)).
- In Classic, `cards.patch.json` and `lib.lua` are shared by every script file:
  add, do not reorder; prefer file-local helpers.
