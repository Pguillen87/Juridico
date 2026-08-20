const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

/**
 * Calcula o SHA-256 do texto bruto recebido.
 */
function generateRawHash(rawText) {
  if (typeof rawText !== 'string') return null;
  return crypto.createHash('sha256').update(rawText).digest('hex');
}

/**
 * Grava as evidências de uma rodada da PoC.
 */
function writeEvidence(runDir, providerResponse) {
  fs.mkdirSync(runDir, { recursive: true });

  if (providerResponse.rawText) {
    fs.writeFileSync(path.join(runDir, 'raw.json'), providerResponse.rawText);

    const rawHash = generateRawHash(providerResponse.rawText);
    const hashesObj = { rawHash };
    if (providerResponse.snapshotHash)
      hashesObj.snapshotHash = providerResponse.snapshotHash;
    fs.writeFileSync(
      path.join(runDir, 'hashes.json'),
      JSON.stringify(hashesObj, null, 2)
    );

    if (providerResponse.normalizedData) {
      fs.writeFileSync(
        path.join(runDir, 'normalized.json'),
        JSON.stringify(providerResponse.normalizedData, null, 2)
      );
    }
  }

  const metadata = {
    state: providerResponse.state,
    durationMs: providerResponse.durationMs,
  };
  if (providerResponse.httpStatus)
    metadata.httpStatus = providerResponse.httpStatus;
  if (providerResponse.errorCode)
    metadata.errorCode = providerResponse.errorCode;
  if (providerResponse.errorMessage)
    metadata.errorMessage = providerResponse.errorMessage;
  fs.writeFileSync(
    path.join(runDir, 'metadata.json'),
    JSON.stringify(metadata, null, 2)
  );
}

module.exports = {
  generateRawHash,
  writeEvidence,
};
