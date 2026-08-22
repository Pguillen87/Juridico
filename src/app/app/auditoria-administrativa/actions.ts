'use server';

import { requirePermission } from '@/lib/auth/guards';
import type { Tables } from '@/types/database.types';
import { createClient } from '@/lib/supabase/server';
import { consumeAdminRateLimit, isRateLimitAllowed } from '@/lib/rate-limit';

export type AuditExportResult = {
  success?: boolean;
  error?: string;
  csv?: string;
  retryAfterSeconds?: number;
};

function escapeCsv(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

export async function exportAdministrativeAuditAction(): Promise<AuditExportResult> {
  try {
    await requirePermission('export_administrative_audit', {
      redirectOnDenied: false,
    });

    const rateLimit = await consumeAdminRateLimit('admin.audit_export');
    if (!isRateLimitAllowed(rateLimit)) {
      return {
        error: 'Operação temporariamente limitada. Tente novamente mais tarde.',
        retryAfterSeconds: rateLimit.retryAfterSeconds,
      };
    }

    const supabase = await createClient();
    const { error: auditError } = await supabase.rpc('record_audit_export');
    if (auditError) {
      return { error: 'Não foi possível registrar a exportação.' };
    }

    const { data, error } = await supabase.rpc('get_administrative_audit', {
      p_limit: 100,
      p_action: null,
      p_entity_type: null,
    });
    if (error) {
      return { error: 'Não foi possível gerar a exportação.' };
    }

    const rows = (data ?? []).map(
      (
        entry: Pick<
          Tables<'audit_log'>,
          'created_at' | 'action' | 'entity_type' | 'metadata'
        >
      ) =>
        [
          entry.created_at,
          entry.action,
          entry.entity_type,
          JSON.stringify(entry.metadata),
        ]
          .map(escapeCsv)
          .join(',')
    );
    return {
      success: true,
      csv: ['created_at,action,entity_type,metadata', ...rows].join('\n'),
    };
  } catch {
    return { error: 'Não foi possível gerar a exportação administrativa.' };
  }
}
