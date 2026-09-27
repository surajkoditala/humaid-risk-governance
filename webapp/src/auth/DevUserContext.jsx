import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { Endpoints, apiFetch } from '../lib/api.js'
import { setDevUserId } from './devUserId.js'

// Simulates "who's logged in" while Auth0 isn't configured (see RequireAuth.jsx's dev bypass and
// DevBypassAuthHandler.cs on the backend). Every screen reads the acting user's id/role from here
// instead of a real JWT claim - the extension point already called out in ChangeRequestController.cs.
// lib/api.js's devUserId.js mirror is what actually gets the id to the backend (X-Dev-User-Id), so
// every change here is followed by a matching setDevUserId call - never let the two drift apart, or
// a request goes out "acting as" someone the screen isn't showing.
const DevUserContext = createContext(null)

const STORAGE_KEY = 'devUserId'

export function DevUserProvider({ children }) {
  const [users, setUsers] = useState([])
  const [userId, setUserId] = useState(() => {
    const stored = localStorage.getItem(STORAGE_KEY) || null
    setDevUserId(stored)
    return stored
  })
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    apiFetch(Endpoints.users.all())
      .then((fetched) => {
        setUsers(fetched || [])
        if (!userId && fetched?.length) {
          setUserId(fetched[0].id)
          setDevUserId(fetched[0].id)
        }
      })
      .catch(() => setUsers([]))
      .finally(() => setLoading(false))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const currentUser = useMemo(() => users.find((u) => u.id === userId) || null, [users, userId])

  const selectUser = (id) => {
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
