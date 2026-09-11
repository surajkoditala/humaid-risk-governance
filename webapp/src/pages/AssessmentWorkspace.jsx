import { useEffect, useState } from 'react'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints, apiFetch } from '../lib/api.js'
import { useFetch } from '../lib/useFetch.js'

const NARRATIVE_STATUS_LABEL = {
  AiDrafted: 'AI-drafted — pending analyst review',
  AnalystReviewed: 'Analyst reviewed',
  AnalystEdited: 'Analyst edited',
}

function ErrorNote({ error }) {
  if (!error) return null
  return <p className="rounded-md bg-amber-50 p-3 text-sm text-amber-900">{error}</p>
}

// ---- Categories tab (Epic 2) ------------------------------------------------------------------
function CategoriesTab({ assessmentId, changeRequest, bump }) {
  const { currentUser } = useDevUser()
  const { data: mapping, error: proposeAiError } = useFetch(
    assessmentId ? Endpoints.categoryMapping.get(assessmentId) : null,
    [assessmentId, bump],
  )
  const { data: allCategories } = useFetch(Endpoints.categoryMapping.categories())
  const [proposing, setProposing] = useState(false)
  const [proposeError, setProposeError] = useState(null)
  const [addCategoryId, setAddCategoryId] = useState('')
  const [reason, setReason] = useState('')

  const propose = async () => {
    setProposing(true)
    setProposeError(null)
    try {
      await apiFetch(Endpoints.categoryMapping.propose(assessmentId, changeRequest.id), { method: 'POST' })
      toast.success('AI proposal saved')
    } catch (err) {
      setProposeError(err.message)
    } finally {
      setProposing(false)
      bump()
    }
  }

  const override = async (riskCategoryId, isActive) => {
    if (!reason.trim()) {
      toast.error('A reason is required to add or remove a category (Epic 6).')
      return
    }
    try {
      await apiFetch(Endpoints.categoryMapping.override(), {
        method: 'POST',
        body: { assessmentId, riskCategoryId, isActive, reason, actorUserId: currentUser.id },
      })
      setReason('')
      setAddCategoryId('')
      bump()
    } catch (err) {
      toast.error(err.message)
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>AI-proposed categories</CardTitle>
          <CardDescription>US-2.1 — grounded against this change type's FFIEC categories.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <Button onClick={propose} disabled={proposing}>
            {proposing ? 'Proposing…' : 'Propose with AI'}
          </Button>
          <ErrorNote error={proposeError} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Mapped categories</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            {(mapping || []).filter((m) => m.isActive).map((m) => (
              <div key={m.id} className="flex items-center justify-between rounded-md border p-3">
                <div>
                  <p className="text-sm font-medium">{m.categoryName}</p>
                  <p className="text-xs text-muted-foreground">
                    {m.source === 'AiProposed' ? `AI — ${m.aiCitation || m.citationSection}` : 'Analyst added'}
                  </p>
                </div>
                <Button size="sm" variant="outline" onClick={() => override(m.riskCategoryId, false)}>
                  Remove
                </Button>
              </div>
            ))}
            {(!mapping || mapping.filter((m) => m.isActive).length === 0) && (
              <p className="text-sm text-muted-foreground">No categories mapped yet.</p>
            )}
          </div>

          <div className="space-y-2 border-t pt-4">
            <Label>Add a category (reason required — Epic 6)</Label>
            <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
              <Select value={addCategoryId} onValueChange={setAddCategoryId}>
                <SelectTrigger className="w-full sm:w-64">
                  <SelectValue placeholder="Select category">
                    {allCategories?.find((c) => c.id === addCategoryId)?.name}
                  </SelectValue>
                </SelectTrigger>
                <SelectContent>
                  {(allCategories || []).map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Input placeholder="Reason" value={reason} onChange={(e) => setReason(e.target.value)} className="sm:flex-1" />
              <Button variant="outline" disabled={!addCategoryId} onClick={() => override(addCategoryId, true)}>
                Add
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// ---- Policy tab (Epic 3) -----------------------------------------------------------------------
function PolicyTab({ assessmentId, mapping, bump }) {
  const { currentUser } = useDevUser()
  const { data: reliance } = useFetch(assessmentId ? Endpoints.policyResearch.reliance(assessmentId) : null, [assessmentId, bump])
  const [query, setQuery] = useState('')
  const [results, setResults] = useState(null)
  const [searching, setSearching] = useState(false)
  const [categoryId, setCategoryId] = useState('')

  const search = async () => {
    if (!query.trim()) return
    setSearching(true)
    try {
      setResults(await apiFetch(Endpoints.policyResearch.search(query, categoryId || null)))
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSearching(false)
    }
  }

  const decide = async (policyChunkId, decision) => {
    try {
      await apiFetch(Endpoints.policyResearch.recordReliance(), {
        method: 'POST',
        body: { assessmentId, riskCategoryId: categoryId || null, policyChunkId, decision, decidedByUserId: currentUser.id },
      })
      toast.success(`Marked ${decision}`)
      bump()
    } catch (err) {
      toast.error(err.message)
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Search the policy corpus</CardTitle>
          <CardDescription>Deterministic full-text search — not an LLM call (see docs/governance).</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
            <Select value={categoryId} onValueChange={setCategoryId}>
              <SelectTrigger className="w-full sm:w-56">
                <SelectValue placeholder="Any category">
                  {mapping?.find((m) => m.riskCategoryId === categoryId)?.categoryName}
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                {(mapping || []).filter((m) => m.isActive).map((m) => (
                  <SelectItem key={m.riskCategoryId} value={m.riskCategoryId}>
                    {m.categoryName}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Input
              className="sm:flex-1"
              placeholder="e.g. beneficial ownership, correspondent banking…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && search()}
            />
            <Button onClick={search} disabled={searching}>
              {searching ? 'Searching…' : 'Search'}
            </Button>
          </div>

          <div className="space-y-2">
            {(results || []).map((r) => (
              <div key={r.id} className="rounded-md border p-3">
                <p className="text-xs font-medium text-muted-foreground">{r.sectionRef}</p>
                <p className="mt-1 text-sm">{r.chunkText}</p>
                <div className="mt-2 flex gap-2">
                  <Button size="sm" variant="outline" onClick={() => decide(r.id, 'ReliedUpon')}>
                    Relied upon
                  </Button>
                  <Button size="sm" variant="ghost" onClick={() => decide(r.id, 'NotRelevant')}>
                    Not relevant
                  </Button>
                </div>
              </div>
            ))}
            {results && results.length === 0 && <p className="text-sm text-muted-foreground">No matches.</p>}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Reliance decisions recorded</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {(reliance || []).map((r) => (
            <div key={r.id} className="flex items-center justify-between text-sm">
              <span>{r.sectionRef}</span>
              <Badge variant={r.decision === 'ReliedUpon' ? 'default' : 'secondary'}>{r.decision}</Badge>
            </div>
          ))}
          {(!reliance || reliance.length === 0) && <p className="text-sm text-muted-foreground">None yet.</p>}
        </CardContent>
      </Card>
    </div>
  )
}

// ---- Extraction tab (Epic 4) --------------------------------------------------------------------
function ExtractionTab({ changeRequest, bump }) {
  const { data: attachments } = useFetch(Endpoints.changeRequests.attachments(changeRequest.id), [bump])
  const { data: fields, error: extractError } = useFetch(Endpoints.documentExtraction.fields(changeRequest.id), [bump])
  const [extracting, setExtracting] = useState(null)
  const [localError, setLocalError] = useState(null)
  const [correcting, setCorrecting] = useState({})

  const extract = async (attachment) => {
    setExtracting(attachment.id)
    setLocalError(null)
    try {
      await apiFetch(Endpoints.documentExtraction.extract(), {
        method: 'POST',
        body: { changeRequestId: changeRequest.id, attachmentId: attachment.id, changeType: changeRequest.changeType, documentText: attachment.fileName },
      })
      toast.success('Extraction complete')
    } catch (err) {
      setLocalError(err.message)
    } finally {
      setExtracting(null)
      bump()
    }
  }

  const correct = async (fieldKey) => {
    const newValue = correcting[fieldKey]
    if (!newValue) return
    try {
      await apiFetch(Endpoints.documentExtraction.correct(), {
        method: 'POST',
        body: { input: { changeRequestId: changeRequest.id, fieldKey, newValue, reason: 'Analyst correction' }, isMaterialChange: true },
      })
      toast.success('Field corrected')
      bump()
    } catch (err) {
      toast.error(err.message)
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Attachments</CardTitle>
          <CardDescription>US-4.1 — extract structured facts from each document's text.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {(attachments || []).map((a) => (
            <div key={a.id} className="flex items-center justify-between rounded-md border p-3">
              <span className="text-sm">{a.fileName} (v{a.versionNumber})</span>
              <Button size="sm" onClick={() => extract(a)} disabled={extracting === a.id}>
                {extracting === a.id ? 'Extracting…' : 'Extract with AI'}
              </Button>
            </div>
          ))}
          {(!attachments || attachments.length === 0) && <p className="text-sm text-muted-foreground">No attachments yet — add one from Submit Request.</p>}
          <ErrorNote error={localError || extractError} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Extracted fields</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {(fields || []).map((f) => (
            <div key={f.id} className="rounded-md border p-3">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">{f.fieldKey}</span>
                <div className="flex items-center gap-2">
                  {f.needsReview && <Badge variant="destructive">Needs review</Badge>}
                  <Badge variant="secondary">{f.source}</Badge>
                </div>
              </div>
              <p className="mt-1 text-sm text-muted-foreground">{f.fieldValue || '(empty)'}</p>
              <div className="mt-2 flex gap-2">
                <Input
                  placeholder="Corrected value"
                  className="flex-1"
                  value={correcting[f.fieldKey] || ''}
                  onChange={(e) => setCorrecting((c) => ({ ...c, [f.fieldKey]: e.target.value }))}
                />
                <Button size="sm" variant="outline" onClick={() => correct(f.fieldKey)}>
                  Correct
                </Button>
              </div>
            </div>
          ))}
          {(!fields || fields.length === 0) && <p className="text-sm text-muted-foreground">Nothing extracted yet.</p>}
        </CardContent>
      </Card>
    </div>
  )
}

// ---- Narrative tab (Epic 5) ---------------------------------------------------------------------
function NarrativeTab({ assessmentId, mapping, bump }) {
  const { currentUser } = useDevUser()
  const { data: sections, error: draftError } = useFetch(assessmentId ? Endpoints.narrative.sections(assessmentId) : null, [assessmentId, bump])
  const [drafting, setDrafting] = useState(null)
  const [localError, setLocalError] = useState(null)
  const [editText, setEditText] = useState({})
  const [editReason, setEditReason] = useState({})

  const draft = async (riskCategoryId, feedback) => {
    setDrafting(riskCategoryId)
    setLocalError(null)
    try {
      await apiFetch(Endpoints.narrative.draft(), { method: 'POST', body: { assessmentId, riskCategoryId, regenerationFeedback: feedback || null } })
      toast.success('Narrative drafted')
    } catch (err) {
      setLocalError(err.message)
    } finally {
      setDrafting(null)
      bump()
    }
  }

  const review = async (riskCategoryId) => {
    await apiFetch(Endpoints.narrative.review(), { method: 'POST', body: { assessmentId, riskCategoryId, actorUserId: currentUser.id } })
    bump()
  }

  const edit = async (riskCategoryId) => {
    const reason = editReason[riskCategoryId]
    const newText = editText[riskCategoryId]
    if (!reason || !newText) {
      toast.error('New text and a reason are both required.')
      return
    }
    try {
      await apiFetch(Endpoints.narrative.edit(), { method: 'POST', body: { assessmentId, riskCategoryId, newText, reason, actorUserId: currentUser.id } })
      toast.success('Narrative edited')
      bump()
    } catch (err) {
      toast.error(err.message)
    }
  }

  return (
    <div className="space-y-4">
      <ErrorNote error={localError || draftError} />
      {(mapping || []).filter((m) => m.isActive).map((m) => {
        const section = (sections || []).find((s) => s.riskCategoryId === m.riskCategoryId)
        return (
          <Card key={m.riskCategoryId}>
            <CardHeader>
              <div className="flex items-center justify-between">
                <CardTitle className="text-base">{m.categoryName}</CardTitle>
                {section && <Badge variant={section.status === 'AiDrafted' ? 'destructive' : 'default'}>{NARRATIVE_STATUS_LABEL[section.status]}</Badge>}
              </div>
            </CardHeader>
            <CardContent className="space-y-3">
              {section ? <p className="text-sm">{section.narrativeText}</p> : <p className="text-sm text-muted-foreground">Not drafted yet.</p>}
              <div className="flex gap-2">
                <Button size="sm" onClick={() => draft(m.riskCategoryId)} disabled={drafting === m.riskCategoryId}>
                  {section ? 'Regenerate' : 'Draft'} with AI
                </Button>
                {section && section.status === 'AiDrafted' && (
                  <Button size="sm" variant="outline" onClick={() => review(m.riskCategoryId)}>
                    Accept as-is
                  </Button>
                )}
              </div>
              {section && (
                <div className="space-y-2 border-t pt-3">
                  <Textarea
                    rows={2}
                    placeholder="Edited narrative text"
                    value={editText[m.riskCategoryId] || ''}
                    onChange={(e) => setEditText((c) => ({ ...c, [m.riskCategoryId]: e.target.value }))}
                  />
                  <div className="flex gap-2">
                    <Input
                      placeholder="Reason for edit"
                      className="flex-1"
                      value={editReason[m.riskCategoryId] || ''}
                      onChange={(e) => setEditReason((c) => ({ ...c, [m.riskCategoryId]: e.target.value }))}
                    />
                    <Button size="sm" variant="outline" onClick={() => edit(m.riskCategoryId)}>
                      Save edit
                    </Button>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        )
      })}
      {(!mapping || mapping.filter((m) => m.isActive).length === 0) && (
        <p className="text-sm text-muted-foreground">Map a risk category first (Categories tab).</p>
      )}
    </div>
  )
}

// ---- Scoring tab (Epic 7) -----------------------------------------------------------------------
function ScoringTab({ assessmentId, mapping, bump }) {
  const { currentUser } = useDevUser()
  const { data: scores, error: calcError } = useFetch(assessmentId ? Endpoints.scoring.scores(assessmentId) : null, [assessmentId, bump])
  const [form, setForm] = useState({})
  const [overrideForm, setOverrideForm] = useState({})
  const [localError, setLocalError] = useState(null)

  const calculate = async (riskCategoryId) => {
    const f = form[riskCategoryId] || {}
    setLocalError(null)
    try {
      await apiFetch(Endpoints.scoring.calculate(), {
        method: 'POST',
        body: {
          assessmentId,
          riskCategoryId,
          inherentRating: Number(f.inherentRating || 3),
          controlIdsCredited: [],
          controlEffectiveness: Number(f.controlEffectiveness || 0.5),
        },
      })
      toast.success('Score calculated')
    } catch (err) {
      setLocalError(err.message)
    } finally {
      bump()
    }
  }

  const override = async (riskCategoryId) => {
    const f = overrideForm[riskCategoryId] || {}
    if (!f.reason || !f.newResidualRating) {
      toast.error('New residual rating and a reason are both required.')
      return
    }
    try {
      await apiFetch(Endpoints.scoring.override(), {
        method: 'POST',
        body: { assessmentId, riskCategoryId, newResidualRating: Number(f.newResidualRating), reason: f.reason, actorUserId: currentUser.id },
      })
      toast.success('Score overridden')
      bump()
    } catch (err) {
      toast.error(err.message)
    }
  }

  return (
    <div className="space-y-4">
      <ErrorNote error={localError || calcError} />
      {(mapping || []).filter((m) => m.isActive).map((m) => {
        const score = (scores || []).find((s) => s.riskCategoryId === m.riskCategoryId)
        return (
          <Card key={m.riskCategoryId}>
            <CardHeader>
              <CardTitle className="text-base">{m.categoryName}</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {score ? (
                <div className="flex flex-wrap gap-4 text-sm">
                  <span>Inherent: <strong>{score.inherentRating}</strong></span>
                  <span>Mitigation: {score.mitigationFactorApplied}</span>
                  <span>Residual: <strong>{score.residualRating}</strong></span>
                  {score.isOverride && <Badge variant="secondary">Analyst override</Badge>}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">Not scored yet.</p>
              )}

              <div className="flex flex-wrap items-end gap-2 border-t pt-3">
                <div className="space-y-1">
                  <Label className="text-xs">Inherent (1-5)</Label>
                  <Input
                    className="w-24"
                    type="number"
                    min={1}
                    max={5}
                    value={form[m.riskCategoryId]?.inherentRating || ''}
                    onChange={(e) => setForm((c) => ({ ...c, [m.riskCategoryId]: { ...c[m.riskCategoryId], inherentRating: e.target.value } }))}
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs">Control effectiveness (0-1)</Label>
                  <Input
                    className="w-32"
                    type="number"
                    step="0.05"
                    min={0}
                    max={1}
                    value={form[m.riskCategoryId]?.controlEffectiveness || ''}
                    onChange={(e) => setForm((c) => ({ ...c, [m.riskCategoryId]: { ...c[m.riskCategoryId], controlEffectiveness: e.target.value } }))}
                  />
                </div>
                <Button size="sm" onClick={() => calculate(m.riskCategoryId)}>
                  Calculate
                </Button>
              </div>

              <div className="flex flex-wrap items-end gap-2 border-t pt-3">
                <div className="space-y-1">
                  <Label className="text-xs">Override residual</Label>
                  <Input
                    className="w-28"
                    type="number"
                    step="0.1"
                    value={overrideForm[m.riskCategoryId]?.newResidualRating || ''}
                    onChange={(e) => setOverrideForm((c) => ({ ...c, [m.riskCategoryId]: { ...c[m.riskCategoryId], newResidualRating: e.target.value } }))}
                  />
                </div>
                <Input
                  placeholder="Reason"
                  className="flex-1"
                  value={overrideForm[m.riskCategoryId]?.reason || ''}
                  onChange={(e) => setOverrideForm((c) => ({ ...c, [m.riskCategoryId]: { ...c[m.riskCategoryId], reason: e.target.value } }))}
                />
                <Button size="sm" variant="outline" onClick={() => override(m.riskCategoryId)}>
                  Override
                </Button>
              </div>
            </CardContent>
          </Card>
        )
      })}
    </div>
  )
}

// ---- Finalize tab (Epic 6/8) --------------------------------------------------------------------
function FinalizeTab({ assessmentId, assessment, bump }) {
  const { currentUser } = useDevUser()
  const { data: readiness } = useFetch(assessmentId ? Endpoints.assessment.readiness(assessmentId) : null, [assessmentId, bump])
  const [busy, setBusy] = useState(false)

  const finalize = async () => {
    setBusy(true)
    try {
      await apiFetch(Endpoints.assessment.finalize(assessmentId), { method: 'POST', body: { actorUserId: currentUser.id } })
      toast.success('Assessment finalized')
    } catch (err) {
      toast.error(err.message)
    } finally {
      setBusy(false)
      bump()
    }
  }

  const route = async () => {
    setBusy(true)
    try {
      await apiFetch(Endpoints.committee.route(), { method: 'POST', body: { assessmentId, actorUserId: currentUser.id } })
      toast.success('Routed to committee')
    } catch (err) {
      toast.error(err.message)
    } finally {
      setBusy(false)
      bump()
    }
  }

  const isFinalized = assessment?.status === 'Finalized'

  return (
    <Card>
      <CardHeader>
        <CardTitle>Readiness</CardTitle>
        <CardDescription>US-6.3 — everything must be reviewed before this can move on.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {readiness?.outstandingNarrativeSections?.length > 0 && (
          <p className="text-sm text-amber-700">Narrative not reviewed: {readiness.outstandingNarrativeSections.join(', ')}</p>
        )}
        {readiness?.categoriesMissingPolicyReliance?.length > 0 && (
          <p className="text-sm text-amber-700">No policy reviewed: {readiness.categoriesMissingPolicyReliance.join(', ')}</p>
        )}
        {readiness?.isReady && <p className="text-sm text-emerald-700">Ready to finalize.</p>}

        <div className="flex gap-2">
          <Button onClick={finalize} disabled={busy || isFinalized || !readiness?.isReady}>
            {isFinalized ? 'Finalized' : 'Finalize'}
          </Button>
          <Button variant="outline" onClick={route} disabled={busy || !isFinalized}>
            Route to committee
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

// ---- Audit tab (Epic 9) -------------------------------------------------------------------------
function AuditTab({ changeRequest, bump }) {
  const { data: trail } = useFetch(Endpoints.audit.trail(changeRequest.id), [bump])
  return (
    <Card>
      <CardHeader>
        <CardTitle>Audit trail</CardTitle>
        <CardDescription>US-9.1 — every AI output, human edit, and reason, in order.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-2">
        {(trail || []).map((e) => (
          <div key={e.id} className="border-b pb-2 text-sm last:border-0">
            <span className="text-xs text-muted-foreground">{new Date(e.createdAt).toLocaleString()}</span>{' '}
            <strong>{e.entityType}.{e.action}</strong> by {e.actorName || e.actorLabel}
            {e.reason && <span className="text-muted-foreground"> — {e.reason}</span>}
          </div>
        ))}
        {(!trail || trail.length === 0) && <p className="text-sm text-muted-foreground">No events yet.</p>}
      </CardContent>
    </Card>
  )
}

// ---- Shell ---------------------------------------------------------------------------------------
export default function AssessmentWorkspace({ changeRequest, onBack }) {
  const [assessmentId, setAssessmentId] = useState(null)
  const [bump, setBumpValue] = useState(0)
  const bumpFn = () => setBumpValue((v) => v + 1)

  const { data: mapping } = useFetch(assessmentId ? Endpoints.categoryMapping.get(assessmentId) : null, [assessmentId, bump])
  const { data: assessment } = useFetch(Endpoints.assessment.byChangeRequest(changeRequest.id), [bump])

  useEffect(() => {
    apiFetch(Endpoints.assessment.openWorkspace(changeRequest.id), { method: 'POST' }).then(setAssessmentId)
  }, [changeRequest.id])

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="min-w-0">
          <Button variant="ghost" size="sm" onClick={onBack}>
            ← Back to inbox
          </Button>
          <h2 className="text-lg font-semibold break-words">{changeRequest.requestNumber} — {changeRequest.title}</h2>
        </div>
        {assessment && <Badge>{assessment.status}</Badge>}
      </div>

      {!assessmentId ? (
        <p className="text-sm text-muted-foreground">Opening workspace…</p>
      ) : (
        <Tabs defaultValue="categories">
          <div className="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
            <TabsList className="w-max min-w-full sm:w-fit">
              <TabsTrigger value="categories">Categories</TabsTrigger>
              <TabsTrigger value="policy">Policy</TabsTrigger>
              <TabsTrigger value="extraction">Extraction</TabsTrigger>
              <TabsTrigger value="narrative">Narrative</TabsTrigger>
              <TabsTrigger value="scoring">Scoring</TabsTrigger>
              <TabsTrigger value="finalize">Finalize</TabsTrigger>
              <TabsTrigger value="audit">Audit</TabsTrigger>
            </TabsList>
          </div>
          <TabsContent value="categories">
            <CategoriesTab assessmentId={assessmentId} changeRequest={changeRequest} bump={bumpFn} />
          </TabsContent>
          <TabsContent value="policy">
            <PolicyTab assessmentId={assessmentId} mapping={mapping} bump={bumpFn} />
          </TabsContent>
          <TabsContent value="extraction">
            <ExtractionTab changeRequest={changeRequest} bump={bumpFn} />
          </TabsContent>
          <TabsContent value="narrative">
            <NarrativeTab assessmentId={assessmentId} mapping={mapping} bump={bumpFn} />
          </TabsContent>
          <TabsContent value="scoring">
            <ScoringTab assessmentId={assessmentId} mapping={mapping} bump={bumpFn} />
          </TabsContent>
          <TabsContent value="finalize">
            <FinalizeTab assessmentId={assessmentId} assessment={assessment} bump={bumpFn} />
          </TabsContent>
          <TabsContent value="audit">
            <AuditTab changeRequest={changeRequest} bump={bumpFn} />
          </TabsContent>
        </Tabs>
      )}
    </div>
  )
}
