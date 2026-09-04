# Juridico — Contexto operacional

## Produto em uma frase

Aplicação administrativa web com controle rigoroso de autorização (D-022) e isolamento multi-tenant para acompanhamento rastreável de processos judiciais, geração de relatórios semanais aprovados, artefatos PDF privados e entregas locais rastreáveis.

## Stack e ambiente local

- **Frontend / Backend**: Next.js (App Router, Server Actions, standalone), TypeScript, Tailwind CSS, Zod.
- **Banco / Auth / Storage**: PostgreSQL local via Supabase CLI (`supabase start`), Supabase Auth, Row Level Security (RLS), bucket privado `private-reports`.
- **Testes & Qualidade**: Vitest (unitários), Playwright (E2E), pgTAP (testes no banco), scripts de concorrência bash/pwsh.
- **Ambiente de execução**: Windows local, Docker Desktop local, PostgreSQL/Supabase locais. Sem cloud externa no escopo.

## Documentos canônicos

- `PRODUCT.md`: Definições essenciais do produto, princípios e restrições.
- `DESIGN.md`: Diretrizes e identidade de interface.
- `README.md`: Instruções de inicialização e rotinas de desenvolvimento.
- `docs/00-visao-geral.md` até `docs/10-matriz-papeis-e-autorizacao.md`: Arquitetura, modelo de dados, decisões D-022 e rastreabilidade.
- `docs/plano-fase-12.md` e `docs/relatorio-fase-12.md`: Baseline aprovada da Fase 12.
- `docs/plano-fase-13.md` e `docs/relatorio-fase-13.md`: Planejamento e relatório factual da Fase 13.

## Baseline aprovada

- **Fase 12**: Encerrada e aprovada no commit `fcbf3c76521ce98f1a2e266282866077cdac3719`.

## Branch/fase atualmente em desenvolvimento

- **Branch**: `phase-13-pdf-delivery`
- **HEAD inicial verificado**: `4e007069e48e18e245bb7483b845658d705de3b3`
- **HEAD atual após correção**: `d0e3a2d3b25916f8ef192b45e9a4f6645fc86762`
- **Fase**: Fase 13 (PDF local + armazenamento privado + entrega fake/local). Não encerrada.

## Estado das macrofases

- Fase 1 a Fase 12: IMPLEMENTADO, TESTADO e ENCERRADO.
- Fase 13: IMPLEMENTADO, BLOQUEADO (Auth E2E resolvido e verde no CI; novo bloqueio identificado no gate subsequente Supabase DB Tests pgTAP).
- Fase 14: NÃO INICIADO (proibido iniciar nesta sessão).

## Invariantes críticos

1. Rastreabilidade total: toda informação expõe fonte, timestamp e estado.
2. Isolamento rígido por `office_id` com RLS no PostgreSQL.
3. Separação de estados de falha: timeout, erro técnico ou ausência de dados NUNCA equivalem a "sem movimentação".
4. Falha nunca significa "unchanged"; timeout nunca significa sucesso; semelhança de nome nunca confirma vínculo de parte.
5. Service role e secrets restritos estritamente ao servidor; nunca versionados ou expostos ao cliente.
6. Imutabilidade histórica: migrations publicadas são intocáveis (`00005`, `00006`, `00007`). Correções somente aditivas.

## Autorização D-022 resumida

- **Papéis funcionais**: `lawyer`, `operator`, `reviewer`, `auditor`.
- **Atributo administrativo**: `is_owner` (booleano independente; não concede poderes jurídicos).
- Somente `lawyer` pode gerar PDF aprovado (`generate_final_pdf`) e autorizar/executar envio (`authorize_send`).
- Auditor acessa exclusivamente trilhas de auditoria sanitizada; nunca acessa artefatos, PDFs, e-mails ou destinatários completos.

## Infra local

- Docker Desktop local ativo.
- Supabase CLI local (`supabase start`).
- PostgreSQL local com RPCs e RLS estritos.

## Serviços externos autorizados

- GitHub (`origin` no repositório `Pguillen87/Juridico`).

## Serviços externos NÃO autorizados

- Supabase Cloud, bancos remotos, Vercel, DataJud real, provedores reais de e-mail/SMTP, WhatsApp/SMS.

## Testes/gates importantes

- `npm run lint`, `npm run typecheck`, `npm run test`, `npm run build`.
- Scripts de validação de histórico de migração (`check-phase*-migration-history.sh`).
- Testes de upgrade e concorrência no PostgreSQL (`test-phase*-migration-upgrade.sh`, pgTAP, scripts bash/ps1).
- Playwright E2E: suíte `chromium` para autenticação histórica (`npm run auth:e2e`) e suíte `phase13` para entrega de PDF (`tests-e2e/phase13-delivery.spec.ts`).

## Estado atual da Fase 13

- Entidades criadas: `client_contact`, `report_artifact`, `email_delivery`, `email_delivery_attempt`.
- Bucket privado `private-reports` e gerador de PDF via Playwright local.
- Entregador fake local `FakeEmailProvider` com fluxo de idempotência, retry manual (máx. 3) e reconciliação de `unknown_outcome`.
- Status da fase: FASE13_BLOQUEADA.

## Diagnóstico do gate Auth E2E (RESOLVIDO)

- No script `scripts/run-auth-e2e.mjs`, a execução invocava `playwright test` sem delimitar `--project=chromium`.
- Correção aplicada no commit `04bc4d3`: adição de `--project=chromium` na chamada do Playwright.
- Evidência remota no Run ID `33896171966`: **Auth E2E Tests passou com sucesso (verde)**, executando exclusivamente o projeto `chromium`.

## Novo bloqueio identificado no CI remoto

- **Run ID**: `33896171966`
- **Head SHA**: `d0e3a2d3b25916f8ef192b45e9a4f6645fc86762`
- **Primeiro gate vermelho**: `Supabase DB Tests (pgTAP)`
- **Primeiro erro relevante**: Colisão de dados e chaves residuais de execução prévia nos testes de banco pgTAP (`duplicate key value violates unique constraint "query_execution_pkey"` no teste 15, e violação de idempotência / contagens de versão no teste 16 decorrentes de ausência de reset entre o gate Auth E2E e o gate pgTAP no workflow).
- Conforme regra de handoff, **não iniciar sequência de correções adicionais**. Parar e submeter relatório para auditoria externa.

## Como atualizar este arquivo

- Atualizar apenas quando o estado real do repositório/CI mudar.
- Manter síntese factual (máx. 250–350 linhas), sem segredos, sem tokens e sem inventar estados.
