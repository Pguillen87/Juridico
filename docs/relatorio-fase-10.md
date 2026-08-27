# Relatório factual — Fase 10: Comparação e Detecção de Alterações

## 1. Escopo e baseline

A Fase 10 foi implementada na branch `phase-10-comparison-detection`, criada exatamente sobre o HEAD final publicado da Fase 9, `8441f7328ec4988a5cd14166b691a9cfd1de5931`, cujo parent imediato é `3517e6f059a50113d31b0ce9a4f7c3be2ee6d726`. `main` não foi alterada. A execução usa somente fixtures sintéticas e Supabase local/Docker; não houve DataJud real, CNJ ou processo real, credencial real, endpoint externo, provider pago, processo sigiloso, produção ou piloto.

O provider continua retornando exclusivamente `observation` ou `failure`. `changed`, `unchanged` e `not_comparable` foram implementados somente na camada comparadora. Não foram iniciadas a Fase 11, notificações, failure center de UI, relatórios, PDF, materialidade jurídica ou ampliação operacional do `ManualProvider`.

## 2. Implementação entregue

O núcleo determinístico está em `src/lib/comparison/comparator.ts`. Ele usa a versão interna allowlisted `comparison-v1`, canonicalização de objetos e coleções, normalização Unicode/data, limites de tamanho e profundidade, identidade estável para movimentos e parties, diff técnico bounded e hash SHA-256 estável. Snapshot inválido, incompleto, de source/provider incompatível ou sem baseline produz resultado não comparável; failure de provider não chega ao comparador e nunca vira `unchanged`.

A integração backend-only está em `src/lib/comparison/persistence.ts`, `src/lib/monitoring/worker.ts` e `src/lib/monitoring/server.ts`. O worker chama a comparação somente depois de a completion da Fase 9 retornar um `snapshot_id`. A comparação não altera scheduler, fila, claim, lease, retry ou completion. Falha técnica na persistência comparativa é isolada e sanitizada; o snapshot já concluído permanece íntegro e pode ser reprocessado internamente pelo ID.

A migration `supabase/migrations/20260827000001_phase_10_comparison_detection.sql` cria `process_comparison` como fonte única, completa e append-only do resultado. `detected_change` é mínimo, só referencia uma comparação `changed` e não duplica `changed_fields` ou `normalized_diff`. A migration também cria constraints, índices, triggers de imutabilidade, RPCs internas, auditoria allowlisted, RLS e grants mínimos. A primeira instrução é `SET lock_timeout = '2s';`; não há edição das migrations publicadas da Fase 9 nem DDL destrutivo.

## 3. PostgreSQL, segurança e auditoria

`phase10_compare_process_snapshot` e `phase10_get_snapshot_pair_internal` são `SECURITY DEFINER` com `search_path = pg_catalog, public`. `PUBLIC`, `anon` e `authenticated` não possuem `EXECUTE`; somente o backend `service_role` possui o execute mínimo. Não há DML direto concedido ao `service_role` nas tabelas comparativas. As tabelas possuem RLS e leitura same-office pela policy operacional existente; `UPDATE` e `DELETE` físicos são bloqueados por trigger.

A RPC deriva o processo e o tenant a partir do snapshot corrente, trava brevemente a linha do processo, valida execution/exchange/provenance, exige `processRef` coerente, revalida o hash e rejeita dados comparativos ou chaves sensíveis no snapshot. A versão comparativa é allowlisted no código e no banco; valores desconhecidos são rejeitados antes da persistência. `detected_change` é protegido por FK composta, unicidade por comparação e trigger que exige `result = changed`.

A auditoria `phase10_write_system_audit` é fechada, `SECURITY DEFINER`, sem execução pública, com eventos e metadata allowlisted, `actor_user_id = NULL`, origem fixa `system_comparator` e correlation ID derivado da execução. A comparação, a mudança detectada e a auditoria são persistidas na mesma transação; falha de auditoria provoca rollback integral.

## 4. Testes e validações executadas

| Gate | Resultado factual |
|---|---|
| Format check | Passou; todos os arquivos estão no padrão Prettier |
| ESLint | Passou |
| Typecheck | Passou após sincronização dos tipos gerados pelo banco |
| Unitários | 114 testes em 20 arquivos, todos passaram; inclui 8 testes do comparador |
| Build Next.js | Passou |
| Reset PostgreSQL | Passou em banco limpo; migrations 00011, 00012 e 00001 aplicadas sequencialmente |
| `supabase db lint` | Passou sem erros de schema |
| pgTAP cumulativo | Passou após reset limpo, incluindo a suíte da Fase 10 |
| pgTAP específico da Fase 10 | Passou com 29 assertions |
| Concorrência real da Fase 10 | Passou com duas comparações concorrentes, duas linhas de comparação, um replay, uma mudança detectada, zero colunas duplicadas de diff e rejeição de versão desconhecida |
| Auth E2E, PoC e concorrências anteriores | Executados na regressão do clone Docker; resultados devem permanecer anexados ao log final do gate cumulativo |
| Database types | Regenerados a partir do banco local e sincronizados ao arquivo versionado |
| Escopo e higiene | Sem provider comparativo, sem raw payload no diff, sem rota browser nova, sem DataJud real, sem Fase 11 |

A saída de concorrência esperada e observada inclui `concurrent_comparison_results=2`, `concurrent_replays=1`, `process_comparisons=2`, `detected_changes=1`, `detected_change_diff_columns=0` e `unknown_version_rejected=1`. A mensagem de rejeição da versão desconhecida é esperada pelo teste negativo e não representa falha do gate.

## 5. Rollback e limites

O rollback é operacional e não destrutivo: a chamada comparativa pode ser removida por commit reversível ou desabilitação server-only, preservando snapshots e evidências em `process_comparison` e `detected_change`. Não há rollback por `DROP TABLE`, `DROP COLUMN` ou edição de migration publicada. O código anterior da Fase 9 continua compatível com as novas tabelas existentes.

A execução deve parar se surgir necessidade de provider real, processo sigiloso automático, segredo, grant amplo, DDL destrutivo, alteração de `main`, auditoria fora da transação, raw payload no diff, conversão de failure em `unchanged`, duplicação concorrente, vulnerabilidade High/Critical ou CI diferente do SHA publicado.

## 6. Status de publicação

No momento deste relatório, a implementação está em validação final na branch `phase-10-comparison-detection`, ainda sobre a baseline `8441f7328ec4988a5cd14166b691a9cfd1de5931`. O commit incremental, o push e o App CI do SHA exato serão registrados somente depois da revisão final, do diff de escopo e da confirmação de que todos os arquivos corretos estão incluídos. A Fase 11 permanece não iniciada.

## Referências

[1]: `01-requisitos-do-produto.md` — Requisitos canônicos do produto.
[2]: `10-matriz-papeis-e-autorizacao.md` — Matriz normativa D-022.
[3]: `09-definicao-de-pronto.md` — Definição canônica de pronto.
[4]: `plano-fase-10.md` — Plano factual executado da Fase 10.
[5]: `../supabase/migrations/20260827000001_phase_10_comparison_detection.sql` — Migration comparativa aditiva.
[6]: `../supabase/tests/database/13_phase_10_comparison_detection.test.sql` — Suíte pgTAP específica.
[7]: `../supabase/tests/concurrency/test_phase10_comparison.sh` — Teste real de concorrência PostgreSQL.
