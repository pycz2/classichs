// Problem reports from the game: the list (filters, unread marks, ticks, export, purge) and one
// report's thread (the player's and the admins' messages, pictures, voice, context, replays; answer,
// state, merge, note, delete, download it, copy it for an AI agent).

import { useState, useEffect } from 'preact/hooks'
import { api, qs } from './api.js'
import { playReplay } from './extra.js'
import { html, useEvents, useLoad, useDebounced, setQuery, go, Card, UserLink, GameLink, Pager, ErrorBox, Empty, Icon, Json, toast, copyText, fullDate, ago } from './ui.js'

const STATES = [['open', 'Open'], ['resolved', 'Resolved'], ['rejected', 'Rejected']]
const STATE_BADGE = { open: 'warn', resolved: 'ok', rejected: '' }

function State ({ s }) {
  return html`<span class=${'badge ' + (STATE_BADGE[s] || '')}>${s}</span>`
}

/** {new, answers} of the reports, kept fresh by the live feed (the menu and the dashboard). */
export function useReportCounts () {
  const [counts, setCounts] = useState({ new: 0, answers: 0 })
  const load = () => api('reports/counts').then(setCounts, () => {})
  const later = useDebounced(load, 400)
  useEffect(() => {
    load()
    const t = setInterval(load, 60000)
    addEventListener('hashchange', later) // (opening a report reads it)
    return () => { clearInterval(t); removeEventListener('hashchange', later) }
  }, [])
  useEvents((e) => { if (e.resync || e.kind === 'report' || (e.kind === 'admin' && e.data && String(e.data.action || '').startsWith('report'))) later() })
  return counts
}

export function Reports ({ query }) {
  const [f, setF] = useState(() => ({ state: '', player: '', version: '', ...query, page: Number(query.page || 0) }))
  const [draft, setDraft] = useState(f.player)
  const [ticked, setTicked] = useState(() => new Set())
  const [scope, setScope] = useState('filtered')
  const [days, setDays] = useState(90)
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
  const purge = async () => {
    if (!confirm(`Delete every report without activity in the last ${days} days, with its pictures and voice messages?`)) return
    try { const r = await api('reports/purge', { method: 'POST', body: { days: Number(days) } }); toast(`${r.removed} reports deleted`); reload() } catch (e) { toast(e.message, 'err') }
  }
  return html`<div class="page">
    <header class="page-head"><h1>Problem reports</h1>${data && html`<span class="muted">${data.counts.new} new · ${data.counts.answers} with the player's answer</span>`}</header>
    <div class="filters">
      <div class="seg text">${[['', 'All'], ...STATES].map(([s, label]) => html`<button key=${s} class=${f.state === s ? 'on' : ''} onClick=${() => set({ state: s })}>${label}</button>`)}</div>
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
          <th>#</th><th>Player</th><th>Text</th><th>Version</th><th>Platform</th><th>Attached</th><th class="num">Messages</th><th>State</th><th>Last activity</th>
        </tr></thead>
        <tbody>${list.map((r) => html`<tr key=${r.id} class=${'clickable' + (r.unread ? ' unread' : '')} onClick=${() => go('reports/' + r.id)}>
          <td onClick=${(e) => e.stopPropagation()}><input type="checkbox" aria-label=${'Tick report ' + r.id} checked=${ticked.has(r.id)} onChange=${(e) => tick(r.id, e.target.checked)} /></td>
          <td class="mono nowrap">${r.unread ? html`<span class="dot" title=${r.opened ? 'The player wrote since you looked' : 'New'}></span>` : ''}${r.id}</td>
          <td onClick=${(e) => e.stopPropagation()}><${UserLink} id=${r.account.id} user=${r.account.user} /></td>
          <td class="report-text">${r.text.length > 120 ? r.text.slice(0, 120) + '…' : r.text}</td>
          <td class="mono">${r.version || '—'}</td>
          <td>${(r.context && r.context.platform) || '—'}</td>
          <td class="nowrap">${[r.screen && 'picture', r.voice && 'voice', r.merged && `+${r.merged} merged`].filter(Boolean).join(' · ')}</td>
          <td class="num">${r.messages}</td>
          <td><${State} s=${r.state} /></td>
          <td class="nowrap" title=${fullDate(r.last_at * 1000)}>${ago(r.last_at * 1000)}</td>
        </tr>`)}</tbody>
      </table></div>
      ${data && !list.length && html`<${Empty}>No reports match</${Empty}>`}
      ${data && html`<div class="table-foot"><span class="row-gap">
          Delete reports without activity for <input type="number" min="1" class="days" value=${days} onInput=${(e) => setDays(e.target.value)} aria-label="Days" /> days
          <button class="btn ghost sm" disabled=${!(days >= 1)} onClick=${purge}><${Icon} name="trash" size=${14} /> Purge</button></span>
        <${Pager} page=${f.page} size=${50} total=${data.total} onPage=${(page) => setF((x) => ({ ...x, page }))} /></div>`}
    </${Card}>
  </div>`
}

// --- one report ---------------------------------------------------------------------------------

export function ReportPage ({ id }) {
  const [data, error, reload] = useLoad(() => api('reports/' + id), [id])
  const [md, , reloadMd] = useLoad(() => fetch(`/admin/api/reports/${id}/markdown`, { credentials: 'same-origin' }).then((r) => r.ok ? r.text() : ''), [id])
  const [note, setNote] = useState(null)
  const [answer, setAnswer] = useState('')
  const [into, setInto] = useState('')
  const [busy, setBusy] = useState(false)
  useEffect(() => { if (data) { setNote(data.note); reloadMd() } }, [data])
  const later = useDebounced(reload, 500)
  useEvents((e) => { if (e.kind === 'report' && e.data && data && [data.id, ...data.merged.map((m) => m.id)].includes(e.data.report)) later() })
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
    if (!confirm(`Delete report ${id} with its thread, pictures and voice message?`)) return
    try { await api(`reports/${id}/delete`, { method: 'POST' }); toast('Deleted'); go('reports') } catch (e) { toast(e.message, 'err') }
  }
  const file = (f) => `/admin/api/reports/${id}/${f}`
  const voices = [data, ...data.merged].filter((r) => r.voice)
  return html`<div class="page report-page">
    ${back}
    <header class="page-head">
      <div>
        <h1>Report #${data.id} ${data.merged_into ? html`<span class="badge">merged into <a href=${'#/reports/' + data.merged_into}>#${data.merged_into}</a></span>` : ''}</h1>
        <div class="muted"><${UserLink} id=${data.account.id} user=${data.account.user} />${data.account.tag ? html` <span class="mono">#${data.account.tag}</span>` : ''} · account ${data.account.id} ·
          written ${fullDate(data.written_at * 1000)} (the player's clock) · received ${fullDate(data.received_at * 1000)}</div>
      </div>
      <div class="row-gap">
        <div class="seg text" role="radiogroup" aria-label="State">${STATES.map(([s, label]) => html`<button key=${s} role="radio" aria-checked=${data.state === s} class=${data.state === s ? 'on' : ''} disabled=${busy} onClick=${() => act('state', { state: s })}>${label}</button>`)}</div>
        <a class="btn ghost sm" href=${file('export')} download=${`report-${id}.zip`}>Download this report</a>
        <button class="btn ghost sm" disabled=${!md} onClick=${() => copyText(md, 'Copied: paste it to the agent')} title="A Markdown text with everything an AI agent needs to reproduce and fix it"><${Icon} name="copy" size=${14} /> Copy for an agent</button>
        <button class="btn ghost sm" onClick=${remove}><${Icon} name="trash" size=${14} /> Delete</button>
      </div>
    </header>
    <div class="grid two-one">
      <div class="stack">
        <${Card} title=${`Thread (${data.thread.length})`}>
          <ol class="thread">${data.thread.map((m) => html`<li key=${m.report + ':' + m.id} class=${'msg ' + m.from}>
            <div class="msg-head"><b>${m.from === 'admin' ? m.name + ' (admin)' : m.name}</b>${m.report !== data.id ? html` <a class="muted small" href=${'#/reports/' + m.report}>report #${m.report}</a>` : ''}
              <span class="muted small" title=${fullDate(m.at * 1000)}>${ago(m.at * 1000)}</span></div>
            <p class="report-full">${m.text}</p>
            ${m.screen && html`<a href=${file(m.screen)} target="_blank" rel="noopener"><img class="report-shot" src=${file(m.screen)} alt="The player's picture" loading="lazy" /></a>`}
          </li>`)}</ol>
          <div class="answer">
            <textarea rows="3" maxlength="4000" value=${answer} onInput=${(e) => setAnswer(e.target.value)} placeholder=${'An answer to ' + (data.merged.length ? 'the players (each sees it in his own thread)' : 'the player')}></textarea>
            <div class="row-gap">
              <button class="btn sm" disabled=${busy || !answer.trim()} onClick=${() => act('answer', { text: answer }, 'Sent').then((ok) => ok && setAnswer(''))}>Send the answer</button>
              <button class="btn ghost sm" disabled=${busy || !answer.trim()} onClick=${() => act('answer', { text: answer }).then((ok) => ok && act('state', { state: 'resolved' }, 'Sent and resolved')).then((ok) => ok && setAnswer(''))}>Send and resolve</button>
            </div>
          </div>
        </${Card}>
        ${voices.map((r) => html`<${Card} key=${'v' + r.id} title=${'Voice message' + (r.id !== data.id ? ` (report #${r.id})` : '')}
          actions=${html`<a class="btn ghost sm" href=${file('voice.ogg?of=' + r.id)} download=${`report-${r.id}.ogg`}>Download</a>`}>
          <audio controls preload="metadata" src=${file('voice.ogg?of=' + r.id)}></audio></${Card}>`)}
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
        <${Card} title=${`Duplicates (${data.merged.length})`}>
          ${data.merged.length ? html`<ul class="rows report-games">${data.merged.map((m) => html`<li key=${m.id}>
            <a href=${'#/reports/' + m.id}>#${m.id}</a> <${UserLink} id=${m.account.id} user=${m.account.user} />
            <span class="muted small">${m.context && m.context.version} · ${m.context && m.context.platform}</span></li>`)}</ul>` : ''}
          <div class="row-gap">
            ${data.merged_into
              ? html`<button class="btn ghost sm" disabled=${busy} onClick=${() => act('unmerge', {}, 'Taken out')}>Take it out of #${data.merged_into}</button>`
              : html`<input type="number" min="1" class="days" placeholder="#" value=${into} onInput=${(e) => setInto(e.target.value)} aria-label="The report to merge into" />
                <button class="btn ghost sm" disabled=${busy || !into} onClick=${() => act('merge', { into: Number(into) }, 'Merged').then((ok) => ok && go('reports/' + into))}>Merge into it</button>`}
          </div>
          <p class="muted small">A duplicate goes under the other report; its player still sees his own thread and gets the answers.</p>
        </${Card}>
        <${Card} title="Note">
          <textarea rows="4" value=${note ?? ''} onInput=${(e) => setNote(e.target.value)} placeholder="Only admins see it"></textarea>
          <div class="row-gap"><button class="btn sm" disabled=${busy || note === data.note} onClick=${() => act('note', { note }, 'Saved')}>Save the note</button></div>
        </${Card}>
      </div>
    </div>
  </div>`
}
