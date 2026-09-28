// Exploratory check on the deployed dev app: long titles overflowing list tables, and the truncated user switcher.
import { createRequire } from 'node:module'
const require = createRequire('C:/claude-personalLap/humaid-risk-governance/tests/e2e/package.json')
const { chromium } = require('playwright')

const BASE = 'https://ca-gh-hrg-workbench-dev.jollyplant-1cbb4459.eastus2.azurecontainerapps.io'
const OUT = 'C:/Users/alaga/AppData/Local/Temp/claude/c--claude-personalLap-humaid-risk-governance/546d1b97-2a9b-4977-957a-af5e39ab6387/scratchpad/ux'
const stamp = new Date().toISOString().slice(0, 16).replace(/\D/g, '')
const TITLE = `[QA-E2E ${stamp}] Onboard QuickPay Processing Ltd (Malta) as the card settlement processor for the consumer debit and prepaid card programmes, including cardholder PII and daily settlement file exchange over API`

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } })
const out = {}

async function actAs(name) {
  const sw = page.getByRole('banner').getByRole('combobox')
  await sw.click()
  await page.getByRole('option', { name: new RegExp(`^${name} —`) }).click()
  await page.waitForTimeout(800)
}
const nav = (l) => page.getByRole('navigation').getByRole('button', { name: l }).click()
const toast = (t) => page.locator('[data-sonner-toast]').filter({ hasText: t }).first()

// measure the table that contains our row
async function measure(label, actionName) {
  const row = page.getByRole('row').filter({ hasText: stamp }).first()
  await row.waitFor({ timeout: 30000 })
  await page.waitForTimeout(500)
  const m = await row.evaluate((tr, actionName) => {
    const wrap = tr.closest('table').parentElement
    const cells = [...tr.cells].map((c) => ({ text: c.innerText.trim().slice(0, 40), right: Math.round(c.getBoundingClientRect().right) }))
    const btn = actionName ? [...tr.querySelectorAll('button')].find((b) => b.innerText.trim() === actionName) : null
    return { viewport: window.innerWidth, tableClient: wrap.clientWidth, tableScroll: wrap.scrollWidth, wrapRight: Math.round(wrap.getBoundingClientRect().right),
      pageHScroll: document.documentElement.scrollWidth > window.innerWidth, cells,
      actionRight: btn ? Math.round(btn.getBoundingClientRect().right) : null }
  }, actionName)
  m.hiddenColumns = m.cells.filter((c) => c.right > m.wrapRight).map((c) => c.text || '(action)')
  m.actionVisible = m.actionRight === null ? null : m.actionRight <= m.wrapRight
  out[label] = m
  await page.screenshot({ path: `${OUT}/${label}.png` })
  return m
}

await page.goto(BASE)
await page.getByRole('button', { name: /Continue without signing in/ }).click()
await page.getByRole('banner').getByRole('combobox').waitFor()
await page.waitForTimeout(1500)

// --- switcher truncation (DEF-025), for each role
for (const name of ['Priya Owens', 'Amara Chen', 'Jordan Blake']) {
  await actAs(name)
  const sw = page.getByRole('banner').getByRole('combobox')
  out[`switcher ${name}`] = await sw.evaluate((el) => ({ shown: el.innerText.trim(), scrollW: el.scrollWidth, clientW: el.clientWidth,
    inner: [...el.querySelectorAll('*')].map((e) => ({ t: e.innerText?.trim(), sw: e.scrollWidth, cw: e.clientWidth })).filter((x) => x.t && x.sw > x.cw) }))
  const bb = await page.getByRole('banner').boundingBox()
  await page.screenshot({ path: `${OUT}/switcher-${name.split(' ')[0]}.png`, clip: { x: bb.x + bb.width - 520, y: bb.y, width: 520, height: bb.height } })
}
// open list to show full option labels
await page.getByRole('banner').getByRole('combobox').click()
await page.waitForTimeout(400)
out.options = await page.getByRole('option').allTextContents()
await page.screenshot({ path: `${OUT}/switcher-options.png` })
await page.keyboard.press('Escape')

// --- submit long-title request as PO
await actAs('Priya Owens')
await nav('Submit Request')
const form = page.locator('[data-slot="card"]').filter({ hasText: 'Submit a change request' }).first()
await form.getByRole('combobox').first().click(); await page.getByRole('option', { name: 'Vendor' }).first().click()
await page.getByLabel('Title').fill(TITLE)
await page.getByLabel('Description').fill('Exploratory UX check: long request title.')
await page.getByLabel('Type-specific details').fill('Vendor: QuickPay Processing Ltd; jurisdiction: Malta')
await form.getByRole('combobox').nth(1).click(); await page.getByRole('option').first().click()
await page.getByRole('button', { name: 'Submit request', exact: true }).click()
await toast(/CR-\d{4}-\d+/).waitFor({ timeout: 30000 })
out.cr = (await toast(/CR-\d{4}-\d+/).innerText()).match(/CR-\d{4}-\d+/)[0]

await nav('My Requests'); await measure('my-requests', null)

// --- analyst inbox
await actAs('Amara Chen'); await nav('Assessments'); await measure('assessments', 'Open')
// scroll-right evidence: bottom of page
await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight))
await page.screenshot({ path: `${OUT}/assessments-bottom.png` })

// route to committee to see the queue (same path as DEF-001 repro)
await page.getByRole('row').filter({ hasText: stamp }).first().getByRole('button', { name: 'Open' }).evaluate((b) => b.click())
await page.getByRole('tab', { name: 'Finalize' }).click()
const rc = page.locator('[data-slot="card"]').filter({ hasText: 'Readiness' }).first()
await rc.getByRole('button', { name: 'Finalize' }).click(); await toast('Assessment finalized').waitFor()
await rc.getByRole('button', { name: 'Route to committee' }).click(); await toast('Routed to committee').waitFor()
await page.screenshot({ path: `${OUT}/workspace-header.png` })

await actAs('Jordan Blake'); await nav('Committee Queue')
const qm = await measure('committee-queue', null)
out['committee-queue'].buttons = await page.getByRole('row').filter({ hasText: stamp }).first().locator('button').allTextContents()

console.log(JSON.stringify(out, null, 1))
await browser.close()
