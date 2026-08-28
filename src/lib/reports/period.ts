const REPORT_TIMEZONE = 'America/Sao_Paulo';

type ZonedParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

export type ReportPeriod = {
  readonly periodStartUtc: string;
  readonly periodEndUtc: string;
  readonly timezone: typeof REPORT_TIMEZONE;
};

const formatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: REPORT_TIMEZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hourCycle: 'h23',
});

function zonedParts(date: Date): ZonedParts {
  const values = Object.fromEntries(
    formatter.formatToParts(date).map((part) => [part.type, part.value])
  );
  return {
    year: Number(values.year),
    month: Number(values.month),
    day: Number(values.day),
    hour: Number(values.hour),
    minute: Number(values.minute),
    second: Number(values.second),
  };
}

function dateOnlyUtc(parts: Pick<ZonedParts, 'year' | 'month' | 'day'>): Date {
  return new Date(Date.UTC(parts.year, parts.month - 1, parts.day));
}

function localDateAtHourUtc(
  parts: Pick<ZonedParts, 'year' | 'month' | 'day'>,
  hour: number
): Date {
  const wallClockMs = Date.UTC(parts.year, parts.month - 1, parts.day, hour);
  let guess = new Date(wallClockMs);
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const observed = zonedParts(guess);
    const observedWallClockMs = Date.UTC(
      observed.year,
      observed.month - 1,
      observed.day,
      observed.hour,
      observed.minute,
      observed.second
    );
    const correction = wallClockMs - observedWallClockMs;
    if (correction === 0) return guess;
    guess = new Date(guess.getTime() + correction);
  }
  return guess;
}

function subtractCalendarDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setUTCDate(result.getUTCDate() - days);
  return result;
}

function fridayAtFivePmUtc(localDate: Date): Date {
  return localDateAtHourUtc(
    {
      year: localDate.getUTCFullYear(),
      month: localDate.getUTCMonth() + 1,
      day: localDate.getUTCDate(),
    },
    17
  );
}

export function weeklyReportPeriod(asOfUtc: Date): ReportPeriod {
  if (Number.isNaN(asOfUtc.getTime()))
    throw new Error('Data de referência inválida.');
  const parts = zonedParts(asOfUtc);
  const localDate = dateOnlyUtc(parts);
  const daysSinceFriday = (localDate.getUTCDay() - 5 + 7) % 7;
  let endLocalDate = subtractCalendarDays(localDate, daysSinceFriday);
  let periodEnd = fridayAtFivePmUtc(endLocalDate);
  if (periodEnd > asOfUtc) {
    endLocalDate = subtractCalendarDays(endLocalDate, 7);
    periodEnd = fridayAtFivePmUtc(endLocalDate);
  }
  const startLocalDate = subtractCalendarDays(endLocalDate, 7);
  const periodStart = fridayAtFivePmUtc(startLocalDate);
  return {
    periodStartUtc: periodStart.toISOString(),
    periodEndUtc: periodEnd.toISOString(),
    timezone: REPORT_TIMEZONE,
  };
}

export function isWithinReportPeriod(
  occurredAt: string,
  period: Pick<ReportPeriod, 'periodStartUtc' | 'periodEndUtc'>
): boolean {
  const timestamp = Date.parse(occurredAt);
  const start = Date.parse(period.periodStartUtc);
  const end = Date.parse(period.periodEndUtc);
  if ([timestamp, start, end].some(Number.isNaN)) return false;
  return timestamp >= start && timestamp < end;
}
