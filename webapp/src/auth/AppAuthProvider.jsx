import { Auth0Provider } from '@auth0/auth0-react'
import { auth0Domain, auth0ClientId, auth0Audience, isAuth0Configured } from './authConfig.js'

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
      {children}
    </Auth0Provider>
  )
}
