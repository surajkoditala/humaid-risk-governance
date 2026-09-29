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

const CHANGE_TYPES = ['Product', 'Feature', 'Process', 'Vendor', 'Geography', 'CustomerSegment']

// DEF-024: Vendor and Geography need their own mandatory, structured fields - not the one generic
// free-text box every change type shared before. Keyed by the typeSpecificFieldsJson field name so
// the labels and the submit/validation logic below stay in sync with one source of truth.
const TYPE_SPECIFIC_FIELD_SCHEMA = {
  Vendor: [
    { key: 'vendorName', label: 'Vendor name' },
    { key: 'jurisdiction', label: 'Jurisdiction' },
    { key: 'dataAccessScope', label: 'Data access scope' },
  ],
  Geography: [{ key: 'targetCountryRegion', label: 'Target country/region' }],
}

// Phase 3 - Data Ingestion Layer: which Mock Systems lookup (if any) applies to a given change
// type. Process has no obvious linked entity - Data Ingestion is a no-op for it, by design.
const LINKED_ENTITY_BY_CHANGE_TYPE = {
  CustomerSegment: 'customer',
  Product: 'product',
  Feature: 'product',
  Vendor: 'vendor',
  Geography: 'product',
}
// US-1.1: submit a change request. US-1.2: attach supporting documents to one already submitted.
export default function Intake() {
  const { currentUser } = useDevUser()
  const [changeType, setChangeType] = useState('')
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [details, setDetails] = useState('')
  const [typeSpecificFields, setTypeSpecificFields] = useState({})
  const [linkedEntityId, setLinkedEntityId] = useState('')
  const [submitting, setSubmitting] = useState(false)

  const typeSpecificSchema = TYPE_SPECIFIC_FIELD_SCHEMA[changeType] || null

  const { data: myRequests, refetch: refetchMyRequests } = useFetch(
    currentUser ? Endpoints.changeRequests.forUser(currentUser.id) : null,
    [currentUser?.id],
  )

  const linkedEntityKind = LINKED_ENTITY_BY_CHANGE_TYPE[changeType] || null
  const { data: mockCustomers } = useFetch(linkedEntityKind === 'customer' ? Endpoints.dataIngestion.mockCustomers() : null, [linkedEntityKind])
  const { data: mockProducts } = useFetch(linkedEntityKind === 'product' ? Endpoints.dataIngestion.mockProducts() : null, [linkedEntityKind])
  const { data: mockVendors } = useFetch(linkedEntityKind === 'vendor' ? Endpoints.dataIngestion.mockVendors() : null, [linkedEntityKind])
  const linkedOptions = linkedEntityKind === 'customer' ? mockCustomers : linkedEntityKind === 'product' ? mockProducts : linkedEntityKind === 'vendor' ? mockVendors : null

  const [attachToId, setAttachToId] = useState('')
  const [file, setFile] = useState(null)
  const [attaching, setAttaching] = useState(false)

  // DEF-023: name exactly which fields are missing instead of one static message that fires
  // ("Change type, title, and description are required.") no matter which one field was left blank.
  const missingFields = () => {
    const missing = []
    if (!changeType) missing.push('change type')
    if (!title) missing.push('title')
    if (!description) missing.push('description')
    for (const field of typeSpecificSchema || []) {
      if (!(typeSpecificFields[field.key] || '').trim()) missing.push(field.label.toLowerCase())
    }
    return missing
  }

  const submit = async (e) => {
    e.preventDefault()
    const missing = missingFields()
    if (missing.length > 0) {
      toast.error(`Missing required field${missing.length > 1 ? 's' : ''}: ${missing.join(', ')}.`)
      return
    }
    setSubmitting(true)
    try {
      const created = await apiFetch(Endpoints.changeRequests.submit(), {
        method: 'POST',
        body: {
          changeType,
          title,
          description,
          typeSpecificFieldsJson: JSON.stringify(typeSpecificSchema ? typeSpecificFields : { details }),
          submittedByUserId: currentUser.id,
          mockCustomerId: linkedEntityKind === 'customer' ? linkedEntityId || null : null,
          mockProductId: linkedEntityKind === 'product' ? linkedEntityId || null : null,
          mockVendorId: linkedEntityKind === 'vendor' ? linkedEntityId || null : null,
        },
      })
      toast.success(`Submitted as ${created.requestNumber}`)
      setChangeType('')
      setTitle('')
      setDescription('')
      setDetails('')
      setTypeSpecificFields({})
      setLinkedEntityId('')
      refetchMyRequests()
    } catch (err) {
      toast.error(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  const attach = async (e) => {
    e.preventDefault()
    if (!attachToId || !file) {
      toast.error('Pick a request and a file.')
      return
    }
    setAttaching(true)
    try {
      const formData = new FormData()
      formData.append('changeRequestId', attachToId)
      formData.append('uploadedByUserId', currentUser.id)
      formData.append('file', file)
      await apiFetch(Endpoints.changeRequests.attachDocumentFile(), { method: 'POST', body: formData })
      toast.success('Document attached — text extracted server-side')
      setFile(null)
    } catch (err) {
      toast.error(err.message)
    } finally {
      setAttaching(false)
    }
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Submit a change request</CardTitle>
          <CardDescription>Epic 1 — structured intake, no more email/SharePoint.</CardDescription>
        </CardHeader>
        <CardContent>
          <form className="space-y-4" onSubmit={submit}>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label>Change type</Label>
                <Select
                  value={changeType}
                  onValueChange={(v) => {
                    setChangeType(v)
                    setLinkedEntityId('')
                    setTypeSpecificFields({})
                  }}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="Select a type" />
                  </SelectTrigger>
                  <SelectContent>
                    {CHANGE_TYPES.map((t) => (
                      <SelectItem key={t} value={t}>
                        {t}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="title">Title</Label>
                <Input id="title" value={title} onChange={(e) => setTitle(e.target.value)} />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="description">Description</Label>
              <Textarea id="description" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
            </div>
            {typeSpecificSchema ? (
              <div className="grid gap-4 sm:grid-cols-2">
                {typeSpecificSchema.map((field) => (
                  <div className="space-y-1.5" key={field.key}>
                    <Label htmlFor={field.key}>{field.label}</Label>
                    <Input
                      id={field.key}
                      value={typeSpecificFields[field.key] || ''}
                      onChange={(e) => setTypeSpecificFields((prev) => ({ ...prev, [field.key]: e.target.value }))}
                    />
                  </div>
                ))}
              </div>
            ) : (
              <div className="space-y-1.5">
                <Label htmlFor="details">Type-specific details</Label>
                <Textarea
                  id="details"
                  rows={2}
                  placeholder="Any additional detail relevant to this change"
                  value={details}
                  onChange={(e) => setDetails(e.target.value)}
                />
              </div>
            )}
            {linkedEntityKind && (
              <div className="space-y-1.5">
                <Label>Linked {linkedEntityKind} (optional — grounds the AI category proposal)</Label>
                <Select value={linkedEntityId} onValueChange={setLinkedEntityId}>
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder={`Select a ${linkedEntityKind} from the bank's systems`}>
                      {linkedOptions?.find((o) => o.id === linkedEntityId)?.label}
                    </SelectValue>
                  </SelectTrigger>
                  <SelectContent>
                    {(linkedOptions || []).map((o) => (
                      <SelectItem key={o.id} value={o.id}>
                        {o.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}
            <Button type="submit" disabled={submitting}>
              {submitting ? 'Submitting…' : 'Submit request'}
            </Button>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Attach a supporting document</CardTitle>
          <CardDescription>
            PDF, DOCX, or XLSX — uploaded to blob storage and its text extracted server-side
            (deterministic parsing, not an AI call); that text is what Epic 4's extraction then
            runs against.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form className="space-y-4" onSubmit={attach}>
            <div className="space-y-1.5">
              <Label>Request</Label>
              <Select value={attachToId} onValueChange={setAttachToId}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Select one of my requests">
                    {(() => {
                      const r = myRequests?.find((req) => req.id === attachToId)
                      return r ? `${r.requestNumber} — ${r.title}` : undefined
                    })()}
                  </SelectValue>
                </SelectTrigger>
                <SelectContent>
                  {(myRequests || []).map((r) => (
                    <SelectItem key={r.id} value={r.id}>
                      {r.requestNumber} — {r.title}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="file">File (PDF, DOCX, or XLSX)</Label>
              <Input
                id="file"
                type="file"
                accept=".pdf,.docx,.xlsx"
                onChange={(e) => setFile(e.target.files?.[0] || null)}
              />
            </div>
            <Button type="submit" variant="outline" disabled={attaching}>
              {attaching ? 'Uploading & extracting…' : 'Attach document'}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
