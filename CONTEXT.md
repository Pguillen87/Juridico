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
- **Fase**: Fase 13 (PDF local + armazenamento privado + entrega fake/local). Não encerrada.

## Estado das macrofases

- Fase 1 a Fase 12: IMPLEMENTADO, TESTADO e ENCERRADO.
- Fase 13: IMPLEMENTADO, PARCIAL (bloqueio de runner isolado corrigido localmente; aguardando CI remoto).
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
- Status da fase: aguardando CI remoto pós-isolamento da suíte Auth E2E.

## Diagnóstico confirmado e correção aplicada

- No script `scripts/run-auth-e2e.mjs`, a execução invocava `npx --no-install playwright test` sem delimitar `--project=chromium`.
- Por consequência, a suíte Auth rodava também os testes de `tests-e2e/phase13-delivery.spec.ts` (projeto `phase13`), os quais falhavam por ausência da fixture sintética (`PHASE13_E2E_FIXTURE=1`), bloqueando o CI no Run ID `33674065960`.
- Correção aplicada: adição explícita de `--project=chromium` na chamada do Playwright em `scripts/run-auth-e2e.mjs`.
- Teste local: `npm run auth:e2e` validado com 34 testes `[chromium]` passando e 0 testes de F13 executados nesta suíte.

## Próxima ação objetiva

- Realizar commits delimitados e push para `phase-13-pdf-delivery`.
- Acompanhar execução do App CI no GitHub para o novo SHA.
- Retornar relatório factual e evidências para auditoria externa.

## Como atualizar este arquivo

- Atualizar apenas quando o estado real do repositório/CI mudar.
- Manter síntese factual (máx. 250–350 linhas), sem segredos, sem tokens e sem inventar estados.
