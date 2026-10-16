// Games: the game packs (.cardpack) the server offers, the players' own packs, uploads
// (drag and drop), enable/disable, delete; live from the event log.

import { useState, useEffect, useRef } from 'preact/hooks'
import { api, upload } from './api.js'
import { html, useEvents, useLoad, useDebounced, useTick, toast, Card, UserLink, ErrorBox, Empty, Icon, ago, fullDate, num, bytes } from './ui.js'
import { FeedRow } from './dashboard.js'
import { Confirm } from './accounts.js'

const PACK_KINDS = ['pack_upload', 'pack_import', 'pack_default', 'pack_enable', 'pack_disable', 'pack_delete', 'pack_rejected', 'pack_download']
/** The activity card leaves the downloads out (the counts show them). */
const FEED_KINDS = PACK_KINDS.filter((k) => k !== 'pack_download')

/** The pack's name in the panel's language, else English, else any. */
function title (p) {
  const n = p.name || {}
  const lang = (navigator.language || 'en').slice(0, 2)
  return n[lang] || n.en || Object.values(n)[0] || p.pack_id
}

/** A cover tile coloured from the content hash (packs have no picture the server reads yet). */
function Cover ({ p }) {
  const h = parseInt(p.content_hash.slice(0, 6), 16)
  const a = h % 360
  const b = (a + 40 + (h >> 9) % 80) % 360
  const letter = (title(p).match(/[\p{L}\p{N}]/u) || ['?'])[0].toUpperCase()
  return html`<span class="cover" style=${`--h1:${a};--h2:${b}`} aria-hidden="true">${letter}</span>`
}

function Hash ({ value, label }) {
  const copy = async (e) => {
    e.stopPropagation()
    try { await navigator.clipboard.writeText(value); toast(label + ' copied') } catch (err) { toast('Copy failed: ' + err.message, 'err') }
  }
  return html`<button class="hash" title=${label + ': ' + value + ' (click to copy)'} onClick=${copy}>${value.slice(0, 10)}<span>…</span></button>`
}

function Switch ({ on, onChange, label, busy }) {
  return html`<button role="switch" aria-checked=${on} aria-label=${label} title=${label} disabled=${busy}
    class=${'switch' + (on ? ' on' : '')} onClick=${() => onChange(!on)}><i></i></button>`
}

/** Drop .cardpack files here (or anywhere on the page) or pick them; uploads one by one with progress. */
function DropZone ({ limit, onDone }) {
  const [over, setOver] = useState(false)
  const [job, setJob] = useState(null) // {name, i, n, p}
  const input = useRef(null)
  const depth = useRef(0)
  const send = async (files) => {
    files = [...files].filter((f) => f.size > 0)
    if (!files.length || job) return
    for (let i = 0; i < files.length; i++) {
      const f = files[i]
      if (!/\.(cardpack|zip)$/i.test(f.name)) { toast(f.name + ': not a .cardpack', 'err'); continue }
      if (limit && f.size > limit) { toast(`${f.name}: over ${bytes(limit)}`, 'err'); continue }
      setJob({ name: f.name, i, n: files.length, p: 0 })
      try {
        const r = await upload('packs', f, (p) => setJob((j) => j && { ...j, p }))
        toast(`${title(r.pack)} ${r.pack.version} is on the server`)
      } catch (err) { toast(`${f.name}: ${err.message}`, 'err') }
    }
    setJob(null)
    onDone()
  }
  useEffect(() => {
    const has = (e) => [...(e.dataTransfer?.types || [])].includes('Files')
    const enter = (e) => { if (has(e)) { depth.current++; setOver(true) } }
    const leave = () => { depth.current = Math.max(0, depth.current - 1); if (!depth.current) setOver(false) }
    const overFn = (e) => { if (has(e)) e.preventDefault() }
    const drop = (e) => { if (!has(e)) return; e.preventDefault(); depth.current = 0; setOver(false); send(e.dataTransfer.files) }
    addEventListener('dragenter', enter); addEventListener('dragleave', leave); addEventListener('dragover', overFn); addEventListener('drop', drop)
    return () => { removeEventListener('dragenter', enter); removeEventListener('dragleave', leave); removeEventListener('dragover', overFn); removeEventListener('drop', drop) }
  })
  return html`<div class=${'dropzone' + (over ? ' over' : '') + (job ? ' busy' : '')} onClick=${() => !job && input.current.click()}
      role="button" tabindex="0" onKeyDown=${(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); input.current.click() } }}>
    <input ref=${input} type="file" accept=".cardpack,.zip" multiple hidden onChange=${(e) => { send(e.target.files); e.target.value = '' }} />
    <span class="dz-icon"><${Icon} name="upload" size=${26} /></span>
    ${job
      ? html`<div class="dz-text"><b>Uploading ${job.name}</b>${job.n > 1 ? html` <span class="muted">(${job.i + 1} of ${job.n})</span>` : ''}
          <div class="progress"><i style=${`width:${Math.round(job.p * 100)}%`}></i></div>
          <span class="muted small">${job.p < 1 ? Math.round(job.p * 100) + ' %' : 'Checking and storing…'}</span></div>`
      : html`<div class="dz-text"><b>${over ? 'Drop to upload' : 'Drop .cardpack files here'}</b>
          <span class="muted">or <span class="link">choose files</span> · up to ${bytes(limit)} · enabled for players at once</span></div>`}
  </div>`
}

/** The default game's name (the starred server pack, else the server's built-in Classic rules). */
function defaultName (data) {
  const d = data.server.find((p) => p.default && p.enabled)
  return d ? `${title(d)} ${d.version}` : 'built-in Classic'
}

function PackCell ({ p }) {
  return html`<div class="pack-cell"><${Cover} p=${p} /><span><b>${title(p)}</b><small class="mono">${p.pack_id}</small></span></div>`
}

/** The default game's star: on for the default, a button that makes a server pack the default. */
function DefaultStar ({ p, onDefault }) {
  if (p.default) return html`<span class="default-star on" title="The default game: requests without a pack play it"><${Icon} name="star" size=${17} /></span>`
  return html`<button class="btn ghost sm icon-only default-star" disabled=${!p.enabled} title=${p.enabled ? 'Make it the default game' : 'Enable it first'}
    aria-label=${'Make ' + title(p) + ' the default game'} onClick=${() => onDefault(p)}><${Icon} name="star" size=${17} /></button>`
}

function PackTable ({ list, players, busy, onToggle, onDelete, onDefault }) {
  if (!list.length) return html`<${Empty}>${players ? 'No player has uploaded a pack yet' : 'No server packs: drop one above, or put *.cardpack files into --packs-dir'}</${Empty}>`
  return html`<div class="table-wrap"><table class="table packs">
    <thead><tr>
      ${players ? html`<th>Player</th>` : html`<th title="The default game">Default</th>`}<th>Pack</th><th>Version</th><th class="num">Size</th><th>Rules hash</th><th>Content hash</th>
      <th class="num" title="Finished games in these rules (and live now)">Games</th><th class="num">Downloads</th><th>${players ? 'Uploaded' : 'Added'}</th><th>${players ? 'Shared' : 'Enabled'}</th><th></th>
    </tr></thead>
    <tbody>${list.map((p) => html`<tr key=${p.id} class=${p.enabled ? '' : 'off'}>
      ${players ? html`<td><${UserLink} ...${p.owner} /></td>` : html`<td><${DefaultStar} p=${p} onDefault=${onDefault} /></td>`}
      <td><${PackCell} p=${p} /></td>
      <td><span class="ver">${p.version}</span></td>
      <td class="num nowrap">${bytes(p.size)}</td>
      <td><${Hash} value=${p.rules_hash} label="Rules hash" /></td>
      <td><${Hash} value=${p.content_hash} label="Content hash" /></td>
      <td class="num nowrap">${num(p.games || 0)}${p.live ? html` <span class="live-count" title="Live now">· ${p.live} live</span>` : ''}</td>
      <td class="num">${num(p.downloads)}</td>
      <td class="nowrap" title=${fullDate(p.created * 1000)}>${ago(p.created * 1000)}</td>
      <td><${Switch} on=${p.enabled} busy=${busy === p.id} label=${p.enabled ? 'Disable' : 'Enable'} onChange=${(on) => onToggle(p, on)} /></td>
      <td class="right-cell"><button class="btn ghost sm icon-only danger-hover" title="Delete" aria-label=${'Delete ' + title(p)} onClick=${() => onDelete(p)}><${Icon} name="trash" size=${16} /></button></td>
    </tr>`)}</tbody>
  </table></div>`
}

export function Packs () {
  const [data, error, reload, loading] = useLoad(() => api('packs'), [])
  const [recent, , reloadRecent] = useLoad(() => api('events?size=10&kind=' + FEED_KINDS.join(',')), [])
  const [feed, setFeed] = useState([])
  const [busy, setBusy] = useState(null)
  const [del, setDel] = useState(null)
  useEffect(() => { if (recent) setFeed(recent.list) }, [recent])
  const later = useDebounced(reload, 300)
  useEvents((e) => {
    if (e.resync) { reload(); reloadRecent(); return }
    if (!PACK_KINDS.includes(e.kind)) return
    if (FEED_KINDS.includes(e.kind)) setFeed((f) => [e, ...f].slice(0, 10))
    later()
  })
  useTick(15000)
  const toggle = async (p, on) => {
    setBusy(p.id)
    try { const r = await api(`packs/${p.id}/${on ? 'enable' : 'disable'}`, { method: 'POST' }); toast(r.text); reload() } catch (err) { toast(err.message, 'err') }
    setBusy(null)
  }
  const makeDefault = async (p) => {
    try { const r = await api(`packs/${p.id}/default`, { method: 'POST' }); toast(r.text); reload() } catch (err) { toast(err.message, 'err') }
  }
  const remove = async () => {
    const p = del
    setDel(null)
    try { const r = await api(`packs/${p.id}/delete`, { method: 'POST' }); toast(r.text); reload() } catch (err) { toast(err.message, 'err') }
  }
  const s = data && data.stats
  return html`<div class="page">
    <header class="page-head"><h1>Games</h1><span class="muted">Game packs (.cardpack): what the server offers and what players uploaded · updates live</span></header>
    <${ErrorBox} error=${error} onRetry=${reload} />
    ${s ? html`<div class="tiles">
      <div class="tile accent"><span class="tile-label">Server packs</span><span class="tile-value">${num(s.server)}</span><span class="tile-sub">${s.enabled} enabled · offered to every player</span></div>
      <div class="tile"><span class="tile-label">Players' packs</span><span class="tile-value">${num(s.players)}</span><span class="tile-sub">by ${s.uploaders} player${s.uploaders === 1 ? '' : 's'} · ${s.limits.per_player} each at most</span></div>
      <div class="tile"><span class="tile-label">Games played</span><span class="tile-value">${num(s.games || 0)}</span><span class="tile-sub">${num(s.live || 0)} live now · default: ${defaultName(data)}</span></div>
      <div class="tile"><span class="tile-label">Stored</span><span class="tile-value">${bytes(s.bytes)}</span><span class="tile-sub" title=${s.storage}>${s.files} file${s.files === 1 ? '' : 's'} · ${num(s.downloads)} downloads · ${s.storage}</span></div>
    </div>` : html`<div class="tiles">${[0, 1, 2, 3].map(() => html`<div class="tile skel-tile"></div>`)}</div>`}
    <${DropZone} limit=${s ? s.limits.server : 0} onDone=${reload} />
    <${Card} title=${`Server packs${data ? ' (' + data.server.length + ')' : ''}`} pad=${false} cls=${loading ? 'loading' : ''}
      actions=${html`<span class="muted small">Only server packs go to the queues · the starred one is the default game</span>`}>
      ${data && html`<${PackTable} list=${data.server} busy=${busy} onToggle=${toggle} onDelete=${setDel} onDefault=${makeDefault} />`}
    </${Card}>
    <${Card} title=${`Players' packs${data ? ' (' + data.players.length + ')' : ''}`} pad=${false} cls=${loading ? 'loading' : ''}
      actions=${html`<span class="muted small">For friendly games with friends; ${s ? bytes(s.limits.player) : '100 MB'} each · off = not shared</span>`}>
      ${data && html`<${PackTable} list=${data.players} players busy=${busy} onToggle=${toggle} onDelete=${setDel} />`}
    </${Card}>
    <${Card} title="Pack activity" pad=${false} actions=${html`<a class="btn ghost sm" href=${'#/events?kind=' + PACK_KINDS.join(',')}>All, with downloads</a>`}>
      ${feed.length ? html`<ul class="feed">${feed.map((e) => html`<${FeedRow} key=${e.id} e=${e} />`)}</ul>` : html`<${Empty}>Nothing yet</${Empty}>`}
    </${Card}>
    ${del && html`<${Confirm} title=${`Delete ${title(del)} ${del.version}?`} kind="danger" button="Delete" onClose=${() => setDel(null)} onYes=${remove}
      text=${del.owner
        ? `This is ${del.owner.user}'s pack. It goes from the server and from their list; games that have it keep their copy.`
        : 'Players will no longer get it from this server; games that have it keep their copy. Bundled packs are not installed again.'} />`}
  </div>`
}
