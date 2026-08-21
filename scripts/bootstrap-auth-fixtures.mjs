import { createClient } from '@supabase/supabase-js';
import { readLocalSupabaseEnv } from './local-supabase-env.mjs';

const OFFICE_ID = '00000000-0000-4000-8000-000000000401';
const INACTIVE_OFFICE_ID = '00000000-0000-4000-8000-000000000402';
const DEFAULT_PASSWORD = 'TestOnly-Local-123!';

async function findOrCreateUser(admin, email, password) {
  const { data: listed, error: listError } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (listError) throw listError;

  const existing = listed.users.find((user) => user.email === email);
  if (existing) {
    const { data, error } = await admin.auth.admin.updateUserById(existing.id, {
      password,
      email_confirm: true,
    });
    if (error) throw error;
    return data.user;
  }

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error || !data.user)
    throw error ?? new Error('Usuário fixture não foi criado.');
  return data.user;
}

async function upsertProfile(admin, profile) {
  const { error } = await admin
    .from('user_profile')
    .upsert(profile, { onConflict: 'id' });
  if (error) throw error;
}

async function removeUserIfPresent(admin, email) {
  const { data, error } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (error) throw error;
  const existing = data.users.find((user) => user.email === email);
  if (!existing) return;
  const { error: deleteError } = await admin.auth.admin.deleteUser(existing.id);
  if (deleteError) throw deleteError;
}

async function main() {
  const values = readLocalSupabaseEnv();
  const url = values.API_URL;
  const serviceRoleKey = values.SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) {
    throw new Error('O status local não forneceu URL e chave administrativa.');
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const password = process.env.JURIDICO_E2E_PASSWORD ?? DEFAULT_PASSWORD;
  await removeUserIfPresent(admin, 'invited-operator@example.test');

  const { error: officeError } = await admin.from('office').upsert(
    [
      { id: OFFICE_ID, name: 'Escritório E2E Teste', is_active: true },
      {
        id: INACTIVE_OFFICE_ID,
        name: 'Escritório E2E Inativo',
        is_active: false,
      },
    ],
    { onConflict: 'id' }
  );
  if (officeError) throw officeError;

  const owner = await findOrCreateUser(admin, 'owner@example.test', password);
  const operator = await findOrCreateUser(
    admin,
    'operator@example.test',
    password
  );
  const inactive = await findOrCreateUser(
    admin,
    'inactive@example.test',
    password
  );
  const inactiveOffice = await findOrCreateUser(
    admin,
    'office-inactive@example.test',
    password
  );
  const recovery = await findOrCreateUser(
    admin,
    'recovery@example.test',
    password
  );

  await upsertProfile(admin, {
    id: owner.id,
    office_id: OFFICE_ID,
    name: 'Owner E2E',
    role: 'lawyer',
    is_owner: true,
    is_active: true,
  });
  await upsertProfile(admin, {
    id: operator.id,
    office_id: OFFICE_ID,
    name: 'Operator E2E',
    role: 'operator',
    is_owner: false,
    is_active: true,
  });
  await upsertProfile(admin, {
    id: inactive.id,
    office_id: OFFICE_ID,
    name: 'Inactive E2E',
    role: 'operator',
    is_owner: false,
    is_active: false,
  });
  await upsertProfile(admin, {
    id: inactiveOffice.id,
    office_id: INACTIVE_OFFICE_ID,
    name: 'Office Inactive E2E',
    role: 'operator',
    is_owner: false,
    is_active: true,
  });
  await upsertProfile(admin, {
    id: recovery.id,
    office_id: OFFICE_ID,
    name: 'Recovery E2E',
    role: 'operator',
    is_owner: false,
    is_active: true,
  });

  process.stdout.write(
    'Auth fixtures locais preparados: owner, operator, recovery, inactive e office-inactive.\n'
  );
}

main().catch((error) => {
  process.stderr.write(`Falha ao preparar fixtures Auth: ${error.message}\n`);
  process.exitCode = 1;
});
