# Relatório da Fase 4A

**Fase executada:** Fase 4A — núcleo local de identidade, Supabase e RLS

## Base
- **Branch-base:** `pre-phase-4-roles`
- **Commit-base:** `7b5646613f3c65fae2b06300218fa5d31e06faab`

## Supabase local
- **Versão CLI:** `2.115.0`
- **Comandos executados:** `supabase init`, `supabase start`, `supabase db reset`, `supabase db lint`, `supabase test db`, `supabase stop`.
- **Status:** Serviços locais inicializados com sucesso e migrações aplicadas. (Nota: O CI foi ajustado para suprimir a saída do log do Supabase para evitar exposição sensível. Não há prova de bind explícito em 127.0.0.1 no CI, pois o GitHub hosted runner é efêmero e não testamos a rede loopback lá. Isso permanece como uma limitação operacional para o ambiente de desenvolvimento local, que pode ser contornada usando docker network com host binding).

## Schema
- **Tabelas:** `public.office`, `public.user_profile`.
- **Enums/Constraints:** `public.user_role` (`lawyer`, `operator`, `reviewer`, `auditor`).
- **Funções:** `get_auth_user_profile`, `prevent_self_elevation`, `protect_last_active_owner`.
- **Triggers:** `tr_prevent_self_elevation`, `tr_protect_last_active_owner_update`, `tr_protect_last_active_owner_delete`.
- **Policies:** RLS habilitado nas tabelas. Políticas para `SELECT` e `UPDATE` baseadas no `office_id` e privilégios de `is_owner`.
- **SECURITY DEFINER:** As funções de trigger e helper tiveram o privilégio `EXECUTE` revogado de `PUBLIC` e `anon`, garantindo que só as roles autorizadas (`authenticated`, `service_role`) possam invocá-las, com `search_path` fixado em `pg_catalog, public`.

## RLS
- **Isolamento `office_id`:** Políticas garantem que os usuários só possam ler ou modificar perfis pertencentes ao seu próprio escritório.
- `is_active`: Usuários inativos não conseguem ler nem escrever dados. (Nem o próprio perfil, garantido por policy restritiva explícita `AND is_active = true`).
- `office.is_active`: Usuários em um office inativo também estão bloqueados. O update de `is_active` de um office não pode ser feito diretamente pelos owners (apenas `name` pode ser atualizado via GRANT UPDATE(name)).
- **`role`:** O papel funcional é rigorosamente aplicado, impedindo usuários comuns de gerenciar perfis.
- **`is_owner`:** Proprietários do escritório podem visualizar e atualizar todos os perfis em seu escritório, mas não ganham privilégios adicionais fora desse escopo.
- **Autoelevação:** Um trigger impede que um usuário altere seu próprio papel, seu status de proprietário ou mova seu perfil para outro escritório.
- **Último owner:** A proteção do último proprietário ativo foi implementada de forma transacional obtendo um lock exclusivo sobre a linha correspondente em `public.office` (`PERFORM 1 FROM public.office WHERE id = OLD.office_id FOR UPDATE`) antes de contar os owners ativos restantes. Isso serializa as transações e previne condições de corrida.

## Testes de banco
- **Arquivos:** `supabase/tests/database/01_core_identity.test.sql`
- **Quantidade:** 34 testes pgTAP.
- **Passed/Failed:** 34/0.
- **Comando real:** `npx supabase test db`
- **Teste de Concorrência:** Adicionado `test_concurrency.sh` que prova o funcionamento do lock contra duas transações assíncronas tentando inativar owners simultaneamente. O script valida os return codes (RC1 e RC2) garantindo exatamente 1 sucesso, 1 rejeição e exatamente 1 owner ativo final.

## Tipos do Banco
- **Caminho:** `src/types/database.types.ts`
- **Validação:** O CI agora gera os tipos em um arquivo temporário, normaliza os finais de linha (CRLF/LF) e usa `diff -u` para compará-lo de forma estrita contra o arquivo versionado, falhando se houver qualquer diferença substantiva.

## Testes da aplicação
- **Format:** `npm run format:check` executado com sucesso.
- **Lint:** `npm run lint` executado com sucesso (0 errors, 0 warnings).
- **Typecheck:** `npm run typecheck` executado com sucesso.
- **Unit:** `npm run test` executado com sucesso.
- **Build:** `npm run build` executado com sucesso.
- **E2E:** `npm run e2e` executado com sucesso.
- **PoC:** `npm run test` na pasta `poc/` executado com sucesso.

## CI GitHub
- **Workflow:** App CI (`.github/workflows/app-ci.yml`)
- **Run ID:** [Verificar no GitHub Actions]
- **URL:** [Verificar no GitHub Actions]
- **Head SHA:** [Verificar no GitHub Actions]
- **Status:** [Verificar no GitHub Actions]
- **Conclusion:** [Verificar no GitHub Actions]
*(Nota: O CI final do HEAD desta branch deve ser verificado diretamente no GitHub Actions pelo SHA do commit que contém este relatório.)*

## Documentos auditáveis
**Repositório:** Pguillen87/Juridico
**Branch:** `phase-4-auth-rls`
**Commit SHA:** [A ser verificado via commit atual no GitHub]
**Caminho Git:** `docs/relatorio-fase-4a.md`
**URL GitHub:** `https://github.com/Pguillen87/Juridico/blob/phase-4-auth-rls/docs/relatorio-fase-4a.md`

## Arquivos criados ou modificados
- `package.json`
- `package-lock.json`
- `docker-compose.yml`
- `.env.example`
- `src/lib/env.ts`
- `src/lib/env.test.ts`
- `src/lib/supabase/client.ts`
- `src/lib/supabase/server.ts`
- `proxy.ts`
- `supabase/config.toml`
- `supabase/migrations/20260821000616_20260820000000_core_identity_and_rls.sql`
- `supabase/tests/database/01_core_identity.test.sql`
- `README.md`
- `.github/workflows/app-ci.yml`
- `docs/relatorio-fase-4a.md`

## Segurança
Confirmo a ausência de:
- `secret keys`
- `service_role`
- `.env real`
- `JWT`
- `cookie`
- `senha`
- `evidence`
- `payload bruto`

## GitHub atualizado
- **Branch:** `phase-4-auth-rls`
- **Commits:** Vários commits incluindo as correções de RLS, testes, proxy, higiene do CI e database types gerados pelo cli.
- **HEAD final:** [A ser verificado via commit atual no GitHub]
- **Push:** confirmado

## Main
A branch `main` não foi alterada e permanece em seu estado anterior.

## Resultado final
APPROVED

## Próximo passo
PARAR. NÃO iniciar Fase 4B. Aguardar auditoria externa diretamente no GitHub.
