// The admin panel: the shell (navigation, theme, the live feed) and the router.

import { render } from 'preact'
import { useState, useEffect, useRef } from 'preact/hooks'
import { api, setCsrf, onUnauthorized } from './api.js'
import { html, bus, LiveContext, MeContext, useRoute, Icon, Toasts, toast } from './ui.js'
import { Login } from './login.js'
import { Dashboard } from './dashboard.js'
import { Events } from './events.js'
import { Accounts, AccountPage } from './accounts.js'
import { Games, GamePage } from './games.js'
import { Messages } from './messages.js'
import { Packs } from './packs.js'
import { Bots } from './bots.js'

const NAV = [
  ['', 'Dashboard', 'dashboard'],
  ['events', 'Event log', 'events'],
  ['games', 'Matches', 'games'],
  ['packs', 'Games', 'packs'],
  ['bots', 'Bots', 'bots'],
  ['accounts', 'Accounts', 'accounts'],
  ['messages', 'Messages', 'messages']
]

// --- theme: system (default), light or dark; remembered -------------------------------

function useTheme () {
  const [theme, set] = useState(() => { try { return localStorage.getItem('chs-theme') || 'system' } catch (e) { return 'system' } })
  useEffect(() => {
    const root = document.documentElement
    if (theme === 'system') delete root.dataset.theme
    else root.dataset.theme = theme
    try { localStorage.setItem('chs-theme', theme) } catch (e) { /* private mode */ }
  }, [theme])
  return [theme, set]
}

function ThemeSwitch () {
  const [theme, set] = useTheme()
  return html`<div class="seg" role="radiogroup" aria-label="Theme">
    ${[['system', 'System'], ['light', 'Light'], ['dark', 'Dark']].map(([k, label]) => html`
      <button role="radio" aria-checked=${theme === k} class=${theme === k ? 'on' : ''} title=${label} onClick=${() => set(k)}>
        <${Icon} name=${k === 'system' ? 'system' : k === 'light' ? 'sun' : 'moon'} size=${15} /></button>`)}
  </div>`
}

// --- the live feed: /admin/ws, reconnecting ------------------------------------------

function useFeed (me) {
  const [live, setLive] = useState({ online: [], queue: [], games: [] })
  const [conn, setConn] = useState('connecting')
  const wsRef = useRef(null)
  useEffect(() => {
    if (!me) return
    let closed = false
    let delay = 500
    let timer = 0
    const open = () => {
      setConn('connecting')
      const ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/admin/ws')
      wsRef.current = ws
      let hello = false
      ws.onmessage = (m) => {
        const v = JSON.parse(m.data)
        if (v.t === 'hello') {
          hello = true
          delay = 500
          setConn('live')
          setLive(v.live)
          bus.emit({ resync: true })
        } else if (v.t === 'live') setLive(v.live)
        else if (v.t === 'event') bus.emit(v.e)
        else if (v.t === 'resync') bus.emit({ resync: true })
      }
      ws.onclose = () => {
        if (closed) return
        setConn('offline')
        // Refused before hello: maybe the session is gone.
        if (!hello) api('me').catch(() => {})
        timer = setTimeout(open, delay)
        delay = Math.min(delay * 2, 10000)
      }
    }
    open()
    return () => { closed = true; clearTimeout(timer); wsRef.current && wsRef.current.close() }
  }, [me])
  return { live, conn }
}

// --- the shell ------------------------------------------------------------------------------

function Shell ({ me, onLogout }) {
  const route = useRoute()
  const feed = useFeed(me)
  const [top] = route.path
  const qkey = JSON.stringify(route.query)
  let page
  switch (top) {
    case undefined: page = html`<${Dashboard} />`; break
    case 'events': page = html`<${Events} query=${route.query} key=${qkey} />`; break
    case 'games': page = route.path[1] ? html`<${GamePage} id=${route.path[1]} key=${route.path[1]} />` : html`<${Games} query=${route.query} key=${qkey} />`; break
    case 'accounts': page = route.path[1] ? html`<${AccountPage} id=${route.path[1]} key=${route.path[1]} />` : html`<${Accounts} query=${route.query} key=${qkey} />`; break
    case 'packs': page = html`<${Packs} />`; break
    case 'bots': page = html`<${Bots} />`; break
    case 'messages': page = html`<${Messages} a=${route.path[1]} b=${route.path[2]} query=${route.query} />`; break
    default: page = html`<div class="page"><h1>Not found</h1><p><a href="#/">Back to the dashboard</a></p></div>`
  }
  const counts = { '': null, games: feed.live.games.length || null, accounts: feed.live.online.length || null }
  return html`<${MeContext.Provider} value=${me}><${LiveContext.Provider} value=${feed}>
    <div class="shell">
      <aside class="side">
        <a class="brand" href="#/"><span class="logo">◆</span><span><b>Classic HS</b><small>server admin</small></span></a>
        <nav>
          ${NAV.map(([p, label, icon]) => html`<a href=${'#/' + p} class=${(top || '') === p ? 'on' : ''}>
            <${Icon} name=${icon} /><span>${label}</span>${counts[p] ? html`<em class="count">${counts[p]}</em>` : ''}</a>`)}
        </nav>
        <div class="side-foot">
          <div class=${'conn ' + feed.conn} title="The live feed (/admin/ws)"><i></i>${feed.conn === 'live' ? 'Live' : feed.conn === 'connecting' ? 'Connecting…' : 'Reconnecting…'}</div>
          <${ThemeSwitch} />
          <div class="whoami">
            <span><b>${me.user}</b><small>${me.role === 'super' ? 'superuser' : 'admin'}</small></span>
            <button class="btn ghost icon-only" title="Log out" aria-label="Log out" onClick=${onLogout}><${Icon} name="logout" /></button>
          </div>
        </div>
      </aside>
      <main class="main">${page}</main>
    </div>
    <${Toasts} />
  </${LiveContext.Provider}></${MeContext.Provider}>`
}

function App () {
  const [me, setMe] = useState(undefined) // undefined = checking, null = logged out
  useEffect(() => {
    onUnauthorized(() => setMe(null))
    api('me').then((m) => { setCsrf(m.csrf); setMe(m) }, () => setMe(null))
  }, [])
  if (me === undefined) return html`<div class="boot"><span class="logo pulse">◆</span></div>`
  if (!me) return html`<${Login} onIn=${(m) => { setCsrf(m.csrf); setMe(m) }} />`
  const logout = async () => {
    try { await api('logout', { method: 'POST' }) } catch (e) { toast(e.message, 'err') }
    setCsrf('')
    setMe(null)
  }
  return html`<${Shell} me=${me} onLogout=${logout} />`
}

render(html`<${App} />`, document.getElementById('app'))
