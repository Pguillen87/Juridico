# Relatório Factual — Fase 7: Abstração de Provedores

## Estado do pacote

A Fase 7 foi implementada na branch `phase-7-provider-abstraction`, criada diretamente do HEAD `9ffd8001e9684035a0e0564d4982f043582220db` da branch `phase-6-processes-csv`. O pacote não altera `main`, migrations, banco ou dados operacionais.

A baseline contém Next.js App Router, Supabase/PostgreSQL com RLS e RPCs, testes Vitest/Playwright, Docker Compose e uma PoC DataJud conceitual. A PoC existente mistura resposta do provider com snapshot e comparação; o novo contrato da Fase 7 separa essa fronteira.

## Implementado

Foi criado `src/lib/providers/` com `ProviderContractV1`, capabilities allowlisted, identidade e metadata de origem, request interna, observação normalizada, falha explícita, erros sanitizados, fingerprint canônico determinístico, registry code-only, gateway backend-only, fixture sintética e `ManualProvider` de observação.

`ProviderResultV1` possui somente `observation` e `failure`. O provider não produz `changed` nem `unchanged`; esses estados pertencem à camada de comparação da Fase 10. Campos ausentes são declarados em `missingFields`, e evidência manual usa somente referência sintética e metadata mínima.

O `ManualProvider` não possui rota, Server Action, RPC, migration ou persistência operacional. A matriz D-022 contém `manual_reprocess` para lawyer/operator, mas não contém `manual_provider_entry`; por isso nenhuma role foi inventada. Entrada manual operacional permanece decisão humana pendente e critério de parada para qualquer expansão futura.

A entrada `src/lib/providers/server.ts` marca a fronteira server-only, enquanto os módulos puros permanecem testáveis em Vitest. Nenhum adapter externo, DataJud, segredo ou provider real foi adicionado. O App CI recebeu somente a branch `phase-7-provider-abstraction` no trigger de push; nenhum job ou gate existente foi removido ou relaxado.

## Deferido expressamente

DataJud operacional, credenciais, tribunais reais, scraping, CAPTCHA, processos sigilosos, scheduler, fila, worker, retry real, snapshot, comparação, detecção de alterações, central de falhas, notificações, relatórios, PDF e deploy permanecem fora da Fase 7. Não houve consulta a processo real, uso de CNJ real, integração externa ou escrita de dados de cliente.

## Validações locais

| Gate | Resultado factual |
|---|---|
| `npm ci` | aprovado; 422 pacotes auditados, zero vulnerabilidades reportadas |
| `format:check` | aprovado |
| `lint` | aprovado |
| `typecheck` | aprovado |
| Unit | 68 testes aprovados em 13 arquivos |
| Build | aprovado; Next.js compilado e rotas geradas |
| Supabase reset | aprovado; migrations publicadas aplicadas sem alteração |
| Database lint | aprovado; sem erros de schema |
| pgTAP | 214 testes aprovados em 10 arquivos |
| Auth E2E | 25 testes aprovados; `.last-run.json` com `status: passed` e `failedTests: []` |
| Rate-limit concurrency | `allowed=5`, `blocked=1`, `final_count=5` |
| Fase 5 confirmation concurrency | `success=1`, `rejected=1`, `terminal_audits=1` |
| Fase 6 concurrency | create CNJ `count:1`; preview `processes:1/imported_audits:1/replay_safe=true`; confirm/reject com uma transição válida |
| PoC DataJud sintética | 29 testes aprovados em 4 arquivos |
| Docker smoke | build/up/health/down aprovados; `/api/health` HTTP 200 com `{"status":"ok"}`; runtime `nextjs` |
| Database types | sem mudança semântica; diferença observada somente de aspas do formatter no arquivo gerado temporário |

## Revisão Production Stack

A revisão do delta não encontrou segredo literal, SQL interpolado ou chamada externa no novo módulo de providers. `npm audit --audit-level=high --omit=dev` retornou zero vulnerabilidades. O delta não contém SQL, migration, alteração RLS, grant ou RPC; portanto não houve risco novo de schema PostgreSQL. Os módulos de provider não importam Supabase, DataJud, `fetch`, Axios, scheduler, worker ou queue. As ocorrências de “comparison” no scan restrito estão somente nos nomes/assertions dos testes que comprovam a separação da comparação futura.

O risco residual da produção permanece fora do escopo desta fase: provider externo, credencial, snapshot, comparação, retries reais, jobs e observabilidade operacional completa dependem de decisões e fases posteriores. A ausência de uma ação D-022 específica para entrada manual de resultado também permanece documentada como decisão humana pendente.

## Status de requisitos

| Item | Status factual nesta Fase 7 |
|---|---|
| RF-006 / US-014 — integração DataJud | Partial/Deferred; contrato preparado, sem DataJud |
| US-015 — provedor manual | Partial/Deferred; somente adapter sintético, sem entrada operacional autorizada |
| RF-007 / US-017 — normalização | Implemented/Tested no limite de observação do contrato; persistência e snapshots deferidos |
| US-027 — provider não suportado | Implemented/Tested no registry/gateway; sem consulta externa |
| US-011 — ativação de monitoramento | permanece Partial/Deferred, conforme Fase 6 |

## Critérios de parada preservados

A implementação deverá parar antes de qualquer expansão se houver necessidade de entrada manual operacional sem decisão humana, provider externo, DataJud real, segredo, consulta de processo real/sigiloso, persistência nova, migration, mudança de D-022, scheduler, fila, worker ou comparação. O contrato não pode receber `changed`/`unchanged` nesta fase e nenhuma falha pode ser reinterpretada como `unchanged`.

## Corretivo incremental de integridade e validação runtime

A auditoria identificou que o `ManualProvider` recebia a referência solicitada e a referência observada, mas não comparava os valores. O corretivo agora exige correspondência exata entre `ManualObservationInput.processRef` e `ProviderRequestV1.subjectRef.value`. Em caso de divergência, o provider retorna `kind=failure`, `status=manual_review_required`, `errorCode=manual_process_mismatch`, `source=manual` e mensagem sanitizada; não retorna observação, `not_found`, `unchanged` ou qualquer mutação.

O validator runtime de `ProviderResultV1` foi fortalecido sem redesign: recebe `unknown`, rejeita chaves extras e campos proibidos, valida contractVersion, identidade e descriptor, capability e source allowlisted, ramo de observação, ramo de falha, errorCode, política de retry, `returnedFields`/`missingFields`, estruturas normalizadas, metadata mínima, evidência, correlationId e coerência do `processRef` com a request. Observação e falha permanecem ramos mutuamente exclusivos.

O código não cria migration, grant, RLS, RPC, endpoint, provider externo, DataJud, scheduler, fila, worker, snapshot ou comparação. A D-022 não foi alterada e nenhuma permissão de entrada manual operacional foi inventada.

Os testes do pacote passaram a cobrir aceitação do mesmo processo, rejeição de processo divergente, ausência de `observation`, ausência de `unchanged`/`not_found`, falha sanitizada, resultado runtime válido, resultado estruturalmente incoerente e ausência de campos proibidos. Todas as fixtures continuam sintéticas.

## Resultado final do corretivo

O corretivo foi validado localmente e está pronto para publicação incremental. A suíte unitária cumulativa terminou com **72 testes aprovados em 13 arquivos**, incluindo **15 testes do pacote de providers**. O pgTAP permaneceu em **214 testes aprovados em 10 arquivos**, o Auth E2E em **25 testes aprovados**, e a PoC sintética em **29 testes aprovados em 4 arquivos**.

A decisão de taxonomia para divergência de processo foi usar o status existente `manual_review_required`, com o novo `errorCode` descritivo `manual_process_mismatch`. Essa escolha preserva `source=manual`, evita inventar estado, não converte a divergência em `not_found` nem em `unchanged`, e exige revisão antes de qualquer decisão.

O validator runtime aceitou resultado válido e rejeitou resultado estruturalmente incoerente, incluindo campos proibidos e incompatibilidade de contrato. Não houve migration, alteração de RLS/grants/RPC, provider externo, DataJud real, dado real ou início da Fase 8.
