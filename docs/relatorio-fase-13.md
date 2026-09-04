# Relatório — Fase 13: Entrega privada de PDF

## 1. Identificação e escopo factual

| Campo | Estado factual |
|---|---|
| Branch | `phase-13-pdf-delivery` |
| Migrations F13 | `20260827000007_phase_13_pdf_delivery.sql` (histórica) + `20260827000008_phase_13_delivery_hardening.sql` (aditiva) |
| Primeiro comando | `SET lock_timeout = '2s';` |
| Escopo | PDF validado, artefato privado local, contato confirmado e workflow de delivery controlado |
| Dados/serviços externos | não utilizados |

Este relatório descreve a implementação local atual, incluindo migration, código de aplicação, tipos sincronizados, documentação e gates de CI.

## 2. IMPLEMENTADO NO CÓDIGO ATUAL

A Fase 13 adiciona bucket privado `private-reports` e as tabelas `client_contact`, `report_artifact`, `email_delivery`, `email_delivery_attempt` e `email_delivery_retry_command`. `report_artifact` vincula relatório, versão aprovada, hashes, fingerprint, tamanho e URI privada. Contatos exigem e-mail normalizado e confirmação. Deliveries preservam cópia dos hashes/URI do artefato e têm idempotência por escritório/chave.

As RPCs `phase13_create_client_contact`, `phase13_confirm_client_contact`, `phase13_deactivate_client_contact`, `phase13_generate_final_pdf`, `phase13_authorize_send`, `phase13_claim_delivery_attempt`, `phase13_record_delivery_attempt`, `phase13_reconcile_unknown_delivery`, `phase13_retry_delivery`, `phase13_resend_delivery`, `phase13_get_delivery_for_send` e `phase13_get_artifact` formam as fronteiras de domínio. O banco exige relatório aprovado, actor lawyer ativo, escritório ativo e objeto privado existente; claims de tentativa são reservados a `service_role`. A reconciliação é solicitada pelo lawyer, mas o resultado vem da evidência do `FakeEmailProvider` e pode ser `positive_confirmation`, `negative_confirmation` ou `still_unknown`. Estados de entrega e o resultado `unknown_outcome` são persistidos explicitamente.

`src/lib/reports/pdf-renderer.ts` fornece renderer injetável e adapter Playwright, valida `%PDF-`, SHA-256, tamanho e hash/snapshot. `src/lib/delivery/email-provider.ts` fornece contrato e `FakeEmailProvider`; suas respostas são sintéticas e não representam envio externo. As Server Actions/UI da branch integram a geração, download/autorização e ações de delivery sem transformar aprovação em envio automático.

## 3. CONTROLES E EVIDÊNCIA DE GATE

A migration inicia com lock curto, usa constraints/foreign keys, RLS, revogação de DML direto e policies de leitura fechada. Triggers tornam artefatos append-only e impedem alteração de identidade de delivery/tentativa. Auditoria allowlisted é gravada na mesma transação pelas RPCs.

Foram adicionados os gates:

- `scripts/check-phase13-migration-history.sh`: verifica 00005 no blob `c8f13774c0707d8502c6348283f2adf0e2673149`, 00006 no blob `2b61ff7a1e857e5ee395a602dda20d83498e6720`, `SET lock_timeout` na 00007 e imutabilidade histórica.
- `scripts/test-phase13-migration-upgrade.sh`: faz reset equivalente terminando em F12, upgrade incremental F12→00007→00008, compara fingerprint de schema/funções/tipos e executa pgTAP nos dois caminhos.
- `.github/workflows/app-ci.yml`: preserva gates anteriores e inclui branch, histórico, upgrade F13, concorrência F13 e E2E sintético local.

Os resultados de execução devem ser registrados pelo CI; este documento não inventa run, SHA ou contagem de testes.

## 4. PARCIAL E DEFERIDO

A capacidade de entrega está preparada apenas para sandbox/local. **Provider real**, **e-mail/SMTP real**, **storage remoto**, **produção**, **staging** e **retenção/expurgo automático** estão explicitamente **DEFERIDOS**. Também não há credenciais reais, endpoint externo, deploy, scheduler de retenção ou política de descarte implementada. O fake provider, o bucket local e os estados SQL não são evidência de integração real.

A autorização de envio registra intenção e permite execução posterior controlada; não prova aceitação por provedor nem entrega ao destinatário. Resultado `unknown_outcome` exige solicitação humana de reconciliação; o lawyer não escolhe delivered/failed, e `still_unknown` permanece bloqueado.

## 5. Rollback e limites

Rollback operacional significa bloquear novas ações F13 e preservar relatórios, artefatos, deliveries, tentativas e auditorias existentes. Não se apagam evidências nem se reescrevem migrations históricas. Qualquer alteração futura deve ser aditiva, revisada e manter o primeiro comando `SET lock_timeout = '2s';`.

## 6. Fechamento factual

- **Baseline F12 SHA**: `fcbf3c76521ce98f1a2e266282866077cdac3719`
- **SHA técnico aprovado da Fase 13**: `4240cff95db072d7c742f4615f18b64cd89473ac`
- **CI técnico**: `33913819841` (Run #207) – **conclusion**: `success`
- **Evidência técnica confirmada**:
  - Auth E2E isolado no projeto `chromium` (`scripts/run-auth-e2e.mjs`);
  - Reset do Supabase pós Auth E2E para evitar contaminação do pgTAP no CI;
  - Propagação determinística do ambiente Supabase local ao webServer Playwright (`readLocalSupabaseEnv`);
  - Phase 13 E2E local: 32/32 PASS;
  - Auth E2E local: 34/34 PASS;
  - CI Phase 13 E2E (local synthetic fixture): PASS.
- **Gates verdes**:
  - Secret Scan
  - Dependency Audit
  - Migration History F9–F13
  - Repository Hygiene
  - Format Check
  - Lint
  - Typecheck
  - Unit Tests
  - Supabase DB Reset
  - Phase 11 Migration Upgrade
  - Phase 12 Migration Upgrade
  - Phase 13 Migration Upgrade
  - Install Playwright Browsers
  - Auth E2E Tests
  - Reset Supabase after Auth E2E
  - Verify PoC
  - Supabase DB Lint
  - Supabase DB Tests (pgTAP)
  - Concurrency Tests (Last Owner, F9, F10, F11, F12, F13)
  - Bootstrap Phase 13 local E2E fixture
  - Phase 13 E2E (local synthetic fixture)
  - Verify PowerShell
  - Concurrency Tests (Admin Rate Limit, Phase 5, Phase 6)
  - Supabase DB Types Check
- **Ambiente e Deferimentos**: sandbox/local only; **provider real**, **e-mail/SMTP real**, **storage remoto**, **produção**, **staging**, **retenção/expurgo automático**, **credenciais reais** e **envio real** permanecem explicitamente **DEFERIDOS**.
