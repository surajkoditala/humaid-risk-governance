import { useAuth0, Auth0Provider } from '@auth0/auth0-react'
import { auth0Domain, auth0ClientId, auth0Audience, isAuth0Configured } from './authConfig.js'
import { setAccessTokenGetter } from './authToken.js'

// Epic 11: pushes the live getAccessTokenSilently reference into authToken.js on every render, so
// lib/api.js can attach a real Bearer token to every request. Set directly in the render body, not
// a useEffect - it's a plain module-variable assignment (no state, no re-render), and doing it here
// guarantees it's set before any descendant's effects run, including DevUserContext's first fetch.
function AuthTokenBridge() {
  const { getAccessTokenSilently } = useAuth0()
  setAccessTokenGetter(getAccessTokenSilently)
  return null
}

// Wraps the app in the Auth0 context. No-op (renders children directly) until Auth0 is configured.
export default function AppAuthProvider({ children }) {
  if (!isAuth0Configured) return children

  return (
    <Auth0Provider
      domain={auth0Domain}
      clientId={auth0ClientId}
      cacheLocation="localstorage"
      useRefreshTokens
      authorizationParams={{
        redirect_uri: window.location.origin,
        ...(auth0Audience ? { audience: auth0Audience } : {}),
      }}
      onRedirectCallback={(appState) => {
        window.history.replaceState({}, document.title, appState?.returnTo || window.location.pathname)
      }}
    >
      <AuthTokenBridge />
      {children}
    </Auth0Provider>
  )
}
