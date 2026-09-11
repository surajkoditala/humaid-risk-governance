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

export const Endpoints = {
  users: { all: () => api('User') },

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
