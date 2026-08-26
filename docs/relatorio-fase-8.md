# Relatório factual — Fase 8: DataJud e Provedor Manual

## 1. Identificação e baseline

A implementação foi realizada em workspace isolado, na branch `phase-8-datajud-manual`, derivada exclusivamente do HEAD final aprovado da Fase 7: `7cf007aed354b95efc1af547e0490be3bc7d0880`, branch `phase-7-provider-abstraction`. A branch `main` não foi usada como baseline nem modificada.

A Fase 8 foi deliberadamente limitada a **sandbox sintético**. Não foram usados processo real, número CNJ real, credencial real, chamada real ao DataJud, provider pago, processo sigiloso, produção, piloto, scheduler, fila, worker, snapshot ou comparação.

## 2. Resultado funcional

O pacote de providers agora possui um `DataJudProvider` com transporte fake injetável. O adapter classifica respostas sintéticas em observação normalizada ou falha explícita, preservando o contrato `ProviderContractV1`. Os estados `changed` e `unchanged` não aparecem no resultado; permanecem reservados para a camada de comparação da Fase 10.

A classificação cobre `not_found`, `not_supported`, `source_unavailable`, `technical_failure`, timeout, rate limit HTTP 429, respostas 5xx, falhas de rede/DNS, schema inválido, payload excessivo e divergência de `processRef`. Mensagens de erro são sanitizadas e a política de retry é determinada pelo status allowlisted.

O transporte real está desabilitado por configuração. A configuração registra somente `credentialState = absent|present`, nunca o valor da credencial. Mesmo quando endpoint e credencial sintéticos estão presentes, o modo real retorna `disabled`; nenhum código de rede externa foi autorizado ou executado.

## 3. Proteções de processo e tenant

Antes de qualquer execução do transporte, o writer server-only chama `require_provider_process_eligible`. O banco verifica que o processo existe, pertence ao escritório do usuário autenticado, está ativo e possui `is_public = true`. Processo sigiloso ou inelegível é rejeitado antes da consulta e antes da persistência.

A RPC repete a proteção no mesmo fluxo transacional, deriva ator e escritório de `auth.uid()` e não aceita `office_id`, role, `is_owner` ou actor fornecidos pelo browser. O writer aceita somente o provider DataJud sandbox autorizado; a tentativa de usar `manual_observation` nessa RPC é rejeitada.

## 4. Persistência privada e auditoria

Foi criada a migration incremental `20260826000009_phase_8_provider_payload.sql`, com as tabelas `provider_exchange` e `raw_provider_payload`. A troca persiste o contrato, status, código de erro, fingerprint de request, correlação, processo e escritório. O payload bruto é opcional e representa somente o payload sanitizado, não o body original recebido do transporte.

O sanitizador remove chaves sensíveis, rejeita valores com aparência de segredo, limita profundidade, quantidade de chaves e tamanho serializado, e calcula SHA-256 do JSON canônico. A tabela mantém `payload_hash`, `payload_bytes`, versão de sanitização e relação explícita com troca, processo e escritório. Triggers impedem alteração ou exclusão física; a política efetiva é append-only.

O acesso direto de `authenticated`, `anon` e `PUBLIC` a INSERT, UPDATE e DELETE é revogado. SELECT de troca depende de RLS; payload bruto não é selecionável diretamente. A leitura bruta ocorre somente pela RPC protegida para advogado ativo do mesmo escritório. Operador, reviewer, auditor e owner sem role de advogado não recebem acesso operacional ao payload bruto.

A RPC grava troca, payload e eventos `provider.exchange.recorded`/`provider.payload.recorded` no mesmo contexto transacional. Se a auditoria falha, toda a mutação é revertida. O helper `write_provider_audit` é fechado, allowlisted e sem EXECUTE direto para usuários autenticados.

A idempotência é garantida pela combinação de escritório, processo, provider, correlação e fingerprint. Replay idêntico devolve a troca existente sem duplicar payload ou auditoria; conflito de correlação com conteúdo diferente é rejeitado.

## 5. ManualProvider e D-022

O `ManualProvider` continua limitado à observação sintética já aprovada e mantém a validação exata de `processRef`. A matriz canônica D-022 possui `manual_reprocess` para `lawyer` e `operator`, mas não possui a ação `manual_provider_entry`. Reprocessamento manual não foi interpretado como autorização equivalente para entrada operacional de resultado.

Por isso, a entrada manual operacional permanece bloqueada nesta Fase 8. Nenhuma role foi inventada, nenhuma Server Action foi criada para gravar resultado manual e nenhuma permissão foi ampliada. A continuação desse fluxo depende de decisão humana explícita e de atualização aprovada da D-022.

## 6. Testes e gates executados

A validação local do workspace isolado passou nos seguintes gates:

| Gate | Resultado |
|---|---|
| `npm ci` | Passou |
| TypeScript | Passou |
| ESLint | Passou sem warnings pendentes nos arquivos da Fase 8 |
| Prettier | Passou |
| Vitest | 95 testes em 16 arquivos, todos passaram |
| Next build | Passou com Next.js 16.3.1 |
| Supabase DB lint | Passou sem erros de schema |
| pgTAP da Fase 8 | 36 assertions, todas passaram |
| Regressão pgTAP 01–10 | Arquivos executados individualmente e todos passaram |
| Conferência de grants/RLS/atomicidade | Coberta no teste pgTAP da Fase 8 |
| Conferência de segredo | Coberta por testes do sanitizador/configuração e assertions SQL |

O runner agrupado de todos os arquivos pgTAP apresentou comportamento de espera no ambiente temporário; para não mascarar resultado, os arquivos legados e o arquivo da Fase 8 foram executados individualmente. Os testes concluídos individualmente passaram, incluindo os testes históricos 01 a 10 e a nova suíte 11.

## 7. CI, rollback e parada

O allowlist de push do App CI foi atualizado para incluir `phase-8-datajud-manual`. A migration é incremental e não altera migrations publicadas das Fases 5 ou 6. Rollback operacional consiste em impedir chamadas ao writer, desabilitar o modo de transporte e reverter a migration somente mediante migration reversa revisada; não há chamadas externas para interromper nem dados reais para remover nesta fase.

A Fase 8 deve parar imediatamente antes de qualquer tentativa de: usar credencial real; consultar DataJud real; consultar processo ou carteira real; acessar processo sigiloso; ativar produção ou piloto; criar scheduler, fila, worker ou snapshot; implementar comparação; ou autorizar entrada manual sem ação explícita da D-022.

## 8. Pendências para fases seguintes

A Fase 9 permanece responsável por `query_job`, `query_execution`, scheduler, fila, worker, retries de job e snapshots. A Fase 10 permanece responsável pela comparação e pelos estados `changed`/`unchanged`. A retenção definitiva, política LGPD e eventual migração de payload para storage privado dedicado devem ser revisadas antes de operação com dados reais.
