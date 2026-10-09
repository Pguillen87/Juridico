export const PORTFOLIO_COLUMN_VISIBILITY_STORAGE_KEY =
  'juridico.processes.visible-columns';

export function parseStoredPortfolioColumnKeys(
  serialized: string | null,
  allowedKeys: readonly string[],
  defaultKeys: readonly string[]
): string[] {
  if (!serialized) return [...defaultKeys];
  try {
    const parsed: unknown = JSON.parse(serialized);
    if (!Array.isArray(parsed)) return [...defaultKeys];
    const allowed = new Set(allowedKeys);
    const selected = parsed.filter(
      (key): key is string => typeof key === 'string' && allowed.has(key)
    );
    const requiredKeys = defaultKeys.filter(
      (key) => key === 'select' || key === 'actions'
    );
    const selectedKeys = new Set([...requiredKeys, ...selected]);
    return allowedKeys.filter((key) => selectedKeys.has(key));
  } catch {
    return [...defaultKeys];
  }
}

export function serializePortfolioColumnKeys(keys: readonly string[]) {
  return JSON.stringify(keys);
}
