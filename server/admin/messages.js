// Messages: every conversation between players, and one conversation (live).

import { useState, useEffect, useRef } from 'preact/hooks'
import { api, qs } from './api.js'
import { html, useEvents, useLoad, useDebounced, useTick, setQuery, Card, UserLink, ErrorBox, Empty, Icon, clock, fullDate, ago } from './ui.js'

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
