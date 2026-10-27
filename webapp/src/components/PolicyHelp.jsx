import { InfoIcon } from 'lucide-react'
import { Dialog, DialogContent, DialogDescription, DialogTitle, DialogTrigger } from '@/components/ui/dialog'

function Section({ title, children }) {
  return (
    <div className="mt-4 space-y-1">
      <h3 className="text-sm font-medium">{title}</h3>
      <div className="space-y-1 text-sm text-muted-foreground">{children}</div>
    </div>
  )
}

// Plain-language guide for the Policy tab: what the step is, how to search, what each decision
// button does, and what finalizing needs. Keep it in step with the behaviour it describes:
// func_searchPolicyChunks (search), PolicyResearchService (decisions), AssessmentService.CheckReadinessAsync (finalizing).
export function PolicyHelp() {
  return (
    <Dialog>
      <DialogTrigger
        aria-label="How the Policy step works"
        title="How the Policy step works"
        className="inline-flex size-6 items-center justify-center rounded-full text-muted-foreground outline-hidden hover:bg-accent hover:text-accent-foreground focus-visible:ring-[3px] focus-visible:ring-ring/50"
      >
        <InfoIcon className="size-4" />
      </DialogTrigger>
      <DialogContent>
        <DialogTitle>How the Policy step works</DialogTitle>
        <DialogDescription>Find supporting guidance for each risk category you mapped, and record whether you rely on it.</DialogDescription>

        <Section title="What you are searching">
          <p>
            A small library of short excerpts that paraphrase the public FFIEC BSA/AML Examination Manual. They are guidance, not your bank's own policies, and not word-for-word quotes. Use
            "View source document" on a result to check the original. The search is a keyword search; no AI is used.
          </p>
        </Section>

        <Section title="Searching">
          <ul className="list-disc space-y-1 pl-5">
            <li>Choose a category to see only its excerpts, or leave "Any category".</li>
            <li>Type a topic, such as wire transfers, beneficial ownership, correspondent banking or high-risk jurisdictions, then press Enter or Search.</li>
            <li>No matches? Try fewer or simpler words. A result has to contain every word you type.</li>
          </ul>
        </Section>

        <Section title="Your decision on each excerpt">
          <ul className="list-disc space-y-1 pl-5">
            <li>
              <span className="font-medium text-foreground">Relied upon</span>: it supports the category, and the narrative draft may cite it.
            </li>
            <li>
              <span className="font-medium text-foreground">Not relevant</span>: you checked it and it does not apply. It is recorded but not used in the narrative.
            </li>
          </ul>
          <p>Each decision is saved with your name and the time, and appears under "Reliance decisions recorded".</p>
        </Section>

        <Section title="What is required">
          <ul className="list-disc space-y-1 pl-5">
            <li>You can draft a narrative without any decision, but it only draws on excerpts marked "Relied upon", so with none it has less to work from.</li>
            <li>To finalize the assessment, every mapped category needs at least one decision, either Relied upon or Not relevant.</li>
            <li>A decision made while "Any category" is selected counts for every category. Pick the specific category when it matters.</li>
          </ul>
        </Section>
      </DialogContent>
    </Dialog>
  )
}
