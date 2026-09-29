import { useLayoutEffect, useRef, useState } from 'react'

// Free-text titles (analyst-typed, or AI/QA-generated) can run to dozens of lines - clamp to 4
// with a click-to-expand toggle instead of letting one row blow out the whole table's height.
export default function ClampedText({ text }) {
  const ref = useRef(null)
  const [expanded, setExpanded] = useState(false)
  const [clamped, setClamped] = useState(false)

  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    setClamped(el.scrollHeight > el.clientHeight + 1)
  }, [text])

  return (
    <div>
      <p
        ref={ref}
        className={expanded ? 'whitespace-normal break-words' : 'line-clamp-4 whitespace-normal break-words'}
        title={expanded ? undefined : text}
      >
        {text}
      </p>
      {(clamped || expanded) && (
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          className="mt-0.5 text-xs font-medium text-primary hover:underline"
        >
          {expanded ? 'View less' : 'View more'}
        </button>
      )}
    </div>
  )
}
