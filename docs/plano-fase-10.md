# Plano factual — Fase 10: Comparação e Detecção de Alterações

## Estado e baseline

A Fase 10 está sendo executada na branch `phase-10-comparison-detection`, criada exatamente sobre o HEAD final publicado da Fase 9, `8441f7328ec4988a5cd14166b691a9cfd1de5931`, cujo parent imediato é `3517e6f059a50113d31b0ce9a4f7c3be2ee6d726`. `main` permanece fora da execução e não será alterada. A implementação usa somente fixtures sintéticas em Supabase local/Docker; não usa DataJud real, CNJ ou processo real, credencial real, endpoint externo, provider pago, processo sigiloso, produção ou piloto.

O provider permanece limitado a `observation` ou `failure`. Os estados `changed`, `unchanged` e `not_comparable` pertencem exclusivamente à camada comparadora. A Fase 11, notificações, central de falhas, relatórios, PDF, materialidade jurídica, override humano e ampliação operacional do `ManualProvider` estão fora do escopo.

## Decisões arquiteturais fechadas

A comparação é uma camada separada em `src/lib/comparison/`, com canonicalização e diff determinísticos. O comparador recebe snapshots normalizados validados e não recebe raw payload. A versão ativa é `comparison-v1`, definida por constante interna e allowlist equivalente no banco; não é configuração do browser nem valor livre do chamador. Uma versão futura exigirá código, migration, testes e documentação próprios, sem reinterpretar registros V1.

`process_comparison` é a fonte única e imutável do resultado completo, incluindo a dupla de snapshots, versão, resultado, razão, `changed_fields`, `normalized_diff`, hash e timestamp. `detected_change` existe somente para resultado `changed` e guarda referência e metadados mínimos, sem duplicar snapshots, campos ou diff. Não são criados campos de severidade, materialidade, prioridade, notificação ou decisão jurídica.

A comparação é chamada pelo worker somente depois de `phase9_complete_query_execution` retornar um `snapshot_id` válido. A integração é server-only, não cria rota browser e não modifica scheduler, fila, claim, lease, retry ou completion. Falha comparativa não transforma snapshot em `unchanged`; permanece erro técnico isolado e sanitizado para replay interno.

## Modelo determinístico

O snapshot corrente é selecionado pelo ID explícito. O baseline anterior é resolvido pela função interna `phase10_resolve_compatible_previous_snapshot`: somente candidatos historicamente anteriores do mesmo `office_id` e `process_id`, com o mesmo provider, source e `normalizer_version`, execution `succeeded`, exchange `observation`, `processRef` coerente, estrutura completa, hash íntegro e ausência de chaves comparativas/sensíveis podem ser escolhidos. Entre os candidatos válidos, o mais recente por `(created_at, id)` é selecionado deterministicamente. O wrapper utiliza o leitor `phase10_get_snapshot_pair_compatible_internal` e a RPC `phase10_compare_process_snapshot_v2`.

O primeiro snapshot, ou um snapshot sem baseline compatível, produz `not_comparable` sem mudança detectada. Snapshots de normalizer ou source incompatíveis, incompletos ou inválidos não são usados como baseline; quando o snapshot corrente é inválido, a RPC mantém a validação de `snapshot_invalid`. Falhas de provider não geram snapshot e nunca são convertidas em `unchanged`.

A canonicalização ordena chaves de objetos, normaliza texto para NFC, remove whitespace externo, normaliza datas conhecidas para UTC e impõe limites de profundidade, nós, entradas e bytes. Parties são comparadas por `partyRef`; movimentos, por `movementRef`, preservando multiplicidade e sem fuzzy matching. Raw payload, headers, tokens, credenciais e mensagens de transporte nunca entram no diff. A distinção entre ausência, `null`, vazio e valor conhecido é preservada; incompletude não vira ausência de mudança.

O `comparison_hash` é SHA-256 do JSON canônico composto por versão, IDs, resultado, razão, campos alterados e diff. A unicidade é `(office_id, process_id, current_snapshot_id, comparison_version)`. O replay da mesma dupla e versão retorna o registro existente sem duplicar comparação, auditoria ou mudança. Um lock curto sobre o processo, constraints e `ON CONFLICT` protegem a execução concorrente.

## Persistência, segurança e auditoria

A migration `20260827000001_phase_10_comparison_detection.sql` permanece byte a byte idêntica à versão publicada no commit `7527d6a9e77b4583d779b8197bbc1fe5eac5d78a`. O hardening posterior está exclusivamente em `20260827000002_phase_10_comparison_hardening.sql`, que começa com `SET lock_timeout = '2s';` e adiciona somente a resolução de baseline compatível, o leitor interno compatível, a RPC v2 com retorno completo e os grants/comentários correspondentes. Nenhuma migration publicada da Fase 9 ou da Fase 10 é reescrita.

As funções incrementais são `SECURITY DEFINER` com `search_path = pg_catalog, public`. `PUBLIC`, `anon` e `authenticated` não têm `EXECUTE`; somente o backend `service_role` recebe execução das funções internas necessárias. O caminho legado permanece preservado para rollback, mas perde execução do backend para evitar que o leitor incompatível seja usado. Não há DML direto concedido ao `service_role` nas tabelas comparativas.

As tabelas possuem RLS habilitada, leitura same-office pela policy operacional existente e nenhum DML público. Triggers negam `UPDATE` e `DELETE` físicos. `detected_change` possui FK composta para a comparação correta e trigger que só permite referência a uma comparação `changed`. A auditoria `phase10_write_system_audit` é interna, allowlisted, usa `actor_user_id = NULL`, origem fixa `system_comparator`, correlation ID derivado da execução e metadata sem raw payload. A inserção da comparação, mudança e auditoria ocorre na mesma transação; falha de auditoria causa rollback integral.

## Implementação e testes

Os arquivos principais são `src/lib/comparison/comparator.ts`, `src/lib/comparison/persistence.ts`, `src/lib/monitoring/worker.ts`, `20260827000001_phase_10_comparison_detection.sql`, `20260827000002_phase_10_comparison_hardening.sql`, os testes pgTAP das Fases 10, o teste de baseline compatível e `test_phase10_comparison.sh`. Os testes cobrem estados, canonicalização, Unicode/whitespace, identidade de movimentos e parties, incompletude, versionamento, hash, idempotência, RLS/grants, tenant, provenance, fonte única do diff, detected change mínimo e rollback transacional da auditoria.

O teste obrigatório usa `A = compatível`, `B = posterior mas incompatível` e `C = atual compatível`. Ele comprova que C escolhe A, ignorando B, e também cobre ausência de baseline compatível, outro provider, outra source, normalizer incompatível, snapshot inválido e outro office. O teste real PostgreSQL usa duas conexões independentes e fixtures sintéticas para comprovar concorrência e idempotência.

O App CI contém um gate de histórico que prova que a migration 00001 permanece idêntica ao commit `7527d6a9` e que o hardening aparece somente na 00002, sem remover ou relaxar gates anteriores.

## Regressão, upgrade, rollback e critérios de parada

A regressão repete `npm ci`, format, lint, typecheck, unitários, build, reset, db lint, pgTAP específico e cumulativo, Auth E2E, PoC sintética, concorrências anteriores e da Fase 10, database types, hygiene, secret scan, `git diff --check`, Docker smoke e `npm audit` em nível High. Também são validados dois caminhos: banco novo aplicando Fase 9 → 00001 original → 00002 corretiva; e banco já no estado após 00001 recebendo somente 00002.

O rollback é operacional e não destrutivo: a chamada comparativa pode ser removida por commit reversível ou desabilitação server-only, preservando snapshots e evidências comparativas. Não há rollback por `DROP TABLE`, `DROP COLUMN` ou edição de migration publicada. A execução deve parar diante de provider real, processo sigiloso, segredo, grant amplo, DDL destrutivo, alteração de `main`, auditoria fora da transação, raw payload no diff, conversão de failure em `unchanged`, duplicação concorrente, vulnerabilidade High/Critical ou CI diferente do SHA publicado.

## Critérios de aceite

A fase será considerada pronta quando a migration 00001 estiver byte a byte igual ao commit publicado, a 00002 contiver as correções incrementais, banco novo e banco já migrado forem equivalentes, o wrapper retornar o diff persistido, C usar A no cenário A → B incompatível → C, ausência de anterior compatível nunca virar `unchanged`, concorrência continuar idempotente, RLS/grants permanecerem corretos, tipos refletirem as migrations, a regressão cumulativa passar e o App CI do SHA exato terminar verde.

A Fase 11 não será iniciada ao concluir este trabalho.
