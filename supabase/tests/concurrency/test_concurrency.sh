#!/bin/bash
set -e

echo "Preparando dados para teste de concorrência..."
docker exec supabase_db_juridico-sync psql -U postgres -d postgres -c "
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
docker exec supabase_db_juridico-sync psql -v ON_ERROR_STOP=1 -U postgres -d postgres -c "
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
docker exec supabase_db_juridico-sync psql -v ON_ERROR_STOP=1 -U postgres -d postgres -c "
BEGIN;
UPDATE public.user_profile SET is_active = false WHERE id = '00000000-0000-0000-0000-000000000012';
COMMIT;
" &
PID2=$!

echo "Aguardando conclusões..."
wait $PID1
RC1=$?

wait $PID2
RC2=$?

echo "RC1: $RC1"
echo "RC2: $RC2"

echo "Verificando resultado final..."
ACTIVE_OWNERS=$(docker exec supabase_db_juridico-sync psql -U postgres -d postgres -t -c "SELECT count(*) FROM public.user_profile WHERE office_id = '55555555-5555-5555-5555-555555555555' AND is_owner = true AND is_active = true;" | tr -d '[:space:]')

echo "Owners ativos finais: $ACTIVE_OWNERS"

if [ "$RC1" -eq 0 ] && [ "$RC2" -eq 0 ]; then
    echo "FALHA: Ambas as transações reportaram sucesso (0)."
    exit 1
fi

if [ "$RC1" -ne 0 ] && [ "$RC2" -ne 0 ]; then
    echo "FALHA: Ambas as transações falharam."
    exit 1
fi

if [ "$ACTIVE_OWNERS" -ne 1 ]; then
    echo "FALHA: Quantidade final de owners ativos ($ACTIVE_OWNERS) diferente de 1."
    exit 1
fi

echo "SUCESSO: Exatamente 1 sucesso, 1 rejeição, 1 owner ativo."
exit 0
