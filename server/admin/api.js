// JSON calls to /admin/api with the CSRF header on everything but GET.

/** The sub-server's path prefix: the panel at `/s/<name>/admin` talks to `/s/<name>/admin/…`, the main one at
 * `/admin` to `/admin/…` (the static files are the same everywhere: index.html loads them from /admin/static). */
export const PREFIX = location.pathname.replace(/\/admin\/?$/, '')
export const BASE = PREFIX + '/admin'

let csrf = ''
let unauthorized = () => {}

export const setCsrf = (t) => { csrf = t || '' }
export const onUnauthorized = (fn) => { unauthorized = fn }

export class ApiError extends Error {
  constructor (status, message) { super(message); this.status = status }
}

export async function api (path, { method = 'GET', body } = {}) {
  const opt = { method, headers: {}, credentials: 'same-origin' }
  if (method !== 'GET') {
    opt.headers['content-type'] = 'application/json'
    opt.headers['x-csrf-token'] = csrf
    opt.body = JSON.stringify(body ?? {})
  }
  const r = await fetch(BASE + '/api/' + path, opt)
  let data = null
  try { data = await r.json() } catch (e) { /* not JSON */ }
  if (r.status === 401 && path !== 'login') unauthorized()
  if (!r.ok) throw new ApiError(r.status, (data && data.error) || r.statusText || 'Request failed')
  return data
}

/** Uploads a file as the raw request body (with the CSRF header); onProgress gets 0..1. With an id, the
 * server tells this upload's stages on the live feed (`pack_stage` with `upload` = the id). */
export function upload (path, file, onProgress = () => {}, id = '') {
  return new Promise((resolve, reject) => {
    const x = new XMLHttpRequest()
    x.open('POST', BASE + '/api/' + path)
    x.setRequestHeader('x-csrf-token', csrf)
    x.setRequestHeader('content-type', 'application/zip')
    if (id) x.setRequestHeader('x-upload-id', id)
    x.upload.onprogress = (e) => { if (e.lengthComputable) onProgress(e.loaded / e.total) }
    x.onload = () => {
      let data = null
      try { data = JSON.parse(x.responseText) } catch (e) { /* not JSON */ }
      if (x.status === 401) unauthorized()
      if (x.status >= 200 && x.status < 300) resolve(data)
      else reject(new ApiError(x.status, (data && data.error) || x.statusText || 'Upload failed'))
    }
    x.onerror = () => reject(new ApiError(0, 'The upload failed: network error'))
    x.send(file)
  })
}

/** A query string from an object, without empty values. */
export const qs = (o) => new URLSearchParams(Object.entries(o).filter(([, v]) => v !== '' && v != null && v !== false)).toString()
