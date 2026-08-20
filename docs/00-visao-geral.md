# Visão Geral do Projeto

## Visão Geral

O **Juridico** será uma aplicação web hospedada para monitorar uma carteira inicial de aproximadamente 60 processos judiciais. O sistema substituirá a rotina de abrir cada processo manualmente por consultas programadas, registro de respostas, normalização, snapshots, comparação, detecção de alterações, alertas e relatório semanal com aprovação humana.

O produto precisa representar com clareza a cliente principal, suas três filhas e quaisquer outras partes relacionadas aos processos. O modelo comum de partes abrangerá pessoas físicas, pessoas jurídicas, clientes, filhas, familiares, representantes e demais participantes. Cada vínculo deverá registrar papel no processo, origem, confirmação e auditoria.

## Objetivos do Negócio

O produto deverá reduzir o trabalho repetitivo de acompanhamento, diminuir o risco de uma movimentação relevante não ser percebida, dar rastreabilidade às informações utilizadas no relacionamento com o cliente e produzir um relatório semanal operacionalmente confiável. O MVP será validado antes da importação integral da carteira.

A operação inicial usará a API Pública do DataJud e um provedor manual para exceções. A arquitetura deverá acomodar novos provedores e canais sem permitir scraping não autorizado, bypass de CAPTCHA, login automatizado sem autorização ou acesso a processo sigiloso fora de uma integração aprovada.

## Princípios Fundamentais

1. **Rastreabilidade:** toda informação deverá indicar fonte, consulta, timestamp, estado e evidência.
2. **Separação de estados:** falha, indisponibilidade, não encontrado e não suportado não são ausência de movimentação.
3. **Controle humano:** vínculos, rascunhos de IA, relatórios e envios exigem revisão ou aprovação apropriada.
4. **Determinismo:** consulta oficial, normalização, comparação e deduplicação não dependerão de IA.
5. **Privacidade e isolamento:** os dados serão isolados por escritório e tratados com controles compatíveis com LGPD.
6. **Recuperação:** consultas e notificações serão idempotentes, reprocessáveis e observáveis.

## Decisões Provisórias

| Item                            | Valor inicial                                                                                    | Estado e validação                           |
| ------------------------------- | ------------------------------------------------------------------------------------------------ | -------------------------------------------- |
| Stack                           | Next.js, TypeScript, Supabase/PostgreSQL, Supabase Auth, RLS, Tailwind, Zod, Vitest e Playwright | `proposed`; aprovação do usuário             |
| Fuso operacional                | `America/Sao_Paulo`                                                                              | `proposed`; validação do advogado            |
| Consultas                       | 08:00, 13:00 e 18:00                                                                             | `proposed`; validação do advogado            |
| Fechamento semanal              | Sexta-feira às 17:00                                                                             | `proposed`; validação do advogado            |
| Alertas                         | E-mail                                                                                           | `proposed`; aprovação do usuário             |
| Fornecedor de e-mail            | Interface abstrata                                                                               | `deferred`; contratação e credencial externa |
| Ambiente de testes              | Adaptador falso ou sandbox                                                                       | `proposed`; validação técnica                |
| Retenção de respostas brutas    | 180 dias inicialmente                                                                            | `proposed`; validação jurídica               |
| Relatórios enviados e auditoria | Sem exclusão automática até decisão jurídica                                                     | `proposed`; validação jurídica               |
| Processos sigilosos             | Sem consulta automática no MVP                                                                   | `rejected` para o escopo atual               |

## Escopo do MVP

O MVP compreenderá autenticação, recuperação de senha, um escritório, usuários básicos, cadastro de clientes e partes, importação CSV, cadastro manual de processos, validação CNJ, vínculos processuais, DataJud, provedor manual, monitoramento agendado, snapshots, comparação, deduplicação, detecção, alertas por e-mail, central de falhas, reprocessamento, relatório semanal, revisão, aprovação, PDF, envio, cópia imutável, auditoria, RLS, testes e documentação operacional.

O MVP não compreenderá portal do cliente, aplicativo nativo, cobrança de múltiplos escritórios, WhatsApp, SMS, peticionamento, assinatura digital, login automatizado em tribunais, CAPTCHA, scraping não autorizado, acesso automático a processos sigilosos, parecer jurídico, cálculo de prazos ou confirmação automática de partes por semelhança de nome.

## Regra Operacional Invariável

> Uma consulta que falhou nunca poderá ser apresentada como “processo sem movimentação”.

Os estados mínimos são: alteração detectada, consulta sem alteração, fonte indisponível, processo não encontrado, processo não suportado, limite de requisições, timeout, falha técnica e revisão manual necessária. O relatório deverá manter esses estados visíveis e separados.

## Situação Atual

O projeto não possui código nem configuração de aplicação. Esta etapa produz documentação e um `DESIGN.md` seed manual; nenhuma implementação funcional foi iniciada. Os números CNJ da PoC ainda não foram fornecidos ou aprovados.
