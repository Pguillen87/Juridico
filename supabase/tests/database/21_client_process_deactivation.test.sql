BEGIN;

SELECT plan(5);

CREATE OR REPLACE FUNCTION pg_temp.set_auth_user(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', p_user_id::TEXT, true);
  PERFORM set_config(
    'request.jwt.claims',
    format('{"sub":"%s","role":"authenticated"}', p_user_id),
    true
  );
END;
$$;

SET ROLE postgres;

INSERT INTO auth.users (id, email)
VALUES ('94000000-0000-4000-8000-000000000001', 'deactivate-lawyer@example.test')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active)
VALUES ('94000000-0000-4000-9000-000000000001', 'Deactivate Office', true)
ON CONFLICT (id) DO UPDATE SET is_active = EXCLUDED.is_active;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active)
VALUES (
  '94000000-0000-4000-8000-000000000001',
  '94000000-0000-4000-9000-000000000001',
  'Deactivate Lawyer',
  'lawyer',
  true,
  true
)
ON CONFLICT (id) DO UPDATE SET office_id = EXCLUDED.office_id, is_active = EXCLUDED.is_active;

INSERT INTO public.party (
  id, office_id, party_type, display_name, normalized_name, created_by
)
VALUES (
  '94000000-0000-4000-a000-000000000001',
  '94000000-0000-4000-9000-000000000001',
  'person',
  'Deactivate Client',
  'deactivate client',
  '94000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.client (id, office_id, party_id, created_by)
VALUES (
  '94000000-0000-4000-b000-000000000001',
  '94000000-0000-4000-9000-000000000001',
  '94000000-0000-4000-a000-000000000001',
  '94000000-0000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.legal_process (
  id, office_id, client_id, cnj_number, tribunal, system,
  is_public, monitoring_status, status, created_by
)
VALUES
  (
    '94000000-0000-4000-c000-000000000001',
    '94000000-0000-4000-9000-000000000001',
    '94000000-0000-4000-b000-000000000001',
    '00044531220268160009',
    'TJPR',
    'PJe',
    true,
    'paused',
    'active',
    '94000000-0000-4000-8000-000000000001'
  ),
  (
    '94000000-0000-4000-c000-000000000002',
    '94000000-0000-4000-9000-000000000001',
    '94000000-0000-4000-b000-000000000001',
    '00044531220268160010',
    'TJPR',
    'PJe',
    true,
    'paused',
    'inactive',
    '94000000-0000-4000-8000-000000000001'
  )
ON CONFLICT (id) DO NOTHING;

SELECT * FROM pg_temp.set_auth_user('94000000-0000-4000-8000-000000000001');

SELECT is(
  (SELECT jsonb_array_length(row->'processes')
     FROM public.get_client_portfolio_read_model(
       '94000000-0000-4000-b000-000000000001'
     ) AS row),
  1,
  'carteira ativa lista somente processos ativos'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
      FROM public.get_client_portfolio_read_model(
        '94000000-0000-4000-b000-000000000001'
      ) AS row
      CROSS JOIN LATERAL jsonb_array_elements(row->'processes') AS process
     WHERE process->>'processId' = '94000000-0000-4000-c000-000000000002'
  ),
  'processo já inativo não aparece na carteira'
);

SELECT lives_ok(
  $$SELECT public.deactivate_legal_process(
    '94000000-0000-4000-c000-000000000001'::uuid
  )$$,
  'ator autorizado consegue excluir o processo da carteira'
);

SELECT is(
  (SELECT status FROM public.legal_process
    WHERE id = '94000000-0000-4000-c000-000000000001'),
  'inactive',
  'exclusão preserva o registro como inativo'
);

SELECT is(
  (SELECT jsonb_array_length(row->'processes')
     FROM public.get_client_portfolio_read_model(
       '94000000-0000-4000-b000-000000000001'
     ) AS row),
  0,
  'processo excluído desaparece da carteira ativa'
);

SELECT * FROM finish();
ROLLBACK;
