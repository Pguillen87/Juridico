# Relatório da Fase 6 — Processos e Importação CSV

## 1. Identificação e baseline

A Fase 6 foi implementada na branch `phase-6-processes-csv`, criada exatamente a partir da baseline aprovada `edaebdfcde0fdfd902c093a3b42a0f6d7fc36972` da branch `phase-5-clients-parties`. A branch não foi criada a partir de `main`. O arquivo `docs/plano-fase-6.md` preserva a versão aprovada do plano técnico e este relatório registra somente o resultado da execução.

Nenhum processo real, CNJ real de carteira, cliente real ou parte real foi usado. As fixtures e os cenários de concorrência usam apenas identificadores sintéticos.

## 2. Escopo executado

Foram implementados os itens US-006 a US-010. US-011 foi implementada somente até o limite aprovado: o processo nasce com `monitoring_status = 'paused'`, a UI informa que não existe monitoramento automático nesta fase e não há provider, DataJud, capability, job, fila, scheduler ou ação falsa de ativação.

| História | Entrega | Situação |
|---|---|---|
| US-006 | Cadastro manual de `legal_process`, CNJ canônico, cliente por ID, publicidade e estado estrutural pausado | Implemented/Tested |
| US-007 | Parser CSV dedicado, preview privado, hash, TTL, erros por linha e confirmação por `preview_id` | Implemented/Tested |
| US-008 | Validação CNJ universal no TypeScript para UX e no PostgreSQL como autoridade final | Implemented/Tested |
| US-009 | Associação N:N em `process_party`, com client/party/process por IDs e vínculo sempre pending | Implemented/Tested |
| US-010 | Confirmação/rejeição terminal somente por lawyer, com auditoria atômica e corrida coberta | Implemented/Tested |
| US-011 | Estado estrutural `paused`, sem provider ou scheduler | Partial/Deferred |

## 3. Banco de dados e segurança

As migrations incrementais adicionadas foram `20260826000006_phase_6_processes_csv.sql`, `20260826000007_phase_6_preview_read.sql` e `20260826000008_phase_6_rls_read_hardening.sql`. A primeira cria `legal_process`, `process_party`, `process_import_preview`, constraints, índices, RLS, grants mínimos, helper CNJ, RPCs de domínio, staging privado, TTL de 30 minutos e auditoria atômica. A segunda expõe exclusivamente a leitura controlada do preview criado pelo próprio actor/office por meio de RPC; não concede DML direto ao staging. A terceira substitui as policies SELECT da Fase 6 por policies que reutilizam `public.can_view_operational_row(office_id)`, incluindo role funcional permitida, usuário ativo, office ativo e isolamento por office.

As RPCs `create_legal_process`, `update_legal_process`, `deactivate_legal_process`, `create_process_party`, `confirm_process_party`, `reject_process_party`, `deactivate_process_party`, `preview_process_import` e `confirm_process_import` são `SECURITY DEFINER`, usam `search_path` fixo, derivam actor/role/office no banco e revalidam D-022. INSERT, UPDATE e DELETE direto nas tabelas operacionais permanecem revogados para `authenticated`, `anon` e `PUBLIC`; SELECT ocorre somente conforme RLS. Não existe DELETE físico de domínio.

A criação de `process_party` ignora qualquer tentativa de autoridade de confirmação enviada pelo caller: todo vínculo nasce como `pending`, com `confirmed_by` e `confirmed_at` nulos. Somente `confirm_process_party` e `reject_process_party`, com actor lawyer, produzem estados terminais. A unique parcial impede duplicata ativa de process/party/role, enquanto relações inativas preservam histórico.

Cada mutação de domínio e seu evento de `audit_log` ocorrem na mesma transação PostgreSQL. A confirmação CSV cria os processos, cria vínculos pending, registra os eventos e consome o preview no mesmo commit. Falha de auditoria ou de qualquer etapa provoca rollback integral. O helper operacional é fechado, allowlisted e não aceita metadata arbitrária do browser. A análise da expiração confirmou que o `UPDATE ... status = 'expired'` seguido de `RAISE EXCEPTION` sofre rollback na mesma transação; portanto, `expires_at` é a autoridade e o status pode permanecer `pending` até uma limpeza lazy futura. Nenhum scheduler foi criado.

## 4. CNJ e CSV

O módulo puro `src/lib/processes/cnj.ts` aceita CNJ formatado ou somente dígitos, exige 20 dígitos, calcula os dígitos verificadores sem limitação TJPR e retorna representação canônica. A migration repete a validação no PostgreSQL; chamadas diretas às RPCs com CNJ inválido falham mesmo quando a validação client-side é contornada.

O parser `src/lib/processes/csv.ts` suporta BOM UTF-8, campos quoted, vírgulas internas, aliases de cabeçalho, colunas obrigatórias, colunas desconhecidas, linhas vazias, limites de bytes/linhas, duplicidade, publicidade, estado de monitoramento e diagnósticos por linha. Não usa `split(',')`. Qualquer linha inválida bloqueia o lote inteiro conforme a Opção B aprovada. A prévia apresenta todas as linhas disponíveis e seus erros, sem persistir processo; somente um `preview_id` válido pode ser confirmado.

A resolução de client/party é assistida por nome, mas termina em IDs existentes no mesmo office. Nome ausente, inexistente, cross-office ou homônimo não cria entidade nem escolhe uma party silenciosamente. A confirmação do batch não recebe as linhas reconstruídas pelo browser.

## 5. UI e autorização

Foi criada a página protegida `/app/processos`, incluída na navegação da área protegida. A UI permite cadastro manual quando autorizado, exibe CNJ canônico, referências curtas de IDs, client e parties, vínculos pending/confirmed/rejected e os controles terminais somente para lawyer. Operator pode criar processo e vínculo pending, mas não vê Confirmar/Rejeitar. Reviewer possui leitura operacional sem mutação; auditor é bloqueado.

O componente de importação CSV mostra erros por linha, avisos, tabela de todas as linhas analisadas, resumo, hash/versão e expiração do preview. A confirmação envia somente `preview_id`. A interface informa explicitamente que monitoramento permanece pausado nesta fase.

## 6. Testes e gates locais

A regressão local foi executada separando os resultados por gate. O Vitest aprovou **57 testes em 12 arquivos**, incluindo os testes puros de CNJ e parser CSV. O build Next.js e o typecheck foram aprovados, e o `format:check` e o lint foram executados sem erro após a estabilização do spec Playwright.

O reset do Supabase aplicou todas as migrations da baseline, as migrations da Fase 5 e as quatro migrations da Fase 6. O `db:lint` terminou com **No schema errors found**. A geração dos tipos Supabase foi executada e formatada. O `db:test` aprovou a suíte existente de 4C/5, o arquivo `09_phase_6_processes_csv.test.sql` com 43 asserções e o arquivo `10_phase_6_rls_read_hardening.test.sql` com 12 asserções, totalizando **214 asserções pgTAP** no pacote.

| Gate | Resultado local |
|---|---|
| Format check | Aprovado |
| Typecheck | Aprovado |
| Lint | Aprovado |
| Unit tests | 57 aprovados |
| Build | Aprovado |
| Supabase reset | Aprovado |
| DB lint | Aprovado, sem erros de schema |
| Supabase types | Gerados e formatados |
| pgTAP | Aprovado; 214 asserções no pacote |
| Auth/Admin/Phase 5/Fase 6 E2E | 25 cenários aprovados; status persistido `passed` |
| Fase 6 concurrency | Aprovado |
| Rate-limit concurrency | `allowed=5`, `blocked=1`, `final_count=5` |
| Phase 5 confirmation concurrency | `success=1`, `rejected=1`, `terminal_audits=1` |
| Fase 6 create concorrente | 1 sucesso e 1 conflito de unique CNJ |
| Fase 6 confirm de preview concorrente | 1 processo, 1 auditoria de importação, replay seguro |
| Fase 6 confirm vs reject | 1 estado terminal e 1 transição inválida |

O E2E local exigiu isolamento de processos residuais do runner e uso de CNJs sintéticos únicos por teste para evitar colisões de retries em ambiente local. Após a limpeza, o arquivo `.last-run.json` registrou `status: passed` e `failedTests: []`.

O script bash de concorrência da proteção de último owner e os gates que dependem de `pwsh`/WSL não foram considerados aprovados localmente quando a ferramenta não estava disponível no Windows conectado. Esses gates permanecem obrigatórios para o App CI e deverão ser validados no workflow antes da conclusão formal.

## 7. CI e procedimento de publicação

O workflow do App CI inclui `phase-6-processes-csv` no trigger de push, preserva os gates da baseline e executa `scripts/test-phase6-concurrency.ps1` após as concorrências existentes da Fase 5. O workflow continua read-only: não contém `git add`, `git commit` ou `git push`. O smoke gate Docker foi executado localmente porque o ambiente suporta Docker Compose; não foi duplicado no CI nesta correção. Se o ambiente de validação não possuir Docker no futuro, o gate deverá executar build, up, health, non-root e down com `if: always()` antes de declarar sucesso.

O pacote corretivo será publicado somente após `git diff --check`, working tree limpo, ausência de artefatos proibidos e presença somente dos arquivos intencionais. O encerramento formal permanece condicionado à auditoria externa do HEAD publicado e ao CI correspondente.

## 8. Reviews de produção e Docker

O review final do delta foi executado nos três eixos pertinentes. O review de segurança não encontrou padrões de segredo versionado, SQL interpolado ou ampliação de grants, e `npm audit --audit-level=high --omit=dev` retornou **0 vulnerabilidades**. O review PostgreSQL confirmou `set lock_timeout = '2s'` como primeira instrução da migration 00008, nenhuma alteração nas migrations publicadas 00006/00007, nenhuma criação de índice/constraint de alto lock e reutilização da função canônica `can_view_operational_row`. O review geral não identificou CRITICAL ou HIGH dentro do delta; os itens MEDIUM/LOW fora do escopo do corretivo permanecem documentados, especialmente o pin por digest da imagem base e a evolução futura de healthcheck de produção.

O smoke gate Docker local passou integralmente: `docker compose build` com código 0, `docker compose up -d` com código 0, `GET /api/health` retornou HTTP 200 e `{"status":"ok"}`, `docker compose exec web whoami` retornou `nextjs`, e `docker compose down` retornou código 0. Não foi criado provider, DataJud, scheduler, job ou integração externa.

## 9. Documentação e critérios de parada

A matriz `docs/08-matriz-de-rastreabilidade.md` foi atualizada para marcar US-006 a US-010 como `Implemented/Tested` e US-011 como `Partial/Deferred`, sem declarar provider ou monitoramento real. A evidência adicional de RLS prova diretamente no PostgreSQL as permissões de reviewer, a negação para auditor/owner-auditor, office inativo e cross-office. Este relatório e o plano aprovado deverão ser publicados juntos no pacote final.

A execução deverá parar para nova autorização se surgir necessidade de provider, scheduler, DataJud, dados reais, criação automática de client/party, alteração de D-022, alteração das migrations da Fase 4C/5 ou ampliação de US-011. A Fase 6 não autoriza o início da Fase 7 ou de qualquer fase posterior.
