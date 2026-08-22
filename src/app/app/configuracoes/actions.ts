'use server';

import { revalidatePath } from 'next/cache';
import { requirePermission } from '@/lib/auth/guards';
import { consumeAdminRateLimit, isRateLimitAllowed } from '@/lib/rate-limit';
import { createClient } from '@/lib/supabase/server';
import { updateOfficeNameSchema } from '@/lib/auth/validation';

export async function updateOfficeNameAction(formData: FormData) {
  try {
    await requirePermission('update_office_settings', {
      redirectOnDenied: false,
    });
    const parsed = updateOfficeNameSchema.safeParse({
      name: formData.get('name'),
    });
    if (!parsed.success) {
      return { error: parsed.error.issues[0]?.message ?? 'Nome inválido.' };
    }

    const rateLimit = await consumeAdminRateLimit('admin.update_office_name');
    if (!isRateLimitAllowed(rateLimit)) {
      return {
        error: 'Operação temporariamente limitada. Tente novamente mais tarde.',
        retryAfterSeconds: rateLimit.retryAfterSeconds,
      };
    }

    const supabase = await createClient();
    const { error } = await supabase.rpc('update_office_name', {
      p_name: parsed.data.name,
    });
    if (error?.code === '42501') {
      return { error: 'Você não tem autorização para esta operação.' };
    }
    if (error?.code === '22023') {
      return { error: 'O nome informado não é válido.' };
    }
    if (error) {
      return { error: 'Não foi possível alterar o nome do escritório.' };
    }

    revalidatePath('/app');
    revalidatePath('/app/configuracoes');
    revalidatePath('/app/usuarios');
    return { success: true };
  } catch {
    return { error: 'Não foi possível alterar o nome do escritório.' };
  }
}
