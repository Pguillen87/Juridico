import 'server-only';

import { createDataJudPublicProvider } from './adapters/datajud-public';
import { DataJudHttpTransport } from './adapters/datajud-http-transport';
import { getDataJudConfiguration } from './datajud-config-core';
import { createManualProvider } from './adapters/manual';
import { ProviderGateway, ProviderRegistry } from './registry';

export function createDefaultProviderRegistry(): ProviderRegistry {
  const configuration = getDataJudConfiguration();
  const liveConfiguration = configuration.mode === 'live';
  const publicTransport = new DataJudHttpTransport({
    apiKey: liveConfiguration ? process.env.DATAJUD_API_KEY : undefined,
    endpointBaseUrl: liveConfiguration
      ? process.env.DATAJUD_API_URL
      : undefined,
  });

  return new ProviderRegistry([
    createDataJudPublicProvider(publicTransport),
    createManualProvider(),
  ]);
}

export function createDefaultProviderGateway(): ProviderGateway {
  return new ProviderGateway(createDefaultProviderRegistry());
}
