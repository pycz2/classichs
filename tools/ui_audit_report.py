#!/usr/bin/env python3
"""The UI audit's local report: ~/ClassicHS-local/ui-audit/index.html from the findings files
~/ClassicHS-local/ui-audit/findings/*.json (each a list of findings) and the shots under shots/.

A finding: {screen, title, kind, severity (high|medium|low), lang (ru|en|both), size ("1280x720", "all" ...),
shot ("shots/<group>/<file>.jpg"), box [x, y, w, h] (shot pixels; optional), what, repro, checked (true: looked
at by eye, false: the layout script only; default true), more?: [{shot, box?, caption?}]}. Kinds: overlap,
out_of_box, cut, off_window, contrast, wrong_language, missing_translation, small_text, other.
The page lets the owner mark each finding "fix" or "false" (with a note), kept in the browser (localStorage by
the finding's stable id), exported/imported as JSON, and builds a prompt for a coding agent from the "fix" ones.
Optional: ~/ClassicHS-local/ui-audit/notes.html (put under the title).
Usage: tools/ui_audit_report.py
"""
import hashlib, html, json, struct, sys
from pathlib import Path

BASE = Path.home() / "ClassicHS-local" / "ui-audit"
KINDS = {"overlap": "наложение", "out_of_box": "текст вне рамки", "cut": "обрезанный текст",
         "off_window": "за краем окна", "contrast": "плохой контраст", "wrong_language": "не тот язык",
         "missing_translation": "нет перевода", "small_text": "мелкий текст", "other": "другое"}
LANGS = {"ru": "русский", "en": "английский", "both": "оба языка"}
SEV = {"high": "высокая", "medium": "средняя", "low": "низкая"}


def jpeg_size(p: Path):
    b = p.read_bytes()
    i = 2
    while i < len(b):
        if b[i] != 0xFF:
            i += 1
            continue
        mark = b[i + 1]
        if mark in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", b[i + 5:i + 9])
            return w, h
        i += 2 + struct.unpack(">H", b[i + 2:i + 4])[0]
    return 1280, 720


def figure(shot: str, box, caption=""):
    p = BASE / shot
    if not p.exists():
        return f'<p class="miss">нет снимка {html.escape(shot)}</p>'
    w, h = jpeg_size(p)
    out = []
    if box:
        x, y, bw, bh = box
        m = max(40, int(max(bw, bh) * 0.35))
        cx, cy = max(0, x - m), max(0, y - m)
        cw, ch = max(1, min(w - cx, bw + 2 * m)), max(1, min(h - cy, bh + 2 * m))
        bx = 0 if cw >= w else cx / (w - cw) * 100
        by = 0 if ch >= h else cy / (h - ch) * 100
        out.append(f'<div class="crop" style="aspect-ratio:{cw}/{ch};max-width:{min(int(cw * 1.4), 520)}px;'
                   f'background-image:url(\'{shot}\');background-size:{w / cw * 100:.3f}% auto;'
                   f'background-position:{bx:.3f}% {by:.3f}%"><i style="left:{(x - cx) / cw * 100:.2f}%;'
                   f'top:{(y - cy) / ch * 100:.2f}%;width:{bw / cw * 100:.2f}%;height:{bh / ch * 100:.2f}%"></i></div>')
    mark = (f'<i style="left:{box[0] / w * 100:.2f}%;top:{box[1] / h * 100:.2f}%;width:{box[2] / w * 100:.2f}%;'
            f'height:{box[3] / h * 100:.2f}%"></i>') if box else ""
    out.append(f'<a class="full" href="{shot}" target="_blank" style="max-width:{min(w, 640)}px">'
               f'<img loading="lazy" src="{shot}" alt="">{mark}</a>')
    cap = f'<figcaption>{html.escape(caption)}</figcaption>' if caption else ""
    return f'<figure>{"".join(out)}{cap}</figure>'


STYLE = """
:root{--bg:#14161b;--card:#1d2027;--line:#2c313b;--text:#e6e8ec;--dim:#9aa3b2;--hi:#ff5d5d;--mid:#f0b54a;--lo:#6fb4ff;--acc:#8fd18f}
*{box-sizing:border-box}p,h3{overflow-wrap:anywhere}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1100px;margin:0 auto;padding:16px}h1{font-size:26px;margin:8px 0}
h2{margin:32px 0 8px;font-size:21px;border-bottom:1px solid var(--line);padding-bottom:4px}
h3{margin:6px 0;font-size:17px}a{color:var(--lo)}p{margin:6px 0}.dim{color:var(--dim)}
table{border-collapse:collapse;width:100%;font-size:15px}td,th{border-bottom:1px solid var(--line);padding:4px 8px;text-align:left}
td.n,th.n{text-align:right;width:70px}td.high{color:var(--hi)}td.medium{color:var(--mid)}td.low{color:var(--lo)}tr.tot td{font-weight:600}
.filters{position:sticky;top:0;background:var(--bg);padding:8px 0;display:flex;flex-wrap:wrap;gap:8px 16px;z-index:2;border-bottom:1px solid var(--line)}
select,input[type=text],button,textarea{background:var(--card);color:var(--text);border:1px solid var(--line);border-radius:6px;padding:4px 8px;font-size:15px;font-family:inherit}
button{cursor:pointer}button:hover{border-color:var(--dim)}
.f{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px;margin:12px 0}
.f[data-choice=fix]{border-color:#b0524a}.f[data-choice=false]{border-color:#3f6b45;opacity:.7}
.f header{display:flex;flex-wrap:wrap;gap:6px;align-items:center}.num{margin-left:auto;color:var(--dim)}
.sev,.tag{font-size:13px;padding:1px 8px;border-radius:10px;border:1px solid var(--line)}
.tag.ok{color:var(--acc)}.tag.warn{color:var(--mid);border-style:dashed}
.sev.high{background:#5a1f22;color:#ffd0d0}.sev.medium{background:#5a4415;color:#ffe9bd}.sev.low{background:#1d3a5c;color:#d4e8ff}
.repro{color:var(--dim);font-size:15px}
figure{margin:10px 0;display:flex;flex-wrap:wrap;gap:10px;align-items:flex-start}figcaption{flex-basis:100%;color:var(--dim);font-size:14px}
.crop{position:relative;flex:1 1 260px;background-repeat:no-repeat;border-radius:6px;border:1px solid var(--line)}
.full{position:relative;display:block;flex:1 1 300px}.full img{width:100%;display:block;border-radius:6px}
i{position:absolute;border:3px solid #ff2a2a;border-radius:3px;box-shadow:0 0 0 1px #000}
.miss{color:var(--hi)}.notes{background:var(--card);border-radius:10px;padding:8px 16px;border:1px solid var(--line)}
.triage{display:flex;flex-wrap:wrap;gap:8px 18px;align-items:center;border-top:1px solid var(--line);padding-top:10px;margin-top:6px}
.triage label{cursor:pointer;white-space:nowrap}.triage .note{flex:1 1 220px;min-width:0}
.bar{display:flex;flex-wrap:wrap;gap:8px 12px;align-items:center;margin:10px 0}.cnt b{font-size:18px}
#promptText{width:100%;min-height:260px;margin-top:8px;font:13px/1.45 ui-monospace,Menlo,monospace}#promptBox{display:none}
"""

SCRIPT = r"""<script>
const DATA = __DATA__;
const KEY = 'classichs-ui-audit-choices';
let choices = {};
try { choices = JSON.parse(localStorage.getItem(KEY) || '{}') || {}; } catch (e) { choices = {}; }
function save() { try { localStorage.setItem(KEY, JSON.stringify(choices)); } catch (e) {} }
const arts = [...document.querySelectorAll('.f')];
const sels = [...document.querySelectorAll('select[data-f]')];
function show() {
  let fix = 0, no = 0;
  arts.forEach(a => {
    const c = choices[a.dataset.id] || {};
    a.dataset.choice = c.choice || '';
    a.querySelectorAll('input[type=radio]').forEach(r => r.checked = r.value === c.choice);
    const note = a.querySelector('.note');
    if (document.activeElement !== note) note.value = c.note || '';
    if (c.choice === 'fix') fix++; else if (c.choice === 'false') no++;
  });
  document.getElementById('nFix').textContent = fix;
  document.getElementById('nFalse').textContent = no;
  document.getElementById('nNone').textContent = arts.length - fix - no;
  apply();
}
function apply() {
  let n = 0;
  arts.forEach(f => {
    const ok = sels.every(s => {
      const v = s.value, k = s.dataset.f, d = k === 'choice' ? (f.dataset.choice || 'none') : f.dataset[k];
      return !v || d === v || (k === 'lang' && d === 'both') || (k === 'size' && d === 'all');
    });
    f.style.display = ok ? '' : 'none';
    if (ok) n++;
  });
  document.querySelectorAll('section').forEach(s => {
    const fs = [...s.querySelectorAll('.f')];
    if (fs.length) s.style.display = fs.some(f => f.style.display !== 'none') ? '' : 'none';
  });
  document.getElementById('shown').textContent = 'показано: ' + n;
}
arts.forEach(a => {
  const id = a.dataset.id;
  a.querySelectorAll('input[type=radio]').forEach(r => r.addEventListener('change', () => {
    choices[id] = Object.assign({}, choices[id], {choice: r.value}); save(); show();
  }));
  a.querySelector('.note').addEventListener('input', e => {
    choices[id] = Object.assign({}, choices[id], {note: e.target.value}); save();
  });
});
sels.forEach(s => s.addEventListener('change', apply));
const msg = t => { document.getElementById('msg').textContent = t; };
document.getElementById('bReset').addEventListener('click', () => {
  if (!confirm('Сбросить все отметки и заметки?')) return;
  choices = {}; save(); show(); msg('Отметки сброшены');
});
document.getElementById('bExport').addEventListener('click', () => {
  const blob = new Blob([JSON.stringify(choices, null, 1)], {type: 'application/json'});
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob); a.download = 'ui-audit-choices.json';
  document.body.appendChild(a); a.click(); a.remove();
});
const fileIn = document.getElementById('fImport');
document.getElementById('bImport').addEventListener('click', () => fileIn.click());
fileIn.addEventListener('change', () => {
  const f = fileIn.files[0]; if (!f) return;
  f.text().then(t => {
    try {
      const got = JSON.parse(t); let n = 0;
      for (const [k, v] of Object.entries(got)) if (DATA[k] && v && typeof v === 'object') { choices[k] = v; n++; }
      save(); show(); msg('Загружено отметок: ' + n);
    } catch (e) { msg('Это не файл с отметками'); }
    fileIn.value = '';
  });
});
function boxText(b) { return b ? `x=${b[0]}, y=${b[1]}, ширина ${b[2]}, высота ${b[3]} (в пикселях снимка)` : 'не указана'; }
document.getElementById('bPrompt').addEventListener('click', () => {
  const ids = arts.map(a => a.dataset.id).filter(id => (choices[id] || {}).choice === 'fix');
  const box = document.getElementById('promptBox');
  box.style.display = 'block';
  const out = document.getElementById('promptText');
  if (!ids.length) { out.value = 'Нет находок с отметкой «Исправить».'; return; }
  const lines = [
    'Исправь в клиенте Classic Heroes Showdown (Godot 4, папка ui/) недочёты интерфейса из проверки экранов (шаг 13 плана дополнений).',
    'Их ' + ids.length + '. По каждому: экран, язык, размер окна, что не так, как повторить, снимок и рамка с проблемой на нём.', ''];
  ids.forEach((id, i) => {
    const d = DATA[id], c = choices[id] || {};
    lines.push(`${i + 1}. ${d.screen}: ${d.title}`);
    lines.push(`   Важность: ${d.severity}. Вид: ${d.kind}. Язык: ${d.lang}. Размер окна: ${d.size}.`);
    lines.push(`   Что не так: ${d.what}`);
    lines.push(`   Как повторить: ${d.repro}`);
    lines.push(`   Снимок: ${d.shot}`);
    lines.push(`   Рамка: ${boxText(d.box)}`);
    (d.more || []).forEach(m => lines.push(`   Ещё снимок: ${m.shot}${m.caption ? ' (' + m.caption + ')' : ''}, рамка: ${boxText(m.box)}`));
    if (c.note && c.note.trim()) lines.push(`   Заметка владельца: ${c.note.trim()}`);
    lines.push('');
  });
  lines.push('Правила:',
    '- Исправляй вёрстку: размеры, переносы, прокрутку, положение. Смысл текстов не меняй; если текст не помещается, сначала ищи место, перенос или прокрутку, а не сокращение.',
    '- Проверь каждый экран на русском и английском, в окне 1280×720 и в размерах телефона 844×390 и 390×844: tools/ui_audit.py <группа> --only <снимок>.',
    '- Сделай снимки до и после для каждой правки и покажи их.',
    '- Все тесты должны пройти: ./run_tests.sh (сначала быстрый test_smoke.gd), для движка cargo nextest run --release в rust/ и server/.',
    '- Пиши код по стилю проекта, без лишних абстракций; коммить на своей ветке.');
  out.value = lines.join('\n');
  out.scrollIntoView({behavior: 'smooth', block: 'center'});
});
document.getElementById('bCopy').addEventListener('click', () => {
  const out = document.getElementById('promptText');
  const done = () => { document.getElementById('copied').textContent = 'Скопировано'; };
  if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(out.value).then(done, () => { out.select(); document.execCommand('copy'); done(); });
  else { out.select(); document.execCommand('copy'); done(); }
});
show();
</script></body></html>"""


def main() -> int:
    title = "Проверка экранов клиента"
    findings = []
    for f in sorted((BASE / "findings").glob("*.json")):
        for x in json.loads(f.read_text()):
            x.setdefault("group", f.stem)
            findings.append(x)
    order = {"high": 0, "medium": 1, "low": 2}
    findings.sort(key=lambda x: (x["screen"], order.get(x["severity"], 3)))
    screens = []
    for x in findings:
        if x["screen"] not in screens:
            screens.append(x["screen"])
    notes = (BASE / "notes.html").read_text() if (BASE / "notes.html").exists() else ""

    rows = []
    tot = {"high": 0, "medium": 0, "low": 0}
    for s in screens:
        c = {k: sum(1 for x in findings if x["screen"] == s and x["severity"] == k) for k in tot}
        for k in tot:
            tot[k] += c[k]
        sid = "s-" + str(screens.index(s))
        rows.append(f'<tr><td><a href="#{sid}">{html.escape(s)}</a></td>' +
                    "".join(f'<td class="n {k}">{c[k] or ""}</td>' for k in tot) + f'<td class="n">{sum(c.values())}</td></tr>')
    rows.append('<tr class="tot"><td>Всего</td>' + "".join(f'<td class="n {k}">{tot[k]}</td>' for k in tot) +
                f'<td class="n">{sum(tot.values())}</td></tr>')

    langs = sorted({x["lang"] for x in findings})
    sizes = sorted({x["size"] for x in findings})
    kinds = sorted({x["kind"] for x in findings})
    sel = lambda name, label, vals, names=None: (f'<label>{label} <select data-f="{name}"><option value="">все</option>' +
        "".join(f'<option value="{v}">{html.escape((names or {}).get(v, v))}</option>' for v in vals) + '</select></label>')

    body = []
    data = {}
    n = 0
    for s in screens:
        sid = "s-" + str(screens.index(s))
        body.append(f'<section id="{sid}"><h2>{html.escape(s)}</h2>')
        for x in findings:
            if x["screen"] != s:
                continue
            n += 1
            fid = hashlib.sha1("|".join([x["group"], x["screen"], x["title"], x["shot"]]).encode()).hexdigest()[:12]
            checked = "yes" if x.get("checked", True) else "no"
            size = "все размеры" if x["size"] == "all" else x["size"]
            data[fid] = {"screen": x["screen"], "title": x["title"], "lang": LANGS.get(x["lang"], x["lang"]), "size": size,
                         "kind": KINDS.get(x["kind"], x["kind"]), "severity": SEV.get(x["severity"], x["severity"]),
                         "what": x["what"], "repro": x["repro"], "shot": str(BASE / x["shot"]), "box": x.get("box"),
                         "more": [{"shot": str(BASE / o["shot"]), "box": o.get("box"), "caption": o.get("caption", "")}
                                  for o in x.get("more", [])]}
            figs = figure(x["shot"], x.get("box")) + "".join(figure(o["shot"], o.get("box"), o.get("caption", "")) for o in x.get("more", []))
            body.append(
                f'<article class="f" id="f-{fid}" data-id="{fid}" data-lang="{x["lang"]}" data-size="{x["size"]}" '
                f'data-sev="{x["severity"]}" data-kind="{x["kind"]}" data-checked="{checked}" data-choice="">'
                f'<header><span class="sev {x["severity"]}">{SEV.get(x["severity"], x["severity"])}</span>'
                f'<span class="tag">{KINDS.get(x["kind"], x["kind"])}</span><span class="tag">{LANGS.get(x["lang"], x["lang"])}</span>'
                f'<span class="tag">{html.escape(size)}</span>'
                f'<span class="tag {"ok" if checked == "yes" else "warn"}">{"проверено глазами" if checked == "yes" else "не проверено глазами"}</span>'
                f'<span class="num">#{n}</span></header>'
                f'<h3>{html.escape(x["title"])}</h3><p>{html.escape(x["what"])}</p>'
                f'<p class="repro"><b>Как повторить:</b> {html.escape(x["repro"])}</p>{figs}'
                f'<div class="triage"><label><input type="radio" name="c-{fid}" value="fix"> Исправить</label>'
                f'<label><input type="radio" name="c-{fid}" value="false"> Ложная / так и надо</label>'
                f'<input type="text" class="note" placeholder="Заметка (по желанию)" maxlength="300" aria-label="Заметка"></div></article>')
        body.append('</section>')

    filters = (sel("lang", "Язык", langs, LANGS) + sel("size", "Размер", sizes, {"all": "все размеры"}) +
               sel("sev", "Важность", ["high", "medium", "low"], SEV) + sel("kind", "Вид", kinds, KINDS) +
               sel("checked", "Проверка", ["yes", "no"], {"yes": "проверено глазами", "no": "не проверено"}) +
               sel("choice", "Решение", ["fix", "false", "none"], {"fix": "исправить", "false": "ложная", "none": "не решено"}))
    head = f"""<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{title}</title><style>{STYLE}</style></head><body><main>
<h1>{title}</h1>
<p class="dim">Шаг 13 плана дополнений: русский и английский интерфейс, окно 1280×720 и размеры телефона. Только находки, без исправлений.</p>
{notes}
<h2>Сводка</h2><table><tr><th>Экран</th><th class="n">высокая</th><th class="n">средняя</th><th class="n">низкая</th><th class="n">всего</th></tr>{"".join(rows)}</table>
<h2>Разбор</h2>
<p class="dim">Отметьте у находки «Исправить» или «Ложная / так и надо», при желании с заметкой. Отметки хранятся в этом браузере; их можно выгрузить в файл и загрузить обратно. «Собрать задание» составит текст для агента из всех находок с отметкой «Исправить».</p>
<div class="bar"><span class="cnt">Исправить: <b id="nFix">0</b></span><span class="cnt">Ложные: <b id="nFalse">0</b></span><span class="cnt">Не решено: <b id="nNone">0</b></span></div>
<div class="bar"><button id="bPrompt">Собрать задание</button><button id="bExport">Выгрузить отметки (JSON)</button>
<button id="bImport">Загрузить отметки</button><input type="file" id="fImport" accept=".json,application/json" hidden><button id="bReset">Сбросить</button><span id="msg" class="dim"></span></div>
<div id="promptBox"><textarea id="promptText" readonly aria-label="Задание для агента"></textarea><div class="bar"><button id="bCopy">Копировать</button><span id="copied" class="dim"></span></div></div>
<div class="filters">{filters}<span id="shown" class="dim"></span></div>
"""
    page = head + "".join(body) + "</main>" + SCRIPT.replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
    (BASE / "index.html").write_text(page)
    print(f"{BASE / 'index.html'}: {len(findings)} findings, {tot}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
