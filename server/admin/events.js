// The event log: filters, sorting, paging and a live tail.

import { useState, useEffect } from 'preact/hooks'
import { api, qs } from './api.js'
import { html, useEvents, useLoad, useDebounced, setQuery, Card, Kind, NameLink, GameLink, Pager, SortTh, ErrorBox, Empty, Icon, Json, CATS, KINDS, kindCat, clock, fullDate } from './ui.js'

const pad = (n) => String(n).padStart(2, '0')
/** ms → the value of an <input type=datetime-local> (local time). */
function toLocalInput (ms) {
  if (!ms) return ''
  const d = new Date(Number(ms))
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** Does a live event pass the filters (the same rules as the server's)? */
export function matches (e, f) {
  const kinds = f.kind ? f.kind.split(',') : []
  if (kinds.length && !kinds.includes(e.kind)) return false
  const lc = (s) => (s || '').toLowerCase()
  if (f.user && lc(e.user) !== lc(f.user) && lc(e.other) !== lc(f.user)) return false
  if (f.game && e.game !== f.game) return false
  if (f.from && e.at < Number(f.from)) return false
  if (f.to && e.at > Number(f.to)) return false
  if (f.q) {
    const q = lc(f.q)
    if (!lc(e.text).includes(q) && !lc(JSON.stringify(e.data)).includes(q)) return false
  }
  return true
}

export function Events ({ query }) {
  const [f, setF] = useState(() => ({ kind: '', user: '', game: '', from: '', to: '', q: '', sort: 'time', dir: 'desc', size: '100', ...query, page: Number(query.page || 0) }))
  const [tail, setTail] = useState(query.tail !== '0')
  const [draft, setDraft] = useState({ user: f.user, game: f.game, q: f.q })
  const [fresh, setFresh] = useState(0)
  const [open, setOpen] = useState(null)
  const [extra, setExtra] = useState([])
  const set = (patch) => setF((x) => ({ ...x, page: 0, ...patch }))
  useEffect(() => { setQuery({ ...f, page: f.page || '', sort: f.sort === 'time' ? '' : f.sort, dir: f.dir === 'desc' ? '' : f.dir, size: f.size === '100' ? '' : f.size, tail: tail ? '' : '0' }) }, [f, tail])
  const commit = useDebounced((d) => set(d), 350)
  const [data, error, reload, loading] = useLoad(
    () => api('events?' + qs({ ...f, sort: f.sort === 'time' ? '' : f.sort })),
    [f]
  )
  useEffect(() => { setExtra([]); setFresh(0) }, [data])
  const live = tail && f.page === 0 && f.sort === 'time' && f.dir === 'desc'
  useEvents((e) => {
    if (e.resync) return reload()
    if (!matches(e, f)) return
    if (live) setExtra((x) => [e, ...x].slice(0, Number(f.size)))
    else setFresh((n) => n + 1)
  })
  const rows = data ? [...extra, ...data.list].slice(0, Number(f.size)) : []
  const total = data ? data.total + extra.length : 0
  const kinds = f.kind ? f.kind.split(',') : []
  const toggleCat = (cat) => {
    const inCat = Object.keys(KINDS).filter((k) => KINDS[k] === cat)
    const all = inCat.every((k) => kinds.includes(k))
    set({ kind: (all ? kinds.filter((k) => !inCat.includes(k)) : [...new Set([...kinds, ...inCat])]).join(',') })
  }
  return html`<div class="page">
    <header class="page-head">
      <h1>Event log</h1>
      <div class="head-actions">
        <button class=${'btn ' + (tail ? 'live-on' : 'ghost')} onClick=${() => setTail(!tail)} title="New events appear at the top as they happen">
          <${Icon} name=${tail ? 'pause' : 'play'} size=${15} />${tail ? 'Live tail on' : 'Live tail off'}</button>
        <button class="btn ghost" onClick=${reload} title="Reload"><${Icon} name="refresh" size=${15} /></button>
      </div>
    </header>
    <div class="filters">
      <label class="search"><${Icon} name="search" size=${16} /><input placeholder="Search text and details" value=${draft.q}
        onInput=${(e) => { const d = { ...draft, q: e.target.value }; setDraft(d); commit(d) }} /></label>
      <input placeholder="User" value=${draft.user} size="12" onInput=${(e) => { const d = { ...draft, user: e.target.value }; setDraft(d); commit(d) }} />
      <input placeholder="Game id" value=${draft.game} size="16" class="mono" onInput=${(e) => { const d = { ...draft, game: e.target.value }; setDraft(d); commit(d) }} />
      <label class="field-inline">From<input type="datetime-local" value=${toLocalInput(f.from)} onChange=${(e) => set({ from: e.target.value ? new Date(e.target.value).getTime() : '' })} /></label>
      <label class="field-inline">To<input type="datetime-local" value=${toLocalInput(f.to)} onChange=${(e) => set({ to: e.target.value ? new Date(e.target.value).getTime() + 59999 : '' })} /></label>
      ${(f.kind || f.user || f.game || f.from || f.to || f.q) && html`<button class="btn ghost sm" onClick=${() => { setDraft({ user: '', game: '', q: '' }); set({ kind: '', user: '', game: '', from: '', to: '', q: '' }) }}>Clear filters</button>`}
    </div>
    <div class="catbar">
      ${Object.entries(CATS).map(([cat, label]) => {
        const inCat = Object.keys(KINDS).filter((k) => KINDS[k] === cat)
        const n = inCat.filter((k) => kinds.includes(k)).length
        return html`<div class=${'catgroup cat-' + cat + (n ? ' some' : '')} key=${cat}>
          <button class="cat-btn" onClick=${() => toggleCat(cat)} title=${'All ' + label.toLowerCase()}>${label}</button>
          ${inCat.map((k) => html`<button key=${k} class=${'kbtn' + (kinds.includes(k) ? ' on' : '')}
            onClick=${() => set({ kind: (kinds.includes(k) ? kinds.filter((x) => x !== k) : [...kinds, k]).join(',') })}>${k.replace(/_/g, ' ')}</button>`)}
        </div>`
      })}
    </div>
    <${ErrorBox} error=${error} onRetry=${reload} />
    ${fresh > 0 && html`<button class="banner" onClick=${() => { setFresh(0); reload() }}>${fresh} new matching event${fresh > 1 ? 's' : ''}: show</button>`}
    <${Card} pad=${false} cls=${loading ? 'loading' : ''}>
      <div class="table-wrap"><table class="table events">
        <thead><tr>
          <${SortTh} col="time" sort=${f.sort} dir=${f.dir} onSort=${(sort, dir) => set({ sort, dir })} cls="w-time">Time</${SortTh}>
          <${SortTh} col="kind" sort=${f.sort} dir=${f.dir} onSort=${(sort, dir) => set({ sort, dir })}>Kind</${SortTh}>
          <${SortTh} col="user" sort=${f.sort} dir=${f.dir} onSort=${(sort, dir) => set({ sort, dir })}>User</${SortTh}>
          <th>Other</th><th>Game</th><th class="w-text">What happened</th>
        </tr></thead>
        <tbody>
          ${rows.map((e) => html`<${Row} key=${e.id} e=${e} fresh=${extra.includes(e)} open=${open === e.id} onToggle=${() => setOpen(open === e.id ? null : e.id)} onFilter=${set} />`)}
        </tbody>
      </table></div>
      ${data && !rows.length && html`<${Empty}>No events match</${Empty}>`}
      <div class="table-foot">
        <label class="field-inline">Rows<select value=${f.size} onChange=${(e) => set({ size: e.target.value })}>${['50', '100', '250', '500'].map((n) => html`<option>${n}</option>`)}</select></label>
        ${data && html`<${Pager} page=${f.page} size=${Number(f.size)} total=${total} onPage=${(page) => setF((x) => ({ ...x, page }))} />`}
      </div>
    </${Card}>
  </div>`
}

function Row ({ e, fresh, open, onToggle, onFilter }) {
  return html`<tr class=${'erow' + (fresh ? ' fresh' : '') + (open ? ' open' : '') + ' row-' + kindCat(e.kind)} onClick=${onToggle}>
      <td class="mono nowrap" title=${fullDate(e.at)}>${clock(e.at)}</td>
      <td><button class="linkish" onClick=${(ev) => { ev.stopPropagation(); onFilter({ kind: e.kind }) }} title="Only this kind"><${Kind} kind=${e.kind} /></button></td>
      <td onClick=${(ev) => ev.stopPropagation()}><${NameLink} name=${e.user} /></td>
      <td onClick=${(ev) => ev.stopPropagation()}><${NameLink} name=${e.other} /></td>
      <td onClick=${(ev) => ev.stopPropagation()}>${e.game && html`<${GameLink} id=${e.game} />`}</td>
      <td class="etext">${e.text}</td>
    </tr>
    ${open && html`<tr class="details"><td colspan="6">
      <div class="detail-grid">
        <div><span class="muted">Event</span> #${e.id} · ${fullDate(e.at)}.${String(e.at % 1000).padStart(3, '0')}</div>
        ${e.account != null && html`<div><span class="muted">Account</span> <a href=${'#/accounts/' + e.account}>#${e.account}</a></div>`}
        ${e.game && html`<div><span class="muted">Game</span> <a class="mono" href=${'#/games/' + e.game}>${e.game}</a> · <a href=${'#/events?game=' + e.game}>its events</a></div>`}
      </div>
      ${e.data != null ? html`<${Json} value=${e.data} />` : html`<span class="muted">No details</span>`}
    </td></tr>`}`
}
