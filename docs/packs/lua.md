# Card scripts: the Lua subset

Card logic in a game pack is written in a small, safe subset of **Lua 5.4**.
The engine runs it with its own interpreter (crate `rust/script`,
`classichs-script`), the same on every platform: the server, the desktop and
Android builds, and the browser (WebAssembly). The same script with the same
game state always does the same thing, everywhere.

The subset is plain Lua with these changes:

- **Integers only.** Numbers are 64-bit integers. There are no floats, no `/`
  and no `^`. Use `//` for division.
- **Overflow is an error.** `math.maxinteger + 1` stops the script (Lua would wrap around).
- **No global variables of your own.** Everything you declare is `local`.
  Globals are the standard library and what the engine provides; they are read-only.
- **`pairs` visits keys in insertion order** (Lua leaves the order unspecified).
- **A sandbox.** No files, no time, no randomness, no loading code, no
  metatables, no coroutines, no `goto`.
- **Limits.** Every call into a script has a budget of steps, call depth,
  table size, string length and memory. Running out ends the script with an error.

A script that runs here gives the same results in a standard Lua 5.4,
except that the standard one wraps on overflow and may visit `pairs` in a different order.

## A script file

A script file is a *module*: it runs once when the pack is loaded and returns
a table. For card scripts that table maps card ids to the card's hooks:

```lua
-- scripts/mage.lua
local cards = {}

local function each_enemy_minion(g, me, fn)
  for _, m in ipairs(g.minions(g.enemy(me))) do
    fn(m)
  end
end

cards.FLAMESTRIKE = {
  spell = function(g, me, target)
    each_enemy_minion(g, me, function(m)
      g.damage(me, m, g.spell_dmg(me, 4))
    end)
  end,
}

return cards
```

`local` values at the top of the file (here `cards` and `each_enemy_minion`)
are shared by all of the file's functions. Prefer to keep game state in the
game (tags, stats) rather than in such variables.

## The language

### Values

| Type | Notes |
|---|---|
| `nil` | |
| `boolean` | `true`, `false`. Only `nil` and `false` count as false; `0` and `""` count as true. |
| `number` | A 64-bit signed integer (`math.mininteger` to `math.maxinteger`). Decimal (`42`) or hexadecimal (`0x2A`) literals. `1.5`, `1e3`, `0x1p4` are errors. |
| `string` | A sequence of bytes (UTF-8 text is fine). Immutable. |
| `table` | The only data structure: arrays, records and maps. |
| `function` | Lua functions (closures) and built-in functions. |

`type(v)` returns one of these names.

### Variables and scope

- `local x = 1`, `local a, b = f()`; a `local` is visible until the end of its block.
- Functions see the locals of the functions around them (closures, "upvalues").
  Two closures that see the same local share it; every loop iteration has its own copy of
  the loop variables and of the locals declared in the body.
- `local function f() ... end` can call itself.
- Any other name is a **global**: a standard library name (`ipairs`, `string`, ...)
  or something the engine provides. Globals are looked up when the file is loaded:
  an unknown name (a typo) is an error that names the file and line, before any card is played.
- Assigning to a global is a compile error: `x = 1` and `function f() end`
  both fail with `assignment to undeclared global 'x' (declare it with 'local')`.
  Write `local x = 1`, `local function f() end`.
  Assigning to a *field* is fine: `function cards.X.spell(g, me) end`, `t.x = 1`.
- `_G` and `_ENV` do not exist.

### Statements

| Statement | |
|---|---|
| `local a, b = e1, e2` | |
| `a, b = e1, e2` | All targets (table and key) and all values are evaluated first, then stored left to right. Extra values are dropped, missing ones are `nil`. `a, b = b, a` swaps. |
| `f(x)`, `obj:m(x)` | A call as a statement. |
| `do ... end` | A block. |
| `if c then ... elseif c then ... else ... end` | |
| `while c do ... end` | |
| `repeat ... until c` | The condition sees the body's locals. |
| `for i = a, b [, step] do ... end` | Integers only; `step` defaults to 1 and cannot be 0. The number of iterations is computed once at the start (so `for i = 1, math.maxinteger` does not overflow, it runs out of steps). Changing `i` inside the body does not change the loop. |
| `for k, v in pairs(t) do ... end` | Generic `for` with `pairs`, `ipairs`, `next` or any iterator function. |
| `break` | Leaves the innermost loop. |
| `return e1, e2` | Must be the last statement of its block. |
| `function a.b.c(...) end`, `function a.b:m(...) end` | Field functions; `:` adds a `self` parameter. |

### Expressions and operators

From lowest to highest precedence:

| Operators | |
|---|---|
| `or` | `a or b`: `a` if it is true, else `b`. |
| `and` | `a and b`: `a` if it is false, else `b`. |
| `<` `>` `<=` `>=` `~=` `==` | Comparisons. `<` etc. compare two numbers or two strings (byte by byte); anything else is an error. `==` never fails: values of different types are different, tables and functions are equal only to themselves. |
| `..` | Concatenation (right-associative). Works on strings and numbers (`"x" .. 1` is `"x1"`). |
| `+` `-` | |
| `*` `//` `%` | |
| `not` `#` `-` (unary) | `#s` is the length of a string in bytes; `#t` the length of an array. |

Integer arithmetic:

- `+`, `-`, `*` and unary `-` stop with `integer overflow in '+'` when the result does not fit.
- `a // b` is **floor** division: it rounds toward minus infinity. `7 // 2 == 3`, `-7 // 2 == -4`, `7 // -2 == -4`.
- `a % b` has the **sign of `b`**, so `a == (a // b) * b + a % b`: `-7 % 3 == 2`, `7 % -3 == -2`.
- `x // 0` and `x % 0` are errors. `math.mininteger // -1` is an overflow error.
- `/` and `^` are syntax errors (`'/' is not supported (no floats); use '//' for integer division`).
- Strings are never converted to numbers: `"10" + 1` is an error. Use `tonumber`.

### Functions

- `function(a, b) ... end`; missing arguments are `nil`, extra ones are dropped.
- `...` (varargs): `function(...) local first = ... ; local all = {...} end`;
  `select("#", ...)` counts them, `select(n, ...)` returns from the n-th.
- Multiple results: `return a, b`. A call in the *last* position of an argument
  list, a table constructor or a `return` passes on all its results; elsewhere,
  and inside parentheses `(f())`, only the first.
- Methods: `obj:m(x)` is `obj.m(obj, x)`. Strings have the `string` functions as
  methods: `("abc"):upper()`, `s:sub(1, 3)`.

### Tables

- Constructors: `{1, 2, 3}`, `{x = 1, y = 2}`, `{[key] = value}`, mixed `{1, x = 2}`; `,` or `;` between fields.
- `t.name` is `t["name"]`. Reading a missing key gives `nil`; assigning `nil` removes the key.
  Keys can be any value except `nil`; `t[1]` and `t["1"]` are different keys.
- `#t` is the length of the array part 1..n. If the array has holes (`{1, nil, 3}`) the result is
  some border of it (deterministic, but do not rely on it); keep arrays without holes.
- **Iteration order:** `pairs` and `next` return keys in the order they were
  added (a constructor adds left to right). Changing the value of a key keeps its place;
  a key removed (set to `nil`) and added again goes to the end, like a new key.
  Removing keys while iterating with `pairs` is allowed; adding new keys while
  iterating is not (the new key may or may not be visited).
- `ipairs(t)` visits `t[1], t[2], ...` up to the first `nil`.

### Strings and comments

- `"double"` or `'single'` quotes, with escapes `\n \t \r \a \b \f \v \\ \" \'`,
  `\ddd` (decimal byte), `\xHH` (hex byte), `\u{XXXX}` (UTF-8), `\z` (skips the
  following whitespace), and `\` before a line break.
- Long strings: `[[...]]`, `[==[...]==]`, no escapes, a first line break is dropped.
- Comments: `-- to the end of the line`, `--[[ long ]]`, `--[==[ long ]==]`.

### Not supported

| Feature | What happens |
|---|---|
| Floats, `/`, `^` | Compile error. |
| Bitwise operators `& \| ~ << >>` | Compile error. |
| `goto`, labels `::x::` | Compile error. |
| `local x <const>`, `<close>` | Compile error. |
| Global assignment, `_G`, `_ENV` | Compile error. |
| `setmetatable`, `getmetatable`, `rawget`, `rawset`, `rawequal`, `rawlen` | Load error: `'setmetatable' is not available: metatables are not supported`. |
| `coroutine` | Load error. |
| `load`, `loadstring`, `loadfile`, `dofile`, `require`, `package` | Load error: scripts cannot load code. |
| `io`, `os`, `debug`, `print`, `collectgarbage`, `utf8` | Load error: not available in the sandbox. |
| `string.dump`, `string.gsub/match/gmatch` (patterns), `table.pack/move`, `math.random`, `math.sqrt`, ... | Not present (`nil`): calling one is `attempt to call a nil value (field 'dump')`. |
| Changing a library table (`string.upper = nil`) | Runtime error: `attempt to modify a read-only table`. |

## Standard library

Arguments in `[brackets]` are optional. Wrong argument types are errors like
`bad argument #1 to 'table.insert' (table expected, got nil)`.

### Base

| Function | |
|---|---|
| `type(v)` | `"nil"`, `"boolean"`, `"number"`, `"string"`, `"table"`, `"function"`. |
| `tostring(v)` | Numbers in decimal, `nil`, `true`, `false`; tables and functions as `table: #12`, `function: #7`, `function: builtin 'pairs'` (a deterministic id, not an address). |
| `tonumber(v [, base])` | An integer from an integer or a string (`" 42 "`, `"-7"`, `"0x1F"`; with `base` 2..36: digits of that base); `nil` if it is not an integer (`"1.5"`, `"abc"`, out of range). |
| `ipairs(t)` | Iterator over `t[1], t[2], ...` until the first `nil`. |
| `pairs(t)` | Iterator over all keys in insertion order. |
| `next(t [, k])` | The key after `k` (the first key if `k` is `nil`) and its value; `nil` at the end. |
| `select(n, ...)` | The arguments from the n-th on; negative `n` counts from the end; `select("#", ...)` is their number. |
| `error(v [, level])` | Raises an error with value `v`. For a string and `level` 1 (default) the message gets the position `file:line:` of the `error` call; level 2 blames the caller of the current function; level 0 adds no position. `v` can be any value (e.g. a table). |
| `assert(v [, msg])` | Returns all its arguments if `v` is true; otherwise raises `msg` (default `"assertion failed!"`). |
| `pcall(f, ...)` | Calls `f(...)`. Returns `true, results...`, or `false, error value` for a **script** error. Limit errors (steps, depth, memory, table size, string length) and fatal engine errors are **not** caught: they end the whole call. |

### `table`

| Function | |
|---|---|
| `table.insert(t, v)` / `table.insert(t, pos, v)` | Appends, or inserts at `pos` (1..#t+1) shifting the rest up. |
| `table.remove(t [, pos])` | Removes and returns `t[pos]` (default the last), shifting the rest down. |
| `table.sort(t [, less])` | Sorts `t[1..n]` in place, **stable** (equal elements keep their order). `less(a, b)` returns true when `a` must come before `b`; the default compares numbers or strings with `<`. An inconsistent `less` gives some order, never a crash. |
| `table.concat(t [, sep [, i [, j]]])` | Joins strings and numbers `t[i..j]`. |
| `table.unpack(t [, i [, j]])` | Returns `t[i], ..., t[j]` (default `1, #t`). |

### `string`

All positions are 1-based; negative positions count from the end (-1 is the last byte).
Every string function is also a method: `s:len()`, `s:sub(2)`.

| Function | |
|---|---|
| `string.len(s)` | Length in bytes. |
| `string.sub(s, i [, j])` | Bytes `i..j` (default `j = -1`). |
| `string.upper(s)`, `string.lower(s)` | ASCII letters only. |
| `string.rep(s, n [, sep])` | `s` repeated `n` times, `sep` between. Bounded by the string limit. |
| `string.format(fmt, ...)` | Only `%d` (integer), `%s` (any value, as `tostring`) and `%%`. No widths or other conversions. |
| `string.find(s, sub [, init [, plain]])` | Plain substring search from `init`; returns the start and end positions or `nil`. Lua patterns are not supported: a `sub` containing one of `^$*+?.([%-` is an error unless `plain` is `true`. |
| `string.byte(s [, i [, j]])` | The byte values of `s[i..j]` (default `i`, `i = 1`). |
| `string.char(...)` | A string from byte values 0..255. |

### `math`

| | |
|---|---|
| `math.min(x, ...)`, `math.max(x, ...)` | |
| `math.abs(x)` | `math.abs(math.mininteger)` is an overflow error. |
| `math.clamp(x, lo, hi)` | `x` limited to `lo..hi`. |
| `math.floor(x)` | `x` (all numbers are integers; for scripts written for Lua). |
| `math.maxinteger`, `math.mininteger` | `9223372036854775807`, `-9223372036854775808`. |

There is no `math.random`: randomness comes from the game (its seeded generator), so that replays and both players agree.

### `list`

Helpers for arrays (`t[1], t[2], ...` up to the first `nil`). They never change their argument;
the functions get `(item, index)`.

| Function | |
|---|---|
| `list.filter(t, f)` | A new array of the items for which `f(item, i)` is true. |
| `list.map(t, f)` | A new array of the non-`nil` results of `f(item, i)`. |
| `list.count(t [, f])` | How many items satisfy `f` (all items without `f`). |
| `list.any(t, f)`, `list.all(t, f)` | |
| `list.sum(t [, f])` | The sum of the items (or of `f(item, i)`); they must be numbers. |
| `list.sort_by(t, key)` | A new array sorted by `key(item)` ascending (numbers or strings), stable. To sort descending, negate a number key. |

There is no `list.shuffle` or random pick here; use the game's functions.

## Limits

Each call from the engine into a script (one hook) has its own budget. When a
hook makes the engine call other hooks (for example, its damage triggers another card),
those run inside the same budget.

| Limit | Default | Error |
|---|---|---|
| Steps | 200 000 | `step limit exceeded (200000 steps per call)` |
| Call depth (Lua and built-in functions) | 200 | `stack overflow (call depth limit 200)` |
| Entries in one table | 10 000 | `table size limit exceeded (10000 entries)` |
| Bytes in one string | 65 536 (64 KiB) | `string length limit exceeded (65536 bytes)` |
| Memory allocated during the call | 16 MiB | `memory limit exceeded (16777216 bytes per call)` |

**Steps** are counted as: 1 per statement executed, 1 per loop iteration
(including the test of `while` and `repeat`), 1 per function call. Built-in
functions that loop charge 1 per element they process (`table.sort` 1 per
comparison, `table.concat` 1 per item, `list.*` 1 per item, ...). An ordinary
card hook uses tens to a few hundred steps.

**Memory** is approximate accounting, not the real heap: a new table 64 bytes,
a new key 32, a closure 32 + 8 per captured variable, a captured local 16, a
string its length + 16. Garbage made during a call is not given back to the
budget; it is collected between calls.

**Nesting.** Source code may nest at most 200 syntactic levels (blocks inside
blocks, parentheses inside parentheses, long chains of operators) per file:
deeper code is a compile error (`chunk has too many syntax levels`). At run
time the total nesting of all active calls is also bounded, so that very deep
recursion of deeply nested functions stops with `stack overflow (nesting of
active calls too deep)` instead of exhausting the native stack. Ordinary code
reaches the call depth limit first.

All limits are errors of kind *limit*: `pcall` cannot catch them, the hook
fails as a whole. In a game, a script error or a limit error ends the game as
"something does not add up" (no penalty for either player).

## Errors

Every error has a message with the file and line, and a traceback:

```
scripts/mage.lua:12: attempt to call a nil value (field 'damge')
stack traceback:
	scripts/mage.lua:12: in function 'cards.FLAMESTRIKE.spell'
	scripts/mage.lua:4: in function 'each_enemy_minion'
```

Messages name the variable when they can: `(local 'x')`, `(upvalue 'x')`,
`(global 'x')`, `(field 'x')`, `(method 'x')`. Kinds of errors:

| Kind | When | Caught by `pcall` |
|---|---|---|
| compile | Syntax errors; at load: unknown globals. The pack does not load. | — |
| runtime | `error()`, type errors (`attempt to index a nil value`), overflow, division by zero, bad arguments to built-in functions, errors raised by engine functions. | yes |
| limit | A limit above was exceeded. | no |
| fatal | An engine function refused to continue (an engine invariant). | no |

`pcall` returns the error *value*: for `error("text")` the string with its
position (`"scripts/x.lua:3: text"`), for `error({code = 1})` the table itself.

## Determinism

Everything a script can observe is determined by the script and the game state:
integer arithmetic only, `pairs` in insertion order, stable sorting,
`tostring` of tables and functions shows a deterministic id (never an address),
no clock, no randomness, no environment. The engine can copy the whole script state
together with the game (for the bot's look-ahead) and both copies continue identically.

## Examples

These are written against a toy engine with functions like the real one's
(`g.minions`, `g.damage`, ...; the real `g` is in [api.md](api.md)). Hook names follow the
plan: `spell`, `battlecry`, `deathrattle`, `on = {event = fn}`, `aura`, ...

**Deal 4 damage to all enemy minions** (a spell):

```lua
cards.FLAMESTRIKE = {
  spell = function(g, me, target)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, g.spell_dmg(me, 4))
    end
  end,
}
```

**Whenever this minion takes damage, draw a card** (an event hook):

```lua
cards.ACOLYTE = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        g.draw(g.ctrl(me))
      end
    end,
  },
}
```

**Your other minions have +1 attack** (an aura; the engine recomputes auras after every change):

```lua
cards.RAID_LEADER = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      g.aura_add(m, 1)
    end
  end,
}
```

**Battlecry: deal 1 damage to each damaged enemy, then gain +1/+1 for each** (helpers from `list`):

```lua
cards.EXAMPLE = {
  battlecry = function(g, me, target)
    local hurt = list.filter(g.chars(g.enemy(me)), function(c) return g.tag(c, "DAMAGE") > 0 end)
    for _, c in ipairs(hurt) do
      g.damage(me, c, 1)
    end
    g.buff(me, #hurt, #hurt)
  end,
}
```

These examples (with a toy engine) are tests: `rust/script/tests/host.rs`.

## Engine functions (`g`)

*The engine's functions, the hooks a card can have and the events they get are in
[api.md](api.md); this section explains how engine functions appear to scripts.*

- The engine registers its functions in the interpreter before the pack's files
  are loaded. They are built-in functions like the standard library: some are globals,
  most live in one read-only table, `g`, which is also passed to every hook as its first
  argument (`spell = function(g, me, target)`).
- Arguments and results are plain values: entity ids and player numbers are
  integers, card ids and tags are strings, lists of entities are arrays
  (`for _, m in ipairs(g.minions(p))`), events are tables (`ev.target`, `ev.amount`).
- An engine function checks its arguments; a wrong one is a runtime error at the line
  of the call: `scripts/mage.lua:7: bad argument #2 to 'g.damage' (number expected, got nil)`.
- Engine functions may call other cards' hooks (a damage triggers "whenever this
  takes damage"); those run within the same call budget.
- Scripts cannot change `g` or any library table.

### For engine developers (Rust)

```rust
use classichs_script::{compile, load, call_path, Args, Error, Host, Value, Vm};

struct Game { vm: Vm<Game>, /* ... */ }
impl Host for Game { fn vm(&mut self) -> &mut Vm<Game> { &mut self.vm } }

fn damage(g: &mut Game, a: Args) -> Result<Vec<Value>, Error> {
    let (src, target, amount) = (a.int(0)?, a.int(1)?, a.int(2)?);
    // ... change the game; may call other hooks with classichs_script::call(g, ...)
    Ok(vec![])
}

let mut vm = Vm::new();                         // standard library, default limits
vm.lib("g", &[("g.damage", damage)]);           // read-only global table `g`
let chunk = compile("scripts/mage.lua", src)?;  // parse once; Chunk is Send + Sync, share it
let mut game = Game { vm, /* ... */ };
load(&mut game, "mage", &chunk)?;               // runs the file, keeps its table as module "mage"
let g = game.vm.global("g");
call_path(&mut game, "mage", &["FLAMESTRIKE", "spell"], &[g, Value::Int(me), Value::Nil])?;
```

- `Host` gives the interpreter the VM inside your state, so engine functions get
  `&mut Game` and can call back into scripts (`call`, `call_path`) re-entrantly.
- Values: `Value::{Nil, Bool, Int, Str, Table, Func, Native}`; `From` for `i64`, `bool`,
  `&str`, `String`, `Option<T>`; `vm.list(vec)`, `vm.list_items(&t)`, `vm.pairs(&t)`,
  `vm.get(&t, k)`, `vm.set(&t, k, v)`, `vm.freeze(&t)`, `vm.display(&v)`; `Args::{int, opt_int, string, bytes, table, func, get}`.
- Tables and functions live in the VM's heap (`Value::Table(Ref)`), so the VM is
  `Send` and `Clone` (a clone copies the whole Lua state). Garbage is collected at the
  start of a top-level call when the heap has grown: values reachable from loaded modules,
  globals, pinned values (`vm.pin`) and the call's arguments survive; any other value you keep
  in Rust across calls may be collected (using it then is an error, never another object).
- `Error`: `kind()` (`Compile`, `Runtime`, `Limit`, `Fatal`), `message`, `value`, `traceback`;
  `Display` prints the message and the traceback. Engine functions return
  `Error::runtime(msg)` (scripts can catch it; the position is added) or `Error::fatal(msg)`.
- Limits: `vm.limits` (`Limits { steps, depth, table_size, string_len, alloc }`).

## Performance

Measured on an Apple M-series laptop (`cargo run --release -p classichs-script --example bench`),
and in WebAssembly under Node 24 (V8), built with `opt-level = "s"` and LTO like the browser build:

| | native | wasm |
|---|---|---|
| Loop of 1 000 000 iterations of `s = s + i % 7` | 28 ms (28 ns/iteration) | 43 ms |
| A small hook (`return n * 2 + me`) called 100 000 times from Rust | 8.5 ms (85 ns/call) | 12 ms |
| A spell hook (`ipairs` over `g.minions`, 3 × `g.damage`) called 100 000 times | 98 ms (1.0 µs/call) | 119 ms |
| Compile and load a small file | ~0.1 ms | |

Scripts are compiled once to a tree with resolved variables (locals in frame
slots, captured locals in shared cells, globals bound at load time) and run by a
tree-walking interpreter; there is no bytecode.
