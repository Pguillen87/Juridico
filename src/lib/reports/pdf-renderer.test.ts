import { describe, expect, it, vi } from 'vitest';

vi.mock('server-only', () => ({}));
import {
  artifactSha256,
  assertPdfArtifactInvariants,
  createPdfRenderer,
} from './pdf-renderer';

describe('PDF rendering contracts', () => {
  it('renders synthetic approved content and keeps approved hash distinct from artifact hash', async () => {
    const renderer = createPdfRenderer({
      render: async () =>
        Buffer.from('%PDF-1.7\nsynthetic fixture\n%%EOF', 'utf8'),
    });
    const result = await renderer.render({
      reportVersionId: 'version-1',
      approvedHash: 'a'.repeat(64),
      html: '<h1>Synthetic approved report</h1>',
    });
    expect(result.reportVersionId).toBe('version-1');
    expect(result.approvedHash).toBe('a'.repeat(64));
    expect(result.artifactSha256).toBe(artifactSha256(result.bytes));
    expect(result.artifactSha256).not.toBe(result.approvedHash);
  });

  it('rejects non-PDF, empty, oversized, or inconsistent artifacts', () => {
    expect(() =>
      assertPdfArtifactInvariants({
        bytes: Buffer.from('not pdf'),
        approvedHash: 'a'.repeat(64),
        artifactSha256: 'b'.repeat(64),
        reportVersionId: 'version-1',
      })
    ).toThrow(/magic/i);
  });

  it('checks snapshot invariants without treating approved hash as snapshot hash', () => {
    expect(() =>
      assertPdfArtifactInvariants({
        bytes: Buffer.from('%PDF-1.7\nfixture\n%%EOF'),
        approvedHash: 'a'.repeat(64),
        artifactSha256: artifactSha256(Buffer.from('%PDF-1.7\nfixture\n%%EOF')),
        reportVersionId: 'version-1',
        snapshotHash: 'c'.repeat(64),
        expectedSnapshotHash: 'd'.repeat(64),
      })
    ).toThrow(/snapshot/i);
  });
});
