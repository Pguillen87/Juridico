import { createDataJudProvider } from './adapters/datajud-core';
import { createManualProvider } from './adapters/manual';
import { ProviderGateway, ProviderRegistry } from './registry';

export function createTestProviderRegistry(): ProviderRegistry {
  return new ProviderRegistry([
    createDataJudProvider(),
    createManualProvider(),
  ]);
}

export function createTestProviderGateway(): ProviderGateway {
  return new ProviderGateway(createTestProviderRegistry());
}
