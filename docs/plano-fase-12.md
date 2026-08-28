# Plano técnico — Fase 12: Relatório Semanal, Revisão e Aprovação

## 1. Baseline, branch e objetivo

A Fase 12 parte exclusivamente da baseline Fase 11 `aa96eca762a47a1497203758fb62513e190139e5`, na branch dedicada `phase-12-weekly-reports-review-approval`. A implementação deve permanecer separada de `main`, usar somente migrations aditivas e preservar a imutabilidade das migrations das Fases 9, 10 e 11.

O objetivo é disponibilizar a geração backend-only de um relatório semanal congelado por cliente e período, sua consulta interna, edição editorial allowlisted, revisão, restauração em nova versão, aprovação humana com hash recalculado e cancelamento terminal. O relatório deve ser reproduzível a partir de fatos persistidos e não pode depender de payload bruto, inferência por nome ou estado mutável posterior ao cutoff.

| Item | Decisão/limite |
|---|---|
| Baseline | `aa96eca762a47a1497203758fb62513e190139e5` |
| Branch | `phase-12-weekly-reports-review-approval` |
| Escopo | geração, congelamento, edição editorial, revisão, restauração, aprovação e cancelamento |
| Atores jurídicos | `lawyer` edita/revisa/aprova/cancela; `reviewer` edita/revisa; `operator` e `auditor` não acessam relatórios |
| Fonte de autoridade | fatos, vínculos e auditoria persistidos antes do cutoff |
| Fora do escopo | PDF, artefato, download, storage de entrega, e-mail, webhook, scheduler novo, fila, worker novo, IA, DataJud/CNJ real, produção, piloto e Fase 13 |

## 2. Regras funcionais congeladas

O período usa a convenção `[start,end)`. A janela semanal termina na sexta-feira às 17:00 em `America/Sao_Paulo`; o instante é convertido para UTC e o timezone IANA é persistido. O cálculo no banco é a autoridade do registro, e a implementação TypeScript serve como validação de apresentação/teste da mesma regra, inclusive em datas históricas de mudança de offset.

A geração é idempotente por escritório, cliente e período. O resultado congela uma versão técnica e seu manifesto de fontes persistidas. O conteúdo inclui separadamente observações `changed`, `unchanged`, `not_comparable` e `failure`; falha nunca pode ser convertida em `unchanged`. Não se persiste payload bruto do provider dentro do relatório.

A prova cliente→processo exige auditoria persistida antes do cutoff. Se a prova histórica não existir, a geração falha fechado com `manual_review_required` antes de criar `weekly_report` ou `report_version`. A relação processo→parte só é incorporada quando o processo já estiver comprovado; ambiguidade de parte mantém o processo comprovado como pendente de revisão manual e não confirma identidade por nome.

## 3. Modelo de dados e imutabilidade

A migration aditiva `20260827000005_phase_12_weekly_reports.sql` deve começar literalmente com `SET lock_timeout = '2s';`. Ela cria apenas as estruturas necessárias para o domínio F12: `weekly_report`, `report_version`, `report_process`, `report_party` e `report_command_idempotency`.

`weekly_report` representa o agregado por cliente/período; `report_version` conserva versões técnicas e editoriais; `report_process` e `report_party` armazenam as projeções congeladas; `report_command_idempotency` evita duplicação de comandos. Triggers append-only e guards impedem alteração indevida das versões, projeções e registros de idempotência. Cancelamento é terminal e não permite uma segunda geração para o mesmo cliente/período.

O hash aprovado é calculado novamente sobre o conteúdo persistido e o manifesto da versão exata no momento da aprovação. A aprovação grava a versão aprovada, o hash recalculado e a auditoria na mesma transação. Restauração nunca sobrescreve uma versão existente: cria uma nova versão com origem `restored`, mantendo o histórico anterior.

## 4. Mutação, autorização e auditoria

Todas as mutações são executadas por RPCs de domínio `SECURITY DEFINER`, com `search_path` fixo, grants mínimos e revalidação de D-022 no banco. O browser envia somente os identificadores e campos allowlisted necessários ao comando; não escolhe `office_id`, actor, role, `is_owner` ou qualquer identidade jurídica. `service_role` pode executar somente a geração backend-only e wrappers internas permitidas; não é ator jurídico.

A camada de leitura server-only exige perfil e escritório ativos e bloqueia explicitamente `operator` e `auditor` na central de relatórios. A RLS permanece como segunda linha de defesa, com isolamento por `office_id`. DML direto em tabelas operacionais novas é revogado para `authenticated`, `anon` e `PUBLIC`; a escrita ocorre somente pelas RPCs de domínio.

Cada RPC mutacional executa a alteração de domínio e o `INSERT` no `audit_log` na mesma transação PostgreSQL. O helper interno de auditoria é fechado, possui eventos e metadados allowlisted, deriva actor/office/role no banco e não aceita metadata arbitrária do navegador. Se a auditoria falhar, a mutação inteira sofre rollback. O `audit_log` continua append-only.

## 5. Comandos e transições

| Comando | RPC de domínio | Atores | Resultado |
|---|---|---|---|
| Gerar relatório | `phase12_generate_weekly_report` | backend-only `service_role` | cria o relatório e a versão técnica somente após as provas históricas |
| Criar versão editorial | `phase12_create_editorial_version` | `lawyer`, `reviewer` | nova versão allowlisted, sem alterar fatos técnicos |
| Restaurar editorial | `phase12_restore_report_version` | `lawyer`, `reviewer` | nova versão `restored`, sem sobrescrever histórico |
| Submeter revisão | `phase12_submit_report` | `lawyer`, `reviewer` | versão corrente passa a `awaiting_review` |
| Devolver para edição | `phase12_return_report_to_draft` | `lawyer`, `reviewer` | retorno controlado a `draft`, preservando histórico |
| Aprovar | `phase12_approve_report` | `lawyer` | recalcula hash e registra aprovação da versão exata |
| Cancelar | `phase12_cancel_report` | `lawyer` | estado terminal, sem nova geração ou mutação posterior |

As Server Actions são apenas fronteiras autenticadas, validadoras e chamadoras das RPCs. Elas não fazem DML direto nem gravam auditoria em chamada posterior separada. Após sucesso, devem revalidar as rotas server-rendered e redirecionar para o detalhe com mensagem allowlisted; falhas permanecem sanitizadas e não expõem SQL, segredo ou payload.

## 6. UI, consulta e D-022

A central `/app/relatorios` oferece filtros server-side por cliente, período e status, preservando o isolamento do escritório. A rota `/app/relatorios/[id]` exibe o período, timezone persistido, versão corrente, fatos congelados, histórico de versões, estado de aprovação/cancelamento e somente os comandos compatíveis com o ator e o estado atual.

A UI deve deixar explícito que aprovação não significa envio. Não deve oferecer PDF, download, artefato, destinatário, e-mail, webhook ou qualquer controle de delivery. A lista e o detalhe devem ter saída de sessão visível para os fluxos autenticados.

A matriz normativa canônica é `docs/10-matriz-papeis-e-autorizacao.md`. Nenhuma permissão nova é inventada para `manual_provider_entry`, e o escopo F12 não altera a política de providers das fases anteriores.

## 7. Validação e testes

A validação deve combinar testes de contrato/editorial/hash/período, pgTAP, concorrência, E2E autenticado, regressão cumulativa e verificação dos tipos gerados pela Supabase CLI. O caminho de banco novo e o upgrade válido a partir da Fase 11 devem ser comparados sem alterar migrations históricas.

| Área | Evidência mínima |
|---|---|
| Banco | pgTAP cobrindo 58 asserts: RLS/grants, geração fechada, congelamento, estados, idempotência, D-022, versões, hash, terminalidade e rollback de auditoria |
| Concorrência | oito cenários reais: geração dupla, edição dupla, edição/submissão, edição/aprovação, aprovação dupla, aprovação/cancelamento, dois escritórios e replay |
| UI/E2E | filtro, edição, submissão, devolução, restauração, restrição de reviewer, aprovação lawyer, cancelamento terminal, logout e bloqueio de auditor |
| Regressão | Fases 9–11, PoC sintética, DB lint, pgTAP, tipos, PowerShell, hygiene, secret scan, auditoria de dependências, build e checks estáticos |
| Segurança | D-022, RLS por office, grants mínimos, ausência de DML direto, auditoria atômica, sanitização e ausência de segredo |

## 8. CI, rollback e critérios de parada

O App CI não pode remover ou relaxar gates existentes. A nova fase acrescenta apenas os gates de histórico F12, upgrade F12 e concorrência F12, mantendo a regressão cumulativa. O gate de tipos deve sempre comparar o arquivo versionado com a saída real de `supabase gen types typescript --local`; qualquer atualização de `database.types.ts` deve ser derivada dessa saída, nunca editada manualmente.

Rollback operacional significa impedir novos comandos da fase e preservar relatórios, versões, auditorias e hashes já produzidos. Não se apagam evidências nem se reabrem estados terminais por rollback de aplicação. Qualquer correção de migration deve ser aditiva, revisada e começar com `SET lock_timeout = '2s';`; migrations F9–F11 permanecem byte a byte inalteradas.

Critérios de parada: falha de parser ou reset; divergência entre reset e upgrade; D-022 inconsistente; bypass de RLS/grant; auditoria fora da transação; geração parcial em prova histórica ausente; hash não reprodutível; mistura de falha com `unchanged`; vazamento de payload/segredo; teste E2E não isolado; tipos gerados divergentes; tentativa de usar processo, credencial, provider ou endpoint real; ou qualquer demanda por PDF, envio, scheduler, fila, worker, produção, piloto ou IA.

O plano considera a skill `impeccable` indisponível no ambiente; ela não é instalada nem necessária para a entrega técnica. Nenhuma ferramenta de produção persistente, scheduler, fila ou worker novo é criada nesta fase.
