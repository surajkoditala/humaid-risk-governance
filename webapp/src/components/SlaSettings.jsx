import { useEffect, useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints, apiFetch } from '../lib/api.js'
import { CHANGE_TYPES } from '../lib/constants.js'
import { SLA_STAGE_LABEL, SLA_STAGES, formatDate } from '../lib/sla.js'
import { useFetch } from '../lib/useFetch.js'
import { RequiredMark } from './RequiredMark.jsx'

// The overall (start to decision) target comes first and is required; the three stage targets after it
// are optional - a stage left blank is still timed and shown, it just has no target of its own.
const COLUMNS = ['EndToEnd', 'Submitted', 'InAssessment', 'PendingCommittee']

// { Product: { Submitted: '2', ... }, ... } from the flat list the API returns.
function toGrid(targets) {
  const grid = {}
  CHANGE_TYPES.forEach((t) => {
    grid[t] = {}
    SLA_STAGES.forEach((s) => {
      grid[t][s] = String(targets.find((x) => x.changeType === t && x.stage === s)?.targetBusinessDays ?? '')
    })
  })
  return grid
}

// Service-level targets, the warning threshold and the holiday calendar. Admin only.
export default function SlaSettings() {
  const { currentUser } = useDevUser()
  const [bump, setBump] = useState(0)
  const { data, error } = useFetch(currentUser ? Endpoints.sla.config(currentUser.id) : null, [currentUser?.id, bump])

  const [grid, setGrid] = useState(null)
  const [threshold, setThreshold] = useState('80')
  const [pause, setPause] = useState(true)
  const [retroactive, setRetroactive] = useState(false)
  const [reason, setReason] = useState('')
  const [warnings, setWarnings] = useState([])
  const [saving, setSaving] = useState(false)

  const [holidayDate, setHolidayDate] = useState('')
  const [holidayReason, setHolidayReason] = useState('')

  // Load the saved version into the form whenever it changes (first load, or after a save).
  useEffect(() => {
    if (!data?.config) return
    setGrid(toGrid(data.targets))
    setThreshold(String(data.config.atRiskThresholdPct))
    setPause(data.config.pauseOnClarification)
  }, [data])

  const setCell = (type, stage, value) => {
    setWarnings([])
    setGrid((g) => ({ ...g, [type]: { ...g[type], [stage]: value } }))
  }

  const buildTargets = () => {
    const targets = []
    for (const type of CHANGE_TYPES) {
      for (const stage of COLUMNS) {
        const raw = (grid[type][stage] ?? '').trim()
        if (raw === '' && stage !== 'EndToEnd') continue // optional stage target left blank
        const days = Number(raw)
        if (raw === '' || !Number.isInteger(days) || days < 1) {
          throw new Error(`${type} — ${SLA_STAGE_LABEL[stage]}: enter a whole number of business days, 1 or more${stage === 'EndToEnd' ? '.' : ' (or leave it blank).'}`)
        }
        targets.push({ changeType: type, stage, targetBusinessDays: days })
      }
    }
    return targets
  }

  const save = async (confirmWarnings = false) => {
    let targets
    try {
      targets = buildTargets()
    } catch (err) {
      toast.error(err.message)
      return
    }
    const pct = Number(threshold)
    if (!Number.isInteger(pct) || pct < 1 || pct > 99) {
      toast.error('The warning level must be a whole number between 1 and 99.')
      return
    }
    if (!reason.trim()) {
      toast.error('A reason is required to change the service levels.')
      return
    }
    setSaving(true)
    try {
      const result = await apiFetch(Endpoints.sla.saveConfig(), {
        method: 'POST',
        body: {
          targets,
          atRiskThresholdPct: pct,
          pauseOnClarification: pause,
          retroactive,
          confirmWarnings,
          reason,
          actorUserId: currentUser.id,
        },
      })
      if (!result.saved) {
        setWarnings(result.warnings)
        return
      }
      toast.success('Service levels updated')
      setWarnings([])
      setReason('')
      setRetroactive(false)
      setBump((b) => b + 1)
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSaving(false)
    }
  }

  const addHoliday = async () => {
    if (!holidayDate || !holidayReason.trim()) {
      toast.error('A date and a reason are both required.')
      return
    }
    try {
      await apiFetch(Endpoints.sla.addHoliday(), {
        method: 'POST',
        body: { holidayDate, reason: holidayReason, actorUserId: currentUser.id },
      })
      toast.success('Holiday added')
      setHolidayDate('')
      setHolidayReason('')
      setBump((b) => b + 1)
    } catch (err) {
      toast.error(err.message)
    }
  }

  const removeHoliday = async (id) => {
    if (!holidayReason.trim()) {
      toast.error('Enter a reason below before removing a holiday.')
      return
    }
    try {
      await apiFetch(Endpoints.sla.removeHoliday(id), {
        method: 'POST',
        body: { reason: holidayReason, actorUserId: currentUser.id },
      })
      toast.success('Holiday removed')
      setHolidayReason('')
      setBump((b) => b + 1)
    } catch (err) {
      toast.error(err.message)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Service levels</CardTitle>
        <CardDescription>
          How many business days a request should take from submission to a decision, for each request type. A target for a single stage is optional — leave it blank to track only the overall time. Weekends and the holidays below don't count. Every change is saved as a new version and audited.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-5">
        {error && <p className="text-sm text-destructive">{error}</p>}
        {data?.config && (
          <p className="text-xs text-muted-foreground">
            Current version {data.config.versionNumber}, set {formatDate(data.config.createdAt)} — {data.config.reason}
          </p>
        )}

        {grid && (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Request type</TableHead>
                  {COLUMNS.map((s) => (
                    <TableHead key={s} className="whitespace-normal">
                      {SLA_STAGE_LABEL[s]}
                      {s === 'EndToEnd' ? <RequiredMark /> : <span className="block text-xs font-normal text-muted-foreground">optional</span>}
                    </TableHead>
                  ))}
                </TableRow>
              </TableHeader>
              <TableBody>
                {CHANGE_TYPES.map((type) => (
                  <TableRow key={type}>
                    <TableCell className="font-medium">{type}</TableCell>
                    {COLUMNS.map((stage) => (
                      <TableCell key={stage}>
                        <Input
                          className="w-20"
                          type="number"
                          min={1}
                          step={1}
                          placeholder={stage === 'EndToEnd' ? '' : '—'}
                          aria-label={`${type} — ${SLA_STAGE_LABEL[stage]} (business days)`}
                          value={grid[type][stage]}
                          onChange={(e) => setCell(type, stage, e.target.value)}
                        />
                      </TableCell>
                    ))}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="sla-threshold">
              Warn when this much of the target is used (%)
              <RequiredMark />
            </Label>
            <Input
              id="sla-threshold"
              className="w-28"
              type="number"
              min={1}
              max={99}
              step={1}
              value={threshold}
              onChange={(e) => setThreshold(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="sla-reason">
              Reason for this change
              <RequiredMark />
            </Label>
            <Input id="sla-reason" value={reason} onChange={(e) => setReason(e.target.value)} />
          </div>
        </div>

        <div className="space-y-2 text-sm">
          <label className="flex items-start gap-2">
            <input type="checkbox" className="mt-0.5" checked={pause} onChange={(e) => setPause(e.target.checked)} />
            <span>Don't count time spent waiting on the requester against the analyst (optional)</span>
          </label>
          <label className="flex items-start gap-2">
            <input type="checkbox" className="mt-0.5" checked={retroactive} onChange={(e) => setRetroactive(e.target.checked)} />
            <span>Also apply to requests already in progress (optional — otherwise they keep the targets they started with)</span>
          </label>
        </div>

        {warnings.length > 0 && (
          <div className="space-y-2 rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
            <p className="font-medium">Check these before saving:</p>
            <ul className="list-disc space-y-1 pl-5">
              {warnings.map((w) => (
                <li key={w}>{w}</li>
              ))}
            </ul>
            <div className="flex gap-2">
              <Button size="sm" onClick={() => save(true)} disabled={saving}>
                Save anyway
              </Button>
              <Button size="sm" variant="outline" onClick={() => setWarnings([])}>
                Go back and edit
              </Button>
            </div>
          </div>
        )}

        <Button onClick={() => save(false)} disabled={saving || !grid}>
          {saving ? 'Saving…' : 'Save service levels'}
        </Button>

        <div className="space-y-3 border-t pt-4">
          <div>
            <p className="text-sm font-medium">Holidays</p>
            <p className="text-xs text-muted-foreground">Days that don't count as business days.</p>
          </div>
          <div className="space-y-2">
            {(data?.holidays || []).map((h) => (
              <div key={h.id} className="flex flex-wrap items-center justify-between gap-2 rounded-md border p-2 text-sm">
                <span>
                  {formatDate(`${h.holidayDate}T00:00:00`)} <span className="text-muted-foreground">— {h.reason}</span>
                </span>
                <Button size="sm" variant="outline" onClick={() => removeHoliday(h.id)}>
                  Remove
                </Button>
              </div>
            ))}
            {data && data.holidays.length === 0 && <p className="text-sm text-muted-foreground">No holidays listed.</p>}
          </div>
          <div className="flex flex-wrap items-end gap-2">
            <div className="space-y-1.5">
              <Label htmlFor="holiday-date">
                Date
                <RequiredMark />
              </Label>
              <Input id="holiday-date" className="w-44" type="date" value={holidayDate} onChange={(e) => setHolidayDate(e.target.value)} />
            </div>
            <div className="min-w-48 flex-1 space-y-1.5">
              <Label htmlFor="holiday-reason">
                Reason (for adding or removing)
                <RequiredMark />
              </Label>
              <Input id="holiday-reason" value={holidayReason} onChange={(e) => setHolidayReason(e.target.value)} />
            </div>
            <Button variant="outline" onClick={addHoliday}>
              Add holiday
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
