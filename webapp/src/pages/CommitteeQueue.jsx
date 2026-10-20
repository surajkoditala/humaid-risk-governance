import { useState } from 'react'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Textarea } from '@/components/ui/textarea'
import ClampedText from '../components/ClampedText.jsx'
import SlaBadge from '../components/SlaBadge.jsx'
import GridPagination from '../components/GridPagination.jsx'
import SortableHeader from '../components/SortableHeader.jsx'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints, apiFetch } from '../lib/api.js'
import { CHANGE_TYPES } from '../lib/constants.js'
import { formatDate } from '../lib/sla.js'
import { useDebouncedValue } from '../lib/useDebouncedValue.js'
import { useFetch } from '../lib/useFetch.js'
import { useGridQuery } from '../lib/useGridQuery.js'

const VOTE_OPTIONS = ['Approve', 'ApproveWithConditions', 'Defer', 'Reject']

function VotePanel({ item, onBack }) {
  const { currentUser } = useDevUser()
  const [bump, setBump] = useState(0)
  const { data: votes } = useFetch(Endpoints.committee.votes(item.assessmentId), [bump])
  const { data: decision } = useFetch(Endpoints.committee.decision(item.assessmentId), [bump])
  // DEF-021: the panel used to show only the title, vote form and vote list - no narrative,
  // scores, cited policy or override history, so a member had to vote blind (US-8.2 AC1).
  const { data: mapping } = useFetch(Endpoints.categoryMapping.get(item.assessmentId), [bump])
  const { data: sections } = useFetch(Endpoints.narrative.sections(item.assessmentId), [bump])
  const { data: scores } = useFetch(Endpoints.scoring.scores(item.assessmentId), [bump])
  const { data: reliance } = useFetch(Endpoints.policyResearch.reliance(item.assessmentId), [bump])
  const [vote, setVote] = useState('')
  const [text, setText] = useState('')
  const [submitting, setSubmitting] = useState(false)

  const needsConditions = vote === 'ApproveWithConditions'
  const needsRationale = vote === 'Reject' || vote === 'Defer'

  const submitVote = async () => {
    if (!vote) return
    if (needsConditions && !text.trim()) {
      toast.error('Conditions text is required for Approve-with-Conditions.')
      return
    }
    if (needsRationale && !text.trim()) {
      toast.error('A rationale is required for Reject/Defer.')
      return
    }
    setSubmitting(true)
    try {
      await apiFetch(Endpoints.committee.vote(), {
        method: 'POST',
        body: {
          assessmentId: item.assessmentId,
          committeeMemberUserId: currentUser.id,
          vote,
          conditionsText: needsConditions ? text : null,
          rationale: needsRationale ? text : null,
        },
      })
      toast.success('Vote cast')
      setVote('')
      setText('')
      setBump((b) => b + 1)
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="space-y-4">
      <Button variant="ghost" size="sm" onClick={onBack}>
        ← Back to queue
      </Button>
      <Card>
        <CardHeader>
          <CardTitle>{item.requestNumber} — {item.title}</CardTitle>
          <CardDescription>Every member's vote is recorded individually, never anonymized.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-3 rounded-md border p-3">
            <p className="text-sm font-medium">Assessment (read-only)</p>
            {(mapping || []).filter((m) => m.isActive).map((m) => {
              const section = (sections || []).find((s) => s.riskCategoryId === m.riskCategoryId)
              const score = (scores || []).find((s) => s.riskCategoryId === m.riskCategoryId)
              const relied = (reliance || []).filter(
                (r) => r.decision === 'ReliedUpon' && (r.riskCategoryId === null || r.riskCategoryId === m.riskCategoryId),
              )
              return (
                <div key={m.riskCategoryId} className="space-y-1 border-t pt-2 first:border-t-0 first:pt-0">
                  <p className="text-sm font-medium">{m.categoryName}</p>
                  <p className="text-xs text-muted-foreground">
                    {m.source === 'AiProposed' ? `AI proposed — ${m.aiCitation || m.citationSection}` : 'Analyst added'}
                  </p>
                  <p className="text-sm">{section?.narrativeText || 'No narrative drafted.'}</p>
                  {score && (
                    <p className="text-xs text-muted-foreground">
                      Inherent {score.inherentRating} · Residual {score.residualRating}
                      {score.isOverride && ' · Analyst override'}
                    </p>
                  )}
                  {relied.length > 0 && (
                    <p className="text-xs text-muted-foreground">Policy relied upon: {relied.map((r) => r.sectionRef).join('; ')}</p>
                  )}
                </div>
              )
            })}
            {(!mapping || mapping.filter((m) => m.isActive).length === 0) && (
              <p className="text-sm text-muted-foreground">No categories mapped.</p>
            )}
          </div>

          {decision ? (
            <div className="rounded-md border border-emerald-300 bg-emerald-50 p-3 text-sm">
              <p className="font-medium">Resolved: {decision.resolution}</p>
              {decision.conditionsText && <p className="mt-1 text-muted-foreground">{decision.conditionsText}</p>}
            </div>
          ) : (
            <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-end">
              <Select value={vote} onValueChange={setVote}>
                <SelectTrigger className="w-full sm:w-56">
                  <SelectValue placeholder="Cast your vote *" />
                </SelectTrigger>
                <SelectContent>
                  {VOTE_OPTIONS.map((v) => (
                    <SelectItem key={v} value={v}>
                      {v}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {(needsConditions || needsRationale) && (
                <Textarea
                  className="sm:flex-1"
                  rows={2}
                  placeholder={needsConditions ? 'Conditions *' : 'Rationale *'}
                  value={text}
                  onChange={(e) => setText(e.target.value)}
                />
              )}
              <Button onClick={submitVote} disabled={submitting || !vote}>
                Submit vote
              </Button>
            </div>
          )}

          <div className="space-y-2 border-t pt-3">
            {(votes || []).map((v) => (
              <div key={v.id} className="flex items-center justify-between text-sm">
                <span>{v.committeeMemberName}</span>
                <div className="flex items-center gap-2">
                  {v.conditionsText && <span className="text-xs text-muted-foreground">{v.conditionsText}</span>}
                  {v.rationale && <span className="text-xs text-muted-foreground">{v.rationale}</span>}
                  <Badge variant="secondary">{v.vote}</Badge>
                </div>
              </div>
            ))}
            {(!votes || votes.length === 0) && <p className="text-sm text-muted-foreground">No votes yet.</p>}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// US-8.1/US-8.2/US-8.3.
export default function CommitteeQueue() {
  const { query, toggleSort, setFilter, setPage } = useGridQuery({ sortBy: 'routedAt', sortDir: 'asc' })
  const debouncedSearch = useDebouncedValue(query.search)
  const { data, loading } = useFetch(Endpoints.committee.queue({ ...query, search: debouncedSearch }))
  const [selected, setSelected] = useState(null)

  if (selected) return <VotePanel item={selected} onBack={() => setSelected(null)} />

  const queue = data?.items

  return (
    <Card>
      <CardHeader>
        <CardTitle>Committee queue</CardTitle>
        <CardDescription>Finalized assessments routed for a decision.</CardDescription>
      </CardHeader>
      <CardContent>
        <div className="mb-4 flex flex-wrap items-center gap-2">
          <Input
            placeholder="Search title or request #…"
            className="w-full sm:w-64"
            value={query.search}
            onChange={(e) => setFilter('search', e.target.value)}
          />
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
        {!loading && (!queue || queue.length === 0) && <p className="text-sm text-muted-foreground">Nothing in the queue right now.</p>}
        {queue?.length > 0 && (
          <>
            <Table className="table-fixed">
              <colgroup>
                <col className="w-28" />
                <col className="w-24" />
                <col />
                <col className="w-36" />
                <col className="w-24" />
              </colgroup>
              <TableHeader>
                <TableRow>
                  <SortableHeader column="requestNumber" label="Request #" query={query} onSort={toggleSort} />
                  <SortableHeader column="changeType" label="Type" query={query} onSort={toggleSort} />
                  <SortableHeader column="title" label="Title" query={query} onSort={toggleSort} />
                  <TableHead>Decision due</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {queue.map((q) => (
                  <TableRow key={q.assessmentId}>
                    <TableCell className="whitespace-normal break-words font-medium">{q.requestNumber}</TableCell>
                    <TableCell className="whitespace-normal break-words">{q.changeType}</TableCell>
                    <TableCell>
                      <ClampedText text={q.title} />
                    </TableCell>
                    <TableCell className="whitespace-normal">
                      {q.dueAt && <p className="text-sm">{formatDate(q.dueAt)}</p>}
                      <SlaBadge state={q.slaState} />
                    </TableCell>
                    <TableCell>
                      <Button size="sm" onClick={() => setSelected(q)}>
                        Review
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
