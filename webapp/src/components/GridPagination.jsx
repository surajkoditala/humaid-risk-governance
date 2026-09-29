import { Button } from '@/components/ui/button'

// Footer control for a server-side-paged grid - "Showing X-Y of N" plus Prev/Next.
export default function GridPagination({ page, pageSize, totalCount, onPageChange }) {
  if (totalCount === 0) return null

  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize))
  const firstRow = (page - 1) * pageSize + 1
  const lastRow = Math.min(page * pageSize, totalCount)

  return (
    <div className="flex items-center justify-between pt-3 text-sm text-muted-foreground">
      <span>
        Showing {firstRow}–{lastRow} of {totalCount}
      </span>
      <div className="flex items-center gap-2">
        <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => onPageChange(page - 1)}>
          Previous
        </Button>
        <span>
          Page {page} of {totalPages}
        </span>
        <Button variant="outline" size="sm" disabled={page >= totalPages} onClick={() => onPageChange(page + 1)}>
          Next
        </Button>
      </div>
    </div>
  )
}
