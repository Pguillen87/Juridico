# Matriz de Rastreabilidade

## Objetivos

| ID | Objetivo |
|---|---|
| O-001 | Reduzir verificação manual de processos. |
| O-002 | Detectar alterações com fonte e evidência. |
| O-003 | Separar falha de ausência de movimentação. |
| O-004 | Alertar e gerar relatório com aprovação humana. |
| O-005 | Isolar dados, auditar ações e proteger dados pessoais. |
| O-006 | Validar tecnicamente a solução antes da carteira integral. |

## Matriz

| Objetivo | Requisito | História | Entidade | Componente | Fase | Teste | Evidência | Status |
|---|---|---|---|---|---|---|---|---|
| O-005 | RF-001 | US-001 | `user_profile` | Auth/API | 3 | T-001 login | Relatório E2E | Planned |
| O-005 | RF-001 | US-002 | `user_profile` | Auth/E-mail | 3 | T-002 recovery | Evidência sandbox | Planned |
| O-005 | RF-002 | US-003 | `user_profile`, `office` | Auth/RLS | 3–4 | T-003 roles | Matriz de permissão | Planned |
| O-005 | RF-003 | US-004 | `party`, `client` | Cadastro/API/UI | 5 | T-004 client | RPC transacional, pgTAP, unit, E2E real: criar/listar cliente, parte principal, editar/desativar | Implemented/Tested |
| O-005 | RF-003 | US-005 | `party`, `client_related_party` | Cadastro/API/UI | 5 | T-005 parties | RPC transacional, RLS, pgTAP, unit e E2E real: relação pending, confirmação/rejeição, roles, homônimos e isolamento | Implemented/Tested |
| O-001 | RF-004 | US-006 | `legal_process` | Processos/API/UI | 6 | T-006 manual process | RPC transacional, CNJ DB-side, RLS, pgTAP, unit e E2E lawyer/operator | Implemented/Tested |
| O-001 | RF-005 | US-007 | `legal_process`, `process_party`, `process_import_preview` | Importação/API/UI | 6 | T-007 CSV | Parser dedicado, preview privado, hash/TTL, erros por linha, confirm transacional, pgTAP, unit e E2E | Implemented/Tested |
| O-001 | RF-004 | US-008 | `legal_process` | Validador/API/UI | 6 | T-008 CNJ | Validador universal, dígitos verificadores, CNJ canônico, unit, pgTAP e E2E | Implemented/Tested |
| O-005 | RF-003 | US-009 | `process_party` | Vínculos/API/UI | 6 | T-009 N:N | Relação N:N real, sempre pending na criação, IDs/RLS, pgTAP e E2E | Implemented/Tested |
| O-005 | RF-003 | US-010 | `process_party`, `audit_log` | Vínculos/API/UI | 6 | T-010 confirmation | Confirm/reject somente lawyer, transição terminal, auditoria atômica, pgTAP, concorrência e E2E | Implemented/Tested |
| O-001 | RF-004 | US-011 | `legal_process.monitoring_status` | Monitoramento | 6,9 | T-011 activation | RPC `manage_monitoring`, processo público/ativo, auditoria e sandbox sem seed ativo | Implemented/Tested — sandbox only |
| O-001 | RF-006 | US-012 | `query_job` | Queue/API | 9 | T-012 manual query | Infraestrutura de job existe, mas não há endpoint browser de consulta manual | Partial/Deferred — US-012 requer decisão específica |
| O-001 | RF-006 | US-013 | `monitoring_schedule`, `query_job` | Scheduler | 9 | T-013 schedule | Tick determinístico, timezone IANA, janela UTC e idempotência | Implemented/Tested — sandbox only |
| O-002 | RF-006 | US-014 | `provider`, `query_execution` | DataJudProvider | 1,7–9 | T-014 contract | Provider fake, gateway com payload, worker sandbox e falhas classificadas | Implemented/Tested — sem transporte real |
| O-002 | RF-006 | US-015 | `provider`, `query_execution` | ManualProvider | 7–9 | T-015 manual provider | Fonte manual distinta, sem fallback automático ou entrada de resultado | Partial/Deferred — D-022 não autoriza `manual_provider_entry` |
| O-002 | RF-007 | US-016 | `raw_provider_payload` | Storage | 8–9 | T-016 raw payload | Hash/sanitização, relação indireta por execution e atomicidade | Implemented/Tested — storage privado |
| O-002 | RF-007 | US-017 | `process_snapshot` | Normalizador | 7–9 | T-017 normalize | Dados normalizados, missing fields e snapshot somente de observation | Implemented/Tested — comparação futura fora |
| O-002 | RF-007 | US-018 | `process_snapshot` | Snapshot | 9 | T-018 snapshot | Um snapshot imutável por execução, hash canônico e provenance | Implemented/Tested — sandbox only |
| O-002 | RF-007 | US-019 | `process_snapshot` | Comparador | 10 | T-019 baseline | Resultado esperado | Planned |
| O-003 | RF-008 | US-020 | `process_movement` | Deduplicação | 10 | T-020 dedupe movement | Constraint/hash | Planned |
| O-002 | RF-008 | US-021 | `detected_change` | Comparador | 10 | T-021 change | Fingerprint | Planned |
| O-003 | RF-008 | US-022 | `query_execution` | Comparador/UI | 10 | T-022 unchanged | Estado exibido | Planned |
| O-003 | RF-009 | US-023 | `query_execution` | Failure center | 9,11 | T-023 source unavailable | `source_unavailable` persistido, retry limitado e mensagem sanitizada | Implemented/Tested — central UI futura |
| O-003 | RF-009 | US-024 | `query_execution`, `query_job` | Worker | 9,11 | T-024 timeout | Claim, lease, recovery, token anti-stale e conclusão server-only | Implemented/Tested — sandbox only |
| O-003 | RF-009 | US-025 | `query_job` | Retry | 9,11 | T-025 rate limit | Máximo de três tentativas, backoff/teto e terminalização | Implemented/Tested — sandbox only |
| O-003 | RF-009 | US-026 | `query_execution` | Failure center | 8,11 | T-026 not found | `not_found` terminal explícito, sem snapshot e sem `unchanged` | Implemented/Tested — persistência sandbox; UI futura |
| O-003 | RF-009 | US-027 | `provider_capability` | Provider | 7,9,11 | T-027 unsupported | Capability/provider allowlisted; incompatibilidade não chama provider | Implemented/Tested — sandbox |
| O-003 | RF-009 | US-028 | `query_execution` | Failure center | 11 | T-028 failure center | Estados e códigos persistidos para futura central, sem UI nova nesta fase | Partial/Deferred — UI futura |
| O-003 | RF-009 | US-029 | `query_job` | Queue/API | 9,11 | T-029 reprocess | RPC permanece sem EXECUTE público enquanto a autorização específica não estiver fechada | Partial/Deferred — sem endpoint |
| O-004 | RF-010 | US-030 | `notification` | EmailProvider | 11 | T-030 email sandbox | Mensagem | Planned |
| O-004 | RF-008 | US-031 | `notification` | Idempotência | 11 | T-031 dedupe notification | Chave única | Planned |
| O-004 | RF-011 | US-032 | `weekly_report` | Scheduler/Reports | 12 | T-032 weekly | Período | Planned |
| O-004 | RF-011 | US-033 | `report_process` | Reports/UI | 12 | T-033 by process | Tela/fixture | Planned |
| O-004 | RF-011 | US-034 | `report_party` | Reports/UI | 12 | T-034 by party | N:N | Planned |
| O-004 | RF-011 | US-035 | `report_version` | Reports/UI | 12 | T-035 edit | Nova versão | Planned |
| O-004 | RF-011 | US-036 | `report_version` | Reports | 12 | T-036 version | Imutabilidade | Planned |
| O-004 | RF-011 | US-037 | `weekly_report` | Authorization | 12 | T-037 approval | Estado auditado | Planned |
| O-004 | RF-012 | US-038 | `report_artifact` | PDF/Storage | 13 | T-038 PDF hash | Artefato privado | Planned |
| O-004 | RF-012 | US-039 | `email_delivery` | Delivery | 13 | T-039 send | Bloqueio | Planned |
| O-004 | RF-012 | US-040 | `email_delivery`, `report_artifact` | Delivery | 13 | T-040 immutable copy | Hash/URI | Planned |
| O-005 | RF-013 | US-041 | `audit_log` | Audit | 3–14 | T-041 audit | Append-only | Planned |
| O-005 | RF-002 | US-042 | `office`, todas | RLS | 4,14 | T-042 isolation | Teste negativo | Planned |
| O-005 | RF-013 | US-043 | `raw_provider_payload`, `audit_log` | Retention | 4,14 | T-043 retention | Relatório | Planned |
| O-004 | RF-014 | US-044 | `report_version`, `audit_log` | IA opcional | 12 | T-044 draft | Marcação/bloqueio | Planned |

## Cobertura Crítica

As histórias `Must` possuem ao menos um teste associado. Na Fase 5, US-004 e US-005 foram implementadas e testadas por RPCs transacionais, RLS, pgTAP, unitários e E2E. Na Fase 6, US-006 a US-010 foram implementadas e testadas com RPCs, RLS, pgTAP, unitários, E2E e concorrência. US-011 permanece parcial/deferida: existe somente estado estrutural `paused`, sem provider, scheduler, fila, capability ou job.

## Aceite funcional adicional da Fase 5

A UI `/app/clientes` lista clientes, parties e vínculos relacionados. Parties homônimas são exibidas com referência curta derivada do ID, tipo e status; a seleção de uma party ocorre por ID, nunca por nome. O módulo `/app/processos` lista processos com CNJ canônico, client/party por ID e referência curta, vínculos pendentes/terminais, importação CSV com preview, erros por linha e confirmação explícita. O fluxo E2E cobre lawyer, operator, reviewer e auditor conforme D-022; monitoramento permanece transparente e pausado. `legal_process` e `process_party` foram implementados na Fase 6; US-011 permanece `Partial/Deferred`.

## Evidência adicional de RLS da Fase 6

O teste `10_phase_6_rls_read_hardening.test.sql` prova diretamente no PostgreSQL, com role `authenticated` e JWT sintético, que reviewer lê somente o próprio office; auditor não lê `legal_process` nem `process_party`; `is_owner=true` não amplia o acesso operacional; usuário ativo de office inativo não lê as tabelas; e dados de outro office permanecem invisíveis. O mesmo teste comprova que o preview expirado é rejeitado e permanece `pending` porque o `UPDATE` seguido de `RAISE EXCEPTION` sofre rollback. A suíte completa passou com 214 asserções.

## Evidências Esperadas

As evidências incluem testes unitários, testes E2E, fixtures, resultados de sandbox, logs sanitizados, hashes, registros de auditoria, testes RLS, fichas por processo da PoC, relatórios de backup/restauração e revisão manual do advogado. Nenhuma evidência poderá incluir segredo ou processo não autorizado.

## Evidência da Fase 7 — Abstração de Provedores

A Fase 7 adiciona a abstração interna `ProviderContractV1` em `src/lib/providers/`, com capabilities allowlisted, request interna, observação normalizada, falha explícita, normalização determinística, registry code-only, gateway backend-only e fixture sintética. O contrato não produz `changed` nem `unchanged`; comparação pertence à Fase 10.

| Objetivo | Requisito | História | Componente | Teste | Status |
|---|---|---|---|---|---|
| O-002 | RF-006 | US-014 | Contrato de provider | `src/lib/providers/providers.test.ts`: contrato e capability | Partial/Deferred — sem DataJud real |
| O-002 | RF-006 | US-015 | `ManualProvider` | observação manual sintética, evidência e falha explícita | Partial/Deferred — entrada operacional sem ação D-022 aprovada |
| O-002 | RF-007 | US-017 | Normalização de observação | resposta normalizada, `missingFields` e validação runtime | Implemented/Tested — snapshots e persistência deferidos |
| O-003 | RF-009 | US-027 | Registry/Gateway | provider ou capability ausente retorna `not_supported` | Implemented/Tested |

A D-022 canônica (`docs/10-matriz-papeis-e-autorizacao.md`) possui `manual_reprocess` para lawyer/operator, mas não possui ação `manual_provider_entry`. Nenhuma role foi inventada para entrada manual operacional; essa expansão permanece decisão humana pendente e critério de parada. Nenhum provider real, DataJud, credencial, scheduler, fila, worker, snapshot ou comparador foi adicionado.

## Evidência do corretivo da Fase 7 — integridade e validação runtime

| Objetivo | Requisito | História | Componente | Teste | Status |
|---|---|---|---|---|---|
| O-002 | RF-007 | US-017 | `ManualProvider` exige `processRef` observado igual ao `subjectRef` solicitado | `providers.test.ts`: mesmo processo é aceito; processo divergente retorna `manual_review_required/manual_process_mismatch` | Implemented/Tested |
| O-002 | RF-007 | US-017 | Falha de integridade permanece `source=manual` e não vira `not_found` ou `unchanged` | assertions de ramo, status, mensagem sanitizada e ausência de estados de comparação | Implemented/Tested |
| O-003 | RF-009 | US-027 | Validator runtime fecha o contrato por allowlists e coerência | `providers.test.ts`: resultado válido aceito e resultado estruturalmente incoerente rejeitado | Implemented/Tested |

O corretivo não amplia D-022, não cria entrada manual operacional, não altera banco e não antecipa Fase 8 ou Fase 10.

## Fechamento do corretivo da Fase 7

| Critério | Evidência | Resultado |
|---|---|---|
| Processo solicitado igual ao observado | `ManualProvider` compara `subjectRef.value` com `ManualObservationInput.processRef` | observação aceita quando igual |
| Processo solicitado diferente do observado | retorno `manual_review_required` com `manual_process_mismatch` e `source=manual` | falha explícita, sanitizada e sem `not_found`/`unchanged` |
| Resultado runtime válido | validator valida contrato, descriptor, capability, source, metadata, campos normalizados e request | aceito |
| Resultado runtime incoerente | validator rejeita chaves extras, campos proibidos, estados de comparação e allowlists inválidas | rejeitado |
| Regressão | 72 unit, 214 pgTAP, 25 E2E, 29 PoC, concorrências e Docker | verde |

A mudança é corretiva e localizada na Fase 7. Não há antecipação da Fase 8, alteração de D-022, migration, RLS, grant, RPC ou integração externa.

## Evidência da Fase 8 — DataJud sandbox e persistência privada

A Fase 8 foi implementada na branch `phase-8-datajud-manual`, derivada do HEAD aprovado da Fase 7 `7cf007aed354b95efc1af547e0490be3bc7d0880`. O corretivo incremental parte do commit publicado `e51849cc30033810aa62b74cfc486ac7a4aca370`; `main` permanece inalterada. O `DataJudProvider` desta fase usa exclusivamente transporte fake injetável e fixtures sintéticas; o modo de transporte real permanece explicitamente desabilitado, sem CNJ real, processo real, credencial real, chamada externa, produção ou piloto.

| Objetivo | Requisito | História | Componente | Teste | Status |
|---|---|---|---|---|---|
| O-002 | RF-006 | US-014 | `DataJudProvider` sandbox | `datajud.test.ts`: observação, timeout, 429, 5xx, network/DNS, not found, schema inválido, mismatch e capability | Implemented/Tested — transporte real desabilitado |
| O-002 | RF-007 | US-016 | `provider_exchange`, `raw_provider_payload` | `11_phase_8_provider_payload.test.sql`: 57 assertions de hash, bytes, sanitização, RLS, grants, actor, idempotência e acesso bruto protegido | Implemented/Tested — storage privado e append-only |
| O-002 | RF-007 | US-017 | Normalização DataJud → `ProviderResultV1` | `datajud.test.ts` e `providers.test.ts`: somente `observation` ou `failure`, sem `changed`/`unchanged` | Implemented/Tested |
| O-003 | RF-009 | US-026/US-027 | Taxonomia de falhas | testes sintéticos para `not_found`, `not_supported`, `source_unavailable`, `technical_failure`, timeout e rate limit | Implemented/Tested — comparação permanece na Fase 10 |
| O-005 | RF-013 | US-041/US-043 | Auditoria e retenção privada | pgTAP: 57 assertions de auditoria atômica, rollback quando audit falha, imutabilidade, grants mínimos e ausência de DML direto | Implemented/Tested |
| O-002 | RF-006 | US-015 | `ManualProvider` operacional | `providers.test.ts` e pgTAP: `manual_provider_entry` ausente e RPC DataJud rejeita `manual_observation` | Partial/Deferred — decisão humana D-022 pendente |

O backend realiza preflight DB-side para impedir consulta automática quando o processo não existe no escritório do ator, está inativo ou possui `is_public=false`; a RPC repete a verificação antes da persistência. O caminho privilegiado é server-only: a sessão real fornece o actor ao backend, e a wrapper `require_provider_actor` reconsulta `user_profile` e `office`, exige ambos ativos e projeta somente a identidade validada nas checagens existentes. Nenhum `office_id`, role, `is_owner` ou actor enviado pelo browser é autoridade. A migration 00010 revoga EXECUTE das RPCs públicas originais para `PUBLIC`, `anon`, `authenticated` e `service_role`; as wrappers `*_internal` recebem EXECUTE somente de `service_role` e são chamadas pelo `createAdminClient()` exclusivamente no backend. O fluxo DataJud sandbox limita roles a `lawyer`/`operator`, revoga DML direto e grava troca, payload opcional e auditoria na mesma transação. A leitura de payload bruto ocorre somente pela RPC interna protegida para `lawyer`; `operator`, `reviewer`, `auditor` e `is_owner` sem `role=lawyer` permanecem sem esse acesso.

A configuração de segredo registra apenas estado `absent`/`present`; nenhum valor de credencial é retornado, persistido ou incluído em logs, erros ou fixtures. A sanitização remove chaves sensíveis, rejeita valores de segredo, limita tamanho/profundidade e calcula SHA-256 sobre JSON canônico. O armazenamento de `raw_provider_payload` é privado, referenciado por `office_id`, protegido por hash/bytes, trigger de integridade e triggers append-only. O `service_role` não recebe DML direto nas tabelas; atua somente via EXECUTE mínimo das wrappers internas, com `search_path` fixo e revalidação DB-side do actor.

Na Fase 8 não foram criados `query_job`, `query_execution`, scheduler, fila, worker, snapshot, comparação, `detected_change`, UI de entrada manual ou integração real. A entrada manual operacional continua bloqueada até que a D-022 possua uma ação explícita e uma decisão humana aprovada.

## Evidência da Fase 9 — Scheduler, fila, worker e snapshots

A Fase 9 foi implementada somente em sandbox sintético a partir do commit `9246583b799a2d5a6e207e3fc7b9944a64a019be` da branch `phase-8-datajud-manual`. A branch de implementação é `phase-9-scheduler-queue-snapshots`; nenhuma alteração foi feita em `main`. A infraestrutura usa fila PostgreSQL/Supabase, RPCs internas com `SECURITY DEFINER`, `search_path` fixo e `EXECUTE` somente para `service_role`; o navegador não cria jobs privilegiados, não reivindica leases e não executa worker.

| Objetivo | Componente | Evidência | Status |
|---|---|---|---|
| Monitoramento autorizado | `phase9_set_process_monitoring_status` e `manage_monitoring` | Processo público/ativo, actor/office/role revalidados no banco, auditoria atômica; nenhum seed ativo | Implemented/Tested |
| Scheduler | `monitoring_configuration`, `monitoring_schedule`, `phase9_scheduler_tick` | Tick UTC controlado, timezone IANA, janela `08:00/13:00/18:00` em fixtures e chave idempotente | Implemented/Tested |
| Fila e claim | `query_job`, `phase9_claim_query_job`, leases | `FOR UPDATE SKIP LOCKED`, tentativa única por claim, lease expirável e token anti-stale | Implemented/Tested |
| Execução | `query_execution`, `phase9_complete_query_execution` | Uma linha por tentativa, revalidação de processo público/ativo e conclusão curta/transacional | Implemented/Tested |
| Snapshot | `process_snapshot` | Snapshot somente para observation, hash canônico, vínculo obrigatório a execution e triggers de imutabilidade | Implemented/Tested |
| Falhas e retry | worker/recovery e classificação SQL | 429/timeout/source unavailable retryáveis até três tentativas; `not_found`/`not_supported`/schema inválido terminais | Implemented/Tested |
| Auditoria sistêmica | `phase9_write_system_audit` | `actor_user_id=NULL`, origem allowlisted `system_scheduler`/`system_worker`, `worker_id` opaco, metadata allowlisted | Implemented/Tested |
| ManualProvider | registry existente | Sem fallback automático e sem `manual_provider_entry`; US-012/US-029 não ganham endpoint novo | Bloqueado/Deferred |

A suíte `12_phase_9_scheduler_queue_snapshots.test.sql` cobre 36 assertions de grants, RLS, ativação D-022, scheduler idempotente, claim, concorrência de lease, conclusão com exchange/payload/snapshot, recovery, stale worker e retry terminal. Comparação, `changed`, `unchanged`, notificações e produção permanecem fora da Fase 9.

## Fechamento factual da Fase 8

| Critério | Evidência | Resultado |
|---|---|---|
| Baseline correta | branch sandbox `phase-8-datajud-manual` baseada em `7cf007...` | atendido |
| Transporte sem chamada externa | fake transport injetável e modo real desabilitado | atendido |
| Processo sigiloso bloqueado antes da consulta | preflight server-only e `require_provider_process_eligible` DB-side | atendido |
| Resultado sem comparação | validator V1 e migration rejeitam `changed`/`unchanged` | atendido |
| Persistência segura | RLS, grants mínimos, RPC SECURITY DEFINER com `search_path` fixo, wrappers internas exclusivas de `service_role`, actor revalidado, hash, sanitização e append-only | atendido |
| ManualProvider | observação sintética preservada; entrada operacional não inventada | bloqueado por decisão D-022 pendente |
| Fases futuras | scheduler/fila/worker/snapshot na Fase 9 e comparação na Fase 10 | Fase 9 não iniciada; não antecipadas |
