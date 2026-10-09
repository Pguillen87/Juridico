import { describe, expect, it } from 'vitest';
import {
  parseStoredPortfolioColumnKeys,
  serializePortfolioColumnKeys,
} from './portfolio-column-visibility';

describe('portfolio column visibility', () => {
  const allowed = ['select', 'process', 'description', 'actions'] as const;
  const defaults = ['select', 'process', 'actions'] as const;

  it('restores only valid stored columns and always keeps required controls', () => {
    expect(
      parseStoredPortfolioColumnKeys(
        JSON.stringify(['process', 'unknown']),
        allowed,
        defaults
      )
    ).toEqual(['select', 'process', 'actions']);
  });

  it('falls back to defaults when storage is invalid', () => {
    expect(
      parseStoredPortfolioColumnKeys('{broken', allowed, defaults)
    ).toEqual(defaults);
  });

  it('serializes the selected keys as JSON', () => {
    expect(serializePortfolioColumnKeys(['select', 'process'])).toBe(
      '["select","process"]'
    );
  });
});
