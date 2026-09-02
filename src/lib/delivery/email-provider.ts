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

export const EMAIL_RECONCILIATION_OUTCOMES = [
  'positive_confirmation',
  'negative_confirmation',
  'still_unknown',
] as const;
export type EmailReconciliationOutcome =
  (typeof EMAIL_RECONCILIATION_OUTCOMES)[number];

export type EmailReconciliationResult = {
  readonly status: EmailReconciliationOutcome;
  readonly providerResponse: string;
  readonly providerReference: string;
};

export interface EmailProvider {
  send(message: EmailMessage): Promise<EmailSendResult>;
  reconcile(providerReference: string): Promise<EmailReconciliationResult>;
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export class FakeEmailProvider implements EmailProvider {
  readonly outcome: EmailOutcome;

  constructor(options: { readonly outcome?: EmailOutcome } = {}) {
    this.outcome = options.outcome ?? 'delivered';
  }

  static outcomeForDelivery(deliveryId: string): EmailOutcome {
    if (deliveryId.endsWith('102')) return 'retryable_failure';
    if (deliveryId.endsWith('103')) return 'terminal_failure';
    if (
      deliveryId.endsWith('104') ||
      deliveryId.endsWith('105') ||
      deliveryId.endsWith('106')
    )
      return 'unknown_outcome';
    return 'delivered';
  }

  static reconciliationForReference(
    providerReference: string
  ): EmailReconciliationOutcome {
    if (providerReference.includes('105')) return 'negative_confirmation';
    if (providerReference.includes('106')) return 'still_unknown';
    return 'positive_confirmation';
  }

  async reconcile(
    providerReference: string
  ): Promise<EmailReconciliationResult> {
    if (!providerReference.trim())
      throw new Error('Provider reference is required.');
    const status =
      FakeEmailProvider.reconciliationForReference(providerReference);
    return {
      status,
      providerResponse: `synthetic ${status}`,
      providerReference,
    };
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
