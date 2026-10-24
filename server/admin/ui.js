// Shared pieces: htm, the live event bus, contexts, formatting and small components.

import { h, createContext } from 'preact'
import { useState, useEffect, useContext, useRef, useCallback } from 'preact/hooks'
import htm from 'htm'

export const html = htm.bind(h)

// --- live data ----------------------------------------------------------------

/** Every event from /admin/ws goes to the subscribers ({resync: true} after a gap). */
const subs = new Set()
export const bus = {
  on (fn) { subs.add(fn); return () => subs.delete(fn) },
  emit (e) { for (const fn of [...subs]) { try { fn(e) } catch (err) { console.error(err) } } }
}

/** Calls fn(event) for every live event while mounted (always the latest fn). */
export function useEvents (fn) {
  const ref = useRef(fn)
  ref.current = fn
  useEffect(() => bus.on((e) => ref.current(e)), [])
}

/** {live: {online, queue, games}, conn: 'live'|'connecting'|'offline'} */
export const LiveContext = createContext({ live: { online: [], queue: [], games: [] }, conn: 'connecting' })
export const MeContext = createContext(null)
export const useLive = () => useContext(LiveContext)
export const useMe = () => useContext(MeContext)

/** Re-renders every `ms` (for "3 s ago"). */
export function useTick (ms = 1000) {
  const [, set] = useState(0)
  useEffect(() => { const t = setInterval(() => set((x) => x + 1), ms); return () => clearInterval(t) }, [ms])
}

/** Runs `load` now and whenever deps change; returns [data, error, reload, loading]. */
export function useLoad (load, deps) {
  const [state, setState] = useState({ data: null, error: null, loading: true })
  const seq = useRef(0)
  const run = useCallback(() => {
    const n = ++seq.current
    setState((s) => ({ ...s, loading: true }))
    load().then(
      (data) => { if (n === seq.current) setState({ data, error: null, loading: false }) },
      (error) => { if (n === seq.current) setState((s) => ({ data: s.data, error, loading: false })) }
    )
  }, deps)
  useEffect(run, [run])
  return [state.data, state.error, run, state.loading]
}

/** A function that runs at most once per `ms` (the last call wins). */
export function useDebounced (fn, ms) {
  const t = useRef(0)
  const ref = useRef(fn)
  ref.current = fn
  useEffect(() => () => clearTimeout(t.current), [])
  return useCallback((...a) => { clearTimeout(t.current); t.current = setTimeout(() => ref.current(...a), ms) }, [ms])
}

// --- routing (#/path?query) -----------------------------------------------------------

export function parseHash () {
  const raw = location.hash.replace(/^#\/?/, '')
  const [p, q] = raw.split('?')
  return { path: p.split('/').filter(Boolean).map(decodeURIComponent), query: Object.fromEntries(new URLSearchParams(q || '')) }
}

export function useRoute () {
  const [r, set] = useState(parseHash)
  useEffect(() => {
    const on = () => set(parseHash())
    addEventListener('hashchange', on)
    return () => removeEventListener('hashchange', on)
  }, [])
  return r
}

export const go = (path) => { location.hash = '#/' + path }

/** Replaces the query of the current page (no new history entry). */
export function setQuery (q) {
  const { path } = parseHash()
  const s = new URLSearchParams(Object.entries(q).filter(([, v]) => v !== '' && v != null && v !== false)).toString()
  history.replaceState(null, '', '#/' + path.map(encodeURIComponent).join('/') + (s ? '?' + s : ''))
}

// --- formatting ---------------------------------------------------------------------------

const pad = (n) => String(n).padStart(2, '0')

/** ms → "14:03:22" today, else "Oct 12 14:03". */
export function clock (ms, seconds = true) {
  if (ms == null) return '—'
  const d = new Date(ms)
  const t = pad(d.getHours()) + ':' + pad(d.getMinutes()) + (seconds ? ':' + pad(d.getSeconds()) : '')
  return new Date().toDateString() === d.toDateString() ? t : d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) + ' ' + t
}

export function fullDate (ms) {
  if (ms == null) return ''
  const d = new Date(ms)
  return d.toLocaleString(undefined, { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

export function ago (ms) {
  if (ms == null) return '—'
  const s = Math.max(0, Math.round((Date.now() - ms) / 1000))
  if (s < 5) return 'just now'
  if (s < 60) return s + ' s ago'
  if (s < 3600) return Math.floor(s / 60) + ' min ago'
  if (s < 86400) return Math.floor(s / 3600) + ' h ago'
  if (s < 86400 * 30) return Math.floor(s / 86400) + ' d ago'
  return new Date(ms).toLocaleDateString()
}

/** seconds → "4:05" or "1:02:03" */
export function dur (s) {
  s = Math.max(0, Math.round(s))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  return (h ? h + ':' + pad(m) : m) + ':' + pad(s % 60)
}

export const num = (n) => (n ?? 0).toLocaleString()

/** 12345678 → "11.8 MB" */
export function bytes (n) {
  n = n || 0
  if (n < 1024) return n + ' B'
  const u = ['KB', 'MB', 'GB', 'TB']
  let i = -1
  do { n /= 1024; i++ } while (n >= 1024 && i < u.length - 1)
  return (n < 10 ? n.toFixed(1) : Math.round(n)) + ' ' + u[i]
}

export function rankText (a) {
  if (a.rank === 0) return a.legend ? 'Legend #' + a.legend : 'Legend'
  return 'Rank ' + a.rank
}

// --- event kinds ----------------------------------------------------------------------------

export const CATS = {
  auth: 'Logins',
  social: 'Social',
  chat: 'Chat',
  queue: 'Queues',
  game: 'Matches',
  pack: 'Game packs',
  admin: 'Admin',
  error: 'Problems'
}

export const KINDS = {
  register: 'auth', login: 'auth', logout: 'auth', disconnect: 'auth', kicked: 'auth', admin_login: 'auth', admin_logout: 'auth',
  login_failed: 'error', error: 'error',
  tag: 'social', friend_request: 'social', friend_accept: 'social', friend_decline: 'social', friend_remove: 'social',
  block: 'social', unblock: 'social', invite: 'social', invite_accept: 'social', invite_decline: 'social',
  msg: 'chat',
  queue: 'queue', unqueue: 'queue', arena: 'queue',
  match: 'game', game_start: 'game', game_action: 'game', game_left: 'game', game_back: 'game', game_end: 'game',
  pack_upload: 'pack', pack_import: 'pack', pack_default: 'pack', pack_enable: 'pack', pack_disable: 'pack', pack_delete: 'pack', pack_download: 'pack', pack_rejected: 'error',
  admin: 'admin',
  bot: 'error'
}

export const kindCat = (k) => KINDS[k] || 'admin'

export function Kind ({ kind }) {
  return html`<span class=${'kind cat-' + kindCat(kind)}>${kind.replace(/_/g, ' ')}</span>`
}

// --- small components ---------------------------------------------------------------------------

const ICONS = {
  dashboard: 'M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z',
  events: 'M4 6h16M4 12h16M4 18h10',
  games: 'M6 4h12a2 2 0 012 2v12a2 2 0 01-2 2H6a2 2 0 01-2-2V6a2 2 0 012-2zm3 5l6 3-6 3V9z',
  accounts: 'M16 11a4 4 0 10-8 0 4 4 0 008 0zM4 21a8 8 0 0116 0',
  messages: 'M4 5h16v11H8l-4 4V5z',
  sun: 'M12 4V2m0 20v-2m8-8h2M2 12h2m13.66-5.66l1.42-1.42M4.92 19.08l1.42-1.42m0-11.32L4.92 4.92m14.16 14.16l-1.42-1.42M12 7a5 5 0 100 10 5 5 0 000-10z',
  moon: 'M21 12.8A9 9 0 1111.2 3a7 7 0 009.8 9.8z',
  system: 'M3 5h18v11H3zM8 21h8M12 16v5',
  logout: 'M15 4h4v16h-4M10 8l-4 4 4 4M6 12h11',
  search: 'M11 4a7 7 0 100 14 7 7 0 000-14zm9 16l-4-4',
  plus: 'M12 5v14M5 12h14',
  x: 'M6 6l12 12M18 6L6 18',
  live: 'M12 9a3 3 0 100 6 3 3 0 000-6zM5.6 5.6a9 9 0 000 12.8m12.8 0a9 9 0 000-12.8',
  back: 'M15 18l-6-6 6-6',
  chevron: 'M9 6l6 6-6 6',
  pause: 'M8 5v14M16 5v14',
  play: 'M7 5l12 7-12 7V5z',
  refresh: 'M20 11a8 8 0 10-2.3 5.7M20 4v7h-7',
  packs: 'M21 8l-9-5-9 5v8l9 5 9-5V8zM3 8l9 5 9-5M12 13v8M7.5 5.5l9 5',
  upload: 'M12 15V4m-5 5l5-5 5 5M4 15v4a1 1 0 001 1h14a1 1 0 001-1v-4',
  star: 'M12 3l2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3 6.4 20.2l1.1-6.2L3 9.6l6.2-.9L12 3z',
  bots: 'M12 3v3M8 3h8M5 8h14v10a2 2 0 01-2 2H7a2 2 0 01-2-2V8zM9.5 13h.01M14.5 13h.01M9 17h6',
  trash: 'M4 7h16M10 11v6m4-6v6M6 7l1 12a2 2 0 002 2h6a2 2 0 002-2l1-12M9 7V4h6v3'
}

export function Icon ({ name, size = 18 }) {
  return html`<svg class="icon" width=${size} height=${size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
    stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d=${ICONS[name]} /></svg>`
}

const STATUS = { online: 'Online', in_game: 'In game', searching: 'Searching', offline: 'Offline' }

export function Status ({ status, label = true }) {
  const s = status || 'offline'
  return html`<span class=${'status st-' + s} title=${STATUS[s] || s}><i></i>${label ? STATUS[s] || s : ''}</span>`
}

export function UserLink ({ id, user }) {
  if (!user) return html`<span class="muted">${id ? '#' + id : '—'}</span>`
  if (id == null) return html`<a class="user" href=${'#/events?user=' + encodeURIComponent(user)}>${user}</a>`
  return html`<a class="user" href=${'#/accounts/' + id}>${user}</a>`
}

/** A name from the event log (the account may be gone): to its events. */
export function NameLink ({ name }) {
  if (!name) return null
  return html`<a class="user" href=${'#/events?user=' + encodeURIComponent(name)}>${name}</a>`
}

export function GameLink ({ id, children }) {
  return html`<a class="mono" href=${'#/games/' + id}>${children || id.slice(0, 8)}</a>`
}

export function Pager ({ page, size, total, more, onPage }) {
  const last = total != null ? Math.max(0, Math.ceil(total / size) - 1) : null
  const from = total === 0 ? 0 : page * size + 1
  const to = total != null ? Math.min(total, (page + 1) * size) : null
  return html`<div class="pager">
    <span class="muted">${total != null ? html`${num(from)}–${num(to)} of ${num(total)}` : html`Page ${page + 1}`}</span>
    <button class="btn ghost sm" disabled=${page <= 0} onClick=${() => onPage(0)} title="First">«</button>
    <button class="btn ghost sm" disabled=${page <= 0} onClick=${() => onPage(page - 1)}>‹ Prev</button>
    <button class="btn ghost sm" disabled=${last != null ? page >= last : !more} onClick=${() => onPage(page + 1)}>Next ›</button>
    ${last != null && html`<button class="btn ghost sm" disabled=${page >= last} onClick=${() => onPage(last)} title="Last">»</button>`}
  </div>`
}

/** A sortable column header. */
export function SortTh ({ col, sort, dir, onSort, children, cls }) {
  const on = sort === col
  return html`<th class=${'sortable ' + (cls || '') + (on ? ' on' : '')} onClick=${() => onSort(col, on && dir === 'desc' ? 'asc' : 'desc')}>
    ${children}<span class="arrow">${on ? (dir === 'asc' ? '▲' : '▼') : '↕'}</span></th>`
}

export function Modal ({ title, onClose, children, wide }) {
  useEffect(() => {
    const k = (e) => { if (e.key === 'Escape') onClose() }
    addEventListener('keydown', k)
    return () => removeEventListener('keydown', k)
  }, [onClose])
  return html`<div class="modal-back" onMouseDown=${(e) => { if (e.target === e.currentTarget) onClose() }}>
    <div class=${'modal' + (wide ? ' wide' : '')} role="dialog" aria-modal="true" aria-label=${title}>
      <div class="modal-head"><h3>${title}</h3><button class="btn ghost icon-only" onClick=${onClose} aria-label="Close"><${Icon} name="x" /></button></div>
      ${children}
    </div>
  </div>`
}

export function Empty ({ children }) {
  return html`<div class="empty">${children}</div>`
}

export function ErrorBox ({ error, onRetry }) {
  if (!error) return null
  return html`<div class="error-box">${error.message || String(error)}${onRetry && html` <button class="btn ghost sm" onClick=${onRetry}>Retry</button>`}</div>`
}

export function Card ({ title, actions, children, cls, pad = true }) {
  return html`<section class=${'card ' + (cls || '')}>
    ${(title || actions) && html`<header class="card-head"><h2>${title}</h2><div class="card-actions">${actions}</div></header>`}
    <div class=${pad ? 'card-body' : 'card-body flush'}>${children}</div>
  </section>`
}

// --- toasts -----------------------------------------------------------------------------------

let pushToast = () => {}
export const toast = (text, kind = 'ok') => pushToast({ text, kind, id: Math.random() })

export function Toasts () {
  const [list, set] = useState([])
  useEffect(() => {
    pushToast = (t) => {
      set((l) => [...l, t])
      setTimeout(() => set((l) => l.filter((x) => x !== t)), 4000)
    }
  }, [])
  return html`<div class="toasts">${list.map((t) => html`<div key=${t.id} class=${'toast ' + t.kind}>${t.text}</div>`)}</div>`
}

/** Pretty JSON for event details. */
export function Json ({ value }) {
  return html`<pre class="json">${JSON.stringify(value, null, 2)}</pre>`
}
