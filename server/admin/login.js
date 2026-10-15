// The login screen (admins and the superuser only).

import { useState } from 'preact/hooks'
import { api } from './api.js'
import { html } from './ui.js'

export function Login ({ onIn }) {
  const [user, setUser] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const submit = async (e) => {
    e.preventDefault()
    setBusy(true)
    setError('')
    try {
      onIn(await api('login', { method: 'POST', body: { user, password } }))
    } catch (err) {
      setError(err.message)
      setBusy(false)
    }
  }
  return html`<div class="login-wrap">
    <form class="login card" onSubmit=${submit}>
      <div class="brand big"><span class="logo">◆</span><span><b>Classic HS</b><small>server admin</small></span></div>
      <label>Name<input name="user" autocomplete="username" required maxlength="20" value=${user} onInput=${(e) => setUser(e.target.value)} autofocus /></label>
      <label>Password<input name="password" type="password" autocomplete="current-password" required maxlength="128" value=${password} onInput=${(e) => setPassword(e.target.value)} /></label>
      ${error && html`<div class="error-box">${error}</div>`}
      <button class="btn primary wide" disabled=${busy}>${busy ? 'Logging in…' : 'Log in'}</button>
      <p class="muted small">The browser stays logged in for 30 days of use. Make the superuser with <code>${'classichs-server admin <name>'}</code>.</p>
    </form>
  </div>`
}
