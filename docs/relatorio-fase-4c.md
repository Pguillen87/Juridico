# Relatório de execução — Fase 4C

## 1. Resultado executivo

A Fase 4C foi implementada localmente a partir da baseline aprovada da Fase 4B (`f17146a0557c5959f1fcc8dc929c467987e487fc`). A entrega encerra a macro Fase 4 como **control plane de autorização e administração**, mantendo Next.js 16, Server Actions, Supabase/PostgreSQL, RLS e execução local/Docker. Nenhum Supabase remoto foi utilizado e `main` não foi alterada.

O pacote inclui catálogo canônico das 29 ações D-022, autorização em profundidade no Next e no banco, RPCs `SECURITY DEFINER` controladas, auditoria administrativa append-only, administração de usuários, administração restrita do office, rate limiting persistente em PostgreSQL, telas administrativas, fixtures para as oito combinações role/is_owner e matriz ampliada de testes.

## 2. Decisões preservadas

| Tema | Decisão implementada |
|---|---|
| Identidade funcional | Um único `role`: `lawyer`, `operator`, `reviewer` ou `auditor`; `is_owner` permanece ortogonal. |
| Remoção de usuários | Somente inativação lógica; hard delete de Auth/profile e UI correspondente permanecem fora da 4C. |
| Office | Owner visualiza o status e pode alterar somente o nome do próprio office. Não desativa, não troca ID, não move usuários e não há outras configurações nesta fase. |
| Auditoria administrativa | Auditor e qualquer role com `is_owner=true` podem consultar/exportar auditoria administrativa. Lawyer/operator/reviewer sem owner são negados. Owner não recebe auditoria operacional por esse atributo. |
| Retenção | Não há TTL, purge, delete periódico ou cron. A exclusão automática fica pendente de política formal: “Sem exclusão automática até aprovação formal da política de retenção.” |
| Rate limit | PostgreSQL, com escopo `(office_id, actor_user_id, operation)`. Redis ficou fora da 4C; IP não é armazenado. |
| Auth invite-only | `auth.enable_signup=false` e `auth.email.enable_signup=true`: signup público bloqueado, login e convites administrativos preservados. Após mudança de `config.toml`, usar `supabase stop` e `supabase start`. |
| Recovery 4B | O fluxo de recovery não foi corrigido por hipótese. A dívida existente permanece condicionada a reprodução determinística, teste vermelho, causa identificada e teste verde. |
| Revisão visual especializada | Impeccable permaneceu indisponível e não foi simulado. A UI foi validada por build e Playwright; revisão visual especializada fica registrada como passo futuro. |

## 3. Componentes entregues

| Camada | Entrega |
|---|---|
| Autorização | `src/lib/auth/permissions.ts` e `requirePermission()` com fail-closed para perfil/office inativo. |
| Banco | Migrations `20260822000001_phase_4c_authorization_audit.sql` e `20260822000002_phase_4c_rate_limit.sql`. |
| RPCs | `change_user_role`, `set_user_active`, `set_user_owner`, `update_office_name`, `get_administrative_audit`, `record_invite_audit`, `record_audit_export` e `consume_admin_rate_limit`. |
| Auditoria | Tabela append-only `public.audit_log`, trigger de mutação, metadata allowlisted de before/after e ausência de segredos/payloads brutos. |
| Usuários | Convite integrado ao audit e limiter; ações de role, status e owner com validação e RPC; sem hard delete. |
| Office | Página e action para alteração exclusiva do nome; status somente leitura. |
| Auditoria UI | Consulta restrita por office, visualização de eventos e exportação CSV limitada. |
| Fixtures/E2E | Fixtures das oito combinações role/is_owner e `tests-e2e/admin.spec.ts`; locator do convite ajustado para coexistir com ações por linha. |
| Concorrência | `scripts/test-rate-limit-concurrency.ps1`, prova local de seis chamadas concorrentes. |

## 4. Defaults de rate limit

| Operação | Limite | Janela |
|---|---:|---:|
| `admin.invite` | 5 | 15 minutos |
| `admin.change_role` | 20 | 15 minutos |
| `admin.set_active` | 20 | 15 minutos |
| `admin.set_owner` | 10 | 15 minutos |
| `admin.update_office_name` | 10 | 15 minutos |
| `admin.audit_export` | 3 | 1 hora |

A função PostgreSQL usa chave primária por operação, office e actor, `INSERT ... ON CONFLICT`, `SELECT ... FOR UPDATE` e atualização atômica da janela. Quando bloqueada, retorna contagem e `retry_after_seconds` sem expor e-mail, IP ou dados sensíveis.

## 5. Evidências locais

| Verificação | Resultado |
|---|---|
| Unitários Vitest | **37 testes aprovados** em 9 arquivos. |
| `npm run typecheck` | Aprovado. |
| `npm run lint` | Aprovado. |
| `npm run format:check` | Aprovado. |
| `supabase db lint` | Sem erros de schema. |
| pgTAP | **84 assertions aprovadas** em 3 suítes: 34 legadas, 31 de autorização/auditoria e 19 de rate limit. |
| Auth + Administração E2E | **16 cenários aprovados**: 12 da Fase 4B e 4 administrativos da 4C. |
| Build Next standalone | Aprovado durante o runner E2E e no build Docker. |
| Docker build | Imagem `juridico:phase-4c` criada com sucesso no Docker Desktop. |
| Docker smoke | Container temporário respondeu `HTTP 200` em `/api/health`; container removido após o teste. |
| Concorrência | 6 chamadas simultâneas: `5` permitidas, `1` bloqueada, `final_count=5`. |

## 6. Fluxo de execução Docker

O pacote pode ser executado localmente com o Supabase local e o compose existente. O build fechado usa a imagem Next standalone e não adiciona Redis ou outro serviço de infraestrutura para a 4C. As variáveis públicas do Supabase entram no container por ambiente; a chave administrativa deve permanecer apenas no servidor e nunca ser colocada em `NEXT_PUBLIC_*`.

A sequência validada foi: `supabase stop`, `supabase start`, `supabase db reset`, execução das suítes pgTAP, build standalone, fixtures Auth, Playwright e build/smoke Docker. A imagem gerada foi testada e o container temporário foi encerrado ao final.

## 7. Auditoria Complementar e Publicação

A implementação da Fase 4C original foi aprovada pela auditoria externa, mas exigiu um fechamento formal para três lacunas de integridade de auditoria e testes.

- **Evidência de Execução CI**: Pode ser verificado dinamicamente no GitHub Actions pelo status `completed/success` no HEAD final desta branch `phase-4c-admin-control-plane`.
- **Estratégia Escolhida para Last-Owner**: Action wrapper intercepta o erro P0001 da RPC e chama o writer `record_rejection_audit_internal` executado via `service_role`. Rejeições por chamada direta à RPC continuam não auditadas (limitação técnica aceita da transação PostgreSQL).
- **Estratégia Escolhida para Auditoria/Rate Limit**: A migration incremental `20260822000003_phase_4c_audit_integrity.sql` revogou o acesso `authenticated` às RPCs de gravação de convite e exportação. Foi criada a `export_administrative_audit` combinada (leitura, rate limit e auditoria na mesma transação) e as funções de gravação `internal` foram restritas à `service_role`.
- **Resultado do Teste de Concorrência Rate Limit**: Teste de concorrência adaptado para PowerShell no CI; verificado `allowed=5`, `blocked=1`, `final_count=5`.

O código, as migrations incrementais e os testes foram validados localmente e publicados na branch GitHub `phase-4c-admin-control-plane`. Nenhuma alteração foi feita em `main` e nenhum serviço remoto de produção foi modificado.

## Atualização da execução autorizada — 25/08/2026

Os gates foram reexecutados no workspace recuperado. O baseline terminou com format:check, lint, typecheck, 43 testes unitários aprovados e build aprovado. O banco local passou por db reset e db lint; o pgTAP registrou 100 testes e 0 falhas. Os tipos gerados pelo Supabase foram comparados ao arquivo versionado e ficaram iguais.

As fixtures Auth foram preparadas para oito combinações role/owner, recovery e usuário inativo. O Auth/Admin E2E passou com 16 cenários aprovados e 0 falhas, após um reset limpo do banco. O teste de rate limit passou com allowed=5, blocked=1 e final_count=5. O script existente de concorrência last-owner terminou com sucesso, confirmando uma operação vencedora, uma rejeitada e exatamente um owner ativo ao final. A regressão da PoC passou com 29/29 testes.


O Docker web foi constru�do com sucesso. O smoke test iniciou o servi�o, recebeu HTTP 200 em /api/health com corpo {"status":"ok"} e confirmou nextjs como usu�rio de runtime n�o-root. O servi�o foi removido com docker compose down; o Supabase local permaneceu separado.

A auditoria Production Stack, limitada � Fase 4C, n�o identificou bloqueadores CRITICAL ou HIGH no c�digo, migrations, autoriza��o, auditoria, rate limit, compensa��o de convite ou CI. Foram mantidas como melhorias futuras MEDIUM/LOW a pinagem de imagens por digest, HEALTHCHECK nativo no Dockerfile, limites de recursos no Compose, observabilidade ampliada e scan Trivy. O workflow CI foi confirmado como read-only, sem comandos de git add, commit, push, reset, restore, checkout ou clean.

O plano docs/plano-fase-4c.md foi preservado. N�o inserir SHA final ou Run ID neste relat�rio. A publica��o deve ocorrer somente na branch phase-4c-admin-control-plane, sem alterar main, sem merge, sem force-push e sem iniciar a Fase 5; ap�s o novo App CI, a execu��o deve parar para auditoria externa.
