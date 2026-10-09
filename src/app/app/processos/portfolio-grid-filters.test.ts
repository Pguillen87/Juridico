import { describe, expect, it } from 'vitest';
import { parsePortfolioGridFilters } from './portfolio-grid-filters';

describe('portfolio grid filters', () => {
  it('normalizes the simple filters used by the process grid', () => {
    expect(
      parsePortfolioGridFilters({
        clientId: '00000000-0000-0000-0000-000000000001',
        q: '  sentença  ',
        state: 'changed',
        visibility: 'private',
      })
    ).toEqual({
      clientId: '00000000-0000-0000-0000-000000000001',
      search: 'sentença',
      state: 'changed',
      isPublic: false,
    });
  });

  it('ignores invalid or empty query values instead of trusting the browser', () => {
    expect(
      parsePortfolioGridFilters({
        clientId: 'not-a-uuid',
        q: '   ',
        state: 'internal_state',
        visibility: 'all',
      })
    ).toEqual({});
  });
});
