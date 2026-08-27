# Relatório factual — Fase 10: Comparação e Detecção de Alterações

## 1. Escopo e baseline

A Fase 10 foi implementada na branch `phase-10-comparison-detection`, criada exatamente sobre o HEAD final publicado da Fase 9, `8441f7328ec4988a5cd14166b691a9cfd1de5931`, cujo parent imediato é `3517e6f059a50113d31b0ce9a4f7c3be2ee6d726`. `main` não foi alterada. A execução usa somente fixtures sintéticas e Supabase local/Docker; não houve DataJud real, CNJ ou processo real, credencial real, endpoint externo, provider pago, processo sigiloso, produção ou piloto.

O provider continua retornando exclusivamente `observation` ou `failure`. `changed`, `unchanged` e `not_comparable` existem somente na camada comparadora. Não foram iniciadas a Fase 11, notificações, failure center de UI, relatórios, PDF, materialidade jurídica ou ampliação operacional do `ManualProvider`.

## 2. Implementação entregue e correção incremental

O núcleo determinístico está em `src/lib/comparison/comparator.ts`. Ele usa a versão interna allowlisted `comparison-v1`, canonicalização de objetos e coleções, normalização Unicode/data, limites de tamanho e profundidade, identidade estável para movimentos e parties, diff técnico bounded e hash SHA-256 estável. Snapshot inválido, incompleto, de source/provider incompatível ou sem baseline produz resultado não comparável; failure de provider não chega ao comparador e nunca vira `unchanged`.

A integração backend-only está em `src/lib/comparison/persistence.ts`, `src/lib/monitoring/worker.ts` e `src/lib/monitoring/server.ts`. O worker chama a comparação somente depois de a completion da Fase 9 retornar um `snapshot_id`. A comparação não altera scheduler, fila, claim, lease, retry ou completion. Falha técnica na persistência comparativa é isolada e sanitizada; o snapshot já concluído permanece íntegro e pode ser reprocessado internamente pelo ID.

A migration `supabase/migrations/20260827000001_phase_10_comparison_detection.sql` cria `process_comparison` como fonte única, completa e append-only do resultado. `detected_change` é mínimo, só referencia uma comparação `changed` e não duplica `changed_fields` ou `normalized_diff`. A migration também cria constraints, índices, triggers de imutabilidade, RPCs internas, auditoria allowlisted, RLS e grants mínimos. A primeira instrução é `SET lock_timeout = '2s';`; não há edição das migrations publicadas da Fase 9 nem DDL destrutivo.

Durante a revisão end-to-end foi corrigida uma incompatibilidade real: a RPC persistia `changed_fields` e `normalized_diff`, mas não os devolvia, enquanto o wrapper server-only exigia esses campos. O contrato SQL agora retorna os dois valores persistidos; os tipos Supabase foram regenerados; `persistedRow()` continua validando a resposta; o teste unitário `src/lib/comparison/persistence.test.ts` usa a resposta RPC realista; e o parser da concorrência foi ajustado para a nova posição da coluna `replayed`. Não há duplicação do diff em `detected_change`.

## 3. PostgreSQL, segurança e auditoria

`phase10_compare_process_snapshot` e `phase10_get_snapshot_pair_internal` são `SECURITY DEFINER` com `search_path = pg_catalog, public`. `PUBLIC`, `anon` e `authenticated` não possuem `EXECUTE`; somente o backend `service_role` possui o execute mínimo. Não há DML direto concedido ao `service_role` nas tabelas comparativas. As tabelas possuem RLS e leitura same-office pela policy operacional existente; `UPDATE` e `DELETE` físicos são bloqueados por trigger.

A RPC deriva o processo e o tenant a partir do snapshot corrente, trava brevemente a linha do processo, valida execution/exchange/provenance, exige `processRef` coerente, revalida o hash e rejeita dados comparativos ou chaves sensíveis no snapshot. A versão comparativa é allowlisted no código e no banco; valores desconhecidos são rejeitados antes da persistência. `detected_change` é protegido por FK composta, unicidade por comparação e trigger que exige `result = changed`.

A RPC valida a forma, os limites, os tipos de mudança, a ausência de chaves sensíveis e a correspondência ordenada entre `changed_fields` e os paths de `normalized_diff`. A semântica do diff é calculada unicamente pelo comparador TypeScript server-only; o banco funciona como fronteira de persistência, coerência, tenant, proveniência e segurança. Nenhum caminho de browser pode invocar a RPC.

A auditoria `phase10_write_system_audit` é fechada, `SECURITY DEFINER`, sem execução pública, com eventos e metadata allowlisted, `actor_user_id = NULL`, origem fixa `system_comparator` e correlation ID derivado da execução. A comparação, a mudança detectada e a auditoria são persistidas na mesma transação; falha de auditoria provoca rollback integral.

## 4. Testes e validações executadas

| Gate | Resultado factual |
|---|---|
| Format check | Passou; todos os arquivos estão no padrão Prettier |
| ESLint | Passou |
| Typecheck | Passou após sincronização dos tipos gerados pelo banco |
| Unitários | 115 testes em 21 arquivos, todos passaram; inclui o novo teste de persistência e 8 testes do comparador |
| Build Next.js | Passou |
| Reset PostgreSQL | Passou em banco limpo; migrations 00011, 00012 e 00001 aplicadas sequencialmente |
| `supabase db lint` | Passou sem erros de schema |
| pgTAP cumulativo | Passou após reset limpo, incluindo a suíte da Fase 10 |
| pgTAP específico da Fase 10 | Passou com 31 assertions, incluindo o retorno dos dois campos persistidos |
| Concorrência real da Fase 10 | Passou com duas comparações concorrentes, duas linhas de comparação, um replay, uma mudança detectada, zero colunas duplicadas de diff e rejeição de versão desconhecida |
| Concorrência real da Fase 9 | Passou com histórico imutável, um vencedor de claim, um snapshot/exchange concorrente e stale lease rejeitado |
| Last-owner, rate limit, Fase 5 e Fase 6 | Passaram no clone Windows/Docker; os scripts PowerShell foram executados com `powershell.exe` |
| Auth E2E | 25 testes passaram |
| PoC sintética | 29 testes passaram; sem endpoint real |
| Database types | Geração oficial do CLI comparada byte a byte com `src/types/database.types.ts` |
| Segurança e higiene | `git diff --check`, hygiene, varredura textual de segredo e `npm audit --audit-level=high --omit=dev` passaram; auditoria retornou 0 vulnerabilidades |

A saída de concorrência observada inclui `concurrent_comparison_results=2`, `concurrent_replays=1`, `process_comparisons=2`, `detected_changes=1`, `detected_change_diff_columns=0` e `unknown_version_rejected=1`. A mensagem de rejeição da versão desconhecida é esperada pelo teste negativo e não representa falha do gate.

## 5. Publicação, rollback e limites

A correção foi preparada como commit incremental normal sobre o commit publicado da Fase 10, sem amend, rebase, squash ou force-push. A confirmação final deve considerar somente o SHA exato publicado, seu parent imediato, a referência remota da branch, o resultado do App CI e a confirmação de que `main` permaneceu intacta.

O rollback é operacional e não destrutivo: a chamada comparativa pode ser removida por commit reversível ou desabilitação server-only, preservando snapshots e evidências em `process_comparison` e `detected_change`. Não há rollback por `DROP TABLE`, `DROP COLUMN` ou edição de migration publicada. O código anterior da Fase 9 continua compatível com as novas tabelas existentes.

A execução deve parar se surgir necessidade de provider real, processo sigiloso automático, segredo, grant amplo, DDL destrutivo, alteração de `main`, auditoria fora da transação, raw payload no diff, conversão de failure em `unchanged`, duplicação concorrente, vulnerabilidade High/Critical ou CI diferente do SHA publicado.

## 6. Confirmação de escopo

A Fase 10 termina na comparação determinística, persistência auditável e detecção mínima de alterações. A Fase 11 não foi iniciada. Nenhum scheduler, fila, worker novo, notificação, relatório, PDF, IA, materialidade jurídica, fuzzy matching ou chamada externa foi antecipado além do escopo já aprovado das fases anteriores.

## Referências

[1]: `01-requisitos-do-produto.md` — Requisitos canônicos do produto.
[2]: `10-matriz-papeis-e-autorizacao.md` — Matriz normativa D-022.
[3]: `09-definicao-de-pronto.md` — Definição canônica de pronto.
[4]: `plano-fase-10.md` — Plano factual executado da Fase 10.
[5]: `../supabase/migrations/20260827000001_phase_10_comparison_detection.sql` — Migration comparativa aditiva.
[6]: `../supabase/tests/database/13_phase_10_comparison_detection.test.sql` — Suíte pgTAP específica.
[7]: `../supabase/tests/concurrency/test_phase10_comparison.sh` — Teste real de concorrência PostgreSQL.
[8]: `../src/lib/comparison/persistence.test.ts` — Teste unitário do contrato RPC-wrapper.
