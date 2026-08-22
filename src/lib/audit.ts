import 'server-only';

import type { Tables } from '@/types/database.types';
import { createClient } from './supabase/server';

export type AdministrativeAuditEntry = Tables<'audit_log'>;

import { createAdminClient } from './supabase/admin';

export async function appendInviteAuditInternal(
  actorUserId: string,
  targetUserId: string | null,
  outcome: 'accepted' | 'rejected',
  reason?: string
): Promise<number> {
  const adminSupabase = createAdminClient();
  const { data, error } = await adminSupabase.rpc(
    'record_invite_audit_internal',
    {
      p_actor_user_id: actorUserId,
      p_target_user_id: targetUserId!,
      p_outcome: outcome,
      p_reason: reason,
    }
  );

  if (error || data === null) {
    throw new Error('Não foi possível registrar a auditoria administrativa.');
  }

  return data;
}

export async function appendRejectionAuditInternal(
  actorUserId: string,
  action: string,
  entityType: string,
  entityId: string | null,
  reason: string
): Promise<number> {
  const adminSupabase = createAdminClient();
  const { data, error } = await adminSupabase.rpc(
    'record_rejection_audit_internal',
    {
      p_actor_user_id: actorUserId,
      p_action: action,
      p_entity_type: entityType,
      p_entity_id: entityId!,
      p_reason: reason,
    }
  );

  if (error || data === null) {
    throw new Error(
      'Não foi possível registrar a auditoria administrativa de rejeição.'
    );
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
