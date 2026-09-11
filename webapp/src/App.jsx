import { useState } from 'react'
import { useAuth0 } from '@auth0/auth0-react'
import { ClipboardList, Gavel, LayoutList, Menu, ShieldCheck, Sliders, X } from 'lucide-react'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { isAuth0Configured } from './auth/authConfig.js'
import { useDevUser } from './auth/DevUserContext.jsx'
import Intake from './pages/Intake.jsx'
import MyRequests from './pages/MyRequests.jsx'
import AnalystInbox from './pages/AnalystInbox.jsx'
import CommitteeQueue from './pages/CommitteeQueue.jsx'
import Configuration from './pages/Configuration.jsx'

const NAV_ITEMS = [
  { key: 'intake', label: 'Submit Request', icon: ClipboardList, roles: ['ProductOwner'] },
  { key: 'myRequests', label: 'My Requests', icon: LayoutList, roles: ['ProductOwner'] },
  { key: 'assessments', label: 'Assessments', icon: ShieldCheck, roles: ['Analyst'] },
  { key: 'committee', label: 'Committee Queue', icon: Gavel, roles: ['CommitteeMember'] },
  { key: 'configuration', label: 'Configuration', icon: Sliders, roles: ['Admin'] },
]

function initialsOf(name) {
  return (name || '')
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((s) => s[0].toUpperCase())
    .join('')
}

function DevUserSwitcher() {
  const { users, currentUser, selectUser, loading } = useDevUser()

  if (loading) return <span className="text-xs text-muted-foreground">Loading users…</span>

  return (
    <Select value={currentUser?.id || ''} onValueChange={selectUser}>
      <SelectTrigger className="w-40 sm:w-56" size="sm">
        <SelectValue placeholder="Acting as…">
          {currentUser ? `${currentUser.displayName} — ${currentUser.role}` : 'Acting as…'}
        </SelectValue>
      </SelectTrigger>
      <SelectContent>
        {users.map((u) => (
          <SelectItem key={u.id} value={u.id}>
            {u.displayName} — {u.role}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

export default function App() {
  const { logout } = useAuth0()
  const { currentUser } = useDevUser()
  const [screen, setScreen] = useState(null)
  const [sidebarOpen, setSidebarOpen] = useState(false)

  const visibleNavItems = NAV_ITEMS.filter((item) => !currentUser || item.roles.includes(currentUser.role))
  const activeScreen = screen && visibleNavItems.some((i) => i.key === screen) ? screen : visibleNavItems[0]?.key

  const signOut = () => {
    if (isAuth0Configured) logout({ logoutParams: { returnTo: window.location.origin } })
  }

  const goTo = (key) => {
    setScreen(key)
    setSidebarOpen(false)
  }

  const screens = {
    intake: <Intake />,
    myRequests: <MyRequests />,
    assessments: <AnalystInbox />,
    committee: <CommitteeQueue />,
    configuration: <Configuration />,
  }

  return (
    <div className="flex min-h-svh flex-col">
      <div className="flex min-h-0 flex-1">
        {sidebarOpen && (
          <div
            className="fixed inset-0 z-40 bg-black/50 md:hidden"
            onClick={() => setSidebarOpen(false)}
            aria-hidden="true"
          />
        )}

        <aside
          className={`fixed inset-y-0 left-0 z-50 flex w-56 flex-none -translate-x-full flex-col bg-sidebar text-sidebar-foreground transition-transform duration-200 md:static md:translate-x-0 ${
            sidebarOpen ? 'translate-x-0' : ''
          }`}
        >
          <div className="flex h-14 items-center gap-2 px-4">
            <ShieldCheck className="size-5 shrink-0 text-sidebar-primary" />
            <span className="text-sm font-semibold">Risk Workbench</span>
            <Button
              variant="ghost"
              size="icon-sm"
              className="ml-auto text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-foreground md:hidden"
              onClick={() => setSidebarOpen(false)}
            >
              <X />
            </Button>
          </div>
          <nav className="flex flex-col gap-1 p-2">
            {visibleNavItems.map((item) => (
              <Button
                key={item.key}
                variant="ghost"
                className={
                  activeScreen === item.key
                    ? 'justify-start bg-sidebar-accent text-sidebar-accent-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground'
                    : 'justify-start text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground'
                }
                onClick={() => goTo(item.key)}
              >
                <item.icon />
                {item.label}
              </Button>
            ))}
            {visibleNavItems.length === 0 && (
              <p className="px-2 text-xs text-sidebar-foreground/60">No screens for this role yet.</p>
            )}
          </nav>
        </aside>

        <div className="flex min-w-0 flex-1 flex-col bg-muted/30">
          <header className="flex h-14 flex-none items-center gap-2 border-b bg-background px-3 sm:gap-3 sm:px-4">
            <Button variant="ghost" size="icon-sm" className="shrink-0 md:hidden" onClick={() => setSidebarOpen(true)}>
              <Menu />
            </Button>
            <DevUserSwitcher />
            <div className="ml-auto flex items-center gap-2 sm:gap-3">
              {currentUser && (
                <Avatar size="sm">
                  <AvatarFallback>{initialsOf(currentUser.displayName)}</AvatarFallback>
                </Avatar>
              )}
              {isAuth0Configured && (
                <Button variant="ghost" size="sm" onClick={signOut}>
                  Sign out
                </Button>
              )}
            </div>
          </header>

          <main className="min-w-0 flex-1 overflow-y-auto p-4 sm:p-6">
            <div className="mx-auto w-full max-w-5xl space-y-6">
              {activeScreen ? screens[activeScreen] : <p className="text-sm text-muted-foreground">Loading…</p>}
            </div>
          </main>

          <footer className="flex-none border-t bg-background px-4 py-3 text-center text-xs text-muted-foreground">
            © 2026 HumAId Risk Governance. All rights reserved.
          </footer>
        </div>
      </div>
    </div>
  )
}
