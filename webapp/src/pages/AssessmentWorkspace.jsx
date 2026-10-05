import { useEffect, useState } from 'react'
import { useAuth0 } from '@auth0/auth0-react'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Button, buttonVariants } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Textarea } from '@/components/ui/textarea'
import { isAuth0Configured } from '../auth/authConfig.js'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { RequiredMark } from '../components/RequiredMark.jsx'
import SlaStrip from '../components/SlaStrip.jsx'
import { Endpoints, apiFetch, downloadFile } from '../lib/api.js'
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
function CategoriesTab({ assessmentId, changeRequest, bump, isFinalized }) {
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
  // DEF-034: each mapped row removes with its own reason - a single shared `reason` field (meant
  // for the Add form below) made Remove silently reuse whatever the Add box happened to hold,
  // which was empty in the normal case since there's no reason input next to Remove itself.
  const [removeReasons, setRemoveReasons] = useState({})

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

  const override = async (riskCategoryId, isActive, reasonText) => {
    if (!reasonText.trim()) {
      toast.error('A reason is required to add or remove a category.')
      return
    }
    try {
      await apiFetch(Endpoints.categoryMapping.override(), {
        method: 'POST',
        body: { assessmentId, riskCategoryId, isActive, reason: reasonText, actorUserId: currentUser.id },
      })
      setReason('')
      setAddCategoryId('')
      setRemoveReasons((prev) => ({ ...prev, [riskCategoryId]: '' }))
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
          <CardDescription>Only categories that apply to this type of change can be proposed.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <Button onClick={propose} disabled={proposing || isFinalized}>
            {proposing ? 'Proposing…' : 'Propose with AI'}
          </Button>
          {isFinalized && <p className="text-xs text-muted-foreground">Finalized — categories are locked.</p>}
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
              <div key={m.id} className="flex flex-col gap-2 rounded-md border p-3 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <p className="text-sm font-medium">{m.categoryName}</p>
                  <p className="text-xs text-muted-foreground">
                    {m.source === 'AiProposed'
                      ? `AI — ${m.aiCitation || m.citationSection}`
                      : `Analyst added${m.analystReason ? ` — ${m.analystReason}` : ''}`}
                  </p>
                </div>
                <div className="flex gap-2">
                  <Input
                    placeholder="Reason for removing *"
                    value={removeReasons[m.riskCategoryId] || ''}
                    onChange={(e) => setRemoveReasons((prev) => ({ ...prev, [m.riskCategoryId]: e.target.value }))}
                    className="sm:w-56"
                  />
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={isFinalized}
                    onClick={() => override(m.riskCategoryId, false, removeReasons[m.riskCategoryId] || '')}
                  >
                    Remove
                  </Button>
                </div>
              </div>
            ))}
            {(!mapping || mapping.filter((m) => m.isActive).length === 0) && (
              <p className="text-sm text-muted-foreground">No categories mapped yet.</p>
            )}
          </div>

          <div className="space-y-2 border-t pt-4">
            <Label>
              Add a category
              <RequiredMark />
            </Label>
            <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
              <Select value={addCategoryId} onValueChange={setAddCategoryId}>
                <SelectTrigger className="w-full sm:w-64">
                  <SelectValue placeholder="Select category *">
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
              <Input placeholder="Reason *" value={reason} onChange={(e) => setReason(e.target.value)} className="sm:flex-1" />
              <Button variant="outline" disabled={!addCategoryId || isFinalized} onClick={() => override(addCategoryId, true, reason)}>
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
          <CardDescription>Search FFIEC policy excerpts by keyword.</CardDescription>
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
                <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
                  <p className="text-xs font-medium text-muted-foreground">
                    {r.documentTitle ? `${r.documentTitle} — ` : ''}
                    {r.sectionRef}
                  </p>
                  <span className="text-xs text-muted-foreground">Relevance rank: {r.rank?.toFixed?.(3) ?? r.rank}</span>
                </div>
                <p className="mt-1 text-sm">{r.chunkText}</p>
                <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                  {r.sourceUrl && (
                    <a href={r.sourceUrl} target="_blank" rel="noreferrer" className="underline underline-offset-2">
                      View source document
                    </a>
                  )}
                  {r.effectiveDate && <span>Effective {new Date(r.effectiveDate).toLocaleDateString()}</span>}
                </div>
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
  const { currentUser } = useDevUser()
  const { data: attachments } = useFetch(Endpoints.changeRequests.attachments(changeRequest.id), [bump])
  const { data: fields, error: extractError } = useFetch(Endpoints.documentExtraction.fields(changeRequest.id), [bump])
  const [extracting, setExtracting] = useState(null)
  const [localError, setLocalError] = useState(null)
  const [correcting, setCorrecting] = useState({})
  const [correctReason, setCorrectReason] = useState({})
  const [correctIsMaterial, setCorrectIsMaterial] = useState({})

  // DEF-020: extraction runs server-side against the attachment's own extracted text (looked up
  // by attachmentId) - the client no longer sends documentText at all.
  const extract = async (attachment) => {
    setExtracting(attachment.id)
    setLocalError(null)
    try {
      await apiFetch(Endpoints.documentExtraction.extract(), {
        method: 'POST',
        body: { changeRequestId: changeRequest.id, attachmentId: attachment.id, changeType: changeRequest.changeType },
      })
      toast.success('Extraction complete')
    } catch (err) {
      setLocalError(err.message)
    } finally {
      setExtracting(null)
      bump()
    }
  }

  // DEF-033/DEF-027: send the real actor (the API rejects Guid.Empty) and let the analyst state
  // why, required only for a material change - not a hard-coded reason/flag for every correction.
  const correct = async (fieldKey) => {
    const newValue = correcting[fieldKey]
    if (!newValue) return
    const isMaterialChange = correctIsMaterial[fieldKey] ?? true
    const reason = correctReason[fieldKey] || ''
    if (isMaterialChange && !reason.trim()) {
      toast.error('A reason is required for a material correction.')
      return
    }
    try {
      await apiFetch(Endpoints.documentExtraction.correct(), {
        method: 'POST',
        body: {
          input: { changeRequestId: changeRequest.id, fieldKey, newValue, reason: reason || null, actorUserId: currentUser.id },
          isMaterialChange,
        },
      })
      toast.success('Field corrected')
      setCorrecting((c) => ({ ...c, [fieldKey]: '' }))
      setCorrectReason((c) => ({ ...c, [fieldKey]: '' }))
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
          <CardDescription>Extract structured facts from each document's text.</CardDescription>
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
              <div className="mt-2 flex flex-col gap-2">
                <div className="flex gap-2">
                  <Input
                    placeholder="Corrected value *"
                    className="flex-1"
                    value={correcting[f.fieldKey] || ''}
                    onChange={(e) => setCorrecting((c) => ({ ...c, [f.fieldKey]: e.target.value }))}
                  />
                  <Button size="sm" variant="outline" onClick={() => correct(f.fieldKey)}>
                    Correct
                  </Button>
                </div>
                <div className="flex items-center gap-2">
                  <label className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <input
                      type="checkbox"
                      checked={correctIsMaterial[f.fieldKey] ?? true}
                      onChange={(e) => setCorrectIsMaterial((c) => ({ ...c, [f.fieldKey]: e.target.checked }))}
                    />
                    Material change (reason required)
                  </label>
                  <Input
                    placeholder={(correctIsMaterial[f.fieldKey] ?? true) ? 'Reason for this correction *' : 'Reason for this correction (optional)'}
                    className="h-8 flex-1 text-xs"
                    value={correctReason[f.fieldKey] || ''}
                    onChange={(e) => setCorrectReason((c) => ({ ...c, [f.fieldKey]: e.target.value }))}
                  />
                </div>
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
function NarrativeTab({ assessmentId, mapping, bump, isFinalized }) {
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
                <Button size="sm" onClick={() => draft(m.riskCategoryId)} disabled={drafting === m.riskCategoryId || isFinalized}>
                  {section ? 'Regenerate' : 'Draft'} with AI
                </Button>
                {section && section.status === 'AiDrafted' && (
                  <Button size="sm" variant="outline" disabled={isFinalized} onClick={() => review(m.riskCategoryId)}>
                    Accept as-is
                  </Button>
                )}
              </div>
              {section && (
                <div className="space-y-2 border-t pt-3">
                  <Textarea
                    rows={2}
                    placeholder="Edited narrative text *"
                    value={editText[m.riskCategoryId] || ''}
                    onChange={(e) => setEditText((c) => ({ ...c, [m.riskCategoryId]: e.target.value }))}
                    disabled={isFinalized}
                  />
                  <div className="flex gap-2">
                    <Input
                      placeholder="Reason for edit *"
                      className="flex-1"
                      value={editReason[m.riskCategoryId] || ''}
                      onChange={(e) => setEditReason((c) => ({ ...c, [m.riskCategoryId]: e.target.value }))}
                      disabled={isFinalized}
                    />
                    <Button size="sm" variant="outline" disabled={isFinalized} onClick={() => edit(m.riskCategoryId)}>
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

// DEF-013: the controls library was empty, so this always had nothing to offer; now that
// seed_controls.sql exists, let the analyst actually credit which controls applied (US-7.1 AC3).
function ControlsPicker({ riskCategoryId, selected, onChange, disabled }) {
  const { data: controls } = useFetch(Endpoints.scoring.controls(riskCategoryId), [riskCategoryId])
  if (!controls || controls.length === 0) return null

  const toggle = (controlId) => {
    const next = selected.includes(controlId) ? selected.filter((id) => id !== controlId) : [...selected, controlId]
    onChange(next)
  }

  return (
    <div className="space-y-1">
      <Label className="text-xs">Controls credited</Label>
      <div className="flex flex-col gap-1">
        {controls.map((c) => (
          <label key={c.id} className="flex items-start gap-1.5 text-xs">
            <input type="checkbox" className="mt-0.5" checked={selected.includes(c.id)} disabled={disabled} onChange={() => toggle(c.id)} />
            <span>
              {c.name}
              {c.description && <span className="text-muted-foreground"> — {c.description}</span>}
            </span>
          </label>
        ))}
      </div>
    </div>
  )
}

// ---- Scoring tab (Epic 7) -----------------------------------------------------------------------
function ScoringTab({ assessmentId, mapping, bump, isFinalized }) {
  const { currentUser } = useDevUser()
  const { data: scores, error: calcError } = useFetch(assessmentId ? Endpoints.scoring.scores(assessmentId) : null, [assessmentId, bump])
  const [form, setForm] = useState({})
  const [overrideForm, setOverrideForm] = useState({})
  const [controlSelections, setControlSelections] = useState({})
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
          controlIdsCredited: controlSelections[riskCategoryId] || [],
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
                  <Label className="text-xs">
                    Inherent (1-5)
                    <RequiredMark />
                  </Label>
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
                  <Label className="text-xs">
                    Control effectiveness (0-1)
                    <RequiredMark />
                  </Label>
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
                <Button size="sm" onClick={() => calculate(m.riskCategoryId)} disabled={isFinalized}>
                  Calculate
                </Button>
              </div>

              <ControlsPicker
                riskCategoryId={m.riskCategoryId}
                selected={controlSelections[m.riskCategoryId] || []}
                onChange={(next) => setControlSelections((c) => ({ ...c, [m.riskCategoryId]: next }))}
                disabled={isFinalized}
              />

              <div className="flex flex-wrap items-end gap-2 border-t pt-3">
                <div className="space-y-1">
                  <Label className="text-xs">
                    Override residual
                    <RequiredMark />
                  </Label>
                  <Input
                    className="w-28"
                    type="number"
                    step="0.1"
                    value={overrideForm[m.riskCategoryId]?.newResidualRating || ''}
                    onChange={(e) => setOverrideForm((c) => ({ ...c, [m.riskCategoryId]: { ...c[m.riskCategoryId], newResidualRating: e.target.value } }))}
                  />
                </div>
                <Input
                  placeholder="Reason *"
                  className="flex-1"
                  value={overrideForm[m.riskCategoryId]?.reason || ''}
                  onChange={(e) => setOverrideForm((c) => ({ ...c, [m.riskCategoryId]: { ...c[m.riskCategoryId], reason: e.target.value } }))}
                />
                <Button size="sm" variant="outline" disabled={isFinalized} onClick={() => override(m.riskCategoryId)}>
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
        <CardDescription>Everything must be reviewed before this can move on.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {readiness?.noCategoriesMapped && (
          <p className="text-sm text-amber-700">No risk categories are mapped yet (Categories tab).</p>
        )}
        {readiness?.outstandingNarrativeSections?.length > 0 && (
          <p className="text-sm text-amber-700">Narrative not reviewed: {readiness.outstandingNarrativeSections.join(', ')}</p>
        )}
        {readiness?.categoriesMissingPolicyReliance?.length > 0 && (
          <p className="text-sm text-amber-700">No policy reviewed: {readiness.categoriesMissingPolicyReliance.join(', ')}</p>
        )}
        {readiness?.categoriesMissingScore?.length > 0 && (
          <p className="text-sm text-amber-700">No score calculated: {readiness.categoriesMissingScore.join(', ')}</p>
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
// DEF-028: mirrors AuditExportService.SummarizeJson's "key=value, key=value" compaction so the
// on-screen trail and the PDF export show the same shape.
function summarizeAuditJson(json) {
  if (!json) return null
  try {
    const obj = JSON.parse(json)
    if (obj === null || typeof obj !== 'object') return String(obj)
    return Object.entries(obj)
      .map(([k, v]) => `${k}=${typeof v === 'object' ? JSON.stringify(v) : v}`)
      .join(', ')
  } catch {
    return json
  }
}

function AuditTab({ changeRequest, bump }) {
  const { data: trail } = useFetch(Endpoints.audit.trail(changeRequest.id), [bump])
  const { getAccessTokenSilently } = useAuth0()

  const handleExportPdf = async () => {
    try {
      // A plain <a href> can't attach a Bearer token, so this goes through the same auth path
      // as every other request instead - see downloadFile's comment in lib/api.js.
      const token = isAuth0Configured ? await getAccessTokenSilently() : null
      await downloadFile(
        Endpoints.audit.exportPdf(changeRequest.id),
        token,
        `audit-trail-${changeRequest.requestNumber}.pdf`,
      )
    } catch (err) {
      toast.error(err.message || 'Failed to export audit trail PDF.')
    }
  }

  return (
    <Card>
      <CardHeader className="flex-row items-start justify-between space-y-0">
        <div>
          <CardTitle>Audit trail</CardTitle>
          <CardDescription>Every AI output, human edit, and reason, in order.</CardDescription>
        </div>
        <button
          type="button"
          onClick={handleExportPdf}
          className={buttonVariants({ variant: 'outline', size: 'sm' })}
        >
          Export PDF
        </button>
      </CardHeader>
      <CardContent className="space-y-2">
        {(trail || []).map((e) => {
          const before = summarizeAuditJson(e.beforeValueJson)
          const after = summarizeAuditJson(e.afterValueJson)
          return (
            <div key={e.id} className="border-b pb-2 text-sm last:border-0">
              <span className="text-xs text-muted-foreground">{new Date(e.createdAt).toLocaleString()}</span>{' '}
              <strong>{e.entityType}.{e.action}</strong> by {e.actorName || e.actorLabel}
              {e.reason && <span className="text-muted-foreground"> — {e.reason}</span>}
              {(before || after) && (
                <details className="mt-1">
                  <summary className="cursor-pointer text-xs text-muted-foreground">What changed</summary>
                  <div className="mt-1 space-y-0.5 pl-3 text-xs">
                    {before && <p><span className="text-muted-foreground">Before:</span> {before}</p>}
                    {after && <p><span className="text-muted-foreground">After:</span> {after}</p>}
                  </div>
                </details>
              )}
            </div>
          )
        })}
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

      {assessmentId && <SlaStrip changeRequestId={changeRequest.id} refreshKey={`${assessmentId}-${bump}`} />}

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
            <CategoriesTab assessmentId={assessmentId} changeRequest={changeRequest} bump={bumpFn} isFinalized={assessment?.status === 'Finalized'} />
          </TabsContent>
          <TabsContent value="policy">
            <PolicyTab assessmentId={assessmentId} mapping={mapping} bump={bumpFn} />
          </TabsContent>
          <TabsContent value="extraction">
            <ExtractionTab changeRequest={changeRequest} bump={bumpFn} />
          </TabsContent>
          <TabsContent value="narrative">
            <NarrativeTab assessmentId={assessmentId} mapping={mapping} bump={bumpFn} isFinalized={assessment?.status === 'Finalized'} />
          </TabsContent>
          <TabsContent value="scoring">
            <ScoringTab assessmentId={assessmentId} mapping={mapping} bump={bumpFn} isFinalized={assessment?.status === 'Finalized'} />
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
