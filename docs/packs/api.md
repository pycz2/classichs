# Card scripts: the engine API (`g`) and hooks

How a pack's Lua scripts talk to the engine (`rust/engine`, phase B of
`docs/superpowers/plans/2026-10-16-game-packs.md`). The language itself (an
integers-only, sandboxed Lua 5.4 subset, its limits and standard library) is in
[lua.md](lua.md); the files of a pack in [format.md](format.md).

Contents: [script files](#script-files) · [hooks](#hooks) · [events](#events) ·
[the `g` library](#the-g-library) · [errors and limits](#errors-and-limits) ·
[porting a Classic class from Rust](#porting-a-classic-class-from-rust)

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
| `target` | `"any"` \| `{base = …, filter = fn(g, me, t) → bool}` | The card (or power) needs a target. Bases: `any`, `minion`, `enemy_minion`, `friendly_minion`, `enemy_char`, `friendly_char`, `enemy_hero`. Enemy STEALTH is never a target; SPELLPROOF blocks spells and powers. A minion's battlecry target is optional (no valid target: it is played without one); a spell's is required. `filter` is read-only. |
| `battlecry` (alias `on_play`) | `fn(g, me, t)` | A minion or weapon is played from the hand (after it is on the board / before it is equipped). |
| `spell` | `fn(g, me, t)` | A spell is cast (not if countered). |
| `combo` | `fn(g, me, t)` | Instead of `battlecry`/`spell` when another card was played before it this turn. |
| `combo_target` | like `target` | The target spec while combo is active (no target without combo). |
| `choose_one` | `{"OPTION_A", "OPTION_B"}` | Two option *cards*; the player picks one (`choice` 0/1); the option card's `target` and `effect` are used. |
| `effect` | `fn(g, me, t)` | On a Choose One option card: what the option does (`me` is the played card). |
| `hero_power` | `fn(g, me, t)` | On a POWER card: the power is used. |
| `can_play` | `fn(g, me) → bool` | The card/power may be played now (read-only). |
| `deathrattle` (alias `on_death`) | `fn(g, me)` | It died (minion or weapon; `g.died_pos(me)` is where). |
| `on` | `{<event type> = fn(g, me, ev)}` | Any event of that type while `me` is in play (or a trap). Queued: runs after the action that caused it. |
| `now` | `{predamage = fn(g, me, ev)}` | Replacement effects: runs at once, inside `g.damage`, before damage applies; set `ev.amount` to change it. |
| `secret` (alias `trap`) | `{event = "<type>", cond = fn(g, me, ev) → bool, effect = fn(g, me, ev)}` | A trap: on `event` during the opponent's turn, if `cond` (omitted: always) holds, the trap is revealed, then `effect` runs. |
| `aura` | `fn(g, me)` | Recomputed after every change while `me` is in play: call `g.aura_add` for what it gives now. |
| `aura_final` | `fn(g, me)` | Like `aura`, after every other aura (Lightspawn: attack = health). |
| `cost_mod` | `fn(g, me) → int` | Added to this card's cost (read-only). |
| `cost_aura` | `fn(g, me, card, cost) → int` | While `me` is in play: the new cost of any `card` (read-only; return `cost` to leave it). |
| `on_choose` | `fn(g, me, option, still)` | The player chose `option` of a `g.request_choice` (`still`: the offered ids still where they were). |
| `immune_while_attacking` | `true` | A weapon: its champion is IMMUNE while attacking with it. |
| `durability_on_attack` | `fn(g, w, defender) → bool` | A weapon: whether attacking costs durability (default yes). |

**Read-only hooks** (`target.filter`, `can_play`, `cost_mod`, `cost_aura`) run
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
| `play` | `entity`, `player`, `card`, `kind` (`minion`/`spell`/`weapon`), `target`; spells: `secret`, `countered` | Before the card's effect. `countered = true` (spells) stops it. Changing `target` redirects a spell. |
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
| `hero_power` | `player`, `entity`, `target` | After the power's effect. |
| `secret_revealed` | `entity`, `player`, `card` | |
| `turn_start`, `turn_end` | `player` (+ `turn`) | `turn_end` hooks run before "this turn" effects end. |

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
| `g.traps(p)` | `p`'s traps (secrets) in play. |
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
| `g.cards_played(p)`, `g.minions_played(p)` | This turn (Combo: `g.combo(e)` = a card was played before). |
| `g.room(p)` | Free board slots (`g.room(p) > 0`: room for one; note `0` is true in Lua). |
| `g.board_pos(m)` | Its 0-based position, or `nil`. |
| `g.died_pos(m)` | Where a dead minion stood (0-based), or `-1`. |
| `g.trap_ready(me)` | `me` is a trap in play and it is the opponent's turn. |
| `g.spell_dmg(me, n)` | `n` plus `me`'s side spell power, doubled per POWER_MULTIPLIER (spells and powers). |
| `g.heal_amt(me, n)`, `g.hp_dmg(me, n)` | Healing / power damage `n` after POWER_MULTIPLIER. |
| `g.rule(name)` | `hand`, `board`, `max_mana`, `deck_size`, `champion_health` from rules.json. |
| `g.mine(me, ev)` | `ev.player` is `me`'s controller. |
| `g.enchants(e, hooks)` | The `player` fields of `e`'s enchantments with these hooks. |
| `g.info(card)` | A card's data: `{id, type, class, rarity, set, cost, attack, health, durability, race, mana_lock, spell_power, collectible, keywords, trap}`. |
| `g.collectible()` | Collectible card ids of the constructed sets, sorted. |

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
| `g.draw_entity(p, e)` | Draws that card of `p`'s deck. |
| `g.add_to_hand(p, card)` | A new card in hand (or `nil` if full). |
| `g.discard_random(p[, n])`, `g.discard(e)` | Discards (emits `discard`). |
| `g.buff(e, atk, hp[, this_turn])` | An enchantment +atk/+hp (`true`: until the end of the turn). |
| `g.set_stats(e, atk, hp)` | Sets attack and/or health (`nil` keeps one); setting health heals. |
| `g.silence(e)`, `g.freeze(e)` | |
| `g.transform(e, card)` | Replaces a minion with a new one; returns it. |
| `g.return_to_hand(e)` | Returns a minion as a fresh card; returns the new card or `nil`. |
| `g.take_control(e, p)` | |
| `g.copy_minion(me, t)` | Turns `me` into a copy of `t` (stats, enchantments, tags, silence). |
| `g.equip(p, card)` | A new weapon (the old one is destroyed). |
| `g.gain_armor(p, n)` | |
| `g.gain_mana(p, n[, empty])` | Crystals up to max mana (`empty`: empty crystals). |
| `g.add_mana(p, n)` | Mana this turn (up to max mana; The Coin). |
| `g.set_mana(p, mana, max)` | Sets mana and/or crystals (`nil` keeps one). |
| `g.set_tag(e, tag, v)` | `v`: boolean, number, string; `nil` removes. |
| `g.give_tag(e, tag[, this_turn])`, `g.erase_tag(e, tag)`, `g.add_tag(e, tag, n)` | |
| `g.set_damage(e, n)` | Sets the damage taken (Alexstrasza). |
| `g.enchant(e, t)` | Adds an enchantment table: `{hooks = name, player = p}`, `{cost = -2}`, `{atk = 1, hp = 1, eot = true}`, … |
| `g.remove_enchant(e, hooks)` | Removes `e`'s enchantments with these hooks. |
| `g.aura_add(e, atk, hp[, tags])` | In an `aura` hook: what `e` gets now (`{WINDFURY = true}`, `{SPELLPOWER = 1}`). |
| `g.replace_hero(p, card)`, `g.set_power(p, card)` | A new champion / power. |
| `g.reveal(me)` | Reveals a trap (for `now` hooks; `secret` hooks are revealed for you). |
| `g.request_choice(me, ids)` | The player must choose one of these entities; `on_choose` gets it. |
| `g.add_cost_mod(p, t)` | `{kind = "spell"|"minion"|"secret"|"any", set = n or delta = n, until = "use"|"turn_end"[, turn = n]}`; `turn` defaults to now. |
| `g.log(ev)`, `g.emit(ev)` | Logs an event table (`emit` also triggers `on` hooks). |
| `g.remove(e[, zone])` | Takes `e` out of its hand/deck/board/trap list (and the weapon slot), optionally setting its zone. |
| `g.cost(e)` | A card's cost now (cost hooks included). |
| `g.random(lo, hi)` | A random integer `lo..hi` from the game's generator. |
| `g.pick(list)` | A random item (or `nil` for an empty list). |
| `g.random_alive(list)` | A random item that is in play and not dying, or `nil`. |
| `g.shuffle(list)` | Shuffles the list in place (and returns it). |

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

## Porting a Classic class from Rust

The Classic pack's hooks are moving from `rust/engine/src/cards/<class>.rs`
to `packs/classic/scripts/<class>.lua`. A card with a `script` field uses Lua;
a card without one still uses its Rust hook (the fallback goes away with the
last Rust file). Done: `mage.lua` (all Mage cards, Fireblast), `neutral.lua`
(the Basic neutral cards, The Coin), `warlock.lua`, `hunter.lua`, `lib.lua`.

Left: `druid.rs`, `paladin.rs`, `priest.rs`, `rogue.rs`,
`shaman.rs`, `warrior.rs`, `heroes.rs` (the other powers),
`neutral.rs` (common to legendary and tokens), `tutorial.rs` (boss cards and
the `ench:tutorial_guard` / `ench:transcendence` hooks).

### Steps

1. Create `packs/classic/scripts/<class>.lua` (one file per class; tokens and
   the class's `ench:*` hooks go with it). Translate each `r.insert(id, Hooks {…})`
   to `cards.<id> = {…}` (table below). Shared helpers go to `lib.lua`.
2. Point the cards at it — add `"script": "scripts/<class>.lua#<id>"` to each
   card's line in `packs/classic/cards.patch.json` (keep one card per line; the
   file is shared, so only touch your cards' lines). Choose One option cards
   (`VAN_EX1_160a`) are cards too and need their own `script`. This adds the
   field for every `cards.<id> =` line of the given files:

   ```sh
   python3 - packs/classic/scripts/<class>.lua <<'EOF'
   import json, re, sys
   src = "packs/classic/cards.patch.json"; patch = json.load(open(src))
   for f in sys.argv[1:]:
       for key in re.findall(r'^cards\.([A-Za-z0-9_]+)\s*=', open(f).read(), re.M):
           patch.setdefault(key, {})["script"] = f"scripts/{f.split('/')[-1]}#{key}"
   patch = dict(sorted(patch.items()))
   body = ",\n".join(f"  {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}" for k, v in patch.items())
   open(src, "w").write("{\n" + body + "\n}\n")
   EOF
   ```

   Named enchantment hooks (`"ench:…"`) need no field: they are found by name.
3. Delete the ported `r.insert` blocks (or the whole `<class>.rs` and its two
   lines in `cards/mod.rs`).
4. Check parity for the class, then everything:

   ```sh
   cd rust
   # quick (~3 s): the committed 1731 games that mention a Warrior card
   PARITY_BIG=0 PARITY_FILTER=WARRIOR cargo test -p classichs-engine --test parity -- --nocapture
   # a few cards, all fixtures
   PARITY_FILTER=VAN_EX1_398,VAN_EX1_407 cargo test -p classichs-engine --test parity -- --nocapture
   # before you are done: everything, 7833 games (~80 s)
   cargo test -p classichs-engine -- --nocapture
   ```

   `PARITY_FILTER` takes card ids, class names and `lua` (every card with Lua
   hooks), comma-separated; a game is replayed if its recorded line mentions
   any of them (random decks mention many classes, so a class still selects
   most of the big set: ~55 s). `PARITY_BIG=0` skips `fixtures/big`. The first lines of a mismatch report show the step, the action
   and what differs. The Lua files are built into the engine (build.rs), so a
   test run always uses the current scripts. `builtin_rules_hash_matches_pack_py`
   (tests/packs.rs) checks the built-in ruleset against `tools/pack.py`.

### Rust → Lua

| Rust | Lua |
|---|---|
| `Hooks { target: ANY, spell: Some(\|g, me, t\| …), ..d() }` | `{ target = "any", spell = function(g, me, t) … end }` |
| `spec_if(Base::Minion, pred)` | `target = { base = "minion", filter = function(g, me, t) return … end }` |
| `on: vec![("turn_end", f)]` | `on = { turn_end = function(g, me, ev) … end }` |
| `secret: Some(Secret { event, cond, effect })` | `secret = { event = "attack", cond = function(g, me, ev) … end, effect = … }` |
| `now: vec![("predamage", f)]` (`ev.insert("amount", …)`) | `now = { predamage = function(g, me, ev) ev.amount = 0 end }` |
| `g.ctrl(me)`, `g.foe(me)`, `1 - p` | `g.ctrl(me)`, `g.enemy(me)`, `g.opponent(p)` |
| `ev_mine(g, me, ev)` | `g.mine(me, ev)` |
| `g.ev_i(ev, "target")`, `g.ev_s(ev, "kind")`, `g.ev_b(ev, "played")` | `ev.target`, `ev.kind`, `ev.played` |
| `g.ev_set(ev, "countered", json!(true))` | `ev.countered = true` |
| `g.e(t).has("TAUNT")`, `.tag("ARMOR")`, `.atk()`, `.health()`, `.damage`, `.race()`, `.is_minion()`, `.card_id`, `.zone` | `g.has(t, "TAUNT")`, `g.tag(t, "ARMOR")`, `g.atk(t)`, `g.health(t)`, `g.dmg(t)`, `g.race(t)`, `g.is_minion(t)`, `g.card(t)`, `g.zone(t)` |
| `g.em(m).give_tag("TAUNT", false)`, `.erase_tag(…)`, `g.add_tag_int(w, "DURABILITY", -1)` | `g.give_tag(m, "TAUNT")`, `g.erase_tag(m, …)`, `g.add_tag(w, "DURABILITY", -1)` |
| `g.em(t).add_enchant(json!({"hooks": "ench:x", "player": p}))` | `g.enchant(t, { hooks = "ench:x", player = p })` |
| `g.weapon(p)` (`Option`), `g.weapon_of(p)` (`NONE`) | `g.weapon(p)` (`nil`) |
| `g.board_has_room(me)`, `MAX_BOARD` | `g.room(g.ctrl(me)) > 0`, `g.rule("board")` |
| `g.players[p].hand / deck / board / secrets` | `g.hand(p)`, `g.deck(p)`, `g.minions(p)`, `g.traps(p)` |
| `g.players[p].mana = MAX_MANA.min(mana + 2)` | `g.add_mana(p, 2)` |
| `g.players[p].cards_played_this_turn` | `g.cards_played(p)` |
| `g.random_choice(&v)`, `g.pick(&v)`, `g.rng.randi_range(a, b)`, `g.shuffle_ids(&mut v)` | `g.pick(v)`, `g.pick(v)`, `g.random(a, b)`, `g.shuffle(v)` |
| `g.random_alive(&v)` (`NONE`) | `g.random_alive(v)` (`nil`) |
| `card_db::card(id).race` | `g.info(id).race` |
| `x.retain(…); g.em(e).zone = "GRAVEYARD"; g.log_event(json!({…}))` | `g.remove(e, "GRAVEYARD"); g.log{ type = "discard", … }` |
| `g.died_pos(me)` | `g.died_pos(me)` |
| `copy_minion(g, me, t)` | `g.copy_minion(me, t)` |
| `for _ in 0..n` | `for _ = 1, n do … end` |
| `if t != NONE` | `if t then` (queries) / `if t >= 0 then` (event fields) |

### Pitfalls

- **Same order, same randomness.** Parity compares every event and the RNG
  state: call `g.pick`/`g.random`/`g.random_alive` exactly where the Rust did,
  as many times, on lists in the same order; compute things inside a loop if the
  Rust did (`g.spell_dmg` per target), keep event order (damage before freeze…).
- `nil` vs `-1`: queries and actions return `nil` for "none"; events keep `-1`.
  `ev.field` is `nil` when the event lacks it — `nil >= 0` is an error.
- `0` and `""` are **true** in Lua: write `g.room(p) > 0`, `#list > 0`.
- Positions are 0-based (`g.summon(p, card, g.died_pos(me))`), lists 1-based.
- `until`, `end`, `and`, `or`, `not` are keywords: `{ ["until"] = "use" }`.
- No `continue`, no `/` (use `//`), no floats, no global variables.
- Read-only hooks (`target.filter`, `can_play`, `cost_mod`, `cost_aura`) see
  only queries: no `g.cost`, no actions.
- `g.tag` adds aura values (`SPELLPOWER` from an aura counts); `g.add_tag`
  changes only the entity's own tag, like Rust `add_tag_int`.
- An `on` hook's changes to `ev` are written back; a copy of `ev` is not.
- Do not keep game state in file-level locals (see [script files](#script-files)).
- `cards.patch.json` and `lib.lua` are shared by everyone porting: add, do not
  reorder; prefer class-local helpers in your own file.
