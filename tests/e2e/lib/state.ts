import fs from 'node:fs'
import path from 'node:path'
import { test } from '@playwright/test'
import { RUN_ID } from './harness'

// Playwright tears the worker down after any failing test, which wipes module-level variables.
// Lifecycle specs deliberately keep going past a failed defect probe (the rest of the flow is
// still worth executing), so their shared ids live on disk, keyed by run.
const FILE = path.join(__dirname, '..', 'results', `state-${RUN_ID}.json`)

function read(): Record<string, any> {
  try {
    return JSON.parse(fs.readFileSync(FILE, 'utf8'))
  } catch {
    return {}
  }
}

export const state = {
  get<T = any>(key: string): T {
    return read()[key]
  },
  set(key: string, value: unknown) {
    fs.mkdirSync(path.dirname(FILE), { recursive: true })
    fs.writeFileSync(FILE, JSON.stringify({ ...read(), [key]: value }, null, 2))
  },
  /** Skips the current test (rather than cascading a confusing failure) if a prerequisite is missing. */
  need<T = any>(key: string): T {
    const v = read()[key]
    test.skip(v === undefined || v === null, `Prerequisite "${key}" was not produced by an earlier step`)
    return v
  },
}
