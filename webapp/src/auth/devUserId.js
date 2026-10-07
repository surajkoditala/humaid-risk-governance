// Epic 11: the currently "acting as" user id, shared between DevUserContext.jsx (which sets it
// whenever the switcher changes) and lib/api.js (which reads it to set the X-Dev-User-Id header on
// every request - see DevBypassAuthHandler.cs). A plain module-level variable, not React state: it
// needs to be readable from api.js without importing React or creating a circular import between
// the two modules.
let currentDevUserId = null

export function setDevUserId(id) {
  currentDevUserId = id
}

export function getDevUserId() {
  return currentDevUserId
}
