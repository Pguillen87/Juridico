'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';

const partySchema = z.object({
  partyType: z.enum(['person', 'company', 'other']),
  displayName: z.string().trim().min(2).max(200),
});

function safeError(message?: string) {
  if (message?.includes('permission denied'))
    return 'Você não tem autorização para esta operação.';
  if (message?.includes('duplicate'))
    return 'Já existe um registro ativo equivalente.';
  if (message?.includes('invalid')) return 'Os dados informados são inválidos.';
  return 'Não foi possível concluir a operação.';
}

export async function createClientAction(formData: FormData) {
  try {
    await requirePermission('manage_clients', { redirectOnDenied: false });
    const parsed = partySchema.safeParse({
      partyType: formData.get('partyType'),
      displayName: formData.get('displayName'),
    });
    if (!parsed.success) return { error: 'Informe tipo e nome válidos.' };
    const supabase = await createClient();
    const { error } = await supabase.rpc('create_client_with_party', {
      p_party_type: parsed.data.partyType,
      p_display_name: parsed.data.displayName,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Não foi possível concluir a operação.' };
  }
}

export async function createPartyAction(formData: FormData) {
  try {
    await requirePermission('manage_parties', { redirectOnDenied: false });
    const parsed = partySchema.safeParse({
      partyType: formData.get('partyType'),
      displayName: formData.get('displayName'),
    });
    if (!parsed.success) return { error: 'Informe tipo e nome válidos.' };
    const supabase = await createClient();
    const { error } = await supabase.rpc('create_party', {
      p_party_type: parsed.data.partyType,
      p_display_name: parsed.data.displayName,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Não foi possível concluir a operação.' };
  }
}

export async function createRelatedPartyAction(formData: FormData) {
  try {
    await requirePermission('manage_parties', { redirectOnDenied: false });
    const clientId = z.string().uuid().parse(formData.get('clientId'));
    const partyId = z.string().uuid().parse(formData.get('partyId'));
    const relationType = z
      .string()
      .trim()
      .min(2)
      .max(80)
      .parse(formData.get('relationType'));
    const notes = z
      .string()
      .max(1000)
      .optional()
      .parse(formData.get('notes') || undefined);
    const supabase = await createClient();
    const { error } = await supabase.rpc('create_client_related_party', {
      p_client_id: clientId,
      p_party_id: partyId,
      p_relation_type: relationType,
      p_notes: notes ?? null,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Os dados da relação são inválidos.' };
  }
}

export async function confirmRelatedPartyAction(formData: FormData) {
  try {
    await requirePermission('confirm_party_links', { redirectOnDenied: false });
    const relationId = z.string().uuid().parse(formData.get('relationId'));
    const supabase = await createClient();
    const { error } = await supabase.rpc('confirm_client_related_party', {
      p_relation_id: relationId,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Não foi possível confirmar a relação.' };
  }
}

export async function rejectRelatedPartyAction(formData: FormData) {
  try {
    await requirePermission('confirm_party_links', { redirectOnDenied: false });
    const relationId = z.string().uuid().parse(formData.get('relationId'));
    const supabase = await createClient();
    const { error } = await supabase.rpc('reject_client_related_party', {
      p_relation_id: relationId,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Não foi possível rejeitar a relação.' };
  }
}

export async function deactivateClientAction(formData: FormData) {
  try {
    await requirePermission('manage_clients', { redirectOnDenied: false });
    const id = z.string().uuid().parse(formData.get('id'));
    const supabase = await createClient();
    const { error } = await supabase.rpc('deactivate_client', { p_id: id });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Não foi possível desativar o cliente.' };
  }
}

export async function deactivatePartyAction(formData: FormData) {
  try {
    await requirePermission('manage_parties', { redirectOnDenied: false });
    const id = z.string().uuid().parse(formData.get('id'));
    const supabase = await createClient();
    const { error } = await supabase.rpc('deactivate_party', { p_id: id });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Não foi possível desativar a parte.' };
  }
}

export async function deactivateRelatedPartyAction(formData: FormData) {
  try {
    await requirePermission('manage_parties', { redirectOnDenied: false });
    const id = z.string().uuid().parse(formData.get('id'));
    const supabase = await createClient();
    const { error } = await supabase.rpc('deactivate_client_related_party', {
      p_id: id,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Não foi possível desativar a relação.' };
  }
}

export async function updateClientAction(formData: FormData) {
  try {
    await requirePermission('manage_clients', { redirectOnDenied: false });
    const id = z.string().uuid().parse(formData.get('id'));
    const status = z.enum(['active', 'inactive']).parse(formData.get('status'));
    const supabase = await createClient();
    const { error } = await supabase.rpc('update_client', {
      p_id: id,
      p_status: status,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Não foi possível atualizar o cliente.' };
  }
}

export async function updatePartyAction(formData: FormData) {
  try {
    await requirePermission('manage_parties', { redirectOnDenied: false });
    const id = z.string().uuid().parse(formData.get('id'));
    const parsed = partySchema.parse({
      partyType: formData.get('partyType'),
      displayName: formData.get('displayName'),
    });
    const supabase = await createClient();
    const { error } = await supabase.rpc('update_party', {
      p_id: id,
      p_display_name: parsed.displayName,
      p_party_type: parsed.partyType,
    });
    if (error) return { error: safeError(error.message) };
    revalidatePath('/app/clientes');
    return { success: true };
  } catch {
    return { error: 'Não foi possível atualizar a parte.' };
  }
}
