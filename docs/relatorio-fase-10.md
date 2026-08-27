# Relatório factual — Corretivo da Fase 10: Comparação e Detecção de Alterações

## 1. Escopo e baseline

Foi executado um corretivo localizado da Fase 10 na branch `phase-10-comparison-detection`, partindo do HEAD `82b0fb46577e3cf65f92a5fb2dfa8c333d83d3bc`. A baseline original da Fase 10 é o commit `7527d6a9e77b4583d779b8197bbc1fe5eac5d78a`; a baseline da Fase 9 permanece `8441f7328ec4988a5cd14166b691a9cfd1de5931`, com parent `3517e6f059a50113d31b0ce9a4f7c3be2ee6d726`. `main` não foi alterada.

A execução usou exclusivamente fixtures sintéticas e Supabase local/Docker. Não houve DataJud real, CNJ ou processo real, credencial real, endpoint externo, provider pago, processo sigiloso, produção ou piloto. O provider continua limitado a `observation` ou `failure`; `changed`, `unchanged` e `not_comparable` permanecem exclusivamente na camada comparadora. A Fase 11 não foi iniciada.

## 2. Correções entregues

A migration `supabase/migrations/20260827000001_phase_10_comparison_detection.sql` foi restaurada diretamente pelo Git ao conteúdo do commit publicado `7527d6a9e77b4583d779b8197bbc1fe5eac5d78a`. A prova `git diff --exit-code 7527d6a9e77b4583d779b8197bbc1fe5eac5d78a -- supabase/migrations/20260827000001_phase_10_comparison_detection.sql` não produziu diferenças. O SHA-256 do arquivo restaurado é `142746e23cf05671b01ac38622880bd47d0e6d5e9cd25de99ecbbe2d1f253b54`.

As correções posteriores foram isoladas em `supabase/migrations/20260827000002_phase_10_comparison_hardening.sql`, cuja primeira instrução é literalmente `SET lock_timeout = '2s';`. A migration incremental adiciona o resolvedor `phase10_resolve_compatible_previous_snapshot`, o leitor `phase10_get_snapshot_pair_compatible_internal` e a RPC `phase10_compare_process_snapshot_v2`, que retorna os valores persistidos `changed_fields` e `normalized_diff`. O caminho legado permanece preservado no banco para rollback, mas não possui mais execução para `service_role`, impedindo que o wrapper utilize a seleção histórica antiga.

O wrapper server-only em `src/lib/comparison/persistence.ts` agora usa somente o leitor compatível e a RPC v2. `process_comparison` continua sendo a única fonte de `changed_fields` e `normalized_diff`; `detected_change` continua mínimo, limitado a comparações `changed` e sem duplicar o diff. O arquivo `src/types/database.types.ts` foi alinhado às assinaturas geradas localmente.

O resolvedor escolhe deterministicamente o snapshot histórico válido imediatamente anterior mais recente que seja do mesmo `office_id` e `process_id`, tenha o mesmo `provider_id`, `source` e `normalizer_version`, esteja ligado a uma execution `succeeded` e a uma exchange `observation`, tenha `processRef` coerente, estrutura completa, hash íntegro e não contenha chaves comparativas ou sensíveis. Snapshots futuros, de outro office/processo, de outro provider/source, com normalizer incompatível, execution inadequada, exchange incompatível, estrutura incompleta ou hash inválido são ignorados.

## 3. Cenário A → B incompatível → C

Foi criado `supabase/tests/database/14_phase_10_compatible_baseline.test.sql` com fixtures sintéticas explícitas. `A` é compatível; `B` é posterior, mas tem normalizer incompatível; `D` usa exchange de outro provider/source; `E` tem hash inválido; `F` pertence a outro office/processo; e `C` é o snapshot atual compatível. O resultado comprovado é que **C compara com A**, não com B, e não retorna `not_comparable` apenas porque B está entre os snapshots.

O mesmo teste comprova que, quando não existe baseline compatível anterior, o resolvedor retorna `NULL`; esse caso não pode ser convertido em `unchanged`. Também são cobertos o isolamento por office/processo, a ausência de `detected_change` para `unchanged` e a dupla de snapshots devolvida pelo leitor compatível.

## 4. PostgreSQL, segurança e auditoria

As funções incrementais são `SECURITY DEFINER` com `search_path = pg_catalog, public`. `PUBLIC`, `anon` e `authenticated` não possuem `EXECUTE`; somente o backend `service_role` executa as funções internas necessárias. Os caminhos legados não são executáveis pelo backend após a migration 00002. Não há DML direto concedido ao `service_role` nas tabelas comparativas.

A RPC continua derivando tenant e processo do snapshot corrente, aplicando lock curto no processo, validando execution/exchange/provenance, coerência de `processRef`, integridade do hash, estrutura, ausência de chaves sensíveis e relação entre `changed_fields` e os paths do diff. A semântica do diff continua calculada unicamente pelo comparador TypeScript server-only. Nenhum caminho browser pode invocar o contrato comparativo.

A auditoria `phase10_write_system_audit` permanece fechada, allowlisted, append-only e transacional. Comparação, mudança detectada e auditoria são persistidas na mesma transação; falha de auditoria provoca rollback integral. Não foram realizadas operações destrutivas nem alterações nas migrations `00011` e `00012` da Fase 9.

## 5. Upgrade e reset

O caminho de banco novo foi validado com `supabase db reset --yes`, aplicando em sequência Fase 9 → `20260827000001_phase_10_comparison_detection.sql` original → `20260827000002_phase_10_comparison_hardening.sql`. O reset terminou com sucesso e o pgTAP cumulativo passou.

O caminho de upgrade foi validado removendo temporariamente a 00002 do diretório de migrations, executando o reset para obter o schema após a 00001 original e aplicando somente o conteúdo da 00002 via PostgreSQL. As funções `phase10_compare_process_snapshot_v2` e `phase10_resolve_compatible_previous_snapshot` foram encontradas no banco; o teste A-B-C passou; e a evidência foi encerrada restaurando o arquivo da 00002 no clone temporário, sem deixar backup ou script transitório.

## 6. Testes e validações

| Gate | Resultado factual |
|---|---|
| Integridade histórica da 00001 | Passou; byte a byte idêntica ao commit `7527d6a9` |
| Migration incremental 00002 | Passou; começa com `SET lock_timeout = '2s';` e contém exclusivamente o hardening posterior |
| Format, ESLint, typecheck e unitários | Passaram; 115 testes em 21 arquivos |
| Build Next.js/Auth E2E | Passou; 25 testes Auth E2E |
| `supabase db reset --yes` | Passou em banco novo com 00001 + 00002 |
| `supabase db lint` | Passou sem erros de schema |
| pgTAP Fase 10 | 33 assertions do contrato comparativo + 10 assertions do cenário A-B-C passaram em execuções limpas |
| pgTAP cumulativo | Passou após reset limpo, com os arquivos 13 e 14 independentes da ordem e das fixtures de outras fases |
| Upgrade 00001 → 00002 | Passou; banco já no estado da 00001 recebeu somente a 00002 e executou o teste A-B-C |
| Concorrência Fase 10 | Passou: 2 resultados, 1 replay, 2 comparações, 1 mudança detectada, 0 colunas duplicadas de diff e versão desconhecida rejeitada |
| Concorrência Fase 9 | Passou: claim exclusivo, completion sem duplicação, stale lease rejeitado e histórico de migrations íntegro |
| Last-owner, rate limit, Fase 5 e Fase 6 | Passaram no clone Windows/Docker |
| PoC sintética | 29 testes passaram; sem endpoint real |
| Database types | Comparação com geração oficial formatada passou no clone Windows |
| Higiene e dependências | `git diff --check`, hygiene, secret scan e `npm audit --audit-level=high --omit=dev` passaram; 0 vulnerabilidades reportadas |

A rejeição de `comparison version` observada na concorrência é o caso negativo esperado (`unknown_version_rejected=1`), não uma falha. Mensagens de transição inválida, proteção do último proprietário e rejeição de rate limit também pertencem aos testes negativos esperados.

## 7. Publicação e CI

O corretivo será publicado como um único commit incremental normal sobre `82b0fb46577e3cf65f92a5fb2dfa8c333d83d3bc`, sem amend, rebase, squash ou force-push, exclusivamente em `phase-10-comparison-detection`. O App CI do SHA final deverá confirmar o gate `Phase 10 Migration History`, pgTAP, concorrência real e todos os gates anteriores.

O rollback permanece operacional e não destrutivo: retirar a chamada comparativa por commit reversível ou desabilitação server-only, preservando snapshots e evidências. Não há rollback por `DROP TABLE`, `DROP COLUMN` ou edição de migration publicada.

## 8. Critérios de parada e confirmação de escopo

A execução deve parar diante de qualquer necessidade de provider real, processo sigiloso automático, segredo, grant amplo, DDL destrutivo, alteração de `main`, auditoria fora da transação, raw payload no diff, conversão de failure em `unchanged`, duplicação concorrente, vulnerabilidade High/Critical ou CI diferente do SHA publicado.

Este corretivo permanece limitado à Fase 10: migration histórica imutável, hardening incremental, seleção de baseline compatível, persistência auditável e detecção mínima de alteração. **A Fase 11 não foi iniciada.**

## Referências

[1]: `01-requisitos-do-produto.md` — Requisitos canônicos do produto.
[2]: `10-matriz-papeis-e-autorizacao.md` — Matriz normativa D-022.
[3]: `09-definicao-de-pronto.md` — Definição canônica de pronto.
[4]: `plano-fase-10.md` — Plano factual atualizado do corretivo.
[5]: `../supabase/migrations/20260827000001_phase_10_comparison_detection.sql` — Migration original restaurada.
[6]: `../supabase/migrations/20260827000002_phase_10_comparison_hardening.sql` — Migration incremental de hardening.
[7]: `../supabase/tests/database/13_phase_10_comparison_detection.test.sql` — PgTAP do contrato comparativo.
[8]: `../supabase/tests/database/14_phase_10_compatible_baseline.test.sql` — PgTAP do cenário A-B-C.
[9]: `../supabase/tests/concurrency/test_phase10_comparison.sh` — Teste real de concorrência PostgreSQL.
[10]: `../src/lib/comparison/persistence.test.ts` — Teste unitário do contrato RPC-wrapper.
