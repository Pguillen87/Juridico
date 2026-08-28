import { describe, expect, it } from 'vitest';
import { isWithinReportPeriod, weeklyReportPeriod } from './period';

describe('weeklyReportPeriod', () => {
  it('closes the week at Friday 17:00 in São Paulo', () => {
    const period = weeklyReportPeriod(new Date('2026-08-28T21:00:00.000Z'));
    expect(period.timezone).toBe('America/Sao_Paulo');
    expect(period.periodEndUtc).toBe('2026-08-28T20:00:00.000Z');
    expect(period.periodStartUtc).toBe('2026-08-21T20:00:00.000Z');
  });

  it('does not use a cutoff that is still in the future', () => {
    const period = weeklyReportPeriod(new Date('2026-08-28T19:00:00.000Z'));
    expect(period.periodEndUtc).toBe('2026-08-21T20:00:00.000Z');
  });

  it('uses an inclusive start and exclusive end', () => {
    const period = weeklyReportPeriod(new Date('2026-08-28T21:00:00.000Z'));
    expect(isWithinReportPeriod(period.periodStartUtc, period)).toBe(true);
    expect(isWithinReportPeriod(period.periodEndUtc, period)).toBe(false);
    expect(isWithinReportPeriod('2026-08-22T00:00:00.000Z', period)).toBe(true);
  });

  it('uses the IANA timezone rules when the historical offset changes', () => {
    const period = weeklyReportPeriod(new Date('2019-02-22T21:00:00.000Z'));
    expect(period.periodEndUtc).toBe('2019-02-22T20:00:00.000Z');
    expect(period.periodStartUtc).toBe('2019-02-15T19:00:00.000Z');
  });

  it('rejects an invalid reference date', () => {
    expect(() => weeklyReportPeriod(new Date('invalid'))).toThrow(
      'Data de referência inválida.'
    );
  });
});
