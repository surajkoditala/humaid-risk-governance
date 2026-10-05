// Auth0 SPA configuration. Values come from Vite env vars - copy .env.example to .env.local
// and fill them in.
export const auth0Domain = import.meta.env.VITE_AUTH0_DOMAIN || ''
export const auth0ClientId = import.meta.env.VITE_AUTH0_CLIENT_ID || ''
export const auth0Audience = import.meta.env.VITE_AUTH0_AUDIENCE || ''

export const isAuth0Configured = Boolean(auth0Domain && auth0ClientId)
