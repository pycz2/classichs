// Accounts: the searchable list, one account's page and the actions on it.

import { useState, useEffect } from 'preact/hooks'
import { api, qs } from './api.js'
import { html, useLive, useMe, useEvents, useLoad, useDebounced, useTick, setQuery, go, toast, Card, Status, UserLink, Pager, SortTh, Modal, ErrorBox, Empty, Icon, rankText, ago, clock, fullDate, num } from './ui.js'
import { FeedRow } from './dashboard.js'

const FILTERS = [['', 'All'], ['online', 'Online'], ['in_game', 'In game'], ['searching', 'Searching'], ['offline', 'Offline'], ['suspended', 'Suspended']]
const ACCOUNT_KINDS = ['register', 'admin', 'tag']

/** The status from the live snapshot (fresher than the list's). */
function useStatusOf () {
  const { live } = useLive()
  const m = new Map(live.online.map((o) => [o.id, o.status]))
  return (id) => m.get(id) || 'offline'
}

function Role ({ role }) {
  return role === 'user' ? null : html`<span class=${'badge role-' + role}>${role === 'super' ? 'superuser' : 'admin'}</span>`
}

export function Rank ({ a }) {
  const stars = a.rank === 0 ? 0 : Math.min(5, a.rank > 20 ? 2 : a.rank > 15 ? 3 : a.rank > 10 ? 4 : 5)
  return html`<span class=${'rank' + (a.rank === 0 ? ' legend' : '')}>${rankText(a)}
    ${stars > 0 && html`<span class="stars" title=${a.stars + ' of ' + stars + ' stars'}>${Array.from({ length: stars }, (_, i) => html`<i class=${i < a.stars ? 'on' : ''}></i>`)}</span>`}</span>`
}

export function Accounts ({ query }) {
  const me = useMe()
  const statusOf = useStatusOf()
  const [f, setF] = useState(() => ({ q: '', status: '', role: '', sort: 'id', dir: 'desc', ...query, page: Number(query.page || 0) }))
  const [draft, setDraft] = useState(f.q)
  const [creating, setCreating] = useState(false)
  const set = (p) => setF((x) => ({ ...x, page: 0, ...p }))
  const commit = useDebounced((q) => set({ q }), 300)
  useEffect(() => { setQuery({ ...f, page: f.page || '', sort: f.sort === 'id' ? '' : f.sort, dir: f.dir === 'desc' ? '' : f.dir }) }, [f])
  const [data, error, reload, loading] = useLoad(() => api('accounts?' + qs({ ...f, size: 50 })), [f])
  const later = useDebounced(reload, 800)
  useEvents((e) => {
    if (e.resync || ACCOUNT_KINDS.includes(e.kind) || (f.status && ['login', 'logout', 'disconnect', 'queue', 'unqueue', 'match', 'game_end'].includes(e.kind))) later()
  })
  useTick(15000)
  const sortProps = { sort: f.sort, dir: f.dir, onSort: (sort, dir) => set({ sort, dir }) }
  return html`<div class="page">
    <header class="page-head"><h1>Accounts</h1>
      <div class="head-actions"><button class="btn primary" onClick=${() => setCreating(true)}><${Icon} name="plus" size=${16} />Create account</button></div>
    </header>
    <div class="filters">
      <label class="search"><${Icon} name="search" size=${16} /><input placeholder="Name or tag" value=${draft} onInput=${(e) => { setDraft(e.target.value); commit(e.target.value) }} /></label>
      <div class="seg text">${FILTERS.map(([k, label]) => html`<button key=${k} class=${f.status === k ? 'on' : ''} onClick=${() => set({ status: k })}>${label}</button>`)}</div>
      <select value=${f.role} onChange=${(e) => set({ role: e.target.value })} aria-label="Role">
        <option value="">Any role</option><option value="user">Players</option><option value="admin">Admins</option><option value="super">Superuser</option>
      </select>
    </div>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <${Card} pad=${false} cls=${loading ? 'loading' : ''}>
      <div class="table-wrap"><table class="table">
        <thead><tr>
          <${SortTh} col="user" ...${sortProps}>User</${SortTh}>
          <th>Tag</th><th>Status</th>
          <${SortTh} col="rank" ...${sortProps}>Rank <span class="muted small">(default game)</span></${SortTh}>
          <${SortTh} col="ranked_mmr" ...${sortProps} cls="num">Ranked MMR</${SortTh}>
          <${SortTh} col="casual_mmr" ...${sortProps} cls="num">Casual MMR</${SortTh}>
          <${SortTh} col="created" ...${sortProps}>Created</${SortTh}>
          <${SortTh} col="last_seen" ...${sortProps}>Last seen</${SortTh}>
        </tr></thead>
        <tbody>${data && data.list.map((a) => html`<tr key=${a.id} class="clickable" onClick=${() => go('accounts/' + a.id)}>
          <td><a href=${'#/accounts/' + a.id} onClick=${(e) => e.stopPropagation()}><b>${a.user}</b></a> <${Role} role=${a.role} /></td>
          <td class="muted">${a.tag || ''}</td>
          <td>${a.suspended ? html`<span class="badge bad">suspended</span>` : html`<${Status} status=${statusOf(a.id)} />`}</td>
          <td><${Rank} a=${a} /></td>
          <td class="num">${num(a.ranked_mmr)}</td><td class="num">${num(a.casual_mmr)}</td>
          <td title=${fullDate(a.created * 1000)}>${clock(a.created * 1000, false)}</td>
          <td title=${fullDate(a.last_seen * 1000)}>${statusOf(a.id) !== 'offline' ? html`<span class="ok-text">now</span>` : ago(a.last_seen * 1000)}</td>
        </tr>`)}</tbody>
      </table></div>
      ${data && !data.list.length && html`<${Empty}>No accounts match</${Empty}>`}
      ${data && html`<div class="table-foot"><span></span><${Pager} page=${f.page} size=${50} total=${data.total} onPage=${(page) => setF((x) => ({ ...x, page }))} /></div>`}
    </${Card}>
    ${creating && html`<${CreateModal} super=${me.role === 'super'} onClose=${() => setCreating(false)} onDone=${(id) => { setCreating(false); go('accounts/' + id) }} />`}
  </div>`
}

function CreateModal ({ super: isSuper, onClose, onDone }) {
  const [v, setV] = useState({ user: '', password: '', role: 'user' })
  const [error, setError] = useState('')
  const submit = async (e) => {
    e.preventDefault()
    try {
      const r = await api('accounts', { method: 'POST', body: v })
      toast('Created ' + v.user)
      onDone(r.id)
    } catch (err) { setError(err.message) }
  }
  return html`<${Modal} title="Create account" onClose=${onClose}>
    <form class="form" onSubmit=${submit}>
      <label>Name<input required minlength="3" maxlength="20" pattern="[A-Za-z0-9_]+" value=${v.user} onInput=${(e) => setV({ ...v, user: e.target.value })} autofocus />
        <small>3–20 letters, digits or _</small></label>
      <label>Password<input type="password" required minlength="8" maxlength="128" autocomplete="new-password" value=${v.password} onInput=${(e) => setV({ ...v, password: e.target.value })} />
        <small>8–128 characters</small></label>
      ${isSuper && html`<label>Role<select value=${v.role} onChange=${(e) => setV({ ...v, role: e.target.value })}><option value="user">Player</option><option value="admin">Admin</option></select></label>`}
      ${error && html`<div class="error-box">${error}</div>`}
      <div class="form-actions"><button type="button" class="btn ghost" onClick=${onClose}>Cancel</button><button class="btn primary">Create</button></div>
    </form>
  </${Modal}>`
}

// --- one account ----------------------------------------------------------------------------

export function AccountPage ({ id }) {
  const statusOf = useStatusOf()
  const [data, error, reload] = useLoad(() => api('accounts/' + id), [id])
  const [modal, setModal] = useState(null)
  const [events, setEvents] = useState([])
  useEffect(() => { if (data) setEvents(data.events) }, [data])
  const later = useDebounced(reload, 600)
  useEvents((e) => {
    if (e.resync) return reload()
    if (!data) return
    const name = data.account.user.toLowerCase()
    if ((e.user || '').toLowerCase() !== name && (e.other || '').toLowerCase() !== name) return
    if (e.kind !== 'game_action') setEvents((l) => [e, ...l].slice(0, 40))
    if (['admin', 'tag', 'friend_accept', 'friend_request', 'friend_remove', 'friend_decline', 'block', 'unblock', 'msg', 'game_end', 'arena', 'login', 'logout'].includes(e.kind)) later()
  })
  useTick(10000)
  if (error && !data) return html`<div class="page"><a class="back" href="#/accounts"><${Icon} name="back" size=${16} />Accounts</a><${ErrorBox} error=${error} onRetry=${reload} /></div>`
  if (!data) return html`<div class="page"><div class="skel-title"></div></div>`
  const a = data.account
  const status = statusOf(a.id)
  const act = async (action, body = {}) => {
    try {
      const r = await api(`accounts/${a.id}/${action}`, { method: 'POST', body })
      toast(r.text)
      setModal(null)
      if (action === 'delete') go('accounts')
      else reload()
    } catch (err) { toast(err.message, 'err') }
  }
  return html`<div class="page">
    <a class="back" href="#/accounts"><${Icon} name="back" size=${16} />Accounts</a>
    <header class="page-head account-head">
      <div class="avatar">${a.user.slice(0, 1).toUpperCase()}</div>
      <div class="who">
        <h1>${a.user} <${Role} role=${a.role} />${a.suspended && html` <span class="badge bad">suspended</span>`}</h1>
        <div class="muted">${a.tag ? html`tag <b>${a.tag}</b> · ` : 'no tag · '}<${Status} status=${status} /> · #${a.id}</div>
      </div>
      ${data.may_manage && html`<div class="head-actions">
        ${a.suspended ? html`<button class="btn" onClick=${() => act('unsuspend')}>Unsuspend</button>` : html`<button class="btn warn" onClick=${() => setModal('suspend')}>Suspend</button>`}
        <button class="btn" onClick=${() => setModal('password')}>Reset password</button>
        ${data.can_role && html`<button class="btn" onClick=${() => act('role', { role: a.role === 'admin' ? 'user' : 'admin' })}>${a.role === 'admin' ? 'Make player' : 'Make admin'}</button>`}
        <button class="btn danger" onClick=${() => setModal('delete')}>Delete…</button>
      </div>`}
    </header>
    <div class="grid three">
      <${Card} title="Profile">
        <dl class="kv">
          <dt>Created</dt><dd title=${fullDate(a.created * 1000)}>${fullDate(a.created * 1000)}</dd>
          <dt>Last seen</dt><dd>${status !== 'offline' ? html`<span class="ok-text">online now</span>` : html`<span title=${fullDate(a.last_seen * 1000)}>${ago(a.last_seen * 1000)}</span>`}</dd>
          <dt>Rank</dt><dd><${Rank} a=${a} /> <span class="muted small">${a.pack} · season ${a.season}</span></dd>
          ${(data.ranks || []).filter((r) => !r.default).map((r) => html`<dt class="muted">${r.pack}</dt><dd><${Rank} a=${r} />
            <span class="muted small">MMR ${num(r.ranked_mmr)} / ${num(r.casual_mmr)}</span></dd>`)}
          <dt>Win streak</dt><dd>${a.streak}</dd>
          <dt>Ranked MMR</dt><dd>${num(a.ranked_mmr)}</dd>
          <dt>Casual MMR</dt><dd>${num(a.casual_mmr)}</dd>
          <dt>Arena</dt><dd>${data.arena ? html`${data.arena.wins}–${data.arena.losses} <span class="muted small">${data.arena.picks} picked${data.arena.pack ? ' · ' + data.arena.pack.slice(0, 10) + '…' : ''}</span>` : html`<span class="muted">no run</span>`}</dd>
        </dl>
      </${Card}>
      <${Card} title=${`Friends (${data.friends.length})`} pad=${false}>
        ${data.friends.length ? html`<ul class="rows">${data.friends.map((p) => html`<li key=${p.id} class="row-line">
          <${Status} status=${statusOf(p.id)} label=${false} /><${UserLink} id=${p.id} user=${p.user} /><span class="muted small">${p.tag}</span>
          <a class="right small" href=${`#/messages/${Math.min(a.id, p.id)}/${Math.max(a.id, p.id)}`}>chat</a></li>`)}</ul>` : html`<${Empty}>No friends yet</${Empty}>`}
        ${(data.requests_in.length > 0 || data.requests_out.length > 0 || data.blocked.length > 0) && html`<div class="card-body sub">
          ${data.requests_in.length > 0 && html`<div><span class="muted">Asked by</span> ${data.requests_in.map((p) => html`<${UserLink} ...${p} /> `)}</div>`}
          ${data.requests_out.length > 0 && html`<div><span class="muted">Asked</span> ${data.requests_out.map((p) => html`<${UserLink} ...${p} /> `)}</div>`}
          ${data.blocked.length > 0 && html`<div><span class="muted">Blocked</span> ${data.blocked.map((p) => html`<${UserLink} ...${p} /> `)}</div>`}
        </div>`}
      </${Card}>
      <${Card} title=${`Sessions (${data.sessions.length})`} pad=${false}>
        ${data.sessions.length ? html`<ul class="rows">${data.sessions.map((s, i) => html`<li key=${i} class="row-line">
          <span class=${'badge ' + (s.kind === 'admin' ? 'role-admin' : '')}>${s.kind}</span>
          <span class="small">used ${s.last_used ? ago(s.last_used * 1000) : '—'}</span>
          <span class="muted small right" title=${'since ' + fullDate(s.created * 1000)}>until ${new Date(s.expires * 1000).toLocaleDateString()}</span></li>`)}</ul>` : html`<${Empty}>Logged out everywhere</${Empty}>`}
      </${Card}>
    </div>
    <div class="grid two">
      <${Card} title="Recent games" pad=${false} actions=${html`<a class="btn ghost sm" href=${'#/games?user=' + encodeURIComponent(a.user)}>All</a>`}>
        ${data.games.length ? html`<div class="table-wrap"><table class="table compact"><tbody>${data.games.map((g) => html`<tr key=${g.id} class="clickable" onClick=${() => go('games/' + g.id)}>
          <td><span class=${'result r-' + g.result}>${g.result}</span></td>
          <td>vs ${g.opponent ? html`<${UserLink} ...${g.opponent} />` : '—'}</td>
          <td><span class=${'mode m-' + g.mode}>${g.mode}</span></td>
          <td class="muted small">${g.reason}</td>
          <td class="muted small nowrap" title=${fullDate(g.ended * 1000)}>${ago(g.ended * 1000)}</td>
        </tr>`)}</tbody></table></div>` : html`<${Empty}>No games yet</${Empty}>`}
      </${Card}>
      <${Card} title="Recent messages" pad=${false} actions=${html`<a class="btn ghost sm" href=${'#/messages?user=' + encodeURIComponent(a.user)}>Conversations</a>`}>
        ${data.messages.length ? html`<ul class="rows">${data.messages.map((m) => html`<li key=${m.id}>
          <a class="row-link" href=${`#/messages/${Math.min(a.id, m.with.id)}/${Math.max(a.id, m.with.id)}`}>
            <span><span class="muted small">${m.out ? 'to' : 'from'}</span> <b>${m.with.user}</b>${!m.out && !m.seen ? html` <span class="badge">unread</span>` : ''}
              <span class="muted small right">${clock(m.at * 1000)}</span></span>
            <span class="msg-preview">${m.text}</span></a></li>`)}</ul>` : html`<${Empty}>No messages</${Empty}>`}
      </${Card}>
    </div>
    <${Card} title="Activity" pad=${false} actions=${html`<a class="btn ghost sm" href=${'#/events?user=' + encodeURIComponent(a.user)}>Event log</a>`}>
      ${events.length ? html`<ul class="feed">${events.map((e) => html`<${FeedRow} key=${e.id} e=${e} />`)}</ul>` : html`<${Empty}>Nothing logged</${Empty}>`}
    </${Card}>
    ${modal === 'suspend' && html`<${Confirm} title=${'Suspend ' + a.user + '?'} text="The player is logged out at once and cannot log in or play until unsuspended."
      button="Suspend" kind="warn" onClose=${() => setModal(null)} onYes=${() => act('suspend')} />`}
    ${modal === 'password' && html`<${PasswordModal} user=${a.user} onClose=${() => setModal(null)} onSet=${(password) => act('password', { password })} />`}
    ${modal === 'delete' && html`<${DeleteModal} user=${a.user} onClose=${() => setModal(null)} onYes=${() => act('delete', { confirm: a.user })} />`}
  </div>`
}

export function Confirm ({ title, text, button, kind, onClose, onYes }) {
  return html`<${Modal} title=${title} onClose=${onClose}>
    <p>${text}</p>
    <div class="form-actions"><button class="btn ghost" onClick=${onClose}>Cancel</button><button class=${'btn ' + kind} onClick=${onYes} autofocus>${button}</button></div>
  </${Modal}>`
}

function PasswordModal ({ user, onClose, onSet }) {
  const [pw, setPw] = useState('')
  return html`<${Modal} title=${'New password for ' + user} onClose=${onClose}>
    <form class="form" onSubmit=${(e) => { e.preventDefault(); onSet(pw) }}>
      <label>Password<input type="password" minlength="8" maxlength="128" required autocomplete="new-password" value=${pw} onInput=${(e) => setPw(e.target.value)} autofocus />
        <small>The account is logged out everywhere.</small></label>
      <div class="form-actions"><button type="button" class="btn ghost" onClick=${onClose}>Cancel</button><button class="btn primary">Set password</button></div>
    </form>
  </${Modal}>`
}

function DeleteModal ({ user, onClose, onYes }) {
  const [typed, setTyped] = useState('')
  return html`<${Modal} title=${'Delete ' + user + '?'} onClose=${onClose}>
    <form class="form" onSubmit=${(e) => { e.preventDefault(); if (typed === user) onYes() }}>
      <p>The account goes with its friends, messages and Arena run. Its games and events stay in the log. This cannot be undone.</p>
      <label><span>Type <b>${user}</b> to confirm</span><input value=${typed} onInput=${(e) => setTyped(e.target.value)} autofocus autocomplete="off" /></label>
      <div class="form-actions"><button type="button" class="btn ghost" onClick=${onClose}>Cancel</button><button class="btn danger" disabled=${typed !== user}>Delete for good</button></div>
    </form>
  </${Modal}>`
}
