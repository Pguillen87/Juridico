# Relatório da Fase 5 — Clientes, Partes e Relações

## Resumo

A Fase 5 implementa `party`, `client` e `client_related_party` como dados operacionais isolados por office. O acesso segue D-022: lawyer e operator executam as mutações autorizadas; reviewer possui leitura; auditor não acessa dados operacionais. Não há confirmação automática de identidade por nome e não há armazenamento de CPF/CNPJ completo.

## Migrations aplicadas

Além da fundação 00001, foram aplicadas as migrations incrementais 00002 (hardening RLS/grants/vocabulary/invariants), 00003 (compatibilidade do validator Phase 5 com a auditoria 4C e grants mínimos), 00004 (correção de `TG_OP` no trigger de invariantes) e 00005 (execução `SECURITY DEFINER` do trigger para que RPCs protegidas não dependam de DML direto do role autenticado). A 00001 e as migrations da Fase 4C permanecem inalteradas.

## Segurança e integridade

SELECT é protegido por RLS. INSERT, UPDATE e soft-delete são exclusivos das RPCs de domínio. DML direto em `party`, `client` e `client_related_party` é negado para `authenticated`, `anon` e `PUBLIC`; DELETE físico não é utilizado. As RPCs usam `SECURITY DEFINER`, `search_path` fixo, actor/office/role derivados no banco e validação de tenant/estado.

A auditoria operacional ocorre dentro da mesma transação da mutação. O teste controlado de rollback provocou falha no audit insert e confirmou que a alteração de domínio e qualquer audit parcial foram revertidos. A auditoria administrativa 4C continua combinada na RPC `export_administrative_audit`, preservando autorização, bucket `admin.audit_export`, evento `audit.export` e retorno do CSV.

## Checklist factual das RPCs

| RPC física | D-022 e contexto | Target/tenant e estado | Mutação + audit atômico | Resultado |
|---|---|---|---|---|
| `create_party` | Actor ativo; lawyer/operator | Office derivado; dados básicos validados | Cria party e registra audit na mesma transação | Implementada/testada |
| `update_party` | Actor ativo; lawyer/operator | Target no office e status validado | Atualiza e audita na mesma transação | Implementada/testada |
| `deactivate_party` | Actor ativo; lawyer/operator | Bloqueia client/relação ativa | Soft-delete e audit na mesma transação | Implementada/testada |
| `create_client` | Actor ativo; lawyer/operator | Party ativa no mesmo office | Cria client e audita na mesma transação | Implementada/testada |
| `update_client` | Actor ativo; lawyer/operator | Target no office | Atualiza e audita na mesma transação | Implementada/testada |
| `deactivate_client` | Actor ativo; lawyer/operator | Bloqueia relação ativa | Soft-delete e audit na mesma transação | Implementada/testada |
| `create_client_related_party` | Actor ativo; lawyer/operator | Client e party ativos no mesmo office; unique parcial | Cria relação e audita na mesma transação | Implementada/testada |
| `confirm_client_related_party` | Somente lawyer | Relação no office; somente `pending` | Transição terminal e audit na mesma transação | Implementada/testada |
| `reject_client_related_party` | Somente lawyer | Relação no office; somente `pending` | Transição terminal e audit na mesma transação | Implementada/testada |
| `deactivate_client_related_party` | Actor ativo; lawyer/operator | Relação no office | Soft-delete e audit na mesma transação | Implementada/testada |

Nenhuma RPC recebe actor, office, role ou `is_owner` confiável do browser. O DML direto permanece negado e não há uso de `service_role` no browser.

## Concorrência e duplicidade

O teste real confirm-versus-reject executou `attempts=2`, com `success=1`, `rejected=1`, `terminal_audits=1`. O estado final foi `confirmed`, com `confirmed_by` coerente e uma única auditoria terminal. A operação perdedora recebeu `invalid transition` e não gravou audit terminal falso.

A chave de duplicidade usa IDs de office, client, party e relation type, não nome. Relações ativas equivalentes são rejeitadas. Homônimos podem existir como parties distintas. Relações inativas preservam histórico; o comportamento de nova relação após inativação segue a constraint e a RPC vigentes.

## Evidências de regressão

| Suite/gate | Evidência |
|---|---:|
| Unitários | 51 aprovados |
| pgTAP | 159 testes, 0 falhas, 8 arquivos |
| Playwright autenticado | 21 aprovados: 16 da 4C e 5 da Fase 5 |
| PoC DataJud | 29 aprovados |
| Last-owner | 1 sucesso, 1 rejeição, 1 owner ativo |
| Rate limit administrativo | 5 permitidos, 1 bloqueado, contador final 5 |
| Docker | Build e execução aprovados; health HTTP 200; runtime `nextjs` não-root |
| Qualidade | format check, lint, typecheck e build aprovados |

A configuração Playwright usa um worker e execução não paralela porque fixtures autenticadas compartilham estado de rate limit. A concorrência de domínio foi verificada separadamente no PostgreSQL, não mascarada pela configuração E2E.

## Evidências funcionais da UI

A página `/app/clientes` agora lista clientes, parties do office e vínculos relacionados. A UI apresenta referência curta derivada do ID, `party_type` e status para distinguir homônimos sem usar nome como identidade. O fluxo de lawyer cria cliente e party, escolhe explicitamente uma party por ID, cria a relação em `pending`, confirma uma relação e rejeita outra; os estados `confirmed` e `rejected` permanecem visíveis. Operator consegue criar relação, mas não recebe controles de confirmação/rejeição. Reviewer permanece em leitura e auditor não acessa o fluxo operacional. O E2E real da Fase 5 cobre esses fluxos, além da separação de parties homônimas.

## Rastreabilidade

US-004 e US-005 estão implementadas e testadas. A confirmação/rejeição de `client_related_party` está implementada e testada na Fase 5. US-009 e US-010, dependentes de `process_party`, estão `DEFERRED` para a Fase 6. `legal_process` e `process_party` não foram criados.

## Production Stack

A revisão local cobriu segurança, PostgreSQL, Docker e revisão de código. Não foram identificados achados Critical/High adicionais dentro do escopo da Fase 5. Itens fora do escopo permanecem documentados para fases posteriores.

## Estado de publicação

Este relatório não contém SHA final nem Run ID. A publicação ocorreu somente após a regressão final completa e a higiene do working tree. A Fase 6 não foi iniciada.
