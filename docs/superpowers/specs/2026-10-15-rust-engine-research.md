# Исследование: единый движок правил на Rust (сервер, десктоп/Android, web)

Дата: 2026-10-15
Статус: исследование и предложение (код не менялся). Нужно решение владельца по фазам (раздел 6).

## 1. Коротко

**Рекомендация:**

1. **Сейчас** (серверу скоро нужно считать логику): поднять Rust-сервер (`classichs-server`, его уже ждёт CI) и считать логику **текущим GDScript-движком в headless Godot** («судья»). Сервер говорит с судьёй по локальному TCP, сообщения — JSON-строки. Логику не переписываем, совпадение 100 %, срок — дни.
2. **Параллельно** зафиксировать **общий интерфейс правил** (JSON: `new_game / apply / legal_actions / view / hash / snapshot / bot_action`). На него перевести UI: экран читает `view(player)` и события, а не объекты `Entity`. Это нужно и серверу: скрытая информация, чужая рука.
3. **Потом** портировать движок и 396 карт с хуками на Rust (крейт `hs-engine`). Паритет проверяем повтором записанных партий: состояние хэшируется после каждого действия, побайтовое совпадение `state_hash()` и событий. Когда паритет зелёный, сервер меняет судью на нативный крейт, а для клиентов движок выходит через две тонкие обёртки:
   - **gdext (GDExtension)** — для Windows/Linux/macOS/Android;
   - **wasm32-unknown-unknown + JavaScriptBridge** — для web. Web-сборка Godot остаётся как есть: без dlink, без nightly Rust, без привязки к версии emscripten, без COOP/COEP.

   Обе обёртки и сервер вызывают одну функцию `hs_engine::api::call(cmd) -> reply`, так что интерфейс один на всех.
4. gdext в web (dlink-шаблоны) **не берём**, пока он «experimental»: нужны nightly и `-Zbuild-std`, паника убивает игру, версия emscripten должна совпадать с шаблонами. Переключиться можно потом за день: API тот же.

## 2. Что есть сейчас (по коду)

| Часть | Файлы | Размер | Важно для порта |
|---|---|---|---|
| Состояние, очередь событий, смерть, ауры, примитивы | `engine/game_state.gd` | 745 строк | `emit` ставит в очередь хуки `on` по `play_order`; `emit_now` — для замещающих эффектов; `resolve()` крутит очередь и фазу смерти (до 5000 шагов) |
| Ходы, действия, законность | `engine/game.gd` | 485 | `apply(action) -> {ok, error, events}`; действие законно, только если оно есть в `legal_actions()` (точное равенство словарей); `_normalize` переводит float из JSON в int |
| Сущность, игрок | `engine/entity.gd`, `engine/player.gd` | 146 + 65 | теги, enchantments, aura, eot; `copy()` для клона |
| Данные карт | `data/cards.json`, `engine/card_db.gd` | 534 карты (282 существа, 190 заклинаний, 26 сил героя, 19 оружий, 17 героев) | `data_hash()` = SHA-256 файла, сверяется онлайн |
| Хуки карт | `cards/*.gd`, `cards/registry.gd` | 2084 строки, **396 карт с хуками** (остальные 138 — только данные) | словарь `{battlecry, spell, deathrattle, on{ev}, now{ev}, aura, aura_final, cost_aura, cost_mod, can_play, choose_one, combo, combo_target, hero_power, on_choose, target, ...}` из лямбд `func(g, me, t/ev)` |
| Сценарии | `engine/scenario.gd` | 255 | сборка состояния из JSON (тесты, debug table) |
| Бот | `game/bot.gd` | 70 | на каждое законное действие делает `g.clone()` + `apply` и оценивает |
| Сеть | `net/net_session.gd` | 223 | lockstep: хозяин выбирает seed, обе стороны применяют те же действия и сверяют `state_hash()` после каждого (кроме mulligan/concede) |
| Тесты карт | `tests/test_cards_*.gd` | 363 теста | императивные, ставят карты прямо в зоны (`H.board`, `H.hand`), потом `H.play` |
| Случайные партии | `tests/sim.gd` | 46 | уже пишет `actions` и `hashes` после каждого действия |

Как устроен детерминизм:
- RNG — `RandomNumberGenerator` Godot (PCG32: `pcg32_random_r`, `pcg32_boundedrand_r`), его используют `random_choice`, `shuffle` и три карты (`randi_range`) ([random_pcg.cpp](https://github.com/godotengine/godot/blob/4.7/core/math/random_pcg.cpp), [random_pcg.h](https://github.com/godotengine/godot/blob/4.7/core/math/random_pcg.h)). Алгоритм переносится в Rust строк за 30.
- `state_hash()` = SHA-256 от `JSON.stringify(to_dict())`. По умолчанию `JSON.stringify` **сортирует ключи** (`p_sort_keys = true`), и формат компактный ([json.h](https://github.com/godotengine/godot/blob/4.7/core/io/json.h)). Значит, хэш воспроизводим в Rust: `serde_json` + `BTreeMap`, только целые.

**Опасные места для порта** (их надо закрыть до сравнения хэшей):
1. `game.gd:171` — `own.seed = hash([rng.seed, "mulligan", p])`. Это внутренний `Variant::recursive_hash` Godot (murmur3 по массиву). Повторить можно, но хрупко. Лучше заменить явной формулой, например `seed * 2 + 1 + p` через тот же PCG, и поднять `PROTOCOL` до 2.
2. `to_dict()` пишет `"rng": str(rng.state)`. В GDScript int — это **i64**, поэтому состояние PCG выше 2^63 печатается отрицательным. Rust должен печатать `state as i64`.
3. Хуки **меняют событие на месте**: `ev.countered = true`, `ev.target = n.id`, `ev.amount = 0` (Counterspell, Spellbender, Ice Block). В GDScript словарь передаётся по ссылке. В Rust событие хранится в арене (`Vec<Event>`), а очередь держит индекс.
4. `_by_order` использует `sort_custom` (нестабильная сортировка), но `play_order` уникален среди сущностей в игре, поэтому стабильный `sort_by_key` в Rust даст тот же порядок.
5. Набор ключей в `enchantments`/`tags` зависит от того, как они созданы: `buff` пишет `{atk, hp, eot, src?}`, а `set_stats` — `{set_atk?, set_hp?, src?}`. Для побайтового хэша Rust-структуры должны сериализовать ровно те же ключи (`Option` + `skip_serializing_if`). Харнесс паритета ловит это сразу.
6. Godot `JSON.parse_string` возвращает **все числа как float**. Поэтому мост web→GDScript должен прогонять ответы через нормализатор целых. Такой уже есть: `Scenario._ints`, `Game._normalize`.

Скорость нынешнего GDScript-движка (замер: Godot 4.7.2 headless, Apple Silicon, 40 случайных партий через `Sim.play_random`, временный скрипт вне репозитория):

| Операция | Время |
|---|---|
| `apply` + `legal_actions` + `state_hash` на одно действие | ≈ 1.0 мс |
| `clone()` | ≈ 0.36 мс |
| `state_hash()` | ≈ 0.39 мс |
| `legal_actions()` | ≈ 0.13 мс |
| Пиковая память процесса (бинарник редактора) | ≈ 140 МБ |

Живая партия — это одно действие раз в несколько секунд. Значит, одно ядро с GDScript-судьёй тянет тысячи одновременных матчей. Производительность не причина переписывать на Rust. Причины — единый источник правды и нормальный серверный стек.

## 3. Состояние технологий (на октябрь 2026)

### 3.1 godot-rust (gdext)

- Последняя версия — `godot` **0.5.5** от 9 августа 2026 ([docs.rs](https://docs.rs/crate/godot/latest), [Changelog](https://github.com/godot-rust/gdext/blob/master/Changelog.md)).
- **Godot 4.7** поддерживается с 0.5.4 от 23 июня 2026: «Godot 4.7: add `api-4-7` level» ([Changelog v0.5.4](https://github.com/godot-rust/gdext/blob/master/Changelog.md#v054)). Godot 4.6 — с 0.5.0 от 27 марта 2026, там же Rust Edition 2024 ([Changelog v0.5.0](https://github.com/godot-rust/gdext/blob/master/Changelog.md#v050)).
- С 0.5.3 bindgen и LLVM не нужны («JSON-based workflow — no more bindgen/LLVM», [Changelog v0.5.3](https://github.com/godot-rust/gdext/blob/master/Changelog.md#v053)). Это упрощает CI, особенно Android и web.
- Совместимость только вперёд: расширение, собранное под API 4.x, работает на рантайме ≥ 4.x. Минимум для 0.4+ — Godot 4.2 ([Compatibility](https://godot-rust.github.io/book/toolchain/compatibility.html)).

### 3.2 GDExtension в web (Godot 4.3+)

- Нужна галка **Extensions Support**: тогда экспорт берёт шаблон `web_dlink[_nothreads]_{debug,release}.zip` ([export_plugin.h](https://github.com/godotengine/godot/blob/master/platform/web/export/export_plugin.h), функция `_get_template_name`). Официальные шаблоны включают и `dlink_enabled=yes threads=no` ([godot-build-scripts/build-web/build.sh](https://github.com/godotengine/godot-build-scripts/blob/main/build-web/build.sh)). Сейчас в `export_presets.cfg` стоит `extensions_support=false`, `thread_support=false`.
- Однопоточный экспорт есть с Godot 4.3, это «the preferred and now default way» ([Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)).
- **Противоречие в источниках про COOP/COEP.** В документации Godot сказано про Extensions Support: «Like thread support, enabling this feature requires the use of cross-origin isolation headers» ([исходник страницы](https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_for_web.rst)). А код загрузчика требует cross-origin isolation и SharedArrayBuffer только при `threads` ([features.js, `getMissingFeatures`](https://github.com/godotengine/godot/blob/master/platform/web/js/engine/features.js)). Книга godot-rust тоже пишет, что однопоточный экспорт заголовков не требует ([Export to Web](https://godot-rust.github.io/book/toolchain/export-web.html)). На GitHub Pages заголовки поставить нельзя, есть только PWA-обход через service worker. Для нас это риск, который нужно проверить руками.
- Что требует gdext в web ([Export to Web](https://godot-rust.github.io/book/toolchain/export-web.html)):
  - поддержка «experimental»;
  - **nightly** Rust + `-Zbuild-std`, цель `wasm32-unknown-emscripten`;
  - фичи `experimental-wasm` и `experimental-wasm-nothreads` (для nothreads — godot-rust 0.3+);
  - `-Z emscripten-wasm-eh=false`, потому что с Rust 1.93 Wasm EH ломает Godot;
  - паника = abort всей игры: «godot-rust cannot catch panics in Wasm yet»;
  - отладка — только через Chrome C/C++ DevTools extension;
  - Firefox поддерживается хуже, чем Chromium.
- **Версия emscripten.** Книга рекомендует emsdk **3.1.74** для Godot 4.3+ ([Export to Web](https://godot-rust.github.io/book/toolchain/export-web.html)). Но официальные шаблоны Godot 4.6/4.7 собраны emsdk **4.0.20** ([build-containers, ветка 4.7, Dockerfile.web](https://github.com/godotengine/build-containers/blob/4.7/Dockerfile.web)), а CI самого Godot 4.7 использует 4.0.11 ([web_builds.yml](https://github.com/godotengine/godot/blob/4.7/.github/workflows/web_builds.yml)). Master уже требует Emscripten 6.0.1+ ([detect.py](https://github.com/godotengine/godot/blob/master/platform/web/detect.py)). Side module грузится в рантайм emscripten основного модуля, поэтому несовпадение версий — реальный риск. Это наш вывод, проверенных отчётов о такой связке мы не нашли.

### 3.3 Android

- gdext собирается отдельно под каждую цель: `aarch64-linux-android` и другие. Линкер задаётся через `CARGO_TARGET_<TRIPLE>_LINKER` из NDK, а версия NDK должна совпадать с той, что в `config.gradle` вашей версии Godot ([Export to Android](https://godot-rust.github.io/book/toolchain/export-android.html)).
- Godot 4.7: `ndkVersion '29.0.14206865'`, `minSdk 24`, `targetSdk 36` ([config.gradle 4.7](https://github.com/godotengine/godot/blob/4.7/platform/android/java/app/config.gradle)).
- Google Play: с 1 февраля 2027 обновления приложений с targetSdk ≥ 35 должны поддерживать страницы 16 КБ. NDK r28+ выравнивает так по умолчанию, для более старых нужны `-Wl,-z,max-page-size=16384` ([Android: 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)). С NDK 29 это бесплатно, но в CI стоит проверять `.so`.

### 3.4 JavaScriptBridge

`JavaScriptBridge.get_interface("obj")` синхронно вызывает функции JS. Строки, числа и bool конвертируются автоматически, float может потерять точность. Свой JS подключается через **Head Include** или свой HTML shell ([The JavaScriptBridge singleton](https://docs.godotengine.org/en/stable/tutorials/platform/web/javascript_bridge.html), [исходник](https://github.com/godotengine/godot-docs/blob/master/tutorials/platform/web/javascript_bridge.rst)). Поэтому `.wasm`, собранный стабильным Rust под `wasm32-unknown-unknown`, можно загрузить на страницу и звать из GDScript строкой JSON на входе и строкой на выходе. Godot-шаблон при этом не меняется. wasm-bindgen жив: репозиторий переехал из архивированной организации rustwasm в новую ([Rust blog, 2025-07-21](https://blog.rust-lang.org/inside-rust/2025/07/21/sunsetting-the-rustwasm-github-org)). Но нам он не нужен: на вход и выход одна строка, хватит `extern "C"` и 30 строк JS-клея.

### 3.5 Headless Godot как сервер

С Godot 4.0 любой бинарник запускается с `--headless` (+ Dummy audio). Отдельная серверная сборка не нужна. Есть режим экспорта «Export as dedicated server», который вырезает текстуры из PCK ([Exporting for dedicated servers](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html)). Чтение stdin через `OS.read_string_from_stdin` из канала блокируется до заполнения буфера ([OS.xml 4.7](https://github.com/godotengine/godot/blob/4.7/doc/classes/OS.xml)). Поэтому для обмена с судьёй берём `StreamPeerTCP` на localhost, а не stdin.

## 4. Варианты

| | A. gdext везде (вкл. web dlink) | B. gdext (натив) + wasm/JSBridge (web) | C. C ABI (`cdylib` + `.h`) | D. Rust только на сервере, тонкие клиенты | E. GDScript + headless Godot-судья |
|---|---|---|---|---|---|
| Порт 534 карт | весь (396 с хуками) | весь | весь | весь | **0** |
| Единый источник правды | да | да (один крейт, 2 обёртки по ~100 строк) | да | только если офлайн-режимы (бот, обучение, Арена без сети) тоже уйдут на сервер или их потеряем; иначе два движка | да (GDScript) |
| Web | experimental: nightly, `-Zbuild-std`, emsdk = версии шаблона, паника = abort, dlink-шаблон тяжелее, вопрос COOP/COEP на gh-pages | **стабильный Rust**, шаблон и gh-pages без изменений | Godot сам по себе не грузит C-библиотеку: нужен GDExtension (= A/B) | web — тонкий клиент без офлайна | как сейчас |
| Android | да (cargo-ndk, NDK 29) | да | через GDExtension | — | как сейчас |
| Детерминизм | один код | один код (тот же крейт; wasm без float — тот же результат) | один код | один код | один код |
| Отладка | натив: lldb/CodeLLDB в процессе Godot; web: почти нет | натив так же; web: исключение JS + `console.error`, без падения игры | натив | лучшая (обычный Rust-сервер) | как сейчас, плюс логи судьи |
| CI | 5 целей cdylib + nightly + emsdk | 4 цели cdylib (stable) + 1 `wasm32-unknown-unknown` (stable) | как A | только сервер | только Godot-экспорт сервера |
| Скорость | лучшая | лучшая; web: +JSON на вызов (доли мс) | лучшая | лучшая | ~1 мс/действие, достаточно |
| Риск | высокий (web) | средний (паритет порта) | — | высокий (продукт меняется) | низкий |

Вывод: **C** — не отдельный вариант, а внутренняя деталь: `api::call(&str) -> String` и есть C-подобный интерфейс, который оборачивают B и сервер. **D** ломает офлайн-игру и сайт на gh-pages. **E** — лучший ход прямо сейчас. **B** — целевая архитектура. **A** — возможный апгрейд web, когда gdext-web перестанет быть экспериментальным.

## 5. Общий интерфейс правил (одинаков для всех хостов)

Одна точка входа в Rust: `hs_engine::api::Session::call(&mut self, req: &str) -> String`. Так же устроен JSON-протокол судьи в фазе 0. Каждый запрос — `{"cmd": ..., ...}`, ответ — JSON.

| cmd | Аргументы | Ответ |
|---|---|---|
| `new_game` | `p0 {hero, deck}`, `p1`, `seed`, `first?` | `{game: id, hash}` |
| `from_scenario` | сценарий (формат `tests/scenarios/*.json`) | `{game: id, hash}` |
| `apply` | `game`, `action` (как сейчас: `{type, player, ...}`) | `{ok, error, events, hash}` |
| `legal_actions` | `game` | `[action...]` |
| `view` | `game`, `player` (`-1` — всё, для отладки) | состояние, видимое игроку: своя рука, у соперника только число карт, колоды — числом, тайны соперника — без id карты |
| `redact` | `events`, `player` | события без скрытого (чужой `draw` без `card`) |
| `snapshot` / `restore` | `game` / `to_dict` | полный `to_dict()` (уже есть) / новая игра |
| `clone` | `game` | `{game: id}` |
| `bot_action` | `game`, `player` | действие (бот переезжает в движок) |
| `hash` | `game` | строка |
| `data_hash` | — | SHA-256 `cards.json` |
| `drop` | `game` | — |

В GDScript есть один фасад `Rules` с бэкендами:
- `GdRules` — нынешний `Game`; остаётся оракулом паритета до конца порта;
- `RemoteRules` — сервер;
- `NativeRules` — класс gdext;
- `JsRules` — `JavaScriptBridge`.

Бэкенд выбирается при старте: `ClassDB.class_exists("HsEngine")` / `OS.has_feature("web")` / онлайн-матч.

UI читает только `view` и события. Сейчас UI и `game/` обращаются к объектам движка напрямую: в 15 файлах примерно 230 мест (`.players[`, `.ent(`, `.atk()`, `.health()`, `.has("`…). Этот рефакторинг — главная работа вне карт. Но он всё равно нужен для сервера со скрытой информацией: в нынешнем lockstep оба клиента знают обе колоды и seed (см. `2026-10-11-online-design.md`, «Скрытая информация»).

## 6. Фазы

### Фаза 0 — сейчас: Rust-сервер + GDScript-судья (1–2 недели)

1. `rust/server` (`classichs-server`, axum + tokio, WebSocket): лобби, матчи, таймер хода, переподключение. Логику считает судья.
2. `tools/referee.gd` (`extends SceneTree`): headless Godot подключается `StreamPeerTCP` к серверу на `127.0.0.1` и держит `match_id -> Game`. Протокол — JSON-строки по таблице из раздела 5. Перед выходом вызывает `Cards.unload()`. Один процесс тянет все матчи (≈1 мс на действие). Сервер может держать 2+ процессов, чтобы падение одного не роняло все матчи, и перезапускает упавший: состояние восстанавливается повтором действий матча.
3. В Rust один трейт `Rules`, у которого сразу две реализации: `Referee` сейчас и `Native` в фазе 3. Значит, это не спекулятивная абстракция.
4. GDScript: добавить `Game.view(player)` и `redact(events, player)`, убрать `hash([...])` в mulligan (`PROTOCOL = 2`).
5. Записывать каждую серверную партию в корпус `{v, data_hash, seed, decks, first, actions[], hashes[], events[]}` (jsonl). Это бесплатные данные для паритета.
6. Сервер — это CI-джоба `server` из `.github/workflows/release.yml`: она уже ищет `server/Cargo.toml`. Либо положить крейт туда, либо поменять 2 строки на `rust/Cargo.toml` (см. раздел 7). Деплой: бинарник сервера + Linux-экспорт Godot в режиме dedicated server.

### Фаза 1 — общий интерфейс в клиенте (1–2 недели, можно параллельно с фазой 2)

- Фасад `Rules` + `GdRules`. Перевести `ui/*` и `game/match.gd` на `view` и события.
- Добавить онлайн-режим через сервер (`RemoteRules`). P2P-lockstep остаётся для игры с другом без сервера.

### Фаза 2 — порт на Rust (3–6 недель, оценка)

- Ядро: примерно 1.3 тыс. строк GDScript превращаются в 2–2.5 тыс. строк Rust.
- Карты: 2.1 тыс. строк превращаются в 3–4 тыс. Перевод механический, файл в файл (`cards/mage.gd` → `cards/mage.rs`), удобно делать с LLM. Каждый файл сразу проверяется харнессом паритета.
- Бот (70 строк) и `ArenaDraft` (120) переезжают туда же: драфт Арены сервер тоже должен считать сам.
- Порядок: RNG + `to_dict`/хэш (паритет на «пустых» партиях) → ядро + 138 карт без хуков → классы по одному. Сим-корпус фильтруется по колодам, в которых только уже портированные карты.

### Фаза 3 — сервер на нативном движке (дни)

Когда паритет зелёный (весь корпус + фикстуры тестов карт), меняем `Referee` на `Native`. Судью держим ещё один релиз как теневой: он считает параллельно, расхождение пишется в лог.

### Фаза 4 — клиенты на Rust (1–2 недели)

- `rust/gd`: gdext-класс `HsEngine` с одним методом `call(String) -> String` (+ удобные `apply(Dictionary)`, если JSON заметно тормозит; по замерам не будет). Плюс `classichs.gdextension` для `windows.x86_64`, `linux.x86_64`, `macos` (universal через `lipo`), `android.arm64`.
- `rust/wasm`: `cdylib` под `wasm32-unknown-unknown`, `extern "C" fn hs_call(ptr, len) -> ptr` + `alloc`/`free`. JS-клей (~30 строк) в Head Include грузит `hs_engine.wasm` до старта Godot. GDScript зовёт `JavaScriptBridge.get_interface("hsEngine").call(json)`.
- Удалить `engine/*.gd` и `cards/*.gd`. Тесты карт переписываются на Rust (`#[test]` над сценариями) или остаются в GDScript поверх фасада `Rules`.

## 7. Раскладка крейтов

```
rust/                     # workspace; .gdignore, чтобы Godot не сканировал target/
  Cargo.toml              # [workspace] members = engine, gd, wasm, server
  engine/                 # hs-engine: lib, без Godot, без I/O, без времени, без потоков
    src/rng.rs            # PCG32, побитно как у Godot
    src/state.rs          # GameState, Entity, Player (арены Vec по id)
    src/game.rs           # apply, legal_actions, ходы, mulligan
    src/events.rs         # Event (типизированный), очередь с индексами событий
    src/hash.rs           # to_dict -> канонический JSON (BTreeMap) -> SHA-256
    src/cards/mod.rs      # fn hooks(card_id) -> &'static Hooks
    src/cards/{neutral,mage,...}.rs   # зеркало cards/*.gd
    src/bot.rs, src/arena_draft.rs, src/scenario.rs
    src/api.rs            # Session::call(&str) -> String — единственный внешний интерфейс
    tests/parity.rs       # прогон корпуса и фикстур
  gd/                     # cdylib, godot = { version = "0.5", features = ["api-4-7"] }, ~100 строк
  wasm/                   # cdylib, wasm32-unknown-unknown, ~50 строк + hs_engine.js
  server/                 # bin classichs-server (axum, tokio), трейт Rules: Referee | Native
```

- **Почему не `no_std`.** serde_json и sha2 работают с `alloc`, а std есть на всех наших целях, включая `wasm32-unknown-unknown`. Нужна не `no_std`, а дисциплина. В `engine/lib.rs`: `#![forbid(unsafe_code)]`; нет `HashMap`/`HashSet` в логике, только `Vec` по id и `BTreeMap` (порядок итерации детерминирован); нет float; нет `std::time`, `rand`, глобального состояния. Зависимости: `serde`, `serde_json`, `sha2`.
- **Данные карт.** `include_bytes!("../../../data/cards.json")`: один файл на Godot и Rust, `data_hash` совпадает с `CardDb.data_hash()` автоматически.
- **Паника.** `api::call` оборачивает `catch_unwind` в нативных обёртках. В wasm (`panic = "abort"`) паника станет JS-исключением, которое `JsRules` ловит и показывает ошибку, а не роняет вкладку.
- **CI.** Добавить джобу `rust` (stable): `cargo test -p hs-engine` (паритет), затем матрица cdylib:
  - ubuntu: `x86_64-unknown-linux-gnu`, `wasm32-unknown-unknown`, `aarch64-linux-android` через `cargo-ndk` с NDK 29;
  - windows: msvc;
  - macos: `aarch64` + `x86_64` → `lipo`.

  Артефакты кладутся в `bin/` проекта до шага «Export every platform». Nightly и emsdk не нужны.

## 8. Как держать карты «data-driven» во время порта

- Цифры, тексты, ключевые слова, тип, раса, overload, spellDamage и durability уже лежат в `data/cards.json`. Их читают оба движка из одного файла. 138 карт без хуков портируются бесплатно.
- Поведение — код с той же формой реестра: `Hooks { target, battlecry, spell, deathrattle, on: &[(Ev, fn)], now, aura, aura_final, cost_aura, cost_mod, can_play, choose_one, combo, combo_target, hero_power, on_choose, durability_on_attack, immune_while_attacking }` + хелпер `secret(ev, cond, effect)`, как `Cards.secret`. Одна лямбда GDScript = одна `fn` в Rust, ревью идёт строка к строке.
- **Свой DSL эффектов (JSON) не делаем.** Его пришлось бы реализовать в обоих движках на время перехода, а 385 лямбд в среднем по 3–5 строк. Если понадобятся моды или «карты без релиза», DSL можно добавить поверх готового крейта.
- Спеки целей (`T.ANY`… или Callable) → `enum Target { Any, Minion, EnemyMinion, ..., Custom(fn), All(&[Target]) }`.

## 9. Проверка паритета

1. **Корпус партий.** В нём `Sim.play_random(seed)` (уже возвращает `actions` и `hashes`), бот против бота (`game/bot.gd`) по всем 9×9 героям, плюс записанные серверные партии фазы 0. Цель — 100 тыс. партий, это около 10 млн действий. На GDScript генерация займёт часы, делается один раз, лежит в CI-кэше или в release-ассете, не в git. Rust прогоняет: `new_game(seed, decks)` → для каждого действия `apply` → сравнить `hash` и `events` (события важны: по ним анимирует UI).
2. **Фикстуры из 363 тестов карт.** На время теста включить в `Game.apply` статический «рекордер», который пишет `{before: to_dict(), action, after_hash, events}`. Так императивные тесты, которые ставят карты прямо в зоны, становятся одношаговыми фикстурами. Rust делает `restore(before)` → `update_auras` → `apply` → сравнивает. Для этого в GDScript нужно одно небольшое изменение — сам рекордер. Плюс `restore` в Rust, он всё равно нужен API.
3. **На первом расхождении** харнесс печатает дифф `to_dict()` по JSON-путям (GDScript против Rust) и номер действия. Это и есть основной отладчик порта.
4. **Fuzz.** В CI каждую ночь гонять случайные партии: GDScript-судья против Rust на одном seed (оба на сервере). Это держит паритет, пока жив `GdRules`.
5. **Порядок хэша** не меняем (v1 = нынешний `to_dict`), чтобы старые записи оставались валидными. Если формат придётся менять, то сначала в GDScript, с новым номером протокола.

## 10. Риски и открытые вопросы

| Риск | Что делаем |
|---|---|
| Хэш не совпадает побайтово из-за мелочей (набор ключей, i64 у `rng`, порядок) | Начать порт с `hash.rs` + `rng.rs` и паритета на «пустых» партиях |
| Хуки меняют события и состояние во время обхода (`in_play()` — копия списка в GDScript) | В Rust обходить снимок `Vec<Id>`, как сейчас; события держать в арене |
| `float` из JSON в GDScript (`JSON.parse_string`) | Нормализатор целых в `JsRules`/`RemoteRules`; gdext отдаёт Variant с настоящими int |
| COOP/COEP для dlink-web (вариант A) | Не нужен в рекомендованном B. Если когда-нибудь A — проверить на gh-pages с PWA-обходом |
| emsdk ≠ шаблону (вариант A) | Не касается B |
| Падение судьи в фазе 0 | Пул процессов + восстановление матча повтором действий |
| UI-рефакторинг на `view` больше, чем кажется | Делать в фазе 1 по экрану, тесты UI уже есть (`test_table_ui`, `test_match`…) |

Решения владельца:
1. Сервер: в `server/` (как ждёт CI) или workspace `rust/` с правкой двух строк CI? Предлагаю `rust/`.
2. Онлайн через сервер становится основным, а P2P остаётся для игр с друзьями? Предлагаю да.
3. Порт на Rust начинаем сразу после фазы 0 или ждём, пока сервер поработает на судье? Предлагаю сразу, параллельно с фазой 1.

## 11. Источники

- gdext Changelog (0.5.0 — 4.6; 0.5.3 — без bindgen; 0.5.4 — api-4-7; 0.5.5 — 9 авг 2026): https://github.com/godot-rust/gdext/blob/master/Changelog.md
- godot на docs.rs (0.5.5): https://docs.rs/crate/godot/latest
- godot-rust book, Compatibility: https://godot-rust.github.io/book/toolchain/compatibility.html
- godot-rust book, Export to Web: https://godot-rust.github.io/book/toolchain/export-web.html (исходник: https://github.com/godot-rust/book/blob/master/src/toolchain/export-web.md)
- godot-rust book, Export to Android: https://godot-rust.github.io/book/toolchain/export-android.html
- Godot, Exporting for the Web: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html (исходник: https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_for_web.rst)
- Godot, имена web-шаблонов (dlink/nothreads): https://github.com/godotengine/godot/blob/master/platform/web/export/export_plugin.h
- Godot, проверка нужных функций браузера: https://github.com/godotengine/godot/blob/master/platform/web/js/engine/features.js
- Godot, сборка официальных web-шаблонов: https://github.com/godotengine/godot-build-scripts/blob/main/build-web/build.sh
- Godot, emsdk для шаблонов 4.7: https://github.com/godotengine/build-containers/blob/4.7/Dockerfile.web
- Godot 4.7 CI web (EM_VERSION): https://github.com/godotengine/godot/blob/4.7/.github/workflows/web_builds.yml
- Godot master, требование Emscripten: https://github.com/godotengine/godot/blob/master/platform/web/detect.py
- Godot 4.7 Android NDK/SDK: https://github.com/godotengine/godot/blob/4.7/platform/android/java/app/config.gradle
- Android 16 KB page sizes: https://developer.android.com/guide/practices/page-sizes
- Godot, JavaScriptBridge: https://docs.godotengine.org/en/stable/tutorials/platform/web/javascript_bridge.html
- Godot, Exporting for dedicated servers: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html
- Godot 4.7 OS (stdin): https://github.com/godotengine/godot/blob/4.7/doc/classes/OS.xml
- Godot 4.7 PCG: https://github.com/godotengine/godot/blob/4.7/core/math/random_pcg.cpp, https://github.com/godotengine/godot/blob/4.7/core/math/random_pcg.h
- Godot 4.7 JSON.stringify (sort_keys по умолчанию): https://github.com/godotengine/godot/blob/4.7/core/io/json.h
- Sunsetting rustwasm org (wasm-bindgen переехал): https://blog.rust-lang.org/inside-rust/2025/07/21/sunsetting-the-rustwasm-github-org
