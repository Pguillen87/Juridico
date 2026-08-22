'use server';

import { revalidatePath } from 'next/cache';
import { PermissionDeniedError, requirePermission } from '@/lib/auth/guards';
import {
  appendInviteAuditInternal,
  appendRejectionAuditInternal,
} from '@/lib/audit';
import {
  consumeAdminRateLimit,
  isRateLimitAllowed,
  type AdminRateLimitOperation,
} from '@/lib/rate-limit';
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';
import {
  changeRoleSchema,
  inviteSchema,
  setActiveSchema,
  setOwnerSchema,
} from '@/lib/auth/validation';

export type AdminActionResult = {
  success?: boolean;
  error?: string;
  retryAfterSeconds?: number;
};

function mapAdminError(error: { code?: string; message?: string }): string {
  if (error.code === 'P0001') {
    return 'Operação bloqueada: o escritório precisa manter um administrador ativo.';
  }
  if (error.code === 'P0002') {
    return 'Usuário não encontrado neste escritório.';
  }
  if (error.code === '42501') {
    return 'Você não tem autorização para esta operação.';
  }
  if (error.code === '22023') {
    return 'Dados inválidos para esta operação.';
  }
  return 'Não foi possível concluir a operação. Tente novamente.';
}

function directPermissionError(error: unknown): AdminActionResult | null {
  if (error instanceof PermissionDeniedError) {
    return { error: 'Você não tem autorização para esta operação.' };
  }
  return null;
}

async function rpcErrorMessage(error: { code?: string; message?: string }) {
  return { error: mapAdminError(error) };
}

async function rateLimitResult(
  operation: AdminRateLimitOperation
): Promise<AdminActionResult | null> {
  const result = await consumeAdminRateLimit(operation);
  if (isRateLimitAllowed(result)) return null;
  return {
    error: 'Operação temporariamente limitada. Tente novamente mais tarde.',
    retryAfterSeconds: result.retryAfterSeconds,
  };
}

export async function inviteUserAction(
  formData: FormData
): Promise<AdminActionResult> {
  try {
    const { profile } = await requirePermission('invite_user');

    const parsed = inviteSchema.safeParse({
      name: formData.get('name'),
      email: formData.get('email'),
      role: formData.get('role'),
    });

    if (!parsed.success) {
      return { error: parsed.error.issues[0]?.message ?? 'Dados inválidos.' };
    }

    const { name, email, role } = parsed.data;
    const limited = await rateLimitResult('admin.invite');
    if (limited) return limited;

    const admin = createAdminClient();
    const redirectTo = `${process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000'}/auth/callback?next=/redefinir-senha`;
    const { data: authData, error: authError } =
      await admin.auth.admin.inviteUserByEmail(email, { redirectTo });

    if (authError || !authData.user) {
      if (profile && profile.id) {
        await appendInviteAuditInternal(
          profile.id,
          null,
          'rejected',
          'auth_error'
        );
      }
      return {
        error:
          'Não foi possível convidar este usuário. Verifique se o e-mail já está em uso.',
      };
    }

    const { error: profileError } = await admin.from('user_profile').insert({
      id: authData.user.id,
      office_id: profile.office_id,
      name,
      role,
      is_active: true,
      is_owner: false,
    });

    if (profileError) {
      await admin.auth.admin.deleteUser(authData.user.id);
      if (profile && profile.id) {
        await appendInviteAuditInternal(
          profile.id,
          null,
          'rejected',
          'profile_error'
        );
      }
      return {
        error:
          'Erro ao registrar o perfil do usuário. O convite foi cancelado.',
      };
    }

    if (profile && profile.id) {
      await appendInviteAuditInternal(profile.id, authData.user.id, 'accepted');
    }
    revalidatePath('/app/usuarios');
    return { success: true };
  } catch {
    return { error: 'Ocorreu um erro inesperado ao processar o convite.' };
  }
}

export async function changeRoleAction(
  formData: FormData
): Promise<AdminActionResult> {
  try {
    await requirePermission('change_role', { redirectOnDenied: false });
    const parsed = changeRoleSchema.safeParse({
      userId: formData.get('userId'),
      role: formData.get('role'),
    });
    if (!parsed.success) {
      return { error: parsed.error.issues[0]?.message ?? 'Dados inválidos.' };
    }

    const limited = await rateLimitResult('admin.change_role');
    if (limited) return limited;

    const supabase = await createClient();
    const { error } = await supabase.rpc('change_user_role', {
      p_target_user_id: parsed.data.userId,
      p_new_role: parsed.data.role,
    });
    if (error) return rpcErrorMessage(error);

    revalidatePath('/app/usuarios');
    return { success: true };
  } catch (error) {
    return (
      directPermissionError(error) ?? {
        error: 'Não foi possível alterar o papel deste usuário.',
      }
    );
  }
}

export async function setActiveAction(
  formData: FormData
): Promise<AdminActionResult> {
  try {
    const { profile } = await requirePermission('set_active', {
      redirectOnDenied: false,
    });
    const rawValue = formData.get('isActive');
    const isActive =
      rawValue === 'true' ? true : rawValue === 'false' ? false : rawValue;
    const parsed = setActiveSchema.safeParse({
      userId: formData.get('userId'),
      isActive,
    });
    if (!parsed.success) {
      return { error: parsed.error.issues[0]?.message ?? 'Dados inválidos.' };
    }

    const limited = await rateLimitResult('admin.set_active');
    if (limited) return limited;

    const supabase = await createClient();
    const { error } = await supabase.rpc('set_user_active', {
      p_target_user_id: parsed.data.userId,
      p_is_active: parsed.data.isActive,
    });
    if (error) {
      if (error.code === '42501' && error.message.includes('last owner')) {
        await appendRejectionAuditInternal(
          profile.id,
          'last_owner_blocked',
          'user_profile',
          parsed.data.userId,
          'Cannot deactivate last active owner'
        );
        return {
          error:
            'Não é possível inativar o último administrador ativo do escritório.',
        };
      }
      return rpcErrorMessage(error);
    }

    revalidatePath('/app/usuarios');
    revalidatePath('/app');
    return { success: true };
  } catch (error) {
    return (
      directPermissionError(error) ?? {
        error: 'Não foi possível alterar o status deste usuário.',
      }
    );
  }
}

export async function setOwnerAction(
  formData: FormData
): Promise<AdminActionResult> {
  try {
    const { profile } = await requirePermission('set_owner', {
      redirectOnDenied: false,
    });
    const rawValue = formData.get('isOwner');
    const isOwner =
      rawValue === 'true' ? true : rawValue === 'false' ? false : rawValue;
    const parsed = setOwnerSchema.safeParse({
      userId: formData.get('userId'),
      isOwner,
    });
    if (!parsed.success) {
      return { error: parsed.error.issues[0]?.message ?? 'Dados inválidos.' };
    }

    const limited = await rateLimitResult('admin.set_owner');
    if (limited) return limited;

    const supabase = await createClient();
    const { error } = await supabase.rpc('set_user_owner', {
      p_target_user_id: parsed.data.userId,
      p_is_owner: parsed.data.isOwner,
    });
    if (error) {
      if (error.code === '42501' && error.message.includes('last owner')) {
        await appendRejectionAuditInternal(
          profile.id,
          'last_owner_blocked',
          'user_profile',
          parsed.data.userId,
          'Cannot revoke last active owner'
        );
        return {
          error:
            'Não é possível revogar o último administrador ativo do escritório.',
        };
      }
      return rpcErrorMessage(error);
    }

    revalidatePath('/app/usuarios');
    return { success: true };
  } catch (error) {
    return (
      directPermissionError(error) ?? {
        error: 'Não foi possível alterar a capacidade administrativa.',
      }
    );
  }
}
