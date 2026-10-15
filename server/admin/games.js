// Games: the live ones, the finished ones, and one game's timeline (live while it runs).

import { useState, useEffect, useRef } from 'preact/hooks'
import { api, qs } from './api.js'
import { html, useLive, useEvents, useLoad, useDebounced, useTick, setQuery, go, Card, Kind, UserLink, Pager, ErrorBox, Empty, Icon, Json, clock, fullDate, dur, ago, num } from './ui.js'

const REASONS = ['over', 'left', 'disconnect', 'illegal', 'desync', 'cheat', 'protocol', 'aborted']

export function Games ({ query }) {
  const { live } = useLive()
  const [f, setF] = useState(() => ({ user: '', mode: '', reason: '', ...query, page: Number(query.page || 0) }))
  const [draft, setDraft] = useState(f.user)
  const set = (p) => setF((x) => ({ ...x, page: 0, ...p }))
  const commit = useDebounced((user) => set({ user }), 350)
  useEffect(() => { setQuery({ ...f, page: f.page || '' }) }, [f])
  const [data, error, reload, loading] = useLoad(() => api('games?' + qs({ ...f, size: 50 })), [f])
  const later = useDebounced(reload, 500)
  useEvents((e) => { if (e.resync || e.kind === 'game_end') later() })
  useTick(1000)
  return html`<div class="page">
    <header class="page-head"><h1>Games</h1></header>
    <${Card} title=${html`<span class="live-dot"></span>Live now (${live.games.length})`} pad=${false}>
      ${live.games.length ? html`<div class="table-wrap"><table class="table">
        <thead><tr><th>Game</th><th>Mode</th><th>Player 1</th><th>Player 2</th><th class="num">Turn</th><th>To move</th><th class="num">Actions</th><th class="num">Running</th></tr></thead>
        <tbody>${live.games.map((g) => html`<tr key=${g.id} class="clickable" onClick=${() => go('games/' + g.id)}>
          <td class="mono">${g.id.slice(0, 8)}</td><td><span class=${'mode m-' + g.mode}>${g.mode}</span></td>
          ${g.players.map((p) => html`<td><${UserLink} ...${p} />${!p.online && html` <span class="badge warn" title="Dropped out: 30 s to come back">away</span>`}</td>`)}
          <td class="num">${g.turn}</td><td>${g.players[g.current] ? g.players[g.current].user : '—'}</td>
          <td class="num">${num(g.actions)}</td><td class="num mono">${dur(Date.now() / 1000 - g.started)}</td>
        </tr>`)}</tbody></table></div>` : html`<${Empty}>No games right now</${Empty}>`}
    </${Card}>
    <div class="filters">
      <label class="search"><${Icon} name="search" size=${16} /><input placeholder="Player" value=${draft} onInput=${(e) => { setDraft(e.target.value); commit(e.target.value) }} /></label>
      <div class="seg text">${['', 'casual', 'ranked', 'arena', 'friendly'].map((m) => html`<button key=${m} class=${f.mode === m ? 'on' : ''} onClick=${() => set({ mode: m })}>${m ? m[0].toUpperCase() + m.slice(1) : 'All modes'}</button>`)}</div>
      <select value=${f.reason} onChange=${(e) => set({ reason: e.target.value })} aria-label="How it ended"><option value="">Any ending</option>${REASONS.map((r) => html`<option>${r}</option>`)}</select>
    </div>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <${Card} title="Finished" pad=${false} cls=${loading ? 'loading' : ''}>
      <div class="table-wrap"><table class="table">
        <thead><tr><th>Game</th><th>Mode</th><th>Winner</th><th>Loser</th><th>Ending</th><th class="num">Length</th><th>Ended</th></tr></thead>
        <tbody>${data && data.list.map((g) => {
          const draw = g.winner < 0
          const [w, l] = draw ? g.players : [g.players[g.winner], g.players[1 - g.winner]]
          return html`<tr key=${g.id} class="clickable" onClick=${() => go('games/' + g.id)}>
            <td class="mono">${g.id.slice(0, 8)}</td><td><span class=${'mode m-' + g.mode}>${g.mode}</span></td>
            <td>${draw ? html`<span class="muted">draw:</span> ` : ''}<${UserLink} ...${w} /></td><td><${UserLink} ...${l} /></td>
            <td><span class=${'reason ' + (g.reason === 'over' ? '' : 'odd')}>${g.reason}</span></td>
            <td class="num mono">${dur(g.ended - g.started)}</td>
            <td class="nowrap" title=${fullDate(g.ended * 1000)}>${ago(g.ended * 1000)}</td></tr>`
        })}</tbody>
      </table></div>
      ${data && !data.list.length && html`<${Empty}>No finished games match</${Empty}>`}
      ${data && html`<div class="table-foot"><span></span><${Pager} page=${f.page} size=${50} total=${data.total} onPage=${(page) => setF((x) => ({ ...x, page }))} /></div>`}
    </${Card}>
  </div>`
}

// --- one game ---------------------------------------------------------------------------------

export function GamePage ({ id }) {
  const { live } = useLive()
  const [data, error, reload] = useLoad(() => api('games/' + encodeURIComponent(id)), [id])
  const [extra, setExtra] = useState([])
  const [open, setOpen] = useState(null)
  const [follow, setFollow] = useState(true)
  const end = useRef(null)
  useEffect(() => setExtra([]), [data])
  useEvents((e) => {
    if (e.resync) return reload()
    if (e.game !== id) return
    setExtra((x) => [...x, e])
    if (e.kind === 'game_end') setTimeout(reload, 300)
  })
  useTick(1000)
  const events = data ? [...data.events, ...extra.filter((e) => !data.events.some((d) => d.id === e.id))] : []
  useEffect(() => { if (follow && end.current && extra.length) end.current.scrollIntoView({ block: 'nearest', behavior: 'smooth' }) }, [extra.length])
  if (error && !data) return html`<div class="page"><a class="back" href="#/games"><${Icon} name="back" size=${16} />Games</a><${ErrorBox} error=${error} onRetry=${reload} /></div>`
  if (!data) return html`<div class="page"><div class="skel-title"></div></div>`
  const lg = live.games.find((g) => g.id === id)
  const g = lg ? { ...data.game, ...lg, live: true } : data.game
  const players = (g.players || []).map((p, i) => ({ ...p, user: (p && p.user) || (data.match && data.match.players[i]) }))
  const heroes = data.match ? data.match.heroes : []
  const t0 = events.length ? events[0].at : Date.now()
  // Turns as they were when each action was sent (the server logs the turn after it).
  let after = 0
  let shown = null
  return html`<div class="page">
    <a class="back" href="#/games"><${Icon} name="back" size=${16} />Games</a>
    <header class="page-head game-head">
      <div>
        <h1 class="vs-title"><span class="p0">${players[0] && players[0].user}</span><span class="muted">vs</span><span class="p1">${players[1] && players[1].user}</span></h1>
        <div class="muted">
          <span class=${'mode m-' + g.mode}>${g.mode}</span> · <span class="mono">${id}</span>
          ${heroes.length ? html` · ${heroes.join(' vs ')}` : ''}
        </div>
      </div>
      <div class="game-state">
        ${g.live
          ? html`<span class="badge live"><span class="live-dot"></span>live</span> turn ${g.turn} · ${num(g.actions)} actions · ${dur(Date.now() / 1000 - g.started)}`
          : g.reason ? html`<span class=${'badge ' + (g.reason === 'over' ? 'ok' : 'warn')}>${g.winner >= 0 && players[g.winner] ? players[g.winner].user + ' won' : 'no winner'} · ${g.reason}</span>
            <span class="muted">${dur(g.ended - g.started)} · ended ${fullDate(g.ended * 1000)}</span>` : html`<span class="badge">unknown</span>`}
      </div>
    </header>
    <div class="grid two-one">
      <${Card} title=${`Timeline (${events.length})`} pad=${false}
        actions=${html`<label class="check"><input type="checkbox" checked=${follow} onChange=${(e) => setFollow(e.target.checked)} />Follow</label>
          <a class="btn ghost sm" href=${'#/events?game=' + id}>In the event log</a>`}>
        ${events.length ? html`<ol class="timeline">${events.map((e) => {
          const act = e.kind === 'game_action' && e.data
          const turn = act ? after : null
          const sep = act && turn !== shown
          if (act) { shown = turn; if (e.data.turn != null) after = e.data.turn }
          const p = players.findIndex((x) => x && x.user && e.user && x.user.toLowerCase() === e.user.toLowerCase())
          return html`${sep && html`<li class="turn-sep" key=${'t' + e.id}><span>${turn ? 'Turn ' + turn : 'Mulligan'}</span></li>`}
          <li key=${e.id} class=${'tl p' + p + ' k-' + e.kind + (open === e.id ? ' open' : '')} onClick=${() => setOpen(open === e.id ? null : e.id)}>
            <time title=${fullDate(e.at)}>+${dur((e.at - t0) / 1000)}<small>.${Math.floor((e.at - t0) % 1000 / 100)}</small></time>
            <${Kind} kind=${e.kind} />
            <span class="tl-text">${e.text}</span>
            ${open === e.id && e.data != null && html`<div class="tl-data" onClick=${(ev) => ev.stopPropagation()}><${Json} value=${e.data} /></div>`}
          </li>`
        })}<li ref=${end} class="tl-end">${g.live ? html`<span class="live-dot"></span> waiting for the next move…` : ''}</li></ol>` : html`<${Empty}>No events for this game</${Empty}>`}
      </${Card}>
      <div class="stack">
        <${Card} title="Players">
          ${players.map((p, i) => html`<div class=${'player-card p' + i} key=${i}>
            <span class="pnum">${'Player ' + (i + 1)}</span>
            <b>${p.id != null ? html`<${UserLink} ...${p} />` : p.user}</b>
            ${heroes[i] && html`<span class="muted small mono">${heroes[i]}</span>`}
            ${lg && html`<span class="small">${lg.current === i ? '▶ to move' : ''} ${p.online === false ? html`<span class="badge warn">away</span>` : ''}</span>`}
          </div>`)}
        </${Card}>
        ${data.match && html`<${Card} title="Match">
          <dl class="kv">
            <dt>Started</dt><dd>${clock(t0)}</dd>
            <dt>Seed</dt><dd class="mono">${data.match.seed}</dd>
            <dt>Actions</dt><dd>${num(events.filter((e) => e.kind === 'game_action').length)}</dd>
          </dl>
        </${Card}>`}
        ${(() => {
          const endEv = events.find((e) => e.kind === 'game_end')
          return endEv && endEv.data && endEv.data.message && html`<${Card} title="What ended it">
            <p>${endEv.data.by} sent${endEv.data.refused ? ' (refused by the rules)' : ''}:</p><${Json} value=${endEv.data.refused || endEv.data.message} /></${Card}>`
        })()}
      </div>
    </div>
  </div>`
}
