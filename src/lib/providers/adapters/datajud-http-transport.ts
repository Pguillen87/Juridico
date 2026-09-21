import {
  type DataJudTransport,
  type DataJudTransportRequest,
  type DataJudTransportResult,
} from './datajud-core';
import { resolveDataJudEndpoint } from '../datajud-endpoint-resolver';

export interface DataJudHttpTransportOptions {
  readonly apiKey?: string;
  readonly endpointBaseUrl?: string;
  readonly fetchFn?: typeof fetch;
}

export class DataJudHttpTransport implements DataJudTransport {
  private readonly apiKey: string | undefined;
  private readonly endpointBaseUrl: string;
  private readonly fetchFn: typeof fetch;

  constructor(options: DataJudHttpTransportOptions = {}) {
    this.apiKey = options.apiKey;
    this.endpointBaseUrl =
      options.endpointBaseUrl ?? 'https://api-publica.datajud.cnj.jus.br';
    this.fetchFn = options.fetchFn ?? fetch;
  }

  async execute(
    request: DataJudTransportRequest
  ): Promise<DataJudTransportResult> {
    if (!this.apiKey) {
      return { kind: 'transport_failure', code: 'not_configured' };
    }

    const resolution = resolveDataJudEndpoint(
      request.subjectRef,
      this.endpointBaseUrl
    );
    if (!resolution.supported) {
      return {
        status: 400,
        body: { error: `CNJ não suportado: ${resolution.reason}` },
        receivedAt: new Date().toISOString(),
      };
    }

    const cnjDigits = request.subjectRef.replace(/\D/g, '');
    const esQuery = {
      query: {
        match: {
          numeroProcesso: cnjDigits,
        },
      },
    };

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), request.timeoutMs);

    const authHeader = this.apiKey.startsWith('APIKey ')
      ? this.apiKey
      : `APIKey ${this.apiKey}`;

    try {
      const response = await this.fetchFn(resolution.url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: authHeader,
          'X-Correlation-Id': request.correlationId,
        },
        body: JSON.stringify(esQuery),
        signal: controller.signal,
      });

      clearTimeout(timeout);

      const retryAfterHeader =
        response.headers?.get('retry-after') ||
        response.headers?.get('Retry-After');

      let responseBody: unknown = undefined;
      const text = await response.text();
      if (text) {
        try {
          responseBody = JSON.parse(text);
        } catch {
          responseBody = text;
        }
      }

      return {
        status: response.status,
        body: responseBody,
        receivedAt: new Date().toISOString(),
        headers: retryAfterHeader
          ? { 'retry-after': retryAfterHeader }
          : undefined,
      };
    } catch (err: unknown) {
      clearTimeout(timeout);
      if (err instanceof Error && err.name === 'AbortError') {
        return {
          kind: 'transport_failure',
          code: 'timeout',
        };
      }
      return {
        kind: 'transport_failure',
        code: 'network',
      };
    }
  }
}
