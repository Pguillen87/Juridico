import { execFileSync } from 'node:child_process';

const OFFICE_ID = '00000000-0000-4000-8000-000000000401';
const CLIENT_IDS = {
  list: 'd1200000-0000-4000-b000-000000000001',
  review: 'd1200000-0000-4000-b000-000000000002',
  approve: 'd1200000-0000-4000-b000-000000000003',
  cancel: 'd1200000-0000-4000-b000-000000000004',
};
const PARTY_IDS = {
  list: 'd1200000-0000-4000-a000-000000000001',
  review: 'd1200000-0000-4000-a000-000000000002',
  approve: 'd1200000-0000-4000-a000-000000000003',
  cancel: 'd1200000-0000-4000-a000-000000000004',
};
const PERIOD_START = '2026-08-21 20:00:00+00';
const PERIOD_END = '2026-08-28 20:00:00+00';
const AS_OF = '2026-08-28 21:00:00+00';

function shellOutput(command, args, options = {}) {
  return execFileSync(command, args, {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'inherit'],
    ...options,
  }).trim();
}

const dbContainer =
  process.env.SUPABASE_DB_CONTAINER ??
  shellOutput('docker', ['ps', '--format', '{{.Names}}'])
    .split('\n')
    .find((name) => name.startsWith('supabase_db_'));

if (!dbContainer)
  throw new Error('Container PostgreSQL do Supabase não encontrado.');

function psql(sql) {
  return shellOutput(
    'docker',
    [
      'exec',
      '-i',
      dbContainer,
      'psql',
      '-X',
      '-qAt',
      '-v',
      'ON_ERROR_STOP=1',
      '-U',
      'postgres',
      '-d',
      'postgres',
    ],
    { input: `${sql}\n` }
  );
}

const actors = psql(
  "SELECT up.id::text FROM public.user_profile up JOIN auth.users au ON au.id = up.id WHERE up.office_id = '" +
    OFFICE_ID +
    "' AND au.email IN ('lawyer@example.test', 'reviewer@example.test') ORDER BY au.email"
).split('\n');
const lawyerId = actors[0]?.split('|')[0];
const reviewerId = actors[1]?.split('|')[0];
if (!lawyerId || !reviewerId) {
  throw new Error('Usuários E2E lawyer/reviewer não foram preparados.');
}

const clientIdList = Object.values(CLIENT_IDS)
  .map((clientId) => `'${clientId}'`)
  .join(', ');

const cleanup = `
SET juridico.phase12_internal = '1';
ALTER TABLE public.report_version DISABLE TRIGGER tr_report_version_append_only;
ALTER TABLE public.report_process DISABLE TRIGGER tr_report_process_append_only;
ALTER TABLE public.report_party DISABLE TRIGGER tr_report_party_append_only;
ALTER TABLE public.weekly_report DISABLE TRIGGER tr_weekly_report_domain_guard;
ALTER TABLE public.report_command_idempotency DISABLE TRIGGER tr_report_idempotency_guard;
UPDATE public.weekly_report
   SET current_version_id = NULL,
       approved_version_id = NULL,
       approved_hash = NULL,
       approved_by = NULL,
       approved_at = NULL,
       cancelled_by = NULL,
       cancelled_at = NULL,
       cancel_reason_code = NULL
 WHERE office_id = '${OFFICE_ID}'
   AND client_id IN (${clientIdList});
DELETE FROM public.report_command_idempotency WHERE office_id = '${OFFICE_ID}';
DELETE FROM public.report_process
 WHERE office_id = '${OFFICE_ID}'
   AND report_id IN (SELECT id FROM public.weekly_report WHERE office_id = '${OFFICE_ID}' AND client_id IN (${clientIdList}));
DELETE FROM public.report_party
 WHERE office_id = '${OFFICE_ID}'
   AND report_id IN (SELECT id FROM public.weekly_report WHERE office_id = '${OFFICE_ID}' AND client_id IN (${clientIdList}));
DO $$
DECLARE
  deleted_count INTEGER;
BEGIN
  LOOP
    DELETE FROM public.report_version rv
     WHERE rv.office_id = '${OFFICE_ID}'
       AND rv.report_id IN (SELECT id FROM public.weekly_report WHERE office_id = '${OFFICE_ID}' AND client_id IN (${clientIdList}))
       AND NOT EXISTS (
         SELECT 1
           FROM public.report_version child
          WHERE child.office_id = rv.office_id
            AND (
              child.previous_version_id = rv.id
              OR child.base_version_id = rv.id
              OR child.source_version_id = rv.id
            )
       );
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    EXIT WHEN deleted_count = 0;
  END LOOP;
END $$;
DELETE FROM public.weekly_report
 WHERE office_id = '${OFFICE_ID}'
   AND client_id IN (${clientIdList});
ALTER TABLE public.report_command_idempotency ENABLE TRIGGER tr_report_idempotency_guard;
ALTER TABLE public.weekly_report ENABLE TRIGGER tr_weekly_report_domain_guard;
ALTER TABLE public.report_party ENABLE TRIGGER tr_report_party_append_only;
ALTER TABLE public.report_process ENABLE TRIGGER tr_report_process_append_only;
ALTER TABLE public.report_version ENABLE TRIGGER tr_report_version_append_only;
RESET juridico.phase12_internal;
`;

const values = Object.entries(CLIENT_IDS)
  .map(([kind, clientId]) => {
    const partyId = PARTY_IDS[kind];
    const name = `Relatório E2E ${kind}`;
    return `
INSERT INTO public.party (id, office_id, party_type, display_name, normalized_name, created_by)
VALUES ('${partyId}', '${OFFICE_ID}', 'person', '${name}', '${name.toLowerCase()}', '${lawyerId}')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.client (id, office_id, party_id, status, created_by)
VALUES ('${clientId}', '${OFFICE_ID}', '${partyId}', 'active', '${lawyerId}')
ON CONFLICT (id) DO NOTHING;
`;
  })
  .join('\n');

psql(`${cleanup}
${values}
SET ROLE service_role;
SELECT public.phase12_generate_weekly_report('${OFFICE_ID}', '${CLIENT_IDS.list}', '${PERIOD_START}', '${PERIOD_END}', '${AS_OF}');
SELECT public.phase12_generate_weekly_report('${OFFICE_ID}', '${CLIENT_IDS.review}', '${PERIOD_START}', '${PERIOD_END}', '${AS_OF}');
SELECT public.phase12_generate_weekly_report('${OFFICE_ID}', '${CLIENT_IDS.approve}', '${PERIOD_START}', '${PERIOD_END}', '${AS_OF}');
SELECT public.phase12_generate_weekly_report('${OFFICE_ID}', '${CLIENT_IDS.cancel}', '${PERIOD_START}', '${PERIOD_END}', '${AS_OF}');
`);

process.stdout.write(
  'Fixture E2E de relatórios semanais preparada com dados sintéticos.\n'
);
