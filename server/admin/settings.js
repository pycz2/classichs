// Settings (the auto-bots' wait, invite-only registration) and the invite keys: make one (a note,
// how many players), copy it, revoke it, see who joined with it.

import { useState, useEffect } from 'preact/hooks'
import { api } from './api.js'
import { html, useLoad, useEvents, useTick, toast, Card, ErrorBox, Empty, Icon, UserLink, ago, fullDate } from './ui.js'
import { Confirm } from './accounts.js'
import { Switch } from './bots.js'

const MAX_WAIT = 600

const waitText = (s) => s === 0 ? 'at once' : s < 60 ? s + ' s' : Math.floor(s / 60) + ' min' + (s % 60 ? ' ' + (s % 60) + ' s' : '')

export function Settings () {
  const [data, error, reload] = useLoad(() => api('settings'), [])
  const [wait, setWait] = useState(null) // seconds being edited (null = as saved)
  const [busy, setBusy] = useState(false)
  useEvents((e) => { if (e.resync || e.kind === 'setting') reload() })
  const save = async (body) => {
    setBusy(true)
    try { await api('settings', { method: 'POST', body }); toast('Saved'); setWait(null); reload() } catch (err) { toast(err.message, 'err') }
    setBusy(false)
  }
  const saved = data ? Math.round(data.autobot_wait_ms / 1000) : 0
  const w = wait ?? saved
  const clamp = (v) => Math.max(0, Math.min(MAX_WAIT, Math.round(+v || 0)))
  return html`<div class="page">
    <header class="page-head"><h1>Settings</h1><span class="muted">For the whole server; a change takes effect at once</span></header>
    <${ErrorBox} error=${error} onRetry=${reload} />
    ${data && html`<div class="grid two">
      <${Card} title="Auto-bots">
        <form class="form" onSubmit=${(e) => { e.preventDefault(); save({ autobot_wait_ms: clamp(w) * 1000 }) }}>
          <label>Wait before an auto-bot comes
            <div class="range-row">
              <input type="range" min="0" max=${MAX_WAIT} step="5" value=${w} onInput=${(e) => setWait(clamp(e.target.value))} aria-label="Wait in seconds" />
              <span class="unit-input"><input type="number" min="0" max=${MAX_WAIT} value=${w} onInput=${(e) => setWait(clamp(e.target.value))} aria-label="Seconds" /><span>s</span></span>
            </div>
            <small>A player alone in a ranked, casual or Arena queue of Classic gets a bot of a fitting level after <b>${waitText(w)}</b>. 0 to 600 seconds (10 minutes); 0: at once.</small>
          </label>
          <div class="form-actions">
            ${wait != null && wait !== saved && html`<button type="button" class="btn ghost" onClick=${() => setWait(null)}>Undo</button>`}
            <button class="btn primary" disabled=${busy || wait == null || wait === saved}>Save</button>
          </div>
        </form>
      </${Card}>
      <${Card} title="Registration">
        <div class="setting-row">
          <div><b>Invite keys only</b>
            <div class="muted small">${data.signup_invite_only
              ? 'New players need a key to register. Accounts that exist log in as before.'
              : 'Anyone who reaches the server can register. A key given anyway is still recorded.'}</div></div>
          <${Switch} on=${data.signup_invite_only} busy=${busy} label="Invite keys only" onChange=${(on) => save({ signup_invite_only: on })} />
        </div>
        <p class="small" style="margin: 14px 0 0"><a href="#/invites">Invite keys →</a></p>
      </${Card}>
    </div>`}
  </div>`
}

/** A key in full, copied on click. */
function CopyKey ({ value }) {
  const copy = async () => {
    try { await navigator.clipboard.writeText(value); toast('Key copied') } catch (err) { toast('Copy failed: select the key by hand', 'err') }
  }
  return html`<span class="key-cell"><code class="key">${value}</code>
    <button class="btn ghost sm icon-only" title="Copy the key" aria-label="Copy the key" onClick=${copy}><${Icon} name="copy" size=${15} /></button></span>`
}

function KeyState ({ k }) {
  if (k.revoked) return html`<span class="badge bad">revoked</span>`
  if (k.uses_left <= 0) return html`<span class="badge">used up</span>`
  return html`<span class="badge ok">active</span>`
}

function NewKey ({ onMade }) {
  const [note, setNote] = useState('')
  const [uses, setUses] = useState(1)
  const [busy, setBusy] = useState(false)
  const submit = async (e) => {
    e.preventDefault()
    setBusy(true)
    try {
      const r = await api('signup_keys', { method: 'POST', body: { note, uses: +uses } })
      toast(r.text)
      setNote('')
      setUses(1)
      onMade(r.key)
    } catch (err) { toast(err.message, 'err') }
    setBusy(false)
  }
  return html`<form class="new-key" onSubmit=${submit}>
    <label class="grow"><span>Note <span class="muted">(optional: who it is for)</span></span>
      <input maxlength="200" placeholder="e.g. Anna from work" value=${note} onInput=${(e) => setNote(e.target.value)} /></label>
    <label>Players<input type="number" min="1" max="1000" required value=${uses} onInput=${(e) => setUses(e.target.value)} /></label>
    <button class="btn primary" disabled=${busy}><${Icon} name="plus" size=${16} />Make a key</button>
  </form>`
}

export function InviteKeys () {
  const [data, error, reload] = useLoad(() => api('signup_keys'), [])
  const [fresh, setFresh] = useState('')
  const [revoke, setRevoke] = useState(null)
  useEvents((e) => { if (e.resync || ['signup_key', 'register', 'setting'].includes(e.kind)) reload() })
  useTick(30000)
  useEffect(() => { if (!fresh) return; const t = setTimeout(() => setFresh(''), 8000); return () => clearTimeout(t) }, [fresh])
  const doRevoke = async (k) => {
    setRevoke(null)
    try { const r = await api(`signup_keys/${k.id}/revoke`, { method: 'POST' }); toast(r.text); reload() } catch (err) { toast(err.message, 'err') }
  }
  const keys = data ? data.keys : []
  const active = keys.filter((k) => !k.revoked && k.uses_left > 0).length
  return html`<div class="page">
    <header class="page-head"><h1>Invite keys</h1>
      ${data && html`<span class="muted">${data.invite_only
        ? html`Registration needs a key (<a href="#/settings">Settings</a>)`
        : html`Registration is open to anyone: keys are optional (<a href="#/settings">Settings</a>)`}</span>`}
    </header>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <${Card} title="New key"><${NewKey} onMade=${(k) => { setFresh(k); reload() }} /></${Card}>
    <${Card} title=${data ? `Keys (${active} active of ${keys.length})` : 'Keys'} pad=${false}>
      ${data && !keys.length ? html`<${Empty}>No keys yet. Make one above and send it to a player: they paste it when they register.</${Empty}>`
        : data && html`<div class="table-wrap"><table class="table keys">
        <thead><tr><th>Key</th><th>Note</th><th class="num">Uses left</th><th>Made by</th><th>Made</th><th>State</th><th>Joined with it</th><th></th></tr></thead>
        <tbody>${keys.map((k) => html`<tr key=${k.id} class=${(k.revoked || k.uses_left <= 0 ? 'off' : '') + (k.key === fresh ? ' fresh' : '')}>
          <td><${CopyKey} value=${k.key} /></td>
          <td>${k.note || html`<span class="muted">—</span>`}</td>
          <td class="num nowrap">${k.uses_left} <span class="muted">/ ${k.uses_total}</span></td>
          <td class="nowrap"><${UserLink} id=${k.created_by} user=${k.created_by_name} /></td>
          <td class="muted nowrap" title=${fullDate(k.created * 1000)}>${ago(k.created * 1000)}</td>
          <td><${KeyState} k=${k} /></td>
          <td>${k.accounts.length ? html`<span class="joined">${k.accounts.map((a) => html`<${UserLink} key=${a.id} id=${a.id} user=${a.user} />`)}</span>` : html`<span class="muted">nobody yet</span>`}</td>
          <td class="right-cell">${!k.revoked && html`<button class="btn ghost sm danger-hover" onClick=${() => setRevoke(k)}>Revoke</button>`}</td>
        </tr>`)}</tbody></table></div>`}
    </${Card}>
    ${revoke && html`<${Confirm} title="Revoke this key?" text=${`Nobody can register with it any more${revoke.note ? ' (' + revoke.note + ')' : ''}. The accounts made with it stay.`}
      button="Revoke" kind="danger" onClose=${() => setRevoke(null)} onYes=${() => doRevoke(revoke)} />`}
  </div>`
}
