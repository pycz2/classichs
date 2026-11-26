// Roles: named sets of permissions given to accounts (admin_roles.rs). This server's roles and the global
// ones with their members; making and changing this server's own roles; giving and taking them (here and on
// an account's page). One gives only what one has; the built-in roles are read-only.

import { useState } from 'preact/hooks'
import { api, qs } from './api.js'
import { html, useCan, useLoad, toast, Card, Modal, ErrorBox, Empty, Icon, UserLink } from './ui.js'
import { Confirm } from './accounts.js'

/** The permissions a role's list stands for (`*` and `chats.*` expanded), as the server counts them. */
export function expand (perms, all) {
  return all.filter((p) => perms.some((g) => g === '*' || g === p || (g.endsWith('.*') && p.startsWith(g.slice(0, -1)))))
}

/** May I give (or take) this role: every permission of it mine, a global one only with superadmins.manage. */
const givable = (r, d) => expand(r.perms, d.all_perms).every((p) => d.mine.includes(p)) && (r.subserver != null || d.mine.includes('superadmins.manage'))

/** An account by its exact name (the accounts search): its id. */
async function accountId (name) {
  const r = await api('accounts?' + qs({ q: name.trim(), size: 20 }))
  const a = r.list.find((x) => x.user.toLowerCase() === name.trim().toLowerCase())
  if (!a) throw new Error('No account ' + name)
  return a.id
}

async function give (role, account, on) {
  const r = await api(`roles/${role.id}/${on ? 'assign' : 'unassign'}`, { method: 'POST', body: { account } })
  toast(on ? `Gave ${role.name}` : `Took ${role.name}`)
  return r
}

function PermList ({ r, all }) {
  if (r.perms.includes('*')) return html`<span class="muted">every permission</span>`
  const list = expand(r.perms, all)
  return html`<span class="perm-list" title=${list.join('\n')}>${list.filter((p) => p !== 'panel.open').join(', ') || html`<span class="muted">none</span>`}</span>`
}

export function Roles () {
  const can = useCan()
  const [data, error, reload, loading] = useLoad(() => api('roles'), [])
  const [modal, setModal] = useState(null) // 'new' | {edit} | {del} | {give}
  const run = async (fn) => { try { await fn(); setModal(null); reload() } catch (err) { toast(err.message, 'err') } }
  return html`<div class="page">
    <header class="page-head"><h1>Roles</h1><span class="muted">What each admin may do in this server's panel: the sum of his roles</span>
      ${can('roles.edit') && html`<div class="head-actions"><button class="btn primary" onClick=${() => setModal('new')}><${Icon} name="plus" size=${16} />New role</button></div>`}
    </header>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <${Card} pad=${false} cls=${loading ? 'loading' : ''}>
      ${data && html`<div class="table-wrap"><table class="table roles">
        <thead><tr><th>Role</th><th>Permissions</th><th>Members</th><th></th></tr></thead>
        <tbody>${data.list.map((r) => {
          const mayGive = can('roles.assign') && givable(r, data)
          return html`<tr key=${r.id}>
            <td class="nowrap"><b>${r.name}</b> ${r.subserver == null ? html`<span class="badge role-super">global</span>` : r.builtin && html`<span class="badge">built-in</span>`}</td>
            <td class="small"><${PermList} r=${r} all=${data.all_perms} /></td>
            <td><div class="chips">${r.members.map((m) => html`<span key=${m.id} class="chip"><${UserLink} ...${m} />
              ${mayGive && html`<button class="btn ghost sm icon-only" title=${'Take ' + r.name + ' from ' + m.user} aria-label=${'Take ' + r.name + ' from ' + m.user}
                onClick=${() => run(() => give(r, m.id, false))}><${Icon} name="x" size=${12} /></button>`}</span>`)}
              ${mayGive && html`<button class="btn ghost sm" onClick=${() => setModal({ give: r })}><${Icon} name="plus" size=${14} />Give</button>`}</div></td>
            <td class="right-cell nowrap">${can('roles.edit') && !r.builtin && r.subserver != null && html`
              <button class="btn ghost sm" onClick=${() => setModal({ edit: r })}>Edit</button>
              <button class="btn ghost sm icon-only danger-hover" title="Delete" aria-label=${'Delete ' + r.name} onClick=${() => setModal({ del: r })}><${Icon} name="trash" size=${15} /></button>`}</td>
          </tr>`
        })}</tbody>
      </table></div>`}
      ${data && !data.list.length && html`<${Empty}>No roles</${Empty}>`}
    </${Card}>
    ${data && (modal === 'new' || modal?.edit) && html`<${RoleModal} role=${modal.edit} data=${data} onClose=${() => setModal(null)} onSave=${(body) => run(() =>
      api(modal.edit ? 'roles/' + modal.edit.id : 'roles', { method: 'POST', body }))} />`}
    ${modal?.del && html`<${Confirm} title=${'Delete the role ' + modal.del.name + '?'} text="Its members lose it (and what it allowed) at once."
      button="Delete" kind="danger" onClose=${() => setModal(null)} onYes=${() => run(() => api(`roles/${modal.del.id}/delete`, { method: 'POST' }))} />`}
    ${modal?.give && html`<${GiveModal} role=${modal.give} onClose=${() => setModal(null)} onGive=${(name) => run(async () => give(modal.give, await accountId(name), true))} />`}
  </div>`
}

function GiveModal ({ role, onClose, onGive }) {
  const [name, setName] = useState('')
  return html`<${Modal} title=${'Give ' + role.name} onClose=${onClose}>
    <form class="form" onSubmit=${(e) => { e.preventDefault(); onGive(name) }}>
      <label>Account name<input required value=${name} onInput=${(e) => setName(e.target.value)} autofocus autocomplete="off" /></label>
      <div class="form-actions"><button type="button" class="btn ghost" onClick=${onClose}>Cancel</button><button class="btn primary">Give</button></div>
    </form>
  </${Modal}>`
}

/** A new role or a change: the name and the permissions, by area; only those I have can be ticked (the super
 * level ones are not shown: only the global Super admin role has them). */
function RoleModal ({ role, data, onClose, onSave }) {
  const [name, setName] = useState(role ? role.name : '')
  const [on, setOn] = useState(() => new Set(role ? expand(role.perms, data.all_perms) : ['panel.open']))
  const areas = {}
  for (const p of data.all_perms) if (!data.super.includes(p)) (areas[p.split('.')[0]] ||= []).push(p)
  const flip = (p) => setOn((s) => { const n = new Set(s); n.has(p) ? n.delete(p) : n.add(p); return n })
  return html`<${Modal} title=${role ? 'Change ' + role.name : 'New role'} onClose=${onClose} wide>
    <form class="form" onSubmit=${(e) => { e.preventDefault(); onSave({ name, perms: [...on] }) }}>
      <label>Name<input required maxlength="40" value=${name} onInput=${(e) => setName(e.target.value)} autofocus /></label>
      <div class="perm-groups">${Object.entries(areas).map(([area, ps]) => html`<fieldset key=${area}><legend>${area}</legend>
        ${ps.map((p) => html`<label class="check" key=${p} title=${data.mine.includes(p) ? p : 'You lack it, so you can\'t give it'}>
          <input type="checkbox" checked=${on.has(p)} disabled=${!data.mine.includes(p)} onChange=${() => flip(p)} />${p.slice(area.length + 1)}</label>`)}
      </fieldset>`)}</div>
      <small class="muted">panel.open lets the role's members log into this panel.</small>
      <div class="form-actions"><button type="button" class="btn ghost" onClick=${onClose}>Cancel</button><button class="btn primary">${role ? 'Save' : 'Make'}</button></div>
    </form>
  </${Modal}>`
}

/** An account page's roles here, with giving and taking. */
export function AccountRoles ({ account }) {
  const can = useCan()
  const [mine, error, reload] = useLoad(() => api(`accounts/${account.id}/roles`), [account.id])
  const [data] = useLoad(() => (can('roles.view') ? api('roles') : Promise.resolve(null)), [])
  const [pick, setPick] = useState('')
  const run = async (fn) => { try { await fn(); setPick(''); reload() } catch (err) { toast(err.message, 'err') } }
  const may = (r) => data && can('roles.assign') && givable(r, data)
  const has = new Set(mine ? mine.list.map((r) => r.id) : [])
  const free = data ? data.list.filter((r) => !has.has(r.id) && may(r)) : []
  return html`<${Card} title="Roles here" actions=${can('roles.view') && html`<a class="btn ghost sm" href="#/roles">All roles</a>`}>
    <${ErrorBox} error=${error} onRetry=${reload} />
    ${mine && html`<div class="chips">
      ${mine.list.map((r) => html`<span key=${r.id} class="chip">${r.name}${r.subserver == null && html` <span class="badge role-super">global</span>`}
        ${may(r) && html`<button class="btn ghost sm icon-only" title=${'Take ' + r.name} aria-label=${'Take ' + r.name} onClick=${() => run(() => give(r, account.id, false))}><${Icon} name="x" size=${12} /></button>`}</span>`)}
      ${!mine.list.length && html`<span class="muted">None: a player</span>`}
      ${free.length > 0 && html`<span class="inline-actions"><select value=${pick} onChange=${(e) => setPick(e.target.value)} aria-label="A role to give">
          <option value="">Give a role…</option>${free.map((r) => html`<option key=${r.id} value=${r.id}>${r.name}</option>`)}</select>
        <button class="btn sm" disabled=${!pick} onClick=${() => run(() => give(free.find((r) => r.id === Number(pick)), account.id, true))}>Give</button></span>`}
    </div>`}
  </${Card}>`
}
