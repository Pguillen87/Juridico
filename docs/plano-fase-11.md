# Plano técnico — Fase 11: Central de Falhas e Notificações

## Baseline e escopo aprovado

A Fase 11 parte da baseline aprovada da Fase 10, `ee687bb0fefdb5d6899b25f3753d5eac77ce3037`, na branch dedicada `phase-11-failures-notifications`. O escopo é criar uma central interna de falhas, sua linha do tempo append-only, reprocessamento controlado e uma outbox somente interna/sintética. A fase não inicia a Fase 12 e não integra entrega externa.

A primeira publicação da migration 00003, no commit `259e6e58ea9177bda7232281b8951a1c6cf0c78c`, continha um erro sintático nos dois `RAISE` da trigger append-only e não era aplicável a banco novo. Foi autorizada uma única exceção controlada à imutabilidade: somente os dois comandos receberam `TG_TABLE_NAME` como argumento. O blob corrigido passa a ser a versão canônica e imutável da 00003; todo hardening posterior permanece exclusivamente na migration incremental 00004. Migrations anteriores das Fases 9 e 10 permanecem imutáveis.

## Modelo funcional

`failure_incident` representa o agregado mutável atual por escritório e fingerprint. `failure_occurrence` registra a linha do tempo append-only, incluindo observação de falha, reabertura, resolução, reprocessamento, atribuição e nota operacional. `occurrence_count` conta somente ocorrências `failure_observed`; não representa tentativas. Quando houver `query_execution`, a tentativa é derivada de `failure_occurrence.attempt_number` e da evidência existente. Falhas sem conceito de tentativa são exibidas como “não se aplica”, nunca como tentativa zero.

O fingerprint inclui somente contexto allowlisted de escritório, processo, provider, capability, etapa, classe, código e contexto permitido. A recovery key é distinta, exclui o código da falha e só permite recuperação de incidentes transitórios compatíveis no mesmo fluxo. Falhas de revisão manual, autorização, sigilo, `not_found` e `not_supported` não são auto-resolvidas.

## Operação, UI e D-022

A central `/app/falhas` oferece filtros server-side por tipo, processo, data, tentativa, prioridade, responsável e estado. A lista e o detalhe exibem a tentativa atual/última de forma compreensível e preservam o isolamento por `office_id`. O detalhe mostra timeline append-only, código sanitizado, prioridade, responsável e notas.

Ações operacionais usam Server Actions protegidas e RPCs que revalidam D-022 no banco. `lawyer` e `operator` podem visualizar e tratar falhas e solicitar reprocessamento; `reviewer` tem somente leitura; `auditor` não visualiza falhas operacionais; usuário ou escritório inativo não opera; `service_role` não representa ator jurídico; `is_owner` não concede bônus operacional. Não é criada autorização para `manual_provider_entry`.

## Persistência, auditoria e notificações

As mutações de domínio e seus registros de auditoria são atômicos na mesma transação PostgreSQL. O helper interno usa allowlist de eventos e metadados, deriva actor/office/role no banco e não aceita payload arbitrário do navegador. DML direto nas tabelas novas é negado; RLS e grants são mínimos e os RPCs `SECURITY DEFINER` usam `search_path` fixo.

A `notification_outbox` é backend-only, append-only, `simulation_only = true`, limitada a `in_app` e `mock_email`, com escopo interno de operadores do escritório. Não existe SMTP, HTTP, webhook, destinatário real, tela genérica de inbox ou mecanismo externo de entrega.

## Fronteiras preservadas

O provider continua produzindo somente `observation` ou `failure`. `changed`, `unchanged`, `not_comparable` e o diff pertencem à camada de comparação da Fase 10. Falha nunca vira `unchanged`, e evento `detected_change` só pode ser emitido após comparação válida com resultado `changed`. Scheduler, fila, worker, DataJud real, processo real, CNJ real, credencial real, produção, piloto e fornecedor pago não fazem parte da execução desta fase.

## Migration e rollback

A migration 00003 deve permanecer byte a byte igual ao novo blob corrigido, depois da exceção única documentada; novas alterações são proibidas. A migration 00004 começa literalmente com `SET lock_timeout = '2s';` e contém somente hardening incremental necessário, sem DDL destrutivo e sem alteração das migrations Fases 9 e 10. O rollback operacional preserva evidência: impede novas chamadas ao writer ou ao transporte sintético e usa migration reversa revisada apenas se necessária; não remove incidentes, ocorrências, auditorias ou histórico.

## Validação e critérios de aceite

A validação cobre o caminho de banco novo — migrations anteriores, 00003 corrigida e 00004 — e o upgrade tecnicamente válido a partir de um schema da Fase 10, aplicando a 00003 corrigida e depois somente a 00004. O cenário `00003 original defeituosa → 00004` é explicitamente impossível e não é critério de aceite, porque a versão original não completa sua própria aplicação. Os caminhos válidos são comparados por funções, assinaturas, grants, RLS/policies, tabelas/constraints, pgTAP e tipos gerados. A regressão cumulativa inclui histórico das Fases 9 e 10, gate byte a byte da Fase 11, formato, lint, typecheck, unitários, build, reset, DB lint, pgTAP, E2E, PoC sintética, concorrência, PowerShell, hygiene, secret scan, `git diff --check` e auditoria de dependências em nível alto.

O aceite exige o novo blob canônico da 00003 imutável, prova explícita da exceção limitada aos dois `RAISE`, hardening exclusivo na 00004, reset e upgrade válido aprovados, contrato funcional preservado, matriz de rastreabilidade atualizada, US-030 explicitamente parcial/deferida para envio real, US-031 limitado à deduplicação lógica sintética, nenhum envio externo e Fase 12 não iniciada.
