'use server';

import { revalidatePath } from 'next/cache';
import { requireOwnerProfile } from '@/lib/auth/guards';
import { createAdminClient } from '@/lib/supabase/admin';
import { inviteSchema } from '@/lib/auth/validation';

export async function inviteUserAction(formData: FormData) {
  try {
    // 1. Autorização: apenas owner autenticado pode convidar
    const { profile } = await requireOwnerProfile();

    // 2. Validação do payload
    const parsed = inviteSchema.safeParse({
      name: formData.get('name'),
      email: formData.get('email'),
      role: formData.get('role'),
    });

    if (!parsed.success) {
      return { error: parsed.error.issues[0]?.message ?? 'Dados inválidos.' };
    }

    const { name, email, role } = parsed.data;

    // 3. Cliente administrativo server-only
    const admin = createAdminClient();

    // 4. Convidar usuário via Auth
    // O redirectTo aponta para o callback que fará exchangeCodeForSession e mandará para redefinir a senha
    // Como invite gera um "recovery" disfarçado ou "invite" type no PKCE, o callback lida com isso.
    const redirectTo = `${process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000'}/auth/callback?next=/redefinir-senha`;

    const { data: authData, error: authError } =
      await admin.auth.admin.inviteUserByEmail(email, {
        redirectTo,
      });

    if (authError || !authData.user) {
      // Se o usuário já existir no auth, inviteUserByEmail pode falhar ou retornar erro.
      // O correto em produção seria conferir se ele já existe e associar, mas para MVP 4B mantemos simples:
      return {
        error:
          'Não foi possível convidar este usuário. Verifique se o e-mail já está em uso.',
      };
    }

    // 5. Criar perfil associado ao office do owner
    // O office_id vem da sessão do owner, nunca do client
    const { error: profileError } = await admin.from('user_profile').insert({
      id: authData.user.id,
      office_id: profile.office_id,
      name,
      role,
      is_active: true,
      is_owner: false,
    });

    if (profileError) {
      // Compensação: se falhar ao criar o perfil, apaga o auth user para não deixar lixo
      await admin.auth.admin.deleteUser(authData.user.id);
      return {
        error:
          'Erro ao registrar o perfil do usuário. O convite foi cancelado.',
      };
    }

    revalidatePath('/app/usuarios');
    return { success: true };
  } catch {
    return { error: 'Ocorreu um erro inesperado ao processar o convite.' };
  }
}
