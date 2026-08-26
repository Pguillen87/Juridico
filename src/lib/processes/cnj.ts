export type CnjValidation = {
  input: string;
  normalized: string | null;
  valid: boolean;
  error?: string;
};

export function normalizeCnj(input: string): string {
  const clean = String(input ?? '').replace(/\D/g, '');
  if (clean.length !== 20) {
    throw new Error(
      `CNJ inválido: esperado exatamente 20 dígitos; recebido ${clean.length}.`
    );
  }

  const base = clean.slice(0, 7) + clean.slice(9);
  const expected = String(
    98 - Number((BigInt(base) * BigInt(100)) % BigInt(97))
  ).padStart(2, '0');
  const actual = clean.slice(7, 9);
  if (actual !== expected) {
    throw new Error(
      `CNJ inválido: dígitos verificadores esperados ${expected}; recebidos ${actual}.`
    );
  }
  return clean;
}

export function validateCnj(input: string): CnjValidation {
  try {
    return { input, normalized: normalizeCnj(input), valid: true };
  } catch (error) {
    return {
      input,
      normalized: null,
      valid: false,
      error: error instanceof Error ? error.message : 'CNJ inválido.',
    };
  }
}

export function formatCnj(cnj: string): string {
  const normalized = normalizeCnj(cnj);
  return `${normalized.slice(0, 7)}-${normalized.slice(7, 9)}.${normalized.slice(9, 13)}.${normalized.slice(13, 14)}.${normalized.slice(14, 16)}.${normalized.slice(16)}`;
}
