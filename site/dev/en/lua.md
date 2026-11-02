# Card scripts in Lua

A card with special text gets its behaviour from a small Lua script. The engine of {name} runs the scripts with its own interpreter (`rust/script`), the same on the server, on desktop and Android and in the browser, so a script with the same game always does the same thing everywhere. The language is **a safe subset of Lua 5.4**: plain Lua, with integers only and no access to anything outside the game.

## A script file

A file in `scripts/` runs once when the pack loads and returns a table: **card id → the card's hooks**. A card uses a hook set when `cards.json` points at it: `"script": "scripts/exec.lua#grid_overseer"` (file `#` key).

```lua
-- scripts/exec.lua (Neonfall)
local cards = {}

-- Grid Overseer: your Drones have +1 Attack.
cards.grid_overseer = {
  aura = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.race(m) == "DRONE" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

return cards
```

Every hook gets `g` (the engine's library, [Engine API](api.html)) and `me`, the entity whose hook runs (the minion, the spell, the trap, the power). Entities, players and numbers are plain integers; card ids and mechanic names are strings.

- `scripts/lib.lua` (optional) loads first; the table it returns is the global **`lib`** in every other file: shared helpers.
- Several cards may point at one key; keys that are not card ids name hook sets for enchantments (`"ench:tutorial_guard"`).
- **Scripts keep no state of their own.** File-level locals are for constants and helper functions only: the bot plays look-ahead copies of the game on the same interpreter. Keep state in the game — tags (`g.set_tag`), enchantments (`g.enchant`), stats. After loading, the tables a file returned are read-only.
- Everything loads or fails at once: a syntax error, an unknown global, an unknown hook name (`spel = …`), a card whose `script` points nowhere — the pack is refused with the file and line.

## The language

### Values and types

| Type | |
|---|---|
| `nil` | Nothing. A missing table key, a missing argument. |
| `boolean` | `true`, `false`. Only `nil` and `false` are false: **`0` and `""` are true**. |
| `number` | A 64-bit **integer**. `42`, `0x2A`. There are no fractions: `1.5`, `1e3` are errors. |
| `string` | Bytes, immutable; UTF-8 text is fine. `"double"`, `'single'`, `[[long]]`. |
| `table` | The only data structure: arrays `{1, 2, 3}`, records `{x = 1}`, maps `{[key] = v}`. |
| `function` | Functions and closures. |

`type(v)` returns these names. Comments: `-- to the end of the line` and `--[[ long ]]`.

### Variables and scope

- `local x = 1`, `local a, b = f()`. A local is visible to the end of its block.
- **No global variables of your own.** `x = 1` or `function f() end` at the top is a compile error: `assignment to undeclared global 'x' (declare it with 'local')`. Write `local x`, `local function f()`. Assigning to a field is fine: `cards.X = {}`, `t.n = 1`.
- Globals are the standard library and the engine's names (`g`, `lib`, `list`); a typo in one (`ipars`) is an error when the pack loads, with its file and line.
- Closures see the locals around them; two closures that see the same local share it; each loop iteration gets its own copy of the loop variables.
- `_G` and `_ENV` do not exist.

### Statements

`local`, assignment (`a, b = b, a` swaps), calls, `do … end`, `if … then … elseif … else … end`, `while … do … end`, `repeat … until c` (the condition sees the body's locals), numeric `for i = a, b [, step]` (integers; `step` 0 is an error), generic `for k, v in pairs(t)` / `ipairs(t)` / `next`, `break`, `return` (last in its block), `function a.b.c() end`, `function a.b:m() end`.

### Operators

From low to high: `or`, `and`, `< > <= >= ~= ==`, `..` (concatenation, also of numbers), `+ -`, `* // %`, unary `not # -`.

- `//` is **floor division**: `7 // 2 == 3`, `-7 // 2 == -4`. `%` has the sign of the divisor: `-7 % 3 == 2`.
- `+ - *` stop with `integer overflow in '+'` when the result does not fit (standard Lua would wrap around). Dividing by zero is an error.
- Strings are never turned into numbers: `"10" + 1` is an error; use `tonumber`.
- `<` compares two numbers or two strings; anything else is an error. `==` never fails: tables and functions are equal only to themselves.

### Functions and tables

- Missing arguments are `nil`, extra ones are dropped. `...` varargs, `select("#", ...)`, several results with `return a, b`.
- Methods: `obj:m(x)` is `obj.m(obj, x)`; strings have the `string` functions as methods: `s:sub(1, 3)`.
- `t.name` is `t["name"]`; assigning `nil` removes a key; `#t` is the length of an array without holes.
- **`pairs` visits keys in the order they were added** (standard Lua leaves the order open). Changing a value keeps its place; a removed and re-added key goes to the end. Don't add keys while iterating.

### The standard library

| | |
|---|---|
| Base | `type`, `tostring`, `tonumber(v [, base])`, `ipairs`, `pairs`, `next`, `select`, `error(v [, level])`, `assert`, `pcall` |
| `table` | `insert`, `remove`, `sort` (stable), `concat`, `unpack` |
| `string` | `len`, `sub`, `upper`, `lower`, `rep`, `byte`, `char`, `format` (only `%d`, `%s`, `%%`), `find` (plain text only; no patterns) |
| `math` | `min`, `max`, `abs`, `clamp(x, lo, hi)`, `floor`, `maxinteger`, `mininteger` |
| `list` | Array helpers that never change their argument: `filter(t, f)`, `map(t, f)`, `count(t [, f])`, `any(t, f)`, `all(t, f)`, `sum(t [, f])`, `sort_by(t, key)` |

There is no `math.random`: randomness comes from the game (`g.random`, `g.pick`, `g.random_alive`, `g.shuffle`), so both players, the server and replays agree.

### Not supported

| Feature | What happens |
|---|---|
| Fractions, `/`, `^` | Compile error: `'/' is not supported (no floats); use '//' for integer division` |
| Bitwise `& \| ~ << >>` | Compile error |
| `goto`, labels, `<const>`, `<close>` | Compile error |
| Global assignment, `_G`, `_ENV` | Compile error |
| Metatables (`setmetatable`, `getmetatable`, `rawget`, `rawset`, …), `coroutine` | Load error: not available |
| `load`, `require`, `dofile`, `io`, `os`, `debug`, `print`, `utf8` | Load error: scripts can't load code or reach the outside |
| String patterns (`gsub`, `match`, `gmatch`), `string.dump`, `table.pack`, `math.random`, `math.sqrt` | Not present (`nil`) |
| `continue` | Not in Lua at all; use `if … then … end` around the rest of the body |
| Changing a library table | Runtime error: `attempt to modify a read-only table` |

### Limits

Each hook call has a budget; hooks that the engine runs inside it (a damage that triggers another card) share it.

| Limit | Default |
|---|---|
| Steps (1 per statement, loop iteration, call; built-ins 1 per element) | 200 000 |
| Call depth | 200 |
| Entries in one table | 10 000 |
| Bytes in one string | 64 KiB |
| Memory allocated in one call | 16 MiB |

An ordinary card hook uses tens to a few hundred steps. `pcall` catches script errors, not limit errors.

## How a card script runs

| Hook | When it runs |
|---|---|
| `target` | Not a function: the card needs a target. `"any"`, `"minion"`, `"enemy_minion"`, `"friendly_minion"`, `"enemy_char"`, `"friendly_char"`, `"enemy_hero"`, or `{base = …, filter = fn(g, me, t)}`. A minion's battlecry target is optional (no valid target: it is played without one); a spell's is required. |
| `battlecry` | A minion or weapon is played from the hand: after the minion is on the board, before the weapon is equipped. Not when it is summoned by another card. |
| `spell` | A spell is cast (not if a trap countered it). |
| `combo` | Instead of `battlecry`/`spell` when another card was played before it this turn (Neonfall's *Chain*). |
| `choose_one` | `{"OPTION_A", "OPTION_B"}`: two option cards; the player picks one and that card's `target` and `effect` are used. |
| `hero_power` | A champion's power is used. |
| `deathrattle` | It died (minion or weapon); `g.died_pos(me)` is where it stood. |
| `on = {event = fn}` | Any event of that type while `me` is in play. **Queued**: it runs after the action that caused it, in order. |
| `now = {predamage = fn}` | A replacement: runs at once inside `g.damage`, before the damage; set `ev.amount`. |
| `secret` | A trap: `{event, cond, effect}`. On `event` during the **opponent's** turn, if `cond` holds, it is revealed and `effect` runs. |
| `aura` | Recomputed after every change while `me` is in play: call `g.aura_add` for what it gives *now*. When `me` leaves, its aura is simply gone. |
| `can_play`, `cost_mod`, `cost_aura` | Read-only questions: can it be played now, its cost change, the cost of other cards while it is in play. |

Every hook with its exact signature: [Engine API](api.html#hooks).

**Determinism.** Everything a script can see is decided by the script and the game: integers only, `pairs` in insertion order, stable sorting, no clock, no randomness of its own, `tostring` of a table is a counter, not an address. That is why two players' games stay in step in an online match, the server can replay any game, and the bot can copy the game to look ahead.

**Errors.** A script error or a limit ends the game as a draw ("a card script failed: …" with the file and line), never a crash. Read-only hooks must not change the game; calling an action there is an error.

## Worked examples

All from Neonfall (`packs/neon/scripts/`) unless marked; the card's line from `cards.json` first, then its hooks.

### 1. A vanilla minion: no script

Glasshound Runner, a 2/2 with Hardlight and Cloak. Keywords that are tags work by themselves:

```json
{"id": "glasshound_runner", "type": "MINION", "class": "NEUTRAL", "rarity": "COMMON", "set": "core",
 "collectible": true, "cost": 3, "attack": 2, "health": 2, "keywords": ["BARRIER", "STEALTH"]}
```

Neonfall's mechanic names are the engine ids themselves (`"BARRIER": {"engine": "BARRIER"}`); players see *Hardlight* and *Cloak* from the locale files.

### 2. A battlecry with a target

Signal Jammer — *Boot: Jam an enemy minion.* `target` says which characters can be chosen; the battlecry gets the chosen one as `t`:

```json
{"id": "signal_jammer", "type": "MINION", "class": "NEUTRAL", "rarity": "COMMON", "set": "core", "collectible": true,
 "cost": 1, "attack": 0, "health": 3, "race": "DRONE", "keywords": ["ON_PLAY"], "refs": ["FREEZE"],
 "script": "scripts/neutral.lua#signal_jammer"}
```

```lua
cards.signal_jammer = {
  target = "enemy_minion",
  battlecry = function(g, me, t) g.freeze(t) end,
}
```

A narrower target with a filter — Field Auditor, *Boot: give a friendly Drone Hardlight*:

```lua
cards.field_auditor = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t) return g.race(t) == "DRONE" end,
  },
  battlecry = function(g, me, t) g.give_tag(t, "BARRIER") end,
}
```

With no friendly Drone on the board the card is still played, without a target.

### 3. An aura

Grid Overseer — *Your Drones have +1 Attack.* The aura says what it gives now; the engine takes it back when the Overseer dies or a Drone leaves:

```lua
cards.grid_overseer = {
  aura = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.race(m) == "DRONE" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}
```

`g.aura_add(m, atk, hp[, tags])` can also give keywords: `g.aura_add(me, 0, 0, {DOUBLE_ATTACK = true})` is Neonfall's *Redline: Dual-Core* (`lib.redline`).

### 4. A deathrattle that summons

Enforcement Mech — *Firewall. Flatline: summon two 0/2 Sentry Drones.* Positions are 0-based; summoning at `g.died_pos(me)` twice puts both where the Mech stood:

```lua
cards.enforcement_mech = {
  deathrattle = function(g, me)
    local p, pos = g.ctrl(me), g.died_pos(me)
    for _ = 1, 2 do
      g.summon(p, "sentry_drone", pos)
    end
  end,
}
```

`g.summon` returns the new minion, or `nil` when the board is full — no check needed here, a full board just summons fewer.

### 5. A trap (secret)

Protocol: Lockout — *When your opponent plays a minion, deal 1 damage to it and Jam it.* The card has the `TRAP` keyword; its hook is `secret`:

```lua
cards.lockout = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev) return ev.played == true and not g.mine(me, ev) end,
    effect = function(g, me, ev)
      g.damage(me, ev.entity, g.spell_dmg(me, 1))
      g.freeze(ev.entity)
    end,
  },
}
```

`ev` is the event table ([events](api.html#events)): `after_summon` has `entity`, `player`, `card` and `played` (true when it came from the hand, not from another card's summon). `g.mine(me, ev)` is "the event's player is my controller". `g.spell_dmg` adds spell power, since a trap is a spell.

### 6. An event hook, with a helper from lib.lua

Medic Drone — *At the end of your turn, restore 2 Health to a random damaged friendly character.* `lib.on_mine` (Neonfall's `scripts/lib.lua`) builds an `on` hook that runs only on its controller's events:

```lua
-- scripts/lib.lua
function lib.on_mine(ty, f)
  return {
    on = {
      [ty] = function(g, me, ev)
        if g.mine(me, ev) then f(g, me, ev) end
      end,
    },
  }
end

-- scripts/exec.lua
cards.medic_drone = lib.on_mine("turn_end", function(g, me)
  local hurt = list.filter(g.chars(g.ctrl(me)), function(c) return g.dmg(c) > 0 end)
  local t = g.pick(hurt)
  if t then
    g.heal(me, t, g.heal_amt(me, 2))
  end
end)
```

`g.pick` takes the random choice from the game's own generator. Classic's `scripts/lib.lua` has more helpers of this kind (`lib.hit(target, n, spell)`, `lib.others_aura(atk, hp)`, `lib.draw_battlecry(n)`…).

### 7. Chain (combo) and Fork (choose one)

```lua
-- Zero-Day: deal 1 damage to a minion and Jam it. Chain: 3 damage instead.
local function zero_day(n)
  return function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, n))
    g.freeze(t)
  end
end
cards.zero_day = { target = "minion", spell = zero_day(1), combo = zero_day(3) }

-- Executive Decision: Fork — Hard Reset (Wipe a minion) or Retention Bonus (+2 Health and Firewall).
cards.executive_decision = { choose_one = { "hard_reset", "retention_bonus" } }
cards.hard_reset = { target = "minion", effect = function(g, me, t) g.silence(t) end }
cards.retention_bonus = {
  target = "minion",
  effect = function(g, me, t)
    g.buff(t, 0, 2)
    g.give_tag(t, "GUARD")
  end,
}
```

The two options are cards of their own in `cards.json` (not collectible), with their texts in the locales.

## Debugging

- **The pack doesn't load.** The engine names the file and line: `scripts/moon.lua:3: assignment to undeclared global 'foo' (declare it with 'local')`. Unknown globals, unknown hook names and scripts that point nowhere are caught here, before any card is played. `tools/pack_try.gd` and the game's *Import* show this message.
- **A card fails in a game.** The game ends as a draw with the error and a traceback: `scripts/sun.lua:16: attempt to call a nil value (field 'damge') (scripts/sun.lua:16: in function 'battlecry')`.
- **Build the position.** *Settings → Debug tools → Scene* (with your game active): put any cards into each player's hand, board, deck, traps and weapon with the mouse, set mana and health, and play it against the bot or for both sides. The scene is also plain JSON (the *JSON* button): copy it, change it, apply it again.
- **Common mistakes:** `0` is true (`if g.room(p) then` is always true; write `g.room(p) > 0`); positions are 0-based but arrays 1-based; an event field the event lacks is `nil` (`ev.target >= 0` fails on `nil`); `until`, `end`, `and` are keywords (`{["until"] = "use"}`); no `/`.

More on testing: [Testing and validating](testing.html). The language in full detail (escapes, `tostring`, every library function, the step accounting): [The Lua subset](../ref/lua.html).
