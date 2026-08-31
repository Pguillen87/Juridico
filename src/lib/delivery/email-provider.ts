import 'server-only';

export const EMAIL_OUTCOMES = [
  'delivered',
  'retryable_failure',
  'terminal_failure',
  'unknown_outcome',
] as const;
export type EmailOutcome = (typeof EMAIL_OUTCOMES)[number];

export type EmailMessage = {
  readonly idempotencyKey: string;
  readonly to: string;
  readonly subject: string;
  readonly text: string;
  readonly artifact: {
    readonly filename: string;
    readonly bytes: Uint8Array;
    readonly sha256: string;
  };
};

export type EmailSendResult = {
  readonly status: EmailOutcome;
  readonly retryable: boolean;
  readonly providerResponse: string;
  readonly idempotencyKey: string;
};

export interface EmailProvider {
  send(message: EmailMessage): Promise<EmailSendResult>;
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export class FakeEmailProvider implements EmailProvider {
  readonly outcome: EmailOutcome;

  constructor(options: { readonly outcome?: EmailOutcome } = {}) {
    this.outcome = options.outcome ?? 'delivered';
  }

  async send(message: EmailMessage): Promise<EmailSendResult> {
    if (!EMAIL.test(message.to)) throw new Error('Invalid email recipient.');
    if (!message.idempotencyKey.trim())
      throw new Error('Email idempotency key is required.');
    if (!message.subject.trim()) throw new Error('Email subject is required.');
    if (message.artifact.bytes.byteLength === 0)
      throw new Error('Email artifact is required.');

    // Unknown is intentionally not mapped to either failure class: callers must decide.
    return {
      status: this.outcome,
      retryable: this.outcome === 'retryable_failure',
      providerResponse:
        this.outcome === 'unknown_outcome'
          ? 'synthetic timeout: outcome unknown'
          : `synthetic ${this.outcome}`,
      idempotencyKey: message.idempotencyKey,
    };
  }
}
