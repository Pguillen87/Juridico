import 'server-only';

import { createHash } from 'node:crypto';

export const PDF_MAGIC_BYTES = '%PDF-' as const;
const PDF_MAGIC = Buffer.from(PDF_MAGIC_BYTES);
const SHA256 = /^[a-f0-9]{64}$/;
const DEFAULT_MAX_BYTES = 25 * 1024 * 1024;

export type PdfRenderInput = {
  readonly reportVersionId: string;
  readonly approvedHash: string;
  readonly html: string;
};

export type PdfArtifact = {
  readonly reportVersionId: string;
  readonly approvedHash: string;
  readonly artifactSha256: string;
  readonly bytes: Uint8Array;
};

export interface PdfRenderer {
  render(input: PdfRenderInput): Promise<PdfArtifact>;
}

export type PdfArtifactInvariantInput = PdfArtifact & {
  readonly snapshotHash?: string;
  readonly expectedSnapshotHash?: string;
  readonly maxBytes?: number;
};

export function artifactSha256(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

export function assertSnapshotInvariants(
  snapshotHash: string,
  expectedSnapshotHash: string
): void {
  if (!SHA256.test(snapshotHash) || !SHA256.test(expectedSnapshotHash))
    throw new Error('Invalid snapshot hash.');
  if (snapshotHash !== expectedSnapshotHash)
    throw new Error('Snapshot hash invariant violated.');
}

export function assertPdfArtifactInvariants(
  input: PdfArtifactInvariantInput
): void {
  if (!input.reportVersionId.trim())
    throw new Error('Report version is required.');
  if (!SHA256.test(input.approvedHash))
    throw new Error('Invalid approved hash.');
  if (!SHA256.test(input.artifactSha256))
    throw new Error('Invalid artifact SHA-256.');
  if (input.bytes.byteLength === 0)
    throw new Error('PDF artifact cannot be empty.');
  if (input.bytes.byteLength > (input.maxBytes ?? DEFAULT_MAX_BYTES))
    throw new Error('PDF artifact exceeds maximum size.');
  if (!Buffer.from(input.bytes).subarray(0, PDF_MAGIC.length).equals(PDF_MAGIC))
    throw new Error('PDF artifact has invalid magic bytes.');
  if (artifactSha256(input.bytes) !== input.artifactSha256)
    throw new Error('Artifact SHA-256 does not match bytes.');
  if (
    input.snapshotHash !== undefined &&
    input.expectedSnapshotHash !== undefined
  )
    assertSnapshotInvariants(input.snapshotHash, input.expectedSnapshotHash);
  else if (input.snapshotHash !== undefined && !SHA256.test(input.snapshotHash))
    throw new Error('Invalid snapshot hash.');
}

export const validatePdfArtifact = assertPdfArtifactInvariants;

type PdfByteRenderer = (html: string) => Promise<Uint8Array>;

export function createPdfRenderer(options: {
  readonly render: PdfByteRenderer;
}): PdfRenderer {
  return {
    async render(input) {
      const bytes = await options.render(input.html);
      const result: PdfArtifact = {
        reportVersionId: input.reportVersionId,
        approvedHash: input.approvedHash,
        artifactSha256: artifactSha256(bytes),
        bytes,
      };
      assertPdfArtifactInvariants(result);
      return result;
    },
  };
}

/** Uses an already-installed Playwright Chromium; no browser or network is provisioned. */
export async function createPlaywrightPdfRenderer(): Promise<PdfRenderer> {
  const { chromium } = await import('playwright');
  return createPdfRenderer({
    render: async (html) => {
      const browser = await chromium.launch({ headless: true });
      try {
        const page = await browser.newPage();
        await page.setContent(html, { waitUntil: 'load' });
        return await page.pdf({ format: 'A4', printBackground: true });
      } finally {
        await browser.close();
      }
    },
  });
}
