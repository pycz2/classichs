// The dashboard: the server at a glance, kept live by the feed.

import { useState, useEffect, useMemo } from 'preact/hooks'
import { api } from './api.js'
import { html, useLive, useEvents, useLoad, useTick, Card, Kind, NameLink, GameLink, Status, UserLink, ErrorBox, Empty, clock, dur, num } from './ui.js'

const HOUR = 3600000
const SERIES = [
  ['login', 'Logins'],
  ['match', 'Games started'],
  ['msg', 'Messages'],
  ['register', 'Registrations']
]

const localMidnight = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d.getTime() }

/** The 24-hour chart data, shifted as hours pass. */
function bump (chart, at, kind) {
  let { start, series } = chart
  let i = Math.floor((at - start) / HOUR)
  if (i < 0 || !series[kind]) return chart
  series = { ...series }
  while (i > 23) {
    for (const k in series) series[k] = [...series[k].slice(1), 0]
    start += HOUR
    i--
  }
  series[kind] = series[kind].map((v, j) => (j === i ? v + 1 : v))
  return { start, series }
}

export function Dashboard () {
  const { live } = useLive()
  const [data, error, reload] = useLoad(() => api('dashboard?day=' + localMidnight()), [])
  const [today, setToday] = useState({})
  const [chart, setChart] = useState(null)
  const [recent, setRecent] = useState([])
  useEffect(() => {
    if (!data) return
    setToday(data.today)
    setChart(data.chart)
    setRecent(data.recent)
  }, [data])
  useEvents((e) => {
    if (e.resync) return reload()
    setToday((t) => ({ ...t, [e.kind]: (t[e.kind] || 0) + 1 }))
    setChart((c) => (c ? bump(c, e.at, e.kind) : c))
    if (e.kind !== 'game_action') setRecent((r) => [e, ...r].slice(0, 40))
  })
  useTick(5000)
  const t = (k) => today[k] || 0
  const q = live.queue
  const byMode = (m) => q.filter((s) => s.mode === m).length
  const inGame = live.online.filter((o) => o.status === 'in_game').length
  return html`<div class="page">
    <header class="page-head"><h1>Dashboard</h1><span class="muted">Today since ${clock(localMidnight(), false)} · updates live</span></header>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <div class="tiles">
      <${Tile} label="Online now" value=${live.online.length} sub=${`${inGame} in a game · ${q.length} searching`} accent />
      <${Tile} label="Searching" value=${q.length} sub=${`casual ${byMode('casual')} · ranked ${byMode('ranked')} · arena ${byMode('arena')}`} />
      <${Tile} label="Live games" value=${live.games.length} sub=${`${num(live.games.reduce((n, g) => n + g.actions, 0))} actions so far`} />
      <${Tile} label="Games today" value=${t('match')} sub=${`${t('game_end')} finished · ${num(t('game_action'))} actions`} />
      <${Tile} label="New players" value=${t('register')} sub=${data ? `${num(data.totals.accounts)} accounts in all` : ''} />
      <${Tile} label="Logins" value=${t('login')} sub=${`${t('login_failed')} failed`} warn=${t('login_failed') > 20} />
      <${Tile} label="Messages" value=${t('msg')} sub=${`${t('friend_request')} friend requests`} />
      <${Tile} label="Problems" value=${t('error')} sub="errors today" bad=${t('error') > 0} href="#/events?kind=error" />
    </div>
    <div class="grid two">
      <${Card} title="Activity, last 24 hours">
        ${chart ? html`<${LineChart} chart=${chart} />` : html`<div class="chart-skel"></div>`}
      </${Card}>
      <${Card} title="Game actions per hour">
        ${chart ? html`<${Bars} start=${chart.start} values=${chart.series.game_action} />` : html`<div class="chart-skel"></div>`}
      </${Card}>
    </div>
    <div class="grid three">
      <${Card} title=${`Live games (${live.games.length})`} pad=${false} actions=${html`<a class="btn ghost sm" href="#/games">All games</a>`}>
        ${live.games.length ? html`<ul class="rows">${live.games.map((g) => html`<li key=${g.id}>
          <a class="row-link" href=${'#/games/' + g.id}>
            <span class="vs"><b>${g.players[0].user}</b><span class="muted">vs</span><b>${g.players[1].user}</b></span>
            <span class="muted small">${g.mode} · turn ${g.turn} · ${g.actions} actions · ${dur(Date.now() / 1000 - g.started)}</span>
          </a></li>`)}</ul>` : html`<${Empty}>No games right now</${Empty}>`}
      </${Card}>
      <${Card} title=${`Searching (${q.length})`} pad=${false}>
        ${q.length ? html`<ul class="rows">${q.map((s) => html`<li key=${s.id} class="row-line">
          <${UserLink} id=${s.id} user=${s.user} /><span class=${'mode m-' + s.mode}>${s.mode}</span>
          <span class="muted small right">${s.waited} s · window ${s.window}</span></li>`)}</ul>` : html`<${Empty}>Nobody in a queue</${Empty}>`}
      </${Card}>
      <${Card} title=${`Online (${live.online.length})`}>
        ${live.online.length ? html`<div class="chips">${live.online.map((o) => html`<a key=${o.id} class="chip" href=${'#/accounts/' + o.id}>
          <${Status} status=${o.status} label=${false} />${o.user}</a>`)}</div>` : html`<${Empty}>Nobody online</${Empty}>`}
      </${Card}>
    </div>
    <${Card} title="Recent events" pad=${false} actions=${html`<a class="btn ghost sm" href="#/events">Event log</a>`}>
      ${recent.length ? html`<ul class="feed">${recent.map((e) => html`<${FeedRow} key=${e.id} e=${e} />`)}</ul>` : html`<${Empty}>Nothing yet</${Empty}>`}
    </${Card}>
  </div>`
}

function Tile ({ label, value, sub, accent, warn, bad, href }) {
  const cls = 'tile' + (accent ? ' accent' : '') + (warn ? ' warn' : '') + (bad ? ' bad' : '')
  const body = html`<span class="tile-label">${label}</span><span class="tile-value">${num(value)}</span><span class="tile-sub">${sub}</span>`
  return href ? html`<a class=${cls} href=${href}>${body}</a>` : html`<div class=${cls}>${body}</div>`
}

export function FeedRow ({ e }) {
  return html`<li class=${'feed-row fresh cat-row-' + e.kind}>
    <time title=${new Date(e.at).toLocaleString()}>${clock(e.at)}</time>
    <${Kind} kind=${e.kind} />
    <span class="feed-text">${e.text}</span>
    <span class="feed-links">${e.game && html`<${GameLink} id=${e.game} />`}${e.user && html`<${NameLink} name=${e.user} />`}</span>
  </li>`
}

// --- charts: inline SVG, one y-axis, hover crosshair ----------------------------------------

const W = 640
const H = 220
const PAD = { l: 34, r: 12, t: 12, b: 26 }

function niceMax (v) {
  if (v <= 4) return 4
  const p = Math.pow(10, Math.floor(Math.log10(v)))
  for (const m of [1, 2, 2.5, 5, 10]) if (m * p >= v) return m * p
  return 10 * p
}

function Axes ({ start, max, n = 24 }) {
  const x = (i) => PAD.l + (i + 0.5) * (W - PAD.l - PAD.r) / n
  const y = (v) => H - PAD.b - v / max * (H - PAD.t - PAD.b)
  const ticks = [0, max / 2, max]
  return html`<g class="axes">
    ${ticks.map((v) => html`<g key=${v}><line x1=${PAD.l} x2=${W - PAD.r} y1=${y(v)} y2=${y(v)} class=${v ? 'grid' : 'base'} />
      <text x=${PAD.l - 6} y=${y(v) + 4} text-anchor="end">${num(Math.round(v))}</text></g>`)}
    ${[0, 6, 12, 18, 23].map((i) => html`<text key=${i} x=${x(i)} y=${H - 8} text-anchor="middle">${i === 23 ? 'now' : clock(start + i * HOUR, false).slice(-5)}</text>`)}
  </g>`
}

function useHover (n) {
  const [hover, setHover] = useState(null)
  const onMove = (ev) => {
    const r = ev.currentTarget.getBoundingClientRect()
    const fx = (ev.clientX - r.left) / r.width * W
    const i = Math.floor((fx - PAD.l) / ((W - PAD.l - PAD.r) / n))
    setHover(i >= 0 && i < n ? i : null)
  }
  return [hover, onMove, () => setHover(null)]
}

function LineChart ({ chart }) {
  const [hidden, setHidden] = useState({})
  const [hover, onMove, onLeave] = useHover(24)
  const shown = SERIES.filter(([k]) => !hidden[k])
  const max = useMemo(() => niceMax(Math.max(1, ...shown.flatMap(([k]) => chart.series[k] || []))), [chart, hidden])
  const x = (i) => PAD.l + (i + 0.5) * (W - PAD.l - PAD.r) / 24
  const y = (v) => H - PAD.b - v / max * (H - PAD.t - PAD.b)
  return html`<div class="chart">
    <div class="legend">${SERIES.map(([k, label], i) => html`<button key=${k} class=${'leg s' + (i + 1) + (hidden[k] ? ' off' : '')}
      onClick=${() => setHidden((h) => ({ ...h, [k]: !h[k] }))} aria-pressed=${!hidden[k]}><i></i>${label}</button>`)}</div>
    <div class="plot">
      <svg viewBox=${`0 0 ${W} ${H}`} role="img" aria-label="Logins, games started, messages and registrations per hour over the last 24 hours"
        onMouseMove=${onMove} onMouseLeave=${onLeave}>
        <${Axes} start=${chart.start} max=${max} />
        ${hover != null && html`<line class="cross" x1=${x(hover)} x2=${x(hover)} y1=${PAD.t} y2=${H - PAD.b} />`}
        ${SERIES.map(([k], i) => !hidden[k] && html`<g key=${k} class=${'s' + (i + 1)}>
          <polyline class="line" points=${(chart.series[k] || []).map((v, j) => x(j) + ',' + y(v)).join(' ')} />
          ${hover != null && html`<circle class="dot" cx=${x(hover)} cy=${y(chart.series[k][hover])} r="4" />`}
        </g>`)}
      </svg>
      ${hover != null && html`<div class="tip" style=${{ left: (x(hover) / W * 100) + '%' }}>
        <b>${clock(chart.start + hover * HOUR, false)}–${clock(chart.start + (hover + 1) * HOUR, false).slice(-5)}</b>
        ${shown.map(([k, label]) => html`<div key=${k}><i class=${'sw s' + (SERIES.findIndex((s) => s[0] === k) + 1)}></i>${label}<span>${num(chart.series[k][hover])}</span></div>`)}
      </div>`}
    </div>
  </div>`
}

function Bars ({ start, values }) {
  const [hover, onMove, onLeave] = useHover(24)
  const max = niceMax(Math.max(1, ...values))
  const bw = (W - PAD.l - PAD.r) / 24
  const y = (v) => H - PAD.b - v / max * (H - PAD.t - PAD.b)
  return html`<div class="chart"><div class="plot">
    <svg viewBox=${`0 0 ${W} ${H}`} role="img" aria-label="Game actions per hour, last 24 hours" onMouseMove=${onMove} onMouseLeave=${onLeave}>
      <${Axes} start=${start} max=${max} />
      ${values.map((v, i) => v > 0 && html`<rect key=${i} class=${'bar' + (hover === i ? ' on' : '')} x=${PAD.l + i * bw + 1} width=${bw - 2}
        y=${y(v)} height=${Math.max(1, H - PAD.b - y(v))} rx="3" />`)}
    </svg>
    ${hover != null && html`<div class="tip" style=${{ left: ((PAD.l + (hover + 0.5) * bw) / W * 100) + '%' }}>
      <b>${clock(start + hover * HOUR, false)}</b><div>Actions<span>${num(values[hover])}</span></div></div>`}
  </div></div>`
}

