import { Fragment, useState } from 'react'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints, apiFetch } from '../lib/api.js'
import { useFetch } from '../lib/useFetch.js'

const ALL_ROLES = ['ProductOwner', 'Analyst', 'CommitteeMember', 'Admin']

function RoleToggle({ roles, onChange }) {
  const toggle = (role) =>
    onChange(roles.includes(role) ? roles.filter((r) => r !== role) : [...roles, role])

  return (
    <div className="flex flex-wrap gap-1.5">
      {ALL_ROLES.map((role) => (
        <Button
          key={role}
          type="button"
          size="sm"
          variant={roles.includes(role) ? 'default' : 'outline'}
          onClick={() => toggle(role)}
        >
          {role}
        </Button>
      ))}
    </div>
  )
}

// Admin user-management screen: list/add/edit-roles/deactivate app_user rows, backed by
// func_createUser/func_setUserRoles/func_setUserActive/func_setUserAuth0Subject - every change
// audited the same way workflow_rule/scoring_config changes already are (see Configuration.jsx).
export default function AdminUsers() {
  const { currentUser } = useDevUser()
  const [bump, setBump] = useState(0)
  const { data: users, loading } = useFetch(Endpoints.users.adminAll(), [bump])

  const [email, setEmail] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [newRoles, setNewRoles] = useState([])
  const [createReason, setCreateReason] = useState('')
  const [creating, setCreating] = useState(false)

  // At most one inline editor open at a time: { userId, mode: 'roles' | 'active' | 'auth0' }.
  const [editing, setEditing] = useState(null)
  const [editRoles, setEditRoles] = useState([])
  const [editAuth0Subject, setEditAuth0Subject] = useState('')
  const [editReason, setEditReason] = useState('')
  const [saving, setSaving] = useState(false)

  const refresh = () => setBump((b) => b + 1)
  const closeEditor = () => {
    setEditing(null)
    setEditReason('')
  }

  const createUser = async () => {
    if (!email.trim() || !displayName.trim()) {
      toast.error('Email and display name are required.')
      return
    }
    if (newRoles.length === 0) {
      toast.error('Select at least one role.')
      return
    }
    if (!createReason.trim()) {
      toast.error('A reason is required to create a user.')
      return
    }
    setCreating(true)
    try {
      await apiFetch(Endpoints.users.adminCreate(), {
        method: 'POST',
        body: { email, displayName, roles: newRoles, reason: createReason, actorUserId: currentUser.id },
      })
      toast.success('User created')
      setEmail('')
      setDisplayName('')
      setNewRoles([])
      setCreateReason('')
      refresh()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setCreating(false)
    }
  }

  const openRolesEditor = (u) => {
    setEditing({ userId: u.id, mode: 'roles' })
    setEditRoles(u.roles)
    setEditReason('')
  }

  const openAuth0Editor = (u) => {
    setEditing({ userId: u.id, mode: 'auth0' })
    setEditAuth0Subject(u.auth0Subject || '')
    setEditReason('')
  }

  const saveRoles = async () => {
    if (editRoles.length === 0) {
      toast.error('A user must hold at least one role.')
      return
    }
    if (!editReason.trim()) {
      toast.error('A reason is required to change a user’s roles.')
      return
    }
    setSaving(true)
    try {
      await apiFetch(Endpoints.users.adminSetRoles(editing.userId), {
        method: 'POST',
        body: { roles: editRoles, reason: editReason, actorUserId: currentUser.id },
      })
      toast.success('Roles updated')
      closeEditor()
      refresh()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  const saveAuth0Subject = async () => {
    if (!editAuth0Subject.trim()) {
      toast.error('An Auth0 subject is required.')
      return
    }
    if (!editReason.trim()) {
      toast.error('A reason is required to link an Auth0 login.')
      return
    }
    setSaving(true)
    try {
      await apiFetch(Endpoints.users.adminSetAuth0Subject(editing.userId), {
        method: 'POST',
        body: { auth0Subject: editAuth0Subject, reason: editReason, actorUserId: currentUser.id },
      })
      toast.success('Auth0 login linked')
      closeEditor()
      refresh()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  const setActive = async (u, isActive) => {
    const reason = window.prompt(`Reason to ${isActive ? 'reactivate' : 'deactivate'} ${u.displayName}:`)
    if (reason === null) return
    if (!reason.trim()) {
      toast.error('A reason is required.')
      return
    }
    try {
      await apiFetch(Endpoints.users.adminSetActive(u.id), {
        method: 'POST',
        body: { isActive, reason, actorUserId: currentUser.id },
      })
      toast.success(isActive ? 'User reactivated' : 'User deactivated')
      refresh()
    } catch (err) {
      toast.error(err.message)
    }
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Add user</CardTitle>
          <CardDescription>
            Creates the person's app_user row with no linked login yet - link their real Auth0
            subject once they've signed in (below), instead of a raw SQL UPDATE.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label>Email</Label>
              <Input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@example.bank" />
            </div>
            <div className="space-y-1.5">
              <Label>Display name</Label>
              <Input value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Roles</Label>
            <RoleToggle roles={newRoles} onChange={setNewRoles} />
          </div>
          <div className="space-y-1.5">
            <Label>Reason (mandatory)</Label>
            <Input value={createReason} onChange={(e) => setCreateReason(e.target.value)} />
          </div>
          <Button onClick={createUser} disabled={creating}>
            Create user
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>All users</CardTitle>
          <CardDescription>Every app_user row, active or not. Every change here is audited.</CardDescription>
        </CardHeader>
        <CardContent>
          {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
          {!loading && (!users || users.length === 0) && <p className="text-sm text-muted-foreground">No users yet.</p>}
          {users?.length > 0 && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Roles</TableHead>
                  <TableHead>Auth0 login</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {users.map((u) => (
                  <Fragment key={u.id}>
                    <TableRow>
                      <TableCell>
                        <div className="font-medium">{u.displayName}</div>
                        <div className="text-xs text-muted-foreground">{u.email}</div>
                      </TableCell>
                      <TableCell>
                        <div className="flex flex-wrap gap-1">
                          {u.roles.map((r) => (
                            <Badge key={r} variant="secondary">
                              {r}
                            </Badge>
                          ))}
                          {u.roles.length === 0 && <span className="text-xs text-muted-foreground">No roles</span>}
                        </div>
                      </TableCell>
                      <TableCell>
                        {u.auth0Subject ? (
                          <span className="text-xs" title={u.auth0Subject}>
                            Linked
                          </span>
                        ) : (
                          <span className="text-xs text-muted-foreground">Not linked</span>
                        )}
                      </TableCell>
                      <TableCell>
                        <Badge variant={u.isActive ? 'secondary' : 'destructive'}>{u.isActive ? 'Active' : 'Inactive'}</Badge>
                      </TableCell>
                      <TableCell>
                        <div className="flex flex-wrap justify-end gap-1.5">
                          <Button size="sm" variant="outline" onClick={() => openRolesEditor(u)}>
                            Edit roles
                          </Button>
                          <Button size="sm" variant="outline" onClick={() => openAuth0Editor(u)}>
                            Link Auth0
                          </Button>
                          <Button size="sm" variant="outline" onClick={() => setActive(u, !u.isActive)}>
                            {u.isActive ? 'Deactivate' : 'Reactivate'}
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                    {editing?.userId === u.id && (
                      <TableRow>
                        <TableCell colSpan={5} className="bg-muted/30">
                          {editing.mode === 'roles' && (
                            <div className="flex flex-wrap items-end gap-2 py-1">
                              <div className="space-y-1.5">
                                <Label>Roles</Label>
                                <RoleToggle roles={editRoles} onChange={setEditRoles} />
                              </div>
                              <div className="space-y-1.5">
                                <Label>Reason (mandatory)</Label>
                                <Input className="w-56" value={editReason} onChange={(e) => setEditReason(e.target.value)} />
                              </div>
                              <Button size="sm" onClick={saveRoles} disabled={saving}>
                                Save
                              </Button>
                              <Button size="sm" variant="ghost" onClick={closeEditor}>
                                Cancel
                              </Button>
                            </div>
                          )}
                          {editing.mode === 'auth0' && (
                            <div className="flex flex-wrap items-end gap-2 py-1">
                              <div className="space-y-1.5">
                                <Label>Auth0 subject (the token's "sub" claim)</Label>
                                <Input className="w-64" value={editAuth0Subject} onChange={(e) => setEditAuth0Subject(e.target.value)} />
                              </div>
                              <div className="space-y-1.5">
                                <Label>Reason (mandatory)</Label>
                                <Input className="w-56" value={editReason} onChange={(e) => setEditReason(e.target.value)} />
                              </div>
                              <Button size="sm" onClick={saveAuth0Subject} disabled={saving}>
                                Save
                              </Button>
                              <Button size="sm" variant="ghost" onClick={closeEditor}>
                                Cancel
                              </Button>
                            </div>
                          )}
                        </TableCell>
                      </TableRow>
                    )}
                  </Fragment>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
