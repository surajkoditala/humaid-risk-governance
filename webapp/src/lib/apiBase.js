// This webapp's own backend (Humaid.RiskGovernance.AdminUI.Web). Empty string (the production
// default, set by the Workbench Dockerfile) means same-origin - deliberately using ?? rather than ||
// so an explicit empty string isn't overridden.
//
// This one stays a build-time value on purpose: it is where the SPA looks for its *runtime* config
// (/config.json, see auth/authConfig.js), so it cannot itself come from there. In the deployed
// single-container shape it is "" (same origin) in every environment, so there is nothing to change
// per environment.
export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:5210'
