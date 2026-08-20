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
  classe?: string;
  assuntos?: string[];
  dataAjuizamento?: string;
  lastUpdateDate?: string;
  source: string;
  movements: ProcessMovement[];
}

export interface ProviderResponse {
  state: QueryState;
  rawText: string | null;
  parsedPayload: any | null;
  normalizedData?: NormalizedProcess;
  snapshotHash?: string;
  capabilitiesProvided?: ProviderCapability[];
  errorCode?: string;
  errorMessage?: string;
  httpStatus?: number;
  durationMs: number;
}

export interface ProcessProvider {
  id(): string;
  capabilities(): ProviderCapability[];
  canQuery(cnjNumber: string, tribunalAlias: string): boolean;
  query(cnjNumber: string, tribunalAlias: string): Promise<ProviderResponse>;
}
