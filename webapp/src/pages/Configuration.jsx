import { useState } from 'react'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { useDevUser } from '../auth/DevUserContext.jsx'
import { Endpoints, apiFetch } from '../lib/api.js'
import { useFetch } from '../lib/useFetch.js'

// Epic 10 — Platform Configuration, analyst/admin-owned, no code change required.
export default function Configuration() {
  const { currentUser } = useDevUser()
  const [bump, setBump] = useState(0)
  const { data: rules } = useFetch(Endpoints.workflowRule.all(), [bump])
  const { data: categories } = useFetch(Endpoints.categoryMapping.categories())

  const [ruleKey, setRuleKey] = useState('CommitteeQuorum')
  const [ruleValue, setRuleValue] = useState('{"quorum": 2}')
  const [ruleReason, setRuleReason] = useState('')

  const [categoryId, setCategoryId] = useState('')
  const [mitigationFactor, setMitigationFactor] = useState('')
  const [scoringReason, setScoringReason] = useState('')

  const saveRule = async () => {
    if (!ruleReason.trim()) {
      toast.error('A reason is required to change a workflow rule (US-10.2).')
      return
    }
    try {
      JSON.parse(ruleValue)
    } catch {
      toast.error('Rule value must be valid JSON.')
      return
    }
    try {
      await apiFetch(Endpoints.workflowRule.upsert(), {
        method: 'POST',
        body: { ruleKey, ruleValueJson: ruleValue, reason: ruleReason, actorUserId: currentUser.id },
      })
      toast.success('Workflow rule updated')
      setRuleReason('')
      setBump((b) => b + 1)
    } catch (err) {
      toast.error(err.message)
    }
  }

  const saveScoringConfig = async () => {
    if (!categoryId || !mitigationFactor || !scoringReason.trim()) {
      toast.error('Category, mitigation factor, and reason are all required.')
      return
    }
    try {
      await apiFetch(Endpoints.scoring.config(), {
        method: 'POST',
        body: { riskCategoryId: categoryId, maxMitigationFactor: Number(mitigationFactor), reason: scoringReason, actorUserId: currentUser.id },
      })
      toast.success('Scoring configuration updated')
      setMitigationFactor('')
      setScoringReason('')
    } catch (err) {
      toast.error(err.message)
    }
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Workflow rules</CardTitle>
          <CardDescription>US-10.2 — plain structured config, not buried in code. Every change is audited.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            {(rules || []).map((r) => (
              <div key={r.id} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 rounded-md border p-3 text-sm">
                <span className="font-medium">{r.ruleKey}</span>
                <code className="break-all text-xs text-muted-foreground">{r.ruleValueJson}</code>
              </div>
            ))}
            {(!rules || rules.length === 0) && <p className="text-sm text-muted-foreground">No rules configured yet.</p>}
          </div>

          <div className="grid gap-3 border-t pt-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label>Rule key</Label>
              <Input value={ruleKey} onChange={(e) => setRuleKey(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Reason (mandatory)</Label>
              <Input value={ruleReason} onChange={(e) => setRuleReason(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Value (JSON)</Label>
            <Textarea rows={2} value={ruleValue} onChange={(e) => setRuleValue(e.target.value)} />
          </div>
          <Button onClick={saveRule}>Save rule</Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Scoring configuration</CardTitle>
          <CardDescription>
            US-10.1 — the mitigation cap per category; a value ≥ 1.0 is rejected outright since that
            would let residual risk reach zero.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex flex-wrap items-end gap-2">
            <div className="space-y-1.5">
              <Label>Category</Label>
              <Select value={categoryId} onValueChange={setCategoryId}>
                <SelectTrigger className="w-56">
                  <SelectValue placeholder="Select category">
                    {categories?.find((c) => c.id === categoryId)?.name}
                  </SelectValue>
                </SelectTrigger>
                <SelectContent>
                  {(categories || []).map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Max mitigation factor (0–1)</Label>
              <Input className="w-40" type="number" step="0.05" min={0} max={0.99} value={mitigationFactor} onChange={(e) => setMitigationFactor(e.target.value)} />
            </div>
          </div>
          <Input placeholder="Reason" value={scoringReason} onChange={(e) => setScoringReason(e.target.value)} />
          <Button onClick={saveScoringConfig}>Save configuration</Button>
        </CardContent>
      </Card>
    </div>
  )
}
