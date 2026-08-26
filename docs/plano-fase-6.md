# Plano Técnico Auditável — Fase 6: Processos e Importação CSV

## 1. Objetivo e regra de execução

Este plano define a implementação futura da Fase 6 do projeto Juridico, abrangendo cadastro manual de processos, validação de CNJ, importação CSV em duas etapas e associação N:N entre partes e processos. Nesta etapa de planejamento não haverá alteração de código, criação de branch, migration, arquivo no repositório, commit ou push.

A implementação somente poderá começar depois da aprovação explícita deste plano. Depois que o usuário clicar **Confirmar**, a versão exata aprovada deverá ser salva localmente no repositório como `docs/plano-fase-6.md`; em seguida, a branch `phase-6-processes-csv` será criada **exatamente** a partir da baseline aprovada `edaebdfcde0fdfd902c093a3b42a0f6d7fc36972` da branch `phase-5-clients-parties`. `main` não será utilizada como base. Durante o `/plan`, nenhum arquivo do repositório, branch, migration, commit ou push será criado.

| Elemento | Decisão de planejamento |
|---|---|
| Repositório | `Pguillen87/Juridico` |
| Baseline | `edaebdfcde0fdfd902c093a3b42a0f6d7fc36972` |
| Branch de origem | `phase-5-clients-parties` |
| Branch futura | `phase-6-processes-csv` |
| Escopo | US-006 a US-011, com limites de dependência documentados |
| Dados de teste | Somente fixtures sintéticas |
| Dados reais | Proibidos nesta fase sem autorização separada |

## 2. Fontes canônicas e inspeção obrigatória

Antes da implementação, a equipe deverá ler integralmente, no SHA da baseline, os documentos `docs/01-requisitos-do-produto.md`, `docs/02-arquitetura-planejada.md`, `docs/03-modelo-de-dados-conceitual.md`, `docs/04-plano-de-implementacao.md`, `docs/05-riscos-e-decisoes-pendentes.md`, `docs/07-decisoes-do-mvp.md`, `docs/08-matriz-de-rastreabilidade.md`, `docs/09-definicao-de-pronto.md`, `docs/10-matriz-papeis-e-autorizacao.md`, `docs/plano-fase-5.md` e `docs/relatorio-fase-5.md`.

Também deverá ser inspecionada a implementação real existente em `src/lib/auth/permissions.ts`, `src/app/app/clientes/`, `supabase/migrations/`, `supabase/tests/`, `tests-e2e/`, `.github/workflows/app-ci.yml` e `poc/validate_cnj.js`. Nenhum documento poderá ser declarado ausente sem verificação no SHA exato. A matriz de papéis `docs/10-matriz-papeis-e-autorizacao.md` continuará sendo fonte normativa da D-022.

A baseline da Fase 5 deverá permanecer funcional e inalterada em comportamento: RLS, DML direto negado, RPCs `SECURITY DEFINER`, auditoria atômica, rollback de auditoria, proteção contra homônimos, concorrência, exportação administrativa, rate limit e fluxos de clientes/partes.

## 3. Escopo funcional

Estão no escopo US-006 — cadastro manual de processo; US-007 — importação CSV; US-008 — validação CNJ; US-009 — associação N:N por `process_party`; US-010 — confirmação/rejeição manual de vínculo; e US-011 — ativação/pausa de monitoramento, limitada pela dependência de providers e scheduler.

As rastreabilidades previstas são T-006, T-007, T-008, T-009, T-010 e T-011. O objetivo operacional é cadastrar processos e importar carteiras com validação, sem duplicação, sem gravação silenciosa e com auditoria.

Ficam fora do escopo: consulta ao DataJud, providers externos, tabela inventada de tribunais, jobs, filas, scheduler, `monitoring_schedule`, `query_job`, dashboard complexo, carteira real, os aproximadamente 60 processos reais, CNJs reais e dados reais de clientes ou partes. `legal_process` e `process_party` serão implementados nesta fase; provider capability e agendamento permanecerão para fases posteriores.

## 4. Decisões aprovadas para a Fase 6

### 4.1 Opção B aprovada: qualquer linha inválida bloqueia o batch

Foram consideradas duas opções: persistir as linhas válidas mesmo com inválidas, ou bloquear o lote inteiro. Fica aprovada a **Opção B: qualquer linha inválida bloqueia o batch inteiro**. Essa escolha reduz o risco de carteira parcialmente importada, evita que o usuário interprete o resumo como uma carteira completa e torna a auditoria e a reconciliação mais simples. A prévia deverá mostrar todas as linhas e seus erros; nenhuma linha inválida será descartada silenciosamente.

Na confirmação, todas as linhas selecionadas como válidas deverão ser persistidas em uma única operação transacional. Se qualquer falha inesperada ocorrer, todo o batch confirmado sofrerá rollback. Se o produto exigir posteriormente importação parcial, isso deverá ser uma nova decisão explícita e um novo contrato de auditoria.

### 4.2 US-011 — Alternativa A aprovada e dependências futuras

Serão comparadas as seguintes alternativas:

| Alternativa | Escopo | Risco/limitação |
|---|---|---|
| A — recomendada | Persistir somente estado estrutural mínimo, iniciar processos pausados e deferir ativação real validada por capability para Fase 7/9 | US-011 não será declarada implementada integralmente |
| B | Permitir marcar monitoramento como solicitado/ativo sem provider e sem gerar job | Cria estado operacional enganoso e pode induzir expectativa de monitoramento real |
| C | Não criar configuração de monitoramento e exibir explicitamente “não disponível nesta fase” | Menor risco, mas exige UI de escopo/limitação |

Fica aprovada a **Alternativa A**, combinada com a transparência da C na interface: `legal_process` possuirá apenas estado estrutural de monitoramento, com valor inicial `paused`; não existirá transição de UI ou RPC para “monitoramento real ativo”; nenhuma chamada a provider, capability, job, fila ou scheduler será criada. A ativação real ficará deferida para fase posterior. D-011 e D-012 não serão marcadas como aprovadas por inferência. US-011 permanecerá `PARTIAL/DEFERRED` e nunca será marcada como `Implemented/Tested` na Fase 6.

Não será criada `monitoring_configuration` nesta fase. Também não serão criados scheduler, fila, provider, capability ou job. Timezone, horários e configuração temporal serão deferidos para a fase apropriada. A UI indicará claramente que monitoramento automático ainda não está disponível e não exibirá uma ação falsa de “ativar” que apenas altere um flag.

### 4.3 Pacote de decisões aprovadas

Ficam fechadas para a Fase 6: (1) qualquer linha inválida bloqueia o batch inteiro; (2) US-011 segue a Alternativa A, com processo inicialmente `paused` e monitoramento real deferido; (3) não serão criados `monitoring_configuration`, scheduler, fila, provider, capability, job ou integração DataJud; (4) CSV nunca criará automaticamente client/party a partir de nome, usando somente entidades existentes explicitamente resolvidas por ID; e (5) serão usadas somente fixtures sintéticas, ficando a carteira real condicionada a autorização separada.

## 5. Modelo físico proposto

### 5.1 `legal_process`

Será criada uma tabela operacional `legal_process` com UUID como identidade, `office_id`, `client_id`, `cnj_number` canônico, `tribunal`, `system`, `is_public`, `monitoring_status`, `status`, `created_at`, `updated_at` e autoria (`created_by`). `status` será explicitamente `active | inactive`, com default `active`, para soft delete e preservação de histórico. `monitoring_status` terá valor inicial `paused` e não haverá transição para monitoramento real ativo nesta fase. Cada campo adicional deverá ser justificado na migration e na matriz de rastreabilidade.

Regras obrigatórias: `office_id` verificável no banco; client pertencente ao mesmo office; CNJ normalizado e válido; `UNIQUE (office_id, cnj_number)`; processo de outro office nunca utilizável; `status` default `active`; desativação auditada; registros inativos preservam histórico; processo inativo não recebe novas mutações operacionais salvo operação explicitamente autorizada; sem DELETE físico; e nenhuma confiança em `office_id` vindo do browser. As FKs e constraints deverão impedir referências cruzadas entre offices.

`monitoring_status` deverá usar vocabulário explícito e mínimo, com estado inicial pausado conforme a decisão de dependência. A nomenclatura final deverá ser alinhada aos documentos canônicos antes da migration; não será inventado estado que implique provider funcional.

### 5.2 `process_party`

Será criada uma tabela `process_party` para associação N:N real entre `legal_process` e `party`, contendo: `id`, `office_id`, `process_id`, `party_id`, `role_in_process`, `source`, `confirmation_status`, `confirmed_by`, `confirmed_at`, `notes`, `status`, `created_at`, `updated_at` e autoria. `status` será explicitamente `active | inactive`, com default `active`, para soft delete, desativação auditada e preservação do histórico.

`source` terá vocabulário explícito e allowlistado, inicialmente limitado a `manual` e `csv`; nenhum provider será inventado. Toda criação de `process_party`, independentemente de `source`, nascerá obrigatoriamente com `confirmation_status = 'pending'`, `confirmed_by = NULL` e `confirmed_at = NULL`. A RPC `create_process_party` não aceitará nem respeitará `confirmation_status`, `confirmed_by` ou `confirmed_at` fornecidos pelo caller/browser. Mesmo lawyer não poderá criar diretamente vínculo confirmado ou rejeitado. Somente `confirm_process_party` e `reject_process_party`, executadas por `role = 'lawyer'` conforme D-022, poderão realizar a transição terminal explícita e auditada. Relações terminais não retornarão silenciosamente a `pending`; confirmação/rejeição registrarão ator e data. A unique parcial deverá impedir duplicata somente quando `status = 'active'`, usando `process_id + party_id + role_in_process`. Relações inativas preservarão histórico e não haverá DELETE físico.

Partes e processos deverão pertencer ao mesmo office, IDs serão a identidade, e homônimos nunca serão confirmados automaticamente. A desativação lógica preservará histórico e não utilizará DELETE físico.

### 5.3 Migrations

As migrations serão incrementais e separadas por responsabilidade: fundação de tabelas e constraints; RLS e grants; RPCs e auditoria; compatibilidades/correções; e staging privado de preview. Nenhuma migration aprovada da Fase 4C ou da Fase 5 será alterada.

A estratégia será expand-contract quando houver evolução de schema. A Fase 6 adotará explicitamente staging PostgreSQL privado, em estrutura equivalente a `process_import_preview`, contendo somente `id/preview_id`, `office_id`, `created_by`, `content_hash`, `parser_version`, payload/linhas normalizados mínimos, `summary`, `created_at`, `expires_at`, `status` (`pending | consumed | expired`) e `consumed_at` quando aplicável. O TTL técnico será de **30 minutos**, salvo requisito canônico posterior; a limpeza poderá ser lazy durante utilização e não haverá scheduler somente para limpeza. CSV bruto não será mantido indefinidamente.

## 6. Validador CNJ

O validador de produto será independente da PoC `poc/validate_cnj.js` e não copiará a limitação específica do TJPR — segmento 8 e tribunal 16. Ele deverá aceitar máscara ou somente dígitos, remover formatação, exigir exatamente 20 dígitos, validar os dígitos verificadores pela regra CNJ, retornar erro compreensível e persistir exclusivamente a representação canônica.

O validador não hardcodará TJPR nem criará tabela de tribunais sem fonte canônica. A coerência entre `tribunal` e código CNJ não será validada por mapeamento inventado; se essa regra for necessária, deverá ser fornecida fonte confiável e decisão própria. Nenhum CNJ real será usado em fixtures.

A implementação ficará em módulo puro e testável, compartilhado por cadastro manual, parser CSV e confirmação do batch. A autoridade final será obrigatoriamente PostgreSQL: toda RPC que cria ou altera `legal_process` deverá chamar helper fechado de banco conceitualmente equivalente a `normalize_cnj(...)`/`validate_cnj(...)` antes de persistir. A implementação TypeScript poderá compartilhar a regra para UX e preview, mas será apenas conveniência/server-only; chamadas diretas à RPC com CNJ inválido deverão falhar. A confirmação CSV também passará pela mesma validação DB-side. Não será hardcodado TJPR.

## 7. Acesso, RLS, RPCs e auditoria

O padrão da Fase 5 será preservado. Para tabelas operacionais mutáveis, SELECT ocorrerá somente quando autorizado por RLS. INSERT, UPDATE e DELETE direto serão `REVOKE/DENY` para `authenticated`, `anon` e `PUBLIC`; DELETE físico será sempre negado. Toda mutação passará por RPC de domínio estreita.

As RPCs serão `SECURITY DEFINER`, com `search_path` fixo, grants mínimos, actor/role/office derivados no banco e D-022 revalidada no banco. O browser nunca será autoridade para `office_id`, actor, role ou `is_owner`; não haverá `service_role` no browser.

RPCs previstas, sujeitas ao ajuste pelos documentos canônicos, incluem `create_legal_process`, `update_legal_process`, `deactivate_legal_process`, `create_process_party`, `confirm_process_party`, `reject_process_party`, `deactivate_process_party`, `preview_process_import` e `confirm_process_import`. `create_process_party` aceitará somente os dados necessários para process/party, role, source e notes; sempre forçará `pending`, NULL de ator/data de confirmação e status `active`, sem aceitar autoridade de confirmação do caller. `confirm_process_party` e `reject_process_party` serão as únicas RPCs de transição terminal e exigirão lawyer. A confirmação do CSV deverá ser uma operação de domínio autenticada, não um INSERT em lote originado diretamente pela Server Action; seus vínculos também nascerão pending.

A auditoria será atômica: cada RPC mutacional executará a mutação de domínio e o INSERT em `audit_log` na mesma transação PostgreSQL; falha da auditoria provocará rollback integral. O helper interno de auditoria operacional será fechado, allowlisted e chamado somente por RPCs controladas. Não aceitará actor, office, role, `is_owner` ou metadata arbitrária do navegador e não terá EXECUTE público/authenticated sem necessidade direta.

Eventos planejados, somente quando realmente utilizados, são `process.created`, `process.updated`, `process.deactivated`, `process_party.created`, `process_party.confirmed`, `process_party.rejected`, `process_party.deactivated` e `process.imported`. Qualquer validator de auditoria introduzido pela Fase 6 deverá atuar somente sobre o vocabulário real de eventos da Fase 6 e não poderá se tornar uma allowlist global de `audit_log`. Eventos administrativos 4C e operacionais da Fase 5 permanecerão compatíveis e append-only.

## 8. D-022 e matriz de permissões

A implementação deverá refletir exatamente a matriz aprovada:

| Operação | Lawyer | Operator | Reviewer | Auditor |
|---|---:|---:|---:|---:|
| Cadastrar processo | ALLOW | ALLOW | DENY | DENY |
| Importar CSV | ALLOW | ALLOW | DENY | DENY |
| Criar vínculo process_party | ALLOW, sempre pending | ALLOW, sempre pending | DENY | DENY |
| Confirmar vínculo process_party | ALLOW | DENY | DENY | DENY |
| Rejeitar vínculo process_party | ALLOW | DENY | DENY | DENY |
| Ativar/desativar monitoramento | ALLOW | ALLOW | DENY | DENY |

`is_owner` não adicionará poder operacional. Usuário inativo e office inativo serão sempre DENY. A matriz será testada tanto na UI quanto em RPC/pgTAP, incluindo spoof de office e tentativa por ID direto.

## 9. Arquitetura CSV: preview e confirm

A fronteira será explicitamente: **Browser -> Server Action -> módulo server-only de parser/normalização CSV -> RPC `preview_process_import` -> staging PostgreSQL privado**. O PostgreSQL não interpretará bytes CSV. O módulo server-only validará tamanho, decodificará UTF-8/BOM, usará parser CSV dedicado, interpretará quoted fields, normalizará headers/campos, validará schema estrutural, executará validação CNJ para feedback e produzirá representação normalizada.

Na **Etapa A — Preview**, a RPC persistirá apenas o staging privado após revalidar actor, office, D-022, client IDs, party IDs, cross-office, CNJ via helper PostgreSQL, duplicidade no DB, versão/hash e regras de `process_party`. Nenhum `legal_process` ou `process_party` será criado nesta etapa. Não haverá leitura/escrita direta do staging pelo browser; `authenticated`, `anon` e `PUBLIC` não terão DML direto.

A prévia deverá produzir um identificador de preview, hash criptográfico do conteúdo normalizado e versão do schema/parser. A confirmação não confiará em linhas reconstruídas pelo browser: revalidará no servidor e aplicará o conteúdo associado ao preview/staging controlado. O preview terá TTL e limpeza definida; não haverá retenção indefinida do CSV bruto.

Na **Etapa B — Confirm**, o Browser enviará somente `preview_id` à Server Action, que chamará `confirm_process_import(preview_id)`; as linhas não serão reenviadas como fonte de verdade. A RPC travará o preview, validará `pending` e não expirado, actor/office, TTL, hash, versão, entidades, constraints, CNJ DB-side e regras de `process_party`; persistirá o batch em uma transação, gravará auditoria e marcará o preview como `consumed` na mesma transação. Preview de outro office/ator, expirado ou consumido será negado ou terá replay seguro sem duplicação. Qualquer falha provocará rollback integral.

O parser deverá suportar UTF-8, BOM, cabeçalho, CSV vazio, colunas obrigatórias ausentes, colunas desconhecidas, linhas vazias, campos quoted, vírgulas dentro de campo, limites máximos de bytes e linhas, linhas inválidas, duplicidade de CNJ no arquivo e no office, client inexistente ou ambíguo, party inexistente ou homônima, papel ausente/inválido e booleano/publicidade inválido. Não será usado `split(',')`.

## 10. Resolução de nomes e `process_party` via CSV

`cliente` e `parte` no CSV serão somente referências textuais para resolução assistida. Toda resolução deverá terminar em IDs reais. Nome homônimo será ambíguo e bloqueará a linha; nome não criará client/party, não fará merge e não escolherá party silenciosamente.

A prévia permitirá selecionar ou reconciliar explicitamente entidades já existentes da Fase 5. O usuário deverá revisar os IDs resolvidos antes de confirmar. Se uma linha não possuir party, o processo poderá permanecer válido sem vínculo quando o requisito permitir; o resumo deverá deixar essa condição explícita. Com `party` e `role`, a associação usará IDs resolvidos, `source='csv'` e `confirmation_status='pending'`, com `confirmed_by=NULL` e `confirmed_at=NULL`, obrigatoriamente. Lawyer poderá criar o vínculo pending e depois confirmar/rejeitar por RPC específica; operator poderá apenas criar o vínculo pending. Nunca haverá confirmação automática porque o nome coincidir.

## 11. Server Actions e UI

Será criada UI funcional mínima em `/app/processos`, sem dashboard complexo. Ela terá listagem paginada/limitada, cadastro manual, detalhe, client associado, CNJ canônico e apresentação formatada quando apropriado, tribunal, sistema, publicidade, status, partes, estados pending/confirmed/rejected, confirmação/rejeição somente para lawyer, importação CSV, preview, erros por linha, warnings, resumo e confirmação explícita.

As Server Actions apenas validarão entrada superficial e poderão chamar o módulo server-only de parsing; não farão DML direto. A persistência ocorrerá somente por RPCs estreitas. Não aceitarão office/actor/role do browser e não executarão auditoria separada. Upload seguirá `preview_id`/staging e confirmação enviará somente `preview_id`, com mensagens seguras e sem exposição de stack trace ou detalhes internos.

Os IDs curtos deverão ser exibidos junto dos nomes para distinguir homônimos. Seleções de client/party usarão `value` com UUID e exibirão nome mais referência curta; ausência, ambiguidade ou cross-office bloqueará o fluxo com mensagem compreensível.

## 12. Testes unitários

Serão adicionados testes puros e sintéticos para normalização CNJ, dígitos verificadores, máscara, tamanho, entradas inválidas e mensagens de erro; parser CSV com BOM, UTF-8, cabeçalho, quoted fields, vírgulas internas, arquivo vazio, colunas ausentes/desconhecidas, linhas vazias, limites, duplicatas e normalização; schemas Zod; e mapeamento de erros seguros.

Nenhuma fixture conterá processo real, CNJ real, cliente real ou parte real. O teste deverá comprovar que a regra TJPR da PoC não vazou para o validador de produto.

## 13. pgTAP e segurança de banco

A suíte deverá preservar todos os testes 4C/5 e adicionar cobertura para constraints de `legal_process`, unique office+CNJ, RLS, cross-office, DML direto negado, matriz RPC por papel, usuário/office inativo, spoof de office, relação N:N, duplicata ativa, homônimos, criação de `process_party` sempre pending para lawyer e operator, rejeição de parâmetros de confirmação na criação, confirm/reject somente por lawyer, transição terminal, append-only, atomicidade, falha de auditoria com rollback, atomicidade de confirmação CSV e corrida de duplicata CSV.

Também serão testadas expiração, hash, staleness, replay, double-click, concorrência, consumo idempotente e limpeza/retention do staging PostgreSQL privado.

## 14. E2E e concorrência

Os E2E usarão fluxos reais e execução serial quando houver estado compartilhado. Lawyer criará processo manual com CNJ válido, verá a persistência canônica, terá CNJ inválido bloqueado, associará party pending, confirmará um vínculo, rejeitará outro e executará CSV com preview, linha inválida visível, ausência de processo antes da confirmação e registros válidos após confirmação.

Operator criará processo, importará CSV, criará process_party pending e não verá Confirmar/Rejeitar. Reviewer terá leitura operacional permitida conforme D-022, sem mutação. Auditor terá o fluxo operacional negado. Cenários cross-office comprovarão que processo, party e client externos não aparecem, ID direto não contorna RLS e importação não referencia entidade externa.

Testes concorrentes cobrirão dois creates do mesmo CNJ, duas confirmações do mesmo preview/batch e confirm versus reject do mesmo `process_party`. Em cada transição terminal deverá haver um sucesso e uma rejeição, sem auditoria falsa da operação perdedora. Constraints e locks PostgreSQL serão a última linha de defesa.

## 15. CI e regressão da baseline

A futura branch `phase-6-processes-csv` deverá ser adicionada ao trigger do App CI somente quando a implementação for publicada. O workflow continuará read-only e nunca conterá `git add`, `git commit` ou `git push`.

Antes da conclusão serão executados, sem reduzir cobertura: format check, lint, typecheck, unit, build, Supabase reset, DB lint, pgTAP, Auth/Admin/Phase 5 E2E, novos E2E de processos/CSV, PoC DataJud, last-owner concurrency, admin rate-limit concurrency, Phase 5 confirmation concurrency, database types, Docker health/non-root e o Production Stack relevante. Novos gates de concorrência deverão estar no CI.

A execução local será registrada separando gates passados, bloqueados por limitação ambiental e executados no CI. Falha local de ferramenta não será mascarada como sucesso.

## 16. Documentação e critérios de pronto

Após aprovação e implementação, deverão existir `docs/plano-fase-6.md` e `docs/relatorio-fase-6.md`, além da atualização factual de `docs/08-matriz-de-rastreabilidade.md`. A documentação deverá registrar decisões, migrations, eventos de auditoria, evidências de testes, limites de US-011 e ausência de dados reais.

A Fase 6 será considerada pronta somente quando: a branch nascer da baseline exata; legal_process e process_party estiverem protegidos por constraints, RLS e RPCs; CNJ estiver normalizado e validado sem limitação TJPR; CSV tiver preview/confirm com hash, revalidação e rollback; homônimos e cross-office estiverem bloqueados com segurança; auditoria for atômica; UI e D-022 estiverem aceitas; concorrências estiverem cobertas; baseline da Fase 5 continuar verde; todos os gates locais possíveis e todos os gates do CI estiverem verdes; documentação estiver factual; e nenhum dado real tiver sido usado.

A implementação deverá parar para nova autorização caso surja necessidade de provider, scheduler, DataJud, novos dados pessoais, criação automática de client/party, mudança de D-022, alteração de migrations 4C/5, ou alteração de escopo US-011.

## 17. Riscos principais e mitigação

| Risco | Mitigação |
|---|---|
| Hash/preview stale ou replay | TTL, hash do conteúdo normalizado, versão do parser, revalidação e operação idempotente |
| Duplicação por concorrência | `UNIQUE` no banco, locks/constraints e teste de corrida |
| Importação parcial inesperada | Opção B: batch inteiro bloqueado por linha inválida e rollback integral em falha inesperada |
| Homônimo associado silenciosamente | Resolução assistida por ID, ambiguidade bloqueante e revisão humana |
| Cross-office por spoof | Actor/office derivados no banco, FKs compostas, RLS e pgTAP |
| Auditoria incompleta | Helper fechado, allowlist, mesma transação e teste de falha/rollback |
| US-011 criar falsa expectativa | Estado pausado, UI transparente e provider/scheduler deferidos |
| CSV malformado ou abusivo | Parser dedicado, limites de bytes/linhas, quoted fields e validação de schema |
| Regressão Fase 5 | Reexecução integral da baseline e gates existentes no CI |

## 18. Confirmação do pacote aprovado e procedimento pós-aprovação

As cinco decisões acima estão aprovadas para este plano: Opção B para linhas inválidas; Alternativa A para US-011; ausência de `monitoring_configuration`, scheduler, fila, provider, capability, job e DataJud; ausência de criação automática de client/party por nome; e uso exclusivo de fixtures sintéticas com autorização separada para carteira real.

Depois que o usuário clicar **Confirmar**, será executado este procedimento: (1) salvar localmente a versão exata aprovada como `docs/plano-fase-6.md`; (2) criar `phase-6-processes-csv` exatamente de `edaebdfcde0fdfd902c093a3b42a0f6d7fc36972`; (3) implementar e testar localmente; (4) não fazer push parcial; (5) somente após o pacote local completo e verde publicar branch e documentação; (6) aguardar o App CI; e (7) parar para auditoria externa. Nenhuma decisão será inferida a partir de `main` ou de dados reais.

**PLANO PRONTO PARA AUDITORIA.**
