import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { isAuth0Configured } from './authConfig.js'
import { setDevUserId } from './devUserId.js'
import { Endpoints, apiFetch } from '../lib/api.js'

// Two identity sources behind one hook, so no screen needs to know or care which is active:
// - No Auth0 tenant: simulates "who's logged in" via the "acting as" switcher (see RequireAuth.jsx's
//   dev bypass and DevBypassAuthHandler.cs on the backend) - the extension point already called out
//   in ChangeRequestController.cs. lib/api.js's devUserId.js mirror is what actually gets the
//   selection to the backend (X-Dev-User-Id), so every change here is followed by a matching
//   setDevUserId call - never let the two drift apart, or a request goes out "acting as" someone
//   the screen isn't showing.
// - Real Auth0 tenant: there is no switcher - GET /api/User/Me resolves the actual logged-in
//   person's role from their app_user row (UserController.cs), and `users` is just that one person
//   (DevUserSwitcher in App.jsx renders it as a read-only "who you are" display, not a picker).
const DevUserContext = createContext(null)

const STORAGE_KEY = 'devUserId'

export function DevUserProvider({ children }) {
  const [users, setUsers] = useState([])
  const [userId, setUserId] = useState(() => {
    if (isAuth0Configured) return null // resolved from /api/User/Me below, not localStorage
    const stored = localStorage.getItem(STORAGE_KEY) || null
    setDevUserId(stored)
    return stored
  })
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const request = isAuth0Configured
      ? apiFetch(Endpoints.users.me()).then((me) => (me ? [me] : []))
      : apiFetch(Endpoints.users.all())

    request
      .then((fetched) => {
        setUsers(fetched || [])
        if (!userId && fetched?.length) {
          setUserId(fetched[0].id)
          if (!isAuth0Configured) setDevUserId(fetched[0].id)
        }
      })
      // Real Auth0, no active app_user row yet (login not provisioned - see auth0-setup.md step 4):
      // stays signed in with no role, same as the backend's own "authenticated but no role" case.
      .catch(() => setUsers([]))
      .finally(() => setLoading(false))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const currentUser = useMemo(() => users.find((u) => u.id === userId) || null, [users, userId])

  const selectUser = (id) => {
    if (isAuth0Configured) return // nothing to switch to - identity comes from the real login
    setUserId(id)
    setDevUserId(id)
    localStorage.setItem(STORAGE_KEY, id)
  }

  return (
    <DevUserContext.Provider value={{ users, currentUser, selectUser, loading }}>
      {children}
    </DevUserContext.Provider>
  )
}

export function useDevUser() {
  const ctx = useContext(DevUserContext)
  if (!ctx) throw new Error('useDevUser must be used within a DevUserProvider')
  return ctx
}
