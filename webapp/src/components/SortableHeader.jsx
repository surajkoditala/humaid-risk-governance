import { ChevronDown, ChevronUp, ChevronsUpDown } from 'lucide-react'
import { TableHead } from '@/components/ui/table'

// A clickable grid column header - click toggles asc/desc, switching columns starts at asc.
export default function SortableHeader({ column, label, query, onSort, className }) {
  const active = query.sortBy === column
  const Icon = active ? (query.sortDir === 'asc' ? ChevronUp : ChevronDown) : ChevronsUpDown

  return (
    <TableHead className={className}>
      <button
        type="button"
        onClick={() => onSort(column)}
        className="inline-flex items-center gap-1 font-medium hover:text-foreground/80"
      >
        {label}
        <Icon className={`size-3.5 ${active ? '' : 'text-muted-foreground/50'}`} />
      </button>
    </TableHead>
  )
}
