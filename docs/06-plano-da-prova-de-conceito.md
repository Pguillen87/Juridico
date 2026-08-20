# Plano da Prova de Conceito

## Objetivo e Limites

A PoC validará os fluxos críticos antes da importação integral da carteira. Ela utilizará de cinco a dez processos públicos reais somente após o usuário fornecer e aprovar explicitamente os números CNJ. Não serão usados números inventados. A PoC não será executada nesta etapa de auditoria.

O fuso de operação será inicialmente `America/Sao_Paulo`, com horários provisórios de consulta 08:00, 13:00 e 18:00. Os resultados serão armazenados com timestamps UTC e apresentados no fuso operacional.

## Preparação e Autorizações

Antes da execução, o advogado deverá confirmar que cada processo é público, fornecer número CNJ, tribunal e contexto mínimo, aprovar a consulta e indicar destinatário de teste. Credenciais externas, se necessárias, deverão ser configuradas fora do código e nunca serão incluídas em payloads, logs ou relatórios.

O ambiente será homologação, com storage privado, adaptador de e-mail falso ou sandbox e dados de teste separados. A PoC real poderá ser interrompida por limite, indisponibilidade, sigilo, mudança de contrato ou ausência de autorização.

## Grupo A — Testes com DataJud Real

Para cada processo aprovado, executar uma consulta baseline e registrar provider, data, resposta HTTP, campos recebidos, movimentos, snapshot, hash, alteração, falha e resultado. Confirmar que payload bruto sanitizado e snapshot são imutáveis, que partes ausentes são tratadas como capacidade não fornecida e que o resultado aparece com a fonte correta.

O baseline não deve gerar alerta de alteração. Uma consulta subsequente somente poderá gerar evento se houver diferença material evidenciada. Os números CNJ não deverão aparecer integralmente em relatório de auditoria quando o mascaramento for necessário.

## Grupo B — Testes com Dados Simulados

Usar fixtures controladas para respostas completas, respostas sem partes, movimentações fora de ordem, alteração de status, correção retroativa, schema inesperado e primeiro snapshot. Validar normalização, canonicalização, hash, comparação e transição de estados sem consultar tribunal.

Critérios de sucesso: mesma entrada gera mesmo hash; campos opcionais ausentes não são inventados; baseline não alerta; alteração material gera `detected_change`; alteração irrelevante não cria falso positivo; nenhum conteúdo de IA altera dados oficiais.

## Grupo C — Testes de Indisponibilidade

Simular timeout, HTTP 429, HTTP 5xx, falha de DNS, resposta vazia e provider não suportado. Confirmar retries limitados com backoff, liberação de lock, classificação como `timeout`, `rate_limited`, `source_unavailable`, `technical_failure` ou `not_supported`, e encaminhamento à central de falhas.

Critério obrigatório: nenhuma dessas situações pode gerar `unchanged` ou ser descrita como “sem movimentação”. O reprocessamento deverá ser manual e auditável após o limite de tentativas.

## Grupo D — Testes de Deduplicação

Reenviar o mesmo payload, executar o mesmo job duas vezes, repetir alteração e repetir notificação para o mesmo destinatário. Validar as chaves:

- Consulta: `office_id + process_id + scheduled_window_utc + provider_id`.
- Alteração: `process_id + previous_snapshot_hash + new_snapshot_hash + change_fingerprint`.
- Notificação: `detected_change_id + recipient + channel + template_version`.

Critério de sucesso: nenhuma movimentação, alteração ou notificação material é duplicada; tentativas distintas permanecem registradas sem sobrescrever evidência.

## Grupo E — Testes de Relatório

Gerar rascunho para período controlado, organizar por processo e por parte, incluir alteração, ausência de alteração, falha, não encontrado e não suportado. Editar observação, criar nova versão, aprovar e verificar que somente a versão aprovada pode gerar PDF e envio.

Testar também período vazio, falha no período, mudança posterior ao fechamento e tentativa de editar versão aprovada. O relatório nunca poderá omitir o motivo de uma falha nem convertê-la em ausência de movimentação.

## Grupo F — Testes de E-mail em Sandbox

Usar adaptador falso ou sandbox. Confirmar destinatário, assunto, conteúdo, fonte, data, processo, partes, link, versão, hash do PDF e resposta sanitizada. Simular sucesso, bounce, timeout, provider indisponível, retry e destinatário inválido.

Critério obrigatório: não enviar relatório sem aprovação; não enviar artefato diferente da versão aprovada; preservar `email_delivery` e cópia imutável privada; não expor credenciais ou dados desnecessários.

## Ficha de Resultado por Processo

Uma ficha deverá ser preenchida para cada processo aprovado:

| Campo | Resultado |
|---|---|
| Identificador CNJ mascarado quando necessário | A preencher na PoC |
| Tribunal | A preencher na PoC |
| Processo público confirmado | Sim/Não, com evidência |
| Autorização do usuário | Data e responsável |
| Data da consulta | UTC e apresentação local |
| Provider | DataJud ou ManualProvider |
| Resposta HTTP | Código ou não aplicável |
| Campos recebidos | Lista objetiva |
| Movimentos recebidos | Quantidade e hashes |
| Snapshot criado | Sim/Não e ID interno |
| Hash criado | Valor interno mascarado quando necessário |
| Alteração detectada | Sim/Não e fingerprint |
| Falha encontrada | Estado padronizado ou “nenhuma” |
| Notificação criada | Sim/Não e chave |
| Relatório incluído | Processo/parte/ambos |
| Resultado | Aprovado/Reprovado |
| Observações | Evidências e pendências |

## Critérios de Aprovação da PoC

A PoC será aprovada somente se os testes cobrirem sucesso, ausência real de alteração, todos os estados de falha, deduplicação, revisão, aprovação, PDF e sandbox. Deverá existir evidência por processo, nenhum segredo exposto, nenhum acesso sigiloso, nenhum envio não aprovado e nenhuma classificação de falha como “sem movimentação”.

A execução real permanece bloqueada até o fornecimento e aprovação dos CNJs, definição do ambiente e autorização explícita do usuário.
