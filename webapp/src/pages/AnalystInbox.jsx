import { useState } from 'react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Endpoints } from '../lib/api.js'
import { useFetch } from '../lib/useFetch.js'
import AssessmentWorkspace from './AssessmentWorkspace.jsx'

// Analyst's inbox - every submitted change request, so there's somewhere to find work from
// (the user stories imply this exists, even though no single story names it directly).
export default function AnalystInbox() {
  const { data: requests, loading } = useFetch(Endpoints.changeRequests.all())
  const [selected, setSelected] = useState(null)

  if (selected) {
    return <AssessmentWorkspace changeRequest={selected} onBack={() => setSelected(null)} />
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Assessments</CardTitle>
        <CardDescription>Pick a change request to open its assessment workspace.</CardDescription>
      </CardHeader>
      <CardContent>
        {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
        {!loading && (!requests || requests.length === 0) && (
          <p className="text-sm text-muted-foreground">No change requests submitted yet.</p>
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
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {requests.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="font-medium">{r.requestNumber}</TableCell>
                  <TableCell>{r.changeType}</TableCell>
                  <TableCell>{r.title}</TableCell>
                  <TableCell>
                    <Badge variant="secondary">{r.status}</Badge>
                  </TableCell>
                  <TableCell className="text-right">{r.daysElapsed}</TableCell>
                  <TableCell>
                    <Button size="sm" onClick={() => setSelected(r)}>
                      Open
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}
