// Extracted fields are keyed by their stored name (e.g. "target_customers" or "dailyLimit").
// Show a readable title instead; the stored key is still what gets sent back to the API.
export function formatFieldKey(key) {
  if (!key) return ''
  const words = String(key)
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .split(/[\s_-]+/)
    .filter(Boolean)
  // An all-caps word is an acronym (KYC, PEP): leave it as it is.
  return words
    .map((w) => (w.length > 1 && w === w.toUpperCase() ? w : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()))
    .join(' ')
}
