# Plano da Fase 5 — Clientes, Partes e Relações

## Objetivo

Implementar um registro multi-tenant de `party`, `client` e `client_related_party`, com isolamento por `office_id`, autorização D-022, mutações exclusivamente por RPCs de domínio e auditoria operacional atômica.

## Decisões aprovadas

A Fase 5 usa a alternativa B. `party` pertence diretamente a um office e não é compartilhada entre offices. Não há armazenamento de CPF/CNPJ completo nem `document_reference`. `confirmation_status` usa `pending`, `confirmed` e `rejected`; uma relação terminal não retorna silenciosamente a `pending`. `client` e `party` usam `active`/`inactive`. `process_party` e `legal_process` ficam diferidos para a Fase 6.

## Modelo de acesso

A leitura das tabelas operacionais ocorre somente quando permitida por RLS. INSERT, UPDATE e soft-delete são executados somente por RPCs específicas de domínio. DML direto nas tabelas base é revogado para `authenticated`, `anon` e `PUBLIC`; DELETE físico é negado. RPCs mutacionais são `SECURITY DEFINER`, usam `search_path` fixo, derivam actor, office e role no banco e revalidam D-022. Nenhum `office_id`, actor, role, `is_owner` ou metadata de autorização enviado pelo navegador é confiado.

## Migrations

| Migration | Finalidade |
|---|---|
| `20260825000001` | Fundação publicada de party, client, client_related_party e RPCs iniciais. |
| `20260825000002` | Hardening de RLS, grants, vocabulary de relação e invariantes de domínio. |
| `20260825000003` | Compatibilidade do validator Phase 5 com a auditoria administrativa 4C e grants mínimos das policies. |
| `20260825000004` | Correção do trigger de invariantes para tratar `TG_OP` corretamente e não acessar `OLD`/`NEW` inválidos. |
| `20260825000005` | Execução `SECURITY DEFINER` do trigger de invariantes, necessária para RPCs protegidas sem DML direto ao role autenticado. |

As migrations da Fase 4C e a 00001 permanecem preservadas.

## Auditoria e concorrência

Cada RPC mutacional executa domínio e audit insert na mesma transação. Falha de auditoria produz rollback integral. O helper de auditoria é fechado, allowlisted e não aceita metadata arbitrária. Confirmação/rejeição usa transição protegida no PostgreSQL; em concorrência confirm-versus-reject há um vencedor, uma rejeição e um único audit terminal.

## Escopo diferido

`process_party`, `legal_process`, ingestão de processos e `process_party` confirmation não pertencem à Fase 5 e serão tratados somente na Fase 6.
