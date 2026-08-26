import { z } from 'zod';

const dataJudConfigurationSchema = z.object({
  DATAJUD_TRANSPORT_MODE: z.string().optional(),
  DATAJUD_API_URL: z.string().optional(),
  DATAJUD_API_KEY: z.string().optional(),
});

export type DataJudConfiguration =
  | {
      readonly mode: 'fake';
      readonly credentialState: 'absent' | 'present';
      readonly endpointConfigured: boolean;
    }
  | {
      readonly mode: 'disabled';
      readonly reason: 'real_transport_disabled' | 'invalid_endpoint';
      readonly credentialState: 'absent' | 'present';
      readonly endpointConfigured: boolean;
    };

export function getDataJudConfiguration(
  source: Record<string, string | undefined> = process.env
): DataJudConfiguration {
  const values = dataJudConfigurationSchema.parse({
    DATAJUD_TRANSPORT_MODE: source.DATAJUD_TRANSPORT_MODE,
    DATAJUD_API_URL: source.DATAJUD_API_URL,
    DATAJUD_API_KEY: source.DATAJUD_API_KEY,
  });
  const mode = values.DATAJUD_TRANSPORT_MODE ?? 'fake';
  const credentialState = values.DATAJUD_API_KEY
    ? ('present' as const)
    : ('absent' as const);
  const endpointConfigured = values.DATAJUD_API_URL !== undefined;
  if (mode !== 'fake') {
    return {
      mode: 'disabled',
      reason: 'real_transport_disabled',
      credentialState,
      endpointConfigured,
    };
  }
  if (endpointConfigured) {
    const parsedEndpoint = z.string().url().safeParse(values.DATAJUD_API_URL);
    if (!parsedEndpoint.success) {
      return {
        mode: 'disabled',
        reason: 'invalid_endpoint',
        credentialState,
        endpointConfigured,
      };
    }
  }
  return { mode: 'fake', credentialState, endpointConfigured };
}
