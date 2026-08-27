# Relatório — Fase 11: Central de Falhas e Notificações

## Identificação

| Campo | Estado factual |
|---|---|
| Branch | `phase-11-failures-notifications` |
| Baseline Fase 10 | `ee687bb0fefdb5d6899b25f3753d5eac77ce3037` |
| Primeiro commit da Fase 11 | `259e6e58ea9177bda7232281b8951a1c6cf0c78c` |
| Corretivo | Em validação nesta execução; sem amend, rebase, squash ou force-push |
| Migration histórica | `20260827000003_phase_11_failures_notifications.sql` |
| Migration incremental | `20260827000004_phase_11_failures_notifications_hardening.sql` |

## IMPLEMENTADO

A Fase 11 implementa `failure_incident` como agregado por escritório e fingerprint, `failure_occurrence` como timeline append-only e `notification_outbox` como outbox interna/sintética. O domínio inclui prioridade operacional, responsável, notas append-only, recovery key, resolução restrita, reabertura, reprocessamento e idempotência. A tentativa é derivada da evidência de `query_execution` e `failure_occurrence.attempt_number`; `occurrence_count` conta somente `failure_observed`.

A central `/app/falhas` e o detalhe do incidente têm filtros server-side por tipo, processo, data, tentativa, prioridade, responsável e estado. O isolamento é por `office_id`. Ações e RPCs revalidam D-022 no banco: `lawyer`/`operator` tratam e reprocessam; `reviewer` lê; `auditor` não visualiza falhas operacionais; perfis e escritórios inativos não operam; `service_role` não é ator jurídico.

A outbox é restrita a `in_app` e `mock_email`, com `simulation_only = true`, sem SMTP, HTTP, webhook, destinatário real ou entrega externa. O provider permanece limitado a `observation` ou `failure`; `changed` e `unchanged` permanecem na comparação da Fase 10.

## CORRETIVO DE MIGRATIONS

A migration 00003 foi restaurada diretamente do primeiro commit publicado e deve permanecer byte a byte idêntica ao blob `27664c487a6757e8695bea28bf56f8f60ca338bb`. O SHA-256 factual do arquivo restaurado é `cb80b2c61f92c5c2b4ec3b0ea05963cbaf044d1b6f2758285b67fbf6362b722c`.

A migration 00004 concentra exclusivamente as quatro correções pós-publicação identificadas no delta real: parâmetros ausentes nos `RAISE` da trigger append-only; permissão explícita do recorder interno para `service_role`/`postgres`; idempotência antecipada do reprocessamento manual; e `GRANT EXECUTE` mínimo para o recorder interno destinado ao backend. Ela começa com `SET lock_timeout = '2s';`, não edita Fases 9/10 e não usa DDL destrutivo.

## TESTADO ANTERIORMENTE NA FASE 11

Antes deste corretivo, o HEAD funcional havia passado format, lint, typecheck, unitários, build, reset Supabase, DB lint, pgTAP, E2E, PoC, todos os testes de concorrência cumulativos, PowerShell e database types no App CI `33106422849`, com sucesso no SHA `5f4286628ade5ad6be48e009d11043bc0bd53056`. Esses resultados são evidência do estado funcional anterior; a validação do par 00003 original + 00004 será registrada após a nova regressão.

## PARCIAL

US-030 permanece parcial/deferida quanto a envio real. Esta fase fornece somente infraestrutura de outbox sintética interna. US-031 comprova somente deduplicação lógica sintética por chave idempotente e não comprova entrega real.

## DEFERIDO E LIMITES

Não foram usados SMTP, destinatário real, serviço externo real, DataJud real, processo real, CNJ real, credencial real, fornecedor pago, produção, piloto ou processo sigiloso. Não foi criada a ação `manual_provider_entry`. Scheduler, fila e worker não foram ampliados neste corretivo; a integração existente permanece limitada ao escopo aprovado. A Fase 12 não foi iniciada.

## Validação do corretivo

Os resultados do reset limpo com 00003 original + 00004, do upgrade sobre banco já aplicado na 00003 original, da regressão cumulativa e do novo App CI serão preenchidos somente com evidência observada após a execução. O gate de histórico da Fase 11 deve provar o blob e o SHA-256 da 00003, a exclusividade do hardening na 00004 e a preservação das migrations anteriores.
