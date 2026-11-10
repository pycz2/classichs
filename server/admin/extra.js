// Beside the pages (server/src/admin_extra.rs): the server's version in the corner, the
// database and pack store sizes, and the replay player docked at the bottom of the page.

import { useState, useEffect } from 'preact/hooks'
import { api } from './api.js'
import { html, useMe, useLoad, Card, Icon, ErrorBox, bytes, num } from './ui.js'

/** The server's release version, always in the top right corner. */
export function VersionTag () {
  const me = useMe()
  return me && me.version ? html`<span class="version-tag" title="The server's version">v${me.version}</span>` : null
}

/** The dashboard's "Storage": the SQLite file and its WAL, the pack store. */
export function StorageCard () {
  const [s, error, reload] = useLoad(() => api('storage'), [])
  return html`<${Card} title="Storage" actions=${html`<button class="btn ghost sm" onClick=${reload}>Refresh</button>`}>
    <${ErrorBox} error=${error} onRetry=${reload} />
    ${s && html`<dl class="kv">
      <dt>Database</dt><dd><b>${bytes(s.db.total)}</b> <span class="muted small">file ${bytes(s.db.file)} · WAL ${bytes(s.db.wal)}</span>
        ${s.db.path ? html`<div class="muted small mono">${s.db.path}</div>` : html`<div class="muted small">in memory</div>`}</dd>
      <dt>Pack store</dt><dd>${s.packs.error ? html`<span class="badge bad">${s.packs.error}</span>`
        : html`<b>${bytes(s.packs.bytes)}</b> <span class="muted small">${num(s.packs.files)} files</span>`}
        <div class="muted small mono">${s.packs.what}</div></dd>
    </dl>`}
  </${Card}>`
}

// --- the replay player ----------------------------------------------------------------------

let open = () => {}
/** Opens the player at the bottom of the page with that game's replay. */
export const playReplay = (id) => open(id)

/** The docked player: the client's replay view (/admin/replay/, a cut-down web build) in a
 * frame. Closed by its button, the player's Back, or going to another page. */
export function ReplayDock () {
  const [id, setId] = useState(null)
  useEffect(() => {
    open = setId
    const close = () => setId(null)
    const onMsg = (e) => { if (e.origin === location.origin && e.data === 'chs-replay-close') close() }
    addEventListener('hashchange', close)
    addEventListener('message', onMsg)
    return () => { open = () => {}; removeEventListener('hashchange', close); removeEventListener('message', onMsg) }
  }, [])
  if (!id) return null
  return html`<section class="replay-dock" aria-label="Replay player">
    <header><b>Replay</b><span class="muted small mono">${id}</span>
      <button class="btn ghost sm icon-only" title="Close" aria-label="Close the replay" onClick=${() => setId(null)}><${Icon} name="x" /></button>
    </header>
    <iframe key=${id} src=${'/admin/replay/index.html?game=' + encodeURIComponent(id)} title="Replay player" allow="fullscreen"></iframe>
  </section>`
}
