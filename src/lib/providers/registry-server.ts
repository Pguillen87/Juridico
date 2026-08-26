import 'server-only';

import { createDataJudProvider } from './adapters/datajud-server';
import { createManualProvider } from './adapters/manual';
import { ProviderGateway, ProviderRegistry } from './registry';

export function createDefaultProviderRegistry(): ProviderRegistry {
  return new ProviderRegistry([
    createDataJudProvider(),
    createManualProvider(),
  ]);
}

export function createDefaultProviderGateway(): ProviderGateway {
  return new ProviderGateway(createDefaultProviderRegistry());
}
