import { useState } from 'react'
import ClampedText from '../components/ClampedText.jsx'
import SlaBadge from '../components/SlaBadge.jsx'
import GridPagination from '../components/GridPagination.jsx'
import SortableHeader from '../components/SortableHeader.jsx'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Endpoints } from '../lib/api.js'
import { CHANGE_REQUEST_STATUSES, CHANGE_TYPES } from '../lib/constants.js'
import { formatDate } from '../lib/sla.js'
import { useDebouncedValue } from '../lib/useDebouncedValue.js'
import { useFetch } from '../lib/useFetch.js'
import { useGridQuery } from '../lib/useGridQuery.js'
import AssessmentWorkspace from './AssessmentWorkspace.jsx'

// Analyst's inbox - every submitted change request, so there's somewhere to find work from
// (the user stories imply this exists, even though no single story names it directly).
export default function AnalystInbox() {
  const { query, toggleSort, setFilter, setPage } = useGridQuery()
  const debouncedSearch = useDebouncedValue(query.search)
  const { data, loading } = useFetch(Endpoints.changeRequests.all({ ...query, search: debouncedSearch }))
  const [selected, setSelected] = useState(null)

  if (selected) {
    return <AssessmentWorkspace changeRequest={selected} onBack={() => setSelected(null)} />
  }

  const requests = data?.items

  return (
    <Card>
      <CardHeader>
        <CardTitle>Assessments</CardTitle>
        <CardDescription>Pick a change request to open its assessment workspace.</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="mb-4 flex flex-wrap items-center gap-2">
          <Input
            placeholder="Search title or request #…"
            className="w-full sm:w-64"
            value={query.search}
            onChange={(e) => setFilter('search', e.target.value)}
          />
          <Select value={query.status || 'all'} onValueChange={(v) => setFilter('status', v === 'all' ? '' : v)}>
            <SelectTrigger className="w-40">
              <SelectValue placeholder="Status" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All statuses</SelectItem>
              {CHANGE_REQUEST_STATUSES.map((s) => (
                <SelectItem key={s} value={s}>
                  {s}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={query.changeType || 'all'} onValueChange={(v) => setFilter('changeType', v === 'all' ? '' : v)}>
            <SelectTrigger className="w-40">
              <SelectValue placeholder="Type" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All types</SelectItem>
              {CHANGE_TYPES.map((t) => (
                <SelectItem key={t} value={t}>
                  {t}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
        {!loading && (!requests || requests.length === 0) && (
          <p className="text-sm text-muted-foreground">No change requests match these filters.</p>
        )}
        {requests?.length > 0 && (
          <>
            <Table className="table-fixed">
              <colgroup>
                <col className="w-28" />
                <col className="w-24" />
                <col />
                <col className="w-28" />
                <col className="w-20" />
                <col className="w-32" />
                <col className="w-16" />
              </colgroup>
              <TableHeader>
                <TableRow>
                  <SortableHeader column="requestNumber" label="Request #" query={query} onSort={toggleSort} />
                  <SortableHeader column="changeType" label="Type" query={query} onSort={toggleSort} />
                  <SortableHeader column="title" label="Title" query={query} onSort={toggleSort} />
                  <SortableHeader column="status" label="Status" query={query} onSort={toggleSort} />
                  <SortableHeader
                    column="daysElapsed"
                    label="Days elapsed"
                    query={query}
                    onSort={toggleSort}
                    className="text-right"
                  />
                  <TableHead>Due</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {requests.map((r) => (
                  <TableRow key={r.id}>
                    <TableCell className="whitespace-normal break-words font-medium">{r.requestNumber}</TableCell>
                    <TableCell className="whitespace-normal break-words">{r.changeType}</TableCell>
                    <TableCell>
                      <ClampedText text={r.title} />
                    </TableCell>
                    <TableCell>
                      <Badge variant="secondary">{r.status}</Badge>
                    </TableCell>
                    <TableCell className="text-right">{r.daysElapsed}</TableCell>
                    <TableCell className="whitespace-normal">
                      {r.dueAt && <p className="text-sm">{formatDate(r.dueAt)}</p>}
                      <SlaBadge state={r.slaState} />
                    </TableCell>
                    <TableCell>
                      <Button size="sm" onClick={() => setSelected(r)}>
                        Open
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            <GridPagination page={data.page} pageSize={data.pageSize} totalCount={data.totalCount} onPageChange={setPage} />
          </>
        )}
      </CardContent>
    </Card>
  )
}
