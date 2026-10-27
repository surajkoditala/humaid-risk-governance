import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Endpoints } from '../lib/api.js'
import { useFetch } from '../lib/useFetch.js'

const STEP_LABEL = {
  category_mapping: 'Category mapping',
  document_extraction: 'Document extraction',
  narrative_drafting: 'Narrative drafting',
}

// A count the provider did not report is null, and shown as a dash - never as 0.
const count = (v) => (v == null ? '—' : Number(v).toLocaleString())
const seconds = (ms) => (ms == null ? '—' : `${(ms / 1000).toFixed(1)} s`)

// Measured token use for one change request: every AI call made while preparing it and the exact
// token counts the provider reported (the same figures it bills on), plus totals. Informational -
// it never gates or decides anything. Rows are appended by the AI clients as they make calls.
export default function AiUsageCard({ changeRequestId }) {
  const { data: usage, loading, error } = useFetch(Endpoints.aiUsage.forRequest(changeRequestId), [changeRequestId])
  const calls = usage?.calls || []

  return (
    <Card>
      <CardHeader>
        <CardTitle>AI usage</CardTitle>
        <CardDescription>
          Tokens the AI provider reported for each AI step on this request. Counts are exact, not estimated.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {loading && <p className="text-sm text-muted-foreground">Loading…</p>}
        {!loading && error && <p className="text-sm text-destructive">Failed to load AI usage: {error}</p>}
        {!loading && !error && calls.length === 0 && (
          <p className="text-sm text-muted-foreground">No AI calls recorded for this request yet.</p>
        )}
        {calls.length > 0 && (
          <>
            <p className="text-sm">
              <strong>{usage.callCount}</strong> AI {usage.callCount === 1 ? 'call' : 'calls'} ·{' '}
              <strong>{count(usage.inputTokens)}</strong> input · <strong>{count(usage.outputTokens)}</strong> output tokens
              {(usage.cacheReadTokens > 0 || usage.cacheCreationTokens > 0) && (
                <span className="text-muted-foreground">
                  {' '}
                  (cache read {count(usage.cacheReadTokens)}, cache write {count(usage.cacheCreationTokens)})
                </span>
              )}
            </p>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>When</TableHead>
                  <TableHead>Step</TableHead>
                  <TableHead>Model</TableHead>
                  <TableHead className="text-right">Input</TableHead>
                  <TableHead className="text-right">Output</TableHead>
                  <TableHead className="text-right">Cache read</TableHead>
                  <TableHead className="text-right">Time</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {calls.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="whitespace-nowrap text-xs text-muted-foreground">
                      {new Date(c.createdAt).toLocaleString()}
                    </TableCell>
                    <TableCell>{STEP_LABEL[c.operation] || c.operation}</TableCell>
                    <TableCell className="text-xs text-muted-foreground">{c.model || '—'}</TableCell>
                    <TableCell className="text-right tabular-nums">{count(c.inputTokens)}</TableCell>
                    <TableCell className="text-right tabular-nums">{count(c.outputTokens)}</TableCell>
                    <TableCell className="text-right tabular-nums">{count(c.cacheReadTokens)}</TableCell>
                    <TableCell className="text-right tabular-nums">{seconds(c.durationMs)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </>
        )}
      </CardContent>
    </Card>
  )
}
