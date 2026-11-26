// Messages: every conversation between players, and one conversation (live); the tournament chats.

import { useState, useEffect, useRef } from 'preact/hooks'
import { api, qs } from './api.js'
import { html, useCan, useEvents, useLoad, useDebounced, useTick, setQuery, toast, Card, UserLink, ErrorBox, Empty, Icon, clock, fullDate, ago } from './ui.js'

export function Messages ({ a, b, query }) {
  const [user, setUser] = useState(query.user || '')
  const [draft, setDraft] = useState(user)
  const [page, setPage] = useState(0)
  const commit = useDebounced((u) => { setUser(u); setPage(0) }, 350)
  useEffect(() => { setQuery({ user }) }, [user])
  const [data, error, reload] = useLoad(() => api('conversations?' + qs({ user, page })), [user, page])
  const later = useDebounced(reload, 400)
  useEvents((e) => { if (e.resync || e.kind === 'msg') later() })
  useTick(15000)
  const sel = a && b ? `${a}/${b}` : null
  return html`<div class="page">
    <header class="page-head"><h1>Messages</h1><span class="muted">What players write to each other</span></header>
    <div class="split">
      <${Card} pad=${false} cls="conv-list">
        <div class="filters inset"><label class="search"><${Icon} name="search" size=${16} /><input placeholder="Player" value=${draft}
          onInput=${(e) => { setDraft(e.target.value); commit(e.target.value) }} /></label></div>
        <${ErrorBox} error=${error} onRetry=${reload} />
        ${data && (data.list.length ? html`<ul class="rows">${data.list.map((c) => {
          const key = `${c.a.id}/${c.b.id}`
          const from = c.last && (c.last.from === c.a.id ? c.a.user : c.b.user)
          return html`<li key=${key}><a class=${'row-link' + (sel === key ? ' on' : '')} href=${'#/messages/' + key + (user ? '?user=' + encodeURIComponent(user) : '')}>
            <span><b>${c.a.user || '?'}</b> <span class="muted">&</span> <b>${c.b.user || '?'}</b>
              ${c.unread > 0 && html` <span class="badge">${c.unread} unread</span>`}
              <span class="muted small right">${c.last ? ago(c.last.at * 1000) : ''}</span></span>
            <span class="msg-preview"><span class="muted">${from}:</span> ${c.last && c.last.text}</span>
            <span class="muted small">${c.count} message${c.count > 1 ? 's' : ''}</span>
          </a></li>`
        })}</ul>` : html`<${Empty}>No conversations</${Empty}>`)}
        ${data && (page > 0 || data.more) && html`<div class="table-foot"><span></span><div class="pager">
          <button class="btn ghost sm" disabled=${page === 0} onClick=${() => setPage(page - 1)}>‹ Newer</button>
          <button class="btn ghost sm" disabled=${!data.more} onClick=${() => setPage(page + 1)}>Older ›</button></div></div>`}
      </${Card}>
      ${sel ? html`<${Conversation} key=${sel} a=${Number(a)} b=${Number(b)} />` : html`<${Card} cls="conv-empty"><${Empty}>Pick a conversation</${Empty}></${Card}>`}
    </div>
  </div>`
}

function Conversation ({ a, b }) {
  const [data, error, reload] = useLoad(() => api(`conversations/${a}/${b}`), [a, b])
  const later = useDebounced(reload, 200)
  const end = useRef(null)
  useEvents((e) => {
    if (e.resync) return reload()
    if (e.kind === 'msg' && e.data && [a, b].includes(e.data.from) && [a, b].includes(e.data.to)) later()
  })
  useEffect(() => { if (end.current) end.current.scrollIntoView({ block: 'end' }) }, [data])
  if (error && !data) return html`<${Card}><${ErrorBox} error=${error} onRetry=${reload} /></${Card}>`
  if (!data) return html`<${Card}><div class="chart-skel"></div></${Card}>`
  const people = Object.fromEntries(data.people.map((p) => [p.id, p]))
  const left = people[a]
  const right = people[b]
  let lastDay = ''
  return html`<${Card} pad=${false} cls="conv"
    title=${html`<span class="conv-title">${left ? html`<${UserLink} id=${a} user=${left.user} />` : '(deleted)'} <span class="muted">&</span> ${right ? html`<${UserLink} id=${b} user=${right.user} />` : '(deleted)'}</span>`}
    actions=${html`<a class="btn ghost sm" href=${'#/events?kind=msg&user=' + encodeURIComponent(left ? left.user : '')}>In the event log</a>`}>
    <div class="bubbles">
      ${data.list.length ? data.list.map((m) => {
        const day = new Date(m.at * 1000).toDateString()
        const sep = day !== lastDay
        lastDay = day
        return html`${sep && html`<div class="day-sep" key=${'d' + m.id}><span>${new Date(m.at * 1000).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}</span></div>`}
          <div key=${m.id} class=${'bubble ' + (m.from === a ? 'left' : 'right')}>
            <span class="who">${(people[m.from] || {}).user || '?'}</span>
            <span class="text">${m.text}</span>
            <span class="meta" title=${fullDate(m.at * 1000)}>${clock(m.at * 1000, false)}${m.seen ? ' · read' : ' · unread'}</span>
          </div>`
      }) : html`<${Empty}>No messages kept (the last 200 of a pair are kept; deleted accounts take theirs along)</${Empty}>`}
      <div ref=${end}></div>
    </div>
  </${Card}>`
}

// --- the tournament chats: the tournaments list's and each tournament's (live) -------------------

const chatTitle = (c) => c.channel === 'tournaments' ? 'Tournaments list' : c.title || c.channel

export function Chats ({ channel }) {
  const [data, error, reload] = useLoad(() => api('chats'), [])
  const later = useDebounced(reload, 400)
  useEvents((e) => { if (e.resync || e.kind === 'chat' || e.kind === 'tournament') later() })
  useTick(30000)
  return html`<div class="page">
    <header class="page-head"><h1>Chats</h1><span class="muted">The tournaments list's chat and each tournament's; write as the admin, delete</span></header>
    <div class="split">
      <${Card} pad=${false} cls="conv-list">
        <${ErrorBox} error=${error} onRetry=${reload} />
        ${data && html`<ul class="rows">${data.chats.map((c) => html`<li key=${c.channel}>
          <a class=${'row-link' + (channel === c.channel ? ' on' : '')} href=${'#/chats/' + encodeURIComponent(c.channel)}>
            <span><b>${chatTitle(c)}</b>${!c.open && html` <span class="badge">closed</span>`}
              <span class="muted small right">${c.last ? ago(c.last * 1000) : ''}</span></span>
            <span class="muted small">${c.count} message${c.count === 1 ? '' : 's'}${c.status ? ' · ' + c.status : ''}</span>
          </a></li>`)}</ul>`}
      </${Card}>
      ${channel ? html`<${Chat} key=${channel} channel=${channel} />` : html`<${Card} cls="conv-empty"><${Empty}>Pick a chat</${Empty}></${Card}>`}
    </div>
  </div>`
}

function Chat ({ channel }) {
  const can = useCan()
  const [data, error, reload] = useLoad(() => api('chats/' + encodeURIComponent(channel)), [channel])
  const later = useDebounced(reload, 200)
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const end = useRef(null)
  useEvents((e) => { if (e.resync || (e.kind === 'chat' && e.data && e.data.channel === channel)) later() })
  useEffect(() => { if (end.current) end.current.scrollIntoView({ block: 'end' }) }, [data])
  const send = async (ev) => {
    ev.preventDefault()
    setBusy(true)
    try { await api('chats/' + encodeURIComponent(channel), { method: 'POST', body: { text } }); setText(''); reload() } catch (err) { toast(err.message, 'err') }
    setBusy(false)
  }
  const del = async (m) => {
    try { await api(`chat_messages/${m.id}/delete`, { method: 'POST' }); reload() } catch (err) { toast(err.message, 'err') }
  }
  if (error && !data) return html`<${Card}><${ErrorBox} error=${error} onRetry=${reload} /></${Card}>`
  if (!data) return html`<${Card}><div class="chart-skel"></div></${Card}>`
  const id = channel.startsWith('t:') ? channel.slice(2) : ''
  return html`<${Card} pad=${false} cls="conv"
    title=${chatTitle(data)}
    actions=${id && html`<a class="btn ghost sm" href=${'#/tournaments/' + id}>The tournament</a>`}>
    <div class="bubbles">
      ${data.list.length ? data.list.map((m) => html`<div key=${m.id} class=${'bubble left' + (m.deleted_by ? ' deleted' : '')}>
          <span class="who">${m.from}${m.mark && html` <span class="badge ok">${m.mark}</span>`}</span>
          ${m.deleted_by
            ? html`<span class="text muted"><i>deleted by ${m.deleted_by}</i>: <s>${m.deleted_text}</s></span>`
            : html`<span class="text">${m.text}</span>`}
          <span class="meta" title=${fullDate(m.at * 1000)}>${clock(m.at * 1000, false)}
            ${!m.deleted_by && can('chats.moderate') && html` · <button class="btn ghost sm danger-hover" onClick=${() => del(m)}>Delete</button>`}</span>
        </div>`) : html`<${Empty}>No messages</${Empty}>`}
      <div ref=${end}></div>
    </div>
    ${data.open && !can('chats.write_as_admin') ? ''
      : data.open
      ? html`<form class="filters inset" onSubmit=${send}>
          <input class="grow" maxlength="500" required placeholder="Write as the admin" value=${text} onInput=${(e) => setText(e.target.value)} />
          <button class="btn primary" disabled=${busy || !text.trim()}>Send</button></form>`
      : html`<p class="muted small inset" style="padding: 12px 16px">Closed: 10 minutes after the tournament's end nobody writes here any more.</p>`}
  </${Card}>`
}
