// Problem reports from the game: the list (filters, ticks, export) and one report (its text, picture,
// voice, context, games; the state, a note, an answer as a private message).

import { useState, useEffect } from 'preact/hooks'
import { api, qs } from './api.js'
import { playReplay } from './extra.js'
import { html, useEvents, useLoad, useDebounced, setQuery, go, Card, UserLink, GameLink, Pager, ErrorBox, Empty, Icon, Json, toast, fullDate, ago } from './ui.js'

const STATES = ['new', 'seen', 'done']
const STATE_BADGE = { new: 'warn', seen: '', done: 'ok' }

function State ({ s }) {
  return html`<span class=${'badge ' + (STATE_BADGE[s] || '')}>${s}</span>`
}

export function Reports ({ query }) {
  const [f, setF] = useState(() => ({ state: '', player: '', version: '', ...query, page: Number(query.page || 0) }))
  const [draft, setDraft] = useState(f.player)
  const [ticked, setTicked] = useState(() => new Set())
  const [scope, setScope] = useState('filtered')
  const set = (p) => setF((x) => ({ ...x, page: 0, ...p }))
  const commit = useDebounced((player) => set({ player }), 350)
  useEffect(() => { setQuery({ ...f, page: f.page || '' }) }, [f])
  const [data, error, reload, loading] = useLoad(() => api('reports?' + qs({ ...f, size: 50 })), [f])
  const later = useDebounced(reload, 500)
  useEvents((e) => { if (e.resync || e.kind === 'report') later() })
  const tick = (id, on) => setTicked((t) => { const n = new Set(t); on ? n.add(id) : n.delete(id); return n })
  const list = data ? data.list : []
  const allOn = list.length > 0 && list.every((r) => ticked.has(r.id))
  const what = scope === 'ticked' ? { ids: [...ticked].join(',') } : scope === 'filtered' ? { state: f.state, player: f.player, version: f.version } : {}
  const href = (format) => '/admin/api/reports/export?' + qs({ ...what, format })
  const none = scope === 'ticked' && !ticked.size
  return html`<div class="page">
    <header class="page-head"><h1>Problem reports</h1>${data && html`<span class="muted">${data.new} new</span>`}</header>
    <div class="filters">
      <div class="seg text">${['', ...STATES].map((s) => html`<button key=${s} class=${f.state === s ? 'on' : ''} onClick=${() => set({ state: s })}>${s ? s[0].toUpperCase() + s.slice(1) : 'All'}</button>`)}</div>
      <label class="search"><${Icon} name="search" size=${16} /><input placeholder="Player" value=${draft} onInput=${(e) => { setDraft(e.target.value); commit(e.target.value) }} /></label>
      <select value=${f.version} onChange=${(e) => set({ version: e.target.value })} aria-label="Version">
        <option value="">Any version</option>${data && data.versions.map((v) => html`<option key=${v} value=${v}>${v || '(none)'}</option>`)}
      </select>
    </div>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <${Card} title="Reports" pad=${false} cls=${loading ? 'loading' : ''}
      actions=${html`<select value=${scope} onChange=${(e) => setScope(e.target.value)} aria-label="Which reports to export">
          <option value="all">All</option><option value="filtered">As filtered</option><option value="ticked">Ticked (${ticked.size})</option></select>
        <a class=${'btn sm' + (none ? ' disabled' : '')} href=${none ? undefined : href('zip')} download>Export zip</a>
        <a class=${'btn ghost sm' + (none ? ' disabled' : '')} href=${none ? undefined : href('json')} download>Export JSON</a>`}>
      <div class="table-wrap"><table class="table">
        <thead><tr>
          <th><input type="checkbox" aria-label="Tick all on this page" checked=${allOn} onChange=${(e) => list.forEach((r) => tick(r.id, e.target.checked))} /></th>
          <th>#</th><th>Player</th><th>Text</th><th>Version</th><th>Platform</th><th>Attached</th><th>State</th><th>Received</th>
        </tr></thead>
        <tbody>${list.map((r) => html`<tr key=${r.id} class="clickable" onClick=${() => go('reports/' + r.id)}>
          <td onClick=${(e) => e.stopPropagation()}><input type="checkbox" aria-label=${'Tick report ' + r.id} checked=${ticked.has(r.id)} onChange=${(e) => tick(r.id, e.target.checked)} /></td>
          <td class="mono">${r.id}</td>
          <td onClick=${(e) => e.stopPropagation()}><${UserLink} id=${r.account.id} user=${r.account.user} /></td>
          <td class="report-text">${r.text.length > 120 ? r.text.slice(0, 120) + '…' : r.text}</td>
          <td class="mono">${r.version || '—'}</td>
          <td>${(r.context && r.context.platform) || '—'}</td>
          <td class="nowrap">${r.screen ? 'picture' : ''}${r.screen && r.voice ? ' · ' : ''}${r.voice ? 'voice' : ''}</td>
          <td><${State} s=${r.state} /></td>
          <td class="nowrap" title=${fullDate(r.received_at * 1000)}>${ago(r.received_at * 1000)}</td>
        </tr>`)}</tbody>
      </table></div>
      ${data && !list.length && html`<${Empty}>No reports match</${Empty}>`}
      ${data && html`<div class="table-foot"><span></span><${Pager} page=${f.page} size=${50} total=${data.total} onPage=${(page) => setF((x) => ({ ...x, page }))} /></div>`}
    </${Card}>
  </div>`
}

// --- one report ---------------------------------------------------------------------------------

export function ReportPage ({ id }) {
  const [data, error, reload] = useLoad(() => api('reports/' + id), [id])
  const [note, setNote] = useState(null)
  const [answer, setAnswer] = useState('')
  const [busy, setBusy] = useState(false)
  useEffect(() => { if (data) setNote(data.note) }, [data])
  const act = async (what, body, done) => {
    setBusy(true)
    let ok = false
    try { await api(`reports/${id}/${what}`, { method: 'POST', body }); if (done) toast(done); reload(); ok = true } catch (e) { toast(e.message, 'err') }
    setBusy(false)
    return ok
  }
  const back = html`<a class="back" href="#/reports"><${Icon} name="back" size=${16} />Problem reports</a>`
  if (error && !data) return html`<div class="page">${back}<${ErrorBox} error=${error} onRetry=${reload} /></div>`
  if (!data) return html`<div class="page"><div class="skel-title"></div></div>`
  const c = data.context || {}
  const remove = async () => {
    if (!confirm(`Delete report ${id} with its picture and voice message?`)) return
    try { await api(`reports/${id}/delete`, { method: 'POST' }); toast('Deleted'); go('reports') } catch (e) { toast(e.message, 'err') }
  }
  const file = (f) => `/admin/api/reports/${id}/${f}`
  return html`<div class="page report-page">
    ${back}
    <header class="page-head">
      <div>
        <h1>Report #${data.id}</h1>
        <div class="muted"><${UserLink} id=${data.account.id} user=${data.account.user} />${data.account.tag ? html` <span class="mono">#${data.account.tag}</span>` : ''} · account ${data.account.id} ·
          written ${fullDate(data.written_at * 1000)} (the player's clock) · received ${fullDate(data.received_at * 1000)}</div>
      </div>
      <div class="row-gap">
        <div class="seg text" role="radiogroup" aria-label="State">${STATES.map((s) => html`<button key=${s} role="radio" aria-checked=${data.state === s} class=${data.state === s ? 'on' : ''} disabled=${busy} onClick=${() => act('state', { state: s })}>${s}</button>`)}</div>
        <button class="btn ghost sm" onClick=${remove}><${Icon} name="trash" size=${14} /> Delete</button>
      </div>
    </header>
    <div class="grid two-one">
      <div class="stack">
        <${Card} title="Text"><p class="report-full">${data.text}</p></${Card}>
        ${data.screen && html`<${Card} title="Picture" actions=${html`<a class="btn ghost sm" href=${file('screen.png')} download=${`report-${id}.png`}>Download</a>`}>
          <a href=${file('screen.png')} target="_blank" rel="noopener"><img class="report-shot" src=${file('screen.png')} alt="The player's screen" /></a></${Card}>`}
        ${data.voice && html`<${Card} title="Voice message" actions=${html`<a class="btn ghost sm" href=${file('voice.ogg')} download=${`report-${id}.ogg`}>Download</a>`}>
          <audio controls preload="metadata" src=${file('voice.ogg')}></audio></${Card}>`}
      </div>
      <div class="stack">
        <${Card} title="Context">
          <dl class="kv">
            <dt>Version</dt><dd class="mono">${c.version || '—'}</dd>
            <dt>Platform</dt><dd>${c.platform || '—'}</dd>
            <dt>Screen</dt><dd>${c.screen || '—'}</dd>
            <dt>Language</dt><dd>${c.language || '—'}</dd>
            <dt>Game</dt><dd>${c.pack ? html`${c.pack.id} ${c.pack.version} <span class="muted small mono">${(c.pack.rules_hash || '').slice(0, 12)}</span>` : '—'}</dd>
            <dt>Sent from</dt><dd>${c.game ? html`the match <${GameLink} id=${c.game} />` : 'the menu'}</dd>
          </dl>
          <details><summary class="muted small">All of it</summary><${Json} value=${c} /></details>
        </${Card}>
        <${Card} title=${`Games (${data.games.length})`} pad=${false}>
          ${data.games.length ? html`<ul class="rows report-games">${data.games.map((g) => html`<li key=${g.game}>
            <${GameLink} id=${g.game} />
            ${g.replay ? html` <span class="muted small">${g.mode} · ${(g.players || []).join(' vs ')}${g.ended ? ' · ' + ago(g.ended * 1000) : ''}</span>
              <button class="btn ghost sm" onClick=${() => playReplay(g.game)}><${Icon} name="play" size=${14} /> Play</button>
              <a class="btn ghost sm" href=${'/admin/api/games/' + encodeURIComponent(g.game) + '/replay'} download=${g.game + '.chsreplay'}>Replay</a>`
              : html` <span class="muted small">no replay (yet)</span>`}
          </li>`)}</ul>` : html`<${Empty}>No games</${Empty}>`}
        </${Card}>
        <${Card} title="Note">
          <textarea rows="4" value=${note ?? ''} onInput=${(e) => setNote(e.target.value)} placeholder="Only admins see it"></textarea>
          <div class="row-gap"><button class="btn sm" disabled=${busy || note === data.note} onClick=${() => act('note', { note }, 'Saved')}>Save the note</button></div>
        </${Card}>
        <${Card} title="Answer the player">
          ${data.answer && html`<p class="muted small">Answered${data.answer.at ? ' ' + fullDate(data.answer.at * 1000) : ''}:</p><p class="report-full">${data.answer.text || '(the message is gone)'}</p>`}
          <textarea rows="3" maxlength="500" value=${answer} onInput=${(e) => setAnswer(e.target.value)} placeholder="A private message from you to the player"></textarea>
          <div class="row-gap"><button class="btn sm" disabled=${busy || !answer.trim()} onClick=${() => act('answer', { text: answer }, 'Sent').then((ok) => ok && setAnswer(''))}>Send as a private message</button></div>
        </${Card}>
      </div>
    </div>
  </div>`
}
