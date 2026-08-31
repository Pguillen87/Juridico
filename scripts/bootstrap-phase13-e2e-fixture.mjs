import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { readLocalSupabaseEnv } from './local-supabase-env.mjs';

const ids = {
  office: 'f1300000-0000-4000-9000-000000000101',
  party: 'f1300000-0000-4000-a000-000000000101',
  client: 'f1300000-0000-4000-b000-000000000101',
  report: 'f1300000-0000-4000-c000-000000000101',
  version: 'f1300000-0000-4000-d000-000000000101',
  artifact: 'f1300000-0000-4000-e000-000000000101',
  contact: 'f1300000-0000-4000-f000-000000000101',
  delivery: 'f1300000-0000-4000-0000-000000000101',
};
const hash = (value) => createHash('sha256').update(value).digest('hex');
const pdf = Buffer.from('%PDF-1.4\n% F13 synthetic local fixture\n%%EOF\n');
const fileHash = hash(pdf);
const approvedHash = hash('f13-approved-content');
const storageKey = `${ids.report}/${ids.version}/${ids.artifact}.pdf`;

const sqlStatements = [
  "SELECT set_config('juridico.phase12_internal','1',false);",
  "SELECT set_config('juridico.phase13_internal','1',false);",
];
const sqlLiteral = (value) =>
  value === null || value === undefined
    ? 'NULL'
    : typeof value === 'boolean' || typeof value === 'number'
      ? String(value)
      : `'${(typeof value === 'object' ? JSON.stringify(value) : String(value)).replaceAll("'", "''")}'`;
async function upsert(_admin, table, rows) {
  for (const row of rows) {
    const columns = Object.keys(row);
    const values = columns.map((column) => sqlLiteral(row[column]));
    const updates = columns
      .filter((column) => column !== 'id')
      .map((column) => `"${column}"=EXCLUDED."${column}"`)
      .join(',');
    const immutable = new Set([
      'report_version',
      'report_artifact',
      'client_contact',
      'email_delivery',
    ]);
    const conflict = immutable.has(table)
      ? 'ON CONFLICT ("id") DO NOTHING'
      : `ON CONFLICT ("id") DO UPDATE SET ${updates}`;
    sqlStatements.push(
      `INSERT INTO public."${table}" ("${columns.join('","')}") VALUES (${values.join(',')}) ${conflict};`
    );
  }
}
function flushSql() {
  execFileSync(
    'docker',
    [
      'exec',
      '-i',
      dbContainer,
      'psql',
      '-X',
      '-q',
      '-v',
      'ON_ERROR_STOP=1',
      '-U',
      'postgres',
      '-d',
      'postgres',
    ],
    { input: `${sqlStatements.join('\n')}\n` }
  );
  sqlStatements.length = 2;
}

execFileSync(process.execPath, ['./scripts/bootstrap-auth-fixtures.mjs'], {
  stdio: 'inherit',
  env: process.env,
});
const values = readLocalSupabaseEnv();
if (!values.API_URL || !values.SERVICE_ROLE_KEY)
  throw new Error('Supabase local não forneceu API_URL/SERVICE_ROLE_KEY.');
const admin = createClient(values.API_URL, values.SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});
// Local migrations intentionally revoke browser table access; grant the fixture
// role only in the disposable local database so setup remains service_role-only.
const dbContainer =
  process.env.SUPABASE_DB_CONTAINER ??
  execFileSync('docker', ['ps', '--format', '{{.Names}}'])
    .toString()
    .split(/\r?\n/)
    .find((name) => name.startsWith('supabase_db_'));
if (!dbContainer)
  throw new Error('Container PostgreSQL local do Supabase não encontrado.');
execFileSync(
  'docker',
  [
    'exec',
    '-i',
    dbContainer,
    'psql',
    '-X',
    '-q',
    '-v',
    'ON_ERROR_STOP=1',
    '-U',
    'postgres',
    '-d',
    'postgres',
  ],
  {
    input:
      "GRANT USAGE ON SCHEMA public TO service_role; GRANT ALL ON TABLE public.office, public.user_profile, public.party, public.client, public.weekly_report, public.report_version, public.report_artifact, public.client_contact, public.email_delivery TO service_role; SELECT set_config('juridico.phase12_internal','1',false); SELECT set_config('juridico.phase13_internal','1',false);\n",
  }
);
const users = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
if (users.error) throw users.error;
const lawyer = users.data.users.find(
  (user) => user.email === 'lawyer@example.test'
);
if (!lawyer)
  throw new Error('Execute bootstrap-auth-fixtures.mjs antes deste fixture.');

await upsert(admin, 'office', [
  { id: ids.office, name: 'F13 E2E Synthetic Office', is_active: true },
]);
await upsert(admin, 'user_profile', [
  {
    id: lawyer.id,
    office_id: ids.office,
    name: 'F13 E2E Lawyer',
    role: 'lawyer',
    is_owner: false,
    is_active: true,
  },
]);
await upsert(admin, 'party', [
  {
    id: ids.party,
    office_id: ids.office,
    party_type: 'person',
    display_name: 'F13 E2E Client',
    normalized_name: 'f13 e2e client',
    created_by: lawyer.id,
  },
]);
await upsert(admin, 'client', [
  {
    id: ids.client,
    office_id: ids.office,
    party_id: ids.party,
    status: 'active',
    created_by: lawyer.id,
  },
]);
await upsert(admin, 'weekly_report', [
  {
    id: ids.report,
    office_id: ids.office,
    client_id: ids.client,
    report_type: 'weekly',
    period_start_utc: '2026-08-21T00:00:00Z',
    period_end_utc: '2026-08-28T00:00:00Z',
    timezone: 'America/Sao_Paulo',
    status: 'draft',
    generation_key: 'f13-e2e-synthetic',
  },
]);
await upsert(admin, 'report_version', [
  {
    id: ids.version,
    office_id: ids.office,
    report_id: ids.report,
    version_number: 1,
    created_by: lawyer.id,
    creation_kind: 'generated',
    schema_version: 'report-v1',
    structured_content: { title: 'F13 E2E synthetic report', sections: [] },
    source_manifest: {},
    content_hash: approvedHash,
  },
]);
await upsert(admin, 'weekly_report', [
  {
    id: ids.report,
    office_id: ids.office,
    client_id: ids.client,
    report_type: 'weekly',
    period_start_utc: '2026-08-21T00:00:00Z',
    period_end_utc: '2026-08-28T00:00:00Z',
    timezone: 'America/Sao_Paulo',
    status: 'approved',
    current_version_id: ids.version,
    approved_version_id: ids.version,
    approved_hash: approvedHash,
    approved_by: lawyer.id,
    approved_at: new Date().toISOString(),
    generation_key: 'f13-e2e-synthetic',
  },
]);
flushSql();
const { error: uploadError } = await admin.storage
  .from('private-reports')
  .upload(storageKey, pdf, { contentType: 'application/pdf', upsert: true });
if (uploadError) throw new Error(`private-reports: ${uploadError.message}`);
await upsert(admin, 'report_artifact', [
  {
    id: ids.artifact,
    office_id: ids.office,
    report_id: ids.report,
    report_version_id: ids.version,
    storage_bucket: 'private-reports',
    private_storage_uri: `private://private-reports/${storageKey}`,
    approved_hash: approvedHash,
    file_hash: fileHash,
    generation_fingerprint: hash(`f13-e2e:${ids.report}:${ids.version}`),
    byte_size: pdf.byteLength,
    created_by: lawyer.id,
  },
]);
await upsert(admin, 'client_contact', [
  {
    id: ids.contact,
    office_id: ids.office,
    client_id: ids.client,
    display_name: 'F13 E2E Recipient',
    email: 'f13-e2e-recipient@synthetic.test',
    is_confirmed: true,
    confirmed_by: lawyer.id,
    confirmed_at: new Date().toISOString(),
  },
]);
await upsert(admin, 'email_delivery', [
  {
    id: ids.delivery,
    office_id: ids.office,
    report_id: ids.report,
    report_version_id: ids.version,
    artifact_id: ids.artifact,
    client_contact_id: ids.contact,
    recipient: 'f13-e2e-recipient@synthetic.test',
    subject: 'F13 synthetic delivery',
    approved_hash: approvedHash,
    artifact_hash: fileHash,
    private_pdf_uri: `private://private-reports/${storageKey}`,
    status: 'pending',
    idempotency_key: 'f13-e2e-initial',
    created_by: lawyer.id,
  },
]);
flushSql();
process.stdout.write(
  `F13 local fixture ready: report=${ids.report} artifact=${ids.artifact}\n`
);
