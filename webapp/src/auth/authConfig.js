// Auth0 SPA configuration.
//
// Resolved once at startup by loadAuthConfig() (called from main.jsx before anything renders):
//   1. Runtime: the API's /config.json, which serves its own AUTH0_DOMAIN / AUTH0_CLIENT_ID /
//      AUTH0_AUDIENCE container env vars. This is what makes one image work in any environment -
//      Vite inlines import.meta.env.VITE_* at build time, so a deployed container's env vars could
//      never reach them.
//   2. Build-time fallback: VITE_AUTH0_* (copy .env.example to .env.local) - local dev, or any
//      setup where the API isn't serving /config.json.
// A non-empty runtime value wins; an empty one falls back to the build-time value.
//
// These are `let` exports on purpose: ES module live bindings mean every importer sees the
// resolved values once loadAuthConfig() has run, and every consumer reads them at render/call time,
// never at import time.
import { API_BASE_URL } from '../lib/apiBase.js'

export let auth0Domain = import.meta.env.VITE_AUTH0_DOMAIN || ''
export let auth0ClientId = import.meta.env.VITE_AUTH0_CLIENT_ID || ''
export let auth0Audience = import.meta.env.VITE_AUTH0_AUDIENCE || ''

export let isAuth0Configured = Boolean(auth0Domain && auth0ClientId)

const CONFIG_TIMEOUT_MS = 5000

export async function loadAuthConfig() {
  try {
    const response = await fetch(`${API_BASE_URL}/config.json`, {
      cache: 'no-store',
      signal: AbortSignal.timeout(CONFIG_TIMEOUT_MS),
    })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    // A dev server answers unknown paths with index.html (200), so check it really is JSON.
    if (!(response.headers.get('content-type') ?? '').includes('json')) {
      throw new Error('response was not JSON')
    }
    const runtime = await response.json()
    auth0Domain = runtime.auth0Domain || auth0Domain
    auth0ClientId = runtime.auth0ClientId || auth0ClientId
    auth0Audience = runtime.auth0Audience || auth0Audience
    isAuth0Configured = Boolean(auth0Domain && auth0ClientId)
  } catch (error) {
    console.warn('Could not load runtime config from /config.json; using build-time VITE_AUTH0_* values.', error)
  }
}
