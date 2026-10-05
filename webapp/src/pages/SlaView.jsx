import { useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import ClampedText from '../components/ClampedText.jsx'
import SlaBadge from '../components/SlaBadge.jsx'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints } from '../lib/api.js'
import { CHANGE_TYPES } from '../lib/constants.js'
import { BASELINE_DAYS, SLA_STAGE_LABEL, SLA_STAGES, formatDate } from '../lib/sla.js'
import { useFetch } from '../lib/useFetch.js'

// Most urgent first. A request with no target configured is listed last, as "Not tracked".
const GROUPS = [
  { key: 'Breached', title: 'Overdue' },
  { key: 'AtRisk', title: 'At risk' },
  { key: 'OnTrack', title: 'On track' },
  { key: 'none', title: 'No target set' },
]

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

function OpenRequests({ actorId }) {
  const [stage, setStage] = useState('')
  const [changeType, setChangeType] = useState('')
  const { data: rows, loading, error } = useFetch(
    actorId ? Endpoints.sla.view(actorId, { stage, changeType }) : null,
    [actorId],
  )

  const grouped = GROUPS.map((g) => ({
    ...g,
    rows: (rows || []).filter((r) => (r.overallState || 'none') === g.key),
  }))

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <FilterSelect
          value={stage}
          onChange={setStage}
          allLabel="All stages"
          options={SLA_STAGES.filter((s) => s !== 'EndToEnd').map((s) => ({ value: s, label: SLA_STAGE_LABEL[s] }))}
        />
        <FilterSelect
          value={changeType}
          onChange={setChangeType}
          allLabel="All types"
          width="w-44"
          options={CHANGE_TYPES.map((t) => ({ value: t, label: t }))}
        />
      </div>

      {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
      {error && <p className="text-sm text-destructive">{error}</p>}
      {!loading && !error && rows?.length === 0 && (
        <p className="text-sm text-muted-foreground">No open requests match these filters.</p>
      )}

      {grouped
        .filter((g) => g.rows.length > 0)
        .map((g) => (
          <Card key={g.key}>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                {g.title}
                <span className="text-sm font-normal text-muted-foreground">({g.rows.length})</span>
              </CardTitle>
            </CardHeader>
            <CardContent>
              <Table className="table-fixed">
                <colgroup>
                  <col className="w-28" />
                  <col />
                  <col className="w-40" />
                  <col className="w-28" />
                  <col className="w-32" />
                </colgroup>
                <TableHeader>
                  <TableRow>
                    <TableHead>Request #</TableHead>
                    <TableHead>Title</TableHead>
                    <TableHead>Where it is</TableHead>
                    <TableHead>Progress</TableHead>
                    <TableHead>Due</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {g.rows.map((r) => (
                    <TableRow key={r.changeRequestId}>
                      <TableCell className="whitespace-normal break-words font-medium">{r.requestNumber}</TableCell>
                      <TableCell>
                        <ClampedText text={r.title} />
                        <p className="text-xs text-muted-foreground">{r.changeType}</p>
                      </TableCell>
                      <TableCell className="whitespace-normal break-words">{SLA_STAGE_LABEL[r.stage] || r.stage}</TableCell>
                      <TableCell className="whitespace-normal">
                        {r.targetDays != null ? `${r.elapsedDays} of ${r.targetDays} days` : `${r.elapsedDays} days`}
                        {r.waitingDays > 0 && (
                          <p className="text-xs text-muted-foreground">+{r.waitingDays} waiting on requester</p>
                        )}
                      </TableCell>
                      <TableCell className="whitespace-normal">
                        {formatDate(r.dueAt)}
                        {r.daysOverdue > 0 && (
                          <p className="text-xs text-red-700">
                            {r.daysOverdue} business day{r.daysOverdue === 1 ? '' : 's'} overdue
                          </p>
                        )}
                        {g.key !== 'none' && (
                          <div className="mt-1">
                            <SlaBadge state={r.overallState} />
                          </div>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        ))}
    </div>
  )
}

function CycleTime({ actorId }) {
  const [changeType, setChangeType] = useState('')
  const { data: rows, loading, error } = useFetch(
    actorId ? Endpoints.sla.performance(actorId, { changeType }) : null,
    [actorId],
  )

  const overall = (rows || []).find((r) => r.changeType === 'All')
  const perType = (rows || []).filter((r) => r.changeType !== 'All')

  return (
    <div className="space-y-4">
      <FilterSelect
        value={changeType}
        onChange={setChangeType}
        allLabel="All types"
        width="w-44"
        options={CHANGE_TYPES.map((t) => ({ value: t, label: t }))}
      />

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

      {perType.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">By request type and stage</CardTitle>
            <CardDescription>All durations are in business days.</CardDescription>
          </CardHeader>
          <CardContent>
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
                {perType.map((r) => (
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
