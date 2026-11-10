"""The content of the architecture map (tools/arch_page.py builds dev/<lang>/architecture.html).

Texts are (English, Russian) pairs; a plain string is the same in both. Inline Markdown works in
texts: `code`, **bold**, [links](url). A source reference is ("path", "a substring of exactly one
line of that file") or just "path"; tools/arch_page.py turns it into a GitHub link to the line.

COMPS: the blocks of the top diagram (x, y in its pixels), each with its parts (x, y on a small
grid; ext = a block of another component, drawn dashed, opens it), arrows between parts, data
and protocol rows and the flows it lists. FLOWS: sequence diagrams — lanes (a component id, or
{id, name, comp}), then steps (from lane, to lane, label, text, [refs]).
"""

TITLE = ("Architecture", "Архитектура")
LEAD = ("How {name} is built, from the top down: one block diagram of the whole system, then every block "
        "opened up — its parts, data, protocols and step-by-step flows, each step linked to the line of code that does it.",
        "Как устроен {name}, сверху вниз: одна блок-схема всей системы, а внутри каждого блока — его части, данные, "
        "протоколы и пошаговые потоки, и каждый шаг ведёт на строку кода, которая его делает.")

LAYERS = {
    "client": {"color": "#3ee8ff", "name": ("Client shell (Godot)", "Клиент (Godot)")},
    "content": {"color": "#ffb020", "name": ("Game content", "Содержимое игры")},
    "core": {"color": "#b197fc", "name": ("Rust core", "Ядро на Rust")},
    "net": {"color": "#ff3ec8", "name": ("Transports", "Транспорт")},
    "server": {"color": "#3cffb4", "name": ("Game server", "Игровой сервер")},
    "ops": {"color": "#8fb4ff", "name": ("Build, ship, deploy", "Сборка, выпуск, развёртывание")},
    "ext": {"color": "#8fa6c4", "name": ("Outside", "Снаружи")},
}


def P(id, name, x, y, text=None, files=(), sub=None, span=1):
    return {"id": id, "name": name, "x": x, "y": y, "text": text, "files": list(files), "sub": sub, "span": span}


def X(ext, x, y):
    """Another top-level component inside a drill-down: drawn dashed, a click opens it."""
    return {"id": "x_" + ext, "ext": ext, "x": x, "y": y}


def E(a, b, label=None, both=False, dash=False, **kw):
    return dict(kw, **{"from": a, "to": b, "label": label, "both": both, "dash": dash})


def L(id, name, comp, sub=None):
    return {"id": id, "name": name, "comp": comp, "sub": sub}


COMPS = []
FLOWS = []
ARROWS = []


# --- the bots' brain (rust/brain) -------------------------------------------------------------------

COMPS.append(dict(
    id="brain", name=("Bots' brain", "Мозг ботов"), sub="rust/brain", layer="core", x=700, y=470,
    short=("The bot that plays like a person who cannot see your hand: it guesses the hidden cards many times "
           "(\"worlds\"), tries every move in each world with the rules engine and keeps the moves that do best — "
           "easy, medium or hard. The same crate thinks for training in the game and for the server's bots.",
           "Бот, который играет как человек, не видящий вашей руки: много раз угадывает скрытые карты («миры»), в каждом "
           "мире пробует каждый ход движком правил и оставляет лучшие — лёгкий, средний или сложный. Один и тот же крейт думает "
           "и в тренировке в игре, и за ботов сервера."),
    text=("The crate `classichs-brain` depends on the rules engine and nothing else that needs the system: no threads, "
          "no clock of its own (native builds read `Instant`, the browser gives it `performance.now()`), no randomness of "
          "its own (the caller passes a seed). So the same code runs inside the GDExtension library, in a Web Worker of the "
          "browser build and on the server.\n\n"
          "It knows **Classic** only for now: its deck library (35 decks) and Arena tier list are Classic's. Other packs play "
          "against the engine's simple greedy bot (`rust/engine/src/bot.rs`), which also plays the tutorial and the debug table.",
          "Крейт `classichs-brain` зависит от движка правил и ни от чего системного: ни потоков, ни своих часов (нативные "
          "сборки читают `Instant`, браузер даёт `performance.now()`), ни своей случайности (seed передаёт вызывающий). "
          "Поэтому один и тот же код работает в библиотеке GDExtension, в Web Worker браузерной сборки и на сервере.\n\n"
          "Пока он знает только **Classic**: его библиотека колод (35 колод) и таблица карт Арены — классические. Другие "
          "пакеты играют против простого жадного бота движка (`rust/engine/src/bot.rs`); он же играет в обучении и на отладочном столе."),
    parts=[
        X("bridge", 0, 0),
        P("lib", "think()", 1, 0, sub="lib.rs",
          text=("The JSON entry point: level, budget, seat, deck and seed from the request into `Knowledge`, then `decide`.",
                "Вход по JSON: уровень, бюджет, место, колода и seed из запроса в `Knowledge`, затем `decide`."),
          files=[("rust/brain/src/lib.rs", "pub fn think(req: &Value) -> Value {")]),
        X("bots", 2, 0),
        P("decide", ("The search", "Поиск"), 1, 1, sub="brain.rs",
          text=("`decide`: the view becomes a Game, the moves are pruned, worlds are sampled, sequential halving keeps the "
                "better half after every world; `eval` scores a position.",
                "`decide`: вид становится партией, ходы прореживаются, миры сэмплируются, последовательное деление пополам "
                "после каждого мира оставляет лучшую половину; `eval` оценивает позицию."),
          files=[("rust/brain/src/brain.rs", "pub fn decide("), ("rust/brain/src/brain.rs", "pub fn eval(g: &Game, me: usize) -> f64 {"),
                 ("rust/brain/src/brain.rs", "pub enum Level {")]),
        P("clock", ("Clock", "Часы"), 0, 1, sub="clock.rs",
          text=("A monotonic clock: `Instant` natively, an imported `chs_now_ms` in WebAssembly.",
                "Монотонные часы: `Instant` в нативных сборках, импортированная `chs_now_ms` в WebAssembly."),
          files=[("rust/brain/src/clock.rs", "fn chs_now_ms() -> f64;")]),
        P("arena", ("Arena drafting", "Драфт Арены"), 2, 1, sub="arena.rs",
          text=("Hero and card picks by level: the tier score of a card for this class, minus a penalty over the mana curve.",
                "Выбор героя и карт по уровню: оценка карты для этого класса из таблицы минус штраф за перебор по кривой маны."),
          files=[("rust/brain/src/arena.rs", "pub fn pick_card("), ("rust/brain/src/arena.rs", "pub fn pick_score(")]),
        P("cards", ("Library and pools", "Библиотека и пулы"), 1, 2, sub="cards.rs",
          text=("What the bot knows before a game: the deck library, tier scores and per-class pools that weight its guesses of hidden cards.",
                "Что бот знает до партии: библиотека колод, оценки карт и пулы по классам, которые задают вес догадкам о скрытых картах."),
          files=[("rust/brain/src/cards.rs", "pub struct Library {"), ("rust/brain/src/cards.rs", "pub fn sample(")]),
        X("engine", 0, 2),
        P("data", "decks.json · arena_tiers.json", 2, 2,
          text=("35 constructed Classic decks (DECKS.md) and 382 cards with draft scores from a 2014 tier list (ARENA_TIERS.md), built into the crate.",
                "35 классических колод (DECKS.md) и 382 карты с оценками драфта из таблицы 2014 года (ARENA_TIERS.md), вшиты в крейт."),
          files=["rust/brain/src/decks.json", "rust/brain/src/arena_tiers.json", "rust/brain/src/DECKS.md"]),
    ],
    arrows=[
        E("x_bridge", "lib", ("think (JSON)", "think (JSON)")),
        E("x_bots", "decide", "decide"),
        E("x_bots", "arena", ("draft picks", "выбор в драфте")),
        E("lib", "decide", "Knowledge"),
        E("decide", "clock", ("deadline", "срок")),
        E("decide", "cards", ("guess hidden\ncards", "угадать скрытые\nкарты")),
        E("decide", "x_engine", ("view → Game,\nclone + apply", "вид → партия,\nкопия + ход")),
        E("arena", "cards", ("tier scores", "оценки")),
        E("cards", "data", "include_str!"),
    ],
    data=[
        (("Levels", "Уровни"),
         ("**Easy**: 1 world, scores only the move itself, keeps 8 first moves and its opening hand, errs 30% of the time (a random one of its top 3). "
          "**Medium**: 2–3 worlds, plays the rest of its turn on, keeps 10 moves, 300 ms. **Hard**: 4–10 worlds, plays its turn on and lets the engine's "
          "greedy bot answer with the opponent's turn, all moves, 1 s.",
          "**Лёгкий**: 1 мир, оценивает только сам ход, оставляет 8 первых ходов и стартовую руку, в 30% случаев ошибается (случайный из трёх лучших). "
          "**Средний**: 2–3 мира, доигрывает свой ход, 10 ходов, 300 мс. **Сложный**: 4–10 миров, доигрывает ход, а за соперника отвечает жадный бот движка, "
          "все ходы, 1 с.")),
        (("Time", "Время"),
         ("A budget per level (easy 0, medium 300 ms, hard 1000 ms) and a hard stop at twice the budget + 200 ms, checked inside every world.",
          "Бюджет по уровню (лёгкий 0, средний 300 мс, сложный 1000 мс) и жёсткий предел — удвоенный бюджет + 200 мс, проверяется внутри каждого мира.")),
        ("Knowledge",
         ("Seat, its own 30-card deck, the seed and whether it is an Arena game (Arena guesses come from tier-weighted pools).",
          "Место, своя колода из 30 карт, seed и Арена ли это (догадки в Арене берутся из пулов, взвешенных оценками драфта).")),
        (("Position value", "Оценка позиции"),
         ("Own side minus the opponent's: life (with a low-life penalty), minions by attack, health and keywords, weapon, cards in hand, secrets, fatigue; a won game is ±1 000 000.",
          "Своя сторона минус сторона соперника: здоровье (со штрафом за низкое), существа по атаке, здоровью и ключевым словам, оружие, карты в руке, секреты, усталость; выигранная партия — ±1 000 000.")),
    ],
    protocol=[
        (("`think` request", "Запрос `think`"),
         ("`{view, seat, deck, level, budget_ms?, seed?, arena?}` — the view is the engine's snapshot for the bot's own seat.",
          "`{view, seat, deck, level, budget_ms?, seed?, arena?}` — вид — снимок движка для места самого бота.")),
        (("`think` reply", "Ответ `think`"),
         ("`{ok, action|null, label, ms, worlds}` or `{ok: false, error}`.", "`{ok, action|null, label, ms, worlds}` или `{ok: false, error}`.")),
        (("In the client", "В клиенте"),
         ("Not through `Rules.request`: a separate door — `RulesBrain.start/poll` natively, `ClassicRules.think_start/think_result` (a Web Worker) in the browser.",
          "Не через `Rules.request`, а отдельным входом: `RulesBrain.start/poll` в нативных сборках, `ClassicRules.think_start/think_result` (Web Worker) в браузере.")),
    ],
    flows=["bot-decides", "training"],
))

FLOWS.append(dict(
    id="bot-decides", home="brain",
    title=("A bot decides", "Бот выбирает ход"),
    short=("From the bot's own view of the table to one action: determinization, worlds, sequential halving.",
           "От вида стола глазами бота до одного действия: детерминизация, миры, последовательное деление пополам."),
    lanes=[L("caller", ("Caller", "Вызывающий"), "bridge", "RulesBrain · worker · server"), L("lib", "think()", "brain", "lib.rs"),
           L("search", ("Search", "Поиск"), "brain", "brain.rs"), L("pools", ("Pools", "Пулы"), "brain", "cards.rs"),
           L("engine", ("Rules engine", "Движок правил"), "engine")],
    steps=[
        ("caller", "lib", "think {view, seat, deck, level}",
         ("Level (default medium), budget, deck, seat, seed and the Arena flag become `Knowledge`.",
          "Уровень (по умолчанию средний), бюджет, колода, место, seed и признак Арены становятся `Knowledge`."),
         [("rust/brain/src/lib.rs", "pub fn think(req: &Value) -> Value {")]),
        ("lib", "search", "decide", ("The search starts with the time budget of the level.", "Поиск начинается с бюджетом времени уровня."),
         [("rust/brain/src/lib.rs", "brain::decide(&req[\"view\"]")]),
        ("search", "engine", ("view → playable Game", "вид → партия"),
         ("The player's view becomes a real game; cards it cannot see become fillers.",
          "Вид игрока становится настоящей партией; невидимые карты становятся заглушками."),
         [("rust/brain/src/brain.rs", "view::from_snapshot_in("), ("rust/engine/src/view.rs", "pub fn from_snapshot_in(")]),
        ("search", "search", ("mulligan, one option", "муллиган, один ход"),
         ("Game over gives nothing; a mulligan replaces costly cards; with one legal option it is played at once.",
          "Конец партии — ничего; в муллигане меняются дорогие карты; если законный ход один, он и делается."),
         [("rust/brain/src/brain.rs", "fn mulligan(")]),
        ("search", "engine", ("legal moves, pruned", "законные ходы, прорежены"),
         ("Concede is dropped, a minion goes only to the rightmost slot unless a card cares about neighbours, identical copies count once.",
          "Сдача убирается, существо ставится только справа, если ни одной карте не важны соседи, одинаковые копии считаются один раз."),
         [("rust/brain/src/brain.rs", "pub fn options(g: &Game, me: usize) -> Vec<Action> {")]),
        ("search", "pools", ("a world: guess hidden cards", "мир: угадать скрытые карты"),
         ("Its own deck from its list minus what it has seen; the opponent's hand and secrets sampled from the class pool within copy limits.",
          "Своя колода — список минус увиденное; рука и секреты соперника сэмплируются из пула его класса с учётом лимита копий."),
         [("rust/brain/src/brain.rs", "fn determinize("), ("rust/brain/src/cards.rs", "pub fn sample(")]),
        ("search", "engine", ("each move: clone + apply", "каждый ход: копия + ход"),
         ("Each move in each world: copy the game, apply the move, play the rest of the turn greedily (medium, hard), let the engine's bot play the opponent's turn (hard), then score.",
          "Каждый ход в каждом мире: копия партии, ход, жадное доигрывание своего хода (средний, сложный), ход соперника жадным ботом движка (сложный), затем оценка."),
         [("rust/brain/src/brain.rs", "fn score_first("), ("rust/brain/src/brain.rs", "fn finish_turn("), ("rust/brain/src/brain.rs", "fn opponent_turn(")]),
        ("search", "search", ("sequential halving", "деление пополам"),
         ("After every world the moves are sorted by their mean and the worse half drops out (at least two stay), until the budget, the deadline or the last move.",
          "После каждого мира ходы сортируются по среднему, и худшая половина выбывает (остаются минимум два), пока не кончится бюджет, срок или ходы."),
         [("rust/brain/src/brain.rs", "alive.truncate(alive.len().div_ceil(2).max(2));")]),
        ("search", "lib", ("the best move", "лучший ход"),
         ("The best mean wins (easy sometimes picks from its top 3); the decision carries the action, a label, worlds, time and the top candidates.",
          "Побеждает лучшее среднее (лёгкий иногда берёт из трёх лучших); решение несёт действие, подпись, число миров, время и лучших кандидатов."),
         [("rust/brain/src/brain.rs", "let mut best = order[0];")]),
        ("lib", "caller", "{action, label, worlds, ms}",
         ("The reply goes back as JSON; the caller checks the game has not moved meanwhile.",
          "Ответ уходит обратно в JSON; вызывающий проверяет, что партия за это время не изменилась."), []),
    ],
))

FLOWS.append(dict(
    id="training", home="brain",
    title=("A training game against the bot", "Тренировка с ботом"),
    short=("The game menu's Training: the level from the settings, the brain on a thread (desktop, Android) or in a Web Worker (browser).",
           "Тренировка в меню игры: уровень из настроек, мозг в отдельном потоке (ПК, Android) или в Web Worker (браузер)."),
    lanes=[L("setup", ("Training setup", "Тренировка"), "client", "ui/training_setup.gd"), L("match", "Match", "client", "game/match.gd"),
           L("botbrain", "BotBrain", "client", "game/bot_brain.gd"), L("bridge", ("Bridge", "Мост"), "bridge", "RulesBrain · worker"),
           L("brain", ("Brain", "Мозг"), "brain"), L("engine", ("Rules engine", "Движок правил"), "engine")],
    steps=[
        ("setup", "setup", ("easy · medium · hard", "лёгкий · средний · сложный"),
         ("The level buttons store `bot_level` in the settings.", "Кнопки уровня сохраняют `bot_level` в настройках."),
         [("ui/training_setup.gd", "for lvl in BotBrain.LEVELS:"), ("game/settings.gd", "\"bot_level\": \"medium\"")]),
        ("setup", "match", ("start_match(decks, level)", "start_match(колоды, уровень)"),
         ("The player's deck against a bot deck of the chosen class; bots `[false, true]`.",
          "Колода игрока против колоды бота выбранного класса; боты `[false, true]`."),
         [("ui/main.gd", "func start_match(")]),
        ("match", "match", ("is it the bot's move?", "ход бота?"),
         ("After each action: the brain plays when a level is set, the game is local, the pack is Classic and a brain is available; otherwise the engine's greedy bot.",
          "После каждого действия: мозг играет, если задан уровень, партия локальная, пакет — Classic и мозг доступен; иначе — жадный бот движка."),
         [("game/match.gd", "func _after() -> void:"), ("game/match.gd", "func uses_brain() -> bool:")]),
        ("match", "botbrain", ("start(request)", "start(запрос)"),
         ("The request is the engine's snapshot for the bot's seat only, its deck, the level and a seed.",
          "Запрос — снимок движка только для места бота, его колода, уровень и seed."),
         [("game/bot_brain.gd", "static func request("), ("game/bot_brain.gd", "func start(")]),
        ("botbrain", "bridge", ("thread / Web Worker", "поток / Web Worker"),
         ("Desktop and Android: `RulesBrain.start` thinks on a std thread. Browser: `think_start` posts to a Worker with its own WebAssembly instance.",
          "ПК и Android: `RulesBrain.start` думает в отдельном потоке. Браузер: `think_start` отправляет запрос в Worker со своим экземпляром WebAssembly."),
         [("rust/godot/src/lib.rs", "fn start(&mut self, request: GString) {"), ("web/rules.js", "api.think_start = function (req) {")]),
        ("bridge", "brain", "classichs_brain::think", ("The flow \"A bot decides\".", "Поток «Бот выбирает ход»."),
         [("rust/godot/src/lib.rs", "fn think_text(request: &str) -> String {"), ("rust/wasm/src/lib.rs", "pub unsafe extern \"C\" fn think(")]),
        ("match", "botbrain", ("poll every 0.05 s", "опрос каждые 0,05 с"),
         ("At least 0.6 s and never while the table animates; leaving the screen abandons the thought.",
          "Не раньше чем через 0,6 с и не пока стол анимируется; уход с экрана бросает раздумье."),
         [("game/match.gd", "func _bot_think() -> void:"), ("game/bot_brain.gd", "func done()")]),
        ("match", "engine", ("act (or op bot)", "act (или op bot)"),
         ("The move is applied only if the game has not changed; a null or refused move falls back to the engine's greedy `bot`; if that fails too, the bot concedes.",
          "Ход применяется, только если партия не изменилась; пустой или отклонённый ход — запасной жадный `bot` движка; если и он не проходит, бот сдаётся."),
         [("game/match.gd", "func _bot_move("), ("rust/engine/src/api.rs", "\"bot\" => {")]),
    ],
))


# --- server bots (server/src/bots) -----------------------------------------------------------------

COMPS.append(dict(
    id="bots", name=("Server bots", "Боты сервера"), sub="server/src/bots", layer="server", x=700, y=620,
    short=("Bots that live inside the server: ones the admin creates (with levels, modes and hours) and auto-bots that "
           "step in when a Classic player has waited 30 s. They connect through an in-memory WebSocket and think with the brain.",
           "Боты внутри сервера: созданные админом (уровень, режимы, часы) и автоботы, которые выходят, когда игрок Classic ждёт 30 с. "
           "Они подключаются через WebSocket в памяти и думают мозгом."),
    text=("A bot is an ordinary account. It talks to the server exactly like a player: `Transport::local` wires an in-memory "
          "pair of channels into the same `ws::serve` a real WebSocket gets, so a bot cannot do anything a client cannot. "
          "Thinking runs off the async runtime in `spawn_blocking`, through a gate of CPU places where the bot with the nearest "
          "turn deadline goes first.",
          "Бот — обычный аккаунт. С сервером он говорит ровно как игрок: `Transport::local` подключает пару каналов в памяти к той же "
          "`ws::serve`, что и настоящий WebSocket, поэтому бот не может ничего, чего не может клиент. Думает он вне асинхронного рантайма, "
          "в `spawn_blocking`, через «места» по числу ядер: первым идёт бот, у которого раньше кончается время хода."),
    parts=[
        X("admin", 0, 0),
        P("manager", ("Manager", "Менеджер"), 1, 0, sub="mod.rs",
          text=("Starts the enabled bots and stops the rest (`sync`), creates accounts `Bot_<Level>_<n>`.",
                "Запускает включённых ботов и останавливает остальных (`sync`), создаёт аккаунты `Bot_<Level>_<n>`."),
          files=[("server/src/bots/mod.rs", "pub struct Manager {"), ("server/src/bots/mod.rs", "pub async fn sync("), ("server/src/bots/mod.rs", "fn spawn(")]),
        P("auto", ("Auto-bots", "Автоботы"), 2, 0, sub="auto.rs",
          text=("Every second: a Classic player waiting 30 s gets a bot of a level by MMR (or by Arena wins) from a pool of 3 accounts per level.",
                "Каждую секунду: игрок Classic, ждущий 30 с, получает бота уровня по MMR (или по победам в Арене) из пула в 3 аккаунта на уровень."),
          files=[("server/src/bots/auto.rs", "pub async fn tick("), ("server/src/bots/auto.rs", "pub fn level_for_mmr(")]),
        P("transport", ("Transport", "Транспорт"), 0, 2, sub="transport.rs",
          text=("`local`: in-memory channels into `ws::serve` (no login rate limit); `net`: a real WebSocket, used by tests.",
                "`local`: каналы в памяти в `ws::serve` (без лимита входов); `net`: настоящий WebSocket, для тестов."),
          files=[("server/src/bots/transport.rs", "pub fn local(app: &AppRef) -> Transport {")]),
        P("runtime", ("A bot's life", "Жизнь бота"), 1, 1, sub="runtime.rs",
          text=("Its hours and pauses, reconnects, ladder or Arena runs, and the game loop that asks the brain for each move.",
                "Часы работы и паузы, переподключения, рейтинг или Арена и игровой цикл, который спрашивает мозг о каждом ходе."),
          files=[("server/src/bots/runtime.rs", "pub async fn run("), ("server/src/bots/runtime.rs", "async fn play("), ("server/src/bots/runtime.rs", "pub async fn one_game(")]),
        P("think", ("CPU gate", "Очередь на ядра"), 2, 1, sub="think.rs",
          text=("Places for thinking (at least 4); a freed place goes to the waiter with the nearest deadline.",
                "Места для раздумий (не меньше 4); освободившееся место получает тот, у кого ближе срок."),
          files=[("server/src/bots/think.rs", "pub struct Think {"), ("server/src/bots/think.rs", "pub async fn enter(")]),
        X("server", 0, 3),
        P("status", ("Status", "Состояние"), 1, 2, sub="status.rs",
          text=("What the admin page shows: each bot's state, its last decision with the top candidates, a 300-line log, its own view of the board.",
                "Что показывает админка: состояние бота, последнее решение с лучшими кандидатами, журнал на 300 строк, стол его глазами."),
          files=[("server/src/bots/status.rs", "pub struct BotStatus {"), ("server/src/bots/status.rs", "pub fn board(")]),
        X("brain", 2, 2),
        P("table", ("Table bots", "Таблица bots"), 0, 1, sub="entity/bot.rs",
          text=("account, level, modes (ladder, ranked, casual, arena), enabled, hours (from, to), pause range.",
                "аккаунт, уровень, режимы (ladder, ranked, casual, arena), включён ли, часы (с, до), диапазон пауз."),
          files=[("server/src/entity/bot.rs", "#[sea_orm(table_name = \"bots\")]")]),
    ],
    arrows=[
        E("x_admin", "manager", ("create, sync", "создать, sync")),
        E("manager", "runtime", ("spawn", "запуск")),
        E("manager", "table", ("rows", "строки")),
        E("auto", "runtime", "one_game"),
        E("runtime", "transport", "send / next"),
        E("transport", "x_server", ("ws::serve,\nin memory", "ws::serve,\nв памяти")),
        E("runtime", "think", "enter"),
        E("runtime", "x_brain", ("decide\n(spawn_blocking)", "decide\n(spawn_blocking)")),
        E("runtime", "status", ("log, decision", "журнал, решение")),
    ],
    data=[
        (("Accounts", "Аккаунты"), ("`Bot_<Level>_<n>` from the admin page (1–50 at a time, 200 in all); `AutoBot_<Level>_<n>` and `AutoBot_Arena_<n>`, made on demand.",
                                    "`Bot_<Level>_<n>` из админки (1–50 за раз, всего 200); `AutoBot_<Level>_<n>` и `AutoBot_Arena_<n>` создаются по необходимости.")),
        ("Hub", ("`auto_for`: auto-bot → the player it came for; matchmaking pairs that bot only with that player, whatever the window.",
                 "`auto_for`: автобот → игрок, ради которого он вышел; подбор сводит этого бота только с этим игроком, при любом окне.")),
        (("Pace", "Темп"), ("Admin bots wait 0.5–1.3 s like a person when there is time; auto-bots never wait.",
                            "Боты админки ждут 0,5–1,3 с, как человек, если есть время; автоботы не ждут никогда.")),
    ],
    protocol=[
        (("What a bot sends", "Что шлёт бот"), ("`resume`, `packs`, `queue {mode, deck, pack}`, `unqueue`, `me`, `arena_start`, `arena_hero`, `arena_pick`, `arena_queue`, `arena_retire`, `act {game, action}` — the player's own protocol.",
                                                 "`resume`, `packs`, `queue {mode, deck, pack}`, `unqueue`, `me`, `arena_start`, `arena_hero`, `arena_pick`, `arena_queue`, `arena_retire`, `act {game, action}` — протокол обычного игрока.")),
        (("What it reads", "Что читает"), ("`auth`, `match`, `state` (only the newest counts), `act_error`, `game_over`, `arena`, `kicked`.",
                                           "`auth`, `match`, `state` (важен только последний), `act_error`, `game_over`, `arena`, `kicked`.")),
    ],
    flows=["auto-bot", "bot-arena"],
))

FLOWS.append(dict(
    id="auto-bot", home="bots",
    title=("An auto-bot steps in", "Автобот выходит на игру"),
    short=("A Classic player has waited 30 s in the queue: a bot of the right level joins through an in-memory connection and plays the game out.",
           "Игрок Classic ждёт в очереди 30 с: бот подходящего уровня подключается через соединение в памяти и доигрывает партию."),
    lanes=[L("hub", ("Hub (matchmaking)", "Hub (подбор)"), "server", "lib.rs"), L("auto", ("Auto-bots", "Автоботы"), "bots", "auto.rs"),
           L("runtime", ("Bot runtime", "Бот"), "bots", "runtime.rs"), L("ws", "ws::serve", "server", "ws.rs"),
           L("think", ("CPU gate", "Ядра"), "bots", "think.rs"), L("brain", ("Brain", "Мозг"), "brain")],
    steps=[
        ("hub", "auto", ("tick, every 1 s", "tick, каждую секунду"),
         ("Seekers who waited 30 s, not in a friendly game, on the Classic pack, not bots and not already served.",
          "Ищущие игру 30 с, не дружеская игра, пакет Classic, не боты и ещё без бота."),
         [("server/src/lib.rs", "bots::auto::tick(&app).await;"), ("server/src/bots/auto.rs", "pub async fn tick(")]),
        ("auto", "auto", ("level by MMR or wins", "уровень по MMR или победам"),
         ("Under 1350 MMR easy, up to 1650 medium, else hard; in the Arena 0–2 wins easy, 3–5 medium, more hard.",
          "До 1350 MMR — лёгкий, до 1650 — средний, выше — сложный; в Арене 0–2 победы — лёгкий, 3–5 — средний, больше — сложный."),
         [("server/src/bots/auto.rs", "pub fn level_for_mmr("), ("server/src/bots/auto.rs", "pub fn level_for_wins(")]),
        ("auto", "hub", ("take an account, auto_for", "аккаунт, auto_for"),
         ("A free pool account is taken (made if missing) and tied to the player: matchmaking will pair it with that player only.",
          "Берётся свободный аккаунт пула (создаётся, если нет) и привязывается к игроку: подбор сведёт его только с ним."),
         [("server/src/bots/auto.rs", "async fn take("), ("server/src/bots/auto.rs", "app.hub().auto_for.insert(account, player);")]),
        ("auto", "runtime", "one_game",
         ("A one-hour session token and the local transport.", "Токен сессии на час и локальный транспорт."),
         [("server/src/bots/auto.rs", "async fn play_once("), ("server/src/bots/runtime.rs", "pub async fn one_game(")]),
        ("runtime", "ws", ("resume, queue (in memory)", "resume, queue (в памяти)"),
         ("The same session code a WebSocket client gets, over channels in memory.",
          "Тот же код сессии, что у клиента WebSocket, но по каналам в памяти."),
         [("server/src/bots/transport.rs", "tokio::spawn(crate::ws::serve(")]),
        ("hub", "ws", ("pair → match", "пара → match"),
         ("The bot and its player are paired at once; the game task starts as for any two players.",
          "Бот и его игрок сразу становятся парой; задача партии стартует, как для любых двух игроков."),
         [("server/src/lib.rs", "let auto = |x: i64, y: i64|")]),
        ("ws", "runtime", "state",
         ("Only the newest state counts; the bot acts only on its own move.", "Важен только последний state; бот действует только в свой ход."),
         [("server/src/bots/runtime.rs", "async fn read_ahead(")]),
        ("runtime", "think", ("enter (deadline)", "enter (срок)"),
         ("Waits for a CPU place; the nearest turn deadline goes first.", "Ждёт место на ядре; первым идёт тот, у кого ближе конец хода."),
         [("server/src/bots/runtime.rs", "let place = ctx.think.enter(")]),
        ("runtime", "brain", "decide · spawn_blocking",
         ("The brain thinks off the async runtime and holds its place until done.", "Мозг думает вне асинхронного рантайма и держит место до конца."),
         [("server/src/bots/runtime.rs", "let d = tokio::task::spawn_blocking(move || {")]),
        ("runtime", "ws", "act {game, action}",
         ("Dropped if a newer state came meanwhile; the game goes on until `game_over`, then the account is freed.",
          "Отбрасывается, если за это время пришёл новый state; партия идёт до `game_over`, затем аккаунт освобождается."),
         [("server/src/bots/runtime.rs", "c.send(json!({\"t\": \"act\", \"game\": game, \"action\": d.action})).await?;"),
          ("server/src/bots/auto.rs", "app2.hub().auto_for.remove(&account);")]),
    ],
))

FLOWS.append(dict(
    id="bot-arena", home="bots",
    title=("A bot drafts an Arena deck", "Бот собирает колоду Арены"),
    short=("The server's Arena for a bot: a hero, 30 picks by its level, then Arena games where it guesses from tier-weighted pools.",
           "Арена сервера для бота: герой, 30 выборов по уровню, затем игры Арены, где догадки берутся из пулов по оценкам драфта."),
    lanes=[L("runtime", ("Bot runtime", "Бот"), "bots", "runtime.rs"), L("ws", ("Server", "Сервер"), "server", "ws.rs"),
           L("arena", ("Arena drafting", "Драфт"), "brain", "arena.rs"), L("cards", ("Tier scores", "Оценки"), "brain", "cards.rs")],
    steps=[
        ("runtime", "ws", "me → arena_start",
         ("A run of another pack, or (for auto-bots) any old run, is retired first.", "Забег другого пакета или (у автоботов) любой старый забег сначала закрывается."),
         [("server/src/bots/runtime.rs", "async fn arena_game("), ("server/src/bots/runtime.rs", "c.send(with_pack(json!({\"t\": \"arena_start\"}), pack)).await?;")]),
        ("runtime", "arena", "pick_hero", ("One of the three offered heroes, at random.", "Один из трёх предложенных героев, случайно."),
         [("rust/brain/src/arena.rs", "pub fn pick_hero(")]),
        ("runtime", "arena", "pick_card × 30",
         ("Easy takes any card, medium the best 70% of the time, hard always the best.", "Лёгкий берёт любую карту, средний — лучшую в 70% случаев, сложный — всегда лучшую."),
         [("server/src/bots/runtime.rs", "let k = arena::pick_card("), ("rust/brain/src/arena.rs", "pub fn pick_card(")]),
        ("arena", "cards", ("tier − curve penalty", "оценка − штраф кривой"),
         ("The card's score for this class, minus 8 per card over the mana curve target, plus 4 where the curve is short.",
          "Оценка карты для класса, минус 8 за каждую карту сверх цели кривой маны, плюс 4, где кривой не хватает."),
         [("rust/brain/src/arena.rs", "pub fn pick_score("), ("rust/brain/src/cards.rs", "pub fn tier(")]),
        ("runtime", "ws", "arena_hero / arena_pick {i}",
         ("The server recomputes every offer from the run's seed, so a bot cannot fake one either.",
          "Сервер пересчитывает каждое предложение по seed забега, так что и бот не может его подделать."),
         [("server/src/bots/runtime.rs", "c.send(json!({\"t\": \"arena_pick\", \"i\": k})).await?;")]),
        ("runtime", "ws", ("arena_queue → play", "arena_queue → игра"),
         ("Then Arena games; hidden cards are guessed from the Arena pools (tier score squared).",
          "Затем игры Арены; скрытые карты угадываются из пулов Арены (квадрат оценки)."),
         [("server/src/bots/runtime.rs", "if let Some(a) = play(ctx, c, m, strs(&st[\"cards\"]), true, level).await? {")]),
    ],
))

# --- the client shell (ui/, game/) ------------------------------------------------------------------

COMPS.append(dict(
    id="client", name=("Client shell", "Клиент"), sub="Godot 4.7 · ui/ game/", layer="client", x=370, y=170,
    short=("A neutral shell in Godot: the main menu, Direct and Server modes, the game library, and inside a game its own "
           "menu in the pack's look. It draws the table and takes input; every rule is asked from the engine.",
           "Нейтральная оболочка на Godot: главное меню, режимы «Без сервера» и «Через сервер», библиотека игр, а внутри игры — "
           "её собственное меню в оформлении пакета. Клиент рисует стол и принимает ввод; каждое правило он спрашивает у движка."),
    text=("One scene (`ui/main.tscn`, a single `Control`); every screen is a GDScript class that `Main` swaps in. There are no "
          "autoloads: the helpers are static `class_name` classes, and only `Sound` and a few helper nodes are instanced.\n\n"
          "**The shell is neutral.** On the client's own screens (main menu, Play, the library, connections) `Packs.shell` is on and "
          "nothing of a game styles them; the menu plays a neutral track. Entering a game (`Packs.enter`) makes its pack active: the "
          "game menu, the collection, the table and the tutorial take the pack's pictures (`ui/menu`, `ui/board`…), colours, fonts and "
          "particles (`ui/theme.json`), its music and sounds and its texts.\n\n"
          "**Menus in 0.40.** Main menu: Play, Settings, Exit (not on the web). Play → *Direct* (the game library) or *Server* "
          "(connections → a server's home → its games). A game's menu: Collection, Training, Code play (Direct only), Play (Server only: "
          "casual, ranked, Arena), Tutorial (when the pack has one), Settings (+ Debug tools), Leave the game.",
          "Одна сцена (`ui/main.tscn`, один `Control`); каждый экран — класс GDScript, который подставляет `Main`. Автозагрузок нет: "
          "помощники — статические классы `class_name`, создаются только `Sound` и несколько служебных узлов.\n\n"
          "**Оболочка нейтральна.** На собственных экранах клиента (главное меню, «Играть», библиотека, подключения) включён `Packs.shell`, "
          "и ни одна игра их не оформляет; в меню звучит нейтральная музыка. Вход в игру (`Packs.enter`) делает её пакет активным: меню игры, "
          "коллекция, стол и обучение берут картинки пакета (`ui/menu`, `ui/board`…), цвета, шрифты и частицы (`ui/theme.json`), его музыку, "
          "звуки и тексты.\n\n"
          "**Меню в 0.40.** Главное меню: «Играть», «Настройки», «Выход» (не в браузере). «Играть» → *Без сервера* (библиотека игр) или "
          "*Через сервер* (подключения → дом сервера → его игры). Меню игры: «Коллекция», «Тренировка», «Игра по коду» (только без сервера), "
          "«Играть» (только через сервер: обычная, рейтинговая, Арена), «Обучение» (если оно есть в пакете), «Настройки» (+ отладка), «Выйти из игры»."),
    parts=[
        P("main", ("Main (the root)", "Main (корень)"), 3, 2, sub="ui/main.gd",
          text=("Swaps screens (`_set_screen`), owns the running match, a `ServerLink` per connection and the `Social` overlay; waits for the engine at start.",
                "Переключает экраны (`_set_screen`), владеет идущей партией, `ServerLink` на каждое подключение и оверлеем `Social`; при старте ждёт движок."),
          files=[("ui/main.gd", "func _ready() -> void:"), ("ui/main.gd", "func _set_screen(s: Control) -> void:"), ("ui/main.gd", "func _wait_for_rules() -> bool:")]),
        P("menus", ("Menus", "Меню"), 1, 0, sub="ui/menu.gd",
          text=("`MainMenu`: with no pack it is the client's main menu (Play → Direct / Server); with a pack, that game's menu in the pack's look.",
                "`MainMenu`: без пакета — главное меню клиента («Играть» → без сервера / через сервер); с пакетом — меню этой игры в её оформлении."),
          files=[("ui/menu.gd", "func show_main() -> void:"), ("ui/menu.gd", "func show_play() -> void:"), ("ui/menu.gd", "func _show_game() -> void:")]),
        P("library", ("Game library", "Библиотека игр"), 0, 0, sub="ui/games_view.gd",
          text=("Direct mode: the installed packs, their details and art / sound / music sets, Play this game, Import a .cardpack, Delete.",
                "Режим без сервера: установленные пакеты, их описание и наборы арта, звука и музыки, «Играть в это», импорт .cardpack, удаление."),
          files=[("ui/games_view.gd", "func activate(p: Pack) -> void:"), ("ui/games_view.gd", "func import_pack() -> void:"), ("ui/games_view.gd", "func delete_pack(p: Pack) -> void:")]),
        P("connections", ("Connections, server home", "Подключения, дом сервера"), 2, 0, sub="connections_view · server_home",
          text=("Server mode: the list of connections (the same address may appear with another login), the login screen, a server's home with its games, art and music kept on the server, upload.",
                "Режим через сервер: список подключений (один адрес может быть с другим логином), вход, дом сервера с его играми, арт и музыка хранятся на сервере, загрузка."),
          files=[("ui/connections_view.gd", "func _server_row(i: int, e: Dictionary) -> Control:"), ("ui/server_home.gd", "func entries() -> Array:"),
                 ("ui/server_home.gd", "func _game_row(e: Dictionary) -> Control:")]),
        X("serverlink", 3, 0),
        P("settings", ("Settings, migration", "Настройки, миграция"), 3, 3, sub="settings.gd · migration.gd",
          text=("Global settings (language, volumes, card back, animation speed, shake, fullscreen, bot level) in `user://settings.json`; a one-time move of the files of before 0.40.",
                "Общие настройки (язык, громкость, рубашка, скорость анимации, тряска, полный экран, уровень бота) в `user://settings.json`; разовый перенос файлов до 0.40."),
          files=[("game/settings.gd", "static func load_settings() -> void:"), ("game/migration.gd", "static func run() -> bool:"), ("ui/settings_view.gd", "func _store(key: String, value: Variant) -> void:")]),
        P("look", ("Look and sound", "Вид и звук"), 1, 1, sub="palette · fonts · art · scene_fx · sound",
          text=("The pack's `ui/theme.json` over the Classic defaults, its fonts in one shared Theme restyled in place, card art sets, particles by name (embers, rain, snow), music and sound sets.",
                "`ui/theme.json` пакета поверх классических значений, его шрифты в одной общей теме, которая перекрашивается на месте, наборы арта, частицы по имени (угли, дождь, снег), наборы музыки и звуков."),
          files=[("ui/palette.gd", "static func load_theme() -> void:"), ("ui/fonts.gd", "static func restyle() -> void:"), ("ui/scene_fx.gd", "static func make(spec: Variant) -> CPUParticles2D:"),
                 ("game/sound.gd", "static func music(track: String) -> void:")]),
        P("decks", ("Decks, collection", "Колоды, коллекция"), 2, 1, sub="deck_store · decks · deck_list_view",
          text=("Decks per pack in `user://decks*.json`, or the server's decks when playing through a server; a new deck is from scratch or from one of the pack's templates.",
                "Колоды по пакетам в `user://decks*.json` или колоды сервера, когда игра идёт через сервер; новая колода — с нуля или из шаблона пакета."),
          files=[("game/deck_store.gd", "static func load_all() -> Array[Deck]:"), ("game/decks.gd", "static func templates("), ("ui/deck_list_view.gd", "func new_from(template: Dictionary) -> Deck:")]),
        P("tutorial", ("Tutorial", "Обучение"), 3, 1, sub="missions · tutorial · tutorial_view",
          text=("Read from the pack's `tutorial.json`: missions, intro pages, the unlock rule, hints, boss lines and scene effects.",
                "Читается из `tutorial.json` пакета: миссии, вводные страницы, правило открытия, подсказки, реплики босса и эффекты сцены."),
          files=[("game/missions.gd", "static func tutorial() -> Dictionary:"), ("game/tutorial.gd", "func next_hint(g: GameView, p: int) -> String:"), ("ui/tutorial_view.gd", "func show_intro(n: int) -> TutorialIntro:")]),
        X("packs", 0, 1),
        P("screens", ("Training, Code play", "Тренировка, игра по коду"), 0, 2, sub="training_setup · online_view",
          text=("Training: a deck, the bot's class and level. Code play: the name, a game or the Arena, a deck, then the invite and answer codes.",
                "Тренировка: колода, класс и уровень бота. Игра по коду: имя, обычная игра или Арена, колода, затем коды приглашения и ответа."),
          files=[("ui/training_setup.gd", "for lvl in BotBrain.LEVELS:"), ("ui/online_view.gd", "func host_game() -> void:")]),
        P("match", "Match", 1, 2, sub="game/match.gd · game_view.gd",
          text=("Talks to whoever owns the game — the local engine or the server; keeps `GameView` (what the table draws), the bot's step, `plan()` for queued orders.",
                "Говорит с хозяином партии — локальным движком или сервером; хранит `GameView` (что рисует стол), шаг бота, `plan()` для отложенных приказов."),
          files=[("game/match.gd", "func setup(req: Dictionary, bot_players: Array) -> String:"), ("game/match.gd", "func submit(action: Dictionary) -> Dictionary:"),
                 ("game/match.gd", "func plan(acts: Array) -> Dictionary:"), ("game/game_view.gd", "func update(s: Dictionary) -> void:")]),
        P("table", ("Match table", "Игровой стол"), 2, 2, sub="ui/match_view.gd",
          text=("Input (click or drag → Choose One → place → target), the order queue, and every batch of engine events played as ordered steps; mulligan, Coin, result.",
                "Ввод (клик или перетаскивание → «Выберите» → место → цель), очередь приказов и каждая пачка событий движка, сыгранная по шагам; муллиган, Монета, результат."),
          files=[("ui/match_view.gd", "func _act(a: Dictionary) -> void:"), ("ui/match_view.gd", "static func steps(events: Array, aimed := -1) -> Array:"), ("ui/match_view.gd", "func _play_step(st: Dictionary) -> void:")]),
        X("codeplay", 0, 3),
        X("bridge", 1, 3),
        P("botbrain", "BotBrain", 2, 3, sub="game/bot_brain.gd",
          text=("The training bot of a level, off the main thread: `RulesBrain` natively, a Web Worker in the browser.",
                "Бот тренировки с уровнем вне главного потока: `RulesBrain` в нативных сборках, Web Worker в браузере."),
          files=[("game/bot_brain.gd", "static func available()"), ("game/bot_brain.gd", "func start(")]),
    ],
    arrows=[
        E("menus", "library", ("Direct", "Без сервера"), both=True),
        E("menus", "connections", ("Server", "Сервер"), both=True),
        E("connections", "x_serverlink", "ServerLink", both=True),
        E("x_packs", "library", ("installed", "установлены"), dash=True),
        E("x_packs", "look", ("theme, music", "тема, музыка")),
        E("menus", "look", "Packs.look()"),
        E("menus", "decks", ("Collection", "Коллекция")),
        E("menus", "tutorial", ("Tutorial", "Обучение")),
        E("menus", "screens", ("Training,\nCode play", "Тренировка,\nпо коду"), lx=196, ly=236),
        E("screens", "match", "start_match"),
        E("tutorial", "match", ("mission", "миссия")),
        E("match", "table", ("events ⇄\nsubmit", "события ⇄\nsubmit"), both=True),
        E("main", "table", ("opens", "открывает")),
        E("main", "settings", ("load, migrate", "загрузка, миграция")),
        E("screens", "x_codeplay", "NetSession"),
        E("match", "x_bridge", "Rules.request"),
        E("match", "botbrain", "start / done"),
        E("botbrain", "x_bridge", "think"),
    ],
    data=[
        ("`user://settings.json`", ("language, music, sfx, shake, fullscreen, anim_speed, card_back, bot_level, `servers` [{id, url, name}] (a second login to an address gets the id `<url>#2`), `pack` (the active one), `pack_sets` (art, sound, music per pack), `layout` (0 before 0.40).",
                                    "language, music, sfx, shake, fullscreen, anim_speed, card_back, bot_level, `servers` [{id, url, name}] (второй вход на тот же адрес получает id `<url>#2`), `pack` (активный), `pack_sets` (арт, звук, музыка по пакетам), `layout` (0 до 0.40).")),
        ("`user://decks.json`, `decks.<pack>.json`", ("Classic's decks and each other pack's, `{version: 2, decks}`; written through a `.tmp`, a damaged file is kept as `*.bad.json`. A deck kept on a server carries `servers: {url: {id, at}}`.",
                                                       "Колоды Classic и каждого другого пакета, `{version: 2, decks}`; запись через `.tmp`, повреждённый файл сохраняется как `*.bad.json`. Колода на сервере несёт `servers: {url: {id, at}}`.")),
        ("`user://packs/`", ("Downloaded, imported and received packs as `<content_hash>.cardpack` with `index.json`; the built-in ones are `res://packs/*.cardpack`.",
                             "Скачанные, импортированные и полученные пакеты как `<content_hash>.cardpack` с `index.json`; встроенные — `res://packs/*.cardpack`.")),
        ("`user://server_session.json`, `tutorial.json`, `profile.json`", ("Saved logins per connection id; finished missions per pack; the name offered before Code play. In the browser `user://` lives in IndexedDB.",
                                                                            "Сохранённые входы по id подключения; пройденные миссии по пакетам; имя, которое предлагается перед игрой по коду. В браузере `user://` хранится в IndexedDB.")),
        (("In memory", "В памяти"), ("`Main.mode` (\"\", direct, server), `Packs.shell` and the active pack, `DeckStore.link` (non-null: the decks are the server's), `MatchView._queue` (event batches) and `_pending_acts` (queued orders).",
                                    "`Main.mode` (\"\", direct, server), `Packs.shell` и активный пакет, `DeckStore.link` (не null — колоды сервера), `MatchView._queue` (пачки событий) и `_pending_acts` (отложенные приказы).")),
    ],
    protocol=[
        (("Match → table", "Match → стол"), ("`changed(events)`, `finished(winner)`, `refused(error)`; the table sets `busy` so the bot waits for the animations.",
                                            "`changed(events)`, `finished(winner)`, `refused(error)`; стол задаёт `busy`, чтобы бот ждал конца анимаций.")),
        (("Match → authority", "Match → хозяин партии"), ("Local: `Rules.request` ops `new`, `act`, `snapshot`, `legal`, `bot`. Server: `{t: act, game, action}` and the server's `state`. Code play: `local_action(action, hash)` / `submit_remote`.",
                                                         "Локально: операции `Rules.request` `new`, `act`, `snapshot`, `legal`, `bot`. Сервер: `{t: act, game, action}` и `state` сервера. По коду: `local_action(action, hash)` / `submit_remote`.")),
    ],
    flows=["startup", "direct-game", "card-played", "tutorial", "migration"],
))

FLOWS.append(dict(
    id="startup", home="client",
    title=("Start-up", "Запуск"),
    short=("From `main.tscn` to the first screen: settings, the migration, the neutral shell, the engine wait, the language picker or the main menu.",
           "От `main.tscn` до первого экрана: настройки, миграция, нейтральная оболочка, ожидание движка, выбор языка или главное меню."),
    lanes=[L("godot", "Godot", "client", "project.godot"), L("main", "Main", "client", "ui/main.gd"), L("settings", ("Settings", "Настройки"), "client", "settings · migration"),
           L("packs", "Packs", "packs", "game/packs.gd"), L("rules", "Rules", "bridge", "game/rules.gd"), L("menu", ("Main menu", "Главное меню"), "client", "ui/menu.gd")],
    steps=[
        ("godot", "main", ("main.tscn → _ready", "main.tscn → _ready"),
         ("One scene, a single Control with `ui/main.gd`; the engine library loads with the game (GDExtension) or `rules.js` starts fetching `rules.wasm`.",
          "Одна сцена, один Control с `ui/main.gd`; библиотека движка загружается вместе с игрой (GDExtension) или `rules.js` начинает качать `rules.wasm`."),
         [("project.godot", "run/main_scene=\"res://ui/main.tscn\""), ("ui/main.gd", "func _ready() -> void:")]),
        ("main", "settings", ("load, migrate", "загрузка, миграция"),
         ("Translations and sprites, then `user://settings.json`; the files of before 0.40 move once.",
          "Переводы и спрайты, затем `user://settings.json`; файлы до 0.40 переносятся один раз."),
         [("ui/main.gd", "Settings.load_settings()"), ("ui/main.gd", "Migration.run()")]),
        ("main", "packs", ("shell on, theme", "оболочка, тема"),
         ("No game styles the client's own screens; the shared Theme goes on the root.",
          "Ни одна игра не оформляет экраны клиента; общая тема ставится на корень."),
         [("ui/main.gd", "Packs.set_shell(true)  # the main menu"), ("ui/main.gd", "theme = Fonts.theme()")]),
        ("main", "main", ("Sound, paste, keyboard", "звук, вставка, клавиатура"),
         ("The one Sound node; WebPaste on the web, KeyboardLift on touch screens; a `ServerLink` per saved connection (not opened yet) and the `Social` overlay.",
          "Один узел Sound; WebPaste в браузере, KeyboardLift на сенсорных экранах; `ServerLink` на каждое сохранённое подключение (пока не открыт) и оверлей `Social`."),
         [("ui/main.gd", "add_child(Sound.new())"), ("ui/main.gd", "func _start_server_link() -> void:")]),
        ("main", "rules", ("wait for the engine", "ждать движок"),
         ("Up to 30 s while `Rules.missing()` says loading (the browser fetches rules.wasm); no engine — a full-screen notice instead of the menu.",
          "До 30 с, пока `Rules.missing()` отвечает «loading» (браузер качает rules.wasm); нет движка — вместо меню надпись на весь экран."),
         [("ui/main.gd", "func _wait_for_rules() -> bool:"), ("game/rules.gd", "static func missing() -> String:")]),
        ("main", "menu", ("language picker or menu", "выбор языка или меню"),
         ("First run: the language picker, then the menu; otherwise the main menu: Play, Settings, Exit.",
          "Первый запуск: выбор языка, затем меню; иначе сразу главное меню: «Играть», «Настройки», «Выход»."),
         [("ui/main.gd", "func show_language_picker() -> void:"), ("ui/main.gd", "func show_menu(play := false) -> void:"), ("ui/menu.gd", "func show_main() -> void:")]),
    ],
))

FLOWS.append(dict(
    id="direct-game", home="client",
    title=("Direct mode: into a game's menu", "Без сервера: в меню игры"),
    short=("Play → Direct → the game library → Play this game: the pack becomes active and its menu appears in its own look.",
           "«Играть» → «Без сервера» → библиотека → «Играть в это»: пакет становится активным, и его меню появляется в его оформлении."),
    lanes=[L("menu", ("Menus", "Меню"), "client", "ui/menu.gd"), L("main", "Main", "client", "ui/main.gd"), L("library", ("Library", "Библиотека"), "client", "ui/games_view.gd"),
           L("packs", "Packs", "packs", "game/packs.gd"), L("look", ("Look", "Вид"), "client", "palette · fonts · sound")],
    steps=[
        ("menu", "main", ("Play → Direct", "Играть → Без сервера"), ("The Play submenu: Direct, Server, Back.", "Подменю «Играть»: без сервера, через сервер, назад."),
         [("ui/menu.gd", "func show_play() -> void:"), ("ui/main.gd", "m.direct.connect(show_library)")]),
        ("main", "library", "show_library",
         ("Mode `direct`, the decks are local (`DeckStore.link = null`), the shell stays neutral.", "Режим `direct`, колоды локальные (`DeckStore.link = null`), оболочка остаётся нейтральной."),
         [("ui/main.gd", "func show_library() -> GamesView:")]),
        ("library", "packs", ("tiles; sets; import", "плитки; наборы; импорт"),
         ("Every installed pack with its details; the art / sound / music choice per pack goes to `pack_sets`; a file can be imported.",
          "Все установленные пакеты с описанием; выбор арта, звука и музыки по пакету идёт в `pack_sets`; можно импортировать файл."),
         [("ui/games_view.gd", "static func set_picker("), ("game/packs.gd", "static func set_choice(p: Pack, kind: String, value: String) -> void:")]),
        ("library", "main", ("Play this game", "Играть в это"), ("`entered(pack)`.", "`entered(pack)`."), [("ui/games_view.gd", "func activate(p: Pack) -> void:")]),
        ("main", "packs", "Packs.enter(pack)",
         ("Shell off, the pack is active (saved in the settings), every cache is reset and the engine will load its rules on the next request.",
          "Оболочка выключена, пакет активен (сохраняется в настройках), все кэши сброшены, и движок загрузит его правила при следующем запросе."),
         [("ui/main.gd", "func enter_game(p: Pack) -> MainMenu:"), ("game/packs.gd", "static func enter(p: Pack, sets := {}) -> void:"), ("game/packs.gd", "static func _changed() -> void:")]),
        ("packs", "look", ("restyle", "перекрасить"),
         ("The pack's theme, fonts and particles restyle the open screens in place.", "Тема, шрифты и частицы пакета перекрашивают открытые экраны на месте."),
         [("ui/palette.gd", "static func load_theme() -> void:"), ("ui/fonts.gd", "static func restyle() -> void:")]),
        ("main", "menu", ("the game's menu", "меню игры"),
         ("Its background picture, title or logo, particles and menu music; items by what the pack and the platform can do.",
          "Фон, название или логотип, частицы и музыка меню игры; пункты — по тому, что умеют пакет и платформа."),
         [("ui/main.gd", "func show_game_menu() -> MainMenu:"), ("ui/menu.gd", "func _show_game() -> void:"), ("game/packs.gd", "static func picture(name: String) -> Texture2D:")]),
    ],
))

FLOWS.append(dict(
    id="card-played", home="client",
    title=("A card is played", "Розыгрыш карты"),
    short=("Input on the table → Match → the engine applies it → events → the table plays them as ordered steps.",
           "Ввод на столе → Match → движок применяет ход → события → стол проигрывает их по шагам."),
    lanes=[L("table", ("Match table", "Стол"), "client", "ui/match_view.gd"), L("match", "Match", "client", "game/match.gd"),
           L("rules", "Rules", "bridge", "game/rules.gd"), L("engine", ("Rules engine", "Движок правил"), "engine"), L("lua", "Lua", "lua")],
    steps=[
        ("table", "table", ("press, drag, click", "нажатие, перетаскивание"),
         ("A card is pressed or dragged onto the board or a target.", "Карту нажимают или тянут на стол или на цель."),
         [("ui/match_view.gd", "func _on_press(v: EntityView) -> void:"), ("ui/match_view.gd", "func _drop_at(m: Vector2, id: int) -> void:")]),
        ("table", "match", ("legal actions (plan)", "законные ходы (plan)"),
         ("The legal actions for this card, after any orders still queued; Choose One, then the place, then the target narrow them to one.",
          "Законные ходы этой карты с учётом ещё не выполненных приказов; «Выберите», место и цель сужают их до одного."),
         [("ui/match_view.gd", "func _select(id: int) -> void:"), ("ui/match_view.gd", "func _advance() -> void:"), ("game/match.gd", "func plan(acts: Array) -> Dictionary:")]),
        ("table", "match", ("submit (or queue)", "submit (или очередь)"),
         ("While the table animates or waits for a server, the order waits in `_pending_acts`; otherwise it goes now.",
          "Пока стол анимируется или ждёт сервер, приказ ждёт в `_pending_acts`; иначе уходит сразу."),
         [("ui/match_view.gd", "func _act(a: Dictionary) -> void:"), ("game/match.gd", "func submit(action: Dictionary) -> Dictionary:")]),
        ("match", "rules", "{op: act}", ("A local game asks its own engine; a server game sends `act` and waits for the server's `state`.",
                                        "Локальная партия спрашивает свой движок; серверная шлёт `act` и ждёт `state` сервера."),
         [("game/match.gd", "func _apply(action: Variant) -> Dictionary:"), ("game/rules.gd", "static func request(req: Dictionary) -> Dictionary:")]),
        ("rules", "engine", "Game::apply",
         ("Legal or refused; then the play itself and every trigger until all is quiet (the flow \"Inside the engine\").",
          "Законен ход или нет; затем сам розыгрыш и все срабатывания, пока всё не затихнет (поток «Ход внутри движка»)."),
         [("rust/engine/src/game.rs", "pub fn apply(&mut self, action: &Value) -> Applied {")]),
        ("engine", "lua", ("the card's hook", "хук карты"), ("Battlecry, spell or trigger as Lua from the pack.", "Боевой клич, заклинание или триггер — Lua из пакета."),
         [("rust/engine/src/game.rs", "fn run_effect(&mut self, e: Id, key: &str")]),
        ("engine", "match", ("{ok, hash, events}", "{ok, hash, events}"),
         ("The new hash and the events; Match takes a snapshot into `GameView` and the history.", "Новый хэш и события; Match берёт снимок в `GameView` и историю."),
         [("game/match.gd", "func _sync() -> void:"), ("game/game_view.gd", "func update(s: Dictionary) -> void:")]),
        ("match", "table", "changed(events)",
         ("The batch and the game right after it join the queue.", "Пачка и партия сразу после неё встают в очередь."),
         [("ui/match_view.gd", "func _on_changed(events: Array) -> void:"), ("ui/match_view.gd", "func _play_queue() -> void:")]),
        ("table", "table", ("events → ordered steps", "события → шаги по порядку"),
         ("play, aim, summon, attack, hits grouped per source, deaths, draws, the Coin…; random multi-hits (Arcane Missiles, Mad Bomber) one hit per step.",
          "розыгрыш, прицел, призыв, атака, удары по источнику, смерти, добор, Монета…; случайные удары (Чародейские стрелы, Безумный бомбардир) — по одному за шаг."),
         [("ui/match_view.gd", "static func steps(events: Array, aimed := -1) -> Array:"), ("ui/match_view.gd", "static func _one_by_one(ev: Dictionary) -> bool:")]),
        ("table", "table", ("play each step", "сыграть каждый шаг"),
         ("The card flies and is shown, an arrow to its target, then each change; the board between steps comes from the events, so the numbers change in the order they happened.",
          "Карта летит и показывается, стрелка к цели, затем каждое изменение; стол между шагами строится по событиям, так что числа меняются в том порядке, в каком всё случилось."),
         [("ui/match_view.gd", "func _animate(item: Dictionary) -> void:"), ("ui/match_view.gd", "func _play_step(st: Dictionary) -> void:"), ("ui/match_view.gd", "func _step_apply(st: Dictionary) -> Dictionary:")]),
        ("table", "match", ("refresh, release orders", "обновить, выпустить приказы"),
         ("Views glide to their places, the queued orders go in turn (an impossible one cancels the rest), then the bot may move.",
          "Виды скользят на места, отложенные приказы уходят по очереди (невозможный отменяет остальные), затем может ходить бот."),
         [("ui/match_view.gd", "func _reconcile(want: Dictionary) -> void:"), ("ui/match_view.gd", "func _release_orders() -> void:"), ("game/match.gd", "func _after() -> void:")]),
    ],
))

FLOWS.append(dict(
    id="tutorial", home="client",
    title=("The tutorial from the pack", "Обучение из пакета"),
    short=("Missions, intro pages, hints, boss lines and scene effects come from the pack's `tutorial.json`; the engine runs the mission's rules.",
           "Миссии, вводные страницы, подсказки, реплики босса и эффекты сцены берутся из `tutorial.json` пакета; правила миссии исполняет движок."),
    lanes=[L("pack", ("Pack", "Пакет"), "packs", "tutorial.json · missions/"), L("view", ("Tutorial screens", "Экраны обучения"), "client", "tutorial_view · intro"),
           L("main", "Main", "client", "ui/main.gd"), L("match", "Match", "client"), L("engine", ("Rules engine", "Движок"), "engine", "missions.rs"),
           L("table", ("Table", "Стол"), "client", "match_view · tutorial.gd")],
    steps=[
        ("pack", "view", "tutorial.json",
         ("Only a pack with missions has a Tutorial item (Classic has six; Neonfall none).", "Пункт «Обучение» есть только у пакета с миссиями (у Classic их шесть, у Neonfall нет)."),
         [("game/pack.gd", "func has_tutorial() -> bool:"), ("game/missions.gd", "static func tutorial() -> Dictionary:")]),
        ("view", "view", ("tiles, unlock, effect", "плитки, открытие, эффект"),
         ("The lock state follows the pack's rule (in order or all); the tutorial-wide scene effect plays behind the tiles.",
          "Замки — по правилу пакета (по порядку или все сразу); общий эффект сцены играет за плитками."),
         [("game/progress.gd", "static func unlocked(n: int) -> bool:"), ("ui/tutorial_view.gd", "var fx := SceneFx.make(")]),
        ("view", "view", ("intro pages", "вводные страницы"), ("Each page may name its own effect; a mission without pages starts at once.",
                                                           "У каждой страницы может быть свой эффект; миссия без страниц начинается сразу."),
         [("ui/tutorial_intro.gd", "func panels() -> Array:")]),
        ("view", "main", "start_tutorial(n)", ("The mission number goes to a new match table.", "Номер миссии уходит на новый игровой стол."), [("ui/main.gd", "func start_tutorial(n: int) -> MatchView:")]),
        ("main", "match", "{mission: n}", ("The engine's greedy bot plays the boss (no level).", "Босса играет жадный бот движка (без уровня)."), []),
        ("match", "engine", ("mission rules", "правила миссии"),
         ("Fixed hands and decks, no mulligan, maybe no hero power, a guard on the hero; \"not yet!\" to end the turn is the engine's answer too.",
          "Заданные руки и колоды, без муллигана, иногда без силы героя, защита героя; «ещё рано» на конец хода — тоже ответ движка."),
         [("rust/engine/src/missions.rs", "pub fn start_in("), ("game/match.gd", "func end_turn_block(p: int) -> String:")]),
        ("table", "table", ("hints, boss lines", "подсказки, реплики"),
         ("Conditions from the pack choose the hint and the boss's line; the mission's effect plays over the board.",
          "Условия из пакета выбирают подсказку и реплику босса; эффект миссии идёт поверх стола."),
         [("game/tutorial.gd", "func boss_line(g: GameView) -> String:"), ("ui/match_view.gd", "func _try_tutorial_hint() -> void:")]),
        ("table", "view", ("win → next mission", "победа → следующая"), ("A win is recorded per pack; Next or Try Again.", "Победа записывается по пакету; «Дальше» или «Ещё раз»."),
         [("ui/match_view.gd", "func _tutorial_result(box: VBoxContainer) -> void:"), ("game/progress.gd", "static func complete(n: int) -> void:")]),
    ],
))

FLOWS.append(dict(
    id="migration", home="client",
    title=("The 0.40 migration", "Переход на 0.40"),
    short=("A player's folder of before 0.40: set choices move into Classic's per-game settings, decks into the pack they belong to.",
           "Папка игрока до 0.40: выбор наборов переходит в настройки Classic, колоды — в пакет, которому они принадлежат."),
    lanes=[L("main", "Main", "client"), L("settings", "Settings", "client", "game/settings.gd"), L("mig", "Migration", "client", "game/migration.gd"),
           L("store", "DeckStore", "client", "user://decks*.json")],
    steps=[
        ("main", "settings", "load_settings",
         ("The raw old file is kept in `Settings.old`; an old single server becomes the first connection with its address as the id, so its saved login stays.",
          "Старый файл как есть остаётся в `Settings.old`; старый единственный сервер становится первым подключением с адресом в роли id, и сохранённый вход остаётся."),
         [("game/settings.gd", "static var old: Dictionary = {}")]),
        ("main", "mig", ("run, once", "run, один раз"), ("Only when `layout` is below the current one.", "Только если `layout` меньше текущего."),
         [("game/migration.gd", "const LAYOUT := 1"), ("game/migration.gd", "static func run() -> bool:")]),
        ("mig", "settings", ("sets → Classic's", "наборы → Classic"),
         ("The old top-level art and music choices become `pack_sets[\"classic-2014\"]`, unless chosen there already.",
          "Старые общие выбор арта и музыки становятся `pack_sets[\"classic-2014\"]`, если там ещё ничего не выбрано."), []),
        ("mig", "store", ("refile decks", "разложить колоды"),
         ("An unchanged ready-made deck is dropped (it is a template now); a deck whose cards belong to another installed pack moves there; damaged files stay as they are.",
          "Неизменённая готовая колода удаляется (теперь это шаблон); колода с картами другого установленного пакета переезжает туда; повреждённые файлы не трогаются."),
         [("game/migration.gd", "static func move_decks() -> void:"), ("game/migration.gd", "static func _fits("), ("game/deck_store.gd", "static func write(at: String, decks: Array) -> bool:")]),
        ("mig", "settings", ("stamp layout", "отметить layout"), ("Saved, so it never runs again; tested on an old folder.", "Сохраняется, и больше не запускается; проверено тестом на старой папке."),
         [("tests/test_migration.gd", "func test_the_old_folder_moves_to_the_new_layout() -> void:")]),
    ],
))

# --- the rules engine (rust/engine) ------------------------------------------------------------------

COMPS.append(dict(
    id="engine", name=("Rules engine", "Движок правил"), sub="rust/engine", layer="core", x=370, y=470,
    short=("The only code of the rules: a deterministic model of a card game with general mechanics. It has no cards of its own — "
           "rules, cards and their Lua hooks come from the pack. One JSON request in, one JSON reply out; the same crate on every platform and on the server.",
           "Единственный код правил: детерминированная модель карточной игры с общими механиками. Своих карт у него нет — правила, карты и их "
           "Lua-хуки приходят из пакета. Один JSON-запрос на входе, один JSON-ответ на выходе; один и тот же крейт на всех платформах и на сервере."),
    text=("Inside, the data is typed (`Act`, `Entity`, `Obj` of `Str`/`V`, `Arc<Entity>` shared copy-on-write between a game and its "
          "look-ahead copies); JSON appears only at the boundary: requests, replies, snapshots, events and the Lua table conversion. "
          "A `Ruleset` is built once per `rules_hash` and kept for the whole process, so every game of a pack points into it.\n\n"
          "**Deterministic.** Godot's PCG32 random generator bit for bit, integers only (the Lua too), `pairs` in insertion order. "
          "`state_hash` is the SHA-256 of a JSON text written byte for byte as Godot's `JSON.stringify` would — the same pack, seed and "
          "moves give the same hash on every platform, which is what code play checks after every move.",
          "Внутри данные типизированы (`Act`, `Entity`, `Obj` из `Str`/`V`, `Arc<Entity>`, общие для партии и её копий для просмотра вперёд, "
          "копируются при записи); JSON — только на границе: запросы, ответы, снимки, события и перевод в таблицы Lua. `Ruleset` строится один раз "
          "на `rules_hash` и живёт весь процесс, и все партии пакета указывают в него.\n\n"
          "**Детерминизм.** ГСЧ PCG32 как у Godot бит в бит, только целые числа (и в Lua), `pairs` в порядке вставки. `state_hash` — SHA-256 "
          "от JSON, записанного байт в байт как `JSON.stringify` у Godot: одинаковые пакет, seed и ходы дают одинаковый хэш на любой "
          "платформе — это и сверяет игра по коду после каждого хода."),
    parts=[
        X("bridge", 0, 0), X("server", 1, 0), X("packs", 2, 0),
        P("build", "build.rs", 3, 0, text=("Embeds the built-in Classic: `packs/classic` and `cards.json` made from `data/cards.json` + `cards.patch.json`.",
                                         "Вшивает встроенный Classic: `packs/classic` и `cards.json` из `data/cards.json` + `cards.patch.json`."),
          files=[("rust/engine/build.rs", "fn main() {")]),
        P("api", ("JSON API", "JSON API"), 0, 1, sub="api.rs",
          text=("`Engine`: games by id and the loaded packs; `call` parses, catches a panic (that game is dropped), `handle` dispatches the op; player views and their events.",
                "`Engine`: партии по id и загруженные пакеты; `call` разбирает запрос и ловит панику (такая партия удаляется), `handle` раздаёт операции; виды игроков и их события."),
          files=[("rust/engine/src/api.rs", "pub fn call(&mut self, req: &str) -> String {"), ("rust/engine/src/api.rs", "pub fn handle(&mut self, req: &Value) -> Value {"),
                 ("rust/engine/src/api.rs", "pub fn snapshot(g: &Game, view: i64) -> Value {")]),
        P("ruleset", "Ruleset", 1, 1, sub="ruleset.rs",
          text=("One pack's rules, cards, mechanic names (`Names`), classes, Arena, missions and hooks; a process-wide cache by `rules_hash`.",
                "Правила, карты, имена механик (`Names`), классы, Арена, миссии и хуки одного пакета; общий для процесса кэш по `rules_hash`."),
          files=[("rust/engine/src/ruleset.rs", "pub fn from_files(files: &Files, builtin: bool)"), ("rust/engine/src/ruleset.rs", "pub fn load(files: &Files) -> Result<&'static Ruleset, String> {")]),
        P("pack", ("Pack reading", "Чтение пакета"), 2, 1, sub="pack.rs",
          text=("A .cardpack zip (or a folder) with every limit of the format, strict and canonical JSON, the `rules_hash`.",
                "Zip .cardpack (или папка) со всеми пределами формата, строгий и канонический JSON, `rules_hash`."),
          files=[("rust/engine/src/pack.rs", "pub fn read_zip(b: &[u8]) -> Result<Files, String> {"), ("rust/engine/src/pack.rs", "pub fn rules_hash(files: &Files) -> Result<String, String> {")]),
        P("rng", ("Determinism", "Детерминизм"), 3, 1, sub="rng.rs · json.rs",
          text=("PCG32 as in Godot, `JSON.stringify` as in Godot (the hash text), the mulligan's own seed per player.",
                "PCG32 как в Godot, `JSON.stringify` как в Godot (текст для хэша), отдельный seed муллигана для каждого игрока."),
          files=[("rust/engine/src/rng.rs", "pub struct Rng {"), ("rust/engine/src/json.rs", "pub fn stringify(v: &Value) -> String {"), ("rust/engine/src/game.rs", "pub fn mulligan_seed(seed: u64, p: usize) -> u64 {")]),
        P("game", ("Turns and legality", "Ходы и законность"), 0, 2, sub="game.rs",
          text=("Set-up, mulligan, turns; the legal actions (costs, `can_play`, target filters); `apply` checks an action against them and plays it.",
                "Подготовка, муллиган, ходы; законные действия (стоимость, `can_play`, фильтры целей); `apply` сверяет действие с ними и выполняет его."),
          files=[("rust/engine/src/game.rs", "pub fn apply(&mut self, action: &Value) -> Applied {"), ("rust/engine/src/game.rs", "pub fn legal(&self) -> Vec<Act> {"),
                 ("rust/engine/src/game.rs", "fn do_play(&mut self, e: Id, t: Id, pos: i64, choice: i64) {")]),
        P("state", ("State and resolution", "Состояние и разрешение"), 1, 2, sub="state.rs",
          text=("`Game`: entities, the event log and the trigger queue, `resolve` until quiet, the death phase, auras, the primitives hooks call, `state_hash`.",
                "`Game`: сущности, журнал событий и очередь триггеров, `resolve` до затишья, фаза смертей, ауры, примитивы для хуков, `state_hash`."),
          files=[("rust/engine/src/state.rs", "pub struct Game {"), ("rust/engine/src/state.rs", "pub fn resolve(&mut self) {"), ("rust/engine/src/state.rs", "fn death_phase(&mut self) -> bool {"),
                 ("rust/engine/src/state.rs", "pub fn state_hash(&self) -> String {")]),
        P("luaglue", ("Lua glue", "Связка с Lua"), 2, 2, sub="lua.rs · hooks.rs",
          text=("Builds the pack's hooks (`HookSet`: indexes of Lua functions), the `g` library (51 queries, 45 actions), calls hooks, ends a game on a script error.",
                "Собирает хуки пакета (`HookSet`: номера Lua-функций), библиотеку `g` (51 запрос, 45 действий), вызывает хуки, заканчивает партию при ошибке скрипта."),
          files=[("rust/engine/src/lua.rs", "pub(crate) fn build(rs: &Ruleset, scripts:"), ("rust/engine/src/hooks.rs", "pub struct HookSet {"), ("rust/engine/src/lua.rs", "pub(crate) fn end_by_script_error(&mut self) {")]),
        X("lua", 3, 2),
        P("view", ("Views", "Виды"), 0, 3, sub="view.rs",
          text=("A playable game rebuilt from a player's view (`new {state}`): hidden cards become fillers; its legal moves match the server's.",
                "Играбельная партия из вида игрока (`new {state}`): скрытые карты становятся заглушками; её законные ходы совпадают с серверными."),
          files=[("rust/engine/src/view.rs", "pub fn from_snapshot_in(")]),
        P("bot", ("Greedy bot", "Жадный бот"), 1, 3, sub="bot.rs",
          text=("One-step greedy (two with the pack's `bot.depth`), sees everything: the tutorial, other packs, the fallback, the opponent inside the hard brain, the server's pack trial.",
                "Жадный на один шаг (на два с `bot.depth` пакета), видит всё: обучение, другие пакеты, запасной ход, соперник в сложном мозге, проба пакета на сервере."),
          files=[("rust/engine/src/bot.rs", "pub fn choose(g: &Game, p: usize) -> Option<Action> {")]),
        P("modes", ("Decks, Arena, missions", "Колоды, Арена, миссии"), 2, 3, sub="deck · arena_draft · missions · scenario",
          text=("Deck rules of the pack, the stateless Arena draft by `modes.arena`, the rules part of tutorial missions, debug scenes.",
                "Правила колод пакета, драфт Арены без состояния по `modes.arena`, правила миссий обучения, отладочные сцены."),
          files=[("rust/engine/src/deck.rs", "pub fn validate_in("), ("rust/engine/src/arena_draft.rs", "pub fn new_in(rs: &'static Ruleset, seed: i64)"),
                 ("rust/engine/src/missions.rs", "pub fn end_turn_block("), ("rust/engine/src/scenario.rs", "pub fn build_in(")]),
        X("brain", 3, 3),
    ],
    arrows=[
        E("x_bridge", "api", "call_json"),
        E("x_server", "api", ("Engine, Game", "Engine, Game")),
        E("x_packs", "pack", ("zip bytes", "байты zip")),
        E("build", "ruleset", "Classic", dash=True, lx=880, ly=88),
        E("api", "ruleset", ("pack → rules", "пакет → правила")),
        E("ruleset", "pack", "read, rules_hash"),
        E("api", "game", "apply"),
        E("game", "state", "emit · resolve", both=True),
        E("state", "luaglue", ("fx_* ⇄ g.*", "fx_* ⇄ g.*"), both=True),
        E("luaglue", "x_lua", ("compile, call", "compile, call")),
        E("ruleset", "luaglue", "lua::build"),
        E("state", "rng", ("random, hash", "случайность, хэш")),
        E("view", "game", ("Game from a view", "партия из вида")),
        E("bot", "game", ("look-ahead copies", "копии наперёд")),
        E("modes", "state", ("decks, draft,\nmissions", "колоды, драфт,\nмиссии")),
        E("x_brain", "state", ("clone_state\n+ apply", "clone_state\n+ apply")),
    ],
    data=[
        ("Ruleset", ("Built once per `rules_hash` and leaked to `&'static`: limits (hand 10, board 7, mana 10, copies), start (cards, Coin, who draws), fatigue, classes and champions, mechanic names, Arena, missions, cards with their hooks, two Lua interpreters.",
                     "Строится один раз на `rules_hash` и живёт всё время (`&'static`): пределы (рука 10, стол 7, мана 10, копии), начало (карты, Монета, кто тянет), усталость, классы и чемпионы, имена механик, Арена, миссии, карты с хуками, два интерпретатора Lua.")),
        ("Game", ("`rng`, players, entities (`Arc`, copy-on-write), turn, current player, phase (MULLIGAN / PLAY / OVER), the pending choice, the event log, the history, the trigger queue, `script_error`.",
                  "`rng`, игроки, сущности (`Arc`, копирование при записи), ход, текущий игрок, фаза (MULLIGAN / PLAY / OVER), ожидающий выбор, журнал событий, история, очередь триггеров, `script_error`.")),
        (("Views", "Виды"), ("`view` −1 is everything; 0 or 1 is a player's view: the opponent's hand, traps and every deck card become `\"\"`, decks are only a number, the random state is left out.",
                             "`view` −1 — всё; 0 или 1 — вид игрока: рука и ловушки соперника и все карты колод становятся `\"\"`, колоды — только число, состояние ГСЧ не передаётся.")),
    ],
    protocol=[
        (("Ops", "Операции"), ("`ping`, `load_pack {data|path}`, `packs`, `data_hash`, `hooks`, `validate {deck}`, `draft {seed, hero, picks}`, `new {decks, seed | scenario | mission | copy | state}`, `drop`, `act {action}`, `legal`, `snapshot`, `hash`, `bot`, `history`, `dump`, `end_turn_block`. Those with rules take `pack` (a `rules_hash`); without it — the built-in Classic.",
                               "`ping`, `load_pack {data|path}`, `packs`, `data_hash`, `hooks`, `validate {deck}`, `draft {seed, hero, picks}`, `new {decks, seed | scenario | mission | copy | state}`, `drop`, `act {action}`, `legal`, `snapshot`, `hash`, `bot`, `history`, `dump`, `end_turn_block`. Операции с правилами принимают `pack` (`rules_hash`); без него — встроенный Classic.")),
        (("Actions", "Действия"), ("`mulligan {replace}`, `play {entity, target, pos, choice}`, `attack {attacker, defender}`, `hero_power {target}`, `choose {option}`, `end_turn`, `concede` — each with `player`.",
                                   "`mulligan {replace}`, `play {entity, target, pos, choice}`, `attack {attacker, defender}`, `hero_power {target}`, `choose {option}`, `end_turn`, `concede` — у каждого `player`.")),
        (("Replies", "Ответы"), ("`{ok, game, hash, over, winner, turn, current, phase, script_error?}` + `events`; a refused action is `{ok: false, error}` and changes nothing. The full list: `rust/engine/README.md`.",
                                 "`{ok, game, hash, over, winner, turn, current, phase, script_error?}` + `events`; отклонённое действие — `{ok: false, error}`, и ничего не меняется. Полный список: `rust/engine/README.md`.")),
    ],
    flows=["engine-play", "pack-loads"],
))

FLOWS.append(dict(
    id="engine-play", home="engine",
    title=("Inside the engine: one play", "Ход внутри движка"),
    short=("`act` → legality → the play → the card's Lua hook → triggers, auras, deaths until quiet → events and the new hash.",
           "`act` → законность → розыгрыш → Lua-хук карты → триггеры, ауры, смерти до затишья → события и новый хэш."),
    lanes=[L("api", ("JSON API", "JSON API"), "engine", "api.rs"), L("game", ("Turns", "Ходы"), "engine", "game.rs"), L("state", ("State", "Состояние"), "engine", "state.rs"),
           L("glue", ("Lua glue", "Связка с Lua"), "engine", "lua.rs"), L("vm", ("Lua VM", "Lua VM"), "lua", "rust/script")],
    steps=[
        ("api", "api", ("parse, catch panics", "разбор, паника"), ("A panic replies `internal error` and drops that game.", "Паника даёт `internal error`, и эта партия удаляется."),
         [("rust/engine/src/api.rs", "pub fn call(&mut self, req: &str) -> String {")]),
        ("api", "game", "apply(action)", ("An action after the game is over changes nothing.", "Действие после конца партии ничего не меняет."),
         [("rust/engine/src/api.rs", "let res = g.apply(action);")]),
        ("game", "game", ("legal?", "законно?"),
         ("It must equal one of the legal actions (costs, `can_play`, target filters through the read-only Lua); otherwise `ok: false` and nothing changes.",
          "Действие должно совпасть с одним из законных (стоимость, `can_play`, фильтры целей через Lua только для чтения); иначе `ok: false`, и ничего не меняется."),
         [("rust/engine/src/game.rs", "fn legal_play_actions(&self, out: &mut Vec<Act>) {"), ("rust/engine/src/game.rs", "fn can_play(&self, e: Id) -> bool {")]),
        ("game", "game", ("pay, play", "оплата, розыгрыш"),
         ("Mana, cost changes, the card leaves the hand, combo; then a minion, a spell or a weapon.", "Мана, изменения стоимости, карта уходит из руки, комбо; затем существо, заклинание или оружие."),
         [("rust/engine/src/game.rs", "fn do_play(&mut self, e: Id, t: Id, pos: i64, choice: i64) {"), ("rust/engine/src/game.rs", "fn play_minion(")]),
        ("game", "state", ("emit play, summon", "emit play, summon"),
         ("Each event is logged and queues the `on` hooks and traps that listen to it.", "Каждое событие пишется в журнал и ставит в очередь слушающие его хуки `on` и ловушки."),
         [("rust/engine/src/state.rs", "pub fn emit(&mut self, ev: Obj) -> usize {")]),
        ("game", "glue", ("run the card's hook", "хук карты"), ("Battlecry, combo, a Choose One option or the spell, with the source card set.",
                                                       "Боевой клич, комбо, вариант «Выберите» или заклинание, с заданной картой-источником."),
         [("rust/engine/src/game.rs", "fn run_effect(&mut self, e: Id, key: &str"), ("rust/engine/src/game.rs", "self.from(e, |g| g.fx_effect(f, e, t));")]),
        ("glue", "vm", ("call the Lua function", "вызов Lua-функции"), ("The main interpreter is checked out for the call; step and memory budgets apply.",
                                                                 "Основной интерпретатор берётся на время вызова; действуют бюджеты шагов и памяти."),
         [("rust/engine/src/lua.rs", "fn lua<T>(&mut self, f: u32"), ("rust/script/src/vm.rs", "pub fn call<H: Host>(h: &mut H, f: &Value, args: &[Value])")]),
        ("vm", "state", ("g.damage, g.summon…", "g.damage, g.summon…"), ("The hook calls the engine's primitives, which emit more events.", "Хук вызывает примитивы движка, и они порождают новые события."),
         [("rust/engine/src/lua.rs", "fn live(g: &mut Game)")]),
        ("state", "state", ("resolve until quiet", "resolve до затишья"),
         ("The trigger queue (bounded), auras, the death phase (deathrattles queue more), again until nothing changes; a dead hero ends the game.",
          "Очередь триггеров (ограниченная), ауры, фаза смертей (предсмертные хрипы добавляют ещё), снова — пока ничего не меняется; смерть героя заканчивает партию."),
         [("rust/engine/src/state.rs", "pub fn resolve(&mut self) {"), ("rust/engine/src/state.rs", "fn death_phase(&mut self) -> bool {")]),
        ("glue", "state", ("script error → draw", "ошибка скрипта → ничья"), ("A Lua error or a hit limit ends the game as a draw with `script_error`, never a panic.",
                                                                     "Ошибка Lua или превышенный предел заканчивают партию ничьей с `script_error`, но никогда не паникой."),
         [("rust/engine/src/lua.rs", "pub(crate) fn end_by_script_error(&mut self) {")]),
        ("game", "api", ("history, events, hash", "история, события, хэш"),
         ("The events become a history entry; the reply carries the new `state_hash` and the events as this viewer may see them.",
          "События становятся записью истории; ответ несёт новый `state_hash` и события так, как их может видеть этот зритель."),
         [("rust/engine/src/api.rs", "r[\"events\"] = events_for(g, &res.events(), view);"), ("rust/engine/src/state.rs", "pub fn state_hash(&self) -> String {")]),
    ],
))


# --- the Lua interpreter (rust/script) ---------------------------------------------------------------

COMPS.append(dict(
    id="lua", name=("Lua interpreter", "Интерпретатор Lua"), sub="rust/script", layer="core", x=40, y=470,
    short=("Its own interpreter of a Lua 5.4 subset, with no dependencies: integers only, a sandbox with no files, time, randomness or code loading, "
           "and hard limits on steps, depth, tables, strings and memory. It runs the pack's card scripts the same way everywhere.",
           "Собственный интерпретатор подмножества Lua 5.4 без зависимостей: только целые числа, песочница без файлов, времени, случайности и загрузки кода, "
           "жёсткие пределы на шаги, глубину, таблицы, строки и память. Он исполняет скрипты карт пакета одинаково везде."),
    text=("Why its own: the same hashes on every platform, a WebAssembly build without emscripten, hard limits and a small language that can be checked. "
          "The engine keeps **two** interpreters per ruleset: the main one, borrowed by a game for each hook call and shared with its look-ahead copies "
          "(so scripts keep no state of their own — the modules are frozen), and a read-only one whose `g` has only the queries, for target filters, "
          "`can_play` and cost changes. The language as a pack author sees it: [Card scripts in Lua](lua.html).",
          "Почему свой: одинаковые хэши на всех платформах, сборка в WebAssembly без emscripten, жёсткие пределы и маленький проверяемый язык. "
          "У движка **два** интерпретатора на набор правил: основной, который партия берёт на время каждого вызова хука и делит со своими копиями "
          "для просмотра вперёд (поэтому у скриптов нет своего состояния — модули заморожены), и только для чтения, где в `g` есть лишь запросы, — "
          "для фильтров целей, `can_play` и изменений стоимости. Язык глазами автора пакета: [Скрипты карт на Lua](lua.html)."),
    parts=[
        X("packs", 0, 0),
        P("glue", ("The engine's glue", "Связка в движке"), 1, 0, sub="rust/engine/src/lua.rs",
          text=("Compiles the pack's scripts, loads `lib.lua` as the global `lib`, freezes the modules, registers `g` for both interpreters.",
                "Компилирует скрипты пакета, загружает `lib.lua` как глобальную `lib`, замораживает модули, регистрирует `g` для обоих интерпретаторов."),
          files=[("rust/engine/src/lua.rs", "let g_main = main.lib(\"g\", &[QUERIES_MAIN, ACTIONS].concat());"), ("rust/engine/src/lua.rs", "let g_probe = probe.vm.lib(\"g\", QUERIES_PROBE);"),
                 ("rust/engine/src/lua.rs", "fn freeze<H>(vm: &mut Vm<H>, t: &L, depth: u32) {")]),
        X("engine", 2, 0),
        P("lex", ("Lexer", "Лексер"), 0, 1, sub="lex.rs", text=("Source text to tokens with line numbers.", "Текст в токены с номерами строк."),
          files=[("rust/script/src/lex.rs", "pub fn tokenize(src: &[u8])")]),
        P("parse", ("Parser", "Парсер"), 1, 1, sub="parse.rs",
          text=("Tokens to a tree with resolved slots (at most 200 levels deep); an unknown global is a compile error.",
                "Токены в дерево с готовыми слотами (не глубже 200 уровней); неизвестная глобальная — ошибка компиляции."),
          files=[("rust/script/src/parse.rs", "pub fn parse(file: &str, src: &[u8])")]),
        P("vm", "Vm", 2, 1, sub="vm.rs",
          text=("Heap, tables (read-only flag), garbage collector, the tree-walking executor with step and memory budgets; `load`, `call`, `call_path`; a `Vm` clones whole.",
                "Куча, таблицы (флаг только для чтения), сборщик мусора, исполнитель дерева с бюджетами шагов и памяти; `load`, `call`, `call_path`; `Vm` копируется целиком."),
          files=[("rust/script/src/vm.rs", "pub struct Vm<H> {"), ("rust/script/src/vm.rs", "pub fn load<H: Host>(h: &mut H, name: &str, chunk: &Chunk)"), ("rust/script/src/vm.rs", "pub(crate) fn step(&mut self, n: u64)")]),
        P("limits", ("Values, limits, host", "Значения, пределы, хозяин"), 0, 2, sub="lib.rs",
          text=("`Value` (nil, bool, i64, string, table, function), `Limits` (200 000 steps, depth 200, 10 000 entries, 64 KB strings, 16 MB per call), `Error` with file, line and trace, the `Host` trait.",
                "`Value` (nil, bool, i64, строка, таблица, функция), `Limits` (200 000 шагов, глубина 200, 10 000 записей, строки 64 КБ, 16 МБ на вызов), `Error` с файлом, строкой и трассировкой, трейт `Host`."),
          files=[("rust/script/src/lib.rs", "pub struct Limits {"), ("rust/script/src/lib.rs", "pub trait Host: Sized + 'static {"), ("rust/script/src/lib.rs", "pub fn compile_bytes(file: &str, src: &[u8])")]),
        P("stdlib", ("Standard library", "Стандартная библиотека"), 1, 2, sub="stdlib.rs",
          text=("`ipairs pairs next type tostring tonumber select error assert pcall`, `table.*`, `string.*`, `math.*`, `list.filter/map/count/any/sort_by`.",
                "`ipairs pairs next type tostring tonumber select error assert pcall`, `table.*`, `string.*`, `math.*`, `list.filter/map/count/any/sort_by`."),
          files=[("rust/script/src/stdlib.rs", "pub(crate) fn install<H: Host>(vm: &mut Vm<H>) {")]),
        P("tests", ("Tests", "Тесты"), 2, 2, sub="rust/script/tests",
          text=("54 tests: semantics, limits, sandbox escapes (`load`, `_G`, metatables, huge `string.rep`, endless loops), deep recursion, the host, fuzzing.",
                "54 теста: семантика, пределы, попытки выйти из песочницы (`load`, `_G`, метатаблицы, огромный `string.rep`, бесконечные циклы), глубокая рекурсия, хозяин, фаззинг."),
          files=["rust/script/tests/sandbox.rs", "rust/script/tests/limits.rs"]),
    ],
    arrows=[
        E("x_packs", "glue", "scripts/*.lua"),
        E("x_engine", "glue", ("hooks ⇄ g.*", "хуки ⇄ g.*"), both=True),
        E("glue", "parse", "compile_bytes"),
        E("parse", "lex", "tokenize"),
        E("glue", "vm", ("load, call, freeze", "load, call, freeze")),
        E("vm", "stdlib", "install"),
        E("vm", "limits", ("budgets", "бюджеты")),
        E("tests", "vm", ("54 tests", "54 теста"), dash=True),
    ],
    data=[
        (("Not in this Lua", "Чего нет в этом Lua"), ("No floats, `/` or `^` (integer division `//`), overflow is an error, no globals of a script's own, `pairs` in insertion order, no metatables, coroutines or `goto`.",
                                                     "Нет дробных чисел, `/` и `^` (целочисленное деление `//`), переполнение — ошибка, нет своих глобальных переменных, `pairs` в порядке вставки, нет метатаблиц, корутин и `goto`.")),
        (("Budgets", "Бюджеты"), ("A step is a statement, a loop turn or a call; built-ins with a loop pay per element. A hit limit is not caught by `pcall`: the hook fails whole.",
                                  "Шаг — оператор, виток цикла или вызов; встроенные функции с циклом платят за каждый элемент. Превышение предела `pcall` не ловит: хук падает целиком.")),
    ],
    flows=["script-run"],
))

FLOWS.append(dict(
    id="script-run", home="lua",
    title=("A card script runs", "Работа скрипта карты"),
    short=("From a pack's `scripts/*.lua` to a hook call in a game: compile once at pack load, then each call under the budgets.",
           "От `scripts/*.lua` пакета до вызова хука в партии: компиляция один раз при загрузке пакета, затем каждый вызов в пределах бюджетов."),
    lanes=[L("ruleset", "Ruleset", "engine", "ruleset.rs"), L("glue", ("Lua glue", "Связка"), "engine", "lua.rs"), L("comp", ("Compiler", "Компилятор"), "lua", "lex · parse"),
           L("vm", "Vm", "lua", "vm.rs"), L("game", "Game", "engine", "state.rs")],
    steps=[
        ("ruleset", "glue", "lua::build(scripts)", ("At pack load, once per `rules_hash`.", "При загрузке пакета, один раз на `rules_hash`."),
         [("rust/engine/src/ruleset.rs", "let (lua, hooks) = crate::lua::build(&rs, &scripts)?;")]),
        ("glue", "comp", "compile_bytes", ("Every file is compiled; a syntax error names its file and line and refuses the pack.",
                                           "Каждый файл компилируется; синтаксическая ошибка называет файл и строку, и пакет отклоняется."),
         [("rust/script/src/lib.rs", "pub fn compile_bytes(file: &str, src: &[u8])")]),
        ("glue", "vm", ("load into both VMs", "загрузить в оба VM"),
         ("`lib.lua` first as the global `lib`, then each module in the main and the read-only interpreter; each card's table becomes a `HookSet`; the modules are frozen.",
          "Сначала `lib.lua` как глобальная `lib`, затем каждый модуль в основной и в интерпретатор для чтения; таблица каждой карты становится `HookSet`; модули замораживаются."),
         [("rust/script/src/vm.rs", "pub fn load<H: Host>(h: &mut H, name: &str, chunk: &Chunk)"), ("rust/engine/src/lua.rs", "fn hooks(&mut self, t: &L, pt: &L) -> Result<HookSet, String> {")]),
        ("game", "glue", ("fx_effect(f, me, t)", "fx_effect(f, me, t)"), ("In a game a hook runs by its number.", "В партии хук вызывается по номеру."),
         [("rust/engine/src/lua.rs", "fn lua<T>(&mut self, f: u32")]),
        ("glue", "vm", ("check out, call", "взять, вызвать"),
         ("The game borrows the main VM, its entities become Lua tables, the budgets reset for a top-level call.",
          "Партия берёт основной VM, её сущности становятся таблицами Lua, бюджеты обнуляются для вызова верхнего уровня."),
         [("rust/engine/src/lua.rs", "fn checkout(&self, lr: &LuaRules)"), ("rust/engine/src/lua.rs", "fn obj_to_lua<H>(")]),
        ("vm", "game", ("g.* → primitives", "g.* → примитивы"), ("Re-entrant host calls into the engine share the same budget.", "Повторные вызовы хозяина делят тот же бюджет."),
         [("rust/engine/src/lua.rs", "fn live(g: &mut Game)")]),
        ("vm", "vm", ("steps, memory", "шаги, память"), ("Every statement, loop turn and call costs a step; tables and strings are charged.", "Каждый оператор, виток и вызов стоит шаг; таблицы и строки оплачиваются памятью."),
         [("rust/script/src/vm.rs", "pub(crate) fn step(&mut self, n: u64)"), ("rust/script/src/vm.rs", "pub(crate) fn charge(&mut self, bytes: u64)")]),
        ("glue", "game", ("write back or draw", "записать или ничья"), ("Changes go back into the game; an error or a limit ends it as a draw.", "Изменения записываются в партию; ошибка или предел — ничья."),
         [("rust/engine/src/lua.rs", "fn write_back(g: &mut Game"), ("rust/engine/src/lua.rs", "pub(crate) fn end_by_script_error(&mut self) {")]),
    ],
))


# --- the engine bridges (game/rules.gd, rust/godot, rust/wasm, web/rules.js) --------------------------

COMPS.append(dict(
    id="bridge", name=("Engine bridge", "Мост к движку"), sub="GDExtension · WebAssembly", layer="core", x=370, y=320,
    short=("How Godot reaches the Rust crates: a GDExtension library on Windows, macOS, Linux and Android, `rules.wasm` through `web/rules.js` in the browser. "
           "In GDScript it is one call, `Rules.request(dict) → dict`, plus a separate door for the bot.",
           "Как Godot достаёт до крейтов на Rust: библиотека GDExtension на Windows, macOS, Linux и Android, `rules.wasm` через `web/rules.js` в браузере. "
           "В GDScript это один вызов `Rules.request(словарь) → словарь` и отдельный вход для бота."),
    text=("There is no fallback engine: without the library the game says the rules engine is missing. `Rules` is also the only place the engine learns "
          "about the active pack: on the first request that needs rules it sends the pack (re-zipped without pictures, sounds and music) as `load_pack`, "
          "then adds `pack` to every `new`, `validate`, `draft`, `hooks`, `data_hash`. A local match — training, the tutorial, the debug table, code play — "
          "is just this path: the game's own engine owns the game.",
          "Запасного движка нет: без библиотеки игра сообщает, что движка правил нет. `Rules` — ещё и единственное место, где движок узнаёт об активном пакете: "
          "при первом запросе с правилами он отправляет пакет (переупакованный без картинок, звуков и музыки) как `load_pack`, а затем добавляет `pack` к каждому "
          "`new`, `validate`, `draft`, `hooks`, `data_hash`. Локальная партия — тренировка, обучение, отладочный стол, игра по коду — это и есть этот путь: партией владеет свой движок."),
    parts=[
        X("client", 1, 0),
        P("rules", "Rules", 0, 1, sub="game/rules.gd",
          text=("`missing()` picks the native class or `window.ClassicRules`; `request` JSON-encodes, calls, decodes and turns whole floats back into ints; `can_play` / `load_pack` give the engine the active pack.",
                "`missing()` выбирает нативный класс или `window.ClassicRules`; `request` кодирует в JSON, вызывает, раскодирует и возвращает целым числам тип int; `can_play` / `load_pack` отдают движку активный пакет."),
          files=[("game/rules.gd", "static func missing() -> String:"), ("game/rules.gd", "static func request(req: Dictionary) -> Dictionary:"), ("game/rules.gd", "static func can_play(p: Pack = null) -> String:")]),
        P("botb", "BotBrain", 2, 1, sub="game/bot_brain.gd",
          text=("The bot's door: a request from the bot's own view, started off the main thread and polled.", "Вход для бота: запрос из вида самого бота, запуск вне главного потока и опрос."),
          files=[("game/bot_brain.gd", "static func think_now(")]),
        P("gdext", "GDExtension", 1, 2, sub="rust/godot",
          text=("`RulesEngine.call_json` around one `Engine`; `RulesBrain` with `think_json` (sync) and `start` / `poll` (a std thread).",
                "`RulesEngine.call_json` вокруг одного `Engine`; `RulesBrain` с `think_json` (синхронно) и `start` / `poll` (поток)."),
          files=[("rust/godot/src/lib.rs", "fn call_json(&mut self, request: GString) -> GString {"), ("rust/godot/src/lib.rs", "struct RulesBrain {"),
                 ("rules/classichs.gdextension", "entry_symbol = \"gdext_rust_init\"")]),
        P("rulesjs", "web/rules.js", 0, 2,
          text=("`window.ClassicRules`: fetches `rules.wasm`, `call_json` copies the request into wasm memory and the reply out; a trap marks it broken.",
                "`window.ClassicRules`: качает `rules.wasm`, `call_json` копирует запрос в память wasm и ответ обратно; ловушка помечает его сломанным."),
          files=[("web/rules.js", "api.call_json = function (s) {"), ("web/rules.js", "window.ClassicRules = api;")]),
        P("worker", "Web Worker", 2, 2, sub="web/rules.js",
          text=("A second WebAssembly instance in a Worker, only for the bot's thinking; `think_start` / `think_result`.",
                "Второй экземпляр WebAssembly в Worker, только для раздумий бота; `think_start` / `think_result`."),
          files=[("web/rules.js", "const WORKER = `"), ("web/rules.js", "api.think_start = function (req) {")]),
        P("build", "build_rules.sh", 3, 3, sub="rules/bin",
          text=("Builds the library per platform (macOS universal by `lipo`, Windows, Linux, Android by the NDK) and `rules.wasm` (opt-level s, LTO) into `rules/bin`, which is not in git.",
                "Собирает библиотеку под каждую платформу (macOS universal через `lipo`, Windows, Linux, Android через NDK) и `rules.wasm` (opt-level s, LTO) в `rules/bin`, которой нет в git."),
          files=["tools/build_rules.sh"]),
        P("wasm", "rust/wasm", 0, 3,
          text=("A plain C ABI: `alloc`, `dealloc`, `call`, `out_ptr`, `out_len`, and `think` for the brain.", "Простой C ABI: `alloc`, `dealloc`, `call`, `out_ptr`, `out_len` и `think` для мозга."),
          files=[("rust/wasm/src/lib.rs", "pub unsafe extern \"C\" fn call(p: *const u8, n: usize) {"), ("rust/wasm/src/lib.rs", "pub unsafe extern \"C\" fn think(")]),
        X("engine", 1, 3),
        X("brain", 3, 2),
    ],
    arrows=[
        E("x_client", "rules", "Rules.request"),
        E("x_client", "botb", "start / done"),
        E("rules", "gdext", ("call_json\n(native)", "call_json\n(нативно)")),
        E("rules", "rulesjs", ("JavaScriptBridge\n(web)", "JavaScriptBridge\n(веб)")),
        E("botb", "gdext", ("RulesBrain", "RulesBrain")),
        E("botb", "worker", "think_start"),
        E("rulesjs", "wasm", "call"),
        E("worker", "x_brain", ("think\n(own wasm)", "think\n(свой wasm)")),
        E("gdext", "x_engine", "Engine::call"),
        E("wasm", "x_engine", "Engine::call"),
        E("build", "gdext", "rules/bin", dash=True),
    ],
    data=[
        (("Why two paths", "Почему два пути"), ("GDExtension: 10 000 calls in 2 ms on macOS; wasm through JavaScriptBridge in Chrome: 10 000 calls in 28 ms. The experimental gdext for the web does not load in Godot 4.7.2.",
                                                "GDExtension: 10 000 вызовов за 2 мс на macOS; wasm через JavaScriptBridge в Chrome: 10 000 вызовов за 28 мс. Экспериментальный gdext для веба Godot 4.7.2 не загружает.")),
        (("Packs sent to the engine", "Пакет для движка"), ("Only the manifest, the rules files and the locales, re-zipped; each set of rules is loaded once per run. An old engine without `load_pack` plays only the built-in Classic.",
                                                            "Только манифест, файлы правил и тексты, переупакованные; каждый набор правил грузится один раз за запуск. Старый движок без `load_pack` играет только встроенный Classic.")),
    ],
    protocol=[
        (("GDScript", "GDScript"), ("`Rules.request({op, …}) → {ok, …}`; `PACK_OPS` get `pack` added.", "`Rules.request({op, …}) → {ok, …}`; к `PACK_OPS` добавляется `pack`.")),
        ("WebAssembly", ("`alloc(n)` → copy the UTF-8 request → `call(ptr, n)` → read `out_ptr` / `out_len` → `dealloc`.", "`alloc(n)` → копия запроса в UTF-8 → `call(ptr, n)` → чтение `out_ptr` / `out_len` → `dealloc`.")),
    ],
    flows=["engine-call", "training"],
))

FLOWS.append(dict(
    id="engine-call", home="bridge",
    title=("An engine call from Godot", "Вызов движка из Godot"),
    short=("`Rules.request` on the desktop and Android (GDExtension) and in the browser (WebAssembly), with the pack loaded on first use.",
           "`Rules.request` на ПК и Android (GDExtension) и в браузере (WebAssembly), с загрузкой пакета при первом обращении."),
    lanes=[L("caller", "Match · Deck · NetSession", "client"), L("rules", "Rules", "bridge", "game/rules.gd"), L("native", "GDExtension", "bridge", "rust/godot"),
           L("web", "rules.js + wasm", "bridge", "web · rust/wasm"), L("engine", ("Rules engine", "Движок"), "engine", "api.rs")],
    steps=[
        ("caller", "rules", "request({op, …})", ("For example `act` from `Match._apply`.", "Например, `act` из `Match._apply`."),
         [("game/match.gd", "func _apply(action: Variant) -> Dictionary:")]),
        ("rules", "rules", ("which engine?", "какой движок?"),
         ("The `RulesEngine` class if it exists; in the browser `ClassicRules` once it is ready; otherwise the reason it is missing.",
          "Класс `RulesEngine`, если он есть; в браузере — `ClassicRules`, когда он готов; иначе — причина, почему движка нет."),
         [("game/rules.gd", "static func missing() -> String:")]),
        ("rules", "engine", ("load_pack, once", "load_pack, один раз"),
         ("An op with rules and no pack yet: the active pack is re-zipped without media and loaded; its `rules_hash` is added from then on.",
          "Операция с правилами, а пакет ещё не загружен: активный пакет переупаковывается без медиа и загружается; дальше добавляется его `rules_hash`."),
         [("game/rules.gd", "static func load_pack(p: Pack) -> String:"), ("game/rules.gd", "static func _rules_zip(p: Pack) -> PackedByteArray:")]),
        ("rules", "native", ("call_json (native)", "call_json (нативно)"), ("Windows, macOS, Linux, Android.", "Windows, macOS, Linux, Android."),
         [("rust/godot/src/lib.rs", "fn call_json(&mut self, request: GString) -> GString {")]),
        ("rules", "web", ("call_json (web)", "call_json (веб)"), ("The request is copied into wasm memory, `call` runs, the reply is read back.", "Запрос копируется в память wasm, выполняется `call`, ответ читается обратно."),
         [("web/rules.js", "api.call_json = function (s) {"), ("rust/wasm/src/lib.rs", "pub unsafe extern \"C\" fn call(p: *const u8, n: usize) {")]),
        ("native", "engine", "Engine::call", ("Both paths end in the same `Engine::call`: the reply is a JSON string.", "Оба пути заканчиваются одним и тем же `Engine::call`: ответ — строка JSON."), [("rust/engine/src/api.rs", "pub fn handle(&mut self, req: &Value) -> Value {")]),
        ("engine", "rules", ("JSON reply", "JSON-ответ"), ("Parsed back; whole floats become ints, because entity ids are dictionary keys.",
                                                       "Разбирается обратно; целые числа снова становятся int, ведь id сущностей — ключи словарей."),
         [("game/rules.gd", "static func ints(v: Variant) -> Variant:")]),
    ],
))


# --- game packs (.cardpack) --------------------------------------------------------------------------

COMPS.append(dict(
    id="packs", name=("Game packs", "Пакеты игр"), sub=".cardpack · packs/", layer="content", x=40, y=170,
    short=("Everything that makes a game a game, in one zip file: rules, cards and their Lua scripts, mechanic names, texts in every language, "
           "art, sound and music sets, the menu look and music, deck templates, the tutorial. Built in: Classic 2014 and Neonfall.",
           "Всё, что делает игру игрой, в одном zip-файле: правила, карты и их скрипты на Lua, имена механик, тексты на всех языках, наборы арта, "
           "звуков и музыки, вид и музыка меню, шаблоны колод, обучение. Встроены «Классика 2014» и Neonfall."),
    text=("The engine knows only general mechanics (its vocabulary — `docs/packs/schema/keywords.json`: GUARD, HASTE, BARRIER…); a pack names them its own way "
          "(Classic: Taunt; Neonfall: Firewall) and fills them with cards. **Two hashes:** `rules_hash` covers only what changes the game (rules, cards without "
          "looks, missions, scripts; JSON canonicalised) — games, servers and code-play peers compare it; `content_hash` covers every file — caches, downloads "
          "and transfers use it. So two packs with the same rules and different art play the same game. How to make one: [Make your own game](packs.html).",
          "Движок знает только общие механики (его словарь — `docs/packs/schema/keywords.json`: GUARD, HASTE, BARRIER…); пакет называет их по-своему "
          "(у Classic — Провокация, у Neonfall — Firewall) и наполняет картами. **Два хэша:** `rules_hash` — только то, что меняет игру (правила, карты без "
          "оформления, миссии, скрипты; JSON в каноническом виде), по нему сверяются партии, серверы и соперники по коду; `content_hash` — все файлы, по нему "
          "кэш, скачивание и передача. Поэтому два пакета с одними правилами и разным артом играют одну игру. Как сделать свой: [Своя игра](packs.html)."),
    parts=[
        P("source", ("Pack source", "Исходник пакета"), 0, 0, sub="packs/classic · packs/neon",
          text=("A folder; Classic's `recipe.json` also pulls cards, texts, layouts, art and sound from `data/`, `art/`, `audio/`.",
                "Папка; `recipe.json` Classic ещё берёт карты, тексты, раскладки, арт и звук из `data/`, `art/`, `audio/`."),
          files=["packs/classic/recipe.json", "packs/neon/manifest.json"]),
        P("packpy", "tools/pack.py", 1, 0, sub="build · check · info · hash",
          text=("Runs the recipe, checks schemas and every cross reference, writes the hashes and a deterministic zip — or refuses.",
                "Выполняет рецепт, проверяет схемы и все перекрёстные ссылки, записывает хэши и детерминированный zip — или отказывает."),
          files=[("tools/pack.py", "def build(src, out=None, art_sets=(), sound_sets=(), voice=None):"), ("tools/pack.py", "def check_files(files):"), ("tools/pack.py", "def write_pack(files, out):")]),
        P("file", ".cardpack", 2, 0, sub="zip",
          text=("Up to 128 MB, 256 MB unpacked, 10 000 files; no zip bombs, links or encryption; only the format's folders.",
                "До 128 МБ, 256 МБ в распакованном виде, 10 000 файлов; без zip-бомб, ссылок и шифрования; только папки формата."),
          files=["docs/packs/format.md"]),
        P("packsgd", ("Packs in the client", "Пакеты в клиенте"), 3, 0, sub="game/packs.gd · pack.gd",
          text=("The built-in `res://packs` and the player's `user://packs`; the active pack; install with checks; the shell switch; a pack read straight from its zip.",
                "Встроенные `res://packs` и пакеты игрока `user://packs`; активный пакет; установка с проверками; переключатель оболочки; пакет читается прямо из zip."),
          files=[("game/packs.gd", "static func _scan() -> void:"), ("game/packs.gd", "static func install(bytes: PackedByteArray"), ("game/pack.gd", "func problems() -> Array:")]),
        X("client", 4, 0),
        P("rulesfiles", ("Rules", "Правила"), 0, 1, sub="rules.json · cards.json · scripts/ · missions/",
          text=("Limits, start, fatigue, timers, classes and champions, mechanics, modes, the ranked ladder; the cards; their Lua; tutorial missions.",
                "Пределы, начало партии, усталость, таймеры, классы и чемпионы, механики, режимы, лестница рангов; карты; их Lua; миссии обучения."),
          files=["docs/packs/rules.md", "docs/packs/cards.md"]),
        P("texts", ("Texts", "Тексты"), 1, 1, sub="locales/ · layout/",
          text=("Names, card texts, mechanics, classes, decks and tutorial texts per language; Classic's hand-made card layouts.",
                "Имена, тексты карт, механики, классы, колоды и тексты обучения по языкам; ручные раскладки карт Classic."),
          files=["packs/neon/locales/en.json"]),
        P("look", ("Look", "Оформление"), 2, 1, sub="ui/ · ui/theme.json · fonts",
          text=("Menu, board, collection and result pictures, the logo and card back, colours, fonts, menu shade and particles.",
                "Картинки меню, стола, коллекции и результата, логотип и рубашка, цвета, шрифты, затемнение и частицы меню."),
          files=["packs/neon/ui/theme.json"]),
        X("bridge", 3, 1),
        P("media", ("Art, sound, music", "Арт, звук, музыка"), 0, 2, sub="art/ sounds/ music/ <set>",
          text=("Named sets; the player picks one per game (per server when playing through one).", "Именованные наборы; игрок выбирает их для каждой игры (через сервер — для каждого сервера)."),
          files=["packs/neon/manifest.json"]),
        P("decktut", ("Templates, tutorial", "Шаблоны, обучение"), 1, 2, sub="decks/ · tutorial.json",
          text=("Deck templates (name, curve, description) to start a deck from; missions, intro pages, unlock rule, hints, scene effects.",
                "Шаблоны колод (имя, кривая, описание), с которых начинают колоду; миссии, вводные страницы, правило открытия, подсказки, эффекты сцены."),
          files=["packs/classic/tutorial.json", ("tools/pack.py", "def check_tutorial(")]),
        P("hashes", ("Two hashes", "Два хэша"), 2, 2, sub="rules_hash · content_hash",
          text=("Computed the same way by `pack.py`, the client and the engine (a test compares them).", "Считаются одинаково в `pack.py`, в клиенте и в движке (тест их сверяет)."),
          files=[("tools/pack.py", "def rules_hash(files):"), ("game/pack.gd", "func computed_rules_hash() -> String:"), ("rust/engine/src/pack.rs", "pub fn rules_hash(files: &Files) -> Result<String, String> {")]),
        X("engine", 3, 2),
    ],
    arrows=[
        E("source", "packpy", "build", dash=True),
        E("packpy", "file", "write_pack", dash=True),
        E("file", "packsgd", ("install, scan", "установка, поиск")),
        E("packsgd", "x_client", ("active pack", "активный пакет")),
        E("packsgd", "x_bridge", ("rules zip", "zip правил")),
        E("x_bridge", "x_engine", "load_pack"),
        E("rulesfiles", "hashes", "rules_hash"),
    ],
    data=[
        (("Built-in packs", "Встроенные пакеты"), ("**Classic 2014** (`classic-2014`): 534 cards, every Classic mechanic in Lua, 6 tutorial missions, 10 deck templates, the 2014 ladder. "
                                                   "**Neonfall** (`neon`): a rainy cyberpunk game, 3 champions, 60 cards and 7 tokens, its own art, sounds, synthwave, theme and fonts — the default game.",
                                                   "**«Классика 2014»** (`classic-2014`): 534 карты, все механики Classic на Lua, 6 миссий обучения, 10 шаблонов колод, лестница 2014 года. "
                                                   "**Neonfall** (`neon`): дождливый киберпанк, 3 чемпиона, 60 карт и 7 жетонов, свой арт, звуки, синтвейв, тема и шрифты — игра по умолчанию.")),
        (("Where packs come from", "Откуда пакеты"), ("Built in (`res://packs`), imported from a file, downloaded from a server, received from a code-play peer; on a server — uploaded by players or the admin, or bundled (`--packs-dir`).",
                                                     "Встроенные (`res://packs`), импорт из файла, скачанные с сервера, полученные от соперника по коду; на сервере — загруженные игроками или админом либо встроенные (`--packs-dir`).")),
    ],
    protocol=[
        ("manifest.json", ("`format`, `id`, `version`, names, languages, art / sound / music sets, card back, logo, `redistributable`, `fx`, `rules_hash`. The reference: [Pack format](../ref/format.html).",
                           "`format`, `id`, `version`, имена, языки, наборы арта, звуков и музыки, рубашка, логотип, `redistributable`, `fx`, `rules_hash`. Справочник: [Pack format](../ref/format.html).")),
    ],
    flows=["pack-loads", "pack-build", "pack-transfer", "pack-upload"],
))

FLOWS.append(dict(
    id="pack-loads", home="packs",
    title=("A pack loads", "Загрузка пакета"),
    short=("File → checks → active pack → the engine reads the zip with limits → `rules_hash` → rules → Lua build → hooks.",
           "Файл → проверки → активный пакет → движок читает zip с пределами → `rules_hash` → правила → сборка Lua → хуки."),
    lanes=[L("packs", "Packs · Pack", "packs", "game/packs.gd"), L("rules", "Rules", "bridge", "game/rules.gd"), L("api", ("Engine API", "API движка"), "engine", "api.rs"),
           L("pack", ("Pack reading", "Чтение"), "engine", "pack.rs"), L("ruleset", "Ruleset", "engine", "ruleset.rs"), L("lua", ("Lua", "Lua"), "lua", "lua.rs")],
    steps=[
        ("packs", "packs", ("scan · install", "поиск · установка"),
         ("Built-in packs and `user://packs` by its index; a new file is checked (paths, limits, the manifest, `rules_hash`) and stored as `<content_hash>.cardpack`.",
          "Встроенные пакеты и `user://packs` по индексу; новый файл проверяется (пути, пределы, манифест, `rules_hash`) и сохраняется как `<content_hash>.cardpack`."),
         [("game/packs.gd", "static func _scan() -> void:"), ("game/packs.gd", "static func install(bytes: PackedByteArray"), ("game/pack.gd", "func problems() -> Array:")]),
        ("packs", "rules", ("active → pack_changed", "активный → pack_changed"), ("Entering a game resets every cache, the engine's rules included.", "Вход в игру сбрасывает все кэши, в том числе правила движка."),
         [("game/packs.gd", "static func active() -> Pack:"), ("game/packs.gd", "Rules.pack_changed()")]),
        ("rules", "api", ("load_pack {data}", "load_pack {data}"),
         ("On the first request with rules: the manifest, rules files and locales as base64.", "При первом запросе с правилами: манифест, файлы правил и тексты в base64."),
         [("game/rules.gd", "static func can_play(p: Pack = null) -> String:"), ("rust/engine/src/api.rs", "fn load_pack(&mut self, req: &Value) -> Value {")]),
        ("api", "pack", ("read_zip with limits", "read_zip с пределами"),
         ("The central directory with every limit (size, count, paths, no duplicates, encryption, links or zip64, ratio); only the manifest and rules files are inflated.",
          "Центральный каталог со всеми пределами (размер, число, пути, без повторов, шифрования, ссылок и zip64, степень сжатия); распаковываются только манифест и файлы правил."),
         [("rust/engine/src/pack.rs", "pub fn read_zip(b: &[u8]) -> Result<Files, String> {")]),
        ("api", "ruleset", ("load: known hash?", "load: хэш известен?"), ("`rules_hash` first; a known one is the same ruleset, at once.", "Сначала `rules_hash`; известный — тот же набор правил, сразу."),
         [("rust/engine/src/ruleset.rs", "pub fn load(files: &Files) -> Result<&'static Ruleset, String> {"), ("rust/engine/src/pack.rs", "pub fn rules_hash(files: &Files) -> Result<String, String> {")]),
        ("ruleset", "ruleset", "from_files",
         ("Strict JSON: the manifest (format 1), `rules.json` → mechanic names → cards → missions → limits, classes, Arena.",
          "Строгий JSON: манифест (format 1), `rules.json` → имена механик → карты → миссии → пределы, классы, Арена."),
         [("rust/engine/src/ruleset.rs", "pub fn from_files(files: &Files, builtin: bool)")]),
        ("ruleset", "lua", "lua::build", ("Every script compiled, each card's table turned into a `HookSet`.", "Каждый скрипт компилируется, таблица каждой карты становится `HookSet`."),
         [("rust/engine/src/lua.rs", "pub(crate) fn build(rs: &Ruleset, scripts:")]),
        ("ruleset", "api", ("hooks on cards, cached", "хуки на картах, в кэш"), ("Hooks copied onto the cards, neighbour-aware cards noted; the ruleset joins the cache.",
                                                                        "Хуки копируются на карты, отмечаются карты, которым важны соседи; набор правил попадает в кэш."),
         [("rust/engine/src/ruleset.rs", "rs.neighbours = neighbours(&rs.cards, &scripts);")]),
        ("api", "rules", "{ok, pack: rules_hash}", ("From now on `new {pack}` plays this game.", "Дальше `new {pack}` играет эту игру."),
         [("rust/engine/src/api.rs", "fn ruleset(&self, req: &Value)")]),
    ],
))

FLOWS.append(dict(
    id="pack-build", home="packs",
    title=("A pack is built", "Сборка пакета"),
    short=("`tools/pack.py build`: the source folder and its recipe → checks → hashes → a byte-for-byte reproducible zip.",
           "`tools/pack.py build`: папка-исходник и её рецепт → проверки → хэши → zip, одинаковый байт в байт."),
    lanes=[L("dev", ("Pack author", "Автор пакета"), "tools"), L("packpy", "pack.py", "packs", "tools/pack.py"), L("schema", ("Schemas", "Схемы"), "packs", "docs/packs/schema"),
           L("zip", ".cardpack", "packs")],
    steps=[
        ("dev", "packpy", "build <src> -o <out>", ("`tools/build_packs.sh` does it for Classic and Neonfall.", "`tools/build_packs.sh` делает это для Classic и Neonfall."),
         [("tools/pack.py", "def main(argv=None):"), "tools/build_packs.sh"]),
        ("packpy", "packpy", ("recipe steps", "шаги рецепта"),
         ("`hsjson`, `keywords`, `voice`, `translate`, `rank_names`, `copy`; the source's own texts go over the generated ones.",
          "`hsjson`, `keywords`, `voice`, `translate`, `rank_names`, `copy`; собственные тексты исходника ложатся поверх сгенерированных."),
         [("tools/pack.py", "STEPS = {"), ("tools/pack.py", "def step_hsjson(")]),
        ("packpy", "packpy", ("fx, rules_hash", "fx, rules_hash"), ("Every effect the cards name, then the rules hash, into the manifest.", "Все эффекты, которые называют карты, затем хэш правил — в манифест."),
         [("tools/pack.py", "b.manifest[\"rules_hash\"] = rules_hash(b.files)")]),
        ("packpy", "schema", ("check every file", "проверить каждый файл"),
         ("Schemas, then cross references: classes, rarities, mechanics in the engine's vocabulary, powers, scripts, sets, locales, legal templates, missions, theme, tutorial.",
          "Схемы, затем перекрёстные ссылки: классы, редкости, механики в словаре движка, силы, скрипты, наборы, тексты, законность шаблонов, миссии, тема, обучение."),
         [("tools/pack.py", "def check_files(files):")]),
        ("packpy", "zip", ("write — only without errors", "записать — только без ошибок"),
         ("Sorted paths, time 1980-01-01, pictures and audio stored, the rest deflated at level 9: the same input gives the same bytes.",
          "Пути по порядку, время 1980-01-01, картинки и звук без сжатия, остальное deflate 9: одинаковый вход — одинаковые байты."),
         [("tools/pack.py", "def write_pack(files, out):")]),
    ],
))

# --- code play over WebRTC (net/) ------------------------------------------------------------------

COMPS.append(dict(
    id="codeplay", name=("Code play (WebRTC)", "Игра по коду (WebRTC)"), sub="net/ · lockstep", layer="net", x=700, y=170,
    short=("Online without a server: two clients join over WebRTC by swapping an invite and an answer code through any messenger. "
           "Each runs the same game in its own engine (lockstep) and both compare the state hash after every move.",
           "Сетевая игра без сервера: два клиента соединяются по WebRTC, обменявшись кодом приглашения и кодом ответа через любой мессенджер. "
           "Каждый ведёт ту же партию в своём движке (lockstep), и после каждого хода оба сверяют хэш состояния."),
    text=("**On every platform.** The browser has WebRTC built in; the desktop and Android builds get the official `webrtc-native` plugin "
          "(1.2.2, pinned by its SHA-256, fetched by `tools/fetch_webrtc.sh`). The Code play item is in a game's menu in Direct mode.\n\n"
          "Lockstep needs both sides to know both decks — fine between friends, and the table shows only what each may see. "
          "Where fairness matters there is the server. Any mismatch — an illegal move, another hash, a skipped number — ends the game for both: "
          "\"Something does not add up: the two games differ. Nobody is banned.\"",
          "**На всех платформах.** В браузере WebRTC встроен; сборки для ПК и Android получают официальный плагин `webrtc-native` "
          "(1.2.2, закреплён по SHA-256, его скачивает `tools/fetch_webrtc.sh`). Пункт «Игра по коду» — в меню игры в режиме без сервера.\n\n"
          "Lockstep требует, чтобы обе стороны знали обе колоды — для игры с друзьями это допустимо, а стол показывает каждому только положенное. "
          "Где важна честность, есть сервер. Любое расхождение — незаконный ход, другой хэш, пропущенный номер — заканчивает партию у обоих: "
          "«Что-то не сходится: две партии различаются. Никого не банят»."),
    parts=[
        X("client", 0, 0),
        P("online", "OnlineView", 1, 0, sub="ui/online_view.gd",
          text=("Steps: name → game or Arena → deck → host or join; the code boxes; the \"download their game?\" dialog and its progress.",
                "Шаги: имя → игра или Арена → колода → создать или присоединиться; поля кодов; окно «скачать их игру?» и прогресс."),
          files=[("ui/online_view.gd", "const STAGES := [\"name\", \"kind\", \"deck\", \"mode\", \"host\", \"join\"]"), ("ui/online_view.gd", "func host_game() -> void:"),
                 ("ui/online_view.gd", "func join_game(invite: String) -> void:")]),
        P("signal", "SignalCode", 2, 0, sub="net/signal_code.gd",
          text=("A code is base64 of a 4-byte SHA-256 checksum + deflated JSON `{v, type, sdp, ice}`; the type check catches a wrong paste.",
                "Код — base64 от 4 байт контрольной суммы SHA-256 + сжатого JSON `{v, type, sdp, ice}`; проверка типа ловит не тот код."),
          files=[("net/signal_code.gd", "static func pack(type: String, sdp: String, ice: Array) -> String:"), ("net/signal_code.gd", "static func unpack(code: String, expect_type := \"\") -> Dictionary:")]),
        P("arena", ("Arena with a friend", "Арена с другом"), 0, 1, sub="arena_session · channel_transport",
          text=("A draft each, then games to 3 wins over the one connection; every game is a `NetSession` over a `ChannelTransport`. No pack transfer: the same game is required.",
                "Свой драфт у каждого, затем игры до 3 побед по одному соединению; каждая игра — `NetSession` поверх `ChannelTransport`. Без передачи пакета: игра должна совпадать."),
          files=[("net/arena_session.gd", "func _maybe_start() -> void:"), ("net/channel_transport.gd", "parent.send({\"t\": \"game\", \"g\": game, \"m\": msg})")]),
        P("session", "NetSession", 1, 1, sub="net/net_session.gd",
          text=("Protocol 3: hello (version, pack, deck), start (seed, decks), numbered actions with hashes, emotes and intents, the pack transfer, bye with a reason.",
                "Протокол 3: hello (версия, пакет, колода), start (seed, колоды), пронумерованные ходы с хэшами, эмоции и намерения, передача пакета, bye с причиной."),
          files=[("net/net_session.gd", "const PROTOCOL := 3"), ("net/net_session.gd", "func _on_hello(msg: Dictionary) -> void:"), ("net/net_session.gd", "func _on_action(msg: Dictionary) -> void:")]),
        P("rtc", "WebRtcTransport", 2, 1, sub="net/webrtc_transport.gd",
          text=("One ordered reliable channel `game`; all ICE candidates gathered into one code; STUN, and a TURN for hard NATs; the guest re-adds the host's candidates for 5 minutes.",
                "Один упорядоченный надёжный канал `game`; все кандидаты ICE собираются в один код; STUN и TURN для сложных NAT; гость повторяет кандидатов хозяина 5 минут."),
          files=[("net/webrtc_transport.gd", "static func available() -> bool:"), ("net/webrtc_transport.gd", "func host() -> void:"), ("net/webrtc_transport.gd", "func finish(answer: String) -> void:")]),
        X("peer", 3, 1),
        X("bridge", 0, 2),
        P("match", ("Match (lockstep side)", "Match (сторона lockstep)"), 1, 2, sub="game/match.gd",
          text=("`local_action(action, hash)` after each own move; `submit_remote` checks the peer's move is legal here and gives the same hash.",
                "`local_action(action, hash)` после каждого своего хода; `submit_remote` проверяет, что ход соперника законен здесь и даёт тот же хэш."),
          files=[("game/match.gd", "signal local_action(action: Dictionary, state_hash: String)"), ("game/match.gd", "func submit_remote(action: Variant, expected_hash: String) -> String:")]),
        P("plugin", "webrtc-native", 2, 2, sub="tools/fetch_webrtc.sh",
          text=("The native WebRTC library for Windows, macOS, Linux and Android in `addons/webrtc_native/lib` (not in git); the web build uses the browser's.",
                "Нативная библиотека WebRTC для Windows, macOS, Linux и Android в `addons/webrtc_native/lib` (не в git); веб-сборка использует браузерную."),
          files=["tools/fetch_webrtc.sh", ("addons/webrtc_native/webrtc_native.gdextension", "exclude_tags = [")]),
    ],
    arrows=[
        E("x_client", "online", ("Code play", "Игра по коду")),
        E("online", "signal", ("codes", "коды")),
        E("online", "session", "setup"),
        E("online", "arena", ("Arena", "Арена")),
        E("arena", "session", ("a game each", "каждая игра")),
        E("session", "rtc", ("send JSON", "send JSON")),
        E("rtc", "signal", "SDP + ICE", dash=True),
        E("rtc", "x_peer", ("channel \"game\"", "канал «game»"), both=True),
        E("session", "match", ("local_action\n⇄ submit_remote", "local_action\n⇄ submit_remote"), both=True),
        E("match", "x_bridge", ("act (own engine)", "act (свой движок)")),
        E("plugin", "rtc", ("native builds", "нативные сборки"), dash=True),
    ],
    data=[
        (("Who is who", "Кто есть кто"), ("The host is always player 0: it chooses the seed and the pack. Each side keeps a full view of the same game in its own engine.",
                                         "Хозяин — всегда игрок 0: он выбирает seed и пакет. У каждой стороны полный вид одной и той же партии в своём движке.")),
        (("Packs", "Пакеты"), ("Peers compare `rules_hash`: the same rules play, each with its own art and texts. Otherwise the guest switches to its own pack with those rules or gets the host's file over the channel.",
                               "Стороны сверяют `rules_hash`: одинаковые правила играют, у каждого свой арт и тексты. Иначе гость переключается на свой пакет с теми же правилами или получает файл хозяина по каналу.")),
    ],
    protocol=[
        ("NetSession", ("`hello {protocol: 3, version, data, name, hero, cards, pack}`, `start {seed, decks}`, `action {n, action, hash}` (no hash for mulligan and concede — both may send them at once), `emote`, `intent`, `pack_want`, `pack_chunk {n, data, last}`, `pack_ack {n}`, `pack_cancel`, `bye {code}`.",
                        "`hello {protocol: 3, version, data, name, hero, cards, pack}`, `start {seed, decks}`, `action {n, action, hash}` (без хэша для муллигана и сдачи — их обе стороны могут прислать одновременно), `emote`, `intent`, `pack_want`, `pack_chunk {n, data, last}`, `pack_ack {n}`, `pack_cancel`, `bye {code}`.")),
        ("ArenaSession", ("`hello {mode: arena}`, `rules {deck: one | each, keep}`, `status {hero, cards, ready, deciding}`, `game {g, m}`, `concede`, `bye`.",
                          "`hello {mode: arena}`, `rules {deck: one | each, keep}`, `status {hero, cards, ready, deciding}`, `game {g, m}`, `concede`, `bye`.")),
        (("bye codes", "Коды bye"), ("`left`, `connection`, `version`, `desync`, `protocol`, `mode`, `pack`, `declined`, `cancel`.", "`left`, `connection`, `version`, `desync`, `protocol`, `mode`, `pack`, `declined`, `cancel`.")),
    ],
    flows=["code-play", "pack-transfer"],
))

FLOWS.append(dict(
    id="code-play", home="codeplay",
    title=("Code play", "Игра по коду"),
    short=("Invite and answer codes → a WebRTC data channel → hello and start → lockstep with a hash check after every move.",
           "Коды приглашения и ответа → канал данных WebRTC → hello и start → lockstep со сверкой хэша после каждого хода."),
    lanes=[L("host", ("Host", "Хозяин"), "client", "OnlineView · NetSession"), L("hrtc", ("Host WebRTC", "WebRTC хозяина"), "codeplay"),
           L("grtc", ("Guest WebRTC", "WebRTC гостя"), "peer"), L("guest", ("Guest", "Гость"), "peer", "OnlineView · NetSession")],
    steps=[
        ("host", "hrtc", ("host(): offer", "host(): предложение"), ("A peer connection with STUN and TURN, the negotiated channel `game`, an offer.",
                                                              "Соединение со STUN и TURN, заранее согласованный канал `game`, предложение."),
         [("ui/online_view.gd", "func host_game() -> void:"), ("net/webrtc_transport.gd", "func host() -> void:")]),
        ("hrtc", "host", ("invite code", "код приглашения"), ("When gathering is complete (or quiet for 1 s, at most 10 s), the SDP with every candidate becomes one code, sent through any messenger.",
                                                         "Когда сбор кандидатов закончен (или 1 с тишины, максимум 10 с), SDP со всеми кандидатами становится одним кодом, его пересылают через любой мессенджер."),
         [("net/webrtc_transport.gd", "code_ready.emit(SignalCode.pack("), ("net/signal_code.gd", "static func pack(type: String, sdp: String, ice: Array) -> String:")]),
        ("guest", "grtc", ("join(invite): answer", "join(код): ответ"), ("The code is checked (an offer, a valid sum); the answer code goes back the same way.",
                                                                   "Код проверяется (предложение, верная сумма); код ответа уходит обратно тем же путём."),
         [("net/webrtc_transport.gd", "func join(invite: String) -> void:"), ("net/signal_code.gd", "static func unpack(code: String, expect_type := \"\") -> Dictionary:")]),
        ("host", "hrtc", ("finish(answer)", "finish(ответ)"), ("The host pastes the answer code; the remote description is set.", "Хозяин вставляет код ответа; задаётся удалённое описание."), [("net/webrtc_transport.gd", "func finish(answer: String) -> void:")]),
        ("hrtc", "grtc", ("channel open", "канал открыт"), ("The data channel opens on both sides.", "Канал данных открывается с обеих сторон."),
         [("net/webrtc_transport.gd", "opened.emit()")]),
        ("guest", "host", "hello", ("Protocol, game version, the pack (`rules_hash`), the deck; other rules → the pack flow; another version → `bye`.",
                                    "Протокол, версия игры, пакет (`rules_hash`), колода; другие правила — поток передачи пакета; другая версия — `bye`."),
         [("net/net_session.gd", "func say_hello() -> void:"), ("net/net_session.gd", "func _on_hello(msg: Dictionary) -> void:")]),
        ("host", "guest", "start {seed, decks}", ("The host picks the seed; both build the same Match in their own engine and open the table.",
                                                  "Хозяин выбирает seed; оба строят одинаковый Match в своём движке и открывают стол."),
         [("net/net_session.gd", "func _on_start(msg: Dictionary) -> void:"), ("net/net_session.gd", "func _begin(decks: Array, seed: int) -> void:"), ("ui/main.gd", "func start_online_match(")]),
        ("host", "guest", "action {n, action, hash}", ("A move runs in the mover's engine; the new state hash goes with it.", "Ход выполняется в движке того, кто ходит; с ним уходит новый хэш состояния."),
         [("game/match.gd", "local_action.emit(action, state_hash)"), ("net/net_session.gd", "func _on_local_action(action: Dictionary, state_hash: String) -> void:")]),
        ("guest", "guest", ("legal here? same hash?", "законно? тот же хэш?"),
         ("The number must be the next one; the move must be legal in this engine and give the same hash — otherwise `bye {desync}` for both.",
          "Номер должен быть следующим; ход — законным в этом движке и давать тот же хэш, иначе `bye {desync}` у обоих."),
         [("game/match.gd", "func submit_remote(action: Variant, expected_hash: String) -> String:"), ("net/net_session.gd", "const DESYNC :=")]),
    ],
))

FLOWS.append(dict(
    id="pack-transfer", home="codeplay",
    title=("A pack over WebRTC", "Пакет по WebRTC"),
    short=("The host plays a game the guest does not have: it is offered, sent in 32 KB pieces, each acknowledged, checked and installed.",
           "Хозяин играет в игру, которой у гостя нет: её предлагают, шлют кусками по 32 КБ с подтверждением каждого, проверяют и ставят."),
    lanes=[L("host", ("Host", "Хозяин"), "codeplay", "NetSession"), L("guest", ("Guest", "Гость"), "peer", "NetSession"), L("view", "OnlineView", "client"),
           L("packs", "Packs", "packs", "game/packs.gd")],
    steps=[
        ("host", "guest", "hello {pack}", ("id, version, name, `rules_hash`, `content_hash`, size, `redistributable`.", "id, версия, имя, `rules_hash`, `content_hash`, размер, `redistributable`."),
         [("net/net_session.gd", "func say_hello() -> void:")]),
        ("guest", "guest", ("same rules here?", "такие правила есть?"),
         ("A pack of its own with the same rules → switch to it. Not redistributable or too big → a clear refusal. Otherwise offer it.",
          "Свой пакет с теми же правилами — переключиться на него. Нельзя передавать или слишком большой — понятный отказ. Иначе — предложить."),
         [("net/net_session.gd", "func _settle_pack(theirs: Dictionary, hello: Dictionary) -> void:")]),
        ("guest", "view", "pack_offer", ("\"Download it and play? (size)\"", "«Скачать и играть? (размер)»"), [("ui/online_view.gd", "s.pack_offer.connect(func(info: Dictionary):")]),
        ("guest", "host", "pack_want {content_hash}", ("The player agreed; the guest asks for the file by its hash.", "Игрок согласился; гость просит файл по его хэшу."), [("net/net_session.gd", "func accept_pack() -> void:")]),
        ("host", "guest", "pack_chunk {n, data, last}", ("32 KB as base64; the next piece only after `pack_ack {n}`, so the channel never overflows; either side may cancel.",
                                                         "32 КБ в base64; следующий кусок — только после `pack_ack {n}`, так канал не переполняется; любая сторона может отменить."),
         [("net/net_session.gd", "func _send_chunk() -> void:"), ("net/net_session.gd", "func _on_pack_ack(msg: Dictionary) -> void:")]),
        ("guest", "packs", "install(bytes, \"p2p\")", ("The file is checked like any import and its `content_hash` must be the promised one.",
                                                       "Файл проверяется как любой импорт, и его `content_hash` должен совпасть с обещанным."),
         [("net/net_session.gd", "func _on_pack_chunk(msg: Dictionary) -> void:"), ("game/packs.gd", "static func install(bytes: PackedByteArray")]),
        ("guest", "host", ("switch, hello again", "переключиться, снова hello"), ("The pack is active, the engine loads its rules, a legal deck of it is taken; then start and lockstep.",
                                                                               "Пакет активен, движок грузит его правила, берётся законная колода этого пакета; затем start и lockstep."),
         [("net/net_session.gd", "func _switch(p: Pack) -> void:")]),
    ],
))

COMPS.append(dict(
    id="peer", name=("The other player", "Другой игрок"), sub=("another client", "другой клиент"), layer="ext", x=1030, y=320,
    short=("In code play the other side is the same client on another device: its own engine, its own copy of the game, joined only by the data channel.",
           "В игре по коду другая сторона — тот же клиент на другом устройстве: свой движок, своя копия партии, их связывает только канал данных."),
    text=("Nothing stands between the two players: no server, no relay of moves. The codes travel through whatever the players use to talk; "
          "STUN finds each side's public address and, when a direct path is impossible (a symmetric NAT, closed UDP), a TURN server relays the encrypted (DTLS) packets.",
          "Между игроками ничего нет: ни сервера, ни ретранслятора ходов. Коды идут через то, чем игроки общаются; STUN находит публичный адрес каждой стороны, "
          "а если прямой путь невозможен (симметричный NAT, закрытый UDP), TURN-сервер пересылает зашифрованные (DTLS) пакеты."),
    parts=[X("codeplay", 0, 0), P("same", ("The same client", "Тот же клиент"), 1, 0, sub="ui/ game/ net/",
                                 text=("Its OnlineView, NetSession, Match and engine — the mirror of the host's.", "Его OnlineView, NetSession, Match и движок — зеркало хозяйских."),
                                 files=["net/net_session.gd"]),
           X("client", 2, 0)],
    arrows=[E("x_codeplay", "same", "WebRTC", both=True), E("same", "x_client", ("is a", "это"), dash=True)],
    flows=["code-play", "pack-transfer"],
))


# --- the client side of a server (net/server_*.gd, ui/server_*.gd, ui/social.gd) ----------------------

COMPS.append(dict(
    id="serverlink", name=("Server link", "Связь с сервером"), sub="net/server_link.gd", layer="net", x=700, y=320,
    short=("Everything in the game that talks to game servers: a WebSocket per connection (many connections, the same address with different logins allowed), "
           "the server's home and lobby, server games, pack download and upload, decks and per-game settings kept on the server, friends and chats.",
           "Всё в игре, что говорит с игровыми серверами: WebSocket на каждое подключение (их много, один адрес с разными логинами можно), дом и лобби сервера, "
           "серверные партии, скачивание и загрузка пакетов, колоды и настройки игры на сервере, друзья и чаты."),
    text=("In a server game the client is thin: it sends actions and draws the server's `state`; it has no hands, decks or secrets of the opponent at all. "
          "To highlight legal moves it rebuilds a playable game from its own view in its own engine (`new {state}`), whose legal moves match the server's.\n\n"
          "A link probes what its server can do one by one (chats → packs → decks → game settings), so an older server still works without the newer parts. "
          "The server keeps one connection per account: a second login kicks the first (close code 4001), and the kicked client does not log in again by itself.",
          "В серверной партии клиент тонкий: он шлёт действия и рисует `state` сервера; рук, колод и секретов соперника у него нет вообще. Чтобы подсветить законные "
          "ходы, он строит из своего вида играбельную партию в своём движке (`new {state}`), и её законные ходы совпадают с серверными.\n\n"
          "Связь по очереди выясняет, что умеет её сервер (чаты → пакеты → колоды → настройки игр), поэтому старый сервер работает и без новых частей. "
          "Сервер держит одно подключение на аккаунт: второй вход выкидывает первый (код закрытия 4001), и выкинутый клиент сам больше не входит."),
    parts=[
        P("screens", ("Connections, home, lobby", "Подключения, дом, лобби"), 0, 0, sub="connections_view · server_home · server_view",
          text=("The list of connections, the login, the home with the server's games (download, play, upload, art and music), the lobby: casual, ranked, Arena.",
                "Список подключений, вход, дом с играми сервера (скачать, играть, загрузить, арт и музыка), лобби: обычная, рейтинговая, Арена."),
          files=[("ui/connections_view.gd", "func add_server(name: String, url: String) -> bool:"), ("ui/server_view.gd", "func log_in(op: String, user: String, password: String, key := \"\") -> void:"),
                 ("ui/server_view.gd", "func queue(m: String) -> void:")]),
        P("link", "ServerLink", 1, 0, sub="net/server_link.gd",
          text=("One WebSocket, JSON `{t: …}`; the saved login per connection id; routes a game's messages to its session; HTTP for packs.",
                "Один WebSocket, JSON `{t: …}`; сохранённый вход по id подключения; сообщения партии — её сессии; HTTP для пакетов."),
          files=[("net/server_link.gd", "func open_and_resume(address: String, force := false) -> Error:"), ("net/server_link.gd", "func dispatch(msg: Dictionary) -> void:"),
                 ("net/server_link.gd", "func with_pack(msg: Dictionary, p: Pack = null) -> Dictionary:")]),
        X("server", 2, 0),
        P("social", "Social", 0, 1, sub="ui/social.gd",
          text=("Over every screen in server mode: friends with a tab per server, presence, chats, toasts, friendly invites (even into a game you lack: download first).",
                "Поверх любого экрана в режиме сервера: друзья с вкладкой на каждый сервер, присутствие, чаты, всплывающие сообщения, приглашения (даже в игру, которой нет: сначала скачать)."),
          files=[("ui/social.gd", "func send_message(user: String, text: String, srv: Server = null) -> void:"), ("ui/social.gd", "func answer_invite(accept: bool) -> void:")]),
        P("session", "ServerSession", 1, 1, sub="net/server_session.gd",
          text=("One server game: makes its pack active (downloading it if needed), turns `state` into `Match.on_state`, sends `act`, emotes, intents.",
                "Одна серверная партия: делает её пакет активным (скачав при нужде), превращает `state` в `Match.on_state`, шлёт `act`, эмоции, намерения."),
          files=[("net/server_session.gd", "func _use_pack() -> void:"), ("net/server_session.gd", "func on_message(msg: Dictionary) -> void:")]),
        P("http", ("Pack HTTP", "Пакеты по HTTP"), 2, 1, sub="download_pack · upload_pack",
          text=("`GET /packs/<content_hash>.cardpack` and `POST /packs` with the session token; the reply codes become clear messages.",
                "`GET /packs/<content_hash>.cardpack` и `POST /packs` с токеном сессии; коды ответа превращаются в понятные сообщения."),
          files=[("net/server_link.gd", "func download_pack(entry: Dictionary) -> void:"), ("net/server_link.gd", "func upload_pack(p: Pack) -> void:")]),
        P("decks", ("Decks, game settings", "Колоды, настройки игры"), 0, 2, sub="deck_list_view · server_home",
          text=("With a server, the collection edits the server's decks (each change is one `deck_save`); local decks of the same rules can be copied up; art and music per game are kept there too.",
                "Через сервер коллекция правит колоды сервера (каждое изменение — один `deck_save`); локальные колоды с теми же правилами можно скопировать туда; арт и музыка игры тоже хранятся там."),
          files=[("net/server_link.gd", "func decks_of(p: Pack) -> Array[Deck]:"), ("ui/deck_list_view.gd", "func _push(d: Deck) -> void:"), ("net/server_link.gd", "func set_game_setting(p: Pack, kind: String, value: String) -> void:")]),
        X("client", 1, 2),
        X("packs", 3, 1),
    ],
    arrows=[
        E("screens", "link", ("login, queue,\npacks", "вход, очередь,\nпакеты"), both=True),
        E("link", "x_server", ("WebSocket JSON", "WebSocket JSON"), both=True),
        E("link", "social", ("friends, msg,\ninvite", "друзья, msg,\ninvite")),
        E("link", "session", ("match, state,\nact_error", "match, state,\nact_error")),
        E("link", "http", ("token", "токен")),
        E("http", "x_server", "HTTP /packs", both=True),
        E("link", "decks", ("decks,\ngame_settings", "decks,\ngame_settings"), lx=206, ly=231),
        E("session", "x_client", ("Match.on_state", "Match.on_state")),
        E("http", "x_packs", "Packs.install"),
    ],
    data=[
        (("Connections", "Подключения"), ("`Settings.servers` [{id, url, name}]; tokens in `user://server_session.json` by connection id, with the last deck, mode and tab, and a `kicked` mark.",
                                         "`Settings.servers` [{id, url, name}]; токены в `user://server_session.json` по id подключения вместе с последней колодой, режимом и вкладкой и отметкой `kicked`.")),
        ("ServerLink", ("`token`, `me`, `has_chats / has_packs / has_decks / has_settings`, `decks`, `game_settings`, `packs {server, mine}`, the games by id.",
                        "`token`, `me`, `has_chats / has_packs / has_decks / has_settings`, `decks`, `game_settings`, `packs {server, mine}`, партии по id.")),
    ],
    protocol=[
        (("Sends", "Шлёт"), ("`login`, `register`, `resume`, `logout`, `me`, `packs`, `queue {mode, deck, pack}`, `unqueue`, `arena_*`, `act`, `emote`, `intent`, `friends…`, `msg`, `invite`, `decks`, `deck_save`, `deck_delete`, `game_settings_set`.",
                             "`login`, `register`, `resume`, `logout`, `me`, `packs`, `queue {mode, deck, pack}`, `unqueue`, `arena_*`, `act`, `emote`, `intent`, `friends…`, `msg`, `invite`, `decks`, `deck_save`, `deck_delete`, `game_settings_set`.")),
        (("`pack` in a message", "`pack` в сообщении"), ("The `rules_hash` of the active pack when the server has that game; without it — the server's default game.",
                                                        "`rules_hash` активного пакета, если у сервера есть эта игра; без него — игра сервера по умолчанию.")),
    ],
    flows=["server-login", "server-decks", "server-game"],
))

FLOWS.append(dict(
    id="server-login", home="serverlink",
    title=("Log in to a server", "Вход на сервер"),
    short=("Play → Server → the connections → log in → the server's home → one of its games → that game's menu.",
           "«Играть» → «Через сервер» → подключения → вход → дом сервера → одна из его игр → меню этой игры."),
    lanes=[L("main", "Main", "client"), L("views", ("Connections, home", "Подключения, дом"), "serverlink", "ui/"), L("link", "ServerLink", "serverlink"),
           L("ws", ("Server session", "Сессия сервера"), "server", "ws.rs"), L("hub", "Hub", "server", "lib.rs")],
    steps=[
        ("main", "link", ("a link per connection", "связь на подключение"), ("Server mode: every saved login resumes silently.", "Режим сервера: каждый сохранённый вход тихо возобновляется."),
         [("ui/main.gd", "func show_connections() -> ConnectionsView:"), ("ui/main.gd", "func sync_server_links() -> void:")]),
        ("views", "main", ("Open", "Открыть"), ("Logged in → the home; otherwise the login screen.", "Вход есть — дом; иначе экран входа."),
         [("ui/connections_view.gd", "open.pressed.connect(func(): chosen.emit(id))"), ("ui/main.gd", "func open_connection(id: String) -> void:")]),
        ("link", "ws", "login {user, password}", ("Or `register`, or `resume {token}`.", "Или `register`, или `resume {token}`."),
         [("ui/server_view.gd", "func log_in(op: String, user: String, password: String, key := \"\") -> void:")]),
        ("ws", "ws", ("argon2, limits", "argon2, лимиты"),
         ("10 tries a minute per address and per name; an unknown name is checked against a dummy hash so the time is the same; a suspended account stays out.",
          "10 попыток в минуту с адреса и на имя; неизвестное имя проверяется по фиктивному хэшу, чтобы время было одинаковым; замороженный аккаунт не входит."),
         [("server/src/ws.rs", "async fn login(&mut self, user: String, password: String) -> R {"), ("server/src/auth.rs", "pub fn hash_password(pw: &str) -> String {")]),
        ("ws", "hub", "attach", ("One connection per account: an older one gets `kicked` and the close code 4001; a running game comes back.",
                                 "Одно подключение на аккаунт: старое получает `kicked` и код закрытия 4001; идущая партия возвращается."),
         [("server/src/ws.rs", "async fn logged_in(&mut self, id: i64, token: Option<String>, via: &str) -> R {"), ("server/src/lib.rs", "pub fn attach(&mut self, account: i64, name: &str")]),
        ("ws", "link", "auth {ok, token, me}", ("The token is saved per connection, then the link probes chats → packs → decks → game settings.",
                                                "Токен сохраняется для подключения, затем связь проверяет чаты → пакеты → колоды → настройки игр."),
         [("net/server_link.gd", "func dispatch(msg: Dictionary) -> void:")]),
        ("views", "views", ("the server's home", "дом сервера"), ("Name, friends, the server's games and mine: download, play, upload, delete, art and music.",
                                                              "Имя, друзья, игры сервера и мои: скачать, играть, загрузить, удалить, арт и музыка."),
         [("ui/main.gd", "func show_server_home() -> ServerHome:"), ("ui/server_home.gd", "func entries() -> Array:")]),
        ("views", "main", ("Play this game", "Играть в эту игру"),
         ("The pack becomes active with the art and music chosen on the server; the decks are the server's; `me` gives the rank in this game; the game menu opens.",
          "Пакет становится активным с артом и музыкой, выбранными на сервере; колоды — серверные; `me` даёт ранг в этой игре; открывается меню игры."),
         [("ui/main.gd", "func enter_game(p: Pack) -> MainMenu:"), ("ui/main.gd", "DeckStore.link = server_link if server_link.has_decks else null")]),
    ],
))

FLOWS.append(dict(
    id="server-decks", home="serverlink",
    title=("Decks on the server", "Колоды на сервере"),
    short=("Through a server the collection edits the server's decks: each change is one `deck_save`, the reply carries the id.",
           "Через сервер коллекция правит колоды сервера: каждое изменение — один `deck_save`, ответ несёт id."),
    lanes=[L("coll", ("Collection", "Коллекция"), "client", "deck_list_view.gd"), L("store", "DeckStore", "client"), L("link", "ServerLink", "serverlink"),
           L("ws", ("Server session", "Сессия сервера"), "server", "ws.rs"), L("db", ("Database", "База"), "storage", "decks")],
    steps=[
        ("link", "ws", "decks", ("After the packs probe: the whole list, every game.", "После проверки пакетов: весь список, все игры."), [("net/server_link.gd", "\"decks\":")]),
        ("store", "link", ("decks_of(active pack)", "decks_of(активный пакет)"), ("`DeckStore.link` is set while playing through this server.", "`DeckStore.link` задан, пока игра идёт через этот сервер."),
         [("game/deck_store.gd", "static func load_all() -> Array[Deck]:"), ("net/server_link.gd", "func decks_of(p: Pack) -> Array[Deck]:")]),
        ("coll", "ws", "deck_save {id?, deck, pack, ref?}", ("Every change sends the one deck; a new deck carries a `ref` to match the reply.", "Каждое изменение шлёт одну колоду; новая колода несёт `ref`, чтобы узнать ответ."),
         [("ui/deck_list_view.gd", "func _push(d: Deck) -> void:")]),
        ("ws", "db", ("check, upsert", "проверка, запись"), ("An unfinished deck is fine, cards foreign to the game are not; at most 100 per account; 60 changes in 10 s.",
                                                       "Незаконченная колода — можно, чужие для игры карты — нет; не больше 100 на аккаунт; 60 изменений за 10 с."),
         [("server/src/ws.rs", "In::DeckSave { id, deck: d, pack, tag } => {"), ("server/src/ws.rs", "fn deck_to_keep(d: &DeckIn, rules: &GameRules) -> Result<String, E> {")]),
        ("ws", "coll", "deck_saved {deck, ref}", ("The id is stored; a deck changed meanwhile is pushed again.", "id запоминается; колода, изменённая за это время, отправляется снова."),
         [("ui/deck_list_view.gd", "func _on_server(msg: Dictionary) -> void:")]),
        ("coll", "ws", ("copy local decks", "скопировать локальные"), ("Local decks of any pack with the same rules, ticked and sent as new decks.", "Локальные колоды любого пакета с теми же правилами, отмеченные и отправленные как новые."),
         [("ui/deck_list_view.gd", "func copy_local(chosen: Array) -> void:")]),
        ("link", "ws", "game_settings_set {pack, settings}", ("The art and music choice of a game works the same way (short keys and values, merged on the server).",
                                                              "Выбор арта и музыки игры работает так же (короткие ключи и значения, сливаются на сервере)."),
         [("net/server_link.gd", "func set_game_setting(p: Pack, kind: String, value: String) -> void:"), ("server/src/ws.rs", "fn merge_game_settings(")]),
    ],
))


# --- the game server (server/) ----------------------------------------------------------------------

COMPS.append(dict(
    id="server", name=("Game server", "Игровой сервер"), sub="server/ · Rust, axum", layer="server", x=370, y=620,
    short=("An optional server: accounts, friends, presence and chats, casual and ranked games, the Arena — each per game pack. It runs every game "
           "itself in the rules engine with that pack's rules and sends each player only their own view.",
           "Необязательный сервер: аккаунты, друзья, присутствие и чаты, обычные и рейтинговые партии, Арена — всё по пакетам игр. Каждую партию он ведёт "
           "сам в движке правил с правилами её пакета и шлёт каждому игроку только его вид."),
    text=("One process (tokio, axum, SeaORM over SQLite, `object_store`): the WebSocket on `/`, packs over HTTP on `/packs`, the admin panel on `/admin`. "
          "A modified client can neither make an illegal move (the server's engine refuses it; three refusals lose the game) nor see the opponent's hand "
          "(the views are cut by the engine). Packs are checked on upload by a trial game the engine's bot plays. Code play works without it. "
          "Running and the protocol in full: `server/README.md`.",
          "Один процесс (tokio, axum, SeaORM поверх SQLite, `object_store`): WebSocket на `/`, пакеты по HTTP на `/packs`, админка на `/admin`. "
          "Изменённый клиент не может ни сделать незаконный ход (движок сервера его отклоняет; три отказа — поражение), ни увидеть руку соперника "
          "(виды режет движок). Пакеты при загрузке проверяются пробной партией, которую играет бот движка. Игра по коду работает и без сервера. "
          "Запуск и протокол целиком: `server/README.md`."),
    parts=[
        X("serverlink", 0, 0), X("bots", 1, 0),
        P("main", "main.rs · router", 3, 0, sub=("flags, start-up", "флаги, старт"),
          text=("Flags (`--listen`, `--db`, `--store-dir` or `--s3-*`, `--packs-dir`, `--default-pack`, `--trust-proxy`), hash migration, bundled packs, the default game, the background loop, the bots.",
                "Флаги (`--listen`, `--db`, `--store-dir` или `--s3-*`, `--packs-dir`, `--default-pack`, `--trust-proxy`), перенос хэшей, встроенные пакеты, игра по умолчанию, фоновый цикл, боты."),
          files=[("server/src/main.rs", "fn main() {"), ("server/src/lib.rs", "pub fn router(app: AppRef) -> Router {")]),
        X("admin", 2, 0),
        P("ws", ("Player session", "Сессия игрока"), 0, 1, sub="ws.rs",
          text=("One connection: frames up to 64 KB, 300 messages in 10 s, `In` with no unknown fields; before login only register / login / resume / ping.",
                "Одно подключение: кадры до 64 КБ, 300 сообщений за 10 с, `In` без лишних полей; до входа — только register / login / resume / ping."),
          files=[("server/src/ws.rs", "enum In {"), ("server/src/ws.rs", "async fn dispatch(&mut self, msg: In) -> R {"), ("server/src/ws.rs", "pub async fn serve<S, R>(")]),
        P("hub", "Hub", 1, 1, sub="lib.rs",
          text=("Connections (one per account), the queues by (mode, pack), live games, invites, presence; every second the background loop pairs players.",
                "Подключения (одно на аккаунт), очереди по (режим, пакет), идущие партии, приглашения, присутствие; каждую секунду фоновый цикл подбирает пары."),
          files=[("server/src/lib.rs", "pub struct Hub {"), ("server/src/lib.rs", "pub fn pair(&mut self, now: Instant) -> Vec<Pairing> {"), ("server/src/lib.rs", "pub fn spawn_background(app: AppRef) {")]),
        P("game", ("Game task", "Задача партии"), 2, 1, sub="game.rs",
          text=("One game, one tokio task that owns its `Game`: moves, refusals (3 lose), the clock from the pack's timers, returning players, the results.",
                "Одна партия — одна задача tokio, которая владеет своей `Game`: ходы, отказы (3 — поражение), часы по таймерам пакета, возвращение игроков, итоги."),
          files=[("server/src/game.rs", "async fn run(ctx: Ctx, mut g: Game, mut rx: mpsc::UnboundedReceiver<Ev>) {"), ("server/src/game.rs", "pub fn state_msg(")]),
        P("ranked", ("Ranks", "Ранги"), 3, 1, sub="ranked.rs",
          text=("The pack's ladder (or the 2014 one): stars, streaks, floors, Legend, season resets; Elo (K 32); the matchmaking windows.",
                "Лестница пакета (или 2014 года): звёзды, серии, «полы», Легенда, сброс сезона; Elo (K 32); окна подбора."),
          files=[("server/src/ranked.rs", "pub fn elo(a: f64, b: f64, a_won: bool) -> (f64, f64) {"), ("server/src/ranked.rs", "pub fn window(mode: Mode, mmr: bool, waited_secs: u64) -> f64 {")]),
        P("packsrs", ("Packs", "Пакеты"), 0, 2, sub="packs.rs",
          text=("Inspect and trial on upload, the registry, `rules_for` (a cache of up to 48 rule sets), `playable`, `/packs` upload and download, bundled packs.",
                "Проверка и пробная партия при загрузке, реестр, `rules_for` (кэш до 48 наборов правил), `playable`, загрузка и скачивание `/packs`, встроенные пакеты."),
          files=[("server/src/packs.rs", "pub fn trial(p: &Inspected) -> Result<(), String> {"), ("server/src/packs.rs", "pub async fn rules_for(app: &AppRef, rules_hash: &str)"),
                 ("server/src/packs.rs", "pub async fn import_bundled(app: &AppRef, dir: &FsPath) -> usize {")]),
        P("auth", ("Accounts", "Аккаунты"), 1, 2, sub="auth.rs",
          text=("argon2id passwords, 32-byte tokens kept as SHA-256 for 30 days, name and tag rules, rate limits.",
                "Пароли argon2id, токены из 32 байт хранятся как SHA-256 30 дней, правила имён и тегов, лимиты попыток."),
          files=[("server/src/auth.rs", "pub fn new_token() -> (String, Vec<u8>) {"), ("server/src/auth.rs", "pub struct RateLimit {")]),
        X("storage", 0, 3),
        P("events", ("Event log", "Журнал событий"), 1, 3, sub="events.rs",
          text=("Everything is an event (logins, moves with hashes, packs, admin actions…), written in batches, kept 90 days, streamed to the admin's live feed.",
                "Всё — событие (входы, ходы с хэшами, пакеты, действия админов…), пишется пачками, хранится 90 дней, идёт в живую ленту админки."),
          files=[("server/src/events.rs", "pub struct Log {"), ("server/src/events.rs", "async fn writer(")]),
        X("engine", 2, 3),
    ],
    arrows=[
        E("x_serverlink", "ws", "WebSocket", both=True),
        E("x_bots", "ws", ("in memory", "в памяти")),
        E("ws", "hub", ("queue, attach", "очередь, attach")),
        E("hub", "game", ("start;\nEv::Act", "start;\nEv::Act")),
        E("game", "ranked", ("results", "итоги")),
        E("ws", "packsrs", ("playable,\nrules_for", "playable,\nrules_for")),
        E("ws", "auth", ("login", "вход")),
        E("packsrs", "x_storage", (".cardpack", ".cardpack"), both=True),
        E("packsrs", "x_engine", ("load, trial", "загрузка, проба")),
        E("game", "x_engine", ("Game::apply,\nviews", "Game::apply,\nвиды")),
        E("game", "events", ("game_action,\ngame_end", "game_action,\ngame_end")),
        E("events", "x_storage", ("events table", "таблица events")),
        E("x_admin", "hub", ("live, accounts", "в сети, аккаунты"), dash=True),
    ],
    data=[
        ("App", ("The database, the pack store, the rules cache by `rules_hash`, the Hub, the login limits, the timers, the event log, the bots' manager.",
                 "База, хранилище пакетов, кэш правил по `rules_hash`, Hub, лимиты входа, таймеры, журнал событий, менеджер ботов.")),
        ("Hub", ("`conns` account → connection, `queue` account → seeker (mode, rules, deck, key, since), `games` id → live game, `in_game`, `invites`, `auto_for`.",
                 "`conns` аккаунт → подключение, `queue` аккаунт → ищущий (режим, правила, колода, ключ, с какого времени), `games` id → идущая партия, `in_game`, `invites`, `auto_for`.")),
        (("Timers", "Таймеры"), ("From the pack's `timers`: turn 75 s, mulligan 45 s, 5 s slack, 30 s to come back after a drop.",
                                 "Из `timers` пакета: ход 75 с, муллиган 45 с, запас 5 с, 30 с на возвращение после обрыва.")),
    ],
    protocol=[
        (("Client → server", "Клиент → сервер"), ("Accounts `register`, `login`, `resume`, `logout`, `me`, `set_tag`; friends `friends`, `friend_add/accept/decline/remove`, `block`, `unblock`; chat `msg`, `history`, `chats`, `read`; "
                                                 "`invite`, `invite_accept`, `invite_decline`; `queue`, `unqueue`; `arena_start/hero/pick/queue/retire`; in a game `act`, `emote`, `intent`; `packs`, `pack_delete`; `decks`, `deck_save`, `deck_delete`; `game_settings`, `game_settings_set`.",
                                                 "Аккаунты `register`, `login`, `resume`, `logout`, `me`, `set_tag`; друзья `friends`, `friend_add/accept/decline/remove`, `block`, `unblock`; чат `msg`, `history`, `chats`, `read`; "
                                                 "`invite`, `invite_accept`, `invite_decline`; `queue`, `unqueue`; `arena_start/hero/pick/queue/retire`; в партии `act`, `emote`, `intent`; `packs`, `pack_delete`; `decks`, `deck_save`, `deck_delete`; `game_settings`, `game_settings_set`.")),
        (("Server → client", "Сервер → клиент"), ("`auth`, `error {code, text}`, `me`, `kicked`; `friends`, `presence`; `msg`, `history`, `chats`; `invite`, `invite_declined`; `queued`, `queue_status`; `arena {state}`; "
                                                 "`match {game, mode, opponent, you, pack, rejoin?}`, `state {game, view, events, result}`, `act_error`, `game_over {result, reason, rank?, arena?}`; `packs {server, mine}`, `decks`, `deck_saved`, `game_settings`.",
                                                 "`auth`, `error {code, text}`, `me`, `kicked`; `friends`, `presence`; `msg`, `history`, `chats`; `invite`, `invite_declined`; `queued`, `queue_status`; `arena {state}`; "
                                                 "`match {game, mode, opponent, you, pack, rejoin?}`, `state {game, view, events, result}`, `act_error`, `game_over {result, reason, rank?, arena?}`; `packs {server, mine}`, `decks`, `deck_saved`, `game_settings`.")),
        ("HTTP", ("`GET /` — the WebSocket; `POST /packs` (bearer token, 100 MB, 10 per player) → 201 or 401 / 409 / 413 / 422; `GET /packs/<content_hash>.cardpack` with ETag and long caching; CORS open for the web build.",
                  "`GET /` — WebSocket; `POST /packs` (токен, 100 МБ, 10 на игрока) → 201 или 401 / 409 / 413 / 422; `GET /packs/<content_hash>.cardpack` с ETag и долгим кэшем; CORS открыт для веб-сборки.")),
    ],
    flows=["server-game", "pack-upload", "server-login"],
))

FLOWS.append(dict(
    id="server-game", home="server",
    title=("A server game", "Партия на сервере"),
    short=("Queue → matchmaking → a game task that owns the game → each player's own view → the client's Match → the table.",
           "Очередь → подбор → задача партии, которая ею владеет → вид каждого игрока → Match клиента → стол."),
    lanes=[L("client", ("Client", "Клиент"), "serverlink", "ServerView · ServerSession"), L("ws", ("Player session", "Сессия"), "server", "ws.rs"),
           L("hub", "Hub", "server", "lib.rs"), L("game", ("Game task", "Задача партии"), "server", "game.rs"), L("engine", ("Rules engine", "Движок"), "engine"),
           L("db", ("Database", "База"), "storage")],
    steps=[
        ("client", "ws", "queue {mode, deck, pack}", ("Casual or ranked, the deck, the game's `rules_hash`.", "Обычная или рейтинговая, колода, `rules_hash` игры."),
         [("ui/server_view.gd", "func queue(m: String) -> void:")]),
        ("ws", "engine", ("playable? deck legal?", "можно? колода законна?"),
         ("The game must be the default, an enabled server pack or (friendly) the inviter's own; the deck is checked by the engine in that pack's rules.",
          "Игра — по умолчанию, включённый пакет сервера или (дружеская) свой пакет пригласившего; колоду проверяет движок по правилам этого пакета."),
         [("server/src/packs.rs", "pub async fn playable(app: &AppRef, pack: Option<&str>, own: Option<i64>)"), ("server/src/ws.rs", "async fn validate(&self, deck: &Value, rules: &GameRules) -> R {")]),
        ("ws", "hub", ("enqueue (key)", "enqueue (ключ)"), ("The key is the MMR (casual) or the stars (ranked) of this game's standing; `queued`, then `queue_status` every second.",
                                                       "Ключ — MMR (обычная) или звёзды (рейтинговая) по этой игре; `queued`, затем каждую секунду `queue_status`."),
         [("server/src/ws.rs", "async fn enqueue(&self, me: i64, mode: Mode, rules: Arc<GameRules>, deck: Value, key: Key) -> R {")]),
        ("hub", "hub", ("pair, every 1 s", "пара, каждую секунду"), ("The longest waiter gets the nearest player of the same mode and pack whose gap fits both windows; the windows grow with waiting.",
                                                                 "Дольше всех ждущий получает ближайшего игрока того же режима и пакета, если разрыв помещается в окна обоих; окна растут со временем."),
         [("server/src/lib.rs", "pub fn pair(&mut self, now: Instant) -> Vec<Pairing> {"), ("server/src/ranked.rs", "pub fn fits(")]),
        ("hub", "game", ("start → begin", "start → begin"), ("Random seats, a new id and seed, `Game::new_in` the pack's rules, `match` to both, one task.",
                                                         "Случайные места, новые id и seed, `Game::new_in` по правилам пакета, `match` обоим, одна задача."),
         [("server/src/game.rs", "async fn begin(")]),
        ("game", "client", "state {view, events, result}", ("Each player gets the engine's snapshot for their seat and the events cut for them — never the opponent's hand, deck or secrets.",
                                                             "Каждый получает снимок движка для своего места и события, урезанные для него, — никогда руки, колоды и секретов соперника."),
         [("server/src/game.rs", "pub fn state_msg("), ("rust/engine/src/api.rs", "pub fn events_for(")]),
        ("client", "client", ("pack, Match, table", "пакет, Match, стол"), ("The session makes the game's pack active (downloads it if missing); the first state sets up the Match; later ones are `on_state`.",
                                                                       "Сессия делает пакет игры активным (скачав, если нет); первый state создаёт Match, следующие идут в `on_state`."),
         [("net/server_session.gd", "func _use_pack() -> void:"), ("game/match.gd", "func setup_server("), ("game/match.gd", "func on_state(msg: Dictionary) -> void:")]),
        ("client", "game", "act {game, action}", ("Through the session to the game task.", "Через сессию в задачу партии."),
         [("server/src/ws.rs", "fn to_game(&self, me: i64, game: Option<String>, ev: impl FnOnce(usize) -> game::Ev) -> R {")]),
        ("game", "engine", "Game::apply", ("Legal → new states to both; refused → `act_error` to the sender only; the third refusal loses (`illegal`); a panic aborts the game.",
                                           "Законно — новые state обоим; отказ — `act_error` только отправителю; третий отказ — поражение (`illegal`); паника — партия прерывается."),
         [("server/src/game.rs", "fn step(&self, g: &mut Game, clock: &mut Clock, p: usize, a: &Value, timeout: bool) -> Step {"), ("server/src/game.rs", "const STRIKES: usize = 3;")]),
        ("game", "game", ("clock, drops", "часы, обрывы"), ("After the deadline + slack the server plays the timeout moves; a dropped player has 30 s to come back (`match {rejoin}`).",
                                                         "После срока + запаса сервер сам делает ходы по таймауту; у оборвавшегося игрока 30 с на возвращение (`match {rejoin}`)."),
         [("server/src/game.rs", "struct Clock {"), ("server/src/game.rs", "fn timeout(&self, g: &mut Game, clock: &mut Clock) -> Option<End> {")]),
        ("game", "db", ("finish: results", "finish: итоги"), ("In one transaction: Elo, stars by the pack's ladder or the Arena record, a `games` row; `game_over` to both.",
                                                         "В одной транзакции: Elo, звёзды по лестнице пакета или счёт Арены, строка `games`; обоим `game_over`."),
         [("server/src/game.rs", "async fn finish(ctx: &Ctx"), ("server/src/game.rs", "async fn apply_results(")]),
    ],
))

FLOWS.append(dict(
    id="pack-upload", home="server",
    title=("A pack on the server", "Пакет на сервере"),
    short=("Upload → checks → a trial game → the store → the list → a download onto another device.",
           "Загрузка → проверки → пробная партия → хранилище → список → скачивание на другом устройстве."),
    lanes=[L("client", ("Client", "Клиент"), "serverlink", "ServerHome · ServerLink"), L("packs", ("Packs", "Пакеты"), "server", "packs.rs"),
           L("engine", ("Rules engine", "Движок"), "engine"), L("store", ("Store, DB", "Хранилище, база"), "storage")],
    steps=[
        ("client", "packs", "POST /packs", ("The Upload panel lists the local packs the server lacks; the bearer token; at most 10 own packs.", "Панель загрузки показывает локальные пакеты, которых нет на сервере; токен; не больше 10 своих пакетов."),
         [("ui/server_home.gd", "func show_upload() -> void:"), ("net/server_link.gd", "func upload_pack(p: Pack) -> void:")]),
        ("packs", "packs", ("stream to a file", "поток в файл"), ("SHA-256 on the way, over 100 MB → 413.", "SHA-256 по дороге, больше 100 МБ — 413."),
         [("server/src/packs.rs", "pub async fn receive(")]),
        ("packs", "engine", ("inspect", "inspect"), ("The zip by the format's rules, the manifest, `rules_hash` must match, `content_hash`.", "Zip по правилам формата, манифест, совпадение `rules_hash`, `content_hash`."),
         [("server/src/packs.rs", "pub fn inspect(bytes: &[u8]) -> Result<Inspected, String> {")]),
        ("packs", "engine", ("trial game", "пробная партия"), ("New rules only: the engine compiles every script and its bot plays a game (600 actions, 20 s), trying every legal move on a copy; any error → 422.",
                                                         "Только новые правила: движок компилирует все скрипты, и его бот играет партию (600 действий, 20 с), пробуя каждый законный ход на копии; любая ошибка — 422."),
         [("server/src/packs.rs", "pub fn trial(p: &Inspected) -> Result<(), String> {")]),
        ("packs", "store", ("put, insert", "положить, записать"), ("Stored once per `content_hash`; a `packs` row with its owner.", "Хранится один раз на `content_hash`; строка `packs` с владельцем."),
         [("server/src/packs.rs", "pub async fn add(app: &AppRef, file: &FsPath, size: u64, owner: Option<i64>)"), ("server/src/storage.rs", "pub async fn put_file(")]),
        ("packs", "client", "201 · packs {server, mine}", ("The new list over the WebSocket; the admin's feed gets `pack_upload`.", "Новый список по WebSocket; лента админки получает `pack_upload`."),
         [("server/src/packs.rs", "pub async fn packs_msg(")]),
        ("client", "packs", "GET /packs/<hash>.cardpack", ("On another device: enabled server packs for all, a player's own for them and their friends.",
                                                           "На другом устройстве: включённые пакеты сервера — всем, свой пакет игрока — ему и его друзьям."),
         [("server/src/packs.rs", "async fn download(State(app): State<AppRef>,"), ("server/src/packs.rs", "async fn visible(")]),
        ("store", "client", ("a stream with ETag", "поток с ETag"), ("Straight from the store; the client checks it and its hash itself and installs it.", "Прямо из хранилища; клиент сам проверяет пакет и хэш и устанавливает его."),
         [("server/src/storage.rs", "pub async fn get("), ("net/server_link.gd", "func _downloaded(code: int, body: PackedByteArray, entry: Dictionary) -> void:")]),
    ],
))


# --- the server's storage ---------------------------------------------------------------------------

COMPS.append(dict(
    id="storage", name=("Storage", "Хранилище"), sub=("SQLite · S3 or a folder", "SQLite · S3 или папка"), layer="server", x=40, y=620,
    short=("Where the server keeps things: SQLite through SeaORM for accounts, ranks, games, events, decks and settings; the .cardpack files in an "
           "S3-compatible bucket (SeaweedFS in Docker) or a folder, keyed by `content_hash`, so a file never changes once written.",
           "Где сервер хранит данные: SQLite через SeaORM — аккаунты, ранги, партии, события, колоды и настройки; файлы .cardpack — в S3-совместимом "
           "бакете (SeaweedFS в Docker) или в папке по ключу `content_hash`, поэтому записанный файл больше не меняется."),
    text=("The database has one connection in WAL mode; the migrations run at every start, so an older database is taken as it is. "
          "Big files go to S3 in parts; downloads stream straight to the player. The same file of several owners is stored once; `gc` removes it when no row refers to it.",
          "У базы одно соединение в режиме WAL; миграции применяются при каждом старте, поэтому старая база подхватывается как есть. "
          "Большие файлы уходят в S3 частями; скачивание идёт потоком прямо игроку. Один и тот же файл разных владельцев хранится один раз; `gc` удаляет его, когда на него не ссылается ни одна строка."),
    parts=[
        X("server", 1, 0),
        P("db", ("Database", "База"), 0, 1, sub="db.rs",
          text=("SQLite through SeaORM, one connection, WAL; standings per (account, pack, season); sessions.",
                "SQLite через SeaORM, одно соединение, WAL; ранги по (аккаунт, пакет, сезон); сессии."),
          files=[("server/src/db.rs", "pub async fn open(path: &str) -> DbResult<Db> {"), ("server/src/db.rs", "pub async fn standing(")]),
        P("migr", ("Migrations", "Миграции"), 1, 1, sub="migration.rs",
          text=("M1 the 0.26 schema · M2 read marks, session times, events · M3 packs · M4 hashes, default pack, standings per pack · M5 bots · M6 decks · M7 game settings.",
                "M1 схема 0.26 · M2 отметки о прочтении, время сессий, события · M3 пакеты · M4 хэши, пакет по умолчанию, ранги по пакетам · M5 боты · M6 колоды · M7 настройки игр."),
          files=[("server/src/migration.rs", "vec![Box::new(M1), Box::new(M2)")]),
        P("store", ("Pack store", "Хранилище пакетов"), 2, 1, sub="storage.rs",
          text=("`object_store`: a folder (default `store`) or S3 (path-style); `put_file` (multipart over 10 MB), `get` as a stream, `delete`.",
                "`object_store`: папка (по умолчанию `store`) или S3 (path-style); `put_file` (частями больше 10 МБ), `get` потоком, `delete`."),
          files=[("server/src/storage.rs", "pub struct Storage {"), ("server/src/storage.rs", "pub fn s3(c: &S3) -> Result<Storage, String> {")]),
        P("tables", ("Tables", "Таблицы"), 0, 2, sub="server/src/entity",
          text=("accounts, sessions, friends, requests, blocks, messages, games, arena, events, packs, pack_imports, standings, bots, decks, game_settings.",
                "accounts, sessions, friends, requests, blocks, messages, games, arena, events, packs, pack_imports, standings, bots, decks, game_settings."),
          files=["server/src/entity/mod.rs", ("server/src/entity/deck.rs", "table_name")]),
        P("bucket", "SeaweedFS · S3", 2, 2, sub="docker-compose.yml",
          text=("`weed mini` (master, volume, filer and S3 in one process, the `packs` bucket made at start); the S3 port is not exposed.",
                "`weed mini` (master, volume, filer и S3 в одном процессе, бакет `packs` создаётся при старте); порт S3 наружу не открыт."),
          files=[("server/docker-compose.yml", "image: chrislusf/seaweedfs:4.48")]),
    ],
    arrows=[
        E("x_server", "db", "SeaORM"),
        E("x_server", "store", (".cardpack", ".cardpack")),
        E("db", "migr", ("at start", "при старте")),
        E("db", "tables", ("rows", "строки")),
        E("store", "bucket", ("S3 API", "S3 API")),
    ],
    data=[
        ("packs", ("id, pack id, version, name, `rules_hash`, `content_hash`, size, owner (null = the server's), enabled, default, downloads.",
                   "id, id пакета, версия, имя, `rules_hash`, `content_hash`, размер, владелец (null — пакет сервера), включён, по умолчанию, скачивания.")),
        (("games, standings, arena", "games, standings, arena"), ("A game row keeps its `rules_hash`; standings are per (account, pack id, season); an Arena run keeps its seed, hero, picks and pack.",
                                                                 "Строка партии хранит её `rules_hash`; ранги — по (аккаунт, id пакета, сезон); забег Арены хранит seed, героя, выборы и пакет.")),
        (("decks, game_settings", "decks, game_settings"), ("Decks per (account, pack id), up to 100; settings per (account, pack id) as a small JSON object.",
                                                           "Колоды по (аккаунт, id пакета), до 100; настройки по (аккаунт, id пакета) как маленький JSON-объект.")),
    ],
    flows=["pack-upload", "server-decks"],
))


# --- the admin panel (server/admin, server/src/admin.rs) -----------------------------------------------

COMPS.append(dict(
    id="admin", name=("Admin panel", "Админка"), sub="/admin · Preact", layer="server", x=1030, y=620,
    short=("A single-page app in the server binary: the dashboard, the event log, accounts, conversations, games move by move, the game packs and the bots, "
           "with a live feed over a WebSocket.",
           "Одностраничное приложение внутри бинарника сервера: сводка, журнал событий, аккаунты, переписки, партии ход за ходом, пакеты игр и боты, "
           "с живой лентой по WebSocket."),
    text=("Plain ES modules with Preact and htm (no build step), embedded in the binary. Its own cookie session (HttpOnly, SameSite=Strict, 30 days), "
          "a CSRF token on every non-GET, Origin checks and a strict Content-Security-Policy. A superuser is made only on the command line "
          "(`classichs-server admin <name>`).",
          "Обычные ES-модули с Preact и htm (без сборки), вшитые в бинарник. Своя сессия на cookie (HttpOnly, SameSite=Strict, 30 дней), "
          "CSRF-токен на всё, кроме GET, проверка Origin и строгая Content-Security-Policy. Суперпользователь создаётся только из командной строки "
          "(`classichs-server admin <name>`)."),
    parts=[
        P("spa", ("The app", "Приложение"), 0, 0, sub="server/admin/app.js",
          text=("The navigation, the shell and the live feed hook.", "Навигация, оболочка и подписка на живую ленту."),
          files=[("server/admin/app.js", "const NAV = ["), ("server/admin/app.js", "function useFeed (me) {")]),
        P("pages", ("Pages", "Страницы"), 1, 0, sub="dashboard · events · games · packs · bots · accounts · messages",
          text=("The packs page uploads by drag and drop (each file checked by the engine); the bots page shows each bot's board and its last decision.",
                "Страница пакетов загружает перетаскиванием (каждый файл проверяет движок); страница ботов показывает стол каждого бота и его последнее решение."),
          files=[("server/admin/packs.js", "export function Packs"), ("server/admin/bots.js", "export function Bots ()")]),
        P("api", "api.js", 0, 1, text=("fetch with the `X-CSRF-Token` header; uploads with progress.", "fetch с заголовком `X-CSRF-Token`; загрузка с прогрессом."),
          files=[("server/admin/api.js", "export async function api (path, { method = 'GET', body } = {}) {")]),
        P("routes", "admin.rs", 1, 1, sub=("routes · guard · CSP", "маршруты · guard · CSP"),
          text=("The routes, the login (admin and super roles only), the guard (cookie, Origin, CSRF), the security headers, the JSON API.",
                "Маршруты, вход (только роли admin и super), guard (cookie, Origin, CSRF), заголовки безопасности, JSON API."),
          files=[("server/src/admin.rs", "pub fn routes(app: AppRef) -> Router<AppRef> {"), ("server/src/admin.rs", "async fn guard(State(app): State<AppRef>, mut req: Request, next: Next) -> Response {"),
                 ("server/src/admin.rs", "fn csp() -> &'static str {")]),
        P("feed", ("Live feed", "Живая лента"), 2, 1, sub="/admin/ws",
          text=("`hello {live}`, then every event and every change of who is online, queued and playing; `resync` when the page lags; the session re-checked every 30 s.",
                "`hello {live}`, затем каждое событие и каждая смена того, кто в сети, в очереди и в партии; `resync`, если страница отстала; сессия перепроверяется каждые 30 с."),
          files=[("server/src/admin.rs", "async fn run_feed(app: AppRef, a: Admin, mut socket: WebSocket) {")]),
        X("storage", 0, 2), X("bots", 1, 2), X("server", 2, 2),
    ],
    arrows=[
        E("spa", "pages", "NAV"),
        E("spa", "api", "api()"),
        E("api", "routes", ("/admin/api", "/admin/api")),
        E("spa", "feed", "useFeed"),
        E("routes", "x_storage", ("accounts, events,\ngames, packs", "аккаунты, события,\nпартии, пакеты")),
        E("routes", "x_server", ("Hub: live,\nkick", "Hub: в сети,\nвыкинуть")),
        E("routes", "x_bots", ("create, start,\nstop", "создать, старт,\nстоп")),
        E("x_server", "feed", ("Log.feed", "Log.feed")),
    ],
    protocol=[
        (("API", "API"), ("`/admin/api/` login, logout, me, dashboard, live, accounts (+ suspend, password, role, delete), events, conversations, games, packs (+ enable, disable, default, delete), bots (+ start, stop, update, delete).",
                          "`/admin/api/` login, logout, me, dashboard, live, accounts (+ заморозить, пароль, роль, удалить), events, conversations, games, packs (+ включить, выключить, по умолчанию, удалить), bots (+ старт, стоп, изменить, удалить).")),
        (("Feed", "Лента"), ("`hello {live}`, `event {e}`, `live {live}`, `resync`.", "`hello {live}`, `event {e}`, `live {live}`, `resync`.")),
    ],
    flows=["admin-feed"],
))

FLOWS.append(dict(
    id="admin-feed", home="admin",
    title=("The admin logs in and watches", "Админ входит и смотрит"),
    short=("The page, the login with a cookie and a CSRF token, guarded API calls, the live feed of events.",
           "Страница, вход с cookie и CSRF-токеном, защищённые вызовы API, живая лента событий."),
    lanes=[L("browser", ("Browser", "Браузер"), "admin", "server/admin/*.js"), L("admin", "admin.rs", "admin"), L("db", ("Database", "База"), "storage"),
           L("log", ("Event log", "Журнал"), "server", "events.rs")],
    steps=[
        ("browser", "admin", "GET /admin", ("index.html under a CSP that hashes its inline scripts; `api('me')` → 401 shows the login.", "index.html под CSP с хэшами встроенных скриптов; `api('me')` → 401 показывает вход."),
         [("server/src/admin.rs", "fn csp() -> &'static str {"), ("server/admin/app.js", "function App () {")]),
        ("browser", "admin", "POST /admin/api/login", ("JSON only; Origin, rate limits, argon2; only the admin and super roles, not suspended.", "Только JSON; Origin, лимиты, argon2; только роли admin и super, не замороженные."),
         [("server/admin/login.js", "export function Login ({ onIn }) {"), ("server/src/admin.rs", "async fn login(State(app): State<AppRef>")]),
        ("admin", "db", ("admin session", "сессия админа"), ("30 days, with a CSRF token; the cookie `chs_admin` (HttpOnly, SameSite=Strict, Secure behind TLS).",
                                                         "30 дней, с CSRF-токеном; cookie `chs_admin` (HttpOnly, SameSite=Strict, Secure за TLS)."),
         [("server/src/db.rs", "pub async fn new_session(")]),
        ("browser", "admin", ("guarded calls", "защищённые вызовы"), ("Every call: Origin, the cookie session, and `X-CSRF-Token` on non-GET, compared in constant time.",
                                                                 "Каждый вызов: Origin, сессия по cookie и `X-CSRF-Token` не для GET, сравнение за постоянное время."),
         [("server/admin/api.js", "export async function api (path, { method = 'GET', body } = {}) {"), ("server/src/admin.rs", "async fn guard(State(app): State<AppRef>, mut req: Request, next: Next) -> Response {")]),
        ("browser", "admin", "/admin/ws", ("Opened by the app, reconnecting with backoff.", "Открывается приложением, переподключается с нарастающей паузой."),
         [("server/admin/app.js", "function useFeed (me) {")]),
        ("log", "admin", ("event, live", "event, live"), ("Each event after it is written; the online / queue / games snapshot when it changes.", "Каждое событие после записи; снимок «в сети / очереди / партии», когда он меняется."),
         [("server/src/events.rs", "async fn writer("), ("server/src/lib.rs", "app.log.push(&json!({\"t\": \"live\", \"live\": live}));")]),
        ("admin", "browser", ("hello, event, live", "hello, event, live"), ("Pages update live; a lagging page gets `resync`.", "Страницы обновляются на лету; отставшая получает `resync`."),
         [("server/src/admin.rs", "async fn run_feed(app: AppRef, a: Admin, mut socket: WebSocket) {")]),
    ],
))

# --- tools and tests ---------------------------------------------------------------------------------

COMPS.append(dict(
    id="tools", name=("Tools and tests", "Инструменты и тесты"), sub="tools/ · tests/", layer="ops", x=40, y=20,
    short=("Python, GDScript and shell outside the game: building and checking packs, generating art and sound, layout and scene checks, "
           "the test suites of the client, the engine, the Lua interpreter and the server.",
           "Python, GDScript и shell вне игры: сборка и проверка пакетов, генерация арта и звука, проверки раскладок и сцен, наборы тестов клиента, "
           "движка, интерпретатора Lua и сервера."),
    text=("The GDScript tools are `extends SceneTree` scripts run with `godot --path . --script res://tools/….gd`; some need a window "
          "(make_splash, screenshots, card_sheets, site_cards). They use the game's own classes, so pictures for the site look exactly like the game.",
          "Инструменты на GDScript — скрипты `extends SceneTree`, запуск: `godot --path . --script res://tools/….gd`; некоторым нужно окно "
          "(make_splash, screenshots, card_sheets, site_cards). Они используют классы самой игры, поэтому картинки для сайта выглядят ровно как в игре."),
    parts=[
        P("packtools", ("Pack tools", "Инструменты пакетов"), 0, 0, sub="pack.py · build_packs.sh · pack_try.gd",
          text=("Build, check, info and hash a pack; build the two built-in ones; play a pack bot against bot from the command line.",
                "Собрать, проверить, описать и посчитать хэши пакета; собрать два встроенных; сыграть пакет бот против бота из командной строки."),
          files=[("tools/pack.py", "def main(argv=None):"), "tools/build_packs.sh", "tools/pack_try.gd"]),
        P("gen", ("Content generators", "Генераторы содержимого"), 1, 0, sub="extract_cards · gen_card_art · neon_art · gen_audio",
          text=("Cards from HearthstoneJSON, card art through Codex, synthesized sounds and music, UI sprites; run once, the results are in the repository.",
                "Карты из HearthstoneJSON, арт карт через Codex, синтезированные звуки и музыка, спрайты интерфейса; запускаются один раз, результат лежит в репозитории."),
          files=["tools/extract_cards.py", "tools/neon_art.py", "tools/gen_audio.py"]),
        P("checks", ("Checks", "Проверки"), 2, 0, sub="card_layout · check_card_tests · server_e2e · web_update_check",
          text=("Card text layouts in every language, every card's test scene, a live server played by two clients, the web update in headless Chrome.",
                "Раскладки текста карт на всех языках, тестовая сцена каждой карты, живой сервер с двумя клиентами, обновление веб-версии в headless Chrome."),
          files=["tools/card_layout.gd", "tools/check_card_tests.gd", "tools/server_e2e.gd", "tools/web_update_check.sh"]),
        P("gdtests", ("Godot tests", "Тесты Godot"), 1, 1, sub="run_tests.sh · tests/",
          text=("About 435 tests in 57 files: screens and flows, the table, network sessions, pack transfer, packs and themes, servers, the tutorial, the migration, translations and fonts.",
                "Около 435 тестов в 57 файлах: экраны и потоки, стол, сетевые сессии, передача пакета, пакеты и темы, серверы, обучение, миграция, переводы и шрифты."),
          files=["run_tests.sh", ("tests/run.gd", "func _run_all() -> void:")]),
        P("rusttests", ("Rust tests", "Тесты на Rust"), 2, 1, sub="cargo test · rust/ server/",
          text=("The engine (parity over 7833 recorded games, the API, packs, Neonfall), the Lua interpreter (54), the brain, the server (games by bots with leak checks, packs, admin, bots).",
                "Движок (паритет на 7833 записанных партиях, API, пакеты, Neonfall), интерпретатор Lua (54), мозг, сервер (партии ботами с проверкой утечек, пакеты, админка, боты)."),
          files=[("rust/engine/tests/parity.rs", "fn parity_with_gdscript()"), "server/tests/flow.rs"]),
        P("doctools", ("Docs tools", "Инструменты документации"), 3, 1, sub="lua_api · site_docs · arch_page",
          text=("The API reference made from `lua.rs` and checked against `api.md`; the developer pages; this map with its line references resolved at build time.",
                "Справочник API из `lua.rs`, сверенный с `api.md`; страницы для разработчиков; эта карта, у которой ссылки на строки вычисляются при сборке."),
          files=["tools/lua_api.py", "tools/site_docs.py", "tools/arch_page.py", "tools/arch_data.py"]),
        X("packs", 0, 1), X("ci", 1, 2), X("site", 3, 2),
    ],
    arrows=[
        E("packtools", "x_packs", ("build", "сборка"), dash=True),
        E("gdtests", "x_ci", ("in CI", "в CI"), dash=True),
        E("rusttests", "x_ci", ("in CI", "в CI"), dash=True),
        E("doctools", "x_site", ("dev/ pages", "страницы dev/"), dash=True),
    ],
    flows=["tests"],
))

FLOWS.append(dict(
    id="tests", home="tools",
    title=("Running the tests", "Запуск тестов"),
    short=("`./run_tests.sh` for the client, `cargo test` in `rust/` and `server/`, `tools/test_pack.py` for the pack tool.",
           "`./run_tests.sh` для клиента, `cargo test` в `rust/` и `server/`, `tools/test_pack.py` для инструмента пакетов."),
    lanes=[L("dev", ("Developer", "Разработчик"), "tools"), L("godot", ("Godot runner", "Godot"), "tools", "tests/run.gd"), L("rust", "cargo", "tools", "rust/ · server/"),
           L("py", "Python", "tools", "test_pack.py")],
    steps=[
        ("dev", "godot", "./run_tests.sh", ("Builds the packs, fetches the WebRTC plugin, imports the project, runs `tests/run.gd`; `-- name` filters by \"file:method\".",
                                            "Собирает пакеты, скачивает плагин WebRTC, импортирует проект, запускает `tests/run.gd`; `-- имя` отбирает по «файл:метод»."),
         ["run_tests.sh", "tools/fetch_webrtc.sh"]),
        ("godot", "godot", ("every test_*", "каждый test_*"),
         ("Instant animations, English, temporary user files; any script error caught by its own Logger fails the test.",
          "Мгновенные анимации, английский язык, временные файлы игрока; любая ошибка скрипта, пойманная своим Logger, проваливает тест."),
         [("tests/run.gd", "class ErrorCounter extends Logger:"), ("tests/run.gd", "print(\"%d tests, %d failed\" % [total, failed])")]),
        ("dev", "rust", "cd rust && cargo test", ("The parity check replays every recorded game and compares legal moves, bot choices, events and the hash at every step.",
                                                  "Проверка паритета переигрывает каждую записанную партию и на каждом шаге сверяет законные ходы, выбор бота, события и хэш."),
         [("rust/engine/tests/parity.rs", "fn parity_with_gdscript()")]),
        ("dev", "rust", "cd server && cargo test", ("A real server on 127.0.0.1 with an in-memory database: whole games by bots, every `state` checked against a mirror game and for leaks.",
                                                    "Настоящий сервер на 127.0.0.1 с базой в памяти: целые партии ботами, каждый `state` сверяется с зеркальной партией и проверяется на утечки."),
         ["server/tests/flow.rs"]),
        ("dev", "py", "python3 -m unittest tools/test_pack.py", ("Building, checking and hashing packs.", "Сборка, проверка и хэши пакетов."),
         ["tools/test_pack.py"]),
    ],
))


# --- the site and the web build ---------------------------------------------------------------------

COMPS.append(dict(
    id="site", name=("Site and web build", "Сайт и веб-версия"), sub="site/ · build_site.sh", layer="ops", x=370, y=20,
    short=("The landing page in 8 languages, the developer pages (with this map), and the game's web build in `play/` — an installable app that "
           "always runs the newest published version and still opens offline.",
           "Лендинг на 8 языках, страницы для разработчиков (и эта карта) и веб-версия игры в `play/` — устанавливаемое приложение, которое всегда "
           "запускает новейшую опубликованную версию и открывается без сети."),
    text=("GitHub Pages, published by hand with `tools/build_site.sh --publish` into the `gh-pages` branch — there is no Pages job in CI. "
          "The game's name is written once, in `site/name.js`; the landing page and the developer pages take it from there.",
          "GitHub Pages, публикуется вручную через `tools/build_site.sh --publish` в ветку `gh-pages` — задачи Pages в CI нет. "
          "Название игры записано в одном месте, `site/name.js`; лендинг и страницы для разработчиков берут его оттуда."),
    parts=[
        P("landing", ("Landing page", "Лендинг"), 0, 0, sub="site/index.html · main.js · i18n/",
          text=("Neonfall's look, 8 languages, cards drawn by the game, the gallery, the For developers block, the game in an iframe on click.",
                "Оформление Neonfall, 8 языков, карты, нарисованные игрой, галерея, блок «Разработчикам», игра во фрейме по нажатию."),
          files=[("site/main.js", "function applyLang() {"), ("site/index.html", "<section id=\"makers\" class=\"makers\">"), "site/name.js"]),
        P("dev", ("Developer pages", "Страницы разработчика"), 1, 0, sub="site_docs.py · site/dev/",
          text=("Guides in English and Russian from Markdown, the API reference from the engine's source, `docs/packs` as the reference, and this map.",
                "Руководства на английском и русском из Markdown, справочник API из исходников движка, `docs/packs` как справочник и эта карта."),
          files=[("tools/site_docs.py", "def build(out):"), ("tools/arch_page.py", "def body(lang):"), "site/dev/arch.js"]),
        P("data", ("Site data", "Данные сайта"), 2, 0, sub="site_data.py · site_cards.gd",
          text=("`data.json`: heroes, showcase cards, version, download size, test count, news; the cards rendered by the game as WebP.",
                "`data.json`: герои, витринные карты, версия, размер загрузки, число тестов, новости; карты, нарисованные игрой, в WebP."),
          files=[("tools/site_data.py", "def main(out):"), ("tools/site_cards.gd", "save_webp(")]),
        P("export", ("Web export", "Веб-экспорт"), 0, 1, sub="export_presets.cfg · web_finish.sh",
          text=("Godot's Web preset (a PWA; the head includes `update.js` and `rules.js`), then the engine, `version.json`, the start gate and the service worker patches.",
                "Пресет Web у Godot (PWA; в head подключаются `update.js` и `rules.js`), затем движок, `version.json`, задержка старта и правки сервис-воркера."),
          files=[("export_presets.cfg", "html/head_include="), "tools/web_finish.sh"]),
        P("build", "build_site.sh", 1, 1, text=("Packs, splash, rules.wasm, the web export, the landing, data, the API check, the dev pages, the cards; `--publish` pushes gh-pages.",
                                                "Пакеты, заставка, rules.wasm, веб-экспорт, лендинг, данные, проверка API, страницы разработчика, карты; `--publish` отправляет gh-pages."),
          files=[("tools/build_site.sh", "python3 tools/site_docs.py \"$OUT\"")]),
        P("pages", "gh-pages", 2, 1, sub="pycz2.github.io/classichs",
          text=("The built site, committed as \"Site from <rev>\" and pushed.", "Собранный сайт, закоммиченный как «Site from <rev>» и отправленный."),
          files=[("tools/build_site.sh", "git -C \"$WT\" push origin gh-pages")]),
        P("update", "update.js", 0, 2, sub="web/update.js",
          text=("Before the engine starts: `version.json` past every cache; a newer build swaps the service worker, drops the old cache and reloads once.",
                "До старта движка: `version.json` мимо всех кэшей; более новая сборка меняет сервис-воркер, удаляет старый кэш и один раз перезагружает страницу."),
          files=[("web/update.js", "async function check() {"), ("web/update.js", "window.chsGate = function (engine) {")]),
        P("sw", ("Service worker", "Сервис-воркер"), 1, 2, sub="index.service.worker.js",
          text=("Godot's, patched: takes over at once, caches the engine too, opens offline; its cache is named by the build, so one stays.",
                "Godot-овский, с правками: берёт управление сразу, кэширует и движок, открывается без сети; кэш назван по сборке, поэтому остаётся один."),
          files=[("tools/web_finish.sh", "\\n\\tself.skipWaiting();")]),
    ],
    arrows=[
        E("build", "export", ("export Web", "экспорт Web")),
        E("build", "dev", "dev/"),
        E("build", "data", "data.json"),
        E("dev", "landing", ("For developers", "Разработчикам"), dash=True),
        E("export", "update", "head include"),
        E("update", "sw", "reg.update"),
        E("build", "pages", "--publish"),
    ],
    data=[
        ("version.json", ("`{\"version\": \"X.Y.Z\", \"build\": \"<Godot's CACHE_VERSION>\"}` next to the game; the build id is also written into `update.js`.",
                          "`{\"version\": \"X.Y.Z\", \"build\": \"<CACHE_VERSION Godot>\"}` рядом с игрой; id сборки записывается и в `update.js`.")),
        (("Caches", "Кэши"), ("`<name>-sw-cache-<build>`; on activate every other cache of the prefix is deleted. `update.js` reloads at most once per build (sessionStorage).",
                              "`<name>-sw-cache-<build>`; при активации все остальные кэши с этим префиксом удаляются. `update.js` перезагружает страницу не больше раза на сборку (sessionStorage).")),
    ],
    flows=["web-update", "site-build"],
))

FLOWS.append(dict(
    id="web-update", home="site",
    title=("The web update", "Обновление веб-версии"),
    short=("`version.json` read past the cache before the engine starts → a newer build: the service worker swaps, the old cache goes, one reload; offline the cached build starts.",
           "`version.json` мимо кэша до старта движка → новая сборка: сервис-воркер меняется, старый кэш уходит, одна перезагрузка; без сети стартует сборка из кэша."),
    lanes=[L("page", ("Page", "Страница"), "site", "index.html · update.js"), L("net", ("Network", "Сеть"), "site", "version.json"),
           L("sw", ("Service worker", "Сервис-воркер"), "site"), L("cache", "CacheStorage", "site"), L("engine", ("Godot engine", "Движок Godot"), "client")],
    steps=[
        ("page", "page", ("gate the start", "задержать старт"), ("`chsGate(engine)` wraps `startGame`: the game starts only after the check.", "`chsGate(engine)` оборачивает `startGame`: игра стартует только после проверки."),
         [("web/update.js", "window.chsGate = function (engine) {"), ("tools/web_finish.sh", "grep -q '^chsGate(engine);$'")]),
        ("page", "net", "version.json?t=…", ("`cache: no-store`, 5 s timeout; offline or an error — the cached build starts.", "`cache: no-store`, тайм-аут 5 с; без сети или при ошибке стартует сборка из кэша."),
         [("web/update.js", "async function check() {")]),
        ("page", "page", ("same build?", "та же сборка?"), ("The same → start. Newer → reload, but at most once per build.", "Та же — старт. Новее — перезагрузка, но не больше раза на сборку."),
         [("web/update.js", "if (!v.build || v.build === BUILD) return;"), ("web/update.js", "if (sessionStorage.getItem(key)) return;")]),
        ("page", "sw", "reg.update()", ("The new worker installs with `skipWaiting` and claims the page; up to 15 s for `controllerchange`.", "Новый воркер ставится со `skipWaiting` и забирает страницу; до 15 с на `controllerchange`."),
         [("web/update.js", "await reg.update();")]),
        ("sw", "cache", ("drop old caches", "удалить старые кэши"), ("On activate every other `<name>-sw-cache-*` goes.", "При активации уходят все остальные `<name>-sw-cache-*`."), []),
        ("page", "cache", ("fallback: clear all", "запасной путь: всё очистить"), ("No registration or a timeout: unregister and delete every cache, so the reload comes from the network.",
                                                                              "Нет регистрации или тайм-аут: снять регистрацию и удалить все кэши, чтобы перезагрузка пришла из сети."),
         [("web/update.js", "if (reg) await reg.unregister();")]),
        ("page", "page", "location.reload()", ("This page never starts the old build.", "Эта страница так и не запускает старую сборку."), [("web/update.js", "location.reload();")]),
        ("page", "engine", ("start the game", "старт игры"), ("On the next load the build matches and the engine starts; checked end to end by `tools/web_update_check.sh`.",
                                                       "При следующей загрузке сборка совпадает, и движок стартует; от начала до конца проверено `tools/web_update_check.sh`."),
         ["tools/web_update_check.sh"]),
    ],
))

FLOWS.append(dict(
    id="site-build", home="site",
    title=("The site build", "Сборка сайта"),
    short=("`tools/build_site.sh`: packs, the web export, the landing, the data, the developer pages (this map: every reference checked), the cards; `--publish` to gh-pages.",
           "`tools/build_site.sh`: пакеты, веб-экспорт, лендинг, данные, страницы разработчика (эта карта: каждая ссылка проверяется), карты; `--publish` — в gh-pages."),
    lanes=[L("sh", "build_site.sh", "site"), L("godot", "Godot", "client"), L("py", ("Python tools", "Python"), "tools", "site_data · lua_api · site_docs · arch_page"),
           L("out", "build/site", "site"), L("pages", "gh-pages", "site")],
    steps=[
        ("sh", "sh", ("packs, rules.wasm", "пакеты, rules.wasm"), ("`build_packs.sh`; `build_rules.sh web` unless `RULES_PREBUILT=1`.", "`build_packs.sh`; `build_rules.sh web`, если не `RULES_PREBUILT=1`."),
         [("tools/build_site.sh", "tools/build_packs.sh  # res://packs/*.cardpack"), ("tools/build_site.sh", "[ \"$RULES_PREBUILT\" = 1 ] || tools/build_rules.sh web")]),
        ("sh", "godot", ("splash, export Web", "заставка, экспорт Web"), ("The splash with the version (needs a window), then the web export into `play/`.", "Заставка с версией (нужно окно), затем веб-экспорт в `play/`."),
         [("tools/build_site.sh", "godot --headless --path . --export-release \"Web\" \"$OUT/play/index.html\"")]),
        ("sh", "out", "web_finish.sh", ("The engine, `update.js`, `version.json`, the start gate, the service worker patches.", "Движок, `update.js`, `version.json`, задержка старта, правки сервис-воркера."),
         [("tools/build_site.sh", "tools/web_finish.sh \"$OUT/play\"")]),
        ("sh", "py", ("data.json, API check", "data.json, проверка API"), ("A changed `g.*` function not described in `api.md` stops the build.", "Изменённая функция `g.*`, не описанная в `api.md`, останавливает сборку."),
         [("tools/build_site.sh", "python3 tools/site_data.py \"$OUT\""), ("tools/build_site.sh", "python3 tools/lua_api.py --check")]),
        ("sh", "py", ("dev/ pages and this map", "страницы dev/ и эта карта"),
         ("Guides, the API, the reference, and the architecture map: every source reference is found in the current code and becomes a GitHub line link; a broken one stops the build.",
          "Руководства, API, справочник и карта архитектуры: каждая ссылка на код находится в текущих исходниках и становится ссылкой на строку в GitHub; сломанная останавливает сборку."),
         [("tools/site_docs.py", "def build(out):"), ("tools/arch_page.py", "class Refs:")]),
        ("sh", "godot", ("cards as WebP", "карты в WebP"), ("The game draws the landing's cards itself (needs a window).", "Игра сама рисует карты лендинга (нужно окно)."),
         [("tools/build_site.sh", "godot --path . --script res://tools/site_cards.gd -- \"$OUT\"")]),
        ("sh", "pages", "--publish", ("A worktree of `gh-pages`, its content replaced, \"Site from <rev>\", pushed.", "Рабочая копия `gh-pages`, содержимое заменяется, «Site from <rev>», push."),
         [("tools/build_site.sh", "git -C \"$WT\" commit -q -m \"Site from $REV\"")]),
    ],
))


# --- CI and release ----------------------------------------------------------------------------------

COMPS.append(dict(
    id="ci", name=("CI and release", "CI и выпуск"), sub=".github/workflows", layer="ops", x=700, y=20,
    short=("GitHub Actions on every push to main (a check) and on every `vX.Y.Z` tag (a release): the engine for every platform, the tests, "
           "the game for Web, Windows, Linux, macOS and Android, the server for three systems, then a GitHub Release.",
           "GitHub Actions на каждый push в main (проверка) и на каждый тег `vX.Y.Z` (выпуск): движок под каждую платформу, тесты, игра для Web, Windows, "
           "Linux, macOS и Android, сервер для трёх систем, затем GitHub Release."),
    text=("A release in the repository: the version in `project.godot`, the changelog in 8 languages, the splash with the version, an annotated tag. "
          "Android is signed with a keystore from the secrets (a throwaway key when they are missing). There is no Docker or deploy job: "
          "the server is deployed from a developer's machine from the release's files.",
          "Выпуск в репозитории: версия в `project.godot`, журнал изменений на 8 языках, заставка с номером, аннотированный тег. "
          "Android подписывается keystore из секретов (одноразовым ключом, если их нет). Задач Docker и развёртывания нет: "
          "сервер разворачивается с машины разработчика из файлов выпуска."),
    parts=[
        P("trigger", ("Triggers", "Запуск"), 0, 0, sub="push main · tag v*",
          text=("A push to main runs everything but the release; a tag skips the tests and publishes.", "Push в main запускает всё, кроме выпуска; тег пропускает тесты и публикует."),
          files=[(".github/workflows/release.yml", "tags: [\"v*\"]")]),
        P("rust", ("job rust", "job rust"), 1, 0, sub=("3 systems", "3 системы"),
          text=("macOS, Windows, Linux (+ Android, wasm): engine tests, `build_rules.sh`, the server tests and build; artifacts `rules-*`, `server-*`.",
                "macOS, Windows, Linux (+ Android, wasm): тесты движка, `build_rules.sh`, тесты и сборка сервера; артефакты `rules-*`, `server-*`."),
          files=[(".github/workflows/release.yml", "  rust:"), (".github/workflows/release.yml", "run: tools/build_rules.sh ${{ matrix.platforms }}")]),
        P("game", ("job game", "job game"), 2, 0, sub="ubuntu",
          text=("Godot 4.7.2 and templates, Android SDK and signing, `./run_tests.sh` (must say 0 failed), `export_all.sh` per platform.",
                "Godot 4.7.2 и шаблоны, Android SDK и подпись, `./run_tests.sh` (должно быть 0 failed), `export_all.sh` по платформам."),
          files=[(".github/workflows/release.yml", "  game:"), (".github/workflows/release.yml", "grep -q \" 0 failed\" /tmp/tests.log")]),
        P("release", ("job release", "job release"), 3, 0, sub=("tags only", "только теги"),
          text=("All artifacts → a GitHub Release \"<name> vX.Y.Z\".", "Все артефакты → GitHub Release «<name> vX.Y.Z»."),
          files=[(".github/workflows/release.yml", "uses: softprops/action-gh-release@v3")]),
        P("stress", "server-stress.yml", 0, 1, sub=("by hand", "вручную"),
          text=("Runs one server test file N times until the first failure.", "Гоняет один файл тестов сервера N раз до первого провала."),
          files=[(".github/workflows/server-stress.yml", "for i in $(seq 1 \"${{ inputs.runs }}\"); do")]),
        P("export", "export_all.sh", 2, 1,
          text=("Packs and WebRTC first; each platform checks its rules library; the web build finished like the site's; Android packs stored uncompressed, aligned and signed.",
                "Сначала пакеты и WebRTC; каждая платформа проверяет свою библиотеку правил; веб-сборка доделывается как у сайта; в Android пакеты без сжатия, выравнивание и подпись."),
          files=[("tools/export_all.sh", "android_store_packs() {"), ("tools/export_all.sh", "tools/web_finish.sh \"$OUT/web\"")]),
        P("assets", ("Release files", "Файлы выпуска"), 3, 1, sub="GitHub Release",
          text=("`<Name>-<ver>-web.zip`, `-windows-x86_64.zip`, `-linux-x86_64.AppImage`, `-macos.zip`, `-android-arm64.apk`, the two `.cardpack`, the server for Linux, Windows, macOS.",
                "`<Name>-<ver>-web.zip`, `-windows-x86_64.zip`, `-linux-x86_64.AppImage`, `-macos.zip`, `-android-arm64.apk`, два `.cardpack`, сервер для Linux, Windows, macOS."),
          files=[(".github/workflows/release.yml", "files: dist/*")]),
        X("deploy", 3, 2),
    ],
    arrows=[
        E("trigger", "rust", "matrix"),
        E("rust", "game", "rules-*"),
        E("game", "release", "game"),
        E("game", "export", ("per platform", "по платформам")),
        E("release", "assets", "action-gh-release"),
        E("assets", "x_deploy", ("server + packs", "сервер + пакеты"), dash=True),
    ],
    flows=["release"],
))

FLOWS.append(dict(
    id="release", home="ci",
    title=("A release", "Выпуск версии"),
    short=("Version, changelog, splash, tag → CI builds every platform → a GitHub Release; the site is published by hand.",
           "Версия, журнал, заставка, тег → CI собирает все платформы → GitHub Release; сайт публикуется вручную."),
    lanes=[L("dev", ("Developer", "Разработчик"), "tools"), L("rust", "job rust", "ci"), L("game", "job game", "ci"), L("rel", "job release", "ci"), L("gh", "GitHub", "ci")],
    steps=[
        ("dev", "dev", ("version, changelog, tag", "версия, журнал, тег"), ("`config/version` in `project.godot`, the changelog in 8 languages, \"Splash for X.Y.Z\", an annotated `vX.Y.Z`.",
                                                                           "`config/version` в `project.godot`, журнал на 8 языках, «Splash for X.Y.Z», аннотированный `vX.Y.Z`."),
         [("project.godot", "config/version=")]),
        ("dev", "rust", ("push the tag", "push тега"), ("Pushing main and the tag starts the workflow.", "Push ветки main и тега запускает workflow."), [(".github/workflows/release.yml", "tags: [\"v*\"]")]),
        ("rust", "rust", ("engine and server", "движок и сервер"), ("The engine's libraries per platform; the server built and named with the version.", "Библиотеки движка по платформам; сервер собран и назван с версией."),
         [(".github/workflows/release.yml", "run: tools/build_rules.sh ${{ matrix.platforms }}"), (".github/workflows/release.yml", "cd server && cargo build --release")]),
        ("rust", "game", "rules-*", ("The libraries come down into `rules/bin`.", "Библиотеки скачиваются в `rules/bin`."), [(".github/workflows/release.yml", "pattern: rules-*")]),
        ("game", "game", ("export every platform", "экспорт всех платформ"), ("With `RULES_PREBUILT=1`; a failed one shows as an error annotation.", "С `RULES_PREBUILT=1`; неудачная платформа видна как ошибка."),
         [(".github/workflows/release.yml", "if ! RULES_PREBUILT=1 tools/export_all.sh \"$p\" > \"/tmp/export_$p.log\" 2>&1; then")]),
        ("game", "rel", ("game + server-*", "game + server-*"), ("Only for `refs/tags/v*`.", "Только для `refs/tags/v*`."), [(".github/workflows/release.yml", "if: startsWith(github.ref, 'refs/tags/v')")]),
        ("rel", "gh", "GitHub Release", ("Every file of the release.", "Все файлы выпуска."), [(".github/workflows/release.yml", "uses: softprops/action-gh-release@v3")]),
        ("dev", "gh", "build_site.sh --publish", ("The site and the web build, by hand.", "Сайт и веб-версия — вручную."), [("tools/build_site.sh", "git -C \"$WT\" push origin gh-pages")]),
    ],
))


# --- deploy ------------------------------------------------------------------------------------------

COMPS.append(dict(
    id="deploy", name=("Deploy", "Развёртывание"), sub="deploy/ · deploy_server.sh", layer="ops", x=1030, y=20,
    short=("The server goes to a Docker host behind Caddy from a release: a tiny scratch image of the release's Linux binary, the packs, "
           "a backup of the database, a health check and a rollback.",
           "Сервер попадает на Docker-хост за Caddy из выпуска: крошечный образ scratch из Linux-бинарника выпуска, пакеты, резервная копия базы, "
           "проверка здоровья и откат."),
    text=("`tools/deploy_server.sh X.Y.Z` runs on a developer's machine (`DEPLOY_HOST`, `DEPLOY_URL`); the host has a one-time `setup.sh` that installs "
          "`classichs-deploy` with a sudo rule for that one script and adds the domain to Caddy. Alternatives built from source: `server/Dockerfile` "
          "(distroless, the packs inside), `server/docker-compose.yml` (with SeaweedFS as S3) and the plain manifests in `deploy/k8s`.",
          "`tools/deploy_server.sh X.Y.Z` запускается на машине разработчика (`DEPLOY_HOST`, `DEPLOY_URL`); на хосте один раз выполняется `setup.sh`, который "
          "ставит `classichs-deploy` с правилом sudo только для этого скрипта и добавляет домен в Caddy. Варианты со сборкой из исходников: `server/Dockerfile` "
          "(distroless, пакеты внутри), `server/docker-compose.yml` (с SeaweedFS в роли S3) и простые манифесты в `deploy/k8s`."),
    parts=[
        X("ci", 0, 0),
        P("script", "deploy_server.sh", 1, 0, sub="tools/",
          text=("Takes the release's server and packs from the GitHub API, builds the image locally, uploads only changed packs, streams the image over ssh, runs the host script, checks the URL.",
                "Берёт из GitHub API сервер и пакеты выпуска, локально собирает образ, загружает только изменённые пакеты, передаёт образ по ssh, запускает скрипт хоста, проверяет адрес."),
          files=[("tools/deploy_server.sh", "API=https://api.github.com/repos/pycz2/classichs/releases/tags/v$V"), ("tools/deploy_server.sh", "ssh \"$DEPLOY_HOST\" sudo -n /usr/local/sbin/classichs-deploy \"$V\"")]),
        P("image", ("Scratch image", "Образ scratch"), 2, 0, sub="deploy/docker-host/Dockerfile",
          text=("The stripped binary and four libraries from Debian trixie on `scratch`, user 65532, port 7377 — about 10 MB compressed.",
                "Урезанный бинарник и четыре библиотеки из Debian trixie на `scratch`, пользователь 65532, порт 7377 — около 10 МБ в сжатом виде."),
          files=[("deploy/docker-host/Dockerfile", "FROM scratch")]),
        P("setup", "setup.sh", 0, 1, sub=("once, with sudo", "один раз, с sudo"),
          text=("Checks DNS and the Caddy container, makes `/srv/classichs`, installs the deploy script and its sudo rule, adds `<domain> { reverse_proxy classichs:7377 }`.",
                "Проверяет DNS и контейнер Caddy, создаёт `/srv/classichs`, ставит скрипт развёртывания и правило sudo, добавляет `<domain> { reverse_proxy classichs:7377 }`."),
          files=[("deploy/docker-host/setup.sh", "reverse_proxy classichs:7377")]),
        P("host", "classichs-deploy", 1, 1, sub=("on the host", "на хосте"),
          text=("Loads the image, stops the old container, backs up the database (keeps 2), runs the new one, health-checks it from Caddy, rolls back on failure, keeps 2 images.",
                "Загружает образ, останавливает старый контейнер, копирует базу (хранит 2 копии), запускает новый, проверяет его из Caddy, при неудаче откатывает, хранит 2 образа."),
          files=[("deploy/docker-host/classichs-deploy", "docker run -d --name classichs"), ("deploy/docker-host/classichs-deploy", "rolled back to $prev")]),
        P("caddy", "Caddy", 0, 2, sub="TLS · wss://",
          text=("The host's reverse proxy: TLS for the domain, the game over `wss://`, the admin over HTTPS.", "Обратный прокси хоста: TLS для домена, игра по `wss://`, админка по HTTPS."),
          files=["deploy/docker-host/setup.sh"]),
        P("alt", ("From source", "Из исходников"), 2, 1, sub="server/Dockerfile · compose · k8s",
          text=("A distroless image built from the repository with the packs inside; compose with SeaweedFS; k8s: one replica, a PVC, a service, an ingress example.",
                "Образ distroless из репозитория с пакетами внутри; compose с SeaweedFS; k8s: одна реплика, PVC, сервис, пример ingress."),
          files=[("server/Dockerfile", "FROM gcr.io/distroless/cc-debian13:nonroot"), "deploy/k8s/README.md"]),
        P("container", ("Container classichs", "Контейнер classichs"), 1, 2,
          text=("`--listen 0.0.0.0:7377 --db /data/classichs.db --store-dir /data/store --packs-dir /packs --default-pack neon --trust-proxy`, 384 MB of memory.",
                "`--listen 0.0.0.0:7377 --db /data/classichs.db --store-dir /data/store --packs-dir /packs --default-pack neon --trust-proxy`, 384 МБ памяти."),
          files=[("deploy/docker-host/classichs-deploy", "docker run -d --name classichs")]),
        X("server", 2, 2),
    ],
    arrows=[
        E("x_ci", "script", ("release files", "файлы выпуска")),
        E("script", "image", "docker build"),
        E("script", "host", ("ssh, sudo -n", "ssh, sudo -n")),
        E("image", "host", ("image.tar.gz", "image.tar.gz")),
        E("setup", "host", ("installs", "ставит"), dash=True),
        E("setup", "caddy", ("site block", "блок сайта"), dash=True),
        E("host", "container", ("run, health,\nrollback", "запуск, проверка,\nоткат")),
        E("caddy", "container", "proxy :7377"),
        E("container", "x_server", ("is", "это")),
        E("alt", "x_server", ("or", "или"), dash=True),
    ],
    flows=["deploy"],
))

FLOWS.append(dict(
    id="deploy", home="deploy",
    title=("Deploy", "Развёртывание"),
    short=("CI → a release → `deploy_server.sh X.Y.Z` → an image → the host → a health check, or a rollback.",
           "CI → выпуск → `deploy_server.sh X.Y.Z` → образ → хост → проверка здоровья или откат."),
    lanes=[L("gh", "GitHub Release", "ci"), L("dev", "deploy_server.sh", "deploy", ("developer's machine", "машина разработчика")), L("host", ("Host", "Хост"), "deploy", "classichs-deploy"),
           L("ctr", ("Container", "Контейнер"), "server", "classichs"), L("caddy", "Caddy", "deploy")],
    steps=[
        ("dev", "gh", ("assets of vX.Y.Z", "файлы vX.Y.Z"), ("The packs and `ClassicHS-server-*-linux-x86_64`; without the Linux binary it stops.", "Пакеты и `ClassicHS-server-*-linux-x86_64`; без Linux-бинарника — стоп."),
         [("tools/deploy_server.sh", "API=https://api.github.com/repos/pycz2/classichs/releases/tags/v$V")]),
        ("dev", "dev", ("build the image", "собрать образ"), ("linux/amd64 from `deploy/docker-host/Dockerfile`, saved as a gzip.", "linux/amd64 из `deploy/docker-host/Dockerfile`, сохраняется в gzip."),
         [("tools/deploy_server.sh", "docker build -q --platform linux/amd64"), ("tools/deploy_server.sh", "docker save \"classichs-server:$V\"")]),
        ("dev", "host", ("changed packs only", "только изменённые пакеты"), ("SHA-256 against the host's `sha256sum`; uploaded as `.part`, then moved; packs the release lacks are removed.",
                                                                        "SHA-256 против `sha256sum` хоста; загрузка как `.part`, затем перенос; пакеты, которых нет в выпуске, удаляются."),
         [("tools/deploy_server.sh", "scp -q \"$f\" \"$DEPLOY_HOST:classichs/packs/.$n.part\"")]),
        ("dev", "host", ("image over ssh, then the script", "образ по ssh, затем скрипт"), ("The image is streamed into `~/classichs/incoming`, then the host script runs through passwordless sudo allowed for that one script.", "Образ передаётся потоком в `~/classichs/incoming`, затем скрипт хоста запускается через sudo без пароля, разрешённый только для него."),
         [("tools/deploy_server.sh", "ssh \"$DEPLOY_HOST\" sudo -n /usr/local/sbin/classichs-deploy \"$V\"")]),
        ("host", "host", ("load, back up", "загрузить, копия базы"), ("`docker load`; the old container stops; `classichs.db*` copied to `backup-before-<V>`.", "`docker load`; старый контейнер останавливается; `classichs.db*` копируется в `backup-before-<V>`."),
         [("deploy/docker-host/classichs-deploy", "loaded=$(gunzip -c \"$IN\" | docker load"), ("deploy/docker-host/classichs-deploy", "cp -p \"$DATA\"/classichs.db* \"$DATA/backup-before-$V/\"")]),
        ("host", "ctr", "docker run", ("On Caddy's network, the data and packs mounted.", "В сети Caddy, данные и пакеты смонтированы."),
         [("deploy/docker-host/classichs-deploy", "docker run -d --name classichs")]),
        ("caddy", "ctr", ("health: GET /admin", "проверка: GET /admin"), ("Up to 20 tries from inside the Caddy container; a failure prints the logs and reruns the previous image.",
                                                                     "До 20 попыток изнутри контейнера Caddy; при неудаче — журнал и снова запуск прежнего образа."),
         [("deploy/docker-host/classichs-deploy", "docker exec \"$CADDY\" wget -q -O /dev/null http://classichs:7377/admin")]),
        ("dev", "caddy", "curl $DEPLOY_URL/admin", ("OK — the game is at `wss://` on the domain.", "OK — игра доступна по `wss://` на домене."),
         [("tools/deploy_server.sh", "curl -fsS -o /dev/null \"$DEPLOY_URL/admin\"")]),
    ],
))


# --- the whole system ----------------------------------------------------------------------------------

SYSTEM = ("{name} is **a neutral client, a rules engine and game packs**. A game — its rules, cards and their logic in a small Lua, art, sounds, music "
          "and look — is one `.cardpack` file. The **rules engine** in Rust knows only the general mechanics of a card game and runs a pack's card scripts "
          "with **its own Lua interpreter**; it is deterministic and speaks JSON. The same crates run everywhere: inside the game as a GDExtension library "
          "(Windows, macOS, Linux, Android) or WebAssembly (the browser), and inside the game server as a plain dependency. The **Godot client** is a thin "
          "shell: it draws what the engine says and asks it what is legal.\n\n"
          "A game is owned by one of three: **the local engine** (training against the **bots' brain**, the tutorial, the debug table), **two engines in "
          "lockstep** (code play over WebRTC, the hash compared after every move) or **the game server**, which runs the game itself and sends each player "
          "only their own view. The server also keeps accounts, ranks per pack, the Arena, friends, chats, decks and per-game settings, stores packs in S3 "
          "or a folder, has its own bots and an admin panel. Around it all: the tools and tests, the site with the web build, CI that builds every platform, "
          "and a deploy to a Docker host.\n\n"
          "Click any block for its parts, data, protocols and step-by-step flows; every step links to the line of code that does it.",
          "{name} — это **нейтральный клиент, движок правил и пакеты игр**. Игра — её правила, карты и их логика на маленьком Lua, арт, звуки, музыка и "
          "оформление — это один файл `.cardpack`. **Движок правил** на Rust знает только общие механики карточной игры и исполняет скрипты карт пакета "
          "**своим интерпретатором Lua**; он детерминирован и говорит на JSON. Одни и те же крейты работают везде: в игре как библиотека GDExtension "
          "(Windows, macOS, Linux, Android) или WebAssembly (браузер) и на игровом сервере как обычная зависимость. **Клиент на Godot** — тонкая оболочка: "
          "он рисует то, что говорит движок, и спрашивает у него, что законно.\n\n"
          "Партией владеет одно из трёх: **локальный движок** (тренировка против **мозга ботов**, обучение, отладочный стол), **два движка в lockstep** "
          "(игра по коду через WebRTC, хэш сверяется после каждого хода) или **игровой сервер**, который сам ведёт партию и шлёт каждому игроку только его вид. "
          "Ещё сервер хранит аккаунты, ранги по пакетам, Арену, друзей, чаты, колоды и настройки игр, держит пакеты в S3 или папке, у него свои боты и админка. "
          "Вокруг всего этого: инструменты и тесты, сайт с веб-версией, CI, которая собирает все платформы, и развёртывание на Docker-хост.\n\n"
          "Нажмите на любой блок, чтобы увидеть его части, данные, протоколы и пошаговые потоки; каждый шаг ведёт на строку кода, которая его делает.")

ARROWS = [
    E("tools", "packs", "pack.py build", dash=True),
    E("client", "site", ("web export", "веб-экспорт"), dash=True),
    E("ci", "client", ("builds every\nplatform", "собирает все\nплатформы"), dash=True),
    E("ci", "deploy", "GitHub Release", dash=True),
    E("packs", "client", ("cards, texts,\nlook, music", "карты, тексты,\nвид, музыка")),
    E("packs", "bridge", ("rules files", "файлы правил")),
    E("client", "bridge", ("Rules.request\n(local match)", "Rules.request\n(локальная партия)"), both=True),
    E("client", "codeplay", "NetSession", both=True),
    E("codeplay", "peer", ("WebRTC data\nchannel", "канал данных\nWebRTC"), both=True),
    E("client", "serverlink", "ServerLink", both=True),
    E("serverlink", "server", ("WebSocket +\nHTTP /packs", "WebSocket +\nHTTP /packs"), both=True, d="M700 382 H642 V652 H590", lx=642, ly=582),
    E("bridge", "engine", "call_json", both=True),
    E("bridge", "brain", ("think\n(training)", "think\n(тренировка)")),
    E("engine", "lua", ("hooks ⇄ g.*", "хуки ⇄ g.*"), both=True),
    E("brain", "engine", ("clone + apply", "копия + ход")),
    E("server", "engine", ("the same crate", "тот же крейт")),
    E("bots", "brain", "decide"),
    E("bots", "server", ("in-memory\nWebSocket", "WebSocket\nв памяти")),
    E("server", "storage", ("SQLite,\n.cardpack", "SQLite,\n.cardpack"), both=True),
    E("admin", "server", "/admin", both=True, d="M1137 694 V730 H478 V700", lx=810, ly=730),
    E("deploy", "server", ("image → host", "образ → хост"), dash=True, d="M1245 57 H1270 V604 H540 V614", lx=1150, ly=432),
]
