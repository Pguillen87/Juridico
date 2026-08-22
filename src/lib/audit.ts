import 'server-only';

import type { Tables } from '@/types/database.types';
import { createClient } from './supabase/server';

export type AdministrativeAuditEntry = Tables<'audit_log'>;

export async function appendInviteAudit(
  targetUserId: string | null,
  outcome: 'accepted' | 'rejected'
): Promise<number> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('record_invite_audit', {
    p_target_user_id: targetUserId,
    p_outcome: outcome,
  });

  if (error || data === null) {
    throw new Error('Não foi possível registrar a auditoria administrativa.');
  }

  return data;
}

export async function listAdministrativeAudit(filters?: {
  limit?: number;
  action?: string;
  entityType?: string;
}): Promise<AdministrativeAuditEntry[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('get_administrative_audit', {
    p_limit: filters?.limit ?? 50,
    p_action: filters?.action ?? null,
    p_entity_type: filters?.entityType ?? null,
  });

  if (error) {
    throw new Error('Não foi possível consultar a auditoria administrativa.');
  }

  return data ?? [];
}
