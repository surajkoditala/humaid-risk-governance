import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHeader, TableRow } from '@/components/ui/table'
import ClampedText from '../components/ClampedText.jsx'
import GridPagination from '../components/GridPagination.jsx'
import SortableHeader from '../components/SortableHeader.jsx'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints } from '../lib/api.js'
import { CHANGE_REQUEST_STATUSES, CHANGE_TYPES } from '../lib/constants.js'
import { useDebouncedValue } from '../lib/useDebouncedValue.js'
import { useFetch } from '../lib/useFetch.js'
import { useGridQuery } from '../lib/useGridQuery.js'

const STATUS_VARIANT = {
  Submitted: 'secondary',
  InAssessment: 'default',
  PendingCommittee: 'default',
  Decisioned: 'outline',
}

// US-1.3: see where every one of my requests stands, without emailing FCRM.
export default function MyRequests() {
  const { currentUser } = useDevUser()
  const { query, toggleSort, setFilter, setPage } = useGridQuery()
  const debouncedSearch = useDebouncedValue(query.search)
  const { data, loading } = useFetch(
    currentUser ? Endpoints.changeRequests.forUser(currentUser.id, { ...query, search: debouncedSearch }) : null,
    [currentUser?.id],
  )

  const requests = data?.items

  return (
    <Card>
      <CardHeader>
        <CardTitle>My requests</CardTitle>
        <CardDescription>Status and days elapsed since submission.</CardDescription>
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
          <p className="text-sm text-muted-foreground">No requests match these filters.</p>
        )}
        {requests?.length > 0 && (
          <>
            <Table className="table-fixed">
              <colgroup>
                <col className="w-28" />
                <col className="w-24" />
                <col />
                <col className="w-40" />
                <col className="w-28" />
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
                      <Badge variant={STATUS_VARIANT[r.status] || 'secondary'}>
                        {/* DEF-022: "Decisioned" alone told the requester nothing - show the actual outcome. */}
                        {r.decisionResolution || r.status}
                      </Badge>
                      {r.decisionConditionsText && (
                        <p className="mt-1 whitespace-normal break-words text-xs text-muted-foreground">
                          {r.decisionConditionsText}
                        </p>
                      )}
                    </TableCell>
                    <TableCell className="text-right">{r.daysElapsed}</TableCell>
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
