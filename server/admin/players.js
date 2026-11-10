// An account's games on its page: per game the ranked standing, the settings and the decks (with
// their codes), and the changes to them; the Arena run and the tag (POST accounts/{id}/…,
// admin_players.rs). Each change is pushed to the player at once when online.

import { useState } from 'preact/hooks'
import { api } from './api.js'
import { html, toast, Card, Modal, Empty, Icon, CopyCode, DeckList, num, fullDate } from './ui.js'
import { Rank, Confirm } from './accounts.js'

/** A change: its text as a toast, then the page again; an error is thrown (the form shows it). */
async function change (id, path, body, reload) {
  const r = await api(`accounts/${id}/${path}`, { method: 'POST', body })
  toast(r.text)
  reload()
}

/** A form in a modal: an error stays in it (the input kept), success closes it. */
function FormModal ({ title, button = 'Save', kind = 'primary', onClose, onSubmit, children }) {
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const submit = async (e) => {
    e.preventDefault()
    setBusy(true)
    try { await onSubmit(); onClose() } catch (err) { setError(err.message); setBusy(false) }
  }
  return html`<${Modal} title=${title} onClose=${onClose}>
    <form class="form" onSubmit=${submit}>${children}
      ${error && html`<div class="error-box" role="alert">${error}</div>`}
      <div class="form-actions"><button type="button" class="btn ghost" onClick=${onClose}>Cancel</button>
        <button class=${'btn ' + kind} disabled=${busy}>${button}</button></div>
    </form>
  </${Modal}>`
}

/** Confirm, then the change (an error as a toast). */
function ask (setModal, props, run) {
  setModal(html`<${Confirm} ...${props} onClose=${() => setModal(null)} onYes=${async () => {
    setModal(null)
    try { await run() } catch (err) { toast(err.message, 'err') }
  }} />`)
}

// --- the page's parts -------------------------------------------------------------------------------

/** The tag: a new one, or none. */
export function TagModal ({ a, onClose, reload }) {
  const [tag, setTag] = useState(a.tag || '')
  return html`<${FormModal} title=${'Tag of ' + a.user} onClose=${onClose} onSubmit=${() => change(a.id, 'tag', { tag }, reload)}>
    <label>Tag<input value=${tag} maxlength="16" onInput=${(e) => setTag(e.target.value)} autofocus />
      <small>3–16 letters or digits, unique ignoring case; empty removes it. Friends add the player by it.</small></label>
  </${FormModal}>`
}

/** The Arena run's record: wins and losses, or the end of the run. */
export function ArenaButtons ({ a, run, games, reload, setModal }) {
  const g = games.find((x) => x.rules_hash === run.pack)
  const max = g ? g.arena : null
  const edit = () => setModal(html`<${ArenaModal} a=${a} run=${run} max=${max} onClose=${() => setModal(null)} reload=${reload} />`)
  const end = () => ask(setModal, { title: 'End the Arena run of ' + a.user + '?', text: `The run (${run.wins}–${run.losses}) is gone; the player may start a new one.`, button: 'End the run', kind: 'danger' },
    () => change(a.id, 'arena', { action: 'end' }, reload))
  return html`<span class="inline-actions"><button class="btn ghost sm" onClick=${edit}>Edit</button><button class="btn ghost sm" onClick=${end}>End</button></span>`
}

function ArenaModal ({ a, run, max, onClose, reload }) {
  const [v, setV] = useState({ wins: run.wins, losses: run.losses })
  const n = (k) => (e) => setV({ ...v, [k]: Number(e.target.value) })
  return html`<${FormModal} title=${'Arena run of ' + a.user} onClose=${onClose} onSubmit=${() => change(a.id, 'arena', { action: 'set', ...v }, reload)}>
    <div class="form-row">
      <label>Wins<input type="number" min="0" max=${max ? max.wins - 1 : null} required value=${v.wins} onInput=${n('wins')} autofocus /></label>
      <label>Losses<input type="number" min="0" max=${max ? max.losses - 1 : null} required value=${v.losses} onInput=${n('losses')} /></label>
    </div>
    <small class="muted">${max ? `The run goes on: 0–${max.wins - 1} wins, 0–${max.losses - 1} losses (${max.wins} wins or ${max.losses} losses end it).` : ''}</small>
    <button type="button" class="btn ghost sm" onClick=${() => setV({ wins: 0, losses: 0 })}>Back to 0–0</button>
  </${FormModal}>`
}

/** Every game of the account: a tab each. */
export function PlayerGames ({ a, games, may, reload, setModal }) {
  const [sel, setSel] = useState(() => (games.find((g) => g.pack === a.pack) || games[0] || {}).pack)
  const g = games.find((x) => x.pack === sel) || games[0]
  if (!g) return null
  const props = { a, g, may, reload, setModal }
  return html`<section class="player-games">
    <header class="games-head"><h2>Games</h2>
      <div class="seg text" role="tablist">${games.map((x) => html`<button key=${x.pack} role="tab" aria-selected=${x.pack === g.pack} class=${x.pack === g.pack ? 'on' : ''}
        onClick=${() => setSel(x.pack)}>${x.name}${x.decks.length ? html` <span class="badge" title="Decks">${x.decks.length}</span>` : ''}</button>`)}</div>
    </header>
    <div class="grid two">
      <${Standing} ...${props} />
      <${Settings} ...${props} />
    </div>
    <${Decks} ...${props} />
  </section>`
}

// --- the standing ------------------------------------------------------------------------------------

function Standing ({ a, g, may, reload, setModal }) {
  const s = g.standing
  const edit = () => setModal(html`<${StandingModal} a=${a} g=${g} onClose=${() => setModal(null)} reload=${reload} />`)
  const reset = () => ask(setModal, { title: 'Reset to the season\'s start?', text: `${a.user}'s rank and MMRs in ${g.name} this season (${s.season}) go back to what the season started with (the last season's rank after its reset, or the ladder's start).`, button: 'Reset', kind: 'warn' },
    () => change(a.id, 'standing', { pack: g.pack, reset: true }, reload))
  return html`<${Card} title=${html`${g.ranked ? 'Ranked' : 'Rating'} <span class="muted small">season ${s.season}</span>`}
    actions=${may && html`<button class="btn sm" onClick=${edit}>Edit…</button><button class="btn ghost sm" onClick=${reset}>Reset to season start</button>`}>
    <dl class="kv">
      ${g.ranked && html`<dt>Rank</dt><dd><${Rank} a=${s} /> ${s.rank > 0 && html`<span class="muted small">${s.stars} star${s.stars === 1 ? '' : 's'}</span>`}</dd>
        <dt>Win streak</dt><dd>${s.streak}</dd>`}
      <dt>Ranked MMR</dt><dd>${num(s.ranked_mmr)}</dd>
      <dt>Casual MMR</dt><dd>${num(s.casual_mmr)}</dd>
      ${!s.kept && html`<dt></dt><dd class="muted small">Not played this season: the season's start</dd>`}
    </dl>
  </${Card}>`
}

function StandingModal ({ a, g, onClose, reload }) {
  const s = g.standing
  const [v, setV] = useState({ rank: s.rank, stars: s.stars, streak: s.streak, ranked_mmr: s.ranked_mmr, casual_mmr: s.casual_mmr })
  const set = (k) => (e) => setV({ ...v, [k]: Number(e.target.value) })
  const legend = v.rank === 0
  const step = g.ladder.ranks.find((r) => r.rank === v.rank)
  const submit = () => change(a.id, 'standing', g.ranked
    ? { pack: g.pack, ...v, legend, ...(legend ? { rank: undefined, stars: undefined } : {}) }
    : { pack: g.pack, ranked_mmr: v.ranked_mmr, casual_mmr: v.casual_mmr }, reload)
  // ranks from the top: Legend, 1, 2 … 25
  const ranks = [...g.ladder.ranks].reverse()
  return html`<${FormModal} title=${`${a.user} in ${g.name}`} onClose=${onClose} onSubmit=${submit}>
    ${g.ranked ? html`<div class="form-row">
      <label>Rank<select value=${v.rank} onChange=${(e) => { const rank = Number(e.target.value); const st = g.ladder.ranks.find((r) => r.rank === rank); setV({ ...v, rank, stars: Math.min(v.stars, st ? st.stars : 0) }) }}>
        ${g.ladder.legend && html`<option value="0">Legend</option>`}
        ${ranks.map((r) => html`<option value=${r.rank}>Rank ${r.rank}</option>`)}</select></label>
      <label>Stars<input type="number" min="0" max=${step ? step.stars : 0} disabled=${legend} value=${legend ? 0 : v.stars} onInput=${set('stars')} />
        <small>${legend ? 'Legend has no stars' : `0–${step ? step.stars : 0}`}</small></label>
      <label>Win streak<input type="number" min="0" max="1000" value=${v.streak} onInput=${set('streak')} /></label>
    </div>` : html`<p class="muted small">This game has no ranked ladder: only the MMRs (the matchmaking ratings).</p>`}
    <div class="form-row">
      <label>Ranked MMR<input type="number" min="0" max="10000" step="any" required value=${v.ranked_mmr} onInput=${set('ranked_mmr')} /><small>hidden; 1500 at the start</small></label>
      <label>Casual MMR<input type="number" min="0" max="10000" step="any" required value=${v.casual_mmr} onInput=${set('casual_mmr')} /><small>hidden; 1500 at the start</small></label>
    </div>
  </${FormModal}>`
}

// --- settings ----------------------------------------------------------------------------------------

function Settings ({ a, g, may, reload, setModal }) {
  const entries = Object.entries(g.settings)
  const edit = () => setModal(html`<${SettingsModal} a=${a} g=${g} onClose=${() => setModal(null)} reload=${reload} />`)
  return html`<${Card} title="Settings" actions=${may && html`<button class="btn sm" onClick=${edit}>Edit…</button>`}>
    ${entries.length ? html`<dl class="kv">${entries.map(([k, v]) => html`<dt class="mono">${k}</dt><dd>${v}</dd>`)}</dl>`
      : html`<p class="muted small">None: the game's own art and music sets</p>`}
  </${Card}>`
}

function SettingsModal ({ a, g, onClose, reload }) {
  const [rows, setRows] = useState(() => [...Object.entries(g.settings), ['', '']])
  const put = (i, j) => (e) => setRows(rows.map((r, n) => n === i ? (j ? [r[0], e.target.value] : [e.target.value, r[1]]) : r))
  const submit = () => {
    const now = Object.fromEntries(rows.filter(([k]) => k.trim()).map(([k, v]) => [k.trim(), v]))
    const changes = { ...Object.fromEntries(Object.keys(g.settings).map((k) => [k, null])), ...now }
    return change(a.id, 'game_settings', { pack: g.pack, settings: changes }, reload)
  }
  return html`<${FormModal} title=${`Settings of ${a.user} in ${g.name}`} onClose=${onClose} onSubmit=${submit}>
    <p class="muted small">What the game keeps for the player: <span class="mono">art</span> and <span class="mono">music</span> (the picture and music sets). A key is 1–32 of a–z 0–9 _, a value 64 characters at most, 16 keys.</p>
    ${rows.map(([k, v], i) => html`<div class="form-row kvrow" key=${i}>
      <input class="mono" placeholder="key" aria-label="Key" value=${k} onInput=${put(i, 0)} />
      <input placeholder="value" aria-label="Value" value=${v} maxlength="64" onInput=${put(i, 1)} />
      <button type="button" class="btn ghost sm icon-only" title="Remove" aria-label="Remove" onClick=${() => setRows(rows.filter((_, n) => n !== i))}><${Icon} name="x" size=${14} /></button>
    </div>`)}
    <button type="button" class="btn ghost sm" onClick=${() => setRows([...rows, ['', '']])}><${Icon} name="plus" size=${14} />Add a key</button>
  </${FormModal}>`
}

// --- decks -------------------------------------------------------------------------------------------

function Decks ({ a, g, may, reload, setModal }) {
  const [open, setOpen] = useState(null)
  const close = () => setModal(null)
  const add = () => setModal(html`<${DeckAddModal} a=${a} g=${g} onClose=${close} reload=${reload} />`)
  const rename = (d) => setModal(html`<${NameModal} a=${a} d=${d} onClose=${close} reload=${reload} />`)
  const copyTo = (d) => setModal(html`<${CopyToModal} a=${a} d=${d} onClose=${close} reload=${reload} />`)
  const del = (d) => ask(setModal, { title: `Delete the deck "${d.name || 'unnamed'}"?`, text: `${a.user} loses it on every device (it is kept on the server only).`, button: 'Delete', kind: 'danger' },
    () => change(a.id, `decks/${d.id}/delete`, {}, reload))
  return html`<${Card} title=${`Decks in ${g.name} (${g.decks.length})`} pad=${false}
    actions=${may && html`<button class="btn sm" onClick=${add}><${Icon} name="plus" size=${14} />Add from code</button>`}>
    ${g.decks.length ? html`<div class="table-wrap"><table class="table compact decks">
      <thead><tr><th>Deck</th><th>Class</th><th class="num">Cards</th><th>Changed</th><th></th></tr></thead>
      <tbody>${g.decks.map((d) => html`
        <tr key=${d.id} class="clickable" onClick=${() => setOpen(open === d.id ? null : d.id)} aria-expanded=${open === d.id}>
          <td><b>${d.name || html`<span class="muted">unnamed</span>`}</b></td>
          <td><span class=${'cls c-' + (d.class || '').toLowerCase()}>${d.class_name || d.class || d.hero}</span></td>
          <td class="num">${d.count}${!d.valid && html` <span class="badge warn" title=${d.problem}>${d.count < 30 ? 'unfinished' : 'not legal'}</span>`}</td>
          <td class="muted small nowrap" title=${fullDate(d.updated * 1000)}>${fullDate(d.updated * 1000)}</td>
          <td class="row-actions" onClick=${(e) => e.stopPropagation()}>
            <${CopyCode} code=${d.code} />
            <button class="btn ghost sm" onClick=${() => setOpen(open === d.id ? null : d.id)}>${open === d.id ? 'Hide' : 'View'}</button>
            ${may && html`<button class="btn ghost sm" onClick=${() => rename(d)}>Rename</button>
              <button class="btn ghost sm" onClick=${() => copyTo(d)}>Copy to…</button>
              <button class="btn ghost sm danger-text" onClick=${() => del(d)}>Delete</button>`}
          </td>
        </tr>
        ${open === d.id && html`<tr class="details"><td colspan="5"><${DeckList} d=${d} /></td></tr>`}`)}</tbody>
    </table></div>` : html`<${Empty}>No decks in this game on the server${may ? ': add one from a deck code' : ''}</${Empty}>`}
  </${Card}>`
}

function DeckAddModal ({ a, g, onClose, reload }) {
  const [v, setV] = useState({ code: '', name: '' })
  return html`<${FormModal} title=${`A deck for ${a.user} in ${g.name}`} button="Add the deck" onClose=${onClose}
    onSubmit=${() => change(a.id, 'decks', { pack: g.pack, ...v }, reload)}>
    <label>Deck code<textarea class="mono" rows="4" required value=${v.code} onInput=${(e) => setV({ ...v, code: e.target.value })} autofocus
      placeholder="AAEDAf0E…" /><small>From the game's Export Code, a "Copy code" here, or Hearthstone (its copied text too, "### Name" included). Checked with ${g.name}'s rules: a complete, legal deck.</small></label>
    <label>Name<input maxlength="60" value=${v.name} onInput=${(e) => setV({ ...v, name: e.target.value })} />
      <small>Optional. Empty: the "### Name" of the text, else "Imported deck"</small></label>
  </${FormModal}>`
}

function NameModal ({ a, d, onClose, reload }) {
  const [name, setName] = useState(d.name)
  return html`<${FormModal} title="Rename the deck" onClose=${onClose} onSubmit=${() => change(a.id, `decks/${d.id}/rename`, { name }, reload)}>
    <label>Name<input maxlength="60" value=${name} onInput=${(e) => setName(e.target.value)} autofocus /><small>0–60 characters</small></label>
  </${FormModal}>`
}

function CopyToModal ({ a, d, onClose, reload }) {
  const [to, setTo] = useState('')
  return html`<${FormModal} title=${`Copy "${d.name || 'unnamed'}" to another account`} button="Copy" onClose=${onClose}
    onSubmit=${() => change(a.id, `decks/${d.id}/copy`, { to }, reload)}>
    <label>Account<input required value=${to} onInput=${(e) => setTo(e.target.value)} autofocus placeholder="name" />
      <small>The same game; ${a.user} keeps the deck.</small></label>
  </${FormModal}>`
}
