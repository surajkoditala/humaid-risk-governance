// Shared wording for the service-level (SLA) screens. Plain language on purpose - the underlying
// states (OnTrack / AtRisk / Breached) and stage names are internal.

export const SLA_STATE_LABEL = {
  OnTrack: 'On track',
  AtRisk: 'At risk',
  Breached: 'Overdue',
  Met: 'Met target',
  Missed: 'Missed target',
}

// What each stage means to the people looking at it.
export const SLA_STAGE_LABEL = {
  Submitted: 'Waiting for an analyst',
  InAssessment: 'With the analyst',
  PendingCommittee: 'With the committee',
  EndToEnd: 'Overall (start to decision)',
}

// The four stage columns, in workflow order.
export const SLA_STAGES = ['Submitted', 'InAssessment', 'PendingCommittee', 'EndToEnd']

// The 15-20 business-day cycle the platform was brought in to shorten (from the brief).
export const BASELINE_DAYS = { min: 15, max: 20 }

export function formatDate(value) {
  if (!value) return '—'
  return new Date(value).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })
}
