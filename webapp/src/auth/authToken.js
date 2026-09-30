// Epic 11: mirrors devUserId.js's pattern, but for real Auth0 login. AuthTokenBridge (rendered
// inside AppAuthProvider.jsx, below <Auth0Provider>) pushes the live getAccessTokenSilently
// reference here on every render; lib/api.js calls it fresh on every request rather than caching
// a token string itself - the Auth0 SDK's own getAccessTokenSilently already caches/refreshes
// internally and knows when a token is stale, so caching it a second time here would risk sending
// an expired one.
let getTokenSilently = null

export function setAccessTokenGetter(fn) {
  getTokenSilently = fn
}

export async function getAuthHeader() {
  if (!getTokenSilently) return {}
  try {
    const token = await getTokenSilently()
    return token ? { Authorization: `Bearer ${token}` } : {}
  } catch (err) {
    // Silent-refresh failed (expired session, revoked consent, etc.) - let the request go out
    // without a token and 401/403 normally. RequireAuth's own Auth0Gate is what re-authenticates;
    // a fetch helper mid-request is the wrong place to trigger that redirect. Logged (not thrown) so
    // the actual Auth0 SDK error (e.g. "login_required", "consent_required", "missing_refresh_token")
    // is visible instead of silently showing up as an unexplained 401 downstream.
    console.warn('Auth0 getAccessTokenSilently() failed; request will go out without a token:', err)
    return {}
  }
}
