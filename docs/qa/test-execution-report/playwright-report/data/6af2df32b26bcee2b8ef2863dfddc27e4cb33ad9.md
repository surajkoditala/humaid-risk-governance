# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: ui\04-committee.ui.spec.ts >> Epic 8 - Committee review & voting (UI) >> TC-UI-055 Decided item leaves the queue; Product Owner sees the outcome and conditions
- Location: specs\ui\04-committee.ui.spec.ts:94:7

# Error details

```
Error: PO should see the actual decision

expect(received).toMatch(expected)

Expected pattern: /Approved/
Received string:  "CR-2026-00066 Vendor [QA-E2E FINAL09251251] UI lifecycle - onboard Malta settlement vendor Decisioned 0"
```

# Page snapshot

```yaml
- generic [ref=f1e2]:
  - generic [ref=f1e4]:
    - complementary [ref=f1e5]:
      - generic [ref=f1e6]: Risk Workbench
      - navigation [ref=f1e11]:
        - button "Submit Request" [ref=f1e12]
        - button "My Requests" [active] [ref=f1e13]
    - generic [ref=f1e14]:
      - banner [ref=f1e15]:
        - combobox [ref=f1e16]:
          - generic [ref=f1e17]: Priya Owens — ProductOwner
          - img [aria-hidden]: ▼
        - textbox [aria-hidden] [ref=f1e18]: a6a709a7-65e7-4a90-9b58-cbbaec1d651a
        - generic [ref=f1e19]: PO
      - main [ref=f1e22]:
        - generic [ref=f1e24]:
          - generic [ref=f1e25]:
            - generic [ref=f1e26]: My requests
            - generic [ref=f1e27]: Status and days elapsed since submission.
          - table [ref=f1e30]:
            - rowgroup [ref=f1e31]:
              - row [ref=f1e32]:
                - 'columnheader "Request #" [ref=f1e33]'
                - columnheader "Type" [ref=f1e34]
                - columnheader "Title" [ref=f1e35]
                - columnheader "Status" [ref=f1e36]
                - columnheader "Days elapsed" [ref=f1e37]
            - rowgroup [ref=f1e38]:
              - row [ref=f1e39]:
                - cell "CR-2026-00066" [ref=f1e40]
                - cell "Vendor" [ref=f1e41]
                - cell "[QA-E2E FINAL09251251] UI lifecycle - onboard Malta settlement vendor" [ref=f1e42]
                - cell "Decisioned" [ref=f1e43]
                - cell "0" [ref=f1e45]
              - row [ref=f1e46]:
                - cell "CR-2026-00065" [ref=f1e47]
                - cell "Feature" [ref=f1e48]
                - cell [ref=f1e49]
                - cell "Submitted" [ref=f1e50]
                - cell "0" [ref=f1e52]
              - row [ref=f1e53]:
                - cell "CR-2026-00064" [ref=f1e54]
                - cell "Process" [ref=f1e55]
                - cell "[QA-E2E FINAL09251251] API probe - actor spoofing" [ref=f1e56]
                - cell "InAssessment" [ref=f1e57]
                - cell "0" [ref=f1e59]
              - row [ref=f1e60]:
                - cell "CR-2026-00063" [ref=f1e61]
                - cell "CustomerSegment" [ref=f1e62]
                - cell "[QA-E2E FINAL09251251] API probe - config versioning" [ref=f1e63]
                - cell "InAssessment" [ref=f1e64]
                - cell "0" [ref=f1e66]
              - row [ref=f1e67]:
                - cell "CR-2026-00062" [ref=f1e68]
                - cell "Feature" [ref=f1e69]
                - cell "[QA-E2E FINAL09251251] API probe - re-vote" [ref=f1e70]
                - cell "PendingCommittee" [ref=f1e71]
                - cell "0" [ref=f1e73]
              - row [ref=f1e74]:
                - cell "CR-2026-00061" [ref=f1e75]
                - cell "Feature" [ref=f1e76]
                - cell "[QA-E2E FINAL09251251] API probe - empty assessment" [ref=f1e77]
                - cell "Decisioned" [ref=f1e78]
                - cell "0" [ref=f1e80]
              - row [ref=f1e81]:
                - cell "CR-2026-00060" [ref=f1e82]
                - cell "Vendor" [ref=f1e83]
                - cell "[QA-E2E FINAL09251251] API lifecycle - onboard settlement vendor" [ref=f1e84]
                - cell "Decisioned" [ref=f1e85]
                - cell "0" [ref=f1e87]
              - row [ref=f1e88]:
                - cell "CR-2026-00059" [ref=f1e89]
                - cell "Process" [ref=f1e90]
                - cell "[QA-E2E FINAL09251251] snapshot none" [ref=f1e91]
                - cell "Submitted" [ref=f1e92]
                - cell "0" [ref=f1e94]
              - row [ref=f1e95]:
                - cell "CR-2026-00058" [ref=f1e96]
                - cell "Product" [ref=f1e97]
                - cell "[QA-E2E FINAL09251251] snapshot linked" [ref=f1e98]
                - cell "Submitted" [ref=f1e99]
                - cell "0" [ref=f1e101]
              - row [ref=f1e102]:
                - cell "CR-2026-00057" [ref=f1e103]
                - cell "Geography" [ref=f1e104]
                - cell "[QA-E2E FINAL09251251] clarification" [ref=f1e105]
                - cell "Submitted" [ref=f1e106]
                - cell "0" [ref=f1e108]
              - row [ref=f1e109]:
                - cell "CR-2026-00056" [ref=f1e110]
                - cell "Vendor" [ref=f1e111]
                - cell "[QA-E2E FINAL09251251] bad uploads" [ref=f1e112]
                - cell "Submitted" [ref=f1e113]
                - cell "0" [ref=f1e115]
              - row [ref=f1e116]:
                - cell "CR-2026-00055" [ref=f1e117]
                - cell "Vendor" [ref=f1e118]
                - cell "[QA-E2E FINAL09251251] attachments" [ref=f1e119]
                - cell "Submitted" [ref=f1e120]
                - cell "0" [ref=f1e122]
              - row [ref=f1e123]:
                - cell "CR-2026-00052" [ref=f1e124]
                - cell "Product" [ref=f1e125]
                - cell [ref=f1e126]
                - cell "Submitted" [ref=f1e127]
                - cell "0" [ref=f1e129]
              - row [ref=f1e130]:
                - cell "CR-2026-00051" [ref=f1e131]
                - cell "CustomerSegment" [ref=f1e132]
                - cell "[QA-E2E FINAL09251251] type CustomerSegment" [ref=f1e133]
                - cell "Submitted" [ref=f1e134]
                - cell "0" [ref=f1e136]
              - row [ref=f1e137]:
                - cell "CR-2026-00050" [ref=f1e138]
                - cell "Geography" [ref=f1e139]
                - cell "[QA-E2E FINAL09251251] type Geography" [ref=f1e140]
                - cell "Submitted" [ref=f1e141]
                - cell "0" [ref=f1e143]
              - row [ref=f1e144]:
                - cell "CR-2026-00049" [ref=f1e145]
                - cell "Vendor" [ref=f1e146]
                - cell "[QA-E2E FINAL09251251] type Vendor" [ref=f1e147]
                - cell "Submitted" [ref=f1e148]
                - cell "0" [ref=f1e150]
              - row [ref=f1e151]:
                - cell "CR-2026-00048" [ref=f1e152]
                - cell "Process" [ref=f1e153]
                - cell "[QA-E2E FINAL09251251] type Process" [ref=f1e154]
                - cell "Submitted" [ref=f1e155]
                - cell "0" [ref=f1e157]
              - row [ref=f1e158]:
                - cell "CR-2026-00047" [ref=f1e159]
                - cell "Feature" [ref=f1e160]
                - cell "[QA-E2E FINAL09251251] type Feature" [ref=f1e161]
                - cell "Submitted" [ref=f1e162]
                - cell "0" [ref=f1e164]
              - row [ref=f1e165]:
                - cell "CR-2026-00046" [ref=f1e166]
                - cell "Product" [ref=f1e167]
                - cell "[QA-E2E FINAL09251251] type Product" [ref=f1e168]
                - cell "Submitted" [ref=f1e169]
                - cell "0" [ref=f1e171]
              - row [ref=f1e172]:
                - cell "CR-2026-00045" [ref=f1e173]
                - cell "Product" [ref=f1e174]
                - cell "[QA-E2E FINAL09251251] API intake - prepaid card" [ref=f1e175]
                - cell "Submitted" [ref=f1e176]
                - cell "0" [ref=f1e178]
              - row [ref=f1e179]:
                - cell "CR-2026-00044" [ref=f1e180]
                - cell "Feature" [ref=f1e181]
                - cell "[QA-E2E 202609250720] <img src=x onerror=\"window.__xss=1\"><script>window.__xss=2</script>" [ref=f1e182]
                - cell "Submitted" [ref=f1e183]
                - cell "0" [ref=f1e185]
              - row [ref=f1e186]:
                - cell "CR-2026-00043" [ref=f1e187]
                - cell "Vendor" [ref=f1e188]
                - cell "[QA-E2E 202609250707] UI lifecycle - onboard Malta settlement vendor" [ref=f1e189]
                - cell "InAssessment" [ref=f1e190]
                - cell "0" [ref=f1e192]
              - row [ref=f1e193]:
                - cell "CR-2026-00042" [ref=f1e194]
                - cell "Feature" [ref=f1e195]
                - cell [ref=f1e196]
                - cell "Submitted" [ref=f1e197]
                - cell "0" [ref=f1e199]
              - row [ref=f1e200]:
                - cell "CR-2026-00041" [ref=f1e201]
                - cell "Process" [ref=f1e202]
                - cell "[QA-E2E 202609250702] API probe - actor spoofing" [ref=f1e203]
                - cell "InAssessment" [ref=f1e204]
                - cell "0" [ref=f1e206]
              - row [ref=f1e207]:
                - cell "CR-2026-00040" [ref=f1e208]
                - cell "CustomerSegment" [ref=f1e209]
                - cell "[QA-E2E 202609250702] API probe - config versioning" [ref=f1e210]
                - cell "InAssessment" [ref=f1e211]
                - cell "0" [ref=f1e213]
              - row [ref=f1e214]:
                - cell "CR-2026-00039" [ref=f1e215]
                - cell "Feature" [ref=f1e216]
                - cell "[QA-E2E 202609250658] API probe - re-vote" [ref=f1e217]
                - cell "PendingCommittee" [ref=f1e218]
                - cell "0" [ref=f1e220]
              - row [ref=f1e221]:
                - cell "CR-2026-00038" [ref=f1e222]
                - cell "Feature" [ref=f1e223]
                - cell "[QA-E2E 202609250658] API probe - empty assessment" [ref=f1e224]
                - cell "Decisioned" [ref=f1e225]
                - cell "0" [ref=f1e227]
              - row [ref=f1e228]:
                - cell "CR-2026-00037" [ref=f1e229]
                - cell "Vendor" [ref=f1e230]
                - cell "[QA-E2E 202609250658] API lifecycle - onboard settlement vendor" [ref=f1e231]
                - cell "Decisioned" [ref=f1e232]
                - cell "0" [ref=f1e234]
              - row [ref=f1e235]:
                - cell "CR-2026-00036" [ref=f1e236]
                - cell "Vendor" [ref=f1e237]
                - cell "[QA-E2E 202609250653] API lifecycle - onboard settlement vendor" [ref=f1e238]
                - cell "Decisioned" [ref=f1e239]
                - cell "0" [ref=f1e241]
              - row [ref=f1e242]:
                - cell "CR-2026-00035" [ref=f1e243]
                - cell "Vendor" [ref=f1e244]
                - cell "[QA-E2E probe] versioning" [ref=f1e245]
                - cell "Submitted" [ref=f1e246]
                - cell "0" [ref=f1e248]
              - row [ref=f1e249]:
                - cell "CR-2026-00034" [ref=f1e250]
                - cell "Process" [ref=f1e251]
                - cell "[QA-E2E 202609250649] snapshot none" [ref=f1e252]
                - cell "Submitted" [ref=f1e253]
                - cell "0" [ref=f1e255]
              - row [ref=f1e256]:
                - cell "CR-2026-00033" [ref=f1e257]
                - cell "Product" [ref=f1e258]
                - cell "[QA-E2E 202609250649] snapshot linked" [ref=f1e259]
                - cell "Submitted" [ref=f1e260]
                - cell "0" [ref=f1e262]
              - row [ref=f1e263]:
                - cell "CR-2026-00032" [ref=f1e264]
                - cell "Geography" [ref=f1e265]
                - cell "[QA-E2E 202609250649] clarification" [ref=f1e266]
                - cell "Submitted" [ref=f1e267]
                - cell "0" [ref=f1e269]
              - row [ref=f1e270]:
                - cell "CR-2026-00031" [ref=f1e271]
                - cell "Vendor" [ref=f1e272]
                - cell "[QA-E2E 202609250649] bad uploads" [ref=f1e273]
                - cell "Submitted" [ref=f1e274]
                - cell "0" [ref=f1e276]
              - row [ref=f1e277]:
                - cell "CR-2026-00030" [ref=f1e278]
                - cell "Vendor" [ref=f1e279]
                - cell "[QA-E2E 202609250649] attachments" [ref=f1e280]
                - cell "Submitted" [ref=f1e281]
                - cell "0" [ref=f1e283]
              - row [ref=f1e284]:
                - cell "CR-2026-00027" [ref=f1e285]
                - cell "Product" [ref=f1e286]
                - cell [ref=f1e287]
                - cell "Submitted" [ref=f1e288]
                - cell "0" [ref=f1e290]
              - row [ref=f1e291]:
                - cell "CR-2026-00026" [ref=f1e292]
                - cell "CustomerSegment" [ref=f1e293]
                - cell "[QA-E2E 202609250649] type CustomerSegment" [ref=f1e294]
                - cell "Submitted" [ref=f1e295]
                - cell "0" [ref=f1e297]
              - row [ref=f1e298]:
                - cell "CR-2026-00025" [ref=f1e299]
                - cell "Geography" [ref=f1e300]
                - cell "[QA-E2E 202609250649] type Geography" [ref=f1e301]
                - cell "Submitted" [ref=f1e302]
                - cell "0" [ref=f1e304]
              - row [ref=f1e305]:
                - cell "CR-2026-00024" [ref=f1e306]
                - cell "Vendor" [ref=f1e307]
                - cell "[QA-E2E 202609250649] type Vendor" [ref=f1e308]
                - cell "Submitted" [ref=f1e309]
                - cell "0" [ref=f1e311]
              - row [ref=f1e312]:
                - cell "CR-2026-00023" [ref=f1e313]
                - cell "Process" [ref=f1e314]
                - cell "[QA-E2E 202609250649] type Process" [ref=f1e315]
                - cell "Submitted" [ref=f1e316]
                - cell "0" [ref=f1e318]
              - row [ref=f1e319]:
                - cell "CR-2026-00022" [ref=f1e320]
                - cell "Feature" [ref=f1e321]
                - cell "[QA-E2E 202609250649] type Feature" [ref=f1e322]
                - cell "Submitted" [ref=f1e323]
                - cell "0" [ref=f1e325]
              - row [ref=f1e326]:
                - cell "CR-2026-00021" [ref=f1e327]
                - cell "Product" [ref=f1e328]
                - cell "[QA-E2E 202609250649] type Product" [ref=f1e329]
                - cell "Submitted" [ref=f1e330]
                - cell "0" [ref=f1e332]
              - row [ref=f1e333]:
                - cell "CR-2026-00020" [ref=f1e334]
                - cell "Product" [ref=f1e335]
                - cell "[QA-E2E 202609250649] API intake - prepaid card" [ref=f1e336]
                - cell "Submitted" [ref=f1e337]
                - cell "0" [ref=f1e339]
              - row [ref=f1e340]:
                - cell "CR-2026-00019" [ref=f1e341]
                - cell "Process" [ref=f1e342]
                - cell "[QA-E2E 202609250649] snapshot none" [ref=f1e343]
                - cell "Submitted" [ref=f1e344]
                - cell "0" [ref=f1e346]
              - row [ref=f1e347]:
                - cell "CR-2026-00018" [ref=f1e348]
                - cell "Product" [ref=f1e349]
                - cell "[QA-E2E 202609250649] snapshot linked" [ref=f1e350]
                - cell "Submitted" [ref=f1e351]
                - cell "0" [ref=f1e353]
              - row [ref=f1e354]:
                - cell "CR-2026-00017" [ref=f1e355]
                - cell "Geography" [ref=f1e356]
                - cell "[QA-E2E 202609250649] clarification" [ref=f1e357]
                - cell "Submitted" [ref=f1e358]
                - cell "0" [ref=f1e360]
              - row [ref=f1e361]:
                - cell "CR-2026-00016" [ref=f1e362]
                - cell "Vendor" [ref=f1e363]
                - cell "[QA-E2E 202609250649] bad uploads" [ref=f1e364]
                - cell "Submitted" [ref=f1e365]
                - cell "0" [ref=f1e367]
              - row [ref=f1e368]:
                - cell "CR-2026-00015" [ref=f1e369]
                - cell "Vendor" [ref=f1e370]
                - cell "[QA-E2E 202609250649] attachments" [ref=f1e371]
                - cell "Submitted" [ref=f1e372]
                - cell "0" [ref=f1e374]
              - row [ref=f1e375]:
                - cell "CR-2026-00012" [ref=f1e376]
                - cell "Product" [ref=f1e377]
                - cell [ref=f1e378]
                - cell "Submitted" [ref=f1e379]
                - cell "0" [ref=f1e381]
              - row [ref=f1e382]:
                - cell "CR-2026-00011" [ref=f1e383]
                - cell "CustomerSegment" [ref=f1e384]
                - cell "[QA-E2E 202609250649] type CustomerSegment" [ref=f1e385]
                - cell "Submitted" [ref=f1e386]
                - cell "0" [ref=f1e388]
              - row [ref=f1e389]:
                - cell "CR-2026-00010" [ref=f1e390]
                - cell "Geography" [ref=f1e391]
                - cell "[QA-E2E 202609250649] type Geography" [ref=f1e392]
                - cell "Submitted" [ref=f1e393]
                - cell "0" [ref=f1e395]
              - row [ref=f1e396]:
                - cell "CR-2026-00009" [ref=f1e397]
                - cell "Vendor" [ref=f1e398]
                - cell "[QA-E2E 202609250649] type Vendor" [ref=f1e399]
                - cell "Submitted" [ref=f1e400]
                - cell "0" [ref=f1e402]
              - row [ref=f1e403]:
                - cell "CR-2026-00008" [ref=f1e404]
                - cell "Process" [ref=f1e405]
                - cell "[QA-E2E 202609250649] type Process" [ref=f1e406]
                - cell "Submitted" [ref=f1e407]
                - cell "0" [ref=f1e409]
              - row [ref=f1e410]:
                - cell "CR-2026-00007" [ref=f1e411]
                - cell "Feature" [ref=f1e412]
                - cell "[QA-E2E 202609250649] type Feature" [ref=f1e413]
                - cell "Submitted" [ref=f1e414]
                - cell "0" [ref=f1e416]
              - row [ref=f1e417]:
                - cell "CR-2026-00006" [ref=f1e418]
                - cell "Product" [ref=f1e419]
                - cell "[QA-E2E 202609250649] type Product" [ref=f1e420]
                - cell "Submitted" [ref=f1e421]
                - cell "0" [ref=f1e423]
              - row [ref=f1e424]:
                - cell "CR-2026-00005" [ref=f1e425]
                - cell "Product" [ref=f1e426]
                - cell "[QA-E2E 202609250649] API intake - prepaid card" [ref=f1e427]
                - cell "Submitted" [ref=f1e428]
                - cell "0" [ref=f1e430]
              - row [ref=f1e431]:
                - cell "CR-2026-00004" [ref=f1e432]
                - cell "Product" [ref=f1e433]
                - cell "AzureFoundry E2E Test - Prepaid Card Launch" [ref=f1e434]
                - cell "Decisioned" [ref=f1e435]
                - cell "0" [ref=f1e437]
              - row [ref=f1e438]:
                - cell "CR-2026-00002" [ref=f1e439]
                - cell "Vendor" [ref=f1e440]
                - cell "Onboard QuickPay Processing for card settlement" [ref=f1e441]
                - cell "Decisioned" [ref=f1e442]
                - cell "2" [ref=f1e444]
              - row [ref=f1e445]:
                - cell "CR-2026-00001" [ref=f1e446]
                - cell "Process" [ref=f1e447]
                - cell "Azure DB e2e verification test" [ref=f1e448]
                - cell "InAssessment" [ref=f1e449]
                - cell "2" [ref=f1e451]
      - contentinfo [ref=f1e452]: © 2026 HumAId Risk Governance. All rights reserved.
  - region "Notifications alt+T"
```

# Test source

```ts
  13  |   await expect(row, 'routed request must be in the committee queue').toBeVisible()
  14  |   await row.getByRole('button', { name: 'Review' }).click()
  15  |   await expect(page.getByRole('button', { name: '← Back to queue' })).toBeVisible()
  16  |   return crNumber
  17  | }
  18  | 
  19  | test.describe('Epic 8 - Committee review & voting (UI)', () => {
  20  |   test('TC-UI-050 Routed assessment appears in the committee queue', async ({ page }) => {
  21  |     tc({ id: 'TC-UI-050', story: 'US-8.1', type: 'Functional', priority: 'P1', steps: ['Act as Jordan Blake (Committee)', 'Open Committee Queue'], expected: 'Queue row shows request #, type and title with a Review button' })
  22  |     const crNumber = state.need(K('crNumber'))
  23  |     await enterApp(page, USERS.committee1)
  24  |     await nav(page, 'Committee Queue')
  25  |     const row = page.getByRole('row').filter({ hasText: crNumber })
  26  |     await expect(row).toBeVisible()
  27  |     await snap(page, 'committee queue')
  28  |     actual(`queue row: ${(await row.textContent())?.replace(/\s+/g, ' ')}`)
  29  |   })
  30  | 
  31  |   test('TC-UI-051 Committee sees the full assessment before voting', async ({ page }) => {
  32  |     tc({ id: 'TC-UI-051', story: 'US-8.2', type: 'Functional', priority: 'P1', steps: ['Open Review on the queue item'], expected: 'Panel shows the narrative per category, residual scores, cited policy and the analyst override history, read-only' })
  33  |     defect('DEF-021')
  34  |     await openVotePanel(page, USERS.committee1)
  35  |     await snap(page, 'vote panel')
  36  |     const text = (await page.getByRole('main').textContent()) || ''
  37  |     const shows = { narrative: /Narrative|narrative/.test(text), scores: /Residual/.test(text), policy: /FFIEC|relied/i.test(text), overrides: /override/i.test(text) }
  38  |     actual(`vote panel contains only the title, vote form and vote list - narrative:${shows.narrative} scores:${shows.scores} policy:${shows.policy} overrides:${shows.overrides}`)
  39  |     expect.soft(shows.scores, 'scores visible to committee').toBe(true)
  40  |     expect.soft(shows.policy, 'cited policy visible to committee').toBe(true)
  41  |   })
  42  | 
  43  |   test('TC-UI-052 Vote validation: conditions / rationale mandatory', async ({ page }) => {
  44  |     tc({ id: 'TC-UI-052', story: 'US-8.2', type: 'Negative', priority: 'P1', steps: ['Choose ApproveWithConditions, leave conditions blank, Submit vote', 'Choose Reject, leave rationale blank, Submit', 'Choose Defer, leave rationale blank, Submit'], expected: 'Each blocked with the matching message; nothing recorded' })
  45  |     await openVotePanel(page, USERS.committee1)
  46  |     const main = page.getByRole('main')
  47  |     await choose(page, main.getByRole('combobox'), 'ApproveWithConditions')
  48  |     await expect(main.getByPlaceholder('Conditions')).toBeVisible()
  49  |     await main.getByRole('button', { name: 'Submit vote' }).click()
  50  |     await expect(toast(page, 'Conditions text is required for Approve-with-Conditions.')).toBeVisible()
  51  |     await snap(page, 'awc blank blocked')
  52  |     await choose(page, main.getByRole('combobox'), 'Reject')
  53  |     await main.getByRole('button', { name: 'Submit vote' }).click()
  54  |     await expect(toast(page, 'A rationale is required for Reject/Defer.')).toBeVisible()
  55  |     await choose(page, main.getByRole('combobox'), 'Defer')
  56  |     await main.getByRole('button', { name: 'Submit vote' }).click()
  57  |     await expect(toast(page, 'A rationale is required for Reject/Defer.').last()).toBeVisible()
  58  |     await snap(page, 'reject defer blank blocked')
  59  |     await expect(main.getByText('No votes yet.')).toBeVisible()
  60  |     actual('all three blank submissions blocked client-side; "No votes yet." still shown')
  61  |   })
  62  | 
  63  |   test('TC-UI-053 First member votes Approve-with-Conditions', async ({ page }) => {
  64  |     tc({ id: 'TC-UI-053', story: 'US-8.2', type: 'Functional', priority: 'P1', steps: ['As Jordan Blake choose ApproveWithConditions', 'Enter conditions', 'Submit vote'], expected: 'Toast "Vote cast"; vote list shows "Jordan Blake - ApproveWithConditions" with the conditions; no decision yet (quorum 2)' })
  65  |     await openVotePanel(page, USERS.committee1)
  66  |     const main = page.getByRole('main')
  67  |     await choose(page, main.getByRole('combobox'), 'ApproveWithConditions')
  68  |     await main.getByPlaceholder('Conditions').fill('Annual on-site audit of the vendor; cardholder PII encrypted at rest (QA)')
  69  |     await main.getByRole('button', { name: 'Submit vote' }).click()
  70  |     await expect(toast(page, 'Vote cast')).toBeVisible()
  71  |     const row = main.locator('.flex.items-center.justify-between').filter({ hasText: USERS.committee1 })
  72  |     await expect(row).toContainText('ApproveWithConditions')
  73  |     await snap(page, 'first vote cast')
  74  |     await expect(main.getByText(/^Resolved:/)).toHaveCount(0)
  75  |     actual(`vote row: ${(await row.textContent())?.replace(/\s+/g, ' ')}; no decision yet`)
  76  |   })
  77  | 
  78  |   test('TC-UI-054 Second vote reaches quorum and records the decision with conditions', async ({ page }) => {
  79  |     tc({ id: 'TC-UI-054', story: 'US-8.2 / US-8.3', type: 'E2E', priority: 'P1', steps: ['As Riley Voss open the item', 'Vote Approve'], expected: 'Decision banner "Resolved: ApprovedWithConditions" with the merged conditions; both votes listed individually' })
  80  |     await openVotePanel(page, USERS.committee2)
  81  |     const main = page.getByRole('main')
  82  |     await choose(page, main.getByRole('combobox'), 'Approve')
  83  |     await main.getByRole('button', { name: 'Submit vote' }).click()
  84  |     await expect(toast(page, 'Vote cast')).toBeVisible()
  85  |     const banner = main.getByText(/^Resolved:/)
  86  |     await expect(banner).toBeVisible()
  87  |     await snap(page, 'decision recorded')
  88  |     const votes = await main.locator('.flex.items-center.justify-between').allTextContents()
  89  |     actual(`${await banner.textContent()}; conditions "${await main.locator('.bg-emerald-50 p').nth(1).textContent()}"; votes: ${votes.map((v) => v.replace(/\s+/g, ' ')).join(' | ')}`)
  90  |     await expect(banner).toHaveText('Resolved: ApprovedWithConditions')
  91  |     expect(votes.length).toBe(2)
  92  |   })
  93  | 
  94  |   test('TC-UI-055 Decided item leaves the queue; Product Owner sees the outcome and conditions', async ({ page }) => {
  95  |     tc({ id: 'TC-UI-055', story: 'US-8.3 / US-1.3', type: 'Functional', priority: 'P1', steps: ['As Jordan Blake reload Committee Queue', 'As Priya Owens open My Requests'], expected: 'Item no longer queued; PO row shows the decision "Approved with Conditions" and the attached conditions' })
  96  |     defect('DEF-022')
  97  |     const crNumber = state.need(K('crNumber'))
  98  |     await enterApp(page, USERS.committee1)
  99  |     await nav(page, 'Committee Queue')
  100 |     await page.waitForTimeout(1000)
  101 |     const stillQueued = await page.getByRole('row').filter({ hasText: crNumber }).count()
  102 |     await snap(page, 'queue after decision')
  103 |     await enterApp(page, USERS.po)
  104 |     await nav(page, 'My Requests')
  105 |     const row = page.getByRole('row').filter({ hasText: crNumber })
  106 |     await expect(row).toBeVisible()
  107 |     await row.scrollIntoViewIfNeeded()
  108 |     await snap(page, 'po sees outcome')
  109 |     const cells = (await row.getByRole('cell').allTextContents()).map((s) => s.trim())
  110 |     actual(`still in queue: ${stillQueued > 0}; PO row status "${cells[3]}" - decision and conditions not shown to the requester`)
  111 |     expect(stillQueued).toBe(0)
  112 |     expect(cells[3]).toBe('Decisioned')
> 113 |     expect.soft(cells.join(' '), 'PO should see the actual decision').toMatch(/Approved/)
      |                                                                       ^ Error: PO should see the actual decision
  114 |   })
  115 | })
  116 | 
```