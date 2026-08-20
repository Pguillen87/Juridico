import { describe, it, expect } from 'vitest';
import { createRequire } from 'node:module';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

const require = createRequire(import.meta.url);
const { generateRawHash, writeEvidence } = require('./evidence.js');

describe('Gestão de Evidências (evidence.js)', () => {
  it('deve gerar o rawHash exatamente como SHA-256 do rawText original', () => {
    const exactRawText = '{ "hits" : { "hits" : [] } }\n';
    const expectedHash = crypto
      .createHash('sha256')
      .update(exactRawText)
      .digest('hex');

    expect(generateRawHash(exactRawText)).toBe(expectedHash);
  });

  it('deve gerar hash diferente se houver diferença de whitespace', () => {
    const rawText1 = '{ "hits" : { "hits" : [] } }\n';
    const rawText2 = '{"hits":{"hits":[]}}'; // Mesmo json, texto diferente

    expect(generateRawHash(rawText1)).not.toBe(generateRawHash(rawText2));
  });

  it('deve preservar o rawText exato em raw.json e o rawHash correto em hashes.json', () => {
    const runDir = path.join(__dirname, 'test_evidence_temp');
    const exactRawText = '{ \n  "hits" : { \n    "hits" : [] \n  } \n}';
    const fakeResponse = {
      state: 'success_without_changes',
      durationMs: 123,
      rawText: exactRawText,
      snapshotHash: 'dummy_snapshot_hash',
    };

    try {
      writeEvidence(runDir, fakeResponse);

      const savedRaw = fs.readFileSync(path.join(runDir, 'raw.json'), 'utf8');
      expect(savedRaw).toBe(exactRawText); // Comprova ausência de JSON.stringify()

      const savedHashes = JSON.parse(
        fs.readFileSync(path.join(runDir, 'hashes.json'), 'utf8')
      );
      const expectedHash = crypto
        .createHash('sha256')
        .update(exactRawText)
        .digest('hex');
      expect(savedHashes.rawHash).toBe(expectedHash);
      expect(savedHashes.snapshotHash).toBe('dummy_snapshot_hash');
    } finally {
      fs.rmSync(runDir, { recursive: true, force: true });
    }
  });
});
