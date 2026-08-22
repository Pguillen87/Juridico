import type { User } from '@supabase/supabase-js';
import { redirect } from 'next/navigation';
import type { Tables } from '@/types/database.types';
import {
  canPerformAction,
  type PermissionAction,
  type PermissionContext,
} from './permissions';
import { createClient } from '../supabase/server';

export type AuthenticatedContext = {
  user: User;
  profile: Tables<'user_profile'>;
  office: Tables<'office'>;
};

export class PermissionDeniedError extends Error {
  readonly code = 'FORBIDDEN' as const;

  constructor(readonly action: PermissionAction) {
    super(`Permission denied for action: ${action}`);
    this.name = 'PermissionDeniedError';
  }
}

export async function requireAuthenticatedProfile(): Promise<AuthenticatedContext> {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) redirect('/login');

  const { data: profiles, error: profileError } = await supabase.rpc(
    'get_auth_user_profile'
  );
  const profile = profiles?.[0];
  if (profileError || !profile || !profile.is_active)
    redirect('/login?error=inactive');

  const { data: office, error: officeError } = await supabase
    .from('office')
    .select('*')
    .eq('id', profile.office_id)
    .maybeSingle();
  if (officeError || !office?.is_active) redirect('/login?error=inactive');

  return { user: data.user, profile, office };
}

export async function requirePermission(
  action: PermissionAction,
  options: { redirectOnDenied?: boolean } = {}
): Promise<AuthenticatedContext> {
  const context = await requireAuthenticatedProfile();
  const permissionContext: PermissionContext = {
    role: context.profile.role,
    isOwner: context.profile.is_owner,
    isActive: context.profile.is_active,
    officeIsActive: context.office.is_active,
  };

  if (!canPerformAction(permissionContext, action)) {
    if (options.redirectOnDenied !== false) redirect('/app?error=forbidden');
    throw new PermissionDeniedError(action);
  }

  return context;
}

export async function requireOwnerProfile(): Promise<AuthenticatedContext> {
  const context = await requireAuthenticatedProfile();
  if (!context.profile.is_owner) redirect('/app?error=forbidden');
  return context;
}

export function roleLabel(role: Tables<'user_profile'>['role']): string {
  return {
    lawyer: 'Advogado',
    operator: 'Operador',
    reviewer: 'Revisor',
    auditor: 'Auditor',
  }[role];
}

export function safeInternalRedirect(value: string | null | undefined): string {
  return value === '/app' ||
    value === '/app/usuarios' ||
    value === '/redefinir-senha'
    ? value
    : '/app';
}
