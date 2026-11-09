// Tournaments: the list by status, one tournament's entrants (places, top 3 highlighted), its
// bracket or table (matches by bracket and round), and cancel.

import { useState } from 'preact/hooks'
import { api, qs } from './api.js'
import { html, useLoad, useEvents, useDebounced, go, toast, Card, ErrorBox, Empty, Icon, GameLink, fullDate } from './ui.js'
import { Confirm } from './accounts.js'

const STATUSES = ['', 'open', 'locked', 'seeded', 'running', 'finished', 'cancelled', 'closed']
const FORMAT = { round_robin: 'Round robin', swiss: 'Swiss', elimination: 'Elimination', scheveningen: 'Scheveningen' }
const SERIES = { conquest: 'Conquest', lhs: 'Last Hero Standing' }
const BRACKET = { w: 'Winners', l: 'Losers', gf: 'Grand final', '': '' }
const ACTIVE = ['open', 'locked', 'seeded', 'running']

const statusBadge = (s) => html`<span class=${'badge ' + (s === 'running' ? 'live' : s === 'finished' ? 'ok' : s === 'cancelled' || s === 'closed' ? 'warn' : '')}>${s}</span>`
const place = (p) => p > 0 ? html`<span class=${'place' + (p <= 3 ? ' top' + p : '')}>${p}</span>` : '—'

function formatText (t) {
  const o = t.options || {}
  const f = FORMAT[t.format] || t.format
  if (t.format === 'elimination') return f + (o.losses === 2 ? ' (double)' : ' (single)')
  if (t.format === 'round_robin') return f + (o.rounds === 2 ? ' ×2' : '')
  if (t.format === 'swiss') return f + (o.rounds ? `, ${o.rounds} rounds` : '') + (o.drop_after ? `, out after ${o.drop_after} losses` : '')
  return f
}

export function Tournaments ({ query }) {
  const [status, setStatus] = useState(query.status || '')
  const [data, error, reload, loading] = useLoad(() => api('tournaments?' + qs({ status })), [status])
  const later = useDebounced(reload, 500)
  useEvents((e) => { if (e.resync || e.kind === 'tournament') later() })
  return html`<div class="page">
    <header class="page-head"><h1>Tournaments</h1></header>
    <div class="filters"><div class="seg text">${STATUSES.map((s) => html`<button key=${s} class=${status === s ? 'on' : ''} onClick=${() => setStatus(s)}>${s || 'All'}</button>`)}</div></div>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <${Card} pad=${false} cls=${loading ? 'loading' : ''}>
      <div class="table-wrap"><table class="table">
        <thead><tr><th>Name</th><th>Status</th><th>Format</th><th>Series</th><th>Game</th><th class="num">Players</th><th>Creator</th><th>Start</th><th>Top 3</th></tr></thead>
        <tbody>${data && data.list.map((t) => html`<tr key=${t.id} class="clickable" onClick=${() => go('tournaments/' + t.id)}>
          <td><b>${t.name}</b></td><td>${statusBadge(t.status)}</td><td>${FORMAT[t.format] || t.format}</td>
          <td>${SERIES[t.series] || t.series}, Bo${t.best_of}</td><td class="muted small">${t.pack_name}</td>
          <td class="num">${t.entrants}/${t.max_players}</td><td>${t.creator}</td>
          <td class="nowrap" title=${fullDate(t.start_at)}>${fullDate(t.start_at)}</td>
          <td>${t.top.map((p) => html`<span class=${'place top' + p.place}>${p.place}</span> ${p.name} `)}</td></tr>`)}</tbody>
      </table></div>
      ${data && !data.list.length && html`<${Empty}>No tournaments</${Empty}>`}
    </${Card}>
  </div>`
}

export function TournamentPage ({ id }) {
  const [data, error, reload] = useLoad(() => api('tournaments/' + id), [id])
  const [ask, setAsk] = useState(false)
  const later = useDebounced(reload, 500)
  useEvents((e) => { if (e.resync || (e.kind === 'tournament' && e.data && e.data.tournament === Number(id)) || e.kind === 'game_end') later() })
  const back = html`<a class="back" href="#/tournaments"><${Icon} name="back" size=${16} />Tournaments</a>`
  if (error && !data) return html`<div class="page">${back}<${ErrorBox} error=${error} onRetry=${reload} /></div>`
  if (!data) return html`<div class="page"><div class="skel-title"></div></div>`
  const t = data
  const cancel = async () => {
    setAsk(false)
    try { await api(`tournaments/${id}/cancel`, { method: 'POST' }); toast('Cancelled'); reload() } catch (e) { toast(e.message, 'err') }
  }
  // matches by bracket, then round
  const groups = {}
  for (const m of t.matches) (groups[m.bracket + ':' + m.round] = groups[m.bracket + ':' + m.round] || []).push(m)
  const order = Object.keys(groups).sort((a, b) => {
    const [ba, ra] = a.split(':'); const [bb, rb] = b.split(':')
    const rank = { w: 0, '': 0, l: 1, gf: 2 }
    return rank[ba] - rank[bb] || ra - rb
  })
  return html`<div class="page">
    ${back}
    <header class="page-head">
      <div><h1>${t.name}</h1>
        <div class="muted">${statusBadge(t.status)} ${t.reason ? html` <span class="muted">(${t.reason})</span>` : ''} · ${formatText(t)} · ${SERIES[t.series]} Bo${t.best_of}${t.bans ? ', 1 ban' : ''}
          · ${t.pack_name} · by ${t.creator} · starts ${fullDate(t.start_at)}${t.deck_reveal ? ' · decks revealed' : ''}${t.spectators ? ' · spectators' : ''}</div></div>
      ${ACTIVE.includes(t.status) && html`<button class="btn danger" onClick=${() => setAsk(true)}><${Icon} name="x" size=${16} />Cancel</button>`}
    </header>
    <div class="grid two-one">
      <${Card} title=${`Matches (${t.matches.length})`} pad=${false}>
        ${t.matches.length ? order.map((k) => {
          const [b, r] = k.split(':')
          return html`<div key=${k}><h3 class="sub">${BRACKET[b] ? BRACKET[b] + (b === 'gf' ? '' : ', round ' + r) : 'Round ' + r}</h3>
            <div class="table-wrap"><table class="table"><tbody>${groups[k].map((m) => html`<tr key=${m.id}>
              <td class=${m.winner && m.winner === m.p[0] ? 'ok-text' : ''}>${m.p[0] || html`<span class="muted">${m.status === 'pending' ? '?' : 'bye'}</span>`}</td>
              <td class="num mono">${m.score[0]} : ${m.score[1]}</td>
              <td class=${m.winner && m.winner === m.p[1] ? 'ok-text' : ''}>${m.p[1] || html`<span class="muted">${m.status === 'pending' ? '?' : 'bye'}</span>`}</td>
              <td><span class="badge">${m.status}</span></td>
              <td>${m.games.map((g) => html`<${GameLink} id=${g} /> `)}</td></tr>`)}</tbody></table></div></div>`
        }) : html`<${Empty}>Made at seeding (a minute before the start)</${Empty}>`}
      </${Card}>
      <${Card} title=${`Entrants (${t.entrants.length}/${t.max_players})`} pad=${false}>
        <div class="table-wrap"><table class="table">
          <thead><tr><th class="num">Place</th><th>Player</th><th class="num">Seed</th>${t.format === 'scheveningen' && html`<th>Team</th>`}<th class="num">Points</th><th class="num">Games</th><th>Decks</th></tr></thead>
          <tbody>${t.entrants.map((e) => html`<tr key=${e.name} class=${e.place > 0 && e.place <= 3 ? 'top-row' : ''}>
            <td class="num">${place(e.place)}</td><td>${e.name}${e.eliminated && html` <span class="badge warn">out</span>`}</td>
            <td class="num">${e.seed >= 0 ? e.seed + 1 : '—'}</td>${t.format === 'scheveningen' && html`<td>${e.team >= 0 ? 'ABC'[e.team] : '—'}</td>`}
            <td class="num">${e.points}</td><td class="num mono">${e.wins}–${e.losses}</td>
            <td class="small muted">${(e.decks || []).map((d) => d.hero).join(', ')}</td></tr>`)}</tbody>
        </table></div>
        ${!t.entrants.length && html`<${Empty}>Nobody has joined</${Empty}>`}
      </${Card}>
    </div>
    ${ask && html`<${Confirm} title="Cancel the tournament?" text=${`${t.name}: games already running play on, but no longer count.`} button="Cancel it" kind="danger" onClose=${() => setAsk(false)} onYes=${cancel} />`}
  </div>`
}
