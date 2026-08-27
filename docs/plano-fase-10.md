# Plano técnico — Fase 10: Comparação e Detecção de Alterações

## Estado e baseline

A Fase 10 está sendo executada na branch `phase-10-comparison-detection`, criada exatamente sobre o HEAD final publicado da Fase 9, `8441f7328ec4988a5cd14166b691a9cfd1de5931`, cujo parent imediato é `3517e6f059a50113d31b0ce9a4f7c3be2ee6d726`. `main` permanece fora da execução e não será alterada. A implementação usa somente fixtures sintéticas em Supabase local/Docker; não usa DataJud real, CNJ ou processo real, credencial real, endpoint externo, provider pago, processo sigiloso, produção ou piloto.

O provider permanece limitado a `observation` ou `failure`. Os estados `changed`, `unchanged` e `not_comparable` pertencem exclusivamente à nova camada comparadora. A Fase 11, notificações, central de falhas, relatórios, PDF, materialidade jurídica, override humano e ampliação operacional do `ManualProvider` estão fora do escopo.

## Decisões arquiteturais fechadas

A comparação é uma camada separada em `src/lib/comparison/`, com canonicalização e diff determinísticos. O comparador recebe snapshots normalizados validados e não recebe raw payload. A versão ativa é `comparison-v1`, definida por constante interna e allowlist equivalente no banco; não é configuração do browser nem valor livre do chamador. Uma versão futura exigirá código, migration, testes e documentação próprios, sem reinterpretar registros V1.

`process_comparison` é a fonte única e imutável do resultado completo, incluindo a dupla de snapshots, versão, resultado, razão, `changed_fields`, `normalized_diff`, hash e timestamp. `detected_change` existe somente para resultado `changed` e guarda referência e metadados mínimos, sem duplicar snapshots, campos ou diff. Não são criados campos de severidade, materialidade, prioridade, notificação ou decisão jurídica.

A comparação é chamada pelo worker somente depois de `phase9_complete_query_execution` retornar um `snapshot_id` válido. A integração é server-only, não cria rota browser e não modifica scheduler, fila, claim, lease, retry ou completion. Falha comparativa não transforma snapshot em `unchanged`; permanece erro técnico isolado e sanitizado para replay interno.

## Modelo determinístico

O snapshot corrente é selecionado pelo ID explícito. O anterior é o registro imediatamente anterior do mesmo `office_id` e `process_id`, ordenado por `created_at` e `id`, com execução bem-sucedida, exchange de observação e provenance compatível. A RPC revalida processo, tenant, execução, provider, source, `processRef`, integridade do JSON e hash do snapshot.

O primeiro snapshot produz `not_comparable` com razão `first_snapshot`, sem mudança detectada. Snapshots de normalizer ou source incompatíveis, incompletos ou inválidos produzem `not_comparable` com razão allowlisted. Falhas de provider não geram snapshot e nunca são convertidas em `unchanged`.

A canonicalização ordena chaves de objetos, normaliza texto para NFC, remove whitespace externo, normaliza datas conhecidas para UTC e impõe limites de profundidade, nós, entradas e bytes. Parties são comparadas por `partyRef`; movimentos, por `movementRef`, preservando multiplicidade e sem fuzzy matching. Raw payload, headers, tokens, credenciais e mensagens de transporte nunca entram no diff. A distinção entre ausência, `null`, vazio e valor conhecido é preservada; incompletude não vira ausência de mudança.

O `comparison_hash` é SHA-256 do JSON canônico composto por versão, IDs, resultado, razão, campos alterados e diff. A unicidade é `(office_id, process_id, current_snapshot_id, comparison_version)`. O replay da mesma dupla e versão retorna o registro existente sem duplicar comparação, auditoria ou mudança. Um lock curto sobre o processo, constraints e `ON CONFLICT` protegem a execução concorrente.

## Persistência, segurança e auditoria

A migration `20260827000001_phase_10_comparison_detection.sql` é aditiva e inicia com `SET lock_timeout = '2s';`. Ela cria as tabelas, constraints, índices, triggers append-only, funções internas, RPC comparadora, policies e grants. Não edita migrations publicadas das fases anteriores e não usa DDL destrutivo.

A RPC `phase10_compare_process_snapshot` e a leitura interna do par de snapshots são `SECURITY DEFINER` com `search_path = pg_catalog, public`. A RPC comparadora não recebe `office_id`, actor, role ou `is_owner` como autoridade. `PUBLIC`, `anon` e `authenticated` não têm `EXECUTE`; somente o backend `service_role` recebe o execute mínimo da RPC e do leitor interno. Não há DML direto concedido ao `service_role` nas tabelas comparativas.

As tabelas possuem RLS habilitada, leitura same-office pela policy operacional existente e nenhum DML público. Triggers negam `UPDATE` e `DELETE` físicos. `detected_change` possui FK composta para a comparação correta e trigger que só permite referência a uma comparação `changed`. A auditoria `phase10_write_system_audit` é interna, allowlisted, usa `actor_user_id = NULL`, origem fixa `system_comparator`, correlation ID derivado da execução e metadata sem raw payload. A inserção da comparação, mudança e auditoria ocorre na mesma transação; falha de auditoria causa rollback integral.

## Implementação e testes

Os arquivos principais são `src/lib/comparison/comparator.ts`, `src/lib/comparison/persistence.ts`, a integração no worker server-only, a migration da Fase 10, `13_phase_10_comparison_detection.test.sql` e `test_phase10_comparison.sh`. Os testes cobrem estados, canonicalização, Unicode/whitespace, identidade de movimentos e parties, incompletude, versionamento, hash, idempotência, RLS/grants, tenant, provenance, fonte única do diff, detected change mínimo e rollback transacional da auditoria.

O teste real PostgreSQL usa duas conexões independentes e fixtures sintéticas. Ele comprova duas chamadas concorrentes para a mesma comparação, uma única comparação, um replay, uma única mudança detectada, ausência de colunas de diff duplicadas e rejeição de versão não allowlisted. A suíte específica e a suíte pgTAP cumulativa devem ser executadas após `supabase db reset --yes`; o App CI Linux executará também as concorrências cumulativas das fases anteriores.

## Regressão, rollback e critérios de parada

A regressão repete `npm ci`, format, lint, typecheck, unitários, build, reset, db lint, pgTAP específico e cumulativo, Auth E2E, PoC sintética, concorrências anteriores e da Fase 10, database types, hygiene, secret scan, `git diff --check`, Docker smoke e `npm audit` em nível High. O workflow App CI inclui a branch `phase-10-comparison-detection` e o teste concorrente novo sem remover ou relaxar gates.

O rollback é operacional e não destrutivo: retirar a chamada do comparador por commit reversível ou desabilitação server-only, preservando snapshots e evidências comparativas. Não há rollback por `DROP TABLE`, `DROP COLUMN` ou alteração de migration publicada. A execução deve parar diante de DataJud real, processo sigiloso, segredo, grant amplo, DDL destrutivo, alteração de `main`, falha de auditoria fora da transação, raw payload no diff, conversão de failure em `unchanged`, duplicação concorrente, vulnerabilidade High/Critical ou CI diferente do SHA publicado.

## Critérios de aceite

A fase será considerada pronta quando a branch e baseline forem confirmadas, o provider continuar sem estados comparativos, snapshots válidos forem comparados de forma determinística, o primeiro snapshot não gerar mudança, iguais gerarem `unchanged`, diferentes gerarem `changed` com diff e fingerprint estáveis, incompatibilidades gerarem `not_comparable`, falhas não gerarem snapshot, replay e concorrência forem idempotentes, RLS/grants impedirem acesso indevido, a auditoria for atômica, os tipos refletirem as migrations, a regressão cumulativa passar e o App CI do SHA exato terminar verde.

A Fase 11 não será iniciada ao concluir este trabalho.
