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
| O-001 | RF-004 | US-011 | `legal_process.monitoring_status` | Monitoramento | 6 | T-011 activation | Estado estrutural `paused`, UI transparente, sem provider/scheduler/job | Partial/Deferred |
| O-001 | RF-006 | US-012 | `query_job` | Queue/API | 9 | T-012 manual query | Job idempotente | Planned |
| O-001 | RF-006 | US-013 | `monitoring_schedule`, `query_job` | Scheduler | 9 | T-013 schedule | Relógio controlado | Planned |
| O-002 | RF-006 | US-014 | `provider`, `query_execution` | DataJudProvider | 1,7–8 | T-014 contract | Fixture/PoC | Planned |
| O-002 | RF-006 | US-015 | `provider`, `query_execution` | ManualProvider | 7–8 | T-015 manual provider | Registro de fonte | Planned |
| O-002 | RF-007 | US-016 | `raw_provider_payload` | Storage | 8–9 | T-016 raw payload | Hash/sanitização | Planned |
| O-002 | RF-007 | US-017 | `process_snapshot` | Normalizador | 7–10 | T-017 normalize | Fixtures | Planned |
| O-002 | RF-007 | US-018 | `process_snapshot` | Snapshot | 9 | T-018 snapshot | Hash estável | Planned |
| O-002 | RF-007 | US-019 | `process_snapshot` | Comparador | 10 | T-019 baseline | Resultado esperado | Planned |
| O-003 | RF-008 | US-020 | `process_movement` | Deduplicação | 10 | T-020 dedupe movement | Constraint/hash | Planned |
| O-002 | RF-008 | US-021 | `detected_change` | Comparador | 10 | T-021 change | Fingerprint | Planned |
| O-003 | RF-008 | US-022 | `query_execution` | Comparador/UI | 10 | T-022 unchanged | Estado exibido | Planned |
| O-003 | RF-009 | US-023 | `query_execution` | Failure center | 9,11 | T-023 source unavailable | Estado e ação | Planned |
| O-003 | RF-009 | US-024 | `query_execution`, `query_job` | Worker | 9,11 | T-024 timeout | Lock liberado | Planned |
| O-003 | RF-009 | US-025 | `query_job` | Retry | 9,11 | T-025 rate limit | Backoff | Planned |
| O-003 | RF-009 | US-026 | `query_execution` | Failure center | 8,11 | T-026 not found | Relatório | Planned |
| O-003 | RF-009 | US-027 | `provider_capability` | Provider | 7,11 | T-027 unsupported | Sem consulta | Planned |
| O-003 | RF-009 | US-028 | `query_execution` | Failure center | 11 | T-028 failure center | Filtros | Planned |
| O-003 | RF-009 | US-029 | `query_job` | Queue/API | 9,11 | T-029 reprocess | Auditoria | Planned |
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

## Evidências Esperadas

As evidências incluem testes unitários, testes E2E, fixtures, resultados de sandbox, logs sanitizados, hashes, registros de auditoria, testes RLS, fichas por processo da PoC, relatórios de backup/restauração e revisão manual do advogado. Nenhuma evidência poderá incluir segredo ou processo não autorizado.
