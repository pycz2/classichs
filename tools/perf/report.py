#!/usr/bin/env python3
"""The performance harness's report: an HTML page of charts and tables from runs of tools/perf/web_run.mjs
(godot.csv, chrome.csv) and desktop runs (a PerfLog CSV), plus a findings fragment (HTML) written by hand.

Usage: python3 tools/perf/report.py --out ~/ClassicHS-local/perf-report/index.html \
         --run "Web=/tmp/classichs-perf/web-run" --run "Desktop=/path/perf-....csv" [--findings findings.html]
A run is a directory (godot.csv, chrome.csv inside) or a PerfLog CSV file.
"""
import argparse
import csv
import html
import json
import math
import os
import statistics

# what is charted, by group: (column, title, unit)
GODOT = [
    ("Кадры", [("fps", "Кадров в секунду", "fps"), ("process_ms", "Самый долгий шаг обработки за секунду (TIME_PROCESS: скрипты без отрисовки)", "мс"),
                ("worst_ms", "Самый долгий кадр за секунду", "мс"), ("slow_frames", "Кадров дольше 50 мс за секунду", "")]),
    ("Объекты и узлы", [("objects", "Объекты", ""), ("nodes", "Узлы (счёт Godot)", ""), ("orphans", "Узлы-сироты", ""),
                           ("resources", "Ресурсы", ""), ("tree_nodes", "Узлы в дереве (обход)", ""),
                           ("controls", "Control в дереве", "")]),
    ("Долгоживущее состояние", [("tweens", "Твины", ""), ("timers", "Узлы Timer", ""), ("audio_players", "Аудиоплееры", ""),
                          ("conns", "Подключения сигналов (дерево, ServerLink, Sound, main)", ""), ("sessions", "Узлы ServerSession", ""),
                          ("link_games", "Записи ServerLink._games", ""), ("link_children", "Дети ServerLink", ""),
                          ("history", "Записи истории открытой партии", ""), ("tour_cache", "Записи TournamentsView.cache", ""),
                          ("heard", "Записи Sound.heard", ""), ("art_textures", "Записи Art._textures", ""),
                          ("palette_frames", "Записи Palette._frames", "")]),
    ("Память", [("mem_mb", "Статическая память Godot (только отладочные сборки)", "МБ"), ("sound_mb", "Декодированный звук в кэше", "МБ"),
                ("sound_streams", "Звуков в кэше", ""), ("texture_mb", "Память текстур", "МБ"), ("video_mb", "Видеопамять", "МБ"),
                ("js_heap_mb", "Память страницы (performance.memory, веб)", "МБ")]),
    ("Горячие места (мс за секунду игры)", [("rules_ms", "Запросы к движку правил", "мс/с"), ("take_state_ms", "Match._take_state", "мс/с"),
                ("on_changed_ms", "MatchView._on_changed", "мс/с"), ("layout_ms", "MatchView.refresh (раскладка)", "мс/с"),
                ("strip_ms", "HistoryStrip.update_from", "мс/с"), ("t_page_ms", "TournamentsView._build_page", "мс/с"),
                ("t_list_ms", "TournamentsView._build_list", "мс/с"), ("bracket_ms", "TournamentBracket._build", "мс/с"),
                ("ws_parse_ms", "Разбор JSON от сервера", "мс/с"), ("opus_ms", "Декодирование Opus (главный поток)", "мс/с")]),
    ("Сообщения и перерисовка", [("ws_in", "Сообщений от сервера", "в с"), ("ws_in_kb", "Данных от сервера", "КБ/с"),
                ("t_push", "Сообщений tournament", "в с"), ("listrow_draw", "Отрисовок строк списка турниров", "в с"),
                ("draw_calls", "Вызовов отрисовки за кадр", "")]),
]
CHROME = [("JSHeapUsedSize", "Куча JS (Chrome, JSHeapUsedSize)", "МБ", 1 / 1048576), ("Nodes", "Узлы DOM", "", 1),
          ("JSEventListeners", "Обработчики событий JS", "", 1), ("wasm1_mb", "Самая большая память WebAssembly (Godot)", "МБ", 1),
          ("wasm_total_mb", "Вся память WebAssembly", "МБ", 1), ("busy_pct", "Загрузка главного потока (TaskDuration)", "%", 1),
          ("audio_buffers_mb", "Живые буферы Web Audio (AudioBuffer, после сборки мусора)", "МБ", 1),
          ("audio_buffers", "Живые буферы Web Audio, штук", "", 1)]
COLORS = ["var(--s1)", "var(--s2)", "var(--s3)"]


def num(v):
    try:
        x = float(v)
        return x if math.isfinite(x) else None
    except (TypeError, ValueError):
        return None


def load_run(spec):
    name, path = spec.split("=", 1)
    path = os.path.expanduser(path)
    godot = os.path.join(path, "godot.csv") if os.path.isdir(path) else path
    rows = list(csv.DictReader(open(godot))) if os.path.exists(godot) else []
    chrome = []
    cpath = os.path.join(path, "chrome.csv") if os.path.isdir(path) else ""
    if cpath and os.path.exists(cpath):
        chrome = list(csv.DictReader(open(cpath)))
        prev = None
        for r in chrome:  # TaskDuration is seconds since start: the share of the 10 s busy
            m, td = num(r["minute"]), num(r["TaskDuration"])
            r["busy_pct"] = "" if prev is None or m == prev[0] else str(100 * (td - prev[1]) / ((m - prev[0]) * 60))
            prev = (m, td)
    probe = os.path.join(path, "probe.jsonl") if os.path.isdir(path) else ""
    if chrome and probe and os.path.exists(probe):  # tools/perf/probe.mjs taken by hand: on the run's minutes
        from datetime import datetime
        start = datetime.fromisoformat(chrome[0]["t"].replace("Z", "+00:00")).timestamp() - 60 * num(chrome[0]["minute"])
        for line in open(probe):
            try:
                p = json.loads(line)
            except ValueError:
                continue
            m = (datetime.fromisoformat(p["time"].replace("Z", "+00:00")).timestamp() - start) / 60
            chrome.append({"minute": str(m), "audio_buffers": str(p["AudioBuffer"]["count"]), "audio_buffers_mb": str(p["AudioBuffer"]["mb"])})
    return {"name": name, "rows": rows, "chrome": chrome}


def per_minute(rows, col, minute_of):
    """Mean of a column per minute: [(minute, value)]."""
    buckets = {}
    for r in rows:
        m, v = minute_of(r), num(r.get(col))
        if m is None or v is None:
            continue
        buckets.setdefault(int(m), []).append(v)
    return [(m, statistics.fmean(v)) for m, v in sorted(buckets.items())]


def chart(title, unit, series, w=420, h=170):
    """An inline SVG line chart: series = [(name, color, [(x, y)])]; one y axis, minutes on x."""
    pts = [p for _, _, s in series for p in s]
    if not pts:
        return ""
    x1 = max(1, max(p[0] for p in pts))
    ys = [p[1] for p in pts]
    y0, y1 = min(0.0, min(ys)), max(ys)
    if y1 == y0:
        y1 = y0 + 1
    L, R, T, B = 46, 10, 10, 26
    sx = lambda x: L + (w - L - R) * x / x1
    sy = lambda y: T + (h - T - B) * (1 - (y - y0) / (y1 - y0))
    out = [f'<figure class="chart"><figcaption>{html.escape(title)}{" (" + unit + ")" if unit else ""}</figcaption>',
           f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="{html.escape(title)}" data-x1="{x1}" data-y0="{y0}" data-y1="{y1}">']
    for i in range(5):
        y = y0 + (y1 - y0) * i / 4
        out.append(f'<line class="grid" x1="{L}" x2="{w - R}" y1="{sy(y):.1f}" y2="{sy(y):.1f}"/>'
                   f'<text class="tick" x="{L - 6}" y="{sy(y) + 4:.1f}" text-anchor="end">{fmt(y)}</text>')
    for i in range(0, int(x1) + 1, max(1, int(x1) // 6)):
        out.append(f'<text class="tick" x="{sx(i):.1f}" y="{h - 8}" text-anchor="middle">{i}</text>')
    data = []
    for name, color, s in series:
        if not s:
            continue
        d = " ".join(f'{"M" if k == 0 else "L"}{sx(x):.1f},{sy(y):.1f}' for k, (x, y) in enumerate(s))
        out.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="2" stroke-linejoin="round"/>')
        data.append({"name": name, "color": color, "pts": [[x, round(y, 2)] for x, y in s]})
    out.append(f'<line class="cross" x1="0" x2="0" y1="{T}" y2="{h - B}" visibility="hidden"/>')
    out.append(f'<rect class="hit" x="{L}" y="{T}" width="{w - L - R}" height="{h - T - B}" fill="transparent"/>')
    out.append(f'</svg><script type="application/json">{json.dumps(data)}</script></figure>')
    return "".join(out)


def fmt(v):
    if abs(v) >= 1000:
        return f"{v / 1000:.1f}k"
    return f"{v:.0f}" if abs(v) >= 10 or v == int(v) else f"{v:.1f}"


def minute_godot(r):
    u = num(r.get("uptime_s"))
    return None if u is None else u / 60


def screen_table(runs):
    """Per run and screen: seconds on it, median FPS and script time in the first and the last third."""
    out = ['<table><thead><tr><th>Прогон</th><th>Экран</th><th>Секунд</th><th>FPS, первая треть</th><th>FPS, последняя треть</th>'
           '<th>Шаг обработки, мс, первая треть</th><th>Шаг обработки, мс, последняя треть</th><th>Худший кадр, мс, последняя треть</th></tr></thead><tbody>']
    for run in runs:
        rows = run["rows"]
        if not rows:
            continue
        end = max(num(r["uptime_s"]) or 0 for r in rows)
        screens = {}
        for r in rows:
            screens.setdefault(r.get("screen") or "?", []).append(r)
        for s, rs in sorted(screens.items(), key=lambda kv: -len(kv[1])):
            if len(rs) < 30:
                continue
            first = [r for r in rs if (num(r["uptime_s"]) or 0) < end / 3]
            last = [r for r in rs if (num(r["uptime_s"]) or 0) >= end * 2 / 3]
            med = lambda xs, c: f'{statistics.median([num(r[c]) for r in xs if num(r[c]) is not None]):.1f}' if xs else "–"
            out.append(f'<tr><td>{html.escape(run["name"])}</td><td>{html.escape(s)}</td><td>{len(rs)}</td><td>{med(first, "fps")}</td>'
                       f'<td>{med(last, "fps")}</td><td>{med(first, "process_ms")}</td><td>{med(last, "process_ms")}</td>'
                       f'<td>{med(last, "worst_ms")}</td></tr>')
    out.append("</tbody></table>")
    return "".join(out)


def growth_table(runs):
    """Each gauge's value in the first and the last minute of each run."""
    cols = [c for _, items in GODOT for c, _, _ in items]
    out = ['<table><thead><tr><th>Счётчик</th>' + "".join(f'<th>{html.escape(r["name"])}: начало</th><th>{html.escape(r["name"])}: конец</th>'
                                                          for r in runs if r["rows"]) + '</tr></thead><tbody>']
    for c in cols:
        cells = []
        for run in runs:
            if not run["rows"]:
                continue
            s = per_minute(run["rows"], c, minute_godot)
            cells.append(f"<td>{fmt(s[0][1]) if s else '–'}</td><td>{fmt(s[-1][1]) if s else '–'}</td>")
        out.append(f"<tr><td><code>{c}</code></td>{''.join(cells)}</tr>")
    out.append("</tbody></table>")
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--run", action="append", default=[])
    ap.add_argument("--findings", default="")
    ap.add_argument("--title", default="Classic HS: долгий турнир под профилировщиком")
    a = ap.parse_args()
    runs = [load_run(s) for s in a.run]
    findings = open(a.findings).read() if a.findings else ""
    legend = "".join(f'<span class="key"><i style="background:{COLORS[i]}"></i>{html.escape(r["name"])}</span>' for i, r in enumerate(runs))
    sections = []
    for group, items in GODOT:
        charts = []
        for col, title, unit in items:
            series = [(r["name"], COLORS[i], per_minute(r["rows"], col, minute_godot)) for i, r in enumerate(runs)]
            if all(not s or max(abs(y) for _, y in s) == 0 for _, _, s in series):
                continue
            charts.append(chart(title, unit, series))
        if charts:
            sections.append(f'<h3>{html.escape(group)}</h3><div class="grid">{"".join(charts)}</div>')
    chrome_runs = [(i, r) for i, r in enumerate(runs) if r["chrome"]]
    if chrome_runs:
        charts = []
        for col, title, unit, k in CHROME:
            series = [(r["name"], COLORS[i], [(p[0], p[1] * k) for p in per_minute(r["chrome"], col, lambda x: num(x["minute"]))])
                      for i, r in chrome_runs]
            charts.append(chart(title, unit, series))
        sections.append(f'<h3>Chrome (каждые 10 с)</h3><div class="grid">{"".join(charts)}</div>')
    page = TEMPLATE.replace("%TITLE%", html.escape(a.title)).replace("%FINDINGS%", findings).replace("%LEGEND%", legend) \
        .replace("%CHARTS%", "".join(sections)).replace("%SCREENS%", screen_table(runs)).replace("%GROWTH%", growth_table(runs))
    os.makedirs(os.path.dirname(os.path.expanduser(a.out)), exist_ok=True)
    open(os.path.expanduser(a.out), "w").write(page)
    print("report:", os.path.expanduser(a.out))


TEMPLATE = """<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Classic HS performance</title>
<style>
:root { color-scheme: light; --bg: #fcfcfb; --card: #ffffff; --ink: #0b0b0b; --ink2: #52514e; --muted: #8a8984; --line: #e4e3df;
  --s1: #2a78d6; --s2: #eb6834; --s3: #1baf7a; --hi: #fff4d6; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { color-scheme: dark; --bg: #1a1a19; --card: #222220;
  --ink: #f0efec; --ink2: #c3c2b7; --muted: #8f8e86; --line: #3a3936; --s1: #3987e5; --s2: #d95926; --s3: #199e70; --hi: #3a3220; } }
:root[data-theme="dark"] { color-scheme: dark; --bg: #1a1a19; --card: #222220; --ink: #f0efec; --ink2: #c3c2b7; --muted: #8f8e86;
  --line: #3a3936; --s1: #3987e5; --s2: #d95926; --s3: #199e70; --hi: #3a3220; }
body { background: var(--bg); color: var(--ink); font: 15px/1.55 system-ui, -apple-system, sans-serif; margin: 0; }
main { max-width: 1320px; margin: 0 auto; padding: 24px 16px 64px; }
h1 { font-size: 26px; margin: 0 0 4px; } h2 { margin-top: 40px; border-bottom: 1px solid var(--line); padding-bottom: 6px; }
h3 { margin: 28px 0 8px; color: var(--ink2); }
.sub { color: var(--ink2); margin: 0 0 20px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 400px), 1fr)); gap: 14px; }
.chart { background: var(--card); border: 1px solid var(--line); border-radius: 10px; margin: 0; padding: 10px 10px 4px; position: relative; }
.chart figcaption { font-size: 13px; color: var(--ink2); margin-bottom: 4px; }
.chart svg { width: 100%; height: auto; display: block; }
.grid line.grid, svg line.grid { stroke: var(--line); stroke-width: 1; }
svg text.tick { fill: var(--muted); font-size: 10px; }
svg line.cross { stroke: var(--muted); stroke-width: 1; }
.tip { position: absolute; pointer-events: none; background: var(--card); border: 1px solid var(--line); border-radius: 6px;
  padding: 4px 8px; font-size: 12px; box-shadow: 0 2px 8px rgba(0,0,0,.15); white-space: nowrap; z-index: 2; }
.tip i, .key i { display: inline-block; width: 10px; height: 3px; border-radius: 2px; vertical-align: middle; margin-right: 5px; }
.legend { position: sticky; top: 0; background: var(--bg); padding: 8px 0; z-index: 3; border-bottom: 1px solid var(--line); }
.key { margin-right: 18px; color: var(--ink2); font-size: 14px; }
table { border-collapse: collapse; width: 100%; font-size: 13px; margin: 8px 0 16px; display: block; overflow-x: auto; }
th, td { border-bottom: 1px solid var(--line); padding: 5px 8px; text-align: left; vertical-align: top; }
th { color: var(--ink2); font-weight: 600; }
code { font-size: 12.5px; background: var(--line); padding: 1px 4px; border-radius: 4px; }
pre { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 10px; overflow-x: auto; font-size: 12.5px; }
.suspect { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 12px 16px; margin: 12px 0; }
.suspect h4 { margin: 0 0 6px; font-size: 17px; }
.rank { display: inline-block; min-width: 26px; text-align: center; border-radius: 6px; background: var(--hi); margin-right: 6px; }
.tag { font-size: 12px; color: var(--ink2); border: 1px solid var(--line); border-radius: 10px; padding: 0 8px; margin-left: 6px; }
</style></head><body><main>
<h1>%TITLE%</h1>
%FINDINGS%
<h2>Графики по минутам</h2>
<div class="legend">%LEGEND% <span class="key">ось X: минуты с начала прогона; значение: среднее за минуту</span></div>
%CHARTS%
<h2>Экраны: начало и конец прогона</h2>
%SCREENS%
<h2>Все счётчики: первая и последняя минута</h2>
%GROWTH%
</main>
<script>
for (const fig of document.querySelectorAll(".chart")) {
  const svg = fig.querySelector("svg"), data = JSON.parse(fig.querySelector("script").textContent);
  const vb = svg.viewBox.baseVal, x1 = +svg.dataset.x1, L = 46, R = 10;
  const tip = document.createElement("div"); tip.className = "tip"; tip.hidden = true; fig.appendChild(tip);
  const cross = svg.querySelector(".cross");
  svg.querySelector(".hit").addEventListener("mousemove", (e) => {
    const p = svg.createSVGPoint(); p.x = e.clientX; p.y = e.clientY;
    const q = p.matrixTransform(svg.getScreenCTM().inverse());
    const m = Math.round((q.x - L) / (vb.width - L - R) * x1);
    const lines = data.map((s) => { const pt = s.pts.find((v) => v[0] === m); return pt ? `<i style="background:${s.color}"></i>${s.name}: ${pt[1]}` : ""; }).filter(Boolean);
    if (!lines.length) { tip.hidden = true; return; }
    const x = L + (vb.width - L - R) * m / x1;
    cross.setAttribute("x1", x); cross.setAttribute("x2", x); cross.setAttribute("visibility", "visible");
    tip.innerHTML = `минута ${m}<br>` + lines.join("<br>"); tip.hidden = false;
    const r = fig.getBoundingClientRect();
    tip.style.left = Math.min(e.clientX - r.left + 12, r.width - tip.offsetWidth - 4) + "px"; tip.style.top = (e.clientY - r.top + 12) + "px";
  });
  svg.querySelector(".hit").addEventListener("mouseleave", () => { tip.hidden = true; cross.setAttribute("visibility", "hidden"); });
}
</script></body></html>
"""

if __name__ == "__main__":
    main()
