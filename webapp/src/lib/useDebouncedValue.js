import { useEffect, useState } from 'react'

// Delays propagating a fast-changing value (e.g. a search box) so a grid doesn't refetch on
// every keystroke.
export function useDebouncedValue(value, delayMs = 300) {
  const [debounced, setDebounced] = useState(value)

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delayMs)
    return () => clearTimeout(timer)
  }, [value, delayMs])

  return debounced
}
