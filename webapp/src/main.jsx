import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './styles/global.css'
import AppAuthProvider from './auth/AppAuthProvider.jsx'
import RequireAuth from './auth/RequireAuth.jsx'
import { DevUserProvider } from './auth/DevUserContext.jsx'
import { Toaster } from '@/components/ui/sonner'
import App from './App.jsx'
import { loadAuthConfig } from './auth/authConfig.js'

// Resolve the Auth0 settings (runtime /config.json, falling back to build-time VITE_*) before the
// first render: AppAuthProvider and RequireAuth decide what to show from them. loadAuthConfig never
// rejects - on any failure it keeps the build-time values - so this always renders.
loadAuthConfig().then(() => {
  createRoot(document.getElementById('root')).render(
    <StrictMode>
      <AppAuthProvider>
        <RequireAuth>
          <DevUserProvider>
            <App />
            <Toaster richColors position="bottom-right" />
          </DevUserProvider>
        </RequireAuth>
      </AppAuthProvider>
    </StrictMode>,
  )
})
