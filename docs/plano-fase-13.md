# Plano técnico — Fase 13: Entrega privada de PDF

## 1. Baseline, branch e objetivo

A Fase 13 é trabalhada na branch `phase-13-pdf-delivery`, sobre o domínio de relatórios da Fase 12. O objetivo deste recorte é implementar, documentar e proteger por CI a entrega privada de um PDF aprovado, mantendo provider, e-mail e storage remoto fora deste recorte.

| Item | Decisão/limite |
|---|---|
| Branch | `phase-13-pdf-delivery` |
| Escopo documentado | artefato PDF privado, contatos confirmados, autorização de envio e estados/retentativas |
| Fonte de autoridade | relatório e versão aprovados, hash persistido e objeto privado local |
| Gates | histórico 00005/00006/00007 e upgrade F12→F13 |
| Fora do escopo | provider real, e-mail real, storage remoto, produção, staging e retenção |

## 2. Implementação atual

A migration aditiva `20260827000007_phase_13_pdf_delivery.sql` começa literalmente com `SET lock_timeout = '2s';`. Ela cria o bucket privado local `private-reports` e as tabelas `client_contact`, `report_artifact`, `email_delivery`, `email_delivery_attempt` e `email_delivery_retry_command`. Os artefatos carregam hash aprovado, hash do arquivo, fingerprint de geração, tamanho e URI privada; a URI aceita somente o formato `private://private-reports/...`.

As funções `phase13_*` revalidam no banco o actor `lawyer`, o escritório e o estado aprovado do relatório. A criação do artefato exige objeto já presente no storage privado e é idempotente por fingerprint. O envio é apenas autorizado/registrado no domínio: exige contato ativo e confirmado, copia hashes e URI imutáveis, usa chave de idempotência e separa `pending`, `processing`, `delivered`, `retry_available`, `failed` e `unknown_outcome`. Claims de tentativa são exclusivos de `service_role`; reconciliação e retry são explícitos.

`src/lib/reports/pdf-renderer.ts` valida magic bytes `%PDF-`, SHA-256, hash aprovado, tamanho máximo e invariantes de snapshot. O renderer Playwright usa Chromium já instalado, sem provisionar browser ou rede. `src/lib/delivery/email-provider.ts` expõe somente o contrato e `FakeEmailProvider`, com respostas sintéticas e resultado `unknown_outcome` não convertido silenciosamente em falha.

## 3. Segurança, imutabilidade e auditoria

As tabelas F13 têm RLS, DML direto revogado e leitura browser bloqueada. Triggers impedem mutação física de artefatos, identidade de deliveries e exclusão de tentativas. RPCs usam `SECURITY DEFINER`, `search_path` fixo, allowlists de campos e auditoria atômica em `audit_log`; respostas de provider são explicitamente sanitizadas. A aprovação da F12 continua sendo pré-condição: gerar PDF não aprova relatório e autorizar envio não significa que o e-mail foi entregue.

## 4. Validação e CI

`check-phase13-migration-history.sh` confirma os blobs aprovados de 00005 (`c8f13774c0707d8502c6348283f2adf0e2673149`) e 00006 (`2b61ff7a1e857e5ee395a602dda20d83498e6720`), o primeiro comando da 00007 e a imutabilidade das migrations F9–F12. `test-phase13-migration-upgrade.sh` compara fingerprint completo, tipos gerados e pgTAP entre reset completo e upgrade incremental F12→00007.

O App CI preserva todos os gates existentes e adiciona os gates de histórico e upgrade F13. Não há gate de concorrência F13 neste recorte porque nenhum script de concorrência F13 existe.

## 5. Adiamentos explícitos

- **Provider real:** deferido; somente contrato/fake e funções backend existem.
- **E-mail real/SMTP:** deferido; não há credencial, transporte ou destinatário real.
- **Storage remoto:** deferido; o bucket é privado e local/sandbox.
- **Produção:** deferida; nenhuma evidência usa infraestrutura ou dados reais.
- **Staging:** deferido; não há ambiente, deploy ou configuração de staging.
- **Retenção/expurgo:** deferida; não há scheduler, política operacional ou exclusão automática de artefatos/auditoria.

Qualquer ativação desses itens exige decisão e documentação próprias, sem relaxar RLS, hashes, idempotência, auditoria ou imutabilidade.
