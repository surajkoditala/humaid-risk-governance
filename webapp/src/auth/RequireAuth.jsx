import { useEffect, useState } from 'react'
import { useAuth0 } from '@auth0/auth0-react'
import { isAuth0Configured } from './authConfig.js'

function CenteredNotice({ children }) {
  return <div className="flex h-svh items-center justify-center p-6">{children}</div>
}

// Fresh checkout with no Auth0 tenant wired up yet: explain how to configure it and require an
// explicit opt-in to continue, instead of silently letting everyone in.
function SetupNotice({ onBypass }) {
  return (
    <CenteredNotice>
      <div className="w-full max-w-lg space-y-4 rounded-lg border border-amber-300 bg-amber-50 p-6 text-sm text-amber-900">
        <p className="font-semibold">Auth0 is not configured</p>
        <p>
          Copy <code>webapp/.env.example</code> to <code>webapp/.env.local</code>, set
          VITE_AUTH0_DOMAIN and VITE_AUTH0_CLIENT_ID from your Auth0 application, and restart the
          dev server.
        </p>
        <button
          type="button"
          onClick={onBypass}
          className="rounded-md border border-amber-400 px-4 py-2 font-medium hover:bg-amber-100"
        >
          Continue without signing in (local dev only)
        </button>
      </div>
    </CenteredNotice>
  )
}

// Only rendered when Auth0 IS configured - sends anonymous visitors to Auth0 Universal Login.
function Auth0Gate({ children }) {
  const { isAuthenticated, isLoading, error, loginWithRedirect } = useAuth0()

  useEffect(() => {
    if (!isLoading && !error && !isAuthenticated) {
      loginWithRedirect({ appState: { returnTo: window.location.pathname } })
    }
  }, [isLoading, isAuthenticated, error, loginWithRedirect])

  if (error) {
    return (
      <CenteredNotice>
        <div className="w-full max-w-lg rounded-lg border border-red-300 bg-red-50 p-6 text-sm text-red-900">
          <p className="font-semibold">Sign-in failed</p>
          <p>{error.message}</p>
        </div>
      </CenteredNotice>
    )
  }

  if (!isAuthenticated) {
    return (
      <CenteredNotice>
        <span className="text-muted-foreground">
          {isLoading ? 'Checking your session…' : 'Redirecting to sign-in…'}
        </span>
      </CenteredNotice>
    )
  }

  return children
}

export default function RequireAuth({ children }) {
  const [devBypass, setDevBypass] = useState(false)

  if (!isAuth0Configured) {
    return devBypass ? children : <SetupNotice onBypass={() => setDevBypass(true)} />
  }
  return <Auth0Gate>{children}</Auth0Gate>
}
