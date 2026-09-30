// Shared across Intake and the list grids so change-type/status option lists stay in one place.
export const CHANGE_TYPES = ['Product', 'Feature', 'Process', 'Vendor', 'Geography', 'CustomerSegment']

// Mirrors change_request.status's CHECK constraint (schema/004_change_requests.sql).
export const CHANGE_REQUEST_STATUSES = ['Submitted', 'InAssessment', 'PendingCommittee', 'Decisioned']
