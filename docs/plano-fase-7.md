# Plano Técnico — Fase 7: Abstração de Provedores

## Objetivo

Criar uma fronteira interna, versionada e backend-only para providers, sem acoplar casos de uso a DataJud, tribunal ou fonte específica. A Fase 7 entrega contrato, capabilities, normalização, falhas explícitas, registry e um `ManualProvider` somente de observação sintética. Não implementa consulta externa, DataJud real, scheduler, fila, worker, snapshot ou comparação.

## Baseline e dependências

A branch `phase-7-provider-abstraction` nasce do HEAD final aprovado da Fase 6, `9ffd8001e9684035a0e0564d4982f043582220db`, filho de `f193b5984cf9987a84322088b3e77bf891dffd4b`. `main` permanece independente em `e48faff7a24a77e469365b9afe2cc5d47b8f4cd1`. A baseline foi confirmada com árvore limpa e o App CI da Fase 6, Run `32989224135`, terminou `completed/success` no SHA exato.

A auditoria da baseline confirmou Next.js App Router, Supabase/PostgreSQL com RLS/RPC, Vitest, Playwright, Docker Compose e uma PoC DataJud sintética. A PoC mistura atualmente observação, snapshot e estados de comparação; a Fase 7 separa essa fronteira e não reutiliza seus estados `success_with_changes` ou `success_without_changes`.

## Escopo

O pacote contém `ProviderContractV1`, tipos fechados de identidade, capabilities, request, observação, falha e metadata; fingerprint canônico determinístico; normalização e validação runtime; registry code-only; gateway server-side; fixture sintética; e `ManualProvider` com `source=manual`.

`ProviderResultV1` possui somente os ramos `observation` e `failure`. O provider não produz `changed` nem `unchanged`. Comparação pertence à Fase 10 e deverá consumir observações válidas sem converter falha, ausência ou resposta incompleta em `unchanged`.

## Segurança e D-022

A implementação não cria migration, tabela, policy, grant, RPC ou endpoint público. Não há persistência de provider, credenciais, raw payload ou dado processual. O pacote não é importado por client component; a entrada `src/lib/providers/server.ts` marca a fronteira server-only.

A D-022 real contém a ação `manual_reprocess` para `lawyer` e `operator`, mas não contém uma ação aprovada para `manual_provider_entry`. A Fase 7 não inventa role para entrada manual operacional: o `ManualProvider` entregue é um adapter de observação sintética, sem mutação e sem superfície operacional. Qualquer entrada manual operacional exige decisão humana antes de implementação futura.

Actor, office, role e `is_owner` permanecem contexto interno; não podem ser escolhidos pelo browser. O provider não usa service role, não recebe credencial e não apresenta resultado manual como DataJud ou tribunal.

## Fora de escopo

Ficam deferidos DataJud operacional, provider externo, credencial, tribunais reais, scraping, CAPTCHA, processos sigilosos, scheduler, fila, worker, retries reais, snapshots, comparação, detecção de alterações, central de falhas, notificações, relatórios, PDF e deploy. `changed`/`unchanged` permanecem exclusivos da Fase 10.

## Testes e aceite

Os testes cobrem contrato versionado, observação manual, ausência explícita de campos, falha por evidência inválida, capability não suportada, provider não registrado, fingerprint determinístico, sanitização de erros, rejeição de retry negativo e ausência de permissão D-022 inventada. Todas as fixtures são sintéticas.

A conclusão requer typecheck, lint, format, testes unitários completos, build, regressão da baseline, revisão de segurança/Production Stack, hygiene, CI da branch com `head_sha` exato e todos os gates verdes. Qualquer divergência documental material, necessidade de persistência ou entrada manual operacional sem decisão humana é critério de parada.
