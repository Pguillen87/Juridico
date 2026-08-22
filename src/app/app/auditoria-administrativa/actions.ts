'use server';

import { requirePermission } from '@/lib/auth/guards';
import type { Tables } from '@/types/database.types';
import { createClient } from '@/lib/supabase/server';

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

    const supabase = await createClient();
    const { data, error } = await supabase.rpc(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      'export_administrative_audit' as any,
      {
        p_limit: 100,
        p_action: null,
        p_entity_type: null,
      }
    );
    if (error) {
      if (error.code === '42900') {
        return {
          error: 'Limite de exportação atingido. Tente novamente mais tarde.',
        };
      }
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
