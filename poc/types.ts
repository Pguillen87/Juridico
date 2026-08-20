export type ProviderCapability = 
  | 'basic_data' 
  | 'movements' 
  | 'parties' 
  | 'publications' 
  | 'documents' 
  | 'sealed_process';

export type QueryState = 
  | 'pending'
  | 'running'
  | 'success_with_changes'
  | 'success_without_changes'
  | 'source_unavailable'
  | 'process_not_found'
  | 'unsupported'
  | 'rate_limited'
  | 'timeout'
  | 'failed'
  | 'manual_review_required';

export interface ProcessParty {
  name: string;
  role?: string;
  document?: string;
}

export interface ProcessMovement {
  code?: number;
  description: string;
  date: string;
  stableHash: string; // Hash determinístico gerado na normalização
}

export interface NormalizedProcess {
  cnjNumber: string;
  tribunal: string;
  system?: string;
  source: string;
  externalId?: string;
  lastUpdateDate?: string;
  parties?: ProcessParty[];
  movements: ProcessMovement[];
}

export interface ProviderResponse {
  rawPayload: Record<string, any>;
  normalizedData?: NormalizedProcess;
  capabilitiesProvided: ProviderCapability[];
  state: QueryState;
  errorCode?: string;
  errorMessage?: string;
}

export interface ProcessProvider {
  id(): string;
  capabilities(): ProviderCapability[];
  canQuery(cnjNumber: string, tribunalAlias: string): boolean;
  query(cnjNumber: string, tribunalAlias: string): Promise<ProviderResponse>;
}
