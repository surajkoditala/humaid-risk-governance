import { useState } from 'react'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Textarea } from '@/components/ui/textarea'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints, apiFetch } from '../lib/api.js'
import { useFetch } from '../lib/useFetch.js'

const VOTE_OPTIONS = ['Approve', 'ApproveWithConditions', 'Defer', 'Reject']

function VotePanel({ item, onBack }) {
  const { currentUser } = useDevUser()
  const [bump, setBump] = useState(0)
  const { data: votes } = useFetch(Endpoints.committee.votes(item.assessmentId), [bump])
  const { data: decision } = useFetch(Endpoints.committee.decision(item.assessmentId), [bump])
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
          <CardDescription>US-8.2 — every member's vote is recorded individually, never anonymized.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {decision ? (
            <div className="rounded-md border border-emerald-300 bg-emerald-50 p-3 text-sm">
              <p className="font-medium">Resolved: {decision.resolution}</p>
              {decision.conditionsText && <p className="mt-1 text-muted-foreground">{decision.conditionsText}</p>}
            </div>
          ) : (
            <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-end">
              <Select value={vote} onValueChange={setVote}>
                <SelectTrigger className="w-full sm:w-56">
                  <SelectValue placeholder="Cast your vote" />
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
                  placeholder={needsConditions ? 'Conditions' : 'Rationale'}
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
  const { data: queue, loading } = useFetch(Endpoints.committee.queue())
  const [selected, setSelected] = useState(null)

  if (selected) return <VotePanel item={selected} onBack={() => setSelected(null)} />

  return (
    <Card>
      <CardHeader>
        <CardTitle>Committee queue</CardTitle>
        <CardDescription>Finalized assessments routed for a decision.</CardDescription>
      </CardHeader>
      <CardContent>
        {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
        {!loading && (!queue || queue.length === 0) && <p className="text-sm text-muted-foreground">Nothing in the queue right now.</p>}
        {queue?.length > 0 && (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Request #</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Title</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {queue.map((q) => (
                <TableRow key={q.assessmentId}>
                  <TableCell className="font-medium">{q.requestNumber}</TableCell>
                  <TableCell>{q.changeType}</TableCell>
                  <TableCell>{q.title}</TableCell>
                  <TableCell>
                    <Button size="sm" onClick={() => setSelected(q)}>
                      Review
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}
