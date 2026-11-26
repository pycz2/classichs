// The audit log: this server's changes of roles, permissions, bans, settings and limits, newest first
// (GET /admin/api/audit, admin_roles.rs): who, what, on what, before → after.

import { useState, useEffect } from 'preact/hooks'
import { api, qs } from './api.js'
import { html, useLoad, useDebounced, setQuery, Card, UserLink, Pager, ErrorBox, Empty, clock, fullDate } from './ui.js'

const SIZE = 50

/** A before/after value in one line (null: nothing). */
const show = (v) => (v == null ? html`<span class="muted">—</span>` : html`<code class="audit-val" title=${JSON.stringify(v, null, 2)}>${typeof v === 'string' ? v : JSON.stringify(v)}</code>`)

export function Audit ({ query }) {
  const [f, setF] = useState(() => ({ action: '', account: '', ...query, page: Number(query.page || 0) }))
  const [draft, setDraft] = useState({ action: f.action, account: f.account })
  const set = (p) => setF((x) => ({ ...x, page: 0, ...p }))
  const commit = useDebounced((d) => set(d), 350)
  useEffect(() => { setQuery({ ...f, page: f.page || '' }) }, [f])
  const [data, error, reload, loading] = useLoad(() => api('audit?' + qs({ ...f, size: SIZE })), [f])
  const field = (k, label) => html`<input placeholder=${label} value=${draft[k]} size="14" onInput=${(e) => { const d = { ...draft, [k]: e.target.value }; setDraft(d); commit(d) }} />`
  return html`<div class="page">
    <header class="page-head"><h1>Audit log</h1><span class="muted">Every change of roles, bans, settings and limits on this server</span></header>
    <div class="filters">
      ${field('action', 'Action (e.g. role)')}${field('account', 'Who (account name)')}
      ${(f.action || f.account) && html`<button class="btn ghost sm" onClick=${() => { setDraft({ action: '', account: '' }); set({ action: '', account: '' }) }}>Clear filters</button>`}
    </div>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <${Card} pad=${false} cls=${loading ? 'loading' : ''}>
      <div class="table-wrap"><table class="table">
        <thead><tr><th>Time</th><th>Who</th><th>Action</th><th>Target</th><th>Before → after</th></tr></thead>
        <tbody>${data && data.list.map((r) => html`<tr key=${r.id}>
          <td class="mono nowrap" title=${fullDate(r.at)}>${clock(r.at)}</td>
          <td><${UserLink} id=${r.account} user=${r.user} /></td>
          <td class="mono">${r.action}</td>
          <td>${r.target}</td>
          <td>${show(r.before)} → ${show(r.after)}</td>
        </tr>`)}</tbody>
      </table></div>
      ${data && !data.list.length && html`<${Empty}>Nothing changed yet</${Empty}>`}
      ${data && html`<div class="table-foot"><span></span><${Pager} page=${f.page} size=${SIZE} total=${data.total} onPage=${(page) => setF((x) => ({ ...x, page }))} /></div>`}
    </${Card}>
  </div>`
}
