// Bots: the server's own players of Classic — how many, how strong, which games, when; what each
// one does now, the game as it sees it, its last decision and its log. Polled every 2 s.

import { useState, useEffect } from 'preact/hooks'
import { api } from './api.js'
import { html, useLoad, useTick, toast, Card, ErrorBox, Empty, Icon, Modal, num, dur } from './ui.js'
import { Confirm } from './accounts.js'

const LEVEL = { easy: 'Easy', medium: 'Medium', hard: 'Hard' }
const LEVEL_TIP = {
  easy: 'One guess of the hidden cards, looks one action ahead, errs now and then (30%)',
  medium: '2–3 guesses of the hidden cards, plays its turn on, ignores the reply',
  hard: 'Up to 24 guesses within a second, plays its turn on and the opponent\'s whole reply'
}
const MODES = { ladder: 'Ranked + casual', ranked: 'Ranked', casual: 'Casual', arena: 'Arena' }

const hm = (m) => String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0')
const window_ = (b) => b.from === b.to ? 'all day' : `${hm(b.from)}–${hm(b.to)} UTC`
const toMin = (t) => { const [h, m] = (t || '0:0').split(':').map(Number); return (h || 0) * 60 + (m || 0) }
const pct = (w, g) => g ? Math.round(100 * w / g) + '%' : '—'
const secs = (t) => Math.max(0, Math.floor(Date.now() / 1000) - t)

function Switch ({ on, onChange, label, busy }) {
  return html`<button role="switch" aria-checked=${on} aria-label=${label} title=${label} disabled=${busy}
    class=${'switch' + (on ? ' on' : '')} onClick=${(e) => { e.stopPropagation(); onChange(!on) }}><i></i></button>`
}

/** The settings form: for new bots (with a count) and for one bot. */
function BotForm ({ bot, onClose, onSave }) {
  const [f, setF] = useState(() => bot
    ? { level: bot.level, modes: bot.modes, allDay: bot.from === bot.to, from: hm(bot.from), to: hm(bot.to), pmin: bot.pause_min, pmax: bot.pause_max }
    : { count: 3, level: 'medium', modes: 'ladder', allDay: true, from: '08:00', to: '23:00', pmin: 5, pmax: 15 })
  const set = (k) => (e) => setF((x) => ({ ...x, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value }))
  const submit = (e) => {
    e.preventDefault()
    const body = { level: f.level, modes: f.modes, from: f.allDay ? 0 : toMin(f.from), to: f.allDay ? 0 : toMin(f.to), pause_min: +f.pmin, pause_max: +f.pmax }
    if (!bot) body.count = +f.count
    onSave(body)
  }
  return html`<${Modal} title=${bot ? 'Settings of ' + bot.name : 'Add bots'} onClose=${onClose}>
    <form class="form" onSubmit=${submit}>
      ${!bot && html`<label>How many<input type="number" min="1" max="50" required value=${f.count} onInput=${set('count')} autofocus />
        <small>Each gets an account Bot_&lt;Level&gt;_&lt;n&gt; (a password nobody knows) and plays Classic only.</small></label>`}
      <label>Strength<select value=${f.level} onChange=${set('level')}>
        ${Object.entries(LEVEL).map(([k, v]) => html`<option value=${k}>${v}</option>`)}</select>
        <small>${LEVEL_TIP[f.level]}. Every level sees only its own player's view.</small></label>
      <label>Games<select value=${f.modes} onChange=${set('modes')}>
        ${Object.entries(MODES).map(([k, v]) => html`<option value=${k}>${v}</option>`)}</select>
        <small>${f.modes === 'arena' ? 'Drafts a deck, plays the run to its end, starts a new one.' : f.modes === 'ladder' ? 'Ranked and casual in turn; a random deck of the library each game.' : 'A random deck of the library each game.'}</small></label>
      <label class="row-label"><span><input type="checkbox" checked=${f.allDay} onChange=${set('allDay')} /> Plays all day</span></label>
      ${!f.allDay && html`<div class="grid two"><label>From (UTC)<input type="time" value=${f.from} onInput=${set('from')} /></label>
        <label>To (UTC)<input type="time" value=${f.to} onInput=${set('to')} /></label></div>`}
      <div class="grid two"><label>Pause before a game, from (s)<input type="number" min="0" max="3600" value=${f.pmin} onInput=${set('pmin')} /></label>
        <label>to (s)<input type="number" min="0" max="3600" value=${f.pmax} onInput=${set('pmax')} /></label></div>
      <div class="form-actions"><button type="button" class="btn ghost" onClick=${onClose}>Cancel</button><button class="btn primary">${bot ? 'Save' : 'Add'}</button></div>
    </form>
  </${Modal}>`
}

function Side ({ s, own }) {
  if (!s) return null
  return html`<div class="bot-side">
    <div><b>${own ? 'Bot' : 'Opponent'}:</b> ${s.hero} · ❤ ${s.hp}${s.armor ? ' · 🛡 ' + s.armor : ''} · mana ${s.mana}/${s.max_mana} · deck ${s.deck}${s.secrets ? ' · secrets ' + s.secrets : ''}${s.weapon ? ` · ⚔ ${s.weapon.name} ${s.weapon.atk}/${s.weapon.dur}` : ''}</div>
    <div class="chips">${s.board.length ? s.board.map((m) => html`<span class=${'chip' + (m.tags.includes('taunt') ? ' taunt' : '')}>${m.name} <b>${m.atk}/${m.hp}</b>${m.tags.length ? ' · ' + m.tags.join(', ') : ''}</span>`) : html`<span class="muted">empty board</span>`}</div>
    <div class="muted">hand: ${Array.isArray(s.hand) ? s.hand.map((h) => html`<span class="chip"><b>${h.cost}</b> ${h.name}</span>`) : s.hand + ' cards (hidden)'}</div>
  </div>`
}

/** One bot: its game as it sees it, its last decision, its log; polled while open. */
function BotPage ({ id, onClose }) {
  const [b, error, reload] = useLoad(() => api('bots/' + id), [id])
  useEffect(() => { const t = setInterval(reload, 1500); return () => clearInterval(t) }, [reload])
  if (!b) return html`<${Modal} title="Bot" onClose=${onClose} wide><${ErrorBox} error=${error} /></${Modal}>`
  const s = b.status
  return html`<${Modal} title=${b.name + ' · ' + LEVEL[b.level] + ' · ' + MODES[b.modes]} onClose=${onClose} wide>
    <div class="bot-page">
      <p><b>${s.state || '—'}</b> <span class="muted">for ${dur(secs(s.since))}</span>${s.opponent && html` · against <b>${s.opponent}</b>`}</p>
      ${s.game && s.board && html`<div class="bot-board"><div class="muted">Game ${s.game}, turn ${s.turn}${s.my_turn ? ' — the bot\'s move' : ''}</div>
        <${Side} s=${s.board.opp} /><${Side} s=${s.board.me} own /></div>`}
      ${s.decision && s.decision.action && html`<div class="bot-decision"><b>Last decision:</b> ${s.decision.action} <span class="muted">(${s.decision.worlds} guesses of the hidden cards, ${s.decision.ms} ms)</span>
        ${s.decision.top && s.decision.top.length ? html`<ol>${s.decision.top.map((t) => html`<li>${t.label} <span class="muted">${t.score}</span></li>`)}</ol>` : ''}</div>`}
      <h3>Log</h3>
      <pre class="bot-log">${s.log.map((l) => new Date(l.at * 1000).toLocaleTimeString() + '  ' + l.text).join('\n') || 'nothing yet'}</pre>
    </div>
  </${Modal}>`
}

export function Bots () {
  const [data, error, reload] = useLoad(() => api('bots'), [])
  useEffect(() => { const t = setInterval(reload, 2000); return () => clearInterval(t) }, [reload])
  useTick(1000)
  const [modal, setModal] = useState(null) // 'add' | {edit} | {del} | {open}
  const [busy, setBusy] = useState(null)
  const act = async (b, action, body) => {
    setBusy(b.id)
    try { const r = await api(`bots/${b.id}/${action}`, { method: 'POST', body }); toast(r.text); reload() } catch (err) { toast(err.message, 'err') }
    setBusy(null)
  }
  const all = async (action) => {
    try { const r = await api('bots/all/' + action, { method: 'POST' }); toast(r.text); reload() } catch (err) { toast(err.message, 'err') }
  }
  const add = async (body) => {
    setModal(null)
    try { const r = await api('bots', { method: 'POST', body }); toast(r.text); reload() } catch (err) { toast(err.message, 'err') }
  }
  const sm = data && data.summary
  return html`<div class="page">
    <header class="page-head"><h1>Bots</h1><span class="muted">The server's own players of Classic: they play through the same protocol as people and see only their own player's view · ${data ? data.decks + ' decks · thinking at once: ' + data.thinkers : ''}</span></header>
    <${ErrorBox} error=${error} onRetry=${reload} />
    <${Card} title="Bots" actions=${html`
      <button class="btn ghost sm" onClick=${() => all('start')}><${Icon} name="play" size=${14} /> Start all</button>
      <button class="btn ghost sm" onClick=${() => all('stop')}><${Icon} name="pause" size=${14} /> Stop all</button>
      <button class="btn primary sm" onClick=${() => setModal('add')}><${Icon} name="plus" size=${14} /> Add bots</button>`} pad=${false}>
      ${sm && html`<div class="chips bot-sum">
        <span class="chip">${sm.total} bots</span><span class="chip">${sm.enabled} on</span><span class="chip">${sm.online} online</span>
        <span class="chip">${sm.playing} in a game</span><span class="chip">${num(sm.games)} games · ${pct(sm.wins, sm.games)} won</span>
        <span class=${'chip' + (sm.errors ? ' bad' : '')}>${sm.errors} errors</span></div>`}
      ${data && !data.bots.length ? html`<${Empty}>No bots yet: add some.</${Empty}>` : data && html`<div class="table-wrap"><table class="table">
        <thead><tr><th></th><th>Bot</th><th>Strength</th><th>Games</th><th>When</th><th>Now</th><th class="num">Played</th><th class="num">Won</th><th>Ladder / Arena</th><th class="num">Errors</th><th></th></tr></thead>
        <tbody>${data.bots.map((b) => {
          const s = b.status
          const stale = s.game && secs(s.since) > 600
          return html`<tr key=${b.id} class="clickable" onClick=${() => setModal({ open: b.id })}>
            <td><${Switch} on=${b.enabled} label=${b.enabled ? 'Stop' : 'Start'} busy=${busy === b.id} onChange=${(on) => act(b, on ? 'start' : 'stop')} /></td>
            <td class="nowrap"><span class=${'dot' + (s.online ? ' on' : '')}></span> <b>${b.name}</b></td>
            <td title=${LEVEL_TIP[b.level]}>${LEVEL[b.level]}</td>
            <td>${MODES[b.modes]}</td>
            <td class="muted">${window_(b)} · ${b.pause_min}–${b.pause_max} s</td>
            <td class=${stale ? 'bad' : ''}>${s.state || '—'} <span class="muted">${dur(secs(s.since))}</span>${stale ? ' (no change for 10 min)' : ''}</td>
            <td class="num">${num(s.games)}</td>
            <td class="num">${pct(s.wins, s.games)}</td>
            <td class="muted">${b.modes === 'arena' ? `${s.arena_runs} runs · best ${s.arena_best}${s.arena_now && s.arena_now.hero ? ` · now ${s.arena_now.hero} ${s.arena_now.wins}–${s.arena_now.losses}` : ''}` : `ranked ${s.ranked} · casual ${s.casual}${s.rank && s.rank.rank !== undefined ? ' · ' + (s.rank.rank === 0 ? 'Legend' : 'rank ' + s.rank.rank) : ''}`}</td>
            <td class=${'num' + (s.errors ? ' bad' : '')} title=${s.last_error || ''}>${s.errors}</td>
            <td class="actions" onClick=${(e) => e.stopPropagation()}>
              <button class="btn ghost sm" onClick=${() => setModal({ edit: b })}>Settings</button>
              <button class="btn ghost sm icon-only" title="Delete" onClick=${() => setModal({ del: b })}><${Icon} name="trash" size=${15} /></button></td>
          </tr>`
        })}</tbody></table></div>`}
    </${Card}>
    ${modal === 'add' && html`<${BotForm} onClose=${() => setModal(null)} onSave=${add} />`}
    ${modal && modal.edit && html`<${BotForm} bot=${modal.edit} onClose=${() => setModal(null)} onSave=${(body) => { const b = modal.edit; setModal(null); act(b, 'update', body) }} />`}
    ${modal && modal.del && html`<${Confirm} title=${'Delete ' + modal.del.name + '?'} text="The bot stops at once (a game it is in is lost). Its account stays, with its games and ranks." button="Delete" kind="danger"
      onClose=${() => setModal(null)} onYes=${() => { const b = modal.del; setModal(null); act(b, 'delete') }} />`}
    ${modal && modal.open && html`<${BotPage} id=${modal.open} onClose=${() => setModal(null)} />`}
  </div>`
}
