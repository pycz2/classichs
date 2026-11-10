// Statistics (HSReplay-like): classes, decks, cards and the mulligan of each game pack, from the
// server's aggregated rows (GET /admin/api/stats; nothing is recomputed here).

import { useState, useEffect, useMemo } from 'preact/hooks'
import { api, qs } from './api.js'
import { html, useLoad, useEvents, useDebounced, setQuery, Card, ErrorBox, Empty, SortTh, Icon, CopyCode, DeckList, num } from './ui.js'

// The page's own styles (kept in their own file).
if (!document.querySelector('link[href$="/stats.css"]')) {
  document.head.append(Object.assign(document.createElement('link'), { rel: 'stylesheet', href: '/admin/static/stats.css' }))
}

const PERIODS = [['hour', 'This hour'], ['day', 'Today'], ['week', 'This week'], ['month', 'This month'], ['year', 'This year'], ['all', 'All time']]
const cap = (s) => s ? s[0].toUpperCase() + s.slice(1) : s
const rate = (w, g) => g > 0 ? w / g : null
const pct = (x, d = 1) => x == null ? '—' : (x * 100).toFixed(d) + '%'
const wrClass = (x) => x == null ? 'muted' : x >= 0.5 ? 'wr up' : 'wr down'
// "2026-11-10T14" → "Nov 10, 14:00"; the current bucket by the period's name ("Today"), the day before "Yesterday"
function bucketLabel (period, b, current) {
  if (period === 'all') return 'All time'
  if (b === current) return PERIODS.find((p) => p[0] === period)[1]
  const d = new Date(Date.parse(b.length === 4 ? b + '-01-01' : b.length === 7 ? b + '-01' : b.slice(0, 10)) + (period === 'hour' ? Number(b.slice(11)) * 36e5 : 0))
  const o = (x) => d.toLocaleString('en', { timeZone: 'UTC', ...x })
  switch (period) {
    case 'hour': return o({ month: 'short', day: 'numeric' }) + ', ' + b.slice(11) + ':00 UTC'
    case 'day': return Date.parse(current) - d === 864e5 ? 'Yesterday' : o({ weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })
    case 'week': return 'Week of ' + o({ month: 'short', day: 'numeric', year: 'numeric' })
    case 'month': return o({ month: 'long', year: 'numeric' })
    default: return b
  }
}
const bracketLabel = (b, mode) => b === 'unknown' ? 'Unknown (counted later)' : b === 'Legend' ? 'Legend' : mode === 'arena' ? b + ' wins' : 'Ranks ' + b

export function Stats ({ query }) {
  const [f, setF] = useState(() => ({ pack: '', mode: '', bracket: '', period: 'all', bucket: '', bots: '1', min: '20', class: '', ...query }))
  const set = (p) => setF((x) => ({ ...x, ...p }))
  useEffect(() => { setQuery(f) }, [f])
  const [data, error, reload, loading] = useLoad(() => api('stats?' + qs(f)), [f])
  const later = useDebounced(reload, 1500)
  useEvents((e) => { if (e.resync || e.kind === 'game_end') later() })
  const [minDraft, setMinDraft] = useState(f.min)
  const commitMin = useDebounced((min) => set({ min }), 400)
  const [muMin, setMuMin] = useState(5)

  if (error && !data) return html`<div class="page"><header class="page-head"><h1>Statistics</h1></header><${ErrorBox} error=${error} onRetry=${reload} /></div>`
  if (!data) return html`<div class="page"><div class="skel-title"></div><div class="chart-skel"></div></div>`
  if (!data.packs.length) {
    return html`<div class="page"><header class="page-head"><h1>Statistics</h1></header>
      <${Card}><${Empty}>No finished games counted yet${data.backfill === 'running' ? ' (the earlier games are being counted…)' : ''}</${Empty}></${Card}></div>`
  }
  const games = data.sides / (data.bracket ? 1 : 2)
  const classNames = Object.fromEntries(data.classes.map((c) => [c.class, c.name]))
  const brackets = data.mode ? data.brackets.filter((b) => b !== 'all') : []
  return html`<div class="page stats">
    <header class="page-head"><h1>Statistics</h1>
      <span class="muted small">${data.backfill === 'running' ? 'Counting the earlier games…' : 'Updated after every finished game'}</span></header>
    <div class="filters stats-filters">
      <select value=${data.pack} onChange=${(e) => set({ pack: e.target.value, mode: '', bracket: '', class: '' })} aria-label="Game">
        ${data.packs.map((p) => html`<option value=${p.pack}>${p.name} (${num(p.games)})</option>`)}</select>
      <div class="seg text">${['', ...data.modes].map((m) => html`<button key=${m} class=${(data.mode || '') === m ? 'on' : ''} onClick=${() => set({ mode: m, bracket: '' })}>${m ? cap(m) : 'All modes'}</button>`)}</div>
      ${brackets.length > 0 && html`<select value=${data.bracket || ''} onChange=${(e) => set({ bracket: e.target.value })} aria-label="Bracket">
        <option value="">All brackets</option>${brackets.map((b) => html`<option value=${b}>${bracketLabel(b, data.mode)}</option>`)}</select>`}
      <div class="seg text">${PERIODS.map(([k, label]) => html`<button key=${k} class=${data.period === k ? 'on' : ''} onClick=${() => set({ period: k, bucket: '' })}>${label}</button>`)}</div>
      ${data.period !== 'all' && html`<select value=${data.bucket} onChange=${(e) => set({ bucket: e.target.value === data.current ? '' : e.target.value })} aria-label="Which ${data.period}">
        ${data.buckets.map((b) => html`<option value=${b.bucket}>${bucketLabel(data.period, b.bucket, data.current)} · ${num(b.sides / (data.bracket ? 1 : 2))} ${data.bracket ? 'players' : 'games'}</option>`)}</select>`}
      <label class="check"><input type="checkbox" checked=${data.bots} onChange=${(e) => set({ bots: e.target.checked ? '1' : '0' })} />Games with bots</label>
      <label class="field-inline">Min. deck games <input class="num-input" type="number" min="1" value=${minDraft}
        onInput=${(e) => { setMinDraft(e.target.value); if (Number(e.target.value) >= 1) commitMin(e.target.value) }} /></label>
    </div>
    <div class=${'stack' + (loading ? ' loading' : '')}>
      <div class="tiles">
        <div class="tile accent"><span class="tile-label">${data.bracket ? 'Players in the bracket' : 'Games'}</span><span class="tile-value">${num(games)}</span>
          <span class="tile-sub">${bucketLabel(data.period, data.bucket, data.current)}</span></div>
        <div class="tile"><span class="tile-label">Classes played</span><span class="tile-value">${data.classes.length}</span><span class="tile-sub">mirrors: ${num(data.classes.reduce((a, c) => a + c.mirrors, 0) / 2)} games</span></div>
        <div class="tile"><span class="tile-label">Decks with ≥ ${data.min} games</span><span class="tile-value">${num(data.decks.total)}</span><span class="tile-sub">by their exact 30 cards</span></div>
        <div class="tile"><span class="tile-label">Cards in decks</span><span class="tile-value">${num(data.cards.length)}</span><span class="tile-sub">${data.class ? classNames[data.class] || data.class : 'all classes'}</span></div>
      </div>
      <div class="grid two">
        <${Card} title="Class win rates"><${ClassBars} classes=${data.classes} /></${Card}>
        <${Card} title=${data.period === 'hour' || data.period === 'day' ? 'Games per hour, last 48 hours' : 'Games per day, last 30 days'}>
          <${TimeBars} series=${data.period === 'hour' || data.period === 'day' ? data.series.hour : data.series.day} hourly=${data.period === 'hour' || data.period === 'day'} per=${data.bracket ? 1 : 2} /></${Card}>
      </div>
      <${Card} title="Matchups" pad=${false} actions=${html`<label class="field-inline">Min. games <input class="num-input" type="number" min="1" value=${muMin}
          onInput=${(e) => setMuMin(Math.max(1, Number(e.target.value) || 1))} /></label>`}><${Matchups} data=${data} min=${muMin} /></${Card}>
      ${!data.kept && html`<p class="muted small stats-note">The deck and card rows of ${data.period === 'hour' ? 'hours older than 48 hours' : 'days older than 400 days'} are not kept: this ${data.period} shows the classes and matchups only.</p>`}
      <${Decks} decks=${data.decks} min=${data.min} names=${classNames} />
      <${Cards} data=${data} names=${classNames} onClass=${(c) => set({ class: c })} />
    </div>
  </div>`
}

// --- charts: inline SVG (the CSP allows no styles but the page's own) ---------------------------

const W = 640

/** Horizontal bars: rows of {label, parts: [[value, cls]], max, text, title}; `mid`: a reference line (0..1). */
function HBars ({ rows, max, mid, label = 150, aria }) {
  const rh = 26
  const H = rows.length * rh + 6
  const x0 = label + 8
  const span = W - x0 - 120
  return html`<div class="hscroll"><svg class="hbars" viewBox=${`0 0 ${W} ${H}`} role="img" aria-label=${aria}>
    ${rows.map((r, i) => {
      let at = x0
      const y = 3 + i * rh
      return html`<g key=${r.label + i}><title>${r.title || r.label + ': ' + r.text}</title>
        <rect class="hb-track" x=${x0} y=${y + 5} width=${span} height=${rh - 10} rx="4" />
        ${r.parts.map(([v, cls]) => {
          const w = Math.max(0, v / max * span)
          const el = html`<rect class=${'hb ' + cls} x=${at} y=${y + 5} width=${Math.max(0, w - (r.parts.length > 1 ? 2 : 0))} height=${rh - 10} rx="4" />`
          at += w
          return el
        })}
        <text class="hb-label" x=${label} y=${y + rh / 2 + 4} text-anchor="end">${r.label.length > 22 ? r.label.slice(0, 21) + '…' : r.label}</text>
        <text class="hb-value" x=${x0 + span + 8} y=${y + rh / 2 + 4}>${r.text}</text>
      </g>`
    })}
    ${mid != null && html`<line class="hb-mid" x1=${x0 + mid * span} x2=${x0 + mid * span} y1="0" y2=${H} />`}
  </svg></div>`
}

function ClassBars ({ classes }) {
  if (!classes.length) return html`<${Empty}>No games in this selection</${Empty}>`
  const total = classes.reduce((a, c) => a + c.games, 0)
  const rows = classes
    .map((c) => ({ c, wr: rate(c.wins, c.games - c.mirrors) }))
    .sort((a, b) => (b.wr ?? -1) - (a.wr ?? -1))
    .map(({ c, wr }) => ({
      label: c.name,
      parts: [[wr ?? 0, wr == null ? 'none' : wr >= 0.5 ? 'up' : 'down']],
      text: pct(wr) + ' · ' + num(c.games),
      title: `${c.name}: ${pct(wr)} win rate in ${num(c.games - c.mirrors)} non-mirror games; ${num(c.games)} played (${pct(c.games / total)}), ${num(c.mirrors)} mirrors`
    }))
  return html`<${HBars} rows=${rows} max=${1} mid=${0.5} label=${110} aria="Win rate of each class; the line is 50%" />
    <p class="small muted stats-note">Bar: win rate (the line is 50%); then the games played. Mirror games count no win or loss for the class.</p>`
}

function TimeBars ({ series, hourly, per }) {
  const [hover, setHover] = useState(null)
  const H = 200
  const P = { l: 34, r: 8, t: 10, b: 24 }
  const vals = series.map((s) => s[1] / per)
  const max = Math.max(4, Math.ceil(Math.max(...vals) / 4) * 4)
  const bw = (W - P.l - P.r) / series.length
  const y = (v) => H - P.b - v / max * (H - P.t - P.b)
  const lab = (k) => hourly ? k.slice(11) + ':00' : k.slice(5)
  const every = hourly ? 8 : 5
  const onMove = (ev) => {
    const r = ev.currentTarget.getBoundingClientRect()
    const i = Math.floor(((ev.clientX - r.left) / r.width * W - P.l) / bw)
    setHover(i >= 0 && i < series.length ? i : null)
  }
  return html`<div class="chart"><div class="plot">
    <svg viewBox=${`0 0 ${W} ${H}`} role="img" aria-label=${hourly ? 'Games per hour' : 'Games per day'} onMouseMove=${onMove} onMouseLeave=${() => setHover(null)}>
      <g class="axes">${[0, max / 2, max].map((v) => html`<g key=${v}><line x1=${P.l} x2=${W - P.r} y1=${y(v)} y2=${y(v)} class=${v ? 'grid' : 'base'} />
        <text x=${P.l - 6} y=${y(v) + 4} text-anchor="end">${num(v)}</text></g>`)}
        ${series.map((s, i) => (series.length - 1 - i) % every === 0 && html`<text key=${i} x=${P.l + (i + 0.5) * bw} y=${H - 7} text-anchor="middle">${lab(s[0])}</text>`)}</g>
      ${vals.map((v, i) => v > 0 && html`<rect key=${i} class=${'bar' + (hover === i ? ' on' : '')} x=${P.l + i * bw + 1} width=${Math.max(1, bw - 2)} y=${y(v)} height=${Math.max(1, H - P.b - y(v))} rx="3" />`)}
    </svg>
    ${hover != null && html`<div class="tip" style=${{ left: ((P.l + (hover + 0.5) * bw) / W * 100) + '%' }}>
      <b>${hourly ? series[hover][0].replace('T', ' ') + ':00 UTC' : series[hover][0]}</b><div>${per === 1 ? 'Players' : 'Games'}<span>${num(vals[hover])}</span></div></div>`}
  </div></div>`
}

// --- decks ---------------------------------------------------------------------------------------

function DeckRows ({ decks, names, rank, head = true }) {
  const [open, setOpen] = useState(null)
  return html`<table class="table compact decks">
    ${head && html`<thead><tr>${rank && html`<th class="num">#</th>`}<th>Deck</th><th class="num">Games</th><th class="w-wr">Win rate</th></tr></thead>`}
    <tbody>${decks.map((d, i) => {
      const wr = rate(d.wins, d.games)
      return html`<tr key=${d.deck} class="clickable" onClick=${() => setOpen(open === d.deck ? null : d.deck)}>
          ${rank && html`<td class="num muted">${i + 1}</td>`}
          <td>${rank && html`<span class=${'cls c-' + d.class.toLowerCase()}>${names[d.class] || cap(d.class.toLowerCase())}</span> `}<span class="deck-name">${d.cards.slice(-2).map((c) => c.name).join(', ')}</span>
            <span class="mono muted small"> ${d.deck.slice(0, 8)}</span> <${CopyCode} code=${d.code} label="" /></td>
          <td class="num">${num(d.games)}</td>
          <td><${WrBar} wr=${wr} /></td>
        </tr>
        ${open === d.deck && html`<tr class="details"><td colspan=${rank ? 4 : 3}><${DeckList} d=${d} /></td></tr>`}`
    })}</tbody></table>`
}

function WrBar ({ wr }) {
  return html`<span class="wrbar"><svg viewBox="0 0 100 8" aria-hidden="true"><rect class="hb-track" width="100" height="8" rx="4" />
    ${wr != null && html`<rect class=${'hb ' + (wr >= 0.5 ? 'up' : 'down')} width=${Math.max(2, wr * 100)} height="8" rx="4" />`}<line class="hb-mid" x1="50" x2="50" y1="0" y2="8" /></svg>
    <span class=${wrClass(wr)}>${pct(wr)}</span></span>`
}

function Decks ({ decks, min, names }) {
  const classes = Object.keys(decks.by_class)
  return html`<${Card} title=${html`Decks <span class="muted small">by win rate, at least ${min} games</span>`} pad=${false}>
    ${decks.top.length ? html`<div class="grid deck-grid">
      <div><h3 class="sub-head">Top 20</h3><div class="table-wrap"><${DeckRows} decks=${decks.top} names=${names} rank=${true} /></div></div>
      <div><h3 class="sub-head">Top 5 of each class</h3>
        ${classes.map((c) => html`<div key=${c} class="class-block"><div class="class-title"><span class=${'cls c-' + c.toLowerCase()}>${names[c] || cap(c.toLowerCase())}</span></div>
          <${DeckRows} decks=${decks.by_class[c]} names=${names} head=${false} /></div>`)}</div>
    </div>` : html`<${Empty}>No deck has ${min} games here yet: lower "Min. deck games"</${Empty}>`}
  </${Card}>`
}

// --- cards ---------------------------------------------------------------------------------------

const COLS = [
  ['name', 'Card'], ['incl', 'In decks'], ['avg', 'Copies'], ['dwr', 'Deck win rate'], ['playedp', 'Played in'], ['pwr', 'Played win rate'],
  ['plays', 'Times played'], ['offered', 'In opening hand'], ['keptp', 'Kept'], ['kwr', 'Kept win rate']
]

function Cards ({ data, names, onClass }) {
  const [sort, setSort] = useState(['plays', 'desc'])
  const [filter, setFilter] = useState('')
  const [all, setAll] = useState(false)
  const rows = useMemo(() => data.cards.map((c) => {
    const offered = c.kept + c.replaced
    return {
      ...c, offered, incl: rate(c.decks, data.sides), avg: rate(c.copies, c.decks), dwr: rate(c.deck_wins, c.decks), playedp: rate(c.played, c.decks),
      pwr: rate(c.played_wins, c.played), keptp: rate(c.kept, offered), kwr: rate(c.kept_wins, c.kept)
    }
  }), [data])
  const [col, dir] = sort
  const shown = rows
    .filter((r) => !filter || r.name.toLowerCase().includes(filter.toLowerCase()))
    .sort((a, b) => {
      const x = a[col] ?? -1
      const y = b[col] ?? -1
      const c = typeof x === 'string' ? x.localeCompare(y) : x - y
      return dir === 'asc' ? c : -c
    })
  const played = [...rows].sort((a, b) => b.plays - a.plays).slice(0, 12).filter((r) => r.plays > 0)
  const mull = [...rows].sort((a, b) => b.offered - a.offered).slice(0, 12).filter((r) => r.offered > 0)
  const maxPlays = Math.max(1, ...played.map((r) => r.plays))
  return html`<${Card} title="Cards" pad=${false} actions=${html`
      <select value=${data.class || ''} onChange=${(e) => onClass(e.target.value)} aria-label="Class">
        <option value="">All classes' decks</option>${Object.entries(names).map(([k, n]) => html`<option value=${k}>${n} decks</option>`)}</select>`}>
    <div class="grid two card-charts">
      <div><h3 class="sub-head">Most played</h3>
        ${played.length ? html`<${HBars} rows=${played.map((r) => ({ label: r.name, parts: [[r.plays, 'pop']], text: num(r.plays) + ' · ' + pct(r.pwr, 0),
          title: `${r.name}: played ${num(r.plays)} times in ${num(r.played)} games, ${pct(r.pwr)} of them won` }))} max=${maxPlays} aria="The most played cards" />
          <p class="small muted stats-note">Times played · win rate of the games it was played in</p>` : html`<${Empty}>Nothing played</${Empty}>`}</div>
      <div><h3 class="sub-head">Mulligan: kept vs replaced</h3>
        ${mull.length ? html`<div class="legend"><span class="leg"><i class="sw-kept"></i>Kept</span><span class="leg"><i class="sw-replaced"></i>Replaced</span></div>
          <${HBars} rows=${mull.map((r) => ({ label: r.name, parts: [[r.kept, 'kept'], [r.replaced, 'replaced']], text: pct(r.keptp, 0) + ' kept',
            title: `${r.name}: in the opening hand ${num(r.offered)} times, kept ${num(r.kept)} (${pct(r.keptp)}), replaced ${num(r.replaced)}; win rate when kept ${pct(r.kwr)}` }))}
            max=${Math.max(1, ...mull.map((r) => r.offered))} aria="Kept and replaced in the opening hand" />
          <p class="small muted stats-note">The cards most often in the opening hand</p>` : html`<${Empty}>No mulligans</${Empty}>`}</div>
    </div>
    <div class="filters inset">
      <label class="search"><${Icon} name="search" size=${16} /><input placeholder="Card" value=${filter} onInput=${(e) => setFilter(e.target.value)} /></label>
      <span class="muted small">${num(shown.length)} cards · in decks of ${num(data.sides)} players</span>
    </div>
    <div class="table-wrap"><table class="table compact cards-table">
      <thead><tr>${COLS.map(([k, label]) => html`<${SortTh} key=${k} col=${k} sort=${col} dir=${dir} cls=${k === 'name' ? '' : 'num'} onSort=${(c, d) => setSort([c, d])}>${label}</${SortTh}>`)}</tr></thead>
      <tbody>${(all ? shown : shown.slice(0, 50)).map((r) => html`<tr key=${r.card}>
        <td title=${r.card}><span class="cost">${r.cost ?? '?'}</span> ${r.name}</td>
        <td class="num">${pct(r.incl)}</td><td class="num">${r.avg == null ? '—' : r.avg.toFixed(2)}</td>
        <td class="num"><span class=${wrClass(r.dwr)}>${pct(r.dwr)}</span></td>
        <td class="num">${pct(r.playedp)}</td><td class="num"><span class=${wrClass(r.pwr)}>${pct(r.pwr)}</span></td>
        <td class="num">${num(r.plays)}</td><td class="num">${num(r.offered)}</td>
        <td class="num"><span class="keep"><svg viewBox="0 0 40 6" aria-hidden="true"><rect class="hb replaced" width="40" height="6" rx="3" />
          ${r.keptp != null && html`<rect class="hb kept" width=${r.keptp * 40} height="6" rx="3" />`}</svg>${pct(r.keptp, 0)}</span></td>
        <td class="num"><span class=${wrClass(r.kwr)}>${pct(r.kwr)}</span></td>
      </tr>`)}</tbody>
    </table></div>
    ${shown.length > 50 && html`<div class="table-foot"><span class="muted small">${all ? 'All' : '50 of'} ${num(shown.length)}</span>
      <button class="btn ghost sm" onClick=${() => setAll(!all)}>${all ? 'Show 50' : 'Show all'}</button></div>`}
  </${Card}>`
}

// --- matchups ------------------------------------------------------------------------------------

// A win rate's colour: red under 50%, green over, full at 25% and 75%.
const wrColor = (wr) => {
  const t = Math.max(-1, Math.min(1, (wr - 0.5) / 0.25))
  return `color-mix(in srgb, var(${t >= 0 ? '--ok' : '--bad'}) ${Math.round(Math.abs(t) * 60)}%, var(--surface))`
}

/** Rows: a class; columns: its opponent; a cell: the row's win rate against it (a mirror: its games). */
function Matchups ({ data, min }) {
  const per = data.bracket ? 1 : 2 // a mirror's row has both players (but in a bracket: its players)
  const names = Object.fromEntries(data.classes.map((c) => [c.class, c.name]))
  const name = (c) => names[c] || cap(c.toLowerCase())
  const at = {}
  for (const m of data.matchups) at[m.class + ' ' + m.opp] = m
  const classes = [...new Set(data.matchups.flatMap((m) => [m.class, m.opp]))].sort((a, b) => name(a).localeCompare(name(b)))
  if (!classes.length) return html`<${Empty}>No games in this selection</${Empty}>`
  // phones: 3 letters, 4 where two classes share them (Warlock, Warrior)
  const short = (c) => name(c).slice(0, classes.some((d) => d !== c && name(d).slice(0, 3) === name(c).slice(0, 3)) ? 4 : 3)
  const head = (c) => html`<span class=${'cls c-' + c.toLowerCase()}><span class="long">${name(c)}</span><span class="short">${short(c)}</span></span>`
  return html`<div class="table-wrap"><table class="mu-grid">
    <thead><tr><th class="mu-corner"><span class="muted small">vs →</span></th>${classes.map((c) => html`<th key=${c} title=${name(c)}>${head(c)}</th>`)}<th class="mu-total">All</th></tr></thead>
    <tbody>${classes.map((a) => {
      const row = classes.filter((b) => b !== a).map((b) => at[a + ' ' + b]).filter(Boolean)
      const games = row.reduce((x, m) => x + m.games, 0)
      const wins = row.reduce((x, m) => x + m.wins, 0)
      const mirror = (at[a + ' ' + a]?.games || 0) / per
      return html`<tr key=${a}><th title=${name(a)}>${head(a)}</th>
        ${classes.map((b) => {
          const m = at[a + ' ' + b]
          if (a === b) {
            return html`<td key=${b} class=${'mu mirror' + (mirror < min ? ' few' : '')} title=${`${name(a)} mirror: ${num(mirror)} games`}><b>—</b><span>${num(mirror)}</span></td>`
          }
          if (!m) return html`<td key=${b} class="mu few" title=${`${name(a)} vs ${name(b)}: no games`}><b></b><span>0</span></td>`
          const wr = m.wins / m.games
          return html`<td key=${b} class=${'mu' + (m.games < min ? ' few' : '')} style=${m.games < min ? null : { background: wrColor(wr) }}
            title=${`${name(a)} vs ${name(b)}: ${pct(wr)} — ${num(m.wins)} won, ${num(m.games - m.wins)} lost of ${num(m.games)} games`}><b>${pct(wr, 0)}</b><span>${num(m.games)}</span></td>`
        })}
        <td class="mu mu-total" style=${games >= min ? { background: wrColor(wins / games) } : null}
          title=${`${name(a)} against the other classes: ${pct(rate(wins, games))} — ${num(wins)} won of ${num(games)} games; ${num(mirror)} mirror games`}><b>${pct(rate(wins, games), 1)}</b><span>${num(games)}</span></td>
      </tr>`
    })}</tbody></table></div>
    <div class="mu-legend small muted"><span>25%</span><i class="mu-scale"></i><span>75%</span>
      <span>Row: the class, column: its opponent; the row's win rate, then the ${per === 1 ? 'players' : 'games'}. Diagonal: mirror games. Faded: under ${min} games.</span></div>`
}
