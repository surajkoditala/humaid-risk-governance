import { useState } from 'react'

/**
 * Shared paging/sorting/filtering state for a server-side grid (Assessments inbox, My Requests,
 * Committee Queue) - grid standard raised on the 2026-09-29 sync-up call. The page component only
 * needs to turn `query` into the request URL (see Endpoints.*) and pass the setters to its
 * filter/sort/pagination controls; any filter or sort change resets back to page 1.
 */
export function useGridQuery({ pageSize = 10, sortBy = null, sortDir = 'desc' } = {}) {
  const [query, setQuery] = useState({
    page: 1,
    pageSize,
    sortBy,
    sortDir,
    status: '',
    changeType: '',
    search: '',
  })

  const toggleSort = (column) =>
    setQuery((q) =>
      q.sortBy === column
        ? { ...q, sortDir: q.sortDir === 'asc' ? 'desc' : 'asc', page: 1 }
        : { ...q, sortBy: column, sortDir: 'asc', page: 1 },
    )

  const setFilter = (key, value) => setQuery((q) => ({ ...q, [key]: value, page: 1 }))

  const setPage = (page) => setQuery((q) => ({ ...q, page }))

  return { query, toggleSort, setFilter, setPage }
}
