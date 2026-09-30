// This webapp's own backend (Humaid.RiskGovernance.AdminUI.Web). Empty string (the production
// default) means same-origin - deliberately using ?? rather than || so an explicit empty string
// isn't overridden.
export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:5210'

/**
 * Every controller wraps its response in OperationResult<T> (isSuccessful/data/message). This
 * unwraps that envelope and throws the server's own message on failure, so callers just get
 * either the payload or a thrown Error with a message worth showing the user.
 * No Authorization header in this build - the backend runs its own DevBypassAuthHandler while
 * AUTH0_DOMAIN is unset (see Program.cs), matching this webapp's own RequireAuth.jsx dev bypass.
 */
export async function apiFetch(url, { method = 'GET', body } = {}) {
  // FormData (file uploads) must NOT be JSON-stringified, and must NOT get an explicit
  // Content-Type - the browser sets its own multipart boundary automatically.
  const isFormData = body instanceof FormData
  const response = await fetch(url, {
    method,
    headers: isFormData ? undefined : { 'Content-Type': 'application/json' },
    body: isFormData ? body : body !== undefined ? JSON.stringify(body) : undefined,
  })
  const payload = await response.json().catch(() => null)
  if (!response.ok || (payload && payload.isSuccessful === false)) {
    throw new Error(payload?.message || `Request to ${url} failed with status ${response.status}`)
  }
  return payload?.data
}

const api = (path) => `${API_BASE_URL}/api/${path}`

/**
 * Turns a grid query ({page, pageSize, sortBy, sortDir, status, changeType, search}) into a query
 * string, dropping empty/blank values so the backend's GridQuery defaults apply. Shared by every
 * grid endpoint (Assessments inbox, My Requests, Committee Queue) so they all encode paging/
 * sorting/filtering the same way.
 */
function toQueryString(query = {}) {
  const params = new URLSearchParams()
  Object.entries(query).forEach(([key, value]) => {
    if (value !== null && value !== undefined && value !== '') params.set(key, value)
  })
  const qs = params.toString()
  return qs ? `?${qs}` : ''
}

export const Endpoints = {
  users: { all: () => api('User') },

  changeRequests: {
    submit: () => api('ChangeRequest/Submit'),
    byId: (id) => api(`ChangeRequest/${id}`),
    forUser: (userId, query) => api(`ChangeRequest/ForUser/${userId}${toQueryString(query)}`),
    all: (query) => api(`ChangeRequest${toQueryString(query)}`),
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
    queue: (query) => api(`Committee/Queue${toQueryString(query)}`),
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
 * fetch() wrapper that attaches an Auth0 access token as a Bearer header - kept for when a real
 * Auth0 tenant is configured (see webapp/.env.example); unused while running in dev-bypass mode.
 */
export async function authorizedFetch(url, token, options = {}) {
  const headers = { ...(options.headers || {}) }
  if (token) headers.Authorization = `Bearer ${token}`

  const response = await fetch(url, { ...options, headers })
  if (!response.ok) {
    throw new Error(`Request to ${url} failed with status ${response.status}`)
  }
  return response.json()
}

/**
 * Downloads a binary response (e.g. the audit trail PDF) with an optional Bearer token attached,
 * then triggers the browser's normal save-file flow via a temporary object URL. A plain anchor
 * href to a protected endpoint can't attach a token, so it would silently 401 once a real Auth0
 * tenant replaces the dev bypass - this goes through the same auth path apiFetch/authorizedFetch
 * already use for every other request.
 */
export async function downloadFile(url, token, filename) {
  const headers = token ? { Authorization: `Bearer ${token}` } : undefined
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
