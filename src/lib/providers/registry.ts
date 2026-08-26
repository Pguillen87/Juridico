import {
  PROVIDER_CONTRACT_VERSION,
  type ProviderAdapter,
  type ProviderCapability,
  type ProviderDescriptor,
  type ProviderFailureV1,
  type ProviderIdentity,
  type ProviderRequestV1,
  type ProviderResultV1,
} from './contract';
import { failurePolicy, sanitizeProviderMessage } from './errors';
import { assertProviderResult } from './normalize';

function providerIdentity(provider: ProviderDescriptor): ProviderIdentity {
  return {
    providerId: provider.providerId,
    providerKind: provider.providerKind,
    adapterVersion: provider.adapterVersion,
    contractVersion: provider.contractVersion,
  };
}

function providerFailure(
  provider: ProviderDescriptor,
  request: ProviderRequestV1,
  code: ProviderFailureV1['status'],
  errorCode: string
): ProviderFailureV1 {
  const policy = failurePolicy(code);
  return {
    kind: 'failure',
    status: code,
    provider: providerIdentity(provider),
    source: provider.providerKind,
    contractVersion: PROVIDER_CONTRACT_VERSION,
    capability: request.capability,
    errorCode,
    message: sanitizeProviderMessage(code),
    ...policy,
    sourceMetadata: {
      sourceType: provider.providerKind,
      providerId: provider.providerId,
      adapterVersion: provider.adapterVersion,
      contractVersion: PROVIDER_CONTRACT_VERSION,
      observedAt: request.requestedAt,
      durationMs: 0,
    },
    correlationId: request.correlationId,
  };
}

export class ProviderRegistry {
  private readonly byId: ReadonlyMap<string, ProviderAdapter>;

  constructor(adapters: readonly ProviderAdapter[]) {
    const entries = adapters.map(
      (adapter) => [adapter.descriptor.providerId, adapter] as const
    );
    if (new Set(entries.map(([id]) => id)).size !== entries.length) {
      throw new Error(
        'Registry de providers contém identificadores duplicados.'
      );
    }
    this.byId = new Map(entries);
  }

  listProviders(): readonly ProviderDescriptor[] {
    return [...this.byId.values()].map((adapter) => adapter.descriptor);
  }

  getProvider(providerId: string): ProviderAdapter | undefined {
    return this.byId.get(providerId);
  }

  supports(providerId: string, capability: ProviderCapability): boolean {
    return (
      this.byId.get(providerId)?.descriptor.capabilities.includes(capability) ??
      false
    );
  }
}

export type ProviderExecutionWithPayload = {
  readonly result: ProviderResultV1;
  readonly rawPayload?: unknown;
};

type PayloadCapableProvider = ProviderAdapter & {
  observeWithPayload(
    request: ProviderRequestV1,
    input?: unknown
  ): Promise<ProviderExecutionWithPayload>;
};

function supportsPayload(
  provider: ProviderAdapter
): provider is PayloadCapableProvider {
  return (
    'observeWithPayload' in provider &&
    typeof provider.observeWithPayload === 'function'
  );
}

export class ProviderGateway {
  constructor(private readonly registry: ProviderRegistry) {}

  async observe(
    providerId: string,
    request: ProviderRequestV1,
    input?: unknown
  ): Promise<ProviderResultV1> {
    const provider = this.registry.getProvider(providerId);
    if (!provider) {
      return providerFailure(
        {
          providerId: 'unknown',
          providerKind: 'unknown',
          displayName: 'Provider não registrado',
          adapterVersion: 'unknown',
          contractVersion: PROVIDER_CONTRACT_VERSION,
          capabilities: [],
        },
        request,
        'not_supported',
        'provider_not_registered'
      );
    }
    if (!provider.descriptor.capabilities.includes(request.capability)) {
      return providerFailure(
        provider.descriptor,
        request,
        'not_supported',
        'capability_not_supported'
      );
    }
    return assertProviderResult(
      await provider.observe(request, input),
      request,
      provider.descriptor
    );
  }

  async observeWithPayload(
    providerId: string,
    request: ProviderRequestV1,
    input?: unknown
  ): Promise<ProviderExecutionWithPayload> {
    const provider = this.registry.getProvider(providerId);
    if (!provider) {
      return {
        result: providerFailure(
          {
            providerId: 'unknown',
            providerKind: 'unknown',
            displayName: 'Provider não registrado',
            adapterVersion: 'unknown',
            contractVersion: PROVIDER_CONTRACT_VERSION,
            capabilities: [],
          },
          request,
          'not_supported',
          'provider_not_registered'
        ),
      };
    }
    if (!provider.descriptor.capabilities.includes(request.capability)) {
      return {
        result: providerFailure(
          provider.descriptor,
          request,
          'not_supported',
          'capability_not_supported'
        ),
      };
    }
    if (!supportsPayload(provider)) {
      return {
        result: assertProviderResult(
          await provider.observe(request, input),
          request,
          provider.descriptor
        ),
      };
    }
    const execution = await provider.observeWithPayload(request, input);
    return {
      result: assertProviderResult(
        execution.result,
        request,
        provider.descriptor
      ),
      ...(execution.rawPayload !== undefined
        ? { rawPayload: execution.rawPayload }
        : {}),
    };
  }
}
