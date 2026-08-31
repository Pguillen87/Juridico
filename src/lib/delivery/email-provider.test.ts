import { describe, expect, it, vi } from 'vitest';

vi.mock('server-only', () => ({}));
import { FakeEmailProvider, type EmailMessage } from './email-provider';

const message: EmailMessage = {
  idempotencyKey: 'version-1:client@example.test:hash',
  to: 'client@example.test',
  subject: 'Synthetic report',
  text: 'Synthetic fixture',
  artifact: {
    filename: 'report.pdf',
    bytes: Buffer.from('%PDF-1.7\nfixture\n%%EOF'),
    sha256: 'b'.repeat(64),
  },
};

describe('fake email provider contracts', () => {
  it.each([
    ['delivered', 'delivered'],
    ['retryable_failure', 'retryable_failure'],
    ['terminal_failure', 'terminal_failure'],
    ['unknown_outcome', 'unknown_outcome'],
  ] as const)('returns deterministic %s outcome', (outcome, expected) => {
    const provider = new FakeEmailProvider({ outcome });
    return expect(provider.send(message)).resolves.toMatchObject({
      status: expected,
    });
  });

  it('does not convert an unknown timeout into a failure or delivery', async () => {
    const provider = new FakeEmailProvider({ outcome: 'unknown_outcome' });
    const result = await provider.send(message);
    expect(result).toMatchObject({
      status: 'unknown_outcome',
      retryable: false,
    });
    expect(result.providerResponse).toContain('timeout');
  });

  it('rejects invalid recipients before delivery', async () => {
    const provider = new FakeEmailProvider({ outcome: 'delivered' });
    await expect(provider.send({ ...message, to: 'invalid' })).rejects.toThrow(
      /recipient/i
    );
  });
});
