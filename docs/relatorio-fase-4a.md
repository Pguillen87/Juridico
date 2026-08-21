# Relatório de Execução - Fase 4A (Rodada Corretiva)

Este documento atesta a conclusão da **Fase 4A** com as correções finais de RLS, permissões e CI.

## Alterações Técnicas Implementadas
1. **Migration `office`:** `REVOKE ALL ON public.office FROM authenticated`, `GRANT SELECT`, e `GRANT UPDATE(name)` separados para garantir que o owner não possa alterar `is_active` ou `id` diretamente.
2. **Testes pgTAP:** 34 testes passando, com `set_auth_user` definindo a role `authenticated` corretamente e novos testes validando a imutabilidade de `is_active`, `id` e `created_at` de `office`.
3. **Teste de Concorrência:** Script `test_concurrency.sh` atualizado com `-v ON_ERROR_STOP=1`, captura rigorosa de RC1/RC2 e validação de que exatamente 1 owner permanece ativo no final.
4. **CI Atualizado:**
   - `supabase start` com saída sensível omitida.
   - Adicionado `db:reset`, `db:lint`, `db:test` e `concurrency test`.
   - Adicionado `db types check` comparando os tipos do banco com `src/types/database.types.ts` com diff.
5. **Lint:** Import não utilizado removido de `env.test.ts`.
6. **Types:** Arquivo `database.types.ts` atualizado com a saída exata do CLI para passar no `diff -u` do CI.

## Testes de Banco
- **pgTAP:** passed: 34 failed: 0
- **Concurrency:** RC transação 1: 0 RC transação 2: 1 owners ativos finais: 1

## Testes da Aplicação
- **format:** OK
- **lint:** OK (0 warnings do projeto)
- **typecheck:** OK
- **unit:** OK (6/6 unitários)
- **build:** OK
- **E2E:** OK (2/2 E2E)
- **PoC:** 29/29 testes passando

## Database types
O CI roda `npx supabase gen types typescript --local` e compara a saída com `src/types/database.types.ts` usando `diff -u`. O arquivo versionado bate exatamente com o gerado.

## Supabase local
- O Supabase local executa somente durante o job efêmero do GitHub-hosted runner;
- O workflow não publica/deploya esse stack como serviço externo;
- Não foi implementada nesta subfase uma prova explícita de bind 127.0.0.1 para workstation local;
- Essa validação permanece requisito operacional do fechamento do ambiente Docker/local;
- Isso foi aceito pela auditoria como limitação não bloqueante da Fase 4A.

## CI GitHub
O CI final deve ser verificado externamente no GitHub Actions usando o SHA do commit que contém este relatório.

Critério esperado:
- workflow App CI;
- branch phase-4-auth-rls;
- status completed;
- conclusion success;
- head_sha exatamente igual ao HEAD da branch.

A resposta final da execução informará os valores reais.
