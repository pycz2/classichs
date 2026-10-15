// JSON calls to /admin/api with the CSRF header on everything but GET.

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
  const r = await fetch('/admin/api/' + path, opt)
  let data = null
  try { data = await r.json() } catch (e) { /* not JSON */ }
  if (r.status === 401 && path !== 'login') unauthorized()
  if (!r.ok) throw new ApiError(r.status, (data && data.error) || r.statusText || 'Request failed')
  return data
}

/** Uploads a file as the raw request body (with the CSRF header); onProgress gets 0..1. */
export function upload (path, file, onProgress = () => {}) {
  return new Promise((resolve, reject) => {
    const x = new XMLHttpRequest()
    x.open('POST', '/admin/api/' + path)
    x.setRequestHeader('x-csrf-token', csrf)
    x.setRequestHeader('content-type', 'application/zip')
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
