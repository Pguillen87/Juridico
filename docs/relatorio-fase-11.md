# Relatório — Fase 11: Central de Falhas e Notificações

## Identificação

| Campo | Estado factual |
|---|---|
| Branch | `phase-11-failures-notifications` |
| Baseline Fase 10 | `ee687bb0fefdb5d6899b25f3753d5eac77ce3037` |
| Primeiro commit da Fase 11 | `259e6e58ea9177bda7232281b8951a1c6cf0c78c` |
| Corretivo final | `a740b82e5ce7fe01c319a81dfcde11e9bcd16b45`; parent `490d4bd1d1a24445b422cc36cb5cc0f2de5982ea` |
| Migration 00003 histórica | `20260827000003_phase_11_failures_notifications.sql` — publicação defeituosa preservada como histórico |
| Migration 00003 canônica corrigida | blob `8d4d9cbcf030d288a5d91ff8262241de94a9bd8c`; SHA-256 `3c61a4215c084d452d70f58ee28a7837df076a5f7716de3ebe774b4bfb200775` |
| Migration 00004 publicada | blob `ad1f88ccc54c3a0e1be6a16480697fbb090365c6` |

## Commits incrementais

| Commit | Conteúdo |
|---|---|
| `5694bae` | Primeiro corretivo: gate histórico, migration 00004, upgrade, E2E, segurança e documentação iniciais. |
| `ee39a38` | Exceção única: correção somente dos dois `RAISE` da 00003. |
| `38d5a12` | Bit executável do gate de upgrade. |
| `e7fbad6` | Comparação estrutural de schema entre reset e upgrade. |
| `490d4bd` | Reset limpo após pgTAP do upgrade para preservar a regressão cumulativa. |
| `a740b82` | Fechamento documental factual da correção. |

## IMPLEMENTADO

A Fase 11 implementa `failure_incident` como agregado por escritório e fingerprint, `failure_occurrence` como timeline append-only e `notification_outbox` como outbox interna/sintética. O domínio inclui prioridade operacional, responsável, notas append-only, recovery key, resolução restrita, reabertura, reprocessamento e idempotência. A tentativa é derivada da evidência de `query_execution` e `failure_occurrence.attempt_number`; `occurrence_count` conta somente `failure_observed`.

A central `/app/falhas` e o detalhe do incidente têm filtros server-side por tipo, processo, data, tentativa, prioridade, responsável e estado. O isolamento é por `office_id`. Ações e RPCs revalidam D-022 no banco: `lawyer`/`operator` tratam e reprocessam; `reviewer` lê; `auditor` não visualiza falhas operacionais; perfis e escritórios inativos não operam; `service_role` não é ator jurídico.

A outbox é restrita a `in_app` e `mock_email`, com `simulation_only = true`, sem SMTP, HTTP, webhook, destinatário real ou entrega externa. O provider permanece limitado a `observation` ou `failure`; `changed` e `unchanged` permanecem na comparação da Fase 10.

## CORRETIVO DE MIGRATIONS

A primeira publicação da migration 00003 continha dois `RAISE EXCEPTION '%'` sem argumento correspondente e falhava com `SQLSTATE 42601: too few parameters specified for RAISE`; portanto, não constituía baseline válida para banco novo. O blob defeituoso original é `27664c487a6757e8695bea28bf56f8f60ca338bb` e seu SHA-256 era `cb80b2c61f92c5c2b4ec3b0ea05963cbaf044d1b6f2758285b67fbf6362b722c`.

Foi autorizada uma única exceção controlada à imutabilidade. Somente os dois `RAISE` receberam `TG_TABLE_NAME` como argumento, preservando `USING ERRCODE` e `HINT`; nenhuma alteração funcional posterior, grant, RLS ou RPC foi incorporada à 00003. O novo blob canônico é `8d4d9cbcf030d288a5d91ff8262241de94a9bd8c`, com SHA-256 `3c61a4215c084d452d70f58ee28a7837df076a5f7716de3ebe774b4bfb200775`; novas alterações da 00003 são proibidas.

A migration 00004 concentra exclusivamente as quatro correções pós-publicação identificadas no delta real: parâmetros ausentes nos `RAISE` da trigger append-only permanecem fora dela porque foram corrigidos na exceção autorizada; permissão explícita do recorder interno para `service_role`/`postgres`; idempotência antecipada do reprocessamento manual; e `GRANT EXECUTE` mínimo para o recorder interno destinado ao backend. Seu blob publicado é `ad1f88ccc54c3a0e1be6a16480697fbb090365c6`, ela começa com `SET lock_timeout = '2s';`, não edita Fases 9/10 e não usa DDL destrutivo.

## TESTADO ANTERIORMENTE NA FASE 11

Antes deste corretivo, o HEAD funcional havia passado format, lint, typecheck, unitários, build, reset Supabase, DB lint, pgTAP, E2E, PoC, todos os testes de concorrência cumulativos, PowerShell e database types no App CI `33106422849`, com sucesso no SHA `5f4286628ade5ad6be48e009d11043bc0bd53056`. O primeiro CI do corretivo (`33109869203`) falhou corretamente em `Start Supabase Local`, expondo o defeito sintático histórico da 00003. O cenário defeituoso `00003 original → 00004` foi retirado como critério de aceite; a regressão final usou Fase 10 → 00003 corrigida → 00004.

## PARCIAL

US-030 permanece parcial/deferida quanto a envio real. Esta fase fornece somente infraestrutura de outbox sintética interna. US-031 comprova somente deduplicação lógica sintética por chave idempotente e não comprova entrega real.

## DEFERIDO E LIMITES

Não foram usados SMTP, destinatário real, serviço externo real, DataJud real, processo real, CNJ real, credencial real, fornecedor pago, produção, piloto ou processo sigiloso. Não foi criada a ação `manual_provider_entry`. Scheduler, fila e worker não foram ampliados neste corretivo; a integração existente permanece limitada ao escopo aprovado. A Fase 12 não foi iniciada.

## Validação do corretivo

O reset completo com 00003 corrigida + 00004 passou. O upgrade válido a partir de schema da Fase 10, aplicando 00003 corrigida e depois somente 00004, passou; o script comparou fingerprints estruturais, funções, assinaturas, grants, RLS/policies, tabelas, constraints, triggers e tipos gerados. O pgTAP passou nos dois estados e o banco foi resetado novamente ao final para não contaminar a regressão cumulativa. O upgrade sobre a 00003 original defeituosa não foi executado nem alegado, pois a versão original não completa sua própria aplicação.

O App CI final `33122271713` concluiu `completed/success` com `headSha=a740b82e5ce7fe01c319a81dfcde11e9bcd16b45`. Passaram os gates de secret scan, auditoria de dependências, histórico F9/F10/F11, hygiene, formato, lint, typecheck, unitários, início do Supabase, reset, upgrade, E2E autenticado — incluindo `tests-e2e/failures.spec.ts` —, PoC sintética, DB lint, pgTAP, concorrência legada/F9/F10/F11, PowerShell e database types. A validação local também passou em parser SQL, `git diff --check`, formato, lint, typecheck, 126 unitários, build e `npm audit` sem vulnerabilidades.

O gate de histórico prova o blob canônico e o SHA-256 da 00003, o diff limitado aos dois argumentos `TG_TABLE_NAME`, a imutabilidade publicada da 00004 e a preservação das migrations anteriores.
