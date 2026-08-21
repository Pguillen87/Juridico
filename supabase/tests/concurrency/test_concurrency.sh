#!/bin/bash
set -e

echo "Preparando dados para teste de concorrência..."
npx supabase db query "
INSERT INTO auth.users (id, email) VALUES 
    ('00000000-0000-0000-0000-000000000011', 'owner1@officeE.com'),
    ('00000000-0000-0000-0000-000000000012', 'owner2@officeE.com')
ON CONFLICT DO NOTHING;

INSERT INTO public.office (id, name, is_active) VALUES 
    ('55555555-5555-5555-5555-555555555555', 'Office E', true)
ON CONFLICT DO NOTHING;

INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active) VALUES 
    ('00000000-0000-0000-0000-000000000011', '55555555-5555-5555-5555-555555555555', 'Owner 1 E', 'lawyer', true, true),
    ('00000000-0000-0000-0000-000000000012', '55555555-5555-5555-5555-555555555555', 'Owner 2 E', 'lawyer', true, true)
ON CONFLICT DO NOTHING;
"

echo "Iniciando transação 1 em background..."
# Transação 1: Inativa o owner 1, mas segura a transação por 2 segundos antes do commit
npx supabase db query "
BEGIN;
UPDATE public.user_profile SET is_active = false WHERE id = '00000000-0000-0000-0000-000000000011';
SELECT pg_sleep(2);
COMMIT;
" &
PID1=$!

# Aguarda 0.5s para garantir que a transação 1 adquiriu o lock
sleep 0.5

echo "Iniciando transação 2 em background..."
# Transação 2: Tenta inativar o owner 2. Deve bloquear aguardando o lock da transação 1.
# Quando a transação 1 commitar, a transação 2 avaliará a trigger e deverá falhar.
npx supabase db query "
BEGIN;
UPDATE public.user_profile SET is_active = false WHERE id = '00000000-0000-0000-0000-000000000012';
COMMIT;
" &
PID2=$!

echo "Aguardando conclusões..."
wait $PID1 || true
wait $PID2 || true

echo "Verificando resultado final..."
ACTIVE_OWNERS=$(npx supabase db query "SELECT count(*) FROM public.user_profile WHERE office_id = '55555555-5555-5555-5555-555555555555' AND is_owner = true AND is_active = true;" | grep -o '[0-9]\+' | tail -n 1)

if [ "$ACTIVE_OWNERS" -eq 0 ]; then
    echo "FALHA: O teste de concorrência permitiu inativar todos os owners."
    exit 1
else
    echo "SUCESSO: Restam $ACTIVE_OWNERS owners ativos. A proteção funcionou."
    exit 0
fi
