// Sub-servers: the super admin's list (state, owner, players, storage; suspend, available, limits, enter, delete),
// the default limits, the quota per account and the admin invites; a sub-server's own limits for its admin; the
// page that takes an admin invite (outside the login).

import { useState, useContext } from 'preact/hooks'
import { api } from './api.js'
import { html, useLoad, useEvents, toast, Card, ErrorBox, Empty, Modal, MeContext, bytes, ago, fullDate, CopyCode } from './ui.js'
import { Confirm } from './accounts.js'

const NAMES = { storage_mb: 'Storage, MB', packs: 'Packs', players: 'Players', bots: 'Bots', tournaments: 'Tournaments' }
const STATES = { active: 'Active', suspended: 'Suspended', unavailable: 'Unavailable' }

/** A form of limits: `values` the current ones, `max` (optional) the most allowed; null = back to the default. */
function LimitsForm ({ keys, values, max, onSave, busy }) {
  const [v, setV] = useState({})
  const shown = (k) => v[k] ?? values[k] ?? ''
  const save = (e) => {
    e.preventDefault()
    const out = {}
    for (const k of keys) if (k in v) out[k] = v[k] === '' ? null : Math.max(0, Math.round(+v[k]))
    onSave(out).then(() => setV({}))
  }
  return html`<form class="form" onSubmit=${save}>
    ${keys.map((k) => html`<label key=${k}>${NAMES[k] || k}
      <input type="number" min="0" max=${max ? max[k] : undefined} value=${shown(k)} onInput=${(e) => setV({ ...v, [k]: e.target.value })} />
      ${max && html`<small>At most ${max[k]} (set by the host)</small>`}</label>`)}
    <div class="form-actions"><button class="btn primary" disabled=${busy || !Object.keys(v).length}>Save</button></div>
  </form>`
}

function LimitsModal ({ s, keys, onClose, onDone }) {
  const save = async (limits) => {
    try { await api(`subservers/${s.id}/limits`, { method: 'POST', body: { limits } }); toast('Saved'); onDone() } catch (err) { toast(err.message, 'err') }
  }
  return html`<${Modal} title=${'Limits of ' + s.name} onClose=${onClose}>
    <p class="muted small">Empty: the default. Its admin may lower them for his server${Object.keys(s.own).length ? ' (now: ' + Object.entries(s.own).map(([k, n]) => (NAMES[k] || k) + ' ' + n).join(', ') + ')' : ''}.</p>
    <${LimitsForm} keys=${keys} values=${s.max} onSave=${save} />
  </${Modal}>`
}

function DeleteServer ({ s, onClose, onYes }) {
  const [typed, setTyped] = useState('')
  return html`<${Modal} title=${'Delete the server ' + s.name + '?'} onClose=${onClose}>
    <form class="form" onSubmit=${(e) => { e.preventDefault(); if (typed === s.name) onYes() }}>
      <p>Its players' standings, games, replays, tournaments, packs, bots, settings and roles there go. The accounts stay (they are common to every server). This cannot be undone.</p>
      <label><span>Type <b>${s.name}</b> to confirm</span><input value=${typed} onInput=${(e) => setTyped(e.target.value)} autofocus autocomplete="off" /></label>
      <div class="form-actions"><button type="button" class="btn ghost" onClick=${onClose}>Cancel</button><button class="btn danger" disabled=${typed !== s.name}>Delete for good</button></div>
    </form>
  </${Modal}>`
}

export function Subservers () {
  const [data, error, reload] = useLoad(() => api('subservers'), [])
  const [limits, setLimits] = useState(null)
  const [del, setDel] = useState(null)
  const [ask, setAsk] = useState(null) // [server, action]
  useEvents((e) => { if (e.resync || e.kind === 'admin') reload() })
  const act = async (s, action, body) => {
    try { await api(`subservers/${s.id}/${action}`, { method: 'POST', body }); toast('Done'); reload() } catch (err) { toast(err.message, 'err') }
  }
  const saveDefaults = async (limits) => {
    try { await api('subservers/defaults', { method: 'POST', body: { limits } }); toast('Saved'); reload() } catch (err) { toast(err.message, 'err') }
  }
  return html`<div class="page">
    <header class="page-head"><h1>Servers</h1><span class="muted">Every game server this host runs</span></header>
    <${ErrorBox} error=${error} onRetry=${reload} />
    ${data && html`<${Card} title=${'Servers (' + data.list.length + ')'} pad=${false}><div class="table-wrap"><table class="table">
      <thead><tr><th>Server</th><th>State</th><th>Owner</th><th class="num">Players</th><th class="num">Online</th><th class="num">Packs</th><th class="num">Storage</th><th>Made</th><th></th></tr></thead>
      <tbody>${data.list.map((s) => html`<tr key=${s.id} class=${s.state === 'active' ? '' : 'off'}>
        <td><b>${s.title}</b> <span class="muted">/s/${s.name}</span></td>
        <td>${STATES[s.state] || s.state}</td>
        <td>${s.owner ? html`${s.owner.user} <span class="muted small">(quota ${s.owner.quota})</span>` : html`<span class="muted">—</span>`}</td>
        <td class="num">${s.players} ${s.id ? html`<span class="muted">/ ${s.limits.players}</span>` : ''}</td>
        <td class="num">${s.online}</td>
        <td class="num">${s.packs} ${s.id ? html`<span class="muted">/ ${s.limits.packs}</span>` : ''}</td>
        <td class="num nowrap">${bytes(s.storage)} ${s.id ? html`<span class="muted">/ ${s.limits.storage_mb} MB</span>` : ''}</td>
        <td class="muted nowrap" title=${fullDate(s.created * 1000)}>${ago(s.created * 1000)}</td>
        <td class="right-cell nowrap">
          <a class="btn ghost sm" href=${s.id === 0 ? '/admin' : '/s/' + s.name + '/admin'}>Enter</a>
          ${s.id !== 0 && html`
            <button class="btn ghost sm" onClick=${() => setLimits(s)}>Limits</button>
            ${s.state === 'active'
              ? html`<button class="btn ghost sm" onClick=${() => setAsk([s, 'unavailable'])}>Make unavailable</button>
                <button class="btn ghost sm danger-hover" onClick=${() => setAsk([s, 'suspend'])}>Suspend</button>`
              : html`<button class="btn ghost sm" onClick=${() => act(s, s.state === 'suspended' ? 'resume' : 'available')}>${s.state === 'suspended' ? 'Resume' : 'Make available'}</button>`}
            <button class="btn ghost sm danger-hover" onClick=${() => setDel(s)}>Delete</button>`}
        </td></tr>`)}</tbody></table></div></${Card}>
      <div class="grid two">
        <${Card} title="Default limits"><p class="muted small">For every server without its own value.</p>
          <${LimitsForm} keys=${data.keys} values=${data.defaults} onSave=${saveDefaults} /></${Card}>
        <${Card} title="Server quota"><${Quota} onDone=${reload} /></${Card}>
      </div>
      <${AdminInvites} />`}
    ${limits && html`<${LimitsModal} s=${limits} keys=${data.keys} onClose=${() => setLimits(null)} onDone=${() => { setLimits(null); reload() }} />`}
    ${del && html`<${DeleteServer} s=${del} onClose=${() => setDel(null)} onYes=${() => { act(del, 'delete', { confirm: del.name }); setDel(null) }} />`}
    ${ask && html`<${Confirm} title=${(ask[1] === 'suspend' ? 'Suspend ' : 'Make unavailable ') + ask[0].name + '?'}
      text=${ask[1] === 'suspend' ? 'Its players are logged out and can\'t log in or play until you resume it.' : 'Its players are logged out and see that the server is not available now.'}
      button=${ask[1] === 'suspend' ? 'Suspend' : 'Make unavailable'} kind="danger" onClose=${() => setAsk(null)} onYes=${() => { act(ask[0], ask[1]); setAsk(null) }} />`}
  </div>`
}

function Quota ({ onDone }) {
  const [user, setUser] = useState('')
  const [quota, setQuota] = useState(1)
  const save = async (e) => {
    e.preventDefault()
    try { await api('subservers/quota', { method: 'POST', body: { user, quota: +quota } }); toast('Saved'); onDone() } catch (err) { toast(err.message, 'err') }
  }
  return html`<form class="form" onSubmit=${save}>
    <p class="muted small">How many servers an account may own. An admin invite gives the first one; within the quota the admin makes more himself.</p>
    <label>Account<input required maxlength="20" value=${user} onInput=${(e) => setUser(e.target.value)} /></label>
    <label>Servers<input type="number" min="0" max="1000" required value=${quota} onInput=${(e) => setQuota(e.target.value)} /></label>
    <div class="form-actions"><button class="btn primary">Set</button></div>
  </form>`
}

function AdminInvites () {
  const [data, error, reload] = useLoad(() => api('admin_invites'), [])
  const [note, setNote] = useState('')
  const make = async (e) => {
    e.preventDefault()
    try { await api('admin_invites', { method: 'POST', body: { note } }); setNote(''); reload() } catch (err) { toast(err.message, 'err') }
  }
  const revoke = async (k) => {
    try { await api(`admin_invites/${k.id}/revoke`, { method: 'POST' }); reload() } catch (err) { toast(err.message, 'err') }
  }
  const link = (k) => location.origin + '/admin#/claim?key=' + encodeURIComponent(k.key)
  return html`<${Card} title="Admin invites" pad=${false}>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <form class="form inline" style="padding: 12px 16px" onSubmit=${make}>
      <input placeholder="Note (who it is for)" maxlength="200" value=${note} onInput=${(e) => setNote(e.target.value)} />
      <button class="btn primary">New admin invite</button>
    </form>
    ${data && !data.list.length ? html`<${Empty}>No admin invites yet. Whoever takes one gets a server of his own.</${Empty}>`
      : data && html`<div class="table-wrap"><table class="table">
      <thead><tr><th>Link</th><th>Note</th><th>Made</th><th>Taken by</th><th></th></tr></thead>
      <tbody>${data.list.map((k) => html`<tr key=${k.id} class=${k.revoked || k.used_by ? 'off' : ''}>
        <td>${k.used_by || k.revoked ? html`<span class="muted">${k.key.slice(0, 8)}…</span>` : html`<${CopyCode} code=${link(k)} label="Copy link" />`}</td>
        <td>${k.note || html`<span class="muted">—</span>`}</td>
        <td class="muted nowrap" title=${fullDate(k.created * 1000)}>${ago(k.created * 1000)} · ${k.created_by_name}</td>
        <td>${k.used_by ? html`${k.used_by} → /s/${k.subserver || '?'}` : k.revoked ? html`<span class="muted">revoked</span>` : html`<span class="muted">not yet</span>`}</td>
        <td class="right-cell">${!k.used_by && !k.revoked && html`<button class="btn ghost sm danger-hover" onClick=${() => revoke(k)}>Revoke</button>`}</td>
      </tr>`)}</tbody></table></div>`}
  </${Card}>`
}

/** The limits of this server, for its admin: he may lower them, never above the host's. */
export function Limits () {
  const me = useContext(MeContext)
  const sub = (me.subserver && me.subserver.id) || 0 // the foundation's `me.subserver`
  const [data, error, reload] = useLoad(() => api(`subservers/${sub}/limits`), [sub])
  const save = async (limits) => {
    try { await api(`subservers/${sub}/limits`, { method: 'POST', body: { limits } }); toast('Saved'); reload() } catch (err) { toast(err.message, 'err') }
  }
  return html`<div class="page">
    <header class="page-head"><h1>Limits</h1><span class="muted">What this server may hold</span></header>
    <${ErrorBox} error=${error} onRetry=${reload} />
    ${data && html`<div class="grid two">
      <${Card} title="In use"><table class="table"><tbody>${data.keys.map((k) => html`<tr key=${k}><td>${NAMES[k] || k}</td>
        <td class="num">${data.used[k] ?? '—'} <span class="muted">/ ${data.limits[k]}</span></td></tr>`)}</tbody></table></${Card}>
      <${Card} title="Lower the limits"><${LimitsForm} keys=${data.keys} values=${data.own} max=${data.max} onSave=${save} /></${Card}>
    </div>`}
  </div>`
}

/** Taking an admin invite (#/claim?key=…): a new account or an existing one gets a server of its own. */
export function Claim () {
  const key = new URLSearchParams(location.hash.split('?')[1] || '').get('key') || ''
  const [f, setF] = useState({ user: '', password: '', register: true, name: '', title: '' })
  const [error, setError] = useState('')
  const [done, setDone] = useState(null)
  const [busy, setBusy] = useState(false)
  const field = (k) => (e) => setF({ ...f, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value })
  const submit = async (e) => {
    e.preventDefault()
    setBusy(true)
    setError('')
    try { setDone(await api('claim', { method: 'POST', body: { ...f, key } })) } catch (err) { setError(err.message) }
    setBusy(false)
  }
  if (done) {
    return html`<div class="login-wrap"><div class="login card">
      <h2>Your server is ready</h2>
      <p>The game connects to <code>${location.origin + '/s/' + done.name}</code>.</p>
      <a class="btn primary wide" href=${done.url}>Open its admin panel</a>
    </div></div>`
  }
  return html`<div class="login-wrap">
    <form class="login card" onSubmit=${submit}>
      <div class="brand big"><span class="logo">◆</span><span><b>Classic HS</b><small>your own server</small></span></div>
      ${!key && html`<div class="error-box">This link has no invite key.</div>`}
      <div class="seg" role="radiogroup" aria-label="Account">
        <button type="button" role="radio" aria-checked=${f.register} class=${f.register ? 'on' : ''} onClick=${() => setF({ ...f, register: true })}>New account</button>
        <button type="button" role="radio" aria-checked=${!f.register} class=${f.register ? '' : 'on'} onClick=${() => setF({ ...f, register: false })}>I have one</button>
      </div>
      <label>Name<input autocomplete="username" required maxlength=${f.register ? 16 : 20} value=${f.user} onInput=${field('user')} autofocus /></label>
      <label>Password<input type="password" autocomplete=${f.register ? 'new-password' : 'current-password'} required minlength=${f.register ? 8 : 1} maxlength="128" value=${f.password} onInput=${field('password')} /></label>
      <label>Server address<input required pattern="[a-z0-9][a-z0-9\\-]{1,30}[a-z0-9]" maxlength="32" value=${f.name} onInput=${field('name')} />
        <small>${location.origin}/s/<b>${f.name || 'name'}</b>: 3–32 small Latin letters, digits or -</small></label>
      <label>Server title<input maxlength="60" value=${f.title} onInput=${field('title')} /></label>
      ${error && html`<div class="error-box">${error}</div>`}
      <button class="btn primary wide" disabled=${busy || !key}>${busy ? 'Making…' : 'Make my server'}</button>
    </form>
  </div>`
}
