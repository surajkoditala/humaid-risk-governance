import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints } from '../lib/api.js'
import { SLA_STAGE_LABEL, formatDate } from '../lib/sla.js'
import { useFetch } from '../lib/useFetch.js'
import SlaBadge from './SlaBadge.jsx'

// A one-line summary of how this request stands against its service level, for the analyst working
// it: the overall (start to decision) position first, then the stage it is in now. Shows nothing if
// no target applies (or the user can't see service levels).
export default function SlaStrip({ changeRequestId, refreshKey }) {
  const { currentUser } = useDevUser()
  const { data: rows } = useFetch(
    currentUser ? Endpoints.sla.forRequest(changeRequestId, currentUser.id) : null,
    [currentUser?.id, refreshKey],
  )

  const stage = rows?.find((r) => r.scope === 'Stage')
  const overall = rows?.find((r) => r.scope === 'EndToEnd')
  if (!stage && !overall) return null

  const day = (r) => (r.targetDays != null ? `day ${r.elapsedDays} of ${r.targetDays}` : `${r.elapsedDays} days`)

  return (
    <div className="flex flex-wrap items-center gap-x-4 gap-y-1 rounded-md border bg-background px-3 py-2 text-sm">
      {overall && (
        <span className="flex flex-wrap items-center gap-2">
          <span className="font-medium">Decision</span>
          <span className="text-muted-foreground">
            {day(overall)}
            {overall.dueAt ? ` · due ${formatDate(overall.dueAt)}` : ''}
          </span>
          <SlaBadge state={overall.state} />
        </span>
      )}
      {stage && (
        <span className="flex flex-wrap items-center gap-2 text-muted-foreground">
          <span>
            {SLA_STAGE_LABEL[stage.stage] || stage.stage} · {day(stage)}
            {stage.dueAt && stage.targetDays != null ? ` · due ${formatDate(stage.dueAt)}` : ''}
          </span>
          {stage.targetDays != null && <SlaBadge state={stage.state} />}
          {stage.waitingDays > 0 && (
            <span className="text-xs">
              ({stage.waitingDays} business day{stage.waitingDays === 1 ? '' : 's'} waiting on the requester, not counted)
            </span>
          )}
        </span>
      )}
    </div>
  )
}
