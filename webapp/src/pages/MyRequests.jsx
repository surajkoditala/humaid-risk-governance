import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints } from '../lib/api.js'
import { useFetch } from '../lib/useFetch.js'

const STATUS_VARIANT = {
  Submitted: 'secondary',
  InAssessment: 'default',
  PendingCommittee: 'default',
  Decisioned: 'outline',
}

// US-1.3: see where every one of my requests stands, without emailing FCRM.
export default function MyRequests() {
  const { currentUser } = useDevUser()
  const { data: requests, loading } = useFetch(
    currentUser ? Endpoints.changeRequests.forUser(currentUser.id) : null,
    [currentUser?.id],
  )

  return (
    <Card>
      <CardHeader>
        <CardTitle>My requests</CardTitle>
        <CardDescription>Status and days elapsed since submission.</CardDescription>
      </CardHeader>
      <CardContent>
        {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
        {!loading && (!requests || requests.length === 0) && (
          <p className="text-sm text-muted-foreground">No requests submitted yet.</p>
        )}
        {requests?.length > 0 && (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Request #</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Title</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="text-right">Days elapsed</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {requests.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="font-medium">{r.requestNumber}</TableCell>
                  <TableCell>{r.changeType}</TableCell>
                  <TableCell>{r.title}</TableCell>
                  <TableCell>
                    <Badge variant={STATUS_VARIANT[r.status] || 'secondary'}>{r.status}</Badge>
                  </TableCell>
                  <TableCell className="text-right">{r.daysElapsed}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}
