# Своя игра

**Пак игры** — всё, что превращает карточную игру в конкретную игру: правила, чемпионы, карты и что они делают, названия механик, тексты на всех языках, картинки, звуки, музыка, колоды, миссии и оформление. Движок {name} знает только нейтральные механики («существо, которое надо атаковать первым», «эффект при розыгрыше»); пак даёт им имена и наполняет содержимым.

Пак — это один файл **`.cardpack`**: zip-архив с фиксированной структурой. Вы пишете его как папку с обычными файлами, а `tools/pack.py` упаковывает её, проверяет и ставит хэши.

## Целый пак в десяти файлах

**Tiny Duel** — самый маленький пак, в который можно играть: Королева Солнца против Короля Луны, колоды по восемь карт, простое существо, существо с «Провокацией», боевой клич с целью, аура, предсмертный хрип и секрет. Ниже все файлы; вместе это игра, которую можно добавить в {name} и сыграть.

```
tiny/
  manifest.json        кто и что
  rules.json           ограничения, начало партии, классы, редкости, механики, режимы
  cards.json           все карты: числа, ключевые слова, какой скрипт у карты
  scripts/sun.lua      карты Королевы Солнца
  scripts/moon.lua     карты Короля Луны
  scripts/neutral.lua  лишняя карта второго игрока
  locales/en.json      названия и тексты по-английски
  locales/ru.json      … и по-русски
  decks/1_dawn.json    готовая колода для каждого чемпиона
  decks/2_dusk.json
```

`manifest.json`:

```json
{
  "format": 1,
  "id": "tiny-duel",
  "version": "0.1.0",
  "engine": "0.28.0",
  "name": {"en": "Tiny Duel", "ru": "Маленькая дуэль"},
  "description": {"en": "Sun against Moon: two champions, a handful of cards."},
  "authors": ["Your Name"],
  "license": "CC BY 4.0",
  "redistributable": true,
  "default_locale": "en",
  "locales": ["en", "ru"],
  "art_sets": [], "sound_sets": [], "music_sets": [],
  "colors": {"classes": {"SUN": "f59f00", "MOON": "5c7cfa", "NEUTRAL": "868e96"}}
}
```

`rules.json`:

```json
{
  "format": 1,
  "limits": {"champion_health": 20, "max_mana": 10, "hand": 10, "board": 7, "deck_size": 8, "copies": 2},
  "start": {"first_player": "random", "hand": [3, 4], "coin": "spark", "mulligan": true},
  "bot": {"trap": 2},
  "fatigue": {"enabled": true, "first": 1, "step": 1},
  "timers": {"turn": 75, "fuse": 15, "mulligan": 45},
  "default_power": "sunbeam",
  "classes": [
    {"id": "SUN", "champion": "sun_queen"},
    {"id": "MOON", "champion": "moon_king"},
    {"id": "NEUTRAL", "neutral": true}
  ],
  "rarities": [{"id": "COMMON", "tier": "common"}, {"id": "RARE", "tier": "rare"}],
  "sets": ["core", "token"],
  "mechanics": {
    "WALL": {"engine": "GUARD"},
    "CRY": {"engine": "ON_PLAY"},
    "LAST_WORD": {"engine": "ON_DEATH"},
    "AMBUSH": {"engine": "TRAP"}
  },
  "modes": {"constructed": {"sets": ["core"], "class_cards": "own_and_neutral"}}
}
```

`cards.json` — чемпионы и их силы тоже карты; `spark` — то, что второй игрок получает после замены карт (`start.coin`):

```json
[
  {"id": "sun_queen", "type": "CHAMPION", "class": "SUN", "set": "core", "health": 20, "power": "sunbeam"},
  {"id": "sunbeam", "type": "POWER", "class": "SUN", "set": "core", "cost": 2, "script": "scripts/sun.lua#sunbeam"},
  {"id": "moon_king", "type": "CHAMPION", "class": "MOON", "set": "core", "health": 20, "power": "moonlight"},
  {"id": "moonlight", "type": "POWER", "class": "MOON", "set": "core", "cost": 2, "script": "scripts/moon.lua#moonlight"},
  {"id": "spark", "type": "SPELL", "class": "NEUTRAL", "set": "token", "cost": 0, "script": "scripts/neutral.lua#spark"},

  {"id": "squire", "type": "MINION", "class": "NEUTRAL", "rarity": "COMMON", "set": "core", "collectible": true,
   "cost": 1, "attack": 2, "health": 1},
  {"id": "shield_bearer", "type": "MINION", "class": "NEUTRAL", "rarity": "COMMON", "set": "core", "collectible": true,
   "cost": 2, "attack": 1, "health": 4, "keywords": ["WALL"]},
  {"id": "archer", "type": "MINION", "class": "SUN", "rarity": "COMMON", "set": "core", "collectible": true,
   "cost": 2, "attack": 2, "health": 2, "keywords": ["CRY"], "script": "scripts/sun.lua#archer"},
  {"id": "banner", "type": "MINION", "class": "SUN", "rarity": "RARE", "set": "core", "collectible": true,
   "cost": 3, "attack": 2, "health": 3, "script": "scripts/sun.lua#banner"},
  {"id": "moon_wolf", "type": "MINION", "class": "MOON", "rarity": "COMMON", "set": "core", "collectible": true,
   "cost": 3, "attack": 3, "health": 2, "keywords": ["LAST_WORD"], "script": "scripts/moon.lua#moon_wolf"},
  {"id": "cub", "type": "MINION", "class": "MOON", "set": "token", "cost": 1, "attack": 1, "health": 1},
  {"id": "ambush", "type": "SPELL", "class": "MOON", "rarity": "RARE", "set": "core", "collectible": true,
   "cost": 2, "keywords": ["AMBUSH"], "script": "scripts/moon.lua#ambush"}
]
```

`scripts/sun.lua` (скрипты разобраны по шагам на странице [Скрипты карт на Lua](lua.html#разобранные-примеры)):

```lua
local cards = {}

cards.sunbeam = {                       -- сила чемпиона: 1 урона
  target = "any",
  hero_power = function(g, me, t) g.damage(me, t, g.hp_dmg(me, 1)) end,
}

cards.archer = {                        -- Клич: 1 урона вражескому существу
  target = "enemy_minion",
  battlecry = function(g, me, t) g.damage(me, t, 1) end,
}

cards.banner = {                        -- другие ваши существа получают +1 к атаке
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do g.aura_add(m, 1, 0) end
  end,
}

return cards
```

`scripts/moon.lua`:

```lua
local cards = {}

cards.moonlight = {                     -- сила чемпиона: восстановить 2 здоровья
  target = "any",
  hero_power = function(g, me, t) g.heal(me, t, g.heal_amt(me, 2)) end,
}

cards.moon_wolf = {                     -- Последнее слово: призвать Волчонка 1/1 на своё место
  deathrattle = function(g, me) g.summon(g.ctrl(me), "cub", g.died_pos(me)) end,
}

cards.ambush = {                        -- секрет: когда противник разыгрывает существо, 2 урона ему
  secret = {
    event = "after_summon",
    cond = function(g, me, ev) return ev.played and not g.mine(me, ev) end,
    effect = function(g, me, ev) g.damage(me, ev.entity, g.spell_dmg(me, 2)) end,
  },
}

return cards
```

`scripts/neutral.lua`:

```lua
local cards = {}
cards.spark = { spell = function(g, me) g.add_mana(g.ctrl(me), 1) end }
return cards
```

`locales/ru.json` (`en.json` — то же по-английски):

```json
{
  "cards": {
    "sun_queen": {"name": "Королева Солнца"},
    "sunbeam": {"name": "Солнечный луч", "text": "Наносит 1 ед. урона."},
    "moon_king": {"name": "Король Луны"},
    "moonlight": {"name": "Лунный свет", "text": "Восстанавливает #2 ед. здоровья."},
    "spark": {"name": "Искра", "text": "Даёт 1 ману до конца хода."},
    "squire": {"name": "Оруженосец"},
    "shield_bearer": {"name": "Щитоносец", "text": "<b>Стена</b>"},
    "archer": {"name": "Лучница", "text": "<b>Клич:</b> наносит 1 ед. урона вражескому существу."},
    "banner": {"name": "Знамя", "text": "Другие ваши существа получают +1 к атаке."},
    "moon_wolf": {"name": "Лунный волк", "text": "<b>Последнее слово:</b> призывает Волчонка 1/1."},
    "cub": {"name": "Волчонок"},
    "ambush": {"name": "Засада", "text": "<b>Засада:</b> когда противник разыгрывает существо, наносит ему $2 ед. урона."}
  },
  "mechanics": {
    "WALL": {"name": "Стена", "tip": "Враги должны сначала атаковать существ со «Стеной»."},
    "CRY": {"name": "Клич", "tip": "Срабатывает, когда вы разыгрываете карту из руки."},
    "LAST_WORD": {"name": "Последнее слово", "tip": "Срабатывает, когда существо погибает."},
    "AMBUSH": {"name": "Засада", "tip": "Скрыта, пока противник не сделает то, чего она ждёт."}
  },
  "classes": {"SUN": "Солнце", "MOON": "Луна", "NEUTRAL": "Нейтральные"},
  "rarities": {"COMMON": "Обычная", "RARE": "Редкая"}
}
```

`decks/1_dawn.json` и `decks/2_dusk.json`:

```json
{"name": "Dawn", "champion": "sun_queen",
 "cards": ["squire", "squire", "shield_bearer", "shield_bearer", "archer", "archer", "banner", "banner"]}

{"name": "Dusk", "champion": "moon_king",
 "cards": ["squire", "squire", "shield_bearer", "shield_bearer", "moon_wolf", "moon_wolf", "ambush", "ambush"]}
```

Соберите, проверьте, сыграйте:

```sh
python3 tools/pack.py build tiny -o tiny.cardpack        # упаковывает, проверяет, пишет rules_hash
godot --headless --path . --script res://tools/pack_try.gd -- tiny.cardpack 4
# loaded tiny-duel 0.1.0, rules_hash 7705adf3…
# game 1: Dawn vs Dusk, turn 14, 51 actions, won by Dawn
# …
```

Потом в {name}: *Игры → Добавить файл игры*, выберите `tiny.cardpack`, *Играть в эту игру* — и начните тренировку против бота.

## Файлы пака

| Путь | Что это | Нужен |
|---|---|---|
| `manifest.json` | Кто и что: id, версия, названия, языки, наборы артов/звуков/музыки, хэши | да |
| `rules.json` | Ограничения, начало партии, бот, усталость, таймеры, классы, расы, редкости, наборы, механики, режимы, ранги | да |
| `cards.json` | Все карты: чемпионы, силы, существа, заклинания, оружие, токены | да |
| `scripts/*.lua` | Логика карт, любые папки внутри `scripts/`; `scripts/lib.lua` — общие помощники | для карт с особым текстом |
| `locales/<lang>.json` | Все тексты, которые видит игрок, по файлу на язык | по одному на язык из манифеста |
| `layout/<lang>.json` | Ручная раскладка текста на картах | нет |
| `art/<set>/<card id>.jpg\|png\|webp` | Картинки карт, папка на каждый набор артов (512 px хватит) | нет: карта без арта получает нарисованную картинку |
| `sounds/<set>/<name>.opus\|ogg\|wav\|mp3` | Звуки событий, папка на каждый набор | нет |
| `music/<set>/<name>.opus\|ogg\|wav\|mp3` | `menu`, `battle_1` … `battle_N` | нет |
| `voice/<lang>/<card id>_<kind>.opus` | Записанные реплики | нет |
| `ui/…` | Картинки `card_back`, `logo`, `menu`, `board`, `library`, `result_victory`/`_defeat`/`_draw`; `theme.json` и `fonts/` | нет |
| `decks/<name>.json` | Готовые колоды (порядок — по именам файлов) | желательно |
| `missions/<n>.json` | Миссии обучения или сюжета | нет |
| `README.md`, `CREDITS.md`, `LICENSE.txt` | Для людей | нет |

Больше ничего в архиве быть не может. Часть пути — буквы, цифры, `_`, `.` и `-` (начинается с буквы, цифры или `_`), весь путь не длиннее 200 символов; ни скрытых файлов, ни ссылок, ни одного файла дважды.

## manifest.json

| Поле | Тип | Смысл |
|---|---|---|
| `format` | `1` | Версия формата. Движок отказывается от формата, которого не знает. |
| `id` | `[a-z0-9][a-z0-9._-]{0,63}` | Постоянный id вашей игры (`neon`, `classic-2014`). Не меняйте его между версиями. |
| `version` | `"X.Y.Z"` | Для людей. Паки различают хэши, а не версия. |
| `engine` | `"X.Y.Z"` | Самая ранняя версия {name}, для которой сделан пак. |
| `name`, `description` | `{lang: текст}` | Видны в списке игр. |
| `authors` | `[строка]` | |
| `license` | строка | Кому что принадлежит, свободным текстом. |
| `redistributable` | bool | Вы разрешаете передавать пак дальше: друг получит его автоматически в сетевой игре, сервер может раздавать. Без этого другим нужен тот же файл. |
| `default_locale` | язык | Запасной язык; должен быть в `locales`. |
| `locales` | `[язык]` | `en`, `ru`, `de`, `fr`, `es`, `pt_BR`, `it`, `pl`…; у каждого свой `locales/<lang>.json`. |
| `art_sets`, `sound_sets`, `music_sets` | `[{id, name?, default?}]` | По записи на каждую папку `art/`, `sounds/`, `music/`; `default` — не больше одного. Игроки выбирают между ними в *Играх*. |
| `card_back`, `logo` | `"ui/<file>"` | Необязательные картинки. |
| `colors` | `{classes: {id: "rrggbb"}, rarities: {id: "rrggbb"}}` | Цвета рамок и камней. |
| `fx`, `rules_hash` | — | Пишет `pack.py build`; сами не пишите. |

## rules.json

Только целые числа. Необязательное поле получает значение движка по умолчанию (как в Classic).

| Раздел | Поля |
|---|---|
| `limits` | `champion_health` (30), `max_mana` (10), `hand` (10: карта, взятая в полную руку, сгорает), `board` (7 существ на сторону), `deck_size` (30), `copies` (2), `copies_by_rarity` (`{"LEGENDARY": 1}`), `queue_steps` (5000: предохранитель) |
| `start` | `first_player` (`"random"`), `hand` (`[3, 4]`: карты первого и второго игрока), `coin` (карта второму игроку или null), `mulligan` (true), `first_player_draws` (true) |
| `bot` | `trap` (во сколько бот ценит свой секрет на столе; 0 — никогда не играет секреты, 2 — как в Neonfall), `depth` (2 — пробует и два действия подряд) |
| `fatigue` | `enabled`, `first`, `step`: урон при взятии карты из пустой колоды |
| `timers` | секунды: `turn` (75), `fuse` (15), `mulligan` (45), `grace` (5), `away` (30) |
| `default_power` | Карта `POWER` для чемпиона без своей силы. **Движку она нужна**, даже если у всех чемпионов есть свои. |
| `classes` | `[{id, champion?, neutral?, playable?}]`: класс с `champion` можно выбрать; карты класса с `neutral` идут в любую колоду. |
| `races` | Расы существ (`"DRONE"`, `"DAEMON"`). |
| `rarities` | `[{id, tier}]`, `tier` — одно из `common`, `rare`, `epic`, `legendary` (шансы Арены, рамки); `no_rarity_tier` — для карт без редкости. |
| `sets` | Все `set`, которые может назвать карта. |
| `mechanics` | Ваше имя → `{"engine": <id движка>}` (ниже). |
| `modes.constructed` | `sets` (карты этих наборов идут в колоды), `class_cards` (`"own_and_neutral"`), `starter_rarities`, `starter_core` (для стартовых колод) |
| `modes.arena` | Драфт Арены: `sets`, `champions_offered`, `classes`, `picks`, `offer`, `tier_weights`, `special_picks`, `special_tier_weights`, `class_weight`, `neutral_weight`, `copies`, `wins`, `losses` |
| `ranked` | Лестница: `start`, `ranks` (звёзды за ранг, «полы», бонус за серию, эмблемы), `streak`, `legend`, `season` |

Все поля со значениями Classic и точный алгоритм драфта: [справочник rules.json](../ref/rules.html).

> Neonfall даёт второму игроку пять стартовых карт (`"hand": [3, 5]`): при `[3, 4]` первый игрок выигрывал 56–60 % партий ботов, при `[3, 5]` — 47–53 %. Прогоны баланса — в `packs/neon/DESIGN.md` §9.

## Механики: слова движка и ваши

Движок работает с нейтральными id; пак даёт имя каждому, который использует. Игроки видят только ваши имена (из `mechanics` в `locales/<lang>.json`). Для примера — имена Neonfall:

| Id движка | Что делает | Neonfall |
|---|---|---|
| `GUARD` | Враги обязаны атаковать его первым | Firewall |
| `HASTE` | Может атаковать сразу | Overclock |
| `BARRIER` | Не даёт пройти первому урону, потом исчезает | Hardlight |
| `DOUBLE_ATTACK` | Две атаки за ход | Dual-Core |
| `STEALTH` | Его нельзя атаковать и выбрать целью, пока он не атакует | Cloak |
| `SPELLPROOF` | Его нельзя выбрать целью заклинаний и сил | Encrypted |
| `SPELL_POWER` | +N к урону заклинаний (поле карты `spell_power`) | Bandwidth |
| `MANA_LOCK` | Блокирует N маны на следующий ход (поле карты `mana_lock`) | Heat |
| `TRAP` | Скрытое заклинание, срабатывающее на событие | Protocol |
| `ON_PLAY` | Эффект при розыгрыше из руки | Boot |
| `ON_DEATH` | Эффект при гибели | Flatline |
| `COMBO` | Бонус, если в этот ход перед ней уже сыграли карту | Chain |
| `CHOICE` | Выбор одного из двух эффектов | Fork |
| `WOUNDED` | Бонус, пока ранен | Redline |
| `FREEZE`, `SILENCE` | Метки: карта замораживает / накладывает немоту (делает это её скрипт) | Jam, Wipe |

`IMMUNE`, `CANT_ATTACK`, `AURA`, `TRIGGER`, `ADJACENT`, теги состояния (`FROZEN`, `EXHAUSTED`, `ARMOR`, …) и остальное: [весь словарь](../ref/format.html#4-mechanics-the-engine-vocabulary-and-pack-names). В `keywords` карты — ваши имена; ключевые слова-теги (Guard, Haste, …) работают сами, а слова-хуки (On play, On death, …) только подписывают карту, у скрипта которой есть такой хук.

## cards.json

Массив карт; чемпионы, силы и токены — тоже карты.

| Поле | Смысл |
|---|---|
| `id` | `[A-Za-z0-9_]{1,64}`, уникальный; по нему называются арты и тексты. |
| `type` | `MINION`, `SPELL`, `WEAPON`, `CHAMPION`, `POWER`. |
| `class`, `rarity`, `set` | Id из `rules.json` (у токенов нет редкости). |
| `collectible` | Можно класть в колоды (если её набор — набор режима). По умолчанию false. |
| `cost`, `attack`, `health`, `durability` | 0–999. `health` чемпиона — его начальное здоровье. |
| `race` | Раса существа. |
| `keywords` | Имена механик (ваши); `refs` — механики, упомянутые в тексте (для подсказок). |
| `spell_power`, `mana_lock` | Величины `SPELL_POWER` и `MANA_LOCK`. |
| `unique` | Легендарная рамка. |
| `power` | Карта `POWER` у `CHAMPION`. |
| `code_id` | Число для кодов колод. |
| `script` | `scripts/<file>.lua#<key>`: её хуки. Нет скрипта — нет хуков (простое существо). |
| `fx` | Визуальные эффекты по имени: `{"element": "fire", "cast": "bolt", "hit": "hurt"}` ([эффекты](../ref/fx.html)). |
| `sounds`, `voice` | Свои имена звуков; чьи реплики она произносит. |

## Тексты: `locales/<lang>.json`

| Ключ | |
|---|---|
| `cards` | `{id: {name, text}}`. У каждой карты должно быть имя на основном языке. |
| `mechanics` | `{NAME: {name, tip}}`: ключевое слово и его подсказка. |
| `classes`, `races`, `rarities`, `sets` | `{id: текст}` |
| `ranks` | `{"25": …, "1": …, "0": "Легенда"}` |
| `decks` | Названия колод. |
| `missions`, `hints` | Вступления и реплики миссий, подсказки обучения. |
| `voice` | `{id карты: {greetings, attack, play, death, …}}`: слова эмоций. |
| `ui` | Ваши слова интерфейса (Neonfall: `armor` → «Plating», `fatigue` → «Data Rot»). |

Разметка текста карты: `<b>…</b>` и `<i>…</i>`; `$N` — число, которое растёт от силы заклинаний; `#N` — число, которое меняют модификаторы лечения; `[x]` в начале — переносы строк расставлены вручную. Нет текста — берётся основной язык, потом id.

## Картинки, звуки, музыка, оформление

- **Арты:** `art/<set>/<card id>.jpg` (или `.png`, `.webp`), не больше 2 МиБ на картинку. У Neonfall два набора — `default` (живопись) и `simple` (плоский 2D); если картинки нет, берётся набор по умолчанию, потом нарисованная.
- **Звуки:** по имени события — `play_card`, `attack`, `damage`, `death`, `hero_power`, `turn_start`, `heal`, `armor`, `equip`, `secret`, `freeze`, `shield`, `spell`, `trigger`, `hit_big`, `draw`, `victory`, `defeat`, `click`. Карта может назвать свои (`"sounds": {"play": "…"}`).
- **Музыка:** `music/<set>/menu.opus`, `battle_1.opus`, `battle_2.opus`, … (в матче — перемешанный плейлист).
- **Звуковые файлы:** лучше всего `.opus` (Ogg Opus, 48 кГц); `.ogg` (Ogg Vorbis), `.wav` и `.mp3` тоже подходят.
- **Оформление:** `ui/theme.json` перекрашивает весь интерфейс, пока ваша игра активна: цвета, стиль кнопок (`wood`, `flat`, `neon`), панели, шрифты (`ui/fonts/*.ttf` с лицензией), частицы в меню (`embers`, `rain`, `none`). Тёмное стекло и пурпурное свечение Neonfall — это его `ui/theme.json`; все ключи: [UI theme](../ref/format.html#11-ui-theme-uithemejson).

## Колоды и миссии

Колода: `{"name", "champion", "cards": [ids], "code"?, "arena"?}`. `pack.py check` проверяет каждую по вашим правилам: размер, класс, копии по редкости, наборы, коллекционность.

Миссия (`missions/<n>.json`) — сценарная партия против босса. См. следующий раздел.

## Обучение

Пункт «Обучение» появляется в меню игры, если у активного пака есть `tutorial.json`: миссии по порядку, страницы перед каждой, когда показывать каждую подсказку ([формат](../ref/format.html#12-tutorial-tutorialjson-and-scene-effects)). Сами миссии — файлы `missions/<n>.json`.

**Готовый пример — обучение Neonfall** (`packs/neon/tutorial.json`, `packs/neon/missions/`). Шесть миссий от затопленных улиц до корпоративных башен, в каждой — босс из мира игры со своими репликами: вышибала Кирпич (карта, бой, чемпионы), ростовщик Шарки (мана, заклинания с целью, Глушение), Стеклянная Мира (Запуск, Отключение, сначала существа), доктор Варга (Файрвол, Разгон и Перегрев, Маскировка), АРХОНТ (Силы чемпионов, Цепочка, Стирание и Глюк) и Директор Вейл с настоящей колодой «Враждебное слияние» (Протоколы, Твёрдый свет, Шифрование). Боссы — карты `CHAMPION` самого пака (`boss_*`, набор `token`); первые две миссии используют `scripts/tutorial.lua#ench:tutorial_guard` пака; над списком и на первом и последнем столе идёт дождь; тексты — во всех восьми `locales/<lang>.json` (`tutorial`, `missions`, `hints`).

В миссии:

| Поле | Смысл |
|---|---|
| `id` | Номер миссии, с 1. |
| `champion`, `boss`, `boss_power` | Чемпион игрока, босс (карта `CHAMPION`) и его сила. |
| `powers_locked`, `boss_guarded` | Силами обоих пользоваться нельзя; босса нельзя атаковать, пока у него есть существа. |
| `end_turn_block` | `{while_can_play, while_can_attack}`: игрок не может закончить ход, пока можно разыграть карту / атаковать существом. |
| `player` | `{mana, hand, deck}`: начальная мана, рука, колода — **верхняя карта первой**. |
| `boss_deck` | Верхняя карта первой. |
| `mulligan` | false: без замены карт. |
| `reward` | Карта, которую показывают после победы. |
| `hints` | Ключи подсказок по порядку; тексты — в `hints` файла `locales/<lang>.json`. |
| `script` | `scripts/<file>.lua#<name>`: хуки, которые чемпион игрока получает в начале, или null. В первых двух миссиях Classic — `ench:tutorial_guard`: здоровье чемпиона не падает ниже 1. |

Слова миссии — вступление, реплики босса (`start`, `hurt`, `defeat`…), фраза о награде — в `missions` файла `locales/<lang>.json`. Миссии входят в `rules_hash`, их тексты — нет.

## Сборка: tools/pack.py

```sh
python3 tools/pack.py build <папка> -o <файл>.cardpack [--art-set mine=путь/к/картинкам]
python3 tools/pack.py check <файл>.cardpack     # все ошибки и предупреждения; код выхода 1 при ошибке
python3 tools/pack.py info  <файл>.cardpack     # размеры по папкам, число карт, языки, наборы, хэши
python3 tools/pack.py hash  <файл>.cardpack     # rules_hash и content_hash
```

`build` читает папку, выполняет её `recipe.json`, если он есть, пишет в манифест `fx` и `rules_hash`, проводит все проверки и записывает архив, только если ошибок нет. Архив детерминирован: одни и те же файлы дают побайтно одинаковый `.cardpack`.

**Рецепты.** Если пак собирается из данных, лежащих в другом месте, `recipe.json` перечисляет шаги сборки: `{"root": "<папка>", "steps": [{"do": …}, …]}`. Ни `recipe.json`, ни `*.patch.json` в пак не попадают.

| Шаг | Что делает |
|---|---|
| `copy` | Копирует файлы из папки (`from`, `to`, маски `files`, `except`). Так Classic берёт свои арты и звуки. |
| `source` | Исходник в собственной форме (Neonfall): убирает служебные поля карт (`drop_card_fields`), убирает файлы (`drop_files`), переносит файлы (`move`, например картинки в `ui/`), переносит `pack.name`/`pack.description` каждого языка в манифест, а `terms` — в `ui`. |
| `hsjson`, `keywords`, `voice`, `translate`, `rank_names` | Шаги Classic: карты и тексты из данных HearthstoneJSON, имена механик, реплики, переводы, имена рангов. |

`--art-set id=папка` добавляет ваш собственный набор картинок; он помечается `local` и никогда не передаётся другим; `--sound-set id=папка` делает то же для звуков (свои звуки карт `<id карты>_play|attack|death|hit` и звуки стола по именам), `--music-set id=папка` — для музыки, а `--voice папка` добавляет ваши записи реплик (`<язык>/<id карты>_<вид>.opus`, с пометкой `voice/LOCAL.md`).

## Загрузка в игру

- **На своём устройстве:** *Игры → Добавить файл игры* (системный диалог выбора файла; в браузере — его выбор файла). Игра проверяет пак (пути, размеры, формат, `rules_hash`), хранит его как `packs/<content_hash>.cardpack` в папке пользователя и показывает в списке. *Играть в эту игру* делает его активным: колоды, арты, звуки, музыка и оформление переключаются сразу. *Удалить* убирает добавленный пак.
- **По сети с другом (коды):** если у друга есть пак с тем же `rules_hash`, игра переключится на него; если нет и пак `redistributable`, другу предложат скачать его у вас.
- **На игровом сервере:** игрок загружает пак в окне *Игры* сервера (*Загрузить мою игру*: до 10 паков по 1 ГиБ); админ загружает в админке или кладёт `.cardpack` в `--packs-dir` сервера. Сервер проверяет каждый новый пак: движок загружает правила, компилирует все скрипты и играет пробную партию с вашими первыми двумя готовыми колодами, перебирая все допустимые ходы; ошибка скрипта, сбой движка, зависшая партия или больше 20 секунд — и пак отклоняется.

## Версии и хэши

| | Что определяет | Меняется, когда |
|---|---|---|
| `version` | Ничего, это для людей | Вы её меняете |
| `rules_hash` | **Игру, как она играется.** По нему подбирают соперников, его используют серверы и записи партий: два пака с одинаковым `rules_hash` — одна и та же игра. | Меняются `rules.json`, `cards.json` (кроме `fx`, `sounds`, `voice`), `missions/*.json` или `scripts/**/*.lua` |
| `content_hash` | **Файл.** Скачивания, кэши, копия в папке пользователя. | Меняется любой файл |

Поэтому можно исправить опечатку, перерисовать арт, добавить язык или набор звуков — и всё так же играть с друзьями, у которых старый файл: имена, тексты, картинки и манифест в `rules_hash` не входят. Поменяли число или скрипт — это другая игра. Оба хэша — SHA-256 по файлам (не по байтам архива), JSON в каноническом виде; точный рецепт: [Hashes](../ref/format.html#3-hashes).

## Ограничения

| Что | Предел |
|---|---|
| Файл `.cardpack` | 1 ГиБ |
| Все файлы в распакованном виде | 2 ГиБ |
| Число файлов | 50 000 |
| Один файл / одна картинка | 16 МиБ / 2 МиБ |
| Правила (`rules.json`, `cards.json`, `missions/`, `scripts/`) | 8 МиБ в распакованном виде |
| Тексты (`locales/`, `layout/`) | 32 МиБ в распакованном виде |
| Одна запись архива, распакованная / сжатая | ≤ 200 (никаких zip-бомб) |
| Один вызов скрипта | 200 000 шагов, глубина вызовов 200, 10 000 записей в таблице, 64 КиБ на строку, 16 МиБ памяти ([ограничения Lua](lua.html#ограничения)) |

## Где читать дальше

Страницы справочника описывают каждый файл ровно так, как его читают движок и инструменты (по-английски): [формат пака](../ref/format.html), [rules.json](../ref/rules.html), [cards.json](../ref/cards.html), [визуальные эффекты](../ref/fx.html). JSON-схемы для машин лежат в `docs/packs/schema/` в исходниках.
