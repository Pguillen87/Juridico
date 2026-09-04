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
- **SHA técnico aprovado F13**: `4240cff95db072d7c742f4615f18b64cd89473ac`
- **Fase**: Fase 13 (PDF local + armazenamento privado + entrega fake/local). **ENCERRADA**.

## Estado das macrofases

- Fase 1 a Fase 12: IMPLEMENTADO, TESTADO e ENCERRADO.
- **Fase 13**: IMPLEMENTADA, TESTADA e ENCERRADA no escopo local/sandbox. CI técnico run **33913819841** (Run #207, SHA `4240cff95db072d7c742f4615f18b64cd89473ac`) concluiu `success`.
- **Fase 14**: NÃO INICIADA (proibido iniciar nesta sessão; próxima ação é planejamento próprio da Fase 14 somente após autorização humana).

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

- Entidades criadas: `client_contact`, `report_artifact`, `email_delivery`, `email_delivery_attempt`, `email_delivery_retry_command`.
- Bucket privado `private-reports` e gerador de PDF via Playwright local.
- Entregador fake local `FakeEmailProvider` com fluxo de idempotência, retry manual (máx. 3) e reconciliação de `unknown_outcome`.
- PDF Playwright local/sandbox.
- Storage privado local.
- Nenhum provider real, nenhum envio real, nenhum deploy.
- Status da fase: IMPLEMENTADA, TESTADA e ENCERRADA no escopo local/sandbox.

## Hardenings finais de CI na Fase 13

1. **Isolamento do Auth E2E**: Execução do Auth E2E restrita estritamente ao projeto `chromium` em `scripts/run-auth-e2e.mjs`.
2. **Reset pós-Auth E2E**: Inclusão de reset do Supabase no workflow do GitHub Actions (`app-ci.yml`) imediatamente após os testes Auth E2E para evitar poluição de dados residuais nos testes pgTAP.
3. **Propagação de ambiente no Playwright**: Leitura determinística das credenciais locais do Supabase via `readLocalSupabaseEnv` e injeção tipada no `webServer.env` em `playwright.config.ts`.

## Como atualizar este arquivo

- Atualizar apenas quando o estado real do repositório/CI mudar.
- Manter síntese factual (máx. 250–350 linhas), sem segredos, sem tokens e sem inventar estados.
