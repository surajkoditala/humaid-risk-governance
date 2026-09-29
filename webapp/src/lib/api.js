import { isAuth0Configured } from '../auth/authConfig.js'
import { getAuthHeader } from '../auth/authToken.js'
import { getDevUserId } from '../auth/devUserId.js'

// This webapp's own backend (Humaid.RiskGovernance.AdminUI.Web). Empty string (the production
// default) means same-origin - deliberately using ?? rather than || so an explicit empty string
// isn't overridden.
export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:5210'

// Epic 11: exactly one of these two paths is live at a time, matching RequireAuth.jsx's own
// isAuth0Configured branch (it never renders the dev bypass once a tenant is configured, so
// devUserId.js's value is simply never set in that case - this mirrors that same switch).
// - Dev bypass (no Auth0 tenant): names which seeded user the switcher is "acting as", so the
//   backend's role checks ([Authorize(Roles = ...)]) see a real role instead of none.
// - Real Auth0: a live Bearer token via authToken.js's AuthTokenBridge-supplied getter - awaited
//   fresh on every call rather than cached here, since the Auth0 SDK's own getAccessTokenSilently
//   already knows when to silently refresh.
// Applied to every request, not just role-gated ones, so a stale/missing identity fails the same
// way everywhere rather than only on some endpoints.
async function authHeaders() {
  if (isAuth0Configured) return getAuthHeader()
  const devUserId = getDevUserId()
  return devUserId ? { 'X-Dev-User-Id': devUserId } : {}
}

/**
 * Every controller wraps its response in OperationResult<T> (isSuccessful/data/message). This
 * unwraps that envelope and throws the server's own message on failure, so callers just get
 * either the payload or a thrown Error with a message worth showing the user.
 */
export async function apiFetch(url, { method = 'GET', body } = {}) {
  // FormData (file uploads) must NOT be JSON-stringified, and must NOT get an explicit
  // Content-Type - the browser sets its own multipart boundary automatically.
  const isFormData = body instanceof FormData
  const auth = await authHeaders()
  const response = await fetch(url, {
    method,
    headers: isFormData ? auth : { 'Content-Type': 'application/json', ...auth },
    body: isFormData ? body : body !== undefined ? JSON.stringify(body) : undefined,
  })
  const payload = await response.json().catch(() => null)
  if (!response.ok || (payload && payload.isSuccessful === false)) {
    throw new Error(payload?.message || `Request to ${url} failed with status ${response.status}`)
  }
  return payload?.data
}

const api = (path) => `${API_BASE_URL}/api/${path}`

export const Endpoints = {
  // all(): the dev "acting as" directory (AccessPolicies.UserDirectory - open in dev, Admin-only
  // otherwise). me(): the caller's own resolved identity - what a real Auth0 login reads instead.
  // admin*: the Admin user-management screen - every user regardless of active status.
  users: {
    all: () => api('User'),
    me: () => api('User/Me'),
    adminAll: () => api('User/Admin'),
    adminCreate: () => api('User/Admin'),
    adminSetRoles: (userId) => api(`User/Admin/${userId}/Roles`),
    adminSetActive: (userId) => api(`User/Admin/${userId}/Active`),
    adminSetAuth0Subject: (userId) => api(`User/Admin/${userId}/Auth0Subject`),
  },

  changeRequests: {
    submit: () => api('ChangeRequest/Submit'),
    byId: (id) => api(`ChangeRequest/${id}`),
    forUser: (userId) => api(`ChangeRequest/ForUser/${userId}`),
    all: () => api('ChangeRequest'),
    attachDocument: () => api('ChangeRequest/AttachDocument'),
    attachDocumentFile: () => api('ChangeRequest/AttachDocumentFile'),
    attachments: (id) => api(`ChangeRequest/${id}/Attachments`),
    requestClarification: (id) => api(`ChangeRequest/${id}/RequestClarification`),
  },

  // Phase 3 - Data Ingestion Layer. The webapp never calls Mock Systems directly - these proxy
  // through the Workbench so "only the ingestion layer reads Mock Systems" holds for browsing the
  // lookup lists too, not just the actual ingest.
  dataIngestion: {
    mockCustomers: () => api('DataIngestion/MockCustomers'),
    mockProducts: () => api('DataIngestion/MockProducts'),
    mockVendors: () => api('DataIngestion/MockVendors'),
    snapshot: (changeRequestId) => api(`DataIngestion/Snapshot/${changeRequestId}`),
  },

  assessment: {
    openWorkspace: (changeRequestId) => api(`Assessment/OpenWorkspace/${changeRequestId}`),
    byChangeRequest: (changeRequestId) => api(`Assessment/ByChangeRequest/${changeRequestId}`),
    readiness: (assessmentId) => api(`Assessment/${assessmentId}/Readiness`),
    finalize: (assessmentId) => api(`Assessment/${assessmentId}/Finalize`),
  },

  categoryMapping: {
    propose: (assessmentId, changeRequestId) =>
      api(`CategoryMapping/Propose?assessmentId=${assessmentId}&changeRequestId=${changeRequestId}`),
    override: () => api('CategoryMapping/Override'),
    get: (assessmentId) => api(`CategoryMapping/${assessmentId}`),
    categories: () => api('CategoryMapping/Categories'),
  },

  policyResearch: {
    search: (queryText, riskCategoryId, topK = 5) =>
      api(`PolicyResearch/Search?queryText=${encodeURIComponent(queryText)}${riskCategoryId ? `&riskCategoryId=${riskCategoryId}` : ''}&topK=${topK}`),
    recordReliance: () => api('PolicyResearch/RecordReliance'),
    reliance: (assessmentId) => api(`PolicyResearch/${assessmentId}/Reliance`),
  },

  documentExtraction: {
    extract: () => api('DocumentExtraction/Extract'),
    correct: () => api('DocumentExtraction/Correct'),
    fields: (changeRequestId) => api(`DocumentExtraction/${changeRequestId}`),
  },

  narrative: {
    draft: () => api('Narrative/Draft'),
    review: () => api('Narrative/Review'),
    edit: () => api('Narrative/Edit'),
    sections: (assessmentId) => api(`Narrative/${assessmentId}`),
  },

  scoring: {
    config: () => api('Scoring/Config'),
    calculate: () => api('Scoring/Calculate'),
    override: () => api('Scoring/Override'),
    scores: (assessmentId) => api(`Scoring/${assessmentId}`),
    controls: (riskCategoryId) => api(`Scoring/Controls/${riskCategoryId}`),
  },

  committee: {
    route: () => api('Committee/Route'),
    queue: () => api('Committee/Queue'),
    vote: () => api('Committee/Vote'),
    votes: (assessmentId) => api(`Committee/${assessmentId}/Votes`),
    decision: (assessmentId) => api(`Committee/${assessmentId}/Decision`),
  },

  workflowRule: {
    all: () => api('WorkflowRule'),
    upsert: () => api('WorkflowRule'),
  },

  audit: {
    trail: (changeRequestId) => api(`Audit/${changeRequestId}`),
    exportPdf: (changeRequestId) => api(`Audit/${changeRequestId}/Export`),
  },
}

/**
 * Downloads a binary response (e.g. the audit trail PDF), then triggers the browser's normal
 * save-file flow via a temporary object URL. A plain anchor href to a protected endpoint can't
 * attach a token, so this goes through the same authHeaders() every other request uses instead -
 * works under the dev bypass and under real Auth0 login without the caller knowing which is active.
 */
export async function downloadFile(url, filename) {
  const headers = await authHeaders()
  const response = await fetch(url, { headers })
  if (!response.ok) {
    throw new Error(`Request to ${url} failed with status ${response.status}`)
  }
  const blob = await response.blob()
  const objectUrl = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = objectUrl
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(objectUrl)
}
