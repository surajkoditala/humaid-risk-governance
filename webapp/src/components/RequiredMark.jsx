// A plain asterisk next to a Label for a required field - no required/optional convention existed
// anywhere in the app before this, so every form left the analyst guessing which fields actually
// block submission. Used next to the Label text itself; free-text inputs with only a placeholder
// (no separate Label) mark the placeholder string instead, e.g. "Reason *".
export function RequiredMark() {
  return (
    <span className="text-destructive" aria-hidden="true">
      {' '}
      *
    </span>
  )
}
