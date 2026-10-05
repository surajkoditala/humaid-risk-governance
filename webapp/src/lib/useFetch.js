import { useCallback, useEffect, useState } from 'react'
import { apiFetch } from './api.js'

/**
 * Small GET-fetching hook: loading/error/data plus a refetch() for after a mutation. `url` may be
 * null to skip fetching (e.g. waiting on a dependency like the current user) - deliberately one
 * shared hook rather than one hook per resource.
 */
export function useFetch(url, deps = []) {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(Boolean(url))
  const [error, setError] = useState(null)

  const refetch = useCallback(async () => {
    if (!url) return
    setLoading(true)
    setError(null)
    try {
      setData(await apiFetch(url))
    } catch (err) {
      setError(err.message || String(err))
    } finally {
      setLoading(false)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [url])

  useEffect(() => {
    refetch()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [url, ...deps])

  return { data, loading, error, refetch }
}
