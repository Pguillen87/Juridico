import { createHash } from 'node:crypto';

import type {
  NormalizedMovement,
  NormalizedPartyObservation,
  NormalizedProcessObservation,
} from '@/lib/providers/contract';

export const COMPARISON_VERSION_V1 = 'comparison-v1' as const;
export const COMPARISON_VERSIONS = [COMPARISON_VERSION_V1] as const;
export type ComparisonVersion = (typeof COMPARISON_VERSIONS)[number];

export const COMPARISON_RESULTS = [
  'changed',
  'unchanged',
  'not_comparable',
] as const;
export type ComparisonResult = (typeof COMPARISON_RESULTS)[number];

export const COMPARISON_REASON_CODES = [
  'first_snapshot',
  'normalizer_incompatible',
  'source_incompatible',
  'required_field_missing',
  'snapshot_invalid',
  'baseline_incomplete',
] as const;
export type ComparisonReasonCode = (typeof COMPARISON_REASON_CODES)[number];

export const COMPARISON_CHANGE_TYPES = [
  'field_updated',
  'movement_added',
  'movement_removed',
  'movement_updated',
  'party_added',
  'party_removed',
  'party_updated',
] as const;
export type ComparisonChangeType = (typeof COMPARISON_CHANGE_TYPES)[number];

const COMPARABLE_MISSING_FIELDS = new Set([
  'tribunal',
  'system',
  'movements',
  'parties',
]);
const MAX_DIFF_ENTRIES = 200;
const MAX_CHANGED_FIELD_LENGTH = 512;
const MAX_COMPARISON_BYTES = 256 * 1024;
const MAX_CANONICAL_DEPTH = 24;
const MAX_CANONICAL_NODES = 10_000;

type ComparisonJson =
  | null
  | boolean
  | number
  | string
  | ComparisonJson[]
  | { readonly [key: string]: ComparisonJson };

export type ComparisonSnapshot = {
  readonly id: string;
  readonly officeId: string;
  readonly processId: string;
  readonly providerId: string;
  readonly source: string;
  readonly normalizerVersion: string;
  readonly normalizedData: NormalizedProcessObservation;
  readonly missingFields: readonly string[];
  readonly snapshotHash: string;
  readonly createdAt: string;
};

export type ComparisonDiffEntry = {
  readonly path: string;
  readonly changeType: ComparisonChangeType;
  readonly before?: ComparisonJson;
  readonly after?: ComparisonJson;
};

export type NormalizedComparisonDiff = {
  readonly entries: readonly ComparisonDiffEntry[];
};

export type ComparisonOutput = {
  readonly comparisonVersion: ComparisonVersion;
  readonly result: ComparisonResult;
  readonly reasonCode: ComparisonReasonCode | null;
  readonly changedFields: readonly string[];
  readonly normalizedDiff: NormalizedComparisonDiff;
  readonly comparisonHash: string;
};

export class ComparisonInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ComparisonInputError';
  }
}

export class UnknownComparisonVersionError extends ComparisonInputError {
  constructor(value: unknown) {
    super(`Versão de comparação não allowlisted: ${String(value)}`);
    this.name = 'UnknownComparisonVersionError';
  }
}

export function isComparisonVersion(
  value: unknown
): value is ComparisonVersion {
  return (
    typeof value === 'string' &&
    (COMPARISON_VERSIONS as readonly string[]).includes(value)
  );
}

export function assertComparisonVersion(
  value: unknown
): asserts value is ComparisonVersion {
  if (!isComparisonVersion(value)) {
    throw new UnknownComparisonVersionError(value);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function normalizedText(value: string, field: string): string {
  const normalized = value.normalize('NFC').trim();
  if (normalized.length === 0) {
    throw new ComparisonInputError(`${field} não pode ser vazio.`);
  }
  return normalized;
}

function normalizedDate(value: string, field: string): string {
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) {
    throw new ComparisonInputError(`${field} possui data inválida.`);
  }
  return new Date(parsed).toISOString();
}

function pointerPart(value: string): string {
  return value.replaceAll('~', '~0').replaceAll('/', '~1');
}

function canonicalJson(
  value: unknown,
  depth = 0,
  nodes = { count: 0 }
): ComparisonJson {
  if (depth > MAX_CANONICAL_DEPTH) {
    throw new ComparisonInputError(
      'Estrutura comparável excede a profundidade máxima.'
    );
  }
  nodes.count += 1;
  if (nodes.count > MAX_CANONICAL_NODES) {
    throw new ComparisonInputError(
      'Estrutura comparável excede o limite de itens.'
    );
  }
  if (value === null) return null;
  if (typeof value === 'boolean' || typeof value === 'string') return value;
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      throw new ComparisonInputError(
        'Número não finito na estrutura comparável.'
      );
    }
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => canonicalJson(item, depth + 1, nodes));
  }
  if (isRecord(value)) {
    const output: Record<string, ComparisonJson> = {};
    for (const key of Object.keys(value).sort()) {
      output[key] = canonicalJson(value[key], depth + 1, nodes);
    }
    return output;
  }
  throw new ComparisonInputError('Valor não serializável na comparação.');
}

export function canonicalizeComparison(value: unknown): string {
  return JSON.stringify(canonicalJson(value));
}

function comparisonHash(input: {
  readonly comparisonVersion: ComparisonVersion;
  readonly previousSnapshotId: string | null;
  readonly currentSnapshotId: string;
  readonly result: ComparisonResult;
  readonly reasonCode: ComparisonReasonCode | null;
  readonly changedFields: readonly string[];
  readonly normalizedDiff: NormalizedComparisonDiff;
}): string {
  const canonical = canonicalizeComparison(input);
  if (Buffer.byteLength(canonical, 'utf8') > MAX_COMPARISON_BYTES) {
    throw new ComparisonInputError(
      'Resultado comparativo excede o limite de tamanho.'
    );
  }
  return createHash('sha256').update(canonical, 'utf8').digest('hex');
}

function validateSnapshotShape(snapshot: ComparisonSnapshot): void {
  for (const [name, value] of Object.entries({
    id: snapshot.id,
    officeId: snapshot.officeId,
    processId: snapshot.processId,
    providerId: snapshot.providerId,
    source: snapshot.source,
    normalizerVersion: snapshot.normalizerVersion,
    snapshotHash: snapshot.snapshotHash,
    createdAt: snapshot.createdAt,
  })) {
    if (typeof value !== 'string' || value.trim() === '') {
      throw new ComparisonInputError(`Snapshot inválido: ${name}.`);
    }
  }
  if (!/^[0-9a-f]{64}$/.test(snapshot.snapshotHash)) {
    throw new ComparisonInputError('Snapshot inválido: snapshot_hash.');
  }
  if (Number.isNaN(Date.parse(snapshot.createdAt))) {
    throw new ComparisonInputError('Snapshot inválido: created_at.');
  }
  if (
    !Array.isArray(snapshot.missingFields) ||
    snapshot.missingFields.some((field) => typeof field !== 'string')
  ) {
    throw new ComparisonInputError('Snapshot inválido: missing_fields.');
  }
  const data = snapshot.normalizedData;
  if (!isRecord(data) || typeof data.processRef !== 'string') {
    throw new ComparisonInputError(
      'Snapshot inválido: normalized_data.processRef.'
    );
  }
}

function normalizedMissingFields(fields: readonly string[]): readonly string[] {
  const normalized = [
    ...new Set(fields.map((field) => normalizedText(field, 'missing_field'))),
  ].sort();
  if (normalized.some((field) => !COMPARABLE_MISSING_FIELDS.has(field))) {
    throw new ComparisonInputError(
      'Snapshot contém campo ausente fora da allowlist comparável.'
    );
  }
  return normalized;
}

function normalizeMovement(movement: NormalizedMovement): NormalizedMovement {
  if (typeof movement.movementRef !== 'string') {
    throw new ComparisonInputError('Movimento sem movementRef.');
  }
  const normalized: NormalizedMovement = {
    movementRef: normalizedText(movement.movementRef, 'movementRef'),
    ...(movement.date
      ? { date: normalizedDate(movement.date, 'movement.date') }
      : {}),
    ...(movement.description
      ? {
          description: normalizedText(
            movement.description,
            'movement.description'
          ),
        }
      : {}),
    missingFields: [...new Set(movement.missingFields ?? [])]
      .map((field) => normalizedText(field, 'movement.missingFields'))
      .sort(),
  };
  return normalized;
}

function normalizeParty(
  party: NormalizedPartyObservation
): NormalizedPartyObservation {
  if (typeof party.partyRef !== 'string') {
    throw new ComparisonInputError('Parte sem partyRef.');
  }
  return {
    partyRef: normalizedText(party.partyRef, 'partyRef'),
    ...(party.role ? { role: normalizedText(party.role, 'party.role') } : {}),
    missingFields: [...new Set(party.missingFields ?? [])]
      .map((field) => normalizedText(field, 'party.missingFields'))
      .sort(),
  };
}

function normalizeData(
  data: NormalizedProcessObservation
): NormalizedProcessObservation {
  const normalized: NormalizedProcessObservation = {
    processRef: normalizedText(data.processRef, 'processRef'),
    ...(data.tribunal
      ? { tribunal: normalizedText(data.tribunal, 'tribunal') }
      : {}),
    ...(data.system ? { system: normalizedText(data.system, 'system') } : {}),
    ...(data.movements
      ? {
          movements: data.movements
            .map(normalizeMovement)
            .sort((left, right) =>
              canonicalizeComparison(left).localeCompare(
                canonicalizeComparison(right)
              )
            ),
        }
      : {}),
    ...(data.parties
      ? {
          parties: data.parties
            .map(normalizeParty)
            .sort((left, right) =>
              canonicalizeComparison(left).localeCompare(
                canonicalizeComparison(right)
              )
            ),
        }
      : {}),
  };
  canonicalJson(normalized);
  return normalized;
}

function snapshotHasIncompleteFields(snapshot: ComparisonSnapshot): boolean {
  const topLevel = normalizedMissingFields(snapshot.missingFields);
  if (topLevel.length > 0) return true;
  const data = normalizeData(snapshot.normalizedData);
  if (!data.tribunal || !data.system || !data.movements || !data.parties)
    return true;
  return (
    data.movements.some((movement) => movement.missingFields.length > 0) ||
    data.parties.some((party) => party.missingFields.length > 0)
  );
}

function outputFor(
  version: ComparisonVersion,
  previous: ComparisonSnapshot | null,
  current: ComparisonSnapshot,
  result: ComparisonResult,
  reasonCode: ComparisonReasonCode | null,
  entries: readonly ComparisonDiffEntry[]
): ComparisonOutput {
  if (entries.length > MAX_DIFF_ENTRIES) {
    throw new ComparisonInputError(
      'Diff comparativo excede o limite de entradas.'
    );
  }
  const normalizedDiff: NormalizedComparisonDiff = {
    entries: entries.map((entry) => ({
      path: normalizedText(entry.path, 'diff.path').slice(
        0,
        MAX_CHANGED_FIELD_LENGTH
      ),
      changeType: entry.changeType,
      ...(entry.before === undefined
        ? {}
        : { before: canonicalJson(entry.before) }),
      ...(entry.after === undefined
        ? {}
        : { after: canonicalJson(entry.after) }),
    })),
  };
  const changedFields = normalizedDiff.entries.map((entry) => entry.path);
  return {
    comparisonVersion: version,
    result,
    reasonCode,
    changedFields,
    normalizedDiff,
    comparisonHash: comparisonHash({
      comparisonVersion: version,
      previousSnapshotId: previous?.id ?? null,
      currentSnapshotId: current.id,
      result,
      reasonCode,
      changedFields,
      normalizedDiff,
    }),
  };
}

function compareScalar(
  entries: ComparisonDiffEntry[],
  path: string,
  before: string | undefined,
  after: string | undefined
): void {
  if (before !== after) {
    entries.push({
      path,
      changeType: 'field_updated',
      ...(before === undefined ? {} : { before }),
      ...(after === undefined ? {} : { after }),
    });
  }
}

function compareKeyedCollection<T extends object>(
  entries: ComparisonDiffEntry[],
  previous: readonly T[],
  current: readonly T[],
  identity: keyof T,
  path: string,
  addedType: ComparisonChangeType,
  removedType: ComparisonChangeType,
  updatedType: ComparisonChangeType,
  fields: readonly (keyof T)[]
): void {
  const group = (items: readonly T[]) => {
    const groups = new Map<string, T[]>();
    for (const item of items) {
      const key = String((item as Record<string, unknown>)[String(identity)]);
      const values = groups.get(key) ?? [];
      values.push(item);
      groups.set(key, values);
    }
    return groups;
  };
  const beforeGroups = group(previous);
  const afterGroups = group(current);
  const keys = [
    ...new Set([...beforeGroups.keys(), ...afterGroups.keys()]),
  ].sort();
  for (const key of keys) {
    const beforeItems = beforeGroups.get(key) ?? [];
    const afterItems = afterGroups.get(key) ?? [];
    const count = Math.max(beforeItems.length, afterItems.length);
    for (let index = 0; index < count; index += 1) {
      const before = beforeItems[index];
      const after = afterItems[index];
      const itemPath =
        `${path}/by-ref/${pointerPart(key)}` +
        (count > 1 ? `/occurrence/${index}` : '');
      if (before === undefined && after !== undefined) {
        entries.push({
          path: itemPath,
          changeType: addedType,
          after: canonicalJson(after),
        });
        continue;
      }
      if (before !== undefined && after === undefined) {
        entries.push({
          path: itemPath,
          changeType: removedType,
          before: canonicalJson(before),
        });
        continue;
      }
      if (!before || !after) continue;
      for (const field of fields) {
        const beforeValue = (before as Record<string, unknown>)[String(field)];
        const afterValue = (after as Record<string, unknown>)[String(field)];
        if (
          canonicalizeComparison(beforeValue) !==
          canonicalizeComparison(afterValue)
        ) {
          entries.push({
            path: `${itemPath}/${String(field)}`,
            changeType: updatedType,
            ...(beforeValue === undefined
              ? {}
              : { before: canonicalJson(beforeValue) }),
            ...(afterValue === undefined
              ? {}
              : { after: canonicalJson(afterValue) }),
          });
        }
      }
    }
  }
}

export function compareSnapshots(
  previous: ComparisonSnapshot | null,
  current: ComparisonSnapshot,
  requestedVersion: unknown = COMPARISON_VERSION_V1
): ComparisonOutput {
  assertComparisonVersion(requestedVersion);
  const version = requestedVersion;
  validateSnapshotShape(current);
  if (previous) validateSnapshotShape(previous);
  if (!previous) {
    return outputFor(
      version,
      null,
      current,
      'not_comparable',
      'first_snapshot',
      []
    );
  }
  if (previous.id === current.id) {
    throw new ComparisonInputError(
      'Snapshot anterior e corrente não podem ser o mesmo registro.'
    );
  }
  if (
    previous.officeId !== current.officeId ||
    previous.processId !== current.processId
  ) {
    throw new ComparisonInputError(
      'Snapshots não pertencem ao mesmo office/processo.'
    );
  }
  if (Date.parse(previous.createdAt) >= Date.parse(current.createdAt)) {
    throw new ComparisonInputError(
      'Snapshot anterior não é historicamente anterior ao corrente.'
    );
  }
  if (previous.normalizerVersion !== current.normalizerVersion) {
    return outputFor(
      version,
      previous,
      current,
      'not_comparable',
      'normalizer_incompatible',
      []
    );
  }
  if (
    previous.providerId !== current.providerId ||
    previous.source !== current.source
  ) {
    return outputFor(
      version,
      previous,
      current,
      'not_comparable',
      'source_incompatible',
      []
    );
  }
  if (
    snapshotHasIncompleteFields(previous) ||
    snapshotHasIncompleteFields(current)
  ) {
    return outputFor(
      version,
      previous,
      current,
      'not_comparable',
      'required_field_missing',
      []
    );
  }

  const before = normalizeData(previous.normalizedData);
  const after = normalizeData(current.normalizedData);
  if (before.processRef !== after.processRef) {
    throw new ComparisonInputError('Snapshots possuem processRef divergente.');
  }
  const entries: ComparisonDiffEntry[] = [];
  compareScalar(entries, '/tribunal', before.tribunal, after.tribunal);
  compareScalar(entries, '/system', before.system, after.system);
  compareKeyedCollection(
    entries,
    before.movements ?? [],
    after.movements ?? [],
    'movementRef',
    '/movements',
    'movement_added',
    'movement_removed',
    'movement_updated',
    ['date', 'description']
  );
  compareKeyedCollection(
    entries,
    before.parties ?? [],
    after.parties ?? [],
    'partyRef',
    '/parties',
    'party_added',
    'party_removed',
    'party_updated',
    ['role']
  );
  entries.sort((left, right) => left.path.localeCompare(right.path));
  return outputFor(
    version,
    previous,
    current,
    entries.length > 0 ? 'changed' : 'unchanged',
    null,
    entries
  );
}
