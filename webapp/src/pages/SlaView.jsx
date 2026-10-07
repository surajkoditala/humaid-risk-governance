import { useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import ClampedText from '../components/ClampedText.jsx'
import GridPagination from '../components/GridPagination.jsx'
import SlaBadge from '../components/SlaBadge.jsx'
import SortableHeader from '../components/SortableHeader.jsx'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints } from '../lib/api.js'
import { CHANGE_TYPES } from '../lib/constants.js'
import { BASELINE_DAYS, SLA_STAGE_LABEL, SLA_STAGES, SLA_STATE_LABEL, formatDate } from '../lib/sla.js'
import { useDebouncedValue } from '../lib/useDebouncedValue.js'
import { useFetch } from '../lib/useFetch.js'
import { useGridQuery } from '../lib/useGridQuery.js'

// The stages a request can currently be in (the overall start-to-decision figure is not one of them).
const OPEN_STAGES = SLA_STAGES.filter((s) => s !== 'EndToEnd')

// State filter chips, most urgent first. Counts come from the server for the current filters.
const STATE_CHIPS = ['Breached', 'AtRisk', 'OnTrack']

function FilterSelect({ value, onChange, allLabel, options, width = 'w-52' }) {
  return (
    <Select value={value || 'all'} onValueChange={(v) => onChange(v === 'all' ? '' : v)}>
      <SelectTrigger className={width}>
        <SelectValue placeholder={allLabel}>
          {value ? options.find((o) => o.value === value)?.label : allLabel}
        </SelectValue>
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="all">{allLabel}</SelectItem>
        {options.map((o) => (
          <SelectItem key={o.value} value={o.value}>
            {o.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

function StateChip({ label, count, active, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-full border px-3 py-1 text-xs font-medium transition-colors ${
        active ? 'border-primary bg-primary text-primary-foreground' : 'bg-background hover:bg-muted'
      }`}
    >
      {label} <span className={active ? '' : 'text-muted-foreground'}>({count})</span>
    </button>
  )
}

function OpenRequests({ actorId }) {
  // Most urgent first until the user picks a column to sort by (blank sortBy = urgency, server side).
  const { query, toggleSort, setFilter, setPage } = useGridQuery({ sortDir: 'asc' })
  const debouncedSearch = useDebouncedValue(query.search)
  const filters = { stage: query.stage, changeType: query.changeType, search: debouncedSearch }

  const { data, loading, error } = useFetch(
    actorId ? Endpoints.sla.view(actorId, { ...query, search: debouncedSearch }) : null,
    [actorId],
  )
  const { data: counts } = useFetch(actorId ? Endpoints.sla.summary(actorId, filters) : null, [actorId])

  const rows = data?.items
  const countOf = (state) => counts?.find((c) => c.overallState === state)?.requestCount ?? 0
  const totalOpen = (counts || []).reduce((sum, c) => sum + c.requestCount, 0)

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <Input
          placeholder="Search title or request #…"
          className="w-full sm:w-64"
          value={query.search}
          onChange={(e) => setFilter('search', e.target.value)}
        />
        <FilterSelect
          value={query.stage}
          onChange={(v) => setFilter('stage', v)}
          allLabel="All stages"
          options={OPEN_STAGES.map((s) => ({ value: s, label: SLA_STAGE_LABEL[s] }))}
        />
        <FilterSelect
          value={query.changeType}
          onChange={(v) => setFilter('changeType', v)}
          allLabel="All types"
          width="w-44"
          options={CHANGE_TYPES.map((t) => ({ value: t, label: t }))}
        />
      </div>

      <div className="flex flex-wrap gap-2">
        <StateChip label="All" count={totalOpen} active={!query.state} onClick={() => setFilter('state', '')} />
        {STATE_CHIPS.map((state) => (
          <StateChip
            key={state}
            label={SLA_STATE_LABEL[state]}
            count={countOf(state)}
            active={query.state === state}
            onClick={() => setFilter('state', query.state === state ? '' : state)}
          />
        ))}
      </div>

      {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
      {error && <p className="text-sm text-destructive">{error}</p>}
      {!loading && !error && rows?.length === 0 && (
        <p className="text-sm text-muted-foreground">No open requests match these filters.</p>
      )}

      {rows?.length > 0 && (
        <>
          <Table className="table-fixed">
            <colgroup>
              <col className="w-28" />
              <col />
              <col className="w-40" />
              <col className="w-32" />
              <col className="w-36" />
            </colgroup>
            <TableHeader>
              <TableRow>
                <SortableHeader column="requestNumber" label="Request #" query={query} onSort={toggleSort} />
                <SortableHeader column="title" label="Title" query={query} onSort={toggleSort} />
                <SortableHeader column="stage" label="Where it is" query={query} onSort={toggleSort} />
                <SortableHeader column="progress" label="Time used" query={query} onSort={toggleSort} />
                <SortableHeader column="dueAt" label="Due" query={query} onSort={toggleSort} />
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => (
                <TableRow key={r.changeRequestId}>
                  <TableCell className="whitespace-normal break-words font-medium">{r.requestNumber}</TableCell>
                  <TableCell>
                    <ClampedText text={r.title} />
                    <p className="text-xs text-muted-foreground">{r.changeType}</p>
                  </TableCell>
                  <TableCell className="whitespace-normal break-words">{SLA_STAGE_LABEL[r.stage] || r.stage}</TableCell>
                  <TableCell className="whitespace-normal">
                    {r.e2eTargetDays != null ? `${r.e2eElapsedDays} of ${r.e2eTargetDays} days` : `${r.elapsedDays} days`}
                    <p className="text-xs text-muted-foreground">
                      {r.e2eTargetDays != null ? 'overall' : 'in this stage'}
                      {r.e2eTargetDays != null && (
                        <>
                          {' · '}
                          {r.targetDays != null ? `${r.elapsedDays} of ${r.targetDays}` : r.elapsedDays} in this stage
                        </>
                      )}
                    </p>
                    {r.waitingDays > 0 && (
                      <p className="text-xs text-muted-foreground">+{r.waitingDays} waiting on requester</p>
                    )}
                  </TableCell>
                  <TableCell className="whitespace-normal">
                    {formatDate(r.dueAt ?? r.e2eDueAt)}
                    {r.daysOverdue > 0 && (
                      <p className="text-xs text-red-700">
                        {r.daysOverdue} business day{r.daysOverdue === 1 ? '' : 's'} overdue
                      </p>
                    )}
                    <div className="mt-1">
                      <SlaBadge state={r.overallState} />
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
          <GridPagination page={data.page} pageSize={data.pageSize} totalCount={data.totalCount} onPageChange={setPage} />
        </>
      )}
    </div>
  )
}

const CYCLE_PAGE_SIZE = 10

function CycleTime({ actorId }) {
  const [changeType, setChangeType] = useState('')
  const [stage, setStage] = useState('')
  const [page, setPage] = useState(1)
  const { data: rows, loading, error } = useFetch(
    actorId ? Endpoints.sla.performance(actorId, { changeType }) : null,
    [actorId],
  )

  const overall = (rows || []).find((r) => r.changeType === 'All')
  const perType = (rows || []).filter((r) => r.changeType !== 'All' && (!stage || r.stage === stage))
  const pageRows = perType.slice((page - 1) * CYCLE_PAGE_SIZE, page * CYCLE_PAGE_SIZE)

  // Any filter change goes back to the first page.
  const changeFilter = (setter) => (value) => {
    setter(value)
    setPage(1)
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <FilterSelect
          value={changeType}
          onChange={changeFilter(setChangeType)}
          allLabel="All types"
          width="w-44"
          options={CHANGE_TYPES.map((t) => ({ value: t, label: t }))}
        />
        <FilterSelect
          value={stage}
          onChange={changeFilter(setStage)}
          allLabel="All stages"
          options={SLA_STAGES.map((s) => ({ value: s, label: SLA_STAGE_LABEL[s] }))}
        />
      </div>

      {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
      {error && <p className="text-sm text-destructive">{error}</p>}
      {!loading && !error && (rows || []).length === 0 && (
        <p className="text-sm text-muted-foreground">
          Nothing to show yet — figures appear once requests have moved through a stage or been decided.
        </p>
      )}

      {overall && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Start to decision</CardTitle>
            <CardDescription>
              Before this platform a request took {BASELINE_DAYS.min}–{BASELINE_DAYS.max} business days.
            </CardDescription>
          </CardHeader>
          <CardContent className="grid gap-4 sm:grid-cols-4">
            <Stat label="Requests decided" value={overall.sampleCount} />
            <Stat label="Typical (median)" value={`${overall.medianDays} days`} />
            <Stat label="9 in 10 finish within" value={`${overall.p90Days} days`} />
            <Stat label="Met their target" value={overall.metPercent != null ? `${overall.metPercent}%` : '—'} />
          </CardContent>
        </Card>
      )}

      {(rows || []).some((r) => r.changeType !== 'All') && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">By request type and stage</CardTitle>
            <CardDescription>All durations are in business days.</CardDescription>
          </CardHeader>
          <CardContent>
            {perType.length === 0 ? (
              <p className="text-sm text-muted-foreground">No figures for this stage yet.</p>
            ) : (
              <>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Type</TableHead>
                      <TableHead>Stage</TableHead>
                      <TableHead className="text-right">Finished</TableHead>
                      <TableHead className="text-right">Target</TableHead>
                      <TableHead className="text-right">Typical</TableHead>
                      <TableHead className="text-right">9 in 10 within</TableHead>
                      <TableHead className="text-right">Met target</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {pageRows.map((r) => (
                      <TableRow key={`${r.changeType}-${r.stage}`}>
                        <TableCell className="font-medium">{r.changeType}</TableCell>
                        <TableCell className="whitespace-normal">{SLA_STAGE_LABEL[r.stage] || r.stage}</TableCell>
                        <TableCell className="text-right">{r.sampleCount}</TableCell>
                        <TableCell className="text-right">{r.targetDays ?? '—'}</TableCell>
                        <TableCell className="text-right">{r.medianDays}</TableCell>
                        <TableCell className="text-right">{r.p90Days}</TableCell>
                        <TableCell className="text-right">{r.metPercent != null ? `${r.metPercent}%` : '—'}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
                <GridPagination page={page} pageSize={CYCLE_PAGE_SIZE} totalCount={perType.length} onPageChange={setPage} />
              </>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  )
}

function Stat({ label, value }) {
  return (
    <div>
      <p className="text-2xl font-semibold">{value}</p>
      <p className="text-xs text-muted-foreground">{label}</p>
    </div>
  )
}

// Where open requests stand against their service levels, and how long finished ones took.
export default function SlaView() {
  const { currentUser } = useDevUser()
  const actorId = currentUser?.id

  return (
    <Card>
      <CardHeader>
        <CardTitle>Service levels</CardTitle>
        <CardDescription>How open requests are tracking against their targets, and how long finished ones took.</CardDescription>
      </CardHeader>
      <CardContent>
        <Tabs defaultValue="open">
          <TabsList>
            <TabsTrigger value="open">Open requests</TabsTrigger>
            <TabsTrigger value="cycle">Cycle time</TabsTrigger>
          </TabsList>
          <TabsContent value="open" className="pt-4">
            <OpenRequests actorId={actorId} />
          </TabsContent>
          <TabsContent value="cycle" className="pt-4">
            <CycleTime actorId={actorId} />
          </TabsContent>
        </Tabs>
      </CardContent>
    </Card>
  )
}
