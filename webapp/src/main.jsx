import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './styles/global.css'
import AppAuthProvider from './auth/AppAuthProvider.jsx'
import RequireAuth from './auth/RequireAuth.jsx'
import { DevUserProvider } from './auth/DevUserContext.jsx'
import { Toaster } from '@/components/ui/sonner'
import App from './App.jsx'

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
