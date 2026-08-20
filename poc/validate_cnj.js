const cnjs = [
  '0004453-12.2026.8.16.0000',
  '0008569-61.2026.8.16.0000',
  '0002557-31.2026.8.16.0000',
  '0008902-13.2026.8.16.0000',
  '0003907-54.2026.8.16.0000',
  '0123860-46.2025.8.16.0000',
  '0152098-75.2025.8.16.0000',
  '0099021-54.2025.8.16.0000',
  '0143282-07.2025.8.16.0000',
  '0129656-18.2025.8.16.0000',
];

function calculateCheckDigits(clean) {
  const base = clean.slice(0, 7) + clean.slice(9);
  const expected = 98n - ((BigInt(base) * 100n) % 97n);
  return expected.toString().padStart(2, '0');
}

function validateCnj(cnj) {
  const clean = cnj.replace(/\D/g, '');
  const isValidLength = clean.length === 20;
  const segment = isValidLength ? clean.substring(13, 14) : '';
  const tribunal = isValidLength ? clean.substring(14, 16) : '';
  const actualCheckDigits = isValidLength ? clean.substring(7, 9) : '';
  const expectedCheckDigits = isValidLength ? calculateCheckDigits(clean) : '';
  const checkDigitsValid =
    isValidLength && actualCheckDigits === expectedCheckDigits;
  const belongsToTjpr = segment === '8' && tribunal === '16';
  const isValid = isValidLength && checkDigitsValid && belongsToTjpr;

  let reason = '';
  if (!isValidLength) reason = `Tamanho inválido: ${clean.length} dígitos.`;
  else if (!checkDigitsValid)
    reason = `Dígitos verificadores inválidos: esperado ${expectedCheckDigits}, recebido ${actualCheckDigits}.`;
  else if (!belongsToTjpr)
    reason = `Segmento (${segment}) ou tribunal (${tribunal}) não corresponde ao TJPR (8.16).`;

  return {
    original: cnj,
    clean,
    isValidLength,
    segment,
    tribunal,
    actualCheckDigits,
    expectedCheckDigits,
    checkDigitsValid,
    endpointAlias: belongsToTjpr ? 'api_publica_tjpr' : null,
    isValid,
    reason,
  };
}

if (require.main === module) {
  console.log(JSON.stringify(cnjs.map(validateCnj), null, 2));
}

module.exports = { calculateCheckDigits, validateCnj };
