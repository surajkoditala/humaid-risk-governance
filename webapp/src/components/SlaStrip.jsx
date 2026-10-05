import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints } from '../lib/api.js'
import { SLA_STAGE_LABEL, formatDate } from '../lib/sla.js'
import { useFetch } from '../lib/useFetch.js'
import SlaBadge from './SlaBadge.jsx'

// A one-line summary of how this request stands against its service level, for the analyst working
// it. Shows nothing if no target applies (or the user can't see service levels).
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
      {stage && (
        <span className="flex flex-wrap items-center gap-2">
          <span className="font-medium">{SLA_STAGE_LABEL[stage.stage] || stage.stage}</span>
          <span className="text-muted-foreground">
            {day(stage)}
            {stage.dueAt ? ` · due ${formatDate(stage.dueAt)}` : ''}
          </span>
          <SlaBadge state={stage.state} />
          {stage.waitingDays > 0 && (
            <span className="text-xs text-muted-foreground">
              ({stage.waitingDays} business day{stage.waitingDays === 1 ? '' : 's'} waiting on the requester, not counted)
            </span>
          )}
        </span>
      )}
      {overall && (
        <span className="flex flex-wrap items-center gap-2 text-muted-foreground">
          <span>Overall {day(overall)}</span>
          {overall.dueAt && <span>· due {formatDate(overall.dueAt)}</span>}
          <SlaBadge state={overall.state} />
        </span>
      )}
    </div>
  )
}
