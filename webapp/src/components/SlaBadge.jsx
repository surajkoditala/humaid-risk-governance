import { Badge } from '@/components/ui/badge'
import { SLA_STATE_LABEL } from '../lib/sla.js'

const STATE_CLASS = {
  OnTrack: 'border-emerald-300 bg-emerald-50 text-emerald-800',
  Met: 'border-emerald-300 bg-emerald-50 text-emerald-800',
  AtRisk: 'border-amber-300 bg-amber-50 text-amber-800',
  Breached: 'border-red-300 bg-red-50 text-red-800',
  Missed: 'border-red-300 bg-red-50 text-red-800',
}

// A request's service-level state as a coloured pill. Renders nothing when no target applies.
export default function SlaBadge({ state }) {
  if (!state) return null
  return (
    <Badge variant="outline" className={STATE_CLASS[state]}>
      {SLA_STATE_LABEL[state] || state}
    </Badge>
  )
}
